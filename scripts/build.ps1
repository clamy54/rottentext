# Build portable (Windows). Localise lazbuild tout seul, chemin .lpi relatif,
# tue l'exe avant de recompiler. Marche depuis n'importe quel dossier / machine.
#
# Usage: powershell -File scripts\build.ps1 [-Release]
param([switch]$Release)

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$lpi  = Join-Path $root 'RottenText.lpi'

# lazbuild : PATH d'abord, puis emplacements d'install classiques
$lazbuild = (Get-Command lazbuild -ErrorAction SilentlyContinue).Source
if (-not $lazbuild) {
  foreach ($c in @(
    'C:\lazarus\lazbuild.exe',
    "$env:ProgramFiles\Lazarus\lazbuild.exe",
    "${env:ProgramFiles(x86)}\Lazarus\lazbuild.exe",
    "$env:LOCALAPPDATA\Lazarus\lazbuild.exe")) {
    if ($c -and (Test-Path $c)) { $lazbuild = $c; break }
  }
}
if (-not $lazbuild) { throw "lazbuild introuvable. Ajoute-le au PATH ou installe Lazarus." }

# l'exe verrouille le lien: demander la fermeture (les prompts de sauvegarde
# s'affichent), et ne tuer qu'apres refus explicite
$running = @(Get-Process RottenText -ErrorAction SilentlyContinue)
foreach ($p in $running) { [void]$p.CloseMainWindow() }
foreach ($p in $running) {
  if (-not $p.WaitForExit(5000)) {
    throw "RottenText (pid $($p.Id)) est toujours ouvert. Ferme-le, puis relance le build."
  }
}

$buildArg = if ($Release) { '--build-mode=Release' } else { '' }
Write-Output "lazbuild: $lazbuild"
& $lazbuild $buildArg $lpi
if ($LASTEXITCODE -ne 0) { throw "build echoue ($LASTEXITCODE)" }
Write-Output "OK -> $(Join-Path $root 'RottenText.exe')"
