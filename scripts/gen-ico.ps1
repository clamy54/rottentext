# regenere RottenText.ico (multi-tailles) depuis icons/rottentext.png.
# A relancer apres changement du png, puis rebuild (l'ico est embarque via
# {$R *.res} + <Icon Value="0"/> du .lpi). Entrees DIB 32bpp 16..128 + PNG 256.
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$root = Split-Path $PSScriptRoot -Parent
$srcPath = Join-Path $root 'icons\rottentext.png'
$outPath = Join-Path $root 'RottenText.ico'
$sizes = 16, 24, 32, 48, 64, 128, 256

$src = [System.Drawing.Bitmap]::FromFile($srcPath)
$entries = @()
try {
  foreach ($n in $sizes) {
    $bmp = New-Object System.Drawing.Bitmap($n, $n, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
    $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    # source pas forcement carree: fit proportionnel centre, fond transparent
    $scale = [Math]::Min($n / $src.Width, $n / $src.Height)
    $dw = [Math]::Round($src.Width * $scale)
    $dh = [Math]::Round($src.Height * $scale)
    $g.DrawImage($src, [int](($n - $dw) / 2), [int](($n - $dh) / 2), $dw, $dh)
    $g.Dispose()

    if ($n -eq 256) {
      $ms = New-Object System.IO.MemoryStream
      $bmp.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
      $data = $ms.ToArray()
      $ms.Dispose()
    } else {
      # DIB: BITMAPINFOHEADER + XOR (BGRA bottom-up) + AND (1bpp, zeros)
      $rect = New-Object System.Drawing.Rectangle(0, 0, $n, $n)
      $bd = $bmp.LockBits($rect, [System.Drawing.Imaging.ImageLockMode]::ReadOnly,
        [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
      $stride = $bd.Stride
      $raw = New-Object byte[] ($stride * $n)
      [System.Runtime.InteropServices.Marshal]::Copy($bd.Scan0, $raw, 0, $raw.Length)
      $bmp.UnlockBits($bd)

      $andRow = [Math]::Floor(($n + 31) / 32) * 4
      $data = New-Object byte[] (40 + $n * $n * 4 + $andRow * $n)
      $bw = New-Object System.IO.BinaryWriter(New-Object System.IO.MemoryStream(,$data))
      $bw.Write([int32]40); $bw.Write([int32]$n); $bw.Write([int32]($n * 2))
      $bw.Write([int16]1); $bw.Write([int16]32)
      $bw.Write([int32]0); $bw.Write([int32]0)   # BI_RGB, sizeimage
      $bw.Write([int32]0); $bw.Write([int32]0); $bw.Write([int32]0); $bw.Write([int32]0)
      for ($y = $n - 1; $y -ge 0; $y--) {
        $bw.Write($raw, $y * $stride, $n * 4)    # lignes bottom-up
      }
      $bw.Dispose() # AND mask deja a zero (alpha 32bpp fait foi)
    }
    $entries += ,@{ Size = $n; Data = $data }
    $bmp.Dispose()
  }
} finally { $src.Dispose() }

$fs = [System.IO.File]::Create($outPath)
$w = New-Object System.IO.BinaryWriter($fs)
$w.Write([int16]0); $w.Write([int16]1); $w.Write([int16]$entries.Count)
$offset = 6 + 16 * $entries.Count
foreach ($e in $entries) {
  $b = if ($e.Size -eq 256) { 0 } else { $e.Size }
  $w.Write([byte]$b); $w.Write([byte]$b)
  $w.Write([byte]0); $w.Write([byte]0)
  $w.Write([int16]1); $w.Write([int16]32)
  $w.Write([int32]$e.Data.Length); $w.Write([int32]$offset)
  $offset += $e.Data.Length
}
foreach ($e in $entries) { $w.Write($e.Data) }
$w.Dispose()
Write-Output "OK -> $outPath ($((Get-Item $outPath).Length) octets)"
