# Enregistre "Edit with RottenText" dans le menu contextuel de l'Explorateur
# Windows (HKCU: pas besoin d'admin). Un fichier ouvert ainsi rejoint
# l'instance deja lancee via IPC (M-mono-instance), sinon une fenetre s'ouvre.
#   .\scripts\register-shell.ps1           enregistre (exe = racine du depot)
#   .\scripts\register-shell.ps1 -Remove   desinscrit
# NON TESTE (ecrit depuis macOS): a valider sur une machine Windows.
param([switch]$Remove)

$key = 'HKCU\Software\Classes\*\shell\RottenText'

if ($Remove) {
    & reg delete $key /f | Out-Null
    Write-Host 'Entree "Edit with RottenText" retiree.'
    exit 0
}

$exe = Join-Path (Split-Path -Parent $PSScriptRoot) 'RottenText.exe'
if (-not (Test-Path $exe)) {
    Write-Error "RottenText.exe introuvable: $exe (compiler d'abord)"
    exit 1
}

# reg.exe plutot que le provider Registry: le '*' du chemin est un joker
# PowerShell, reg le prend litteralement
& reg add $key /ve /d 'Edit with RottenText' /f | Out-Null
& reg add $key /v Icon /d "`"$exe`",0" /f | Out-Null
& reg add "$key\command" /ve /d "`"$exe`" `"%1`"" /f | Out-Null
Write-Host "Fait: clic droit sur un fichier > Edit with RottenText -> $exe"
