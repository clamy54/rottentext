# Extrait RT_VERSION de src\uMain.pas et genere version.iss (#define AppVersion).
# Lance par rottentext.iss a la compilation, meme mecanisme que make-notices.ps1.
$ErrorActionPreference = 'Stop'

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$main = Join-Path $here '..\..\src\uMain.pas'

$m = Select-String -LiteralPath $main -Pattern "RT_VERSION = '([^']+)'" |
    Select-Object -First 1
if (-not $m) {
    Write-Host "RT_VERSION introuvable dans $main"
    exit 1
}
$ver = $m.Matches[0].Groups[1].Value

Set-Content -LiteralPath (Join-Path $here 'version.iss') `
    -Value "#define AppVersion `"$ver`"" -Encoding ASCII
Write-Host "version.iss genere: AppVersion=$ver"
exit 0
