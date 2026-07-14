# Bench E2E M-perf : ouverture reelle + RAM + CPU d'une rafale de frappes.
# Machine INACTIVE obligatoire (SendKeys). Fixtures regenerees a chaque run.
$ErrorActionPreference = 'Stop'
$exe = Join-Path (Split-Path $PSScriptRoot -Parent) 'RottenText.exe'
if (-not (Test-Path $exe)) { throw "exe introuvable: $exe (compiler d'abord)" }
$sh = New-Object -ComObject WScript.Shell

foreach ($n in 10000, 100000, 1000000) {
  $f = Join-Path $env:TEMP "bench-$n.pas"
  $sb = New-Object Text.StringBuilder
  for ($i = 1; $i -le $n; $i++) {
    switch ($i % 4) {
      0 { [void]$sb.AppendLine("procedure Foo$i(const A: Integer); // ligne $i") }
      1 { [void]$sb.AppendLine("  X := X + $i; {* bloc *}") }
      2 { [void]$sb.AppendLine("  if (A > $i) then Exit('chaine $i');") }
      3 { [void]$sb.AppendLine("end;") }
    }
  }
  [IO.File]::WriteAllText($f, $sb.ToString())

  Get-Process RottenText -ErrorAction SilentlyContinue | Stop-Process -Force
  Start-Sleep -Milliseconds 400

  $sw = [Diagnostics.Stopwatch]::StartNew()
  Start-Process $exe -ArgumentList "`"$f`""
  $title = "bench-$n.pas - RottenText"
  while (-not $sh.AppActivate($title)) {
    Start-Sleep -Milliseconds 50
    if ($sw.Elapsed.TotalSeconds -gt 180) { throw "timeout ouverture $n" }
  }
  $tOpen = $sw.Elapsed.TotalMilliseconds

  # laisser le scan idle initial se poser avant de mesurer la frappe
  Start-Sleep -Seconds 8
  $p = Get-Process RottenText
  $ram = $p.WorkingSet64 / 1MB
  $p.Refresh(); $cpu0 = $p.TotalProcessorTime

  if ($sh.AppActivate($title)) {
    $sh.SendKeys('abcdefghij0123456789')   # 20 frappes
    Start-Sleep -Seconds 5                  # laisser le resync/rescan bruler
    $p.Refresh(); $cpu1 = $p.TotalProcessorTime
    $cpuTape = ($cpu1 - $cpu0).TotalSeconds
  } else { $cpuTape = -1 }

  "{0,8} lignes : ouverture {1,6:N0} ms | RAM {2,5:N0} Mo | CPU 20 frappes {3,5:N1} s" -f `
    $n, $tOpen, $ram, $cpuTape
  Get-Process RottenText -ErrorAction SilentlyContinue | Stop-Process -Force
}
