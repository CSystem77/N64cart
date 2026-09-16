
[CmdletBinding()]
param(
    [ValidateSet("v3", "v2", "pico", "pico-lite")]
    [string]$Board = "v3",

    [ValidateSet("pal", "ntsc", "both")]
    [string]$Region = "both",

    [string]$ProjectRoot,

    [string]$OutputDir,

    [string]$SdkVersion,
    [string]$ToolchainVersion,
    [string]$PicotoolVersion,

    [string]$SdkRoot,

    [switch]$NoDownload,

    [switch]$Clean
)

$ErrorActionPreference = "Stop"

function Fail($msg) {
    Write-Host ""
    Write-Host "ERREUR : $msg" -ForegroundColor Red
    exit 1
}

function Get-LatestDir($base, $forced) {
    if (-not (Test-Path $base)) { return $null }
    if ($forced) {
        $p = Join-Path $base $forced
        if (-not (Test-Path $p)) { Fail "Version '$forced' introuvable dans $base" }
        return Get-Item $p
    }
    Get-ChildItem -Path $base -Directory | Sort-Object Name -Descending | Select-Object -First 1
}

Write-Host "=== Compilation firmware n64cart (carte $Board, region $Region) ===" -ForegroundColor Cyan

function Test-ProjectDir([string]$path) {
    return (Test-Path (Join-Path $path "fw\CMakeLists.txt"))
}

function Find-ProjectRoot([string]$start) {
    if (-not $start) { return @() }
    $dir = Get-Item -LiteralPath $start -ErrorAction SilentlyContinue

    $chain = @()
    for ($i = 0; $i -lt 5 -and $dir; $i++) { $chain += $dir; $dir = $dir.Parent }

    foreach ($d in $chain) {
        if (Test-ProjectDir $d.FullName) { return @($d.FullName) }
    }

    foreach ($d in $chain) {
        $hits = @()
        foreach ($sub in (Get-ChildItem -LiteralPath $d.FullName -Directory -ErrorAction SilentlyContinue)) {
            if (Test-ProjectDir $sub.FullName) { $hits += $sub.FullName }
        }
        if ($hits.Count -gt 0) { return @($hits | Sort-Object -Unique) }
    }

    return @()
}

if ($ProjectRoot) {
    $ProjectRoot = (Resolve-Path $ProjectRoot).Path
    if (-not (Test-ProjectDir $ProjectRoot)) {
        $found = @(Find-ProjectRoot $ProjectRoot)
        if ($found.Count -eq 0) { Fail "Aucun fw\CMakeLists.txt trouve autour de $ProjectRoot." }
        $ProjectRoot = $found[0]
    }
} else {
    $found = @(Find-ProjectRoot $PSScriptRoot)
    if ($found.Count -eq 0) { $found = @(Find-ProjectRoot (Get-Location).Path) }

    if ($found.Count -eq 0) {
        Fail @"
Racine du projet introuvable (dossier contenant fw\CMakeLists.txt).
Recherche effectuee depuis $PSScriptRoot, ses parents et leurs sous-dossiers.
Utilise -ProjectRoot <chemin> pour la designer explicitement.
"@
    }
    if ($found.Count -gt 1) {
        Write-Host ""
        Write-Host "Plusieurs projets n64cart trouves :" -ForegroundColor Yellow
        $found | ForEach-Object { Write-Host "  $_" }
        Fail "Precise lequel utiliser avec -ProjectRoot <chemin>."
    }
    $ProjectRoot = $found[0]
}

$fw = Join-Path $ProjectRoot "fw"
if ($fw -match '\s') {
    Fail @"
Le chemin contient un espace :
  $fw
Le SDK Pico echoue de facon obscure dans ce cas. Deplace le projet vers un
chemin sans espace, par exemple X:\N64cart, puis relance le script.
"@
}

if (-not $OutputDir) {
    if ($PSScriptRoot) {
        $OutputDir = Join-Path (Split-Path $PSScriptRoot -Parent) "Output"
    } else {
        $OutputDir = Join-Path $ProjectRoot "Output"
    }
}

$outDir = Join-Path $OutputDir "fw"

Write-Host "Script    : $PSScriptRoot"
Write-Host "Racine    : $ProjectRoot"
Write-Host "Firmware  : $fw"
Write-Host "Sortie    : $outDir"

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Host "Note      : git absent du PATH, le hash de version sera vide (sans gravite)." -ForegroundColor Yellow
}

function Test-PicoRoot([string]$path) {
    return $path -and (Test-Path (Join-Path $path "sdk"))
}

$defaultSdkRoot = if ($PSScriptRoot) {
    Join-Path (Split-Path $PSScriptRoot -Parent) "SDK"
} else {
    Join-Path $ProjectRoot "SDK"
}

if ($SdkRoot) {
    if (-not (Test-PicoRoot $SdkRoot)) { Fail "Aucun SDK Pico sous $SdkRoot (sous-dossier sdk\ attendu)." }
    $picoRoot = (Resolve-Path $SdkRoot).Path
} else {
    $picoRoot = @($defaultSdkRoot, (Join-Path $env:USERPROFILE ".pico-sdk")) |
        Where-Object { Test-PicoRoot $_ } | Select-Object -First 1
    if ($picoRoot) { $picoRoot = (Resolve-Path $picoRoot).Path }
}

if (-not $picoRoot) {
    if ($NoDownload) {
        Fail @"
SDK Pico introuvable ($defaultSdkRoot et $env:USERPROFILE\.pico-sdk).
Relance sans -NoDownload, lance get-pico-sdk.ps1, ou indique -SdkRoot <chemin>.
"@
    }
    $getter = Join-Path $PSScriptRoot "get-pico-sdk.ps1"
    if (-not (Test-Path $getter)) { Fail "SDK Pico introuvable et get-pico-sdk.ps1 est absent de $PSScriptRoot." }

    Write-Host ""
    Write-Host "SDK Pico introuvable, telechargement dans $defaultSdkRoot" -ForegroundColor Yellow
    & $getter -SdkRoot $defaultSdkRoot
    if ($LASTEXITCODE -ne 0) { Fail "Le telechargement du SDK a echoue (code $LASTEXITCODE)." }
    if (-not (Test-PicoRoot $defaultSdkRoot)) { Fail "Le SDK est toujours absent apres telechargement." }
    $picoRoot = (Resolve-Path $defaultSdkRoot).Path
}

$sdk       = Get-LatestDir (Join-Path $picoRoot "sdk")       $SdkVersion
$toolchain = Get-LatestDir (Join-Path $picoRoot "toolchain") $ToolchainVersion
$picotool  = Get-LatestDir (Join-Path $picoRoot "picotool")  $PicotoolVersion
$ninjaDir  = Get-LatestDir (Join-Path $picoRoot "ninja")     $null
$cmakeDir  = Get-LatestDir (Join-Path $picoRoot "cmake")     $null
$toolsDir  = Get-LatestDir (Join-Path $picoRoot "tools")     $null

foreach ($pair in @(@("SDK", $sdk), @("toolchain Arm", $toolchain), @("picotool", $picotool),
                    @("Ninja", $ninjaDir), @("CMake", $cmakeDir))) {
    if (-not $pair[1]) { Fail "$($pair[0]) introuvable sous $picoRoot (lance get-pico-sdk.ps1)" }
}

Write-Host "SDK Pico  : $picoRoot"
Write-Host "SDK       : $($sdk.Name)"
Write-Host "Toolchain : $($toolchain.Name)"
Write-Host "Picotool  : $($picotool.Name)"
Write-Host "Ninja     : $($ninjaDir.Name)"
Write-Host "CMake     : $($cmakeDir.Name)"

$env:PICO_SDK_PATH = $sdk.FullName
$env:PICO_TOOLCHAIN_PATH = $toolchain.FullName
$env:PATH = "$($toolchain.FullName)\bin;$($ninjaDir.FullName);$($cmakeDir.FullName)\bin;$env:PATH"

$cmakeLists = Join-Path $fw "CMakeLists.txt"
$marker = "# --- toolchain pico, ajoute par build-n64cart ---"

$blockLines = @(
    $marker,
    "set(PICO_SDK_PATH `"$($sdk.FullName -replace '\\', '/')`")",
    "set(PICO_TOOLCHAIN_PATH `"$($toolchain.FullName -replace '\\', '/')`")"
)

$picotoolDir = Join-Path $picotool.FullName "picotool"
if (Test-Path (Join-Path $picotoolDir "picotoolConfig.cmake")) {
    $blockLines += "set(picotool_DIR `"$($picotoolDir -replace '\\', '/')`")"
}
if ($toolsDir) {
    $pioasmDir = Join-Path $toolsDir.FullName "pioasm"
    if (Test-Path (Join-Path $pioasmDir "pioasmConfig.cmake")) {
        $blockLines += "set(pioasm_DIR `"$($pioasmDir -replace '\\', '/')`")"
    }
}
$blockLines += "# --- fin ---"

$lines = @(Get-Content $cmakeLists)

$cleaned = @()
$inBlock = $false
foreach ($line in $lines) {
    if (-not $inBlock -and $line -like "# --- toolchain pico*") {
        $inBlock = $true
        continue
    }
    if ($inBlock) {
        if ($line -like "# --- fin ---*") { $inBlock = $false }
        continue
    }
    $cleaned += $line
}
if ($inBlock) { Fail "Bloc toolchain non termine dans $cmakeLists (restaure CMakeLists.txt.bak)." }

$anchor = -1
for ($i = 0; $i -lt $cleaned.Count; $i++) {
    if ($cleaned[$i] -match 'cmake_minimum_required') { $anchor = $i; break }
}
if ($anchor -lt 0) { Fail "cmake_minimum_required introuvable dans $cmakeLists" }

$out = @()
$out += $cleaned[0..$anchor]
$out += $blockLines
if ($anchor + 1 -lt $cleaned.Count) { $out += $cleaned[($anchor + 1)..($cleaned.Count - 1)] }

if (($out -join "`n") -eq ($lines -join "`n")) {
    Write-Host "CMakeLists.txt deja configure pour ce SDK."
} else {

    if (-not (Test-Path "$cmakeLists.bak")) {
        Copy-Item $cmakeLists "$cmakeLists.bak"
        Write-Host "Sauvegarde: CMakeLists.txt.bak"
    }
    Set-Content -Path $cmakeLists -Value $out -Encoding UTF8
    Write-Host "CMakeLists.txt pointe sur $picoRoot" -ForegroundColor Green
}

New-Item -ItemType Directory -Force -Path $outDir | Out-Null
$outDir = (Resolve-Path $outDir).Path

$regions = if ($Region -eq "both") { @("pal", "ntsc") } else { @($Region) }
$results = @()

foreach ($reg in $regions) {

    Write-Host ""
    Write-Host "=================== $Board / $($reg.ToUpper()) ===================" -ForegroundColor Cyan

    $build = Join-Path $fw "build-$Board-$reg"
    if ($Clean -and (Test-Path $build)) {
        Write-Host "Nettoyage de $build"
        Remove-Item -Recurse -Force $build
    }
    New-Item -ItemType Directory -Force -Path $build | Out-Null

    Push-Location $build
    try {
        Write-Host ""
        Write-Host "--- cmake ---" -ForegroundColor Cyan

        cmake -G Ninja "-DBOARD=$Board" "-DREGION=$reg" ..
        if ($LASTEXITCODE -ne 0) { Fail "cmake a echoue pour $reg (code $LASTEXITCODE)" }

        Write-Host ""
        Write-Host "--- ninja ---" -ForegroundColor Cyan
        ninja
        if ($LASTEXITCODE -ne 0) { Fail "ninja a echoue pour $reg (code $LASTEXITCODE)" }
    } finally {
        Pop-Location
    }

    $bin = Join-Path $build "n64cart.bin"
    $uf2 = Join-Path $build "n64cart.uf2"
    if (-not (Test-Path $uf2)) { Fail "n64cart.uf2 n'a pas ete produit pour $reg." }

    $size = (Get-Item $bin).Length
    $align = 32768

    $romfsStart = [int]([math]::Ceiling($size / $align) * $align)

    $final = Join-Path $outDir "n64cart-$Board-$reg.uf2"
    Copy-Item $uf2 $final -Force

    $results += [pscustomobject]@{
        Region = $reg.ToUpper()
        Taille = $size
        Offset = $romfsStart
        Fichier = Split-Path $final -Leaf
        Ok = ($romfsStart -eq 65536)
    }
}

Write-Host ""
Write-Host "=================== Recapitulatif ===================" -ForegroundColor Cyan

foreach ($r in $results) {
    $etat = if ($r.Ok) { "compatible" } else { "INCOMPATIBLE" }
    $couleur = if ($r.Ok) { "Green" } else { "Yellow" }
    Write-Host ("{0,-5} {1,7} o   ROMFS 0x{2:X8}   {3,-24} {4}" -f `
        $r.Region, $r.Taille, $r.Offset, $r.Fichier, $etat) -ForegroundColor $couleur
}

if ($results | Where-Object { -not $_.Ok }) {
    Write-Host ""
    Write-Host "ATTENTION : un binaire depasse 64 Ko, le ROMFS ne demarrerait plus a" -ForegroundColor Yellow
    Write-Host "0x00010000. Flasher ce firmware rendrait le catalogue illisible et imposerait" -ForegroundColor Yellow
    Write-Host "un format suivi d'un rechargement complet des ROMs." -ForegroundColor Yellow
}

Write-Host ""
Write-Host "Fichiers dans : $outDir" -ForegroundColor Green
Write-Host "Flashage      : ROM FS Manager -> File -> Bootloader, puis glisser sur RPI-RP2."
