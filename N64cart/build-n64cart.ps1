<#
.SYNOPSIS
    Compile le firmware n64cart nativement sous Windows, sans WSL.

.DESCRIPTION
    Utilise le SDK, le toolchain Arm, CMake, Ninja et picotool installes par
    l'extension VS Code officielle "Raspberry Pi Pico" dans %USERPROFILE%\.pico-sdk.
    Aucun compilateur natif (MinGW / Visual Studio) n'est necessaire.

    Prerequis : avoir cree UNE FOIS un projet d'exemple avec l'extension, pour
    qu'elle telecharge les outils.

.EXAMPLE
    .\build-n64cart.ps1
    Compile en v3 / PAL avec les versions d'outils les plus recentes trouvees.

.EXAMPLE
    .\build-n64cart.ps1 -Region ntsc -Clean
    Recompile de zero en NTSC.
#>

[CmdletBinding()]
param(
    [ValidateSet("v3", "v2", "pico", "pico-lite")]
    [string]$Board = "v3",

    [ValidateSet("pal", "ntsc")]
    [string]$Region = "pal",

    # Racine du projet n64cart (celle qui contient le dossier fw).
    [string]$ProjectRoot = $PSScriptRoot,

    # Forcer une version d'outil precise au lieu de la plus recente.
    [string]$SdkVersion,
    [string]$ToolchainVersion,
    [string]$PicotoolVersion,

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

Write-Host "=== Compilation firmware n64cart ($Board / $Region) ===" -ForegroundColor Cyan

# ---------------------------------------------------------------- projet ----

if (-not $ProjectRoot) { $ProjectRoot = (Get-Location).Path }
$ProjectRoot = (Resolve-Path $ProjectRoot).Path

$fw = Join-Path $ProjectRoot "fw"
if (-not (Test-Path (Join-Path $fw "CMakeLists.txt"))) {
    # le script est peut-etre deja dans fw/
    if (Test-Path (Join-Path $ProjectRoot "CMakeLists.txt")) {
        $fw = $ProjectRoot
    } else {
        Fail "Aucun fw\CMakeLists.txt trouve sous $ProjectRoot. Place le script a la racine du projet n64cart."
    }
}

if ($fw -match '\s') {
    Fail @"
Le chemin contient un espace :
  $fw
Le SDK Pico echoue de facon obscure dans ce cas. Deplace le projet vers un
chemin sans espace, par exemple X:\N64cart, puis relance le script.
"@
}

Write-Host "Projet    : $fw"

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Host "Note      : git absent du PATH, le hash de version sera vide (sans gravite)." -ForegroundColor Yellow
}

# ---------------------------------------------------------------- outils ----

$picoRoot = Join-Path $env:USERPROFILE ".pico-sdk"
if (-not (Test-Path $picoRoot)) {
    Fail @"
$picoRoot est introuvable.
Installe VS Code puis l'extension "Raspberry Pi Pico" (editeur Raspberry Pi),
et cree une fois un projet d'exemple pour declencher le telechargement des outils.
"@
}

$sdk       = Get-LatestDir (Join-Path $picoRoot "sdk")       $SdkVersion
$toolchain = Get-LatestDir (Join-Path $picoRoot "toolchain") $ToolchainVersion
$picotool  = Get-LatestDir (Join-Path $picoRoot "picotool")  $PicotoolVersion
$ninjaDir  = Get-LatestDir (Join-Path $picoRoot "ninja")     $null
$cmakeDir  = Get-LatestDir (Join-Path $picoRoot "cmake")     $null

foreach ($pair in @(@("SDK", $sdk), @("toolchain Arm", $toolchain), @("picotool", $picotool),
                    @("Ninja", $ninjaDir), @("CMake", $cmakeDir))) {
    if (-not $pair[1]) { Fail "$($pair[0]) introuvable sous $picoRoot" }
}

$picoVscode = Join-Path $picoRoot "cmake\pico-vscode.cmake"
if (-not (Test-Path $picoVscode)) {
    Fail "$picoVscode introuvable. Relance une creation de projet depuis l'extension VS Code."
}

Write-Host "SDK       : $($sdk.Name)"
Write-Host "Toolchain : $($toolchain.Name)"
Write-Host "Picotool  : $($picotool.Name)"
Write-Host "Ninja     : $($ninjaDir.Name)"
Write-Host "CMake     : $($cmakeDir.Name)"

$env:PICO_SDK_PATH = $sdk.FullName
$env:PATH = "$($toolchain.FullName)\bin;$($ninjaDir.FullName);$($cmakeDir.FullName)\bin;$env:PATH"

# ------------------------------------------------- injection dans CMake -----

$cmakeLists = Join-Path $fw "CMakeLists.txt"
$marker = "# --- toolchain pico-vscode, ajoute par build-n64cart.ps1 ---"
$raw = Get-Content $cmakeLists -Raw

if ($raw -notmatch [regex]::Escape($marker)) {
    Copy-Item $cmakeLists "$cmakeLists.bak" -Force
    Write-Host "Sauvegarde: CMakeLists.txt.bak"

    $block = @"
$marker
set(USERHOME `$ENV{USERPROFILE})
set(sdkVersion $($sdk.Name))
set(toolchainVersion $($toolchain.Name))
set(picotoolVersion $($picotool.Name))
set(picoVscode `${USERHOME}/.pico-sdk/cmake/pico-vscode.cmake)
if (EXISTS `${picoVscode})
    include(`${picoVscode})
endif()
# --- fin ---
"@

    $lines = Get-Content $cmakeLists
    $hit = $lines | Select-String -Pattern 'cmake_minimum_required' | Select-Object -First 1
    if (-not $hit) { Fail "cmake_minimum_required introuvable dans $cmakeLists" }
    $i = $hit.LineNumber   # 1-based : insertion juste apres cette ligne

    $out = @()
    $out += $lines[0..($i - 1)]
    $out += $block -split "`r?`n"
    $out += $lines[$i..($lines.Count - 1)]
    Set-Content -Path $cmakeLists -Value $out -Encoding UTF8
    Write-Host "CMakeLists.txt complete avec les chemins du toolchain." -ForegroundColor Green
} else {
    Write-Host "CMakeLists.txt deja configure."
}

# --------------------------------------------------------------- build ------

$build = Join-Path $fw "build-$Board-$Region"
if ($Clean -and (Test-Path $build)) {
    Write-Host "Nettoyage de $build"
    Remove-Item -Recurse -Force $build
}
New-Item -ItemType Directory -Force -Path $build | Out-Null

Push-Location $build
try {
    Write-Host ""
    Write-Host "--- cmake ---" -ForegroundColor Cyan
    cmake -G Ninja -DBOARD=$Board -DREGION=$Region ..
    if ($LASTEXITCODE -ne 0) { Fail "cmake a echoue (code $LASTEXITCODE)" }

    Write-Host ""
    Write-Host "--- ninja ---" -ForegroundColor Cyan
    ninja
    if ($LASTEXITCODE -ne 0) { Fail "ninja a echoue (code $LASTEXITCODE)" }
} finally {
    Pop-Location
}

# -------------------------------------------------------------- controle ----

$bin = Join-Path $build "n64cart.bin"
$uf2 = Join-Path $build "n64cart.uf2"
if (-not (Test-Path $uf2)) { Fail "n64cart.uf2 n'a pas ete produit." }

$size = (Get-Item $bin).Length
$align = 32768
# le cast en int est indispensable : Ceiling renvoie un Double, que le
# specificateur de format X8 refuse.
$romfsStart = [int]([math]::Ceiling($size / $align) * $align)

Write-Host ""
Write-Host "Binaire       : $size octets"
Write-Host ("Debut du ROMFS: 0x{0:X8}" -f $romfsStart)

if ($romfsStart -ne 65536) {
    Write-Host ""
    Write-Host "ATTENTION : le ROMFS ne demarrerait plus a 0x00010000." -ForegroundColor Yellow
    Write-Host "Flasher ce firmware rendrait le catalogue actuel illisible et imposerait" -ForegroundColor Yellow
    Write-Host "un format suivi d'un rechargement complet des ROMs." -ForegroundColor Yellow
} else {
    Write-Host "Compatible avec le contenu actuel de la cartouche (offset inchange)." -ForegroundColor Green
}

$outDir = Join-Path $ProjectRoot "Output"
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

$final = Join-Path $outDir "n64cart-$Board-$Region.uf2"
Copy-Item $uf2 $final -Force

Write-Host ""
Write-Host "Fichier pret : $final" -ForegroundColor Green
Write-Host "Flashage     : ROM FS Manager -> File -> Bootloader, puis glisser sur RPI-RP2."
