{
  "targets": [
    {
      "target_name": "n64cart",
      "sources": [
        "native/src/addon.cc",
        "native/src/cart.c",
        "native/vendor/romfs/romfs.c"
      ],
      "include_dirs": [
        "<!@(node -p \"require('node-addon-api').include\")",
        "native/src",
        "native/vendor/romfs"
      ],
      "defines": [
        "ROMFS_NO_INTERNAL_BUFFERS",
        "NAPI_VERSION=8"
      ],
      "conditions": [
        ["OS=='win'", {
          "sources": [
            "native/vendor/libusb/libusb/core.c",
            "native/vendor/libusb/libusb/descriptor.c",
            "native/vendor/libusb/libusb/hotplug.c",
            "native/vendor/libusb/libusb/io.c",
            "native/vendor/libusb/libusb/strerror.c",
            "native/vendor/libusb/libusb/sync.c",
            "native/vendor/libusb/libusb/os/events_windows.c",
            "native/vendor/libusb/libusb/os/threads_windows.c",
            "native/vendor/libusb/libusb/os/windows_common.c",
            "native/vendor/libusb/libusb/os/windows_usbdk.c",
            "native/vendor/libusb/libusb/os/windows_winusb.c"
          ],
          "include_dirs": [
            "native/vendor/libusb/libusb",
            "native/vendor/libusb/msvc"
          ],
          "defines": [
            "_CRT_SECURE_NO_WARNINGS"
          ],
          "msvs_settings": {
            "VCCLCompilerTool": {
              "ExceptionHandling": 1,
              "AdditionalOptions": [
                "/FI<(module_root_dir)/native/src/msvc_compat.h"
              ]
            }
          },
          "libraries": [
            "-ladvapi32",
            "-lole32",
            "-lsetupapi"
          ]
        }],
        ["OS=='linux'", {
          "cflags": ["<!@(pkg-config --cflags libusb-1.0)"],
          "cflags_cc": ["<!@(pkg-config --cflags libusb-1.0)", "-fexceptions"],
          "cflags_cc!": ["-fno-exceptions"],
          "libraries": ["<!@(pkg-config --libs libusb-1.0)"]
        }],
        ["OS=='mac'", {
          "cflags": ["<!@(pkg-config --cflags libusb-1.0)"],
          "xcode_settings": {
            "GCC_ENABLE_CPP_EXCEPTIONS": "YES",
            "OTHER_CFLAGS": ["<!@(pkg-config --cflags libusb-1.0)"],
            "OTHER_CPLUSPLUSFLAGS": ["<!@(pkg-config --cflags libusb-1.0)"],
            "MACOSX_DEPLOYMENT_TARGET": "11.0"
          },
          "libraries": ["<!@(pkg-config --libs libusb-1.0)"]
        }]
      ]
    }
  ]
}
