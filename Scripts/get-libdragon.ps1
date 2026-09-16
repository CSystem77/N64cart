
[CmdletBinding()]
param(

    [string]$SdkRoot,

    [string]$Branch = "preview",

    [switch]$Force,

    [switch]$ToolchainOnly,

    [switch]$NoCompilerDownload
)

$ErrorActionPreference = "Stop"

$TOOLCHAIN_URL = "https://github.com/DragonMinded/libdragon/releases/download/toolchain-continuous-prerelease/gcc-toolchain-mips64-win64.zip"
$LIBDRAGON_GIT = "https://github.com/DragonMinded/libdragon.git"

$MINGW_URL = "https://github.com/brechtsanders/winlibs_mingw/releases/download/16.2.0posix-14.0.0-ucrt-r1/winlibs-x86_64-posix-seh-gcc-16.2.0-mingw-w64ucrt-14.0.0-r1.zip"

$BUSYBOX_URL = "https://frippery.org/files/busybox/busybox64.exe"

function Fail($msg) {
    Write-Host ""
    Write-Host "ERREUR : $msg" -ForegroundColor Red
    exit 1
}

function Remove-Tree([string]$path) {
    if (-not (Test-Path $path)) { return }
    Get-ChildItem -LiteralPath $path -Recurse -Force -ErrorAction SilentlyContinue |
        ForEach-Object { try { $_.Attributes = [System.IO.FileAttributes]::Normal } catch {} }
    for ($attempt = 1; $attempt -le 5; $attempt++) {
        try {
            [System.IO.Directory]::Delete($path, $true)
            return
        } catch {
            if ($attempt -eq 5) { Fail "Impossible de supprimer $path : $($_.Exception.Message)" }
            Start-Sleep -Seconds $attempt
        }
    }
}

Write-Host "=== Installation de libdragon ===" -ForegroundColor Cyan

if (-not $SdkRoot) {
    $SdkRoot = Join-Path (Split-Path $PSScriptRoot -Parent) "SDK"
}
New-Item -ItemType Directory -Force -Path $SdkRoot | Out-Null
$SdkRoot = (Resolve-Path $SdkRoot).Path

$prefix = Join-Path $SdkRoot "libdragon"
$sources = Join-Path $SdkRoot "libdragon-src"
$cache = Join-Path $SdkRoot ".cache"
New-Item -ItemType Directory -Force -Path $cache | Out-Null

Write-Host "Prefixe   : $prefix"
Write-Host "Sources   : $sources"
Write-Host "Branche   : $Branch"

$gitExe = (Get-Command git -ErrorAction SilentlyContinue).Source

$tarExe = Join-Path $env:SystemRoot "System32\tar.exe"
if (-not (Test-Path $tarExe)) { Fail "tar.exe est introuvable (fourni avec Windows 10 1803 et plus recent)." }

Write-Host ""
Write-Host "--- toolchain mips64-elf ---" -ForegroundColor Cyan

$gccPath = Join-Path $prefix "bin\mips64-elf-gcc.exe"
if ((Test-Path $gccPath) -and -not $Force) {
    Write-Host "  deja presente : $prefix" -ForegroundColor Green
} else {
    $archive = Join-Path $cache "gcc-toolchain-mips64-win64.zip"
    if (-not (Test-Path $archive) -or $Force) {
        Write-Host "  telechargement (~96 Mo)"
        & curl.exe -L --fail --retry 5 --retry-all-errors --retry-delay 2 --connect-timeout 30 `
            --progress-bar -o $archive $TOOLCHAIN_URL
        if ($LASTEXITCODE -ne 0) { Fail "Telechargement de la toolchain echoue." }
    } else {
        Write-Host "  archive deja en cache"
    }

    Write-Host "  extraction vers $prefix"

    New-Item -ItemType Directory -Force -Path $prefix | Out-Null
    & $tarExe -xf $archive -C $prefix
    if ($LASTEXITCODE -ne 0) { Fail "Extraction de la toolchain echouee." }
    if (-not (Test-Path $gccPath)) { Fail "mips64-elf-gcc.exe est absent apres extraction." }
    Write-Host "  installee" -ForegroundColor Green
}

Write-Host ""
Write-Host "--- sources libdragon ($Branch) ---" -ForegroundColor Cyan

if ((Test-Path (Join-Path $sources "Makefile")) -and -not $Force) {
    Write-Host "  deja presentes"
    if ($gitExe -and (Test-Path (Join-Path $sources ".git"))) {
        & $gitExe -C $sources fetch --depth 1 origin $Branch
        if ($LASTEXITCODE -eq 0) { & $gitExe -C $sources checkout -q FETCH_HEAD }
    }
} elseif ($gitExe) {
    Remove-Tree $sources
    & $gitExe clone --depth 1 --branch $Branch $LIBDRAGON_GIT $sources
    if ($LASTEXITCODE -ne 0) { Fail "Le clone de libdragon a echoue (branche $Branch)." }
} else {

    Write-Host "  git absent : telechargement de l'archive de la branche"
    $archive = Join-Path $cache "libdragon-$Branch.zip"
    & curl.exe -L --fail --retry 5 --retry-all-errors --retry-delay 2 --connect-timeout 30 `
        --progress-bar -o $archive "https://codeload.github.com/DragonMinded/libdragon/zip/refs/heads/$Branch"
    if ($LASTEXITCODE -ne 0) { Fail "Telechargement des sources de libdragon echoue (branche $Branch)." }

    $staging = Join-Path $cache "libdragon-src-tmp"
    Remove-Tree $staging
    New-Item -ItemType Directory -Force -Path $staging | Out-Null
    try {
        Expand-Archive -LiteralPath $archive -DestinationPath $staging -Force
    } catch {
        Fail "Extraction des sources de libdragon echouee : $($_.Exception.Message)"
    }

    $extracted = @(Get-ChildItem -LiteralPath $staging -Directory)
    if ($extracted.Count -ne 1) { Fail "Archive de sources inattendue." }
    Remove-Tree $sources
    [System.IO.Directory]::Move($extracted[0].FullName, $sources)
    Remove-Tree $staging
    Remove-Item -Force $archive -ErrorAction SilentlyContinue
}
Write-Host "  sources pretes" -ForegroundColor Green

$libdragonMakefile = Join-Path $sources "Makefile"
$makefileText = Get-Content $libdragonMakefile -Raw
if ($makefileText.Contains("install -Cv ")) {
    Set-Content -Path $libdragonMakefile -Value $makefileText.Replace("install -Cv ", "install -cv ") -NoNewline
    Write-Host "  Makefile : install -C remplace par -c (compatibilite BusyBox)"
}

if ($ToolchainOnly) {
    Write-Host ""
    Write-Host "-ToolchainOnly demande : compilation de libdragon ignoree." -ForegroundColor Yellow
    exit 0
}

Write-Host ""
Write-Host "--- compilation de libdragon ---" -ForegroundColor Cyan

if ((Test-Path (Join-Path $prefix "mips64-elf\lib\libdragon.a")) -and
    (Test-Path (Join-Path $prefix "bin\n64sym.exe")) -and -not $Force) {
    Write-Host "  deja compilee" -ForegroundColor Green
    Write-Host ""
    Write-Host "libdragon prete dans : $prefix" -ForegroundColor Green
    exit 0
}

function Get-HostCompilerBin {
    $system = Get-Command gcc -ErrorAction SilentlyContinue
    if ($system) { return Split-Path $system.Source -Parent }

    $local = Join-Path $SdkRoot "mingw64\bin\gcc.exe"
    if (Test-Path $local) { return Split-Path $local -Parent }

    foreach ($msys in @("$env:MSYS2_ROOT\mingw64\bin\gcc.exe", "C:\msys64\mingw64\bin\gcc.exe")) {
        if ($msys -and (Test-Path $msys)) { return Split-Path $msys -Parent }
    }
    return $null
}

$compilerBin = Get-HostCompilerBin

if (-not $compilerBin) {
    if ($NoCompilerDownload) {
        Fail "Aucun compilateur hote trouve et -NoCompilerDownload demande."
    }
    Write-Host "  aucun compilateur hote : telechargement de GCC portable (~274 Mo)"
    $archive = Join-Path $cache "winlibs-gcc.zip"
    if (-not (Test-Path $archive) -or $Force) {
        & curl.exe -L --fail --retry 5 --retry-all-errors --retry-delay 2 --connect-timeout 30 `
            --progress-bar -o $archive $MINGW_URL
        if ($LASTEXITCODE -ne 0) { Fail "Telechargement de GCC echoue." }
    }
    Write-Host "  extraction vers $SdkRoot\mingw64"

    Remove-Tree (Join-Path $SdkRoot "mingw64")
    & $tarExe -xf $archive -C $SdkRoot
    if ($LASTEXITCODE -ne 0) { Fail "Extraction de GCC echouee." }
    $compilerBin = Get-HostCompilerBin
    if (-not $compilerBin) { Fail "gcc.exe est absent apres extraction." }
}

Write-Host "  compilateur hote : $compilerBin"

$ccExe = Join-Path $compilerBin "cc.exe"
if (-not (Test-Path $ccExe)) {
    $gccExe = Join-Path $compilerBin "gcc.exe"
    if (Test-Path $gccExe) {
        Copy-Item $gccExe $ccExe
        Write-Host "  alias cc.exe cree"
    }
}

$busyboxDir = Join-Path $SdkRoot "busybox"
$busyboxExe = Join-Path $busyboxDir "busybox.exe"
$APPLETS = @("sh", "sed", "xxd", "awk", "cat", "cp", "mv", "rm", "mkdir", "rmdir", "printf", "echo",
             "install", "find", "grep", "sort", "uniq", "head", "tail", "wc", "tr", "expr", "test",
             "dirname", "basename", "touch", "true", "false", "date", "env", "which", "ln", "chmod",
             "cut", "sleep", "xargs", "diff", "od", "tee", "seq", "realpath", "readlink", "stat",
             "uname", "mktemp", "pwd", "cmp", "md5sum", "sha1sum", "nproc", "id", "yes", "sync")

if (-not (Test-Path (Join-Path $busyboxDir "sh.exe")) -or $Force) {
    New-Item -ItemType Directory -Force -Path $busyboxDir | Out-Null
    if (-not (Test-Path $busyboxExe) -or $Force) {
        Write-Host "  telechargement de BusyBox (~0,7 Mo)"
        & curl.exe -L --fail --retry 5 --retry-all-errors --retry-delay 2 --connect-timeout 30 `
            --progress-bar -o $busyboxExe $BUSYBOX_URL
        if ($LASTEXITCODE -ne 0) { Fail "Telechargement de BusyBox echoue." }
    }

    foreach ($applet in $APPLETS) {
        $link = Join-Path $busyboxDir "$applet.exe"
        if (Test-Path $link) { continue }

        try {
            New-Item -ItemType HardLink -Path $link -Target $busyboxExe -ErrorAction Stop | Out-Null
        } catch {
            Copy-Item $busyboxExe $link
        }
    }
    Write-Host "  BusyBox installe ($($APPLETS.Count) applets)" -ForegroundColor Green
}

$unixTools = $busyboxDir
Write-Host "  utilitaires Unix : $unixTools"

$makeExe = Join-Path $prefix "bin\make.exe"
if (-not (Test-Path $makeExe)) {
    $found = Get-Command make -ErrorAction SilentlyContinue
    if (-not $found) { Fail "make est introuvable." }
    $makeExe = $found.Source
}

$env:N64_INST = ($prefix -replace '\\', '/')
$env:PATH = "$prefix\bin;$compilerBin;$unixTools;$env:PATH"
$jobs = [Environment]::ProcessorCount

$msys2Age = "MSYS2_AGE=20260101"

$steps = @(
    @{ Label = "install-mk"; Args = @("install-mk") },
    @{ Label = "libdragon"; Args = @("-j$jobs", "libdragon") },
    @{ Label = "tools"; Args = @("-j$jobs", $msys2Age, "tools") },
    @{ Label = "install"; Args = @("install") },
    @{ Label = "tools-install"; Args = @($msys2Age, "tools-install") }
)

Push-Location $sources
try {
    foreach ($step in $steps) {
        Write-Host ""
        Write-Host "  make $($step.Label)" -ForegroundColor Cyan
        & $makeExe @($step.Args)
        if ($LASTEXITCODE -ne 0) { Fail "make $($step.Label) a echoue (code $LASTEXITCODE)" }
    }
} finally {
    Pop-Location
}

if (-not (Test-Path (Join-Path $prefix "mips64-elf\lib\libdragon.a"))) {
    Fail "libdragon.a est absente apres compilation."
}
if (-not (Test-Path (Join-Path $prefix "bin\n64sym.exe"))) {
    Fail "Les outils hote de libdragon n ont pas ete installes dans $prefix\bin."
}

Write-Host ""
Write-Host "=================== Recapitulatif ===================" -ForegroundColor Cyan
Write-Host ("{0,-12} {1}" -f "toolchain", (Join-Path $prefix "bin")) -ForegroundColor Green
Write-Host ("{0,-12} {1}" -f "libdragon", (Join-Path $prefix "mips64-elf\lib\libdragon.a")) -ForegroundColor Green
Write-Host ""
Write-Host "N64_INST  : $prefix" -ForegroundColor Green
Write-Host "build-n64cart-manager.ps1 l'utilisera automatiquement."
