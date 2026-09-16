
[CmdletBinding()]
param(
    [ValidateSet("nsis", "portable", "both")]
    [string]$Target = "both",

    [string]$ProjectRoot,

    [string]$OutputDir,

    [switch]$Clean,

    [switch]$NativeOnly
)

$ErrorActionPreference = "Stop"

function Fail($msg) {
    Write-Host ""
    Write-Host "ERREUR : $msg" -ForegroundColor Red
    exit 1
}

function Invoke-Step([string]$title, [scriptblock]$block) {
    Write-Host ""
    Write-Host "--- $title ---" -ForegroundColor Cyan
    & $block
    if ($LASTEXITCODE -ne 0) { Fail "$title a echoue (code $LASTEXITCODE)" }
}

Write-Host "=== Compilation N64CartControl (Windows, cible $Target) ===" -ForegroundColor Cyan

function Test-ProjectDir([string]$path) {
    return (Test-Path (Join-Path $path "binding.gyp")) -and (Test-Path (Join-Path $path "package.json"))
}

if ($ProjectRoot) {
    if (-not (Test-Path $ProjectRoot)) { Fail "ProjectRoot introuvable : $ProjectRoot" }
    $ProjectRoot = (Resolve-Path $ProjectRoot).Path
} else {
    $candidates = @(
        (Join-Path (Split-Path $PSScriptRoot -Parent) "N64CartControl"),
        (Join-Path $PSScriptRoot "N64CartControl"),
        (Split-Path $PSScriptRoot -Parent)
    )
    $ProjectRoot = $candidates | Where-Object { Test-ProjectDir $_ } | Select-Object -First 1
}

if (-not $ProjectRoot -or -not (Test-ProjectDir $ProjectRoot)) {
    Fail @"
Projet N64CartControl introuvable (dossier contenant package.json et binding.gyp).
Utilise -ProjectRoot <chemin> pour le designer explicitement.
"@
}

if (-not $OutputDir) {
    $OutputDir = Join-Path (Split-Path $PSScriptRoot -Parent) "Output"
}
New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null

$appOut = Join-Path (Resolve-Path $OutputDir).Path "app"

Write-Host "Script    : $PSScriptRoot"
Write-Host "Projet    : $ProjectRoot"
Write-Host "Sortie    : $appOut"

foreach ($tool in @("node", "npm")) {
    if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
        Fail "$tool est absent du PATH. Installe Node.js 22 ou plus recent."
    }
}

$nodeMajor = [int]((node -p "process.versions.node.split('.')[0]"))
if ($nodeMajor -lt 22) {
    Fail @"
Node.js 22 minimum est requis (version detectee : $nodeMajor).
node-gyp 13, qui compile le module natif, exige Node ^22.22.2, ^24.15.0 ou >=26 ;
en dessous il echoue sur "ReferenceError: File is not defined".
Installe une version recente depuis https://nodejs.org
"@
}

if (-not (Get-Command python -ErrorAction SilentlyContinue)) {
    Write-Host "Note      : python absent du PATH, node-gyp risque d'echouer." -ForegroundColor Yellow
}

Write-Host "Node      : $(node -v)"
Write-Host "npm       : $(npm -v)"

Push-Location $ProjectRoot
try {

    $env:ELECTRON_RUN_AS_NODE = $null

    if (-not (Test-Path (Join-Path $ProjectRoot "node_modules"))) {
        Invoke-Step "npm install" { npm install --ignore-scripts }
    } else {
        Write-Host ""
        Write-Host "node_modules deja present, installation ignoree."
    }

    if ($Clean) {
        Invoke-Step "node-gyp clean" { npx node-gyp clean }
    }

    Invoke-Step "module natif (node-gyp)" { npx node-gyp rebuild }

    $addon = Join-Path $ProjectRoot "build\Release\n64cart.node"
    if (-not (Test-Path $addon)) { Fail "n64cart.node n'a pas ete produit." }
    Write-Host "Module natif : $addon" -ForegroundColor Green

    if ($NativeOnly) {
        Write-Host ""
        Write-Host "NativeOnly demande, empaquetage ignore." -ForegroundColor Green
        exit 0
    }

    $targets = switch ($Target) {
        "both" { @("--win", "nsis", "portable") }
        default { @("--win", $Target) }
    }

    Invoke-Step "empaquetage (electron-builder)" {
        npx electron-builder @targets --config.directories.output="$appOut"
    }
} finally {
    Pop-Location
}

Write-Host ""
Write-Host "=================== Recapitulatif ===================" -ForegroundColor Cyan

$artifacts = Get-ChildItem -Path $appOut -File -ErrorAction SilentlyContinue |
    Where-Object { $_.Extension -in '.exe', '.msi' }
if (-not $artifacts) {
    Fail "Aucun executable produit dans $appOut."
}
foreach ($a in $artifacts) {
    Write-Host ("{0,-52} {1,8:N1} Mo" -f $a.Name, ($a.Length / 1MB)) -ForegroundColor Green
}

Write-Host ""
Write-Host "Fichiers dans : $appOut" -ForegroundColor Green
Write-Host "Rappel        : la cartouche doit utiliser le pilote WinUSB (Zadig) pour etre vue en USB."
