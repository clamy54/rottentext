unit uExtract;

{$mode objfpc}{$H+}

// Extraction de motifs ops (IPv4, URL, email, UUID, hash, hostname).
// Scanners lineaires, pas de regex (ReDoS). Hostnames = HEURISTIQUE, un nom de
// fichier 'settings.json' matche aussi (annonce dans le titre de section).

interface

type
  TExtractKind = (ekIPv4, ekURL, ekEmail, ekUUID, ekHash, ekHost);
  TExtractKinds = set of TExtractKind;

function ExtractReport(const S: string; AKinds: TExtractKinds): string;

implementation

uses
  Classes, SysUtils;

function IsDigit(c: Char): Boolean; inline;
begin
  Result := c in ['0'..'9'];
end;

function IsHexCh(c: Char): Boolean; inline;
begin
  Result := c in ['0'..'9', 'a'..'f', 'A'..'F'];
end;

function IsAlpha(c: Char): Boolean; inline;
begin
  Result := c in ['A'..'Z', 'a'..'z'];
end;

function IsAlnum(c: Char): Boolean; inline;
begin
  Result := c in ['A'..'Z', 'a'..'z', '0'..'9'];
end;

// compteur : Objects = nb d'occurrences
procedure Bump(L: TStringList; const V: string);
var
  i: Integer;
begin
  if L.Find(V, i) then
    L.Objects[i] := TObject(PtrInt(L.Objects[i]) + 1)
  else
    L.AddObject(V, TObject(PtrInt(1)));
end;

{ ---- scanners ---- }

procedure ScanIPv4(const S: string; L: TStringList);
var
  i, j, oct, val, start: Integer;
  ok: Boolean;
begin
  i := 1;
  while i <= Length(S) do
  begin
    if IsDigit(S[i]) and
       ((i = 1) or not (IsAlnum(S[i - 1]) or (S[i - 1] = '.'))) then
    begin
      start := i;
      j := i;
      ok := True;
      for oct := 1 to 4 do
      begin
        val := 0;
        if (j > Length(S)) or not IsDigit(S[j]) then begin ok := False; Break; end;
        while (j <= Length(S)) and IsDigit(S[j]) and (j - i < 3) do
        begin
          val := val * 10 + (Ord(S[j]) - Ord('0'));
          Inc(j);
        end;
        if (val > 255) or ((j <= Length(S)) and IsDigit(S[j])) then
          begin ok := False; Break; end;
        if oct < 4 then
        begin
          if (j > Length(S)) or (S[j] <> '.') then begin ok := False; Break; end;
          Inc(j);
          i := j; // borne "3 chiffres" relative au debut de l'octet
        end;
      end;
      // rejette '1.2.3.4abc' et le '1.2.3.4' d'un '1.2.3.4.5'
      if ok and (j <= Length(S)) and
         (IsAlnum(S[j]) or
          ((S[j] = '.') and (j < Length(S)) and IsDigit(S[j + 1]))) then
        ok := False;
      if ok then
      begin
        Bump(L, Copy(S, start, j - start));
        i := j;
        Continue;
      end;
      i := start + 1;
    end
    else
      Inc(i);
  end;
end;

procedure ScanUUID(const S: string; L: TStringList);
const
  GROUPS: array[0..4] of Integer = (8, 4, 4, 4, 12);
var
  i, j, g, k: Integer;
  ok: Boolean;
begin
  i := 1;
  while i <= Length(S) do
  begin
    if IsHexCh(S[i]) and
       ((i = 1) or not (IsAlnum(S[i - 1]) or (S[i - 1] = '-'))) then
    begin
      j := i;
      ok := True;
      for g := 0 to 4 do
      begin
        for k := 1 to GROUPS[g] do
        begin
          if (j > Length(S)) or not IsHexCh(S[j]) then begin ok := False; Break; end;
          Inc(j);
        end;
        if not ok then Break;
        if g < 4 then
        begin
          if (j > Length(S)) or (S[j] <> '-') then begin ok := False; Break; end;
          Inc(j);
        end;
      end;
      if ok and (j <= Length(S)) and (IsAlnum(S[j]) or (S[j] = '-')) then
        ok := False;
      if ok then
      begin
        Bump(L, LowerCase(Copy(S, i, j - i)));
        i := j;
        Continue;
      end;
    end;
    Inc(i);
  end;
end;

procedure ScanHash(const S: string; L: TStringList);
var
  i, j, len: Integer;
begin
  i := 1;
  while i <= Length(S) do
  begin
    if IsHexCh(S[i]) and ((i = 1) or not IsAlnum(S[i - 1])) then
    begin
      j := i;
      while (j <= Length(S)) and IsHexCh(S[j]) do Inc(j);
      len := j - i;
      if ((j > Length(S)) or not IsAlnum(S[j])) and
         ((len = 32) or (len = 40) or (len = 64) or (len = 128)) then
        Bump(L, LowerCase(Copy(S, i, len)));
      i := j;
    end
    else
      Inc(i);
  end;
end;

// TLD alphabetique >= 2 : ecarte les IP et les 'v1.2'
function HostOK(const H: string): Boolean;
var
  i, labStart, labLen: Integer;
  hasDot, hasAlpha, curAlpha: Boolean;
begin
  Result := False;
  if Length(H) < 4 then Exit;   // minimum 'a.bc'
  if (H[1] in ['.', '-']) or (H[Length(H)] in ['.', '-']) then Exit;
  hasDot := False;
  hasAlpha := False;
  curAlpha := True;
  labStart := 1;
  for i := 1 to Length(H) + 1 do
    if (i > Length(H)) or (H[i] = '.') then
    begin
      labLen := i - labStart;
      if (labLen < 1) or (labLen > 63) then Exit;
      if (H[labStart] = '-') or (H[i - 1] = '-') then Exit;
      if i > Length(H) then
      begin
        if (labLen < 2) or not curAlpha then Exit;
      end
      else
        hasDot := True;
      labStart := i + 1;
      curAlpha := True;
    end
    else if IsAlpha(H[i]) then
      hasAlpha := True
    else
      curAlpha := False;
  Result := hasDot and hasAlpha;
end;

procedure ScanHost(const S: string; L: TStringList);
var
  i, j: Integer;
  run: string;
begin
  i := 1;
  while i <= Length(S) do
  begin
    if (IsAlnum(S[i])) and
       ((i = 1) or not (IsAlnum(S[i - 1]) or (S[i - 1] in ['.', '-']))) then
    begin
      j := i;
      while (j <= Length(S)) and (IsAlnum(S[j]) or (S[j] in ['.', '-'])) do Inc(j);
      run := Copy(S, i, j - i);
      while (run <> '') and (run[Length(run)] in ['.', '-']) do
        SetLength(run, Length(run) - 1); // point final de phrase
      if HostOK(run) then Bump(L, LowerCase(run));
      i := j;
    end
    else
      Inc(i);
  end;
end;

procedure ScanURL(const S: string; L: TStringList);
var
  i, p, e, sStart: Integer;
  url: string;
begin
  p := 1;
  while p + 2 <= Length(S) do
  begin
    if (S[p] = ':') and (S[p + 1] = '/') and (S[p + 2] = '/') then
    begin
      sStart := p;
      while (sStart > 1) and
            (IsAlnum(S[sStart - 1]) or (S[sStart - 1] in ['+', '-', '.'])) do
        Dec(sStart);
      if (sStart < p) and IsAlpha(S[sStart]) and (p - sStart <= 12) then
      begin
        e := p + 3;
        while (e <= Length(S)) and (Ord(S[e]) > 32) and
              not (S[e] in ['"', '''', '<', '>', '`']) do
          Inc(e);
        url := Copy(S, sStart, e - sStart);
        while (url <> '') and (url[Length(url)] in ['.', ',', ';', ':', ')', ']', '}', '!', '?']) do
          SetLength(url, Length(url) - 1);
        if Length(url) > p - sStart + 3 then Bump(L, url);
        p := e;
        Continue;
      end;
    end;
    Inc(p);
  end;
end;

procedure ScanEmail(const S: string; L: TStringList);
var
  i, ls, de: Integer;
  dom: string;
begin
  for i := 2 to Length(S) - 3 do
    if S[i] = '@' then
    begin
      ls := i - 1;
      while (ls >= 1) and (S[ls] in ['A'..'Z', 'a'..'z', '0'..'9', '.', '_', '%', '+', '-']) do
        Dec(ls);
      Inc(ls);
      if (ls >= i) or ((ls > 1) and IsAlnum(S[ls - 1])) then Continue;
      de := i + 1;
      while (de <= Length(S)) and (IsAlnum(S[de]) or (S[de] in ['.', '-'])) do
        Inc(de);
      dom := Copy(S, i + 1, de - i - 1);
      while (dom <> '') and (dom[Length(dom)] in ['.', '-']) do
        SetLength(dom, Length(dom) - 1);
      if HostOK(dom) then
        Bump(L, LowerCase(Copy(S, ls, i - ls)) + '@' + LowerCase(dom));
    end;
end;

{ ---- rapport ---- }

function CmpCountDesc(L: TStringList; A, B: Integer): Integer;
var
  ca, cb: PtrInt;
begin
  ca := PtrInt(L.Objects[A]);
  cb := PtrInt(L.Objects[B]);
  if ca <> cb then Result := cb - ca
  else Result := CompareStr(L[A], L[B]);
end;

procedure AddSection(SB: TStringList; const ATitle: string; L: TStringList);
var
  ord_: TStringList;
  i, total: Integer;
begin
  total := 0;
  for i := 0 to L.Count - 1 do
    Inc(total, PtrInt(L.Objects[i]));
  SB.Add(Format('=== %s: %d unique / %d total ===', [ATitle, L.Count, total]));
  if L.Count = 0 then
    SB.Add('  (none)')
  else
  begin
    ord_ := TStringList.Create;   // CustomSort exige une liste non-Sorted
    try
      for i := 0 to L.Count - 1 do
        ord_.AddObject(L[i], L.Objects[i]);
      ord_.CustomSort(@CmpCountDesc);
      for i := 0 to ord_.Count - 1 do
        SB.Add(Format('%6d  %s', [PtrInt(ord_.Objects[i]), ord_[i]]));
    finally
      ord_.Free;
    end;
  end;
  SB.Add('');
end;

function ExtractReport(const S: string; AKinds: TExtractKinds): string;
var
  sb, L: TStringList;
begin
  sb := TStringList.Create;
  L := TStringList.Create;
  try
    L.Sorted := True;
    L.CaseSensitive := True;
    if ekIPv4 in AKinds then
    begin
      ScanIPv4(S, L);
      AddSection(sb, 'IPv4 addresses', L);
      L.Clear;
    end;
    if ekURL in AKinds then
    begin
      ScanURL(S, L);
      AddSection(sb, 'URLs', L);
      L.Clear;
    end;
    if ekEmail in AKinds then
    begin
      ScanEmail(S, L);
      AddSection(sb, 'Email addresses', L);
      L.Clear;
    end;
    if ekUUID in AKinds then
    begin
      ScanUUID(S, L);
      AddSection(sb, 'UUIDs', L);
      L.Clear;
    end;
    if ekHash in AKinds then
    begin
      ScanHash(S, L);
      AddSection(sb, 'Hashes (hex 32/40/64/128)', L);
      L.Clear;
    end;
    if ekHost in AKinds then
    begin
      ScanHost(S, L);
      AddSection(sb, 'Hostnames (heuristic)', L);
      L.Clear;
    end;
    Result := sb.Text;
  finally
    L.Free;
    sb.Free;
  end;
end;

end.
