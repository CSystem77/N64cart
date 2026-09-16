
#include <napi.h>

#include <cstdio>
#include <functional>
#include <mutex>
#include <string>
#include <vector>

extern "C" {
#include "cart.h"
#include "romfs.h"
}

namespace {

std::mutex g_cart_mutex;

constexpr uint64_t kProgressStep = 512 * 1024;

struct Progress {
    uint64_t processed;
    uint64_t total;
};

using ProgressFn = std::function<void(uint64_t processed, uint64_t total)>;

class CartError : public std::exception {
  public:
    explicit CartError(std::string message) : message_(std::move(message)) {}
    const char *what() const noexcept override { return message_.c_str(); }

  private:
    std::string message_;
};

void Fail(const std::string &message) { throw CartError(message); }

void FailRomfs(const std::string &what, uint32_t err)
{
    Fail(what + ": " + romfs_strerror(err));
}

std::string NormalizePath(const std::string &path)
{
    if (path.empty()) {
        return "/";
    }
    std::string out = path;
    while (out.size() > 1 && out.back() == '/') {
        out.pop_back();
    }
    return out;
}

void WithSession(const std::function<void()> &body)
{
    char err[CART_ERR_LEN] = {0};
    if (!cart_session_begin(err)) {
        Fail(err[0] ? err : "Cannot open a cart session");
    }

    try {
        body();
    } catch (...) {
        cart_session_end(nullptr);
        throw;
    }

    if (!cart_session_end(err)) {
        Fail(err[0] ? err : "Cannot switch the flash back to quad mode");
    }
}

class CartWorker : public Napi::AsyncWorker {
  public:
    using Body = std::function<void(const ProgressFn &)>;
    using ResultFn = std::function<Napi::Value(Napi::Env)>;

    CartWorker(Napi::Env env, Body body, Napi::Function onProgress)
        : Napi::AsyncWorker(env), deferred_(Napi::Promise::Deferred::New(env)), body_(std::move(body))
    {
        if (!onProgress.IsEmpty()) {
            progress_ = Napi::ThreadSafeFunction::New(env, onProgress, "n64cartProgress", 0, 1);
            hasProgress_ = true;
        }
    }

    Napi::Promise Promise() { return deferred_.Promise(); }

    void SetResultFn(ResultFn fn) { result_ = std::move(fn); }

    void Execute() override
    {
        std::lock_guard<std::mutex> lock(g_cart_mutex);
        try {
            body_([this](uint64_t processed, uint64_t total) { EmitProgress(processed, total); });
        } catch (const std::exception &e) {
            SetError(e.what());
        }
    }

    void OnOK() override
    {
        ReleaseProgress();
        Napi::Env env = Env();
        Napi::HandleScope scope(env);
        deferred_.Resolve(result_ ? result_(env) : env.Undefined());
    }

    void OnError(const Napi::Error &error) override
    {
        ReleaseProgress();
        Napi::Env env = Env();
        Napi::HandleScope scope(env);
        deferred_.Reject(error.Value());
    }

  private:
    void EmitProgress(uint64_t processed, uint64_t total)
    {
        if (!hasProgress_) {
            return;
        }
        const bool done = (total > 0 && processed >= total);
        if (!done && processed - lastReported_ < kProgressStep) {
            return;
        }
        lastReported_ = processed;

        auto *payload = new Progress{processed, total};
        napi_status status = progress_.BlockingCall(payload, [](Napi::Env env, Napi::Function cb, Progress *data) {
            cb.Call({Napi::Number::New(env, static_cast<double>(data->processed)),
                     Napi::Number::New(env, static_cast<double>(data->total))});
            delete data;
        });
        if (status != napi_ok) {
            delete payload;
        }
    }

    void ReleaseProgress()
    {
        if (hasProgress_) {
            progress_.Release();
            hasProgress_ = false;
        }
    }

    Napi::Promise::Deferred deferred_;
    Body body_;
    ResultFn result_;
    Napi::ThreadSafeFunction progress_;
    bool hasProgress_ = false;
    uint64_t lastReported_ = 0;
};

Napi::Promise RunAsync(Napi::Env env, CartWorker::Body body, CartWorker::ResultFn result = nullptr,
                       Napi::Function onProgress = Napi::Function())
{
    auto *worker = new CartWorker(env, std::move(body), onProgress);
    if (result) {
        worker->SetResultFn(std::move(result));
    }
    Napi::Promise promise = worker->Promise();
    worker->Queue();
    return promise;
}

Napi::Object InfoToObject(Napi::Env env, const cart_info_t &info)
{
    Napi::Object out = Napi::Object::New(env);
    out.Set("firmwareVersion", Napi::String::New(env, std::to_string(info.vers >> 8) + "." +
                                                         std::to_string(info.vers & 0xff)));
    out.Set("romfsStart", Napi::Number::New(env, info.start));
    out.Set("romfsSize", Napi::Number::New(env, info.size));
    return out;
}

Napi::Value Connect(const Napi::CallbackInfo &cbInfo)
{
    Napi::Env env = cbInfo.Env();
    return RunAsync(
        env,
        [](const ProgressFn &) {
            char err[CART_ERR_LEN] = {0};
            if (!cart_connect(err)) {
                Fail(err[0] ? err : "Cannot connect to the cart");
            }
        },
        [](Napi::Env e) { return InfoToObject(e, *cart_info()); });
}

Napi::Value Disconnect(const Napi::CallbackInfo &cbInfo)
{
    return RunAsync(cbInfo.Env(), [](const ProgressFn &) { cart_disconnect(); });
}

Napi::Value IsConnected(const Napi::CallbackInfo &cbInfo)
{
    return Napi::Boolean::New(cbInfo.Env(), cart_connected());
}

Napi::Value Info(const Napi::CallbackInfo &cbInfo)
{
    Napi::Env env = cbInfo.Env();
    if (!cart_connected()) {
        return env.Null();
    }
    return InfoToObject(env, *cart_info());
}

struct ListedEntry {
    std::string name;
    bool isDirectory;
    uint32_t size;
    uint16_t mode;
    uint16_t type;
};

Napi::Value List(const Napi::CallbackInfo &cbInfo)
{
    Napi::Env env = cbInfo.Env();
    std::string path = NormalizePath(cbInfo[0].As<Napi::String>().Utf8Value());
    auto entries = std::make_shared<std::vector<ListedEntry>>();
    auto freeBytes = std::make_shared<uint32_t>(0);

    return RunAsync(
        env,
        [path, entries, freeBytes](const ProgressFn &) {
            WithSession([&] {
                romfs_dir dir;
                uint32_t err = (path == "/") ? romfs_dir_root(&dir) : romfs_dir_open_path(path.c_str(), &dir);
                if (err != ROMFS_NOERR) {
                    FailRomfs("Cannot open " + path, err);
                }

                romfs_file file = {};
                uint32_t listErr = romfs_list_dir(&file, true, &dir, true);
                if (listErr == ROMFS_NOERR) {
                    do {
                        ListedEntry entry;
                        entry.name = file.entry.name;
                        entry.isDirectory = (file.entry.attr.names.type == ROMFS_TYPE_DIR);
                        entry.size = entry.isDirectory ? 0 : file.entry.size;
                        entry.mode = file.entry.attr.names.mode;
                        entry.type = file.entry.attr.names.type;
                        entries->push_back(entry);
                    } while (romfs_list_dir(&file, false, &dir, true) == ROMFS_NOERR);
                } else if (listErr != ROMFS_ERR_NO_FREE_ENTRIES) {

                    FailRomfs("Cannot list " + path, listErr);
                }

                *freeBytes = romfs_free();
            });
        },
        [path, entries, freeBytes](Napi::Env e) {
            Napi::Array arr = Napi::Array::New(e, entries->size());
            for (size_t i = 0; i < entries->size(); i++) {
                const ListedEntry &src = (*entries)[i];
                Napi::Object item = Napi::Object::New(e);
                item.Set("name", Napi::String::New(e, src.name));
                item.Set("path", Napi::String::New(e, path == "/" ? "/" + src.name : path + "/" + src.name));
                item.Set("isDirectory", Napi::Boolean::New(e, src.isDirectory));
                item.Set("size", Napi::Number::New(e, src.size));
                item.Set("mode", Napi::Number::New(e, src.mode));
                item.Set("type", Napi::Number::New(e, src.type));
                arr.Set(i, item);
            }
            Napi::Object out = Napi::Object::New(e);
            out.Set("path", Napi::String::New(e, path));
            out.Set("entries", arr);
            out.Set("freeBytes", Napi::Number::New(e, *freeBytes));
            return out;
        });
}

Napi::Value FreeSpace(const Napi::CallbackInfo &cbInfo)
{
    Napi::Env env = cbInfo.Env();
    auto freeBytes = std::make_shared<uint32_t>(0);
    return RunAsync(
        env,
        [freeBytes](const ProgressFn &) {
            WithSession([&] { *freeBytes = romfs_free(); });
        },
        [freeBytes](Napi::Env e) { return Napi::Number::New(e, *freeBytes); });
}

Napi::Value Mkdir(const Napi::CallbackInfo &cbInfo)
{
    Napi::Env env = cbInfo.Env();
    std::string path = NormalizePath(cbInfo[0].As<Napi::String>().Utf8Value());
    return RunAsync(env, [path](const ProgressFn &) {
        WithSession([&] {
            romfs_dir created;
            uint32_t err = romfs_mkdir_path(path.c_str(), true, &created);
            if (err != ROMFS_NOERR) {
                FailRomfs("Cannot create " + path, err);
            }
        });
    });
}

Napi::Value Rmdir(const Napi::CallbackInfo &cbInfo)
{
    Napi::Env env = cbInfo.Env();
    std::string path = NormalizePath(cbInfo[0].As<Napi::String>().Utf8Value());
    return RunAsync(env, [path](const ProgressFn &) {
        WithSession([&] {
            uint32_t err = romfs_rmdir_path(path.c_str());
            if (err != ROMFS_NOERR) {
                FailRomfs("Cannot remove " + path, err);
            }
        });
    });
}

Napi::Value Unlink(const Napi::CallbackInfo &cbInfo)
{
    Napi::Env env = cbInfo.Env();
    std::string path = NormalizePath(cbInfo[0].As<Napi::String>().Utf8Value());
    return RunAsync(env, [path](const ProgressFn &) {
        WithSession([&] {
            uint32_t err = romfs_delete_path(path.c_str());
            if (err != ROMFS_NOERR) {
                FailRomfs("Cannot delete " + path, err);
            }
        });
    });
}

Napi::Value Rename(const Napi::CallbackInfo &cbInfo)
{
    Napi::Env env = cbInfo.Env();
    std::string from = NormalizePath(cbInfo[0].As<Napi::String>().Utf8Value());
    std::string to = NormalizePath(cbInfo[1].As<Napi::String>().Utf8Value());
    bool createDirs = cbInfo.Length() > 2 && cbInfo[2].ToBoolean().Value();
    return RunAsync(env, [from, to, createDirs](const ProgressFn &) {
        WithSession([&] {
            uint32_t err = romfs_rename_path(from.c_str(), to.c_str(), createDirs);
            if (err != ROMFS_NOERR) {
                FailRomfs("Cannot rename " + from, err);
            }
        });
    });
}

Napi::Value Format(const Napi::CallbackInfo &cbInfo)
{
    return RunAsync(cbInfo.Env(), [](const ProgressFn &) {
        WithSession([&] {
            if (!romfs_format()) {
                Fail("Format failed");
            }
        });
    });
}

void FixRomChunk(uint8_t *data, size_t length, int *romType)
{
    if (*romType == -1) {
        if (length < 4) {
            Fail("ROM file is too small");
        }
        if (data[0] == 0x80 && data[1] == 0x37 && data[2] == 0x12 && data[3] == 0x40) {
            *romType = 0;
        } else if (data[0] == 0x40 && data[1] == 0x12 && data[2] == 0x37 && data[3] == 0x80) {
            *romType = 1;
        } else if (data[0] == 0x37 && data[1] == 0x80 && data[2] == 0x40 && data[3] == 0x12) {
            *romType = 2;
        } else {
            Fail("Unknown ROM byte order");
        }
    }

    if (*romType == 0) {
        return;
    }
    if (length % 4 != 0) {
        Fail("Unaligned ROM data chunk");
    }

    for (size_t i = 0; i < length; i += 4) {
        if (*romType == 1) {
            std::swap(data[i + 0], data[i + 3]);
            std::swap(data[i + 1], data[i + 2]);
        } else {
            std::swap(data[i + 0], data[i + 1]);
            std::swap(data[i + 2], data[i + 3]);
        }
    }
}

Napi::Value Upload(const Napi::CallbackInfo &cbInfo)
{
    Napi::Env env = cbInfo.Env();
    std::string localPath = cbInfo[0].As<Napi::String>().Utf8Value();
    std::string remotePath = NormalizePath(cbInfo[1].As<Napi::String>().Utf8Value());

    bool fixRom = false;
    int piBusSpeed = -1;
    if (cbInfo.Length() > 2 && cbInfo[2].IsObject()) {
        Napi::Object options = cbInfo[2].As<Napi::Object>();
        if (options.Has("fixRom")) {
            fixRom = options.Get("fixRom").ToBoolean().Value();
        }
        if (options.Has("piBusSpeed") && options.Get("piBusSpeed").IsNumber()) {
            piBusSpeed = options.Get("piBusSpeed").As<Napi::Number>().Int32Value() & 0xff;
        }
    }
    Napi::Function onProgress;
    if (cbInfo.Length() > 3 && cbInfo[3].IsFunction()) {
        onProgress = cbInfo[3].As<Napi::Function>();
    }

    return RunAsync(
        env,
        [localPath, remotePath, fixRom, piBusSpeed](const ProgressFn &progress) {
            FILE *in = fopen(localPath.c_str(), "rb");
            if (!in) {
                Fail("Cannot open " + localPath);
            }
            fseek(in, 0, SEEK_END);
            const long fileSize = ftell(in);
            fseek(in, 0, SEEK_SET);

            try {
                WithSession([&] {
                    romfs_file file = {};
                    uint32_t err = romfs_create_path(remotePath.c_str(), &file, ROMFS_MODE_READWRITE, ROMFS_TYPE_MISC,
                                                     cart_io_buffer(), true);
                    if (err != ROMFS_NOERR) {
                        FailRomfs("Cannot create " + remotePath, err);
                    }

                    std::vector<uint8_t> buffer(ROMFS_FLASH_SECTOR);
                    int romType = -1;
                    bool patchPiBus = (piBusSpeed >= 0);
                    uint64_t total = 0;

                    while (true) {
                        size_t read = fread(buffer.data(), 1, buffer.size(), in);
                        if (read == 0) {
                            break;
                        }

                        if (fixRom) {
                            FixRomChunk(buffer.data(), read, &romType);
                        }

                        if (patchPiBus) {
                            if (read >= 4 && buffer[0] == 0x80 && buffer[1] == 0x37 && buffer[3] == 0x40) {
                                buffer[2] = static_cast<uint8_t>(piBusSpeed);
                                patchPiBus = false;
                            } else {
                                Fail("Setting the PI bus speed needs a z64 ROM (enable the ROM fix)");
                            }
                        }

                        if (romfs_write_file(buffer.data(), static_cast<uint32_t>(read), &file) == 0) {
                            break;
                        }
                        total += read;
                        progress(total, static_cast<uint64_t>(fileSize));
                    }

                    if (file.err != ROMFS_NOERR && file.err != ROMFS_ERR_EOF) {
                        uint32_t writeErr = file.err;
                        romfs_close_file(&file);
                        FailRomfs("Write failed", writeErr);
                    }

                    if (romfs_close_file(&file) != ROMFS_NOERR) {
                        Fail("Cannot close " + remotePath + " on the cart");
                    }
                    progress(static_cast<uint64_t>(fileSize), static_cast<uint64_t>(fileSize));
                });
            } catch (...) {
                fclose(in);
                throw;
            }
            fclose(in);
        },
        nullptr, onProgress);
}

Napi::Value Download(const Napi::CallbackInfo &cbInfo)
{
    Napi::Env env = cbInfo.Env();
    std::string remotePath = NormalizePath(cbInfo[0].As<Napi::String>().Utf8Value());
    std::string localPath = cbInfo[1].As<Napi::String>().Utf8Value();
    Napi::Function onProgress;
    if (cbInfo.Length() > 2 && cbInfo[2].IsFunction()) {
        onProgress = cbInfo[2].As<Napi::Function>();
    }

    return RunAsync(
        env,
        [remotePath, localPath](const ProgressFn &progress) {
            FILE *out = fopen(localPath.c_str(), "wb");
            if (!out) {
                Fail("Cannot write " + localPath);
            }

            try {
                WithSession([&] {
                    romfs_file file = {};
                    if (romfs_open_path(remotePath.c_str(), &file, cart_io_buffer()) != ROMFS_NOERR) {
                        FailRomfs("Cannot open " + remotePath, file.err);
                    }

                    std::vector<uint8_t> buffer(ROMFS_FLASH_SECTOR);
                    const uint64_t total = file.entry.size;
                    while (true) {
                        int read = romfs_read_file(buffer.data(), static_cast<uint32_t>(buffer.size()), &file);
                        if (read <= 0) {
                            break;
                        }
                        if (fwrite(buffer.data(), 1, static_cast<size_t>(read), out) != static_cast<size_t>(read)) {
                            romfs_close_file(&file);
                            Fail("Cannot write " + localPath);
                        }
                        progress(file.read_offset, total);
                    }

                    if (file.err != ROMFS_NOERR && file.err != ROMFS_ERR_EOF) {
                        uint32_t readErr = file.err;
                        romfs_close_file(&file);
                        FailRomfs("Read failed", readErr);
                    }
                    romfs_close_file(&file);
                    progress(total, total);
                });
            } catch (...) {
                fclose(out);
                remove(localPath.c_str());
                throw;
            }
            fclose(out);
        },
        nullptr, onProgress);
}

Napi::Value Reboot(const Napi::CallbackInfo &cbInfo)
{
    return RunAsync(cbInfo.Env(), [](const ProgressFn &) {
        char err[CART_ERR_LEN] = {0};
        if (!cart_reboot(err)) {
            Fail(err[0] ? err : "Reboot failed");
        }
    });
}

Napi::Value Bootloader(const Napi::CallbackInfo &cbInfo)
{
    return RunAsync(cbInfo.Env(), [](const ProgressFn &) {
        char err[CART_ERR_LEN] = {0};
        if (!cart_bootloader(err)) {
            Fail(err[0] ? err : "Cannot enter bootloader mode");
        }
    });
}

}

Napi::Object Init(Napi::Env env, Napi::Object exports)
{
    exports.Set("connect", Napi::Function::New(env, Connect));
    exports.Set("disconnect", Napi::Function::New(env, Disconnect));
    exports.Set("isConnected", Napi::Function::New(env, IsConnected));
    exports.Set("info", Napi::Function::New(env, Info));
    exports.Set("list", Napi::Function::New(env, List));
    exports.Set("freeSpace", Napi::Function::New(env, FreeSpace));
    exports.Set("mkdir", Napi::Function::New(env, Mkdir));
    exports.Set("rmdir", Napi::Function::New(env, Rmdir));
    exports.Set("unlink", Napi::Function::New(env, Unlink));
    exports.Set("rename", Napi::Function::New(env, Rename));
    exports.Set("format", Napi::Function::New(env, Format));
    exports.Set("upload", Napi::Function::New(env, Upload));
    exports.Set("download", Napi::Function::New(env, Download));
    exports.Set("reboot", Napi::Function::New(env, Reboot));
    exports.Set("bootloader", Napi::Function::New(env, Bootloader));
    return exports;
}

NODE_API_MODULE(n64cart, Init)
