unit uNmap;

{$mode objfpc}{$H+}

// Constructeur de ligne de commande nmap.

interface

type
  TNmapScan = (nsSyn, nsConnect, nsUdp, nsPing, nsList);
  TNmapOpts = record
    Target: string;
    Scan: TNmapScan;
    Ports: string;       // '' / '22,80' / '1-1000' / '-' (tout) / 'top:1000'
    SvcVersion: Boolean;
    OsDetect: Boolean;
    DefScripts: Boolean;
    Aggressive: Boolean;
    NoPing: Boolean;
    OnlyOpen: Boolean;
    Verbose: Boolean;
    Timing: Integer;     // 0..5 -> -T0..-T5 ; hors 0..5 = pas d'option
  end;

function BuildNmap(const O: TNmapOpts): string;

implementation

uses
  SysUtils;

function PortsArg(const P: string): string;
var
  s, digits: string;
  i: Integer;
begin
  Result := '';
  s := Trim(P);
  if s = '' then Exit;
  if s = '-' then Exit('-p-');
  if LowerCase(Copy(s, 1, 3)) = 'top' then
  begin
    digits := '';
    for i := 1 to Length(s) do
      if s[i] in ['0'..'9'] then digits := digits + s[i];
    if digits <> '' then Exit('--top-ports ' + digits);
    Exit('');
  end;
  Result := '-p ' + s;
end;

function BuildNmap(const O: TNmapOpts): string;
var
  parts, pa: string;
  portScan: Boolean;
begin
  parts := 'nmap';
  case O.Scan of
    nsSyn:     parts := parts + ' -sS';
    nsConnect: parts := parts + ' -sT';
    nsUdp:     parts := parts + ' -sU';
    nsPing:    parts := parts + ' -sn';
    nsList:    parts := parts + ' -sL';
  end;
  portScan := O.Scan in [nsSyn, nsConnect, nsUdp];
  if O.NoPing and (O.Scan <> nsList) then parts := parts + ' -Pn';
  if portScan then
  begin
    pa := PortsArg(O.Ports);
    if pa <> '' then parts := parts + ' ' + pa;
    if O.Aggressive then
      parts := parts + ' -A'
    else
    begin
      if O.SvcVersion then parts := parts + ' -sV';
      if O.OsDetect then parts := parts + ' -O';
      if O.DefScripts then parts := parts + ' -sC';
    end;
    if O.OnlyOpen then parts := parts + ' --open';
  end;
  if O.Verbose then parts := parts + ' -v';
  if (O.Timing >= 0) and (O.Timing <= 5) then
    parts := parts + ' -T' + IntToStr(O.Timing);
  parts := parts + ' ' + Trim(O.Target);
  Result := parts;
end;

end.
