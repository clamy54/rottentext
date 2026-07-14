# Lance RottenText.exe, tape optionnellement du texte, et capture UNIQUEMENT
# la fenetre de l'app (via PrintWindow) -> jamais le plein ecran.
#
# Usage:
#   powershell -File scripts\screenshot.ps1 [-Text "..."] [-Out scripts\out.png] [-KeepOpen]
# SendKeys: {ENTER}=nouvelle ligne, ^n=Ctrl+N, {UP} etc. Eviter { } = ; litteraux.

param(
  [string]$Text = "",
  [string]$Out = "scripts\out.png",
  [switch]$KeepOpen
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms
Add-Type @"
using System;using System.Runtime.InteropServices;
public class Cap {
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr hdc, uint flags);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern int GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr p);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  public delegate bool EnumProc(IntPtr h, IntPtr p);
  public struct RECT { public int Left, Top, Right, Bottom; }
  // la plus grande fenetre visible du process = la fenetre principale
  public static IntPtr Find(uint t){IntPtr b=IntPtr.Zero;int ba=0;EnumWindows((h,p)=>{uint pid;GetWindowThreadProcessId(h,out pid);if(pid==t&&IsWindowVisible(h)){RECT r;GetWindowRect(h,out r);int a=(r.Right-r.Left)*(r.Bottom-r.Top);if(a>ba){ba=a;b=h;}}return true;},IntPtr.Zero);return b;}
}
"@

$root = Split-Path $PSScriptRoot -Parent
$exe = Join-Path $root "RottenText.exe"
$p = Start-Process $exe -PassThru
Start-Sleep -Seconds 2
$h = [Cap]::Find([uint32]$p.Id)
[void][Cap]::SetForegroundWindow($h); Start-Sleep -Milliseconds 400
if ($Text -ne "") {
  [System.Windows.Forms.SendKeys]::SendWait($Text)
  Start-Sleep -Milliseconds 400
}
$r = New-Object Cap+RECT; [void][Cap]::GetWindowRect($h, [ref]$r)
$w = [int]$r.Right - [int]$r.Left; $ht = [int]$r.Bottom - [int]$r.Top
$bmp = New-Object System.Drawing.Bitmap $w, $ht
$g = [System.Drawing.Graphics]::FromImage($bmp)
$hdc = $g.GetHdc(); [void][Cap]::PrintWindow($h, $hdc, 2); $g.ReleaseHdc($hdc)
if (-not [System.IO.Path]::IsPathRooted($Out)) { $Out = Join-Path $root $Out }
$bmp.Save($Out, [System.Drawing.Imaging.ImageFormat]::Png)
$g.Dispose(); $bmp.Dispose()
Write-Output "saved $Out ($w x $ht)"
if (-not $KeepOpen) { Stop-Process -Id $p.Id -Force }
