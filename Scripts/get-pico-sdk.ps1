
[CmdletBinding()]
param(

    [string]$SdkRoot,

    [ValidateSet("sdk", "toolchain", "cmake", "ninja", "picotool", "tools")]
    [string[]]$Component,

    [string]$CacheDir,

    [switch]$Force,

    [switch]$IncludeOpenOcd,

    [switch]$KeepArchives
)

$ErrorActionPreference = "Stop"

$SDK_VERSION       = "2.3.1"
$TOOLCHAIN_VERSION = "15_2_Rel1"
$CMAKE_VERSION     = "v4.3.4"
$NINJA_VERSION     = "v1.13.2"
$PICOTOOL_VERSION  = "2.3.1"
$TOOLS_TAG         = "v2.3.1-0"

function Fail($msg) {
    Write-Host ""
    Write-Host "ERREUR : $msg" -ForegroundColor Red
    exit 1
}

$arch = if ($env:PROCESSOR_ARCHITECTURE -eq "ARM64") { "arm64" } else { "x64" }
if ($arch -eq "arm64") {
    Write-Host "Note      : Windows ARM64 detecte, la chaine Arm x64 sera utilisee (emulation)." -ForegroundColor Yellow
}

$catalog = [ordered]@{
    sdk = @{
        Dir   = "sdk\$SDK_VERSION"
        Url   = "https://github.com/raspberrypi/pico-sdk/releases/download/$SDK_VERSION/pico-sdk-$SDK_VERSION.tar.gz"

        GitUrl = "https://github.com/raspberrypi/pico-sdk.git"
        Strip = 1

        Probe = "src\rp2_common\pico_stdlib\CMakeLists.txt"
        Label = "SDK Pico $SDK_VERSION"
    }
    toolchain = @{
        Dir   = "toolchain\$TOOLCHAIN_VERSION"
        Url   = "https://armkeil.blob.core.windows.net/developer/files/downloads/gnu/15.2.rel1/binrel/arm-gnu-toolchain-15.2.rel1-mingw-w64-x86_64-arm-none-eabi.zip"

        Strip = 0
        Probe = "bin\arm-none-eabi-gcc.exe"
        Label = "chaine Arm GNU 15.2.rel1"
    }
    cmake = @{
        Dir   = "cmake\$CMAKE_VERSION"
        Url   = "https://github.com/Kitware/CMake/releases/download/$CMAKE_VERSION/cmake-4.3.4-windows-x86_64.zip"
        Strip = 1
        Probe = "bin\cmake.exe"
        Label = "CMake 4.3.4"
    }
    ninja = @{
        Dir   = "ninja\$NINJA_VERSION"
        Url   = "https://github.com/ninja-build/ninja/releases/download/$NINJA_VERSION/ninja-win.zip"
        Strip = 0
        Probe = "ninja.exe"
        Label = "Ninja 1.13.2"
    }
    picotool = @{
        Dir   = "picotool\$PICOTOOL_VERSION"
        Url   = "https://github.com/raspberrypi/pico-sdk-tools/releases/download/$TOOLS_TAG/picotool-$PICOTOOL_VERSION-x64-win.zip"
        Strip = 0
        Probe = "picotool"
        Label = "picotool $PICOTOOL_VERSION"
    }
    tools = @{
        Dir   = "tools\$SDK_VERSION"
        Url   = "https://github.com/raspberrypi/pico-sdk-tools/releases/download/$TOOLS_TAG/pico-sdk-tools-$SDK_VERSION-x64-win.zip"
        Strip = 0
        Probe = "pioasm"
        Label = "outils du SDK (pioasm)"
    }
}

if ($IncludeOpenOcd) {
    $catalog["openocd"] = @{
        Dir   = "openocd\0.12.0+dev"
        Url   = "https://github.com/raspberrypi/pico-sdk-tools/releases/download/$TOOLS_TAG/openocd-0.12.0%2Bdev-x64-win.zip"
        Strip = 0
        Probe = "openocd.exe"
        Label = "openocd 0.12.0+dev"
    }
}

if (-not $SdkRoot) {
    $SdkRoot = Join-Path (Split-Path $PSScriptRoot -Parent) "SDK"
}
New-Item -ItemType Directory -Force -Path $SdkRoot | Out-Null
$SdkRoot = (Resolve-Path $SdkRoot).Path

if (-not $CacheDir) { $CacheDir = Join-Path $SdkRoot ".cache" }
New-Item -ItemType Directory -Force -Path $CacheDir | Out-Null

$wanted = if ($Component) { $Component } else { $catalog.Keys }

Write-Host "=== Telechargement du SDK Pico ===" -ForegroundColor Cyan
Write-Host "Destination : $SdkRoot"
Write-Host "Cache       : $CacheDir"
Write-Host "Composants  : $($wanted -join ', ')"

$curl = Get-Command curl.exe -ErrorAction SilentlyContinue
$gitExe = (Get-Command git -ErrorAction SilentlyContinue).Source
if (-not $gitExe) {
    Write-Host "Note        : git absent du PATH, le SDK sera pris depuis l'archive de release." -ForegroundColor Yellow
}

$tarExe = Join-Path $env:SystemRoot "System32\tar.exe"
if (-not (Test-Path $tarExe)) {
    $found = Get-Command tar.exe -ErrorAction SilentlyContinue
    if (-not $found) { Fail "tar.exe est introuvable (fourni avec Windows 10 1803 et plus recent)." }
    $tarExe = $found.Source
}

function Invoke-WithRetry([scriptblock]$action, [string]$what) {
    for ($attempt = 1; $attempt -le 6; $attempt++) {
        try {
            & $action
            return
        } catch {
            if ($attempt -eq 6) { Fail "$what : $($_.Exception.Message)" }
            Start-Sleep -Seconds $attempt
        }
    }
}

function Clear-ReadOnly([string]$path) {
    Get-ChildItem -LiteralPath $path -Recurse -Force -ErrorAction SilentlyContinue |
        ForEach-Object {
            try { $_.Attributes = [System.IO.FileAttributes]::Normal } catch {}
        }
}

function Remove-Tree([string]$path) {
    if (-not (Test-Path $path)) { return }
    Clear-ReadOnly $path
    Invoke-WithRetry { [System.IO.Directory]::Delete($path, $true) } "Impossible de supprimer $path"
}

function Move-Tree([string]$source, [string]$destination) {
    Remove-Tree $destination
    New-Item -ItemType Directory -Force -Path (Split-Path $destination -Parent) | Out-Null
    Clear-ReadOnly $source
    Invoke-WithRetry { [System.IO.Directory]::Move($source, $destination) } `
        "Impossible de deplacer $source vers $destination"
}

function Get-Archive([string]$url, [string]$destination) {
    if ((Test-Path $destination) -and -not $Force) {
        Write-Host "  archive deja en cache : $(Split-Path $destination -Leaf)"
        return
    }
    Write-Host "  telechargement de $url"
    if ($curl) {
        & curl.exe -L --fail --retry 5 --retry-all-errors --retry-delay 2 --connect-timeout 30 `
            --progress-bar -o $destination $url
        if ($LASTEXITCODE -ne 0) { Fail "Telechargement echoue ($url)" }
    } else {
        $previous = $ProgressPreference
        $ProgressPreference = "SilentlyContinue"
        try {
            Invoke-WebRequest -Uri $url -OutFile $destination -UseBasicParsing
        } finally {
            $ProgressPreference = $previous
        }
    }
}

function Expand-Component([string]$archive, [string]$target, [int]$strip) {
    $staging = Join-Path $CacheDir ("stage-" + [System.IO.Path]::GetRandomFileName())
    New-Item -ItemType Directory -Force -Path $staging | Out-Null
    try {

        & $tarExe -xf $archive -C $staging
        if ($LASTEXITCODE -ne 0) { Fail "Extraction echouee : $archive" }

        $source = $staging
        if ($strip -gt 0) {
            for ($i = 0; $i -lt $strip; $i++) {
                $children = @(Get-ChildItem -LiteralPath $source -Force)
                if ($children.Count -ne 1 -or -not $children[0].PSIsContainer) {
                    Fail "Archive inattendue (pas un dossier unique a la racine) : $archive"
                }
                $source = $children[0].FullName
            }
        }

        Move-Tree $source $target
    } finally {
        Remove-Tree $staging
    }
}

$installed = @()

foreach ($name in $wanted) {
    $item = $catalog[$name]
    if (-not $item) { Fail "Composant inconnu : $name" }

    $target = Join-Path $SdkRoot $item.Dir
    $probe = Join-Path $target $item.Probe

    Write-Host ""
    Write-Host "--- $($item.Label) ---" -ForegroundColor Cyan

    if ((Test-Path $probe) -and -not $Force) {
        Write-Host "  deja installe : $target" -ForegroundColor Green
        $installed += $name
        continue
    }

    $gitUrl = $item['GitUrl']
    if ($gitUrl -and $gitExe) {
        Write-Host "  clone de $gitUrl (branche $SDK_VERSION, sous-modules inclus)"

        Remove-Tree "$target.tmp"
        Remove-Tree $target
        New-Item -ItemType Directory -Force -Path (Split-Path $target -Parent) | Out-Null
        & $gitExe clone --depth 1 --branch $SDK_VERSION --recurse-submodules --shallow-submodules `
            $gitUrl $target
        if ($LASTEXITCODE -ne 0) {
            Remove-Tree $target
            Fail "Le clone du SDK a echoue (relance le script pour reprendre)."
        }
    } else {
        if ($gitUrl) {
            Write-Host "  git absent : archive de release utilisee, les sous-modules (tinyusb, lwip...) resteront vides." -ForegroundColor Yellow
        }
        $archive = Join-Path $CacheDir ([System.IO.Path]::GetFileName(([uri]$item.Url).LocalPath))
        Get-Archive $item.Url $archive
        Write-Host "  extraction vers $target"
        Expand-Component $archive $target $item.Strip
        if (-not $KeepArchives) { Remove-Item -Force $archive -ErrorAction SilentlyContinue }
    }

    if (-not (Test-Path $probe)) {
        Fail "$($item.Label) : $($item.Probe) est absent apres extraction, archive inattendue."
    }
    Write-Host "  installe" -ForegroundColor Green
    $installed += $name
}

if (-not $KeepArchives) {
    Remove-Item -Recurse -Force $CacheDir -ErrorAction SilentlyContinue
}

Write-Host ""
Write-Host "=================== Recapitulatif ===================" -ForegroundColor Cyan
foreach ($name in $installed) {
    $dir = Join-Path $SdkRoot $catalog[$name].Dir
    Write-Host ("{0,-10} {1}" -f $name, $dir) -ForegroundColor Green
}
Write-Host ""
Write-Host "SDK pret dans : $SdkRoot" -ForegroundColor Green
Write-Host "build-n64cart.ps1 l utilisera automatiquement."
