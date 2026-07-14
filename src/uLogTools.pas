unit uLogTools;

{$mode objfpc}{$H+}

// Outils logs : Normalize / Sort / Merge / Deltas / Summary. Une ligne sans
// timestamp COLLE a la ligne datee qui precede (une stack trace suit son
// erreur). Regroupements = HEURISTIQUE, annoncee dans le rapport.
// local<->UTC a l'offset courant : pas de DST historique.

interface

uses
  Classes, SysUtils, DateUtils;

function FindLineStamp(const ALine: string; out APos, ALen: Integer;
  out AUtc: TDateTime): Boolean;

function LogNormalize(const S: string): string;
function LogSort(const S: string): string;
function LogMerge(const A, B: string): string;
function LogDeltas(const S: string): string;
function LogSummary(const S: string): string;

implementation

const
  MONTHS: array[1..12] of string =
    ('jan', 'feb', 'mar', 'apr', 'may', 'jun',
     'jul', 'aug', 'sep', 'oct', 'nov', 'dec');
  MAX_KEYS = 50000; // plafond d'entrees uniques par compteur
  TOP_N = 10;

function IsDig(c: Char): Boolean; inline;
begin
  Result := c in ['0'..'9'];
end;

function IsAlnumC(c: Char): Boolean; inline;
begin
  Result := c in ['A'..'Z', 'a'..'z', '0'..'9'];
end;

function MonthOf3(const S3: string): Integer;
var
  i: Integer;
  l: string;
begin
  Result := 0;
  l := LowerCase(S3);
  for i := 1 to 12 do
    if l = MONTHS[i] then Exit(i);
end;

function IsoLocal(UTC: TDateTime): string;
var
  bias, disp: Integer;
  sign: Char;
begin
  bias := GetLocalTimeOffset; // minutes : UTC = local + bias
  disp := -bias;
  if disp >= 0 then sign := '+' else sign := '-';
  Result := FormatDateTime('yyyy-mm-dd"T"hh:nn:ss', UniversalTimeToLocal(UTC)) +
    Format('%s%.2d:%.2d', [sign, Abs(disp) div 60, Abs(disp) mod 60]);
end;

function DigitsAt(const S: string; i, n: Integer): Boolean;
var
  k: Integer;
begin
  Result := False;
  if (i < 1) or (i + n - 1 > Length(S)) then Exit;
  for k := i to i + n - 1 do
    if not IsDig(S[k]) then Exit;
  Result := True;
end;

function NumAt(const S: string; i, n: Integer): Integer;
var
  k: Integer;
begin
  Result := 0;
  for k := i to i + n - 1 do
    Result := Result * 10 + Ord(S[k]) - Ord('0');
end;

function TryISO(const S: string; i: Integer; out ALen: Integer;
  out AUtc: TDateTime): Boolean;
var
  j, y, mo, d, hh, nn, ss, zh, zm, zsign, ms, fracStart: Integer;
  hasZone, utcz: Boolean;
  frac: string;
  dt: TDateTime;
begin
  Result := False;
  if not (DigitsAt(S, i, 4) and (i + 9 <= Length(S)) and (S[i + 4] = '-') and
          DigitsAt(S, i + 5, 2) and (S[i + 7] = '-') and DigitsAt(S, i + 8, 2) and
          ((i = 1) or not IsAlnumC(S[i - 1]))) then Exit;
  y := NumAt(S, i, 4); mo := NumAt(S, i + 5, 2); d := NumAt(S, i + 8, 2);
  j := i + 10;
  hh := 0; nn := 0; ss := 0; ms := 0;
  hasZone := False; utcz := False; zh := 0; zm := 0; zsign := 1;
  if (j <= Length(S)) and (S[j] in ['T', ' ']) and DigitsAt(S, j + 1, 2) and
     (j + 3 <= Length(S)) and (S[j + 3] = ':') and DigitsAt(S, j + 4, 2) then
  begin
    hh := NumAt(S, j + 1, 2); nn := NumAt(S, j + 4, 2);
    j := j + 6;
    if (j <= Length(S)) and (S[j] = ':') and DigitsAt(S, j + 1, 2) then
    begin
      ss := NumAt(S, j + 1, 2);
      j := j + 3;
    end;
    if (j <= Length(S)) and (S[j] = '.') and DigitsAt(S, j + 1, 1) then
    begin
      Inc(j);
      fracStart := j;
      while (j <= Length(S)) and IsDig(S[j]) do Inc(j);
      // ms = 3 premiers chiffres, completes a droite (sinon .010 et .980 egaux)
      frac := Copy(S, fracStart, j - fracStart);
      while Length(frac) < 3 do frac := frac + '0';
      ms := NumAt(frac, 1, 3);
    end;
    if (j <= Length(S)) and (S[j] in ['Z', 'z']) then
    begin
      hasZone := True; utcz := True; Inc(j);
    end
    else if (j <= Length(S)) and (S[j] in ['+', '-']) and DigitsAt(S, j + 1, 2) then
    begin
      hasZone := True;
      if S[j] = '-' then zsign := -1;
      zh := NumAt(S, j + 1, 2);
      if (j + 3 <= Length(S)) and (S[j + 3] = ':') and DigitsAt(S, j + 4, 2) then
      begin zm := NumAt(S, j + 4, 2); j := j + 6; end
      else if DigitsAt(S, j + 3, 2) then
      begin zm := NumAt(S, j + 3, 2); j := j + 5; end
      else
        j := j + 3;
    end;
  end;
  // zone explicite invalide = rejet, on n'invente pas un "local"
  if ((j <= Length(S)) and IsDig(S[j])) or
     (hasZone and ((zh > 23) or (zm > 59))) or
     not TryEncodeDateTime(y, mo, d, hh, nn, ss, ms, dt) then Exit;
  if hasZone then
  begin
    if utcz then AUtc := dt
    else AUtc := dt - zsign * (zh * 60 + zm) / (24 * 60);
  end
  else
    AUtc := LocalTimeToUniversal(dt);
  ALen := j - i;
  Result := True;
end;

function TryCLF(const S: string; i: Integer; out ALen: Integer;
  out AUtc: TDateTime): Boolean;
var
  j, d, mo, y, hh, nn, ss, zh, zm, zsign, dlen: Integer;
  hasZone: Boolean;
  dt: TDateTime;
begin
  Result := False;
  if not (IsDig(S[i]) and ((i = 1) or not IsAlnumC(S[i - 1]))) then Exit;
  dlen := 1;
  if DigitsAt(S, i + 1, 1) then dlen := 2;
  j := i + dlen;
  if not ((j + 17 <= Length(S)) and (S[j] = '/') and
          (MonthOf3(Copy(S, j + 1, 3)) > 0) and (S[j + 4] = '/') and
          DigitsAt(S, j + 5, 4) and (S[j + 9] = ':') and DigitsAt(S, j + 10, 2) and
          (S[j + 12] = ':') and DigitsAt(S, j + 13, 2) and (S[j + 15] = ':') and
          DigitsAt(S, j + 16, 2)) then Exit;
  d := NumAt(S, i, dlen);
  mo := MonthOf3(Copy(S, j + 1, 3));
  y := NumAt(S, j + 5, 4);
  hh := NumAt(S, j + 10, 2); nn := NumAt(S, j + 13, 2); ss := NumAt(S, j + 16, 2);
  j := j + 18;
  hasZone := False; zsign := 1; zh := 0; zm := 0;
  if (j <= Length(S)) and (S[j] = ' ') and (j + 1 <= Length(S)) and
     (S[j + 1] in ['+', '-']) and DigitsAt(S, j + 2, 4) then
  begin
    hasZone := True;
    if S[j + 1] = '-' then zsign := -1;
    zh := NumAt(S, j + 2, 2);
    zm := NumAt(S, j + 4, 2);
    j := j + 6;
  end;
  // zone explicite invalide = rejet
  if (hasZone and ((zh > 23) or (zm > 59))) or
     not TryEncodeDateTime(y, mo, d, hh, nn, ss, 0, dt) then Exit;
  if hasZone then AUtc := dt - zsign * (zh * 60 + zm) / (24 * 60)
  else AUtc := LocalTimeToUniversal(dt);
  ALen := j - i;
  Result := True;
end;

function TrySyslog(const S: string; i: Integer; out ALen: Integer;
  out AUtc: TDateTime): Boolean;
var
  j, mo, d, hh, nn, ss, y: Integer;
  dt: TDateTime;
begin
  Result := False;
  if not ((i + 10 <= Length(S)) and (S[i] in ['A'..'Z', 'a'..'z']) and
          ((i = 1) or not IsAlnumC(S[i - 1])) and
          (S[i + 1] in ['A'..'Z', 'a'..'z']) and
          (S[i + 2] in ['A'..'Z', 'a'..'z']) and (S[i + 3] = ' ') and
          (MonthOf3(Copy(S, i, 3)) > 0)) then Exit;
  mo := MonthOf3(Copy(S, i, 3));
  j := i + 4;
  if (j <= Length(S)) and (S[j] = ' ') then Inc(j); // jour padde 'Jan  5'
  if not ((j <= Length(S)) and IsDig(S[j])) then Exit;
  d := Ord(S[j]) - Ord('0');
  Inc(j);
  if (j <= Length(S)) and IsDig(S[j]) then
  begin
    d := d * 10 + Ord(S[j]) - Ord('0');
    Inc(j);
  end;
  if not ((j + 8 <= Length(S)) and (S[j] = ' ') and DigitsAt(S, j + 1, 2) and
          (S[j + 3] = ':') and DigitsAt(S, j + 4, 2) and (S[j + 6] = ':') and
          DigitsAt(S, j + 7, 2)) then Exit;
  hh := NumAt(S, j + 1, 2); nn := NumAt(S, j + 4, 2); ss := NumAt(S, j + 7, 2);
  y := YearOf(Now); // RFC3164 : pas d'annee dans le format
  if not TryEncodeDateTime(y, mo, d, hh, nn, ss, 0, dt) then Exit;
  AUtc := LocalTimeToUniversal(dt);
  ALen := (j + 9) - i;
  Result := True;
end;

function TryUnix(const S: string; i: Integer; out ALen: Integer;
  out AUtc: TDateTime): Boolean;
var
  j, len: Integer;
  v: Int64;
begin
  Result := False;
  if not (IsDig(S[i]) and ((i = 1) or not IsAlnumC(S[i - 1]))) then Exit;
  j := i;
  while (j <= Length(S)) and IsDig(S[j]) do Inc(j);
  len := j - i;
  if ((j <= Length(S)) and IsAlnumC(S[j])) or
     ((len <> 10) and (len <> 13)) then Exit;
  v := StrToInt64Def(Copy(S, i, len), -1);
  if v <= 0 then Exit;
  if len = 13 then
    AUtc := UnixToDateTime(v div 1000) + (v mod 1000) / 86400000.0
  else
    AUtc := UnixToDateTime(v);
  ALen := len;
  Result := True;
end;

function FindLineStamp(const ALine: string; out APos, ALen: Integer;
  out AUtc: TDateTime): Boolean;
var
  i: Integer;
begin
  Result := False;
  APos := 0; ALen := 0; AUtc := 0;
  for i := 1 to Length(ALine) do
  begin
    // formats structures d'abord : leurs chiffres ne doivent pas matcher unix
    if TryISO(ALine, i, ALen, AUtc) or TryCLF(ALine, i, ALen, AUtc) or
       TrySyslog(ALine, i, ALen, AUtc) or TryUnix(ALine, i, ALen, AUtc) then
    begin
      APos := i;
      Exit(True);
    end;
  end;
end;

function SplitLines(const S: string): TStringList;
begin
  Result := TStringList.Create;
  Result.TextLineBreakStyle := tlbsLF;
  Result.Text := S;
end;

type
  TLogRec = record
    Start, Count: Integer; // lignes [Start .. Start+Count-1] de la source
    HasT: Boolean;
    Utc: TDateTime;
    Src: Integer;  // 0 = buffer, 1 = fichier (merge)
    Ord_: Integer;
  end;
  TLogRecs = array of TLogRec;

procedure BuildRecs(ALines: TStringList; ASrc: Integer; var ARecs: TLogRecs);
var
  i, p, l, n: Integer;
  utc: TDateTime;
begin
  for i := 0 to ALines.Count - 1 do
    if FindLineStamp(ALines[i], p, l, utc) then
    begin
      n := Length(ARecs);
      SetLength(ARecs, n + 1);
      ARecs[n].Start := i;
      ARecs[n].Count := 1;
      ARecs[n].HasT := True;
      ARecs[n].Utc := utc;
      ARecs[n].Src := ASrc;
      ARecs[n].Ord_ := n;
    end
    else
    begin
      n := Length(ARecs);
      // sans le test de source, l'entete de B collerait au dernier record de A
      // (Src=0) -> lecture hors bornes a l'emission
      if (n = 0) or (ARecs[n - 1].Src <> ASrc) then
      begin
        SetLength(ARecs, n + 1);
        ARecs[n].Start := i;
        ARecs[n].Count := 1;
        ARecs[n].HasT := False;
        ARecs[n].Utc := 0;
        ARecs[n].Src := ASrc;
        ARecs[n].Ord_ := n;
      end
      else
        Inc(ARecs[n - 1].Count);
    end;
end;

// ordre TOTAL (le quicksort est donc stable de fait)
function RecLess(const A, B: TLogRec): Boolean;
begin
  if A.HasT <> B.HasT then Exit(not A.HasT);
  if A.HasT and (A.Utc <> B.Utc) then Exit(A.Utc < B.Utc);
  if A.Src <> B.Src then Exit(A.Src < B.Src);
  Result := A.Ord_ < B.Ord_;
end;

procedure SortRecs(var R: TLogRecs; ALo, AHi: Integer);
var
  i, j: Integer;
  p, t: TLogRec;
begin
  while ALo < AHi do
  begin
    i := ALo; j := AHi;
    p := R[(ALo + AHi) div 2];
    repeat
      while RecLess(R[i], p) do Inc(i);
      while RecLess(p, R[j]) do Dec(j);
      if i <= j then
      begin
        t := R[i]; R[i] := R[j]; R[j] := t;
        Inc(i); Dec(j);
      end;
    until i > j;
    if j - ALo < AHi - i then
    begin
      SortRecs(R, ALo, j);
      ALo := i;
    end
    else
    begin
      SortRecs(R, i, AHi);
      AHi := j;
    end;
  end;
end;

function LogNormalize(const S: string): string;
var
  lines, outp: TStringList;
  i, p, l: Integer;
  utc: TDateTime;
  ln: string;
begin
  lines := SplitLines(S);
  outp := TStringList.Create;
  outp.TextLineBreakStyle := tlbsLF;
  try
    for i := 0 to lines.Count - 1 do
    begin
      ln := lines[i];
      if FindLineStamp(ln, p, l, utc) then
        outp.Add(Copy(ln, 1, p - 1) + IsoLocal(utc) + Copy(ln, p + l, MaxInt))
      else
        outp.Add(ln);
    end;
    Result := outp.Text;
  finally
    lines.Free; outp.Free;
  end;
end;

function EmitRecs(ALines, BLines: TStringList; const R: TLogRecs): string;
var
  outp: TStringList;
  i, k: Integer;
  src: TStringList;
begin
  outp := TStringList.Create;
  outp.TextLineBreakStyle := tlbsLF;
  try
    for i := 0 to High(R) do
    begin
      if R[i].Src = 0 then src := ALines else src := BLines;
      for k := R[i].Start to R[i].Start + R[i].Count - 1 do
        outp.Add(src[k]);
    end;
    Result := outp.Text;
  finally
    outp.Free;
  end;
end;

function LogSort(const S: string): string;
var
  lines: TStringList;
  recs: TLogRecs;
begin
  lines := SplitLines(S);
  try
    recs := nil;
    BuildRecs(lines, 0, recs);
    if Length(recs) > 1 then
      SortRecs(recs, 0, High(recs));
    Result := EmitRecs(lines, nil, recs);
  finally
    lines.Free;
  end;
end;

function LogMerge(const A, B: string): string;
var
  la, lb: TStringList;
  recs: TLogRecs;
begin
  la := SplitLines(A);
  lb := SplitLines(B);
  try
    recs := nil;
    BuildRecs(la, 0, recs);
    BuildRecs(lb, 1, recs);
    if Length(recs) > 1 then
      SortRecs(recs, 0, High(recs));
    Result := EmitRecs(la, lb, recs);
  finally
    la.Free; lb.Free;
  end;
end;

function LogDeltas(const S: string): string;
var
  lines, outp: TStringList;
  i, p, l: Integer;
  utc, prev: TDateTime;
  hasPrev: Boolean;
  ms: Int64;
  sign: string;
begin
  lines := SplitLines(S);
  outp := TStringList.Create;
  outp.TextLineBreakStyle := tlbsLF;
  try
    hasPrev := False;
    prev := 0;
    for i := 0 to lines.Count - 1 do
      if FindLineStamp(lines[i], p, l, utc) then
      begin
        if not hasPrev then
          ms := 0
        else
          ms := MilliSecondsBetween(prev, utc);
        if hasPrev and (utc < prev) then sign := '-' else sign := '+';
        outp.Add(Format('[%s%d.%.3ds] ', [sign, ms div 1000, ms mod 1000])
          + lines[i]);
        prev := utc;
        hasPrev := True;
      end
      else
        outp.Add(lines[i]);
    Result := outp.Text;
  finally
    lines.Free; outp.Free;
  end;
end;

// compteur : Objects = nb d'occurrences
procedure CountKey(AMap: TStringList; const AKey: string; var ADropped: Integer);
var
  idx: Integer;
begin
  if AMap.Find(AKey, idx) then
    AMap.Objects[idx] := TObject(PtrInt(AMap.Objects[idx]) + 1)
  else if AMap.Count < MAX_KEYS then
    AMap.AddObject(AKey, TObject(PtrInt(1)))
  else
    Inc(ADropped);
end;

procedure AppendTop(AOut: TStringList; AMap: TStringList; const ATitle: string;
  ADropped: Integer);
var
  i, k, best, total: Integer;
  used: array of Boolean;
begin
  AOut.Add(ATitle);
  if AMap.Count = 0 then
  begin
    AOut.Add('  (none)');
    Exit;
  end;
  total := 0;
  for i := 0 to AMap.Count - 1 do
    Inc(total, PtrInt(AMap.Objects[i]));
  SetLength(used, AMap.Count);
  for k := 1 to TOP_N do
  begin
    best := -1;
    for i := 0 to AMap.Count - 1 do
      if not used[i] then
        if (best < 0) or (PtrInt(AMap.Objects[i]) > PtrInt(AMap.Objects[best])) then
          best := i;
    if best < 0 then Break;
    used[best] := True;
    AOut.Add(Format('  %6dx  %s', [PtrInt(AMap.Objects[best]), AMap[best]]));
  end;
  if AMap.Count > TOP_N then
    AOut.Add(Format('  (%d unique, %d total)', [AMap.Count, total]))
  else
    AOut.Add(Format('  (%d total)', [total]));
  if ADropped > 0 then
    AOut.Add(Format('  (counter capped at %d keys, %d occurrences dropped)',
      [MAX_KEYS, ADropped]));
end;

procedure CountIPs(const L: string; AMap: TStringList; var ADropped: Integer);
var
  i, j, o, oc, dots: Integer;
  ok: Boolean;
  start: Integer;
begin
  i := 1;
  while i <= Length(L) do
  begin
    if IsDig(L[i]) and ((i = 1) or not (IsAlnumC(L[i - 1]) or (L[i - 1] = '.'))) then
    begin
      j := i;
      dots := 0;
      ok := True;
      start := i;
      while True do
      begin
        o := 0; oc := 0;
        while (j <= Length(L)) and IsDig(L[j]) and (oc < 3) do
        begin
          o := o * 10 + Ord(L[j]) - Ord('0');
          Inc(oc); Inc(j);
        end;
        if (oc = 0) or (o > 255) or ((j <= Length(L)) and IsDig(L[j])) then
        begin
          ok := False;
          Break;
        end;
        if dots = 3 then Break;
        if (j <= Length(L)) and (L[j] = '.') then
        begin
          Inc(dots); Inc(j);
        end
        else
        begin
          ok := False;
          Break;
        end;
      end;
      // rejette le '1.2.3.4' d'un '1.2.3.4.5'
      if ok and (dots = 3) and
         ((j > Length(L)) or not (IsAlnumC(L[j]) or
          ((L[j] = '.') and (j + 1 <= Length(L)) and IsDig(L[j + 1])))) then
      begin
        CountKey(AMap, Copy(L, start, j - start), ADropped);
        i := j;
        Continue;
      end;
    end;
    Inc(i);
  end;
end;

// status = `" NNN` apres la requete quotee (access log CLF/combined)
function StatusOnLine(const L: string): Integer;
var
  i, v: Integer;
begin
  Result := 0;
  for i := 1 to Length(L) - 4 do
    if (L[i] = '"') and (L[i + 1] = ' ') and DigitsAt(L, i + 2, 3) and
       ((i + 5 > Length(L)) or not IsAlnumC(L[i + 5])) then
    begin
      v := NumAt(L, i + 2, 3);
      if (v >= 100) and (v <= 599) then Exit(v);
    end;
end;

// 3 = fatal, 2 = error, 1 = warning
function SeverityOf(const U: string): Integer;

  function HasWord(const W: string): Boolean;
  var
    p, e: Integer;
  begin
    Result := False;
    p := 1;
    repeat
      p := Pos(W, U, p);
      if p = 0 then Exit;
      e := p + Length(W);
      if ((p = 1) or not IsAlnumC(U[p - 1])) and
         ((e > Length(U)) or not IsAlnumC(U[e])) then Exit(True);
      p := e;
    until False;
  end;

begin
  if HasWord('FATAL') or HasWord('CRIT') or HasWord('CRITICAL') or
     HasWord('ALERT') or HasWord('EMERG') or HasWord('PANIC') then Exit(3);
  if HasWord('ERROR') or HasWord('ERR') or HasWord('SEVERE') or
     HasWord('FAIL') or HasWord('FAILED') or HasWord('FAILURE') then Exit(2);
  if HasWord('WARN') or HasWord('WARNING') then Exit(1);
  Result := 0;
end;

// suites de chiffres -> '#' : pid/port/duree ne separent pas deux occurrences
function ErrorKey(const L: string; ATsPos, ATsLen: Integer): string;
var
  s: string;
  i: Integer;
  lastDig: Boolean;
begin
  if ATsLen > 0 then
    s := Copy(L, 1, ATsPos - 1) + Copy(L, ATsPos + ATsLen, MaxInt)
  else
    s := L;
  s := Trim(s);
  Result := '';
  lastDig := False;
  for i := 1 to Length(s) do
    if IsDig(s[i]) then
    begin
      if not lastDig then Result := Result + '#';
      lastDig := True;
    end
    else
    begin
      Result := Result + s[i];
      lastDig := False;
    end;
  if Length(Result) > 200 then Result := Copy(Result, 1, 197) + '...';
end;

function LogSummary(const S: string): string;
var
  lines, outp, ips, errs, stats: TStringList;
  i, p, l, st, sev, stamped: Integer;
  nFatal, nErr, nWarn: Integer;
  dropIp, dropErr, dropSt: Integer;
  utc, tFirst, tLast: TDateTime;
  hasT: Boolean;
  ln: string;
  secs: Int64;
  cls: array[1..5] of Integer;
begin
  lines := SplitLines(S);
  outp := TStringList.Create;
  outp.TextLineBreakStyle := tlbsLF;
  ips := TStringList.Create;
  ips.Sorted := True; ips.CaseSensitive := True;
  errs := TStringList.Create;
  errs.Sorted := True; errs.CaseSensitive := True;
  stats := TStringList.Create;
  stats.Sorted := True;
  try
    stamped := 0;
    nFatal := 0; nErr := 0; nWarn := 0;
    dropIp := 0; dropErr := 0; dropSt := 0;
    tFirst := 0; tLast := 0;
    hasT := False;
    FillChar(cls, SizeOf(cls), 0);
    for i := 0 to lines.Count - 1 do
    begin
      ln := lines[i];
      if FindLineStamp(ln, p, l, utc) then
      begin
        Inc(stamped);
        if not hasT then
        begin
          tFirst := utc; tLast := utc; hasT := True;
        end
        else
        begin
          if utc < tFirst then tFirst := utc;
          if utc > tLast then tLast := utc;
        end;
      end
      else
      begin
        p := 0; l := 0;
      end;
      CountIPs(ln, ips, dropIp);
      st := StatusOnLine(ln);
      if st > 0 then
      begin
        CountKey(stats, IntToStr(st), dropSt);
        Inc(cls[st div 100]);
      end;
      sev := SeverityOf(UpperCase(ln));
      case sev of
        3: Inc(nFatal);
        2: Inc(nErr);
        1: Inc(nWarn);
      end;
      if sev >= 2 then
        CountKey(errs, ErrorKey(ln, p, l), dropErr);
    end;

    outp.Add('=== Log summary ===');
    outp.Add(Format('lines: %d (%d with a recognized timestamp)',
      [lines.Count, stamped]));
    if hasT then
    begin
      secs := Abs(SecondsBetween(tFirst, tLast));
      outp.Add('first: ' + IsoLocal(tFirst));
      outp.Add('last:  ' + IsoLocal(tLast));
      outp.Add(Format('span:  %dd %.2d:%.2d:%.2d',
        [secs div 86400, (secs mod 86400) div 3600, (secs mod 3600) div 60,
         secs mod 60]));
    end;
    outp.Add(Format('severity lines: fatal/crit %d, error %d, warning %d'
      + ' (word match, heuristic)', [nFatal, nErr, nWarn]));
    outp.Add('');
    AppendTop(outp, stats, '=== Top HTTP status codes ("..." NNN) ===', dropSt);
    if cls[2] + cls[3] + cls[4] + cls[5] > 0 then
      outp.Add(Format('  by class: 2xx %d, 3xx %d, 4xx %d, 5xx %d',
        [cls[2], cls[3], cls[4], cls[5]]));
    outp.Add('');
    AppendTop(outp, ips, '=== Top IPv4 addresses ===', dropIp);
    outp.Add('');
    AppendTop(outp, errs,
      '=== Top repeated errors (timestamp stripped, digit runs -> #) ===',
      dropErr);
    Result := outp.Text;
  finally
    lines.Free; outp.Free; ips.Free; errs.Free; stats.Free;
  end;
end;

end.
