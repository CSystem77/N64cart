
[CmdletBinding()]
param(
    [ValidateSet("v3", "v2", "pico", "pico-lite")]
    [string]$Board = "v3",

    [ValidateSet("auto", "docker", "wsl", "native")]
    [string]$Backend = "auto",

    [string]$ProjectRoot,

    [string]$OutputDir,

    [string]$Image = "ghcr.io/dragonminded/libdragon:latest",

    [switch]$Clean
)

$ErrorActionPreference = "Stop"

function Fail($msg) {
    Write-Host ""
    Write-Host "ERREUR : $msg" -ForegroundColor Red
    exit 1
}

Write-Host "=== Compilation du menu n64cart-manager (carte $Board) ===" -ForegroundColor Cyan

function Test-ProjectDir([string]$path) {
    return (Test-Path (Join-Path $path "rom\Makefile")) -and (Test-Path (Join-Path $path "fw\CMakeLists.txt"))
}

if ($ProjectRoot) {
    if (-not (Test-ProjectDir $ProjectRoot)) { Fail "Aucun projet n64cart sous $ProjectRoot (rom\Makefile attendu)." }
    $ProjectRoot = (Resolve-Path $ProjectRoot).Path
} else {
    $parent = Split-Path $PSScriptRoot -Parent
    $found = @(Get-ChildItem -LiteralPath $parent -Directory -ErrorAction SilentlyContinue |
        Where-Object { Test-ProjectDir $_.FullName } | Select-Object -ExpandProperty FullName)
    if (Test-ProjectDir $parent) { $found = @($parent) }

    if ($found.Count -eq 0) {
        Fail "Projet n64cart introuvable autour de $parent. Utilise -ProjectRoot <chemin>."
    }
    if ($found.Count -gt 1) {
        Write-Host "Plusieurs projets trouves :" -ForegroundColor Yellow
        $found | ForEach-Object { Write-Host "  $_" }
        Fail "Precise lequel utiliser avec -ProjectRoot <chemin>."
    }
    $ProjectRoot = $found[0]
}

$romDir = Join-Path $ProjectRoot "rom"

if (-not $OutputDir) {
    $OutputDir = Join-Path (Split-Path $PSScriptRoot -Parent) "Output"
}
New-Item -ItemType Directory -Force -Path (Join-Path $OutputDir "rom") | Out-Null
$outDir = (Resolve-Path (Join-Path $OutputDir "rom")).Path

Write-Host "Script    : $PSScriptRoot"
Write-Host "Racine    : $ProjectRoot"
Write-Host "Sources   : $romDir"
Write-Host "Sortie    : $outDir"

function Test-Docker {
    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) { return $false }
    & docker version --format '{{.Server.Version}}' 2>&1 | Out-Null
    return $LASTEXITCODE -eq 0
}

function Get-WslDistro {
    if (-not (Get-Command wsl.exe -ErrorAction SilentlyContinue)) { return $null }

    $raw = (& wsl.exe -l -q 2>$null) -join "`n"
    $names = ($raw -replace "`0", "") -split "`r?`n" | Where-Object { $_.Trim() }
    if ($names.Count -eq 0) { return $null }
    return $names[0].Trim()
}

$sdkRoot = Join-Path (Split-Path $PSScriptRoot -Parent) "SDK"
$localLibdragon = Join-Path $sdkRoot "libdragon"
if (((Test-Path (Join-Path $localLibdragon "mips64-elf\lib\libdragon.a")) -and
     (Test-Path (Join-Path $localLibdragon "bin\n64sym.exe"))) -and -not $env:N64_INST) {
    $env:N64_INST = ($localLibdragon -replace '\\', '/')
    $env:PATH = "$localLibdragon\bin;$env:PATH"
}

$unixBin = $null
$busybox = Join-Path $sdkRoot "busybox"
if (Test-Path (Join-Path $busybox "sh.exe")) {
    $unixBin = $busybox
} else {
    $unixCandidates = @()
    $gitCommand = (Get-Command git -ErrorAction SilentlyContinue).Source
    if ($gitCommand) {
        $dir = Split-Path $gitCommand -Parent
        for ($level = 0; $level -lt 3 -and $dir; $level++) {
            $unixCandidates += (Join-Path $dir "usr\bin")
            $dir = Split-Path $dir -Parent
        }
    }
    $unixCandidates += "$env:ProgramFiles\Git\usr\bin"
    foreach ($candidate in $unixCandidates) {
        if ((Test-Path (Join-Path $candidate "sh.exe")) -and
            (Test-Path (Join-Path $candidate "sed.exe")) -and
            (Test-Path (Join-Path $candidate "xxd.exe"))) {
            $unixBin = $candidate
            break
        }
    }
}
if ($unixBin) {

    $env:PATH = "$unixBin;$env:PATH"
}

$localMingw = Join-Path $sdkRoot "mingw64\bin"
if (Test-Path (Join-Path $localMingw "gcc.exe")) {
    $env:PATH = "$env:PATH;$localMingw"
}

function Test-Native {
    if (-not $env:N64_INST) { return $false }
    if (-not (Get-Command make -ErrorAction SilentlyContinue)) { return $false }
    return (Test-Path (Join-Path $env:N64_INST "bin\mips64-elf-gcc.exe")) -or
           (Test-Path (Join-Path $env:N64_INST "bin/mips64-elf-gcc"))
}

if ($Backend -eq "auto") {
    if (-not (Test-Native)) {

        $getter = Join-Path $PSScriptRoot "get-libdragon.ps1"
        if (-not (Test-Path $getter)) {
            Fail "libdragon est absent de $sdkRoot et get-libdragon.ps1 est introuvable dans $PSScriptRoot."
        }

        Write-Host ""
        Write-Host "libdragon absent : installation dans $sdkRoot (toolchain + compilateur, ~370 Mo)" -ForegroundColor Yellow
        & $getter -SdkRoot $sdkRoot
        if ($LASTEXITCODE -ne 0) { Fail "L'installation de libdragon a echoue (code $LASTEXITCODE)." }

        if (((Test-Path (Join-Path $localLibdragon "mips64-elf\lib\libdragon.a")) -and
     (Test-Path (Join-Path $localLibdragon "bin\n64sym.exe"))) -and -not $env:N64_INST) {
            $env:N64_INST = ($localLibdragon -replace '\\', '/')
            $env:PATH = "$localLibdragon\bin;$env:PATH"
        }
    }

    if (Test-Native) {
        $Backend = "native"
    } else {
        Fail "libdragon est installe mais make ou mips64-elf-gcc reste introuvable dans $env:N64_INST."
    }
}

Write-Host "Backend   : $Backend"

$makeArgs = "BOARD=$Board"
if ($Clean) { $makeArgs = "clean $makeArgs" }

switch ($Backend) {
    "native" {
        if (-not (Test-Native)) { Fail "Backend native demande mais N64_INST ou make est absent." }
        Write-Host "N64_INST  : $env:N64_INST"

        $romMakefile = Join-Path $romDir "Makefile"
        $makefileText = Get-Content $romMakefile -Raw
        $shellCall = "'s/.*FIRMWARE_VERSION.*\(0x[0-9a-fA-F]*\).*/\1/p' ../fw/CMakeLists.txt)"
        if ($makefileText.Contains($shellCall)) {
            if (-not (Test-Path "$romMakefile.bak")) {
                Copy-Item $romMakefile "$romMakefile.bak"
                Write-Host "Sauvegarde: Makefile.bak"
            }
            $patched = $makefileText.Replace($shellCall,
                "'s/.*FIRMWARE_VERSION.*\(0x[0-9a-fA-F]*\).*/\1/p' ../fw/CMakeLists.txt | cat)")
            Set-Content -Path $romMakefile -Value $patched -NoNewline
            Write-Host "Makefile  : adapte au make natif Windows" -ForegroundColor Green
        }

        if (-not $unixBin) {
            Fail "Aucun shell POSIX trouve : lance .\get-libdragon.ps1, il installe BusyBox dans SDK\busybox."
        }
        Write-Host "Shell     : $unixBin"

        $makeExe = Join-Path $env:N64_INST "bin\make.exe"
        if (-not (Test-Path $makeExe)) {
            $found = Get-Command make -ErrorAction SilentlyContinue
            if (-not $found) { Fail "make est introuvable dans $env:N64_INST\bin." }
            $makeExe = $found.Source
        }

        Push-Location $romDir
        try {
            & $makeExe @($makeArgs -split ' ')
            if ($LASTEXITCODE -ne 0) { Fail "make a echoue (code $LASTEXITCODE)" }
        } finally {
            Pop-Location
        }
    }

    "docker" {
        if (-not (Test-Docker)) { Fail "Docker n'est pas disponible (le service tourne-t-il ?)." }

        $script = "command -v xxd >/dev/null 2>&1 || (apt-get update -qq && apt-get install -y -qq xxd || apt-get install -y -qq vim-common); make $makeArgs"
        Write-Host ""
        Write-Host "--- docker run $Image ---" -ForegroundColor Cyan
        & docker run --rm -v "$($ProjectRoot):/src" -w /src/rom $Image /bin/bash -lc $script
        if ($LASTEXITCODE -ne 0) { Fail "La compilation dans le conteneur a echoue (code $LASTEXITCODE)" }
    }

    "wsl" {
        $distro = Get-WslDistro
        if (-not $distro) { Fail "Aucune distribution WSL installee (wsl --install -d Ubuntu)." }
        Write-Host "Distro    : $distro"

        $wslPath = (& wsl.exe -d $distro wslpath -a "$romDir") -replace "`0", ""
        $wslPath = $wslPath.Trim()

        $probe = (& wsl.exe -d $distro bash -lc 'echo -n "$N64_INST"') -replace "`0", ""
        if (-not $probe.Trim()) {
            Fail @"
N64_INST n'est pas defini dans la distribution $distro.
Compile libdragon (branche opengl) puis ajoute par exemple a ~/.bashrc :
  export N64_INST=/opt/libdragon
"@
        }
        Write-Host "N64_INST  : $($probe.Trim())"

        & wsl.exe -d $distro bash -lc "cd '$wslPath' && make $makeArgs"
        if ($LASTEXITCODE -ne 0) { Fail "La compilation dans WSL a echoue (code $LASTEXITCODE)" }
    }
}

$rom = Join-Path $romDir "n64cart-manager.z64"
if (-not (Test-Path $rom)) { Fail "n64cart-manager.z64 n'a pas ete produit." }

$final = Join-Path $outDir "n64cart-manager.z64"
Copy-Item $rom $final -Force

Write-Host ""
Write-Host "=================== Recapitulatif ===================" -ForegroundColor Cyan
Write-Host ("{0,-28} {1,10:N0} o" -f (Split-Path $final -Leaf), (Get-Item $final).Length) -ForegroundColor Green
Write-Host ""
Write-Host "Fichier dans : $outDir" -ForegroundColor Green
Write-Host "N64 Cart Control le proposera automatiquement si la cartouche ne l'a pas."
