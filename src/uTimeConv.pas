unit uTimeConv;

{$mode objfpc}{$H+}

// Detection de timestamps dans un texte : unix 10/13 chiffres, ISO 8601,
// Apache CLF, syslog RFC3164 (annee courante supposee). Scanners lineaires,
// pas de regex (ReDoS). local<->UTC a l'offset COURANT : pas de DST historique.

interface

// '' si aucun timestamp reconnu
function TimestampReport(const S: string): string;

implementation

uses
  Classes, SysUtils, DateUtils;

const
  MAXFOUND = 200;
  MONTHS: array[1..12] of string =
    ('jan', 'feb', 'mar', 'apr', 'may', 'jun',
     'jul', 'aug', 'sep', 'oct', 'nov', 'dec');

type
  TFound = record
    UTC: TDateTime;
    Raw: string;
    Kind: string;
    Pos_: Integer;
  end;

function IsDig(c: Char): Boolean; inline;
begin
  Result := c in ['0'..'9'];
end;

function IsAlphaC(c: Char): Boolean; inline;
begin
  Result := c in ['A'..'Z', 'a'..'z'];
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

function IsoUtc(UTC: TDateTime): string;
begin
  Result := FormatDateTime('yyyy-mm-dd"T"hh:nn:ss', UTC) + 'Z';
end;

function IsoLocal(UTC: TDateTime): string;
var
  bias, disp: Integer;
  sign: Char;
begin
  bias := GetLocalTimeOffset;   // minutes : UTC = local + bias
  disp := -bias;
  if disp >= 0 then sign := '+' else sign := '-';
  Result := FormatDateTime('yyyy-mm-dd"T"hh:nn:ss', UniversalTimeToLocal(UTC)) +
    Format('%s%.2d:%.2d', [sign, Abs(disp) div 60, Abs(disp) mod 60]);
end;

function TimestampReport(const S: string): string;
var
  used: array of Boolean;
  found: array of TFound;
  nf: Integer;

  function DigitsAt(i, n: Integer): Boolean;
  var
    k: Integer;
  begin
    Result := False;
    if (i < 1) or (i + n - 1 > Length(S)) then Exit;
    for k := i to i + n - 1 do
      if not IsDig(S[k]) then Exit;
    Result := True;
  end;

  function NumAt(i, n: Integer): Integer;
  var
    k: Integer;
  begin
    Result := 0;
    for k := i to i + n - 1 do
      Result := Result * 10 + Ord(S[k]) - Ord('0');
  end;

  function SpanFree(p, len: Integer): Boolean;
  var
    k: Integer;
  begin
    Result := False;
    for k := p to p + len - 1 do
      if used[k - 1] then Exit;
    Result := True;
  end;

  procedure MarkUsed(p, len: Integer);
  var
    k: Integer;
  begin
    for k := p to p + len - 1 do
      used[k - 1] := True;
  end;

  procedure AddFound(const F: TFound);
  begin
    if nf >= MAXFOUND then Exit;
    if nf >= Length(found) then SetLength(found, nf + 32);
    found[nf] := F;
    Inc(nf);
  end;

  procedure ScanISO;
  var
    i, j, y, mo, d, hh, nn, ss, zh, zm, zsign, len: Integer;
    hasZone, utcz: Boolean;
    dt: TDateTime;
    f: TFound;
  begin
    i := 1;
    while i + 9 <= Length(S) + 1 do
    begin
      if DigitsAt(i, 4) and (i + 9 <= Length(S)) and (S[i + 4] = '-') and
         DigitsAt(i + 5, 2) and (S[i + 7] = '-') and DigitsAt(i + 8, 2) and
         ((i = 1) or not IsAlnumC(S[i - 1])) then
      begin
        y := NumAt(i, 4); mo := NumAt(i + 5, 2); d := NumAt(i + 8, 2);
        j := i + 10;
        hh := 0; nn := 0; ss := 0;
        hasZone := False; utcz := False; zh := 0; zm := 0; zsign := 1;
        if (j <= Length(S)) and (S[j] in ['T', ' ']) and DigitsAt(j + 1, 2) and
           (j + 3 <= Length(S)) and (S[j + 3] = ':') and DigitsAt(j + 4, 2) then
        begin
          hh := NumAt(j + 1, 2); nn := NumAt(j + 4, 2);
          j := j + 6;
          if (j <= Length(S)) and (S[j] = ':') and DigitsAt(j + 1, 2) then
          begin
            ss := NumAt(j + 1, 2);
            j := j + 3;
          end;
          if (j <= Length(S)) and (S[j] = '.') and DigitsAt(j + 1, 1) then
          begin
            Inc(j);
            while (j <= Length(S)) and IsDig(S[j]) do Inc(j);
          end;
          if (j <= Length(S)) and (S[j] in ['Z', 'z']) then
          begin
            hasZone := True; utcz := True; Inc(j);
          end
          else if (j <= Length(S)) and (S[j] in ['+', '-']) and DigitsAt(j + 1, 2) then
          begin
            hasZone := True;
            if S[j] = '-' then zsign := -1;
            zh := NumAt(j + 1, 2);
            if (j + 3 <= Length(S)) and (S[j + 3] = ':') and DigitsAt(j + 4, 2) then
            begin zm := NumAt(j + 4, 2); j := j + 6; end
            else if DigitsAt(j + 3, 2) then
            begin zm := NumAt(j + 3, 2); j := j + 5; end
            else
              j := j + 3;
          end;
        end;
        len := j - i;
        // zone explicite invalide (+99:99) = rejet, on n'invente pas un "local"
        if ((j > Length(S)) or not IsDig(S[j])) and
           (not hasZone or ((zh <= 23) and (zm <= 59))) and
           TryEncodeDateTime(y, mo, d, hh, nn, ss, 0, dt) and SpanFree(i, len) then
        begin
          if hasZone then
          begin
            if utcz then f.UTC := dt
            else f.UTC := dt - zsign * (zh * 60 + zm) / (24 * 60);
            f.Kind := 'ISO 8601';
          end
          else
          begin
            f.UTC := LocalTimeToUniversal(dt);
            f.Kind := 'ISO 8601 (local assumed)';
          end;
          f.Raw := Copy(S, i, len);
          f.Pos_ := i;
          AddFound(f);
          MarkUsed(i, len);
          i := i + len;
          Continue;
        end;
      end;
      Inc(i);
    end;
  end;

  procedure ScanApache;
  var
    i, j, d, mo, y, hh, nn, ss, zh, zm, zsign, len, dlen: Integer;
    hasZone: Boolean;
    dt: TDateTime;
    f: TFound;
  begin
    i := 1;
    while i <= Length(S) do
    begin
      if IsDig(S[i]) and ((i = 1) or not IsAlnumC(S[i - 1])) then
      begin
        dlen := 1;
        if DigitsAt(i + 1, 1) then dlen := 2;
        j := i + dlen;
        if (j + 17 <= Length(S)) and (S[j] = '/') and
           (MonthOf3(Copy(S, j + 1, 3)) > 0) and (S[j + 4] = '/') and
           DigitsAt(j + 5, 4) and (S[j + 9] = ':') and DigitsAt(j + 10, 2) and
           (S[j + 12] = ':') and DigitsAt(j + 13, 2) and (S[j + 15] = ':') and
           DigitsAt(j + 16, 2) then
        begin
          d := NumAt(i, dlen);
          mo := MonthOf3(Copy(S, j + 1, 3));
          y := NumAt(j + 5, 4);
          hh := NumAt(j + 10, 2); nn := NumAt(j + 13, 2); ss := NumAt(j + 16, 2);
          j := j + 18;
          hasZone := False; zsign := 1; zh := 0; zm := 0;
          if (j + 5 <= Length(S) + 1) and (j <= Length(S)) and (S[j] = ' ') and
             (j + 1 <= Length(S)) and (S[j + 1] in ['+', '-']) and
             DigitsAt(j + 2, 4) then
          begin
            hasZone := True;
            if S[j + 1] = '-' then zsign := -1;
            zh := NumAt(j + 2, 2);
            zm := NumAt(j + 4, 2);
            j := j + 6;
          end;
          len := j - i;
          // zone explicite invalide = rejet
          if (not hasZone or ((zh <= 23) and (zm <= 59))) and
             TryEncodeDateTime(y, mo, d, hh, nn, ss, 0, dt) and SpanFree(i, len) then
          begin
            if hasZone then f.UTC := dt - zsign * (zh * 60 + zm) / (24 * 60)
            else f.UTC := LocalTimeToUniversal(dt);
            f.Kind := 'Apache CLF';
            f.Raw := Copy(S, i, len);
            f.Pos_ := i;
            AddFound(f);
            MarkUsed(i, len);
            i := i + len;
            Continue;
          end;
        end;
      end;
      Inc(i);
    end;
  end;

  procedure ScanSyslog;
  var
    i, j, mo, d, hh, nn, ss, len, y: Integer;
    dt: TDateTime;
    f: TFound;
  begin
    i := 1;
    while i + 10 <= Length(S) do
    begin
      if IsAlphaC(S[i]) and ((i = 1) or not IsAlnumC(S[i - 1])) and
         IsAlphaC(S[i + 1]) and IsAlphaC(S[i + 2]) and (S[i + 3] = ' ') and
         (MonthOf3(Copy(S, i, 3)) > 0) then
      begin
        mo := MonthOf3(Copy(S, i, 3));
        j := i + 4;
        if (j <= Length(S)) and (S[j] = ' ') then Inc(j);   // jour padde 'Jan  5'
        if (j <= Length(S)) and IsDig(S[j]) then
        begin
          d := Ord(S[j]) - Ord('0');
          Inc(j);
          if (j <= Length(S)) and IsDig(S[j]) then
          begin
            d := d * 10 + Ord(S[j]) - Ord('0');
            Inc(j);
          end;
          if (j + 8 <= Length(S)) and (S[j] = ' ') and DigitsAt(j + 1, 2) and
             (S[j + 3] = ':') and DigitsAt(j + 4, 2) and (S[j + 6] = ':') and
             DigitsAt(j + 7, 2) then
          begin
            hh := NumAt(j + 1, 2); nn := NumAt(j + 4, 2); ss := NumAt(j + 7, 2);
            len := (j + 9) - i;
            y := YearOf(Now);   // RFC3164 : pas d'annee dans le format
            if TryEncodeDateTime(y, mo, d, hh, nn, ss, 0, dt) and
               SpanFree(i, len) then
            begin
              f.UTC := LocalTimeToUniversal(dt);
              f.Kind := Format('syslog (year %d assumed)', [y]);
              f.Raw := Copy(S, i, len);
              f.Pos_ := i;
              AddFound(f);
              MarkUsed(i, len);
              i := i + len;
              Continue;
            end;
          end;
        end;
      end;
      Inc(i);
    end;
  end;

  procedure ScanUnix;
  var
    i, j, len: Integer;
    v: Int64;
    f: TFound;
  begin
    i := 1;
    while i <= Length(S) do
    begin
      // '.' devant rejete : '192.168.1.1700000000' n'est pas un timestamp
      if IsDig(S[i]) and ((i = 1) or (not IsAlnumC(S[i - 1]) and (S[i - 1] <> '.'))) then
      begin
        j := i;
        while (j <= Length(S)) and IsDig(S[j]) do Inc(j);
        len := j - i;
        if ((j > Length(S)) or not IsAlnumC(S[j])) and
           ((len = 10) or (len = 13)) and SpanFree(i, len) then
        begin
          v := StrToInt64Def(Copy(S, i, len), -1);
          if v > 0 then
          begin
            if len = 13 then
            begin
              f.UTC := UnixToDateTime(v div 1000);
              f.Kind := 'unix milliseconds';
            end
            else
            begin
              f.UTC := UnixToDateTime(v);
              f.Kind := 'unix seconds';
            end;
            f.Raw := Copy(S, i, len);
            f.Pos_ := i;
            AddFound(f);
            MarkUsed(i, len);
          end;
        end;
        i := j;
      end
      else
        Inc(i);
    end;
  end;

var
  sb: TStringList;
  i, k, shown: Integer;
  secs: Int64;
  tmp: TFound;
begin
  Result := '';
  if S = '' then Exit;
  SetLength(used, Length(S));
  FillChar(used[0], Length(S), 0);
  nf := 0;
  SetLength(found, 0);
  ScanISO;
  ScanApache;
  ScanSyslog;
  ScanUnix;
  if nf = 0 then Exit;
  for i := 1 to nf - 1 do
    for k := nf - 1 downto i do
      if found[k].Pos_ < found[k - 1].Pos_ then
      begin
        tmp := found[k];
        found[k] := found[k - 1];
        found[k - 1] := tmp;
      end;
  sb := TStringList.Create;
  try
    if nf >= MAXFOUND then
      sb.Add(Format('=== Timestamps: %d found (capped) ===', [nf]))
    else
      sb.Add(Format('=== Timestamps: %d found ===', [nf]));
    shown := nf;
    if shown > 50 then shown := 50;
    for k := 0 to shown - 1 do
    begin
      sb.Add(found[k].Raw + '  (' + found[k].Kind + ')');
      sb.Add(Format('    unix %d | utc %s | local %s',
        [DateTimeToUnix(found[k].UTC), IsoUtc(found[k].UTC),
         IsoLocal(found[k].UTC)]));
    end;
    if nf > shown then
      sb.Add(Format('    ... %d more', [nf - shown]));
    if nf >= 2 then
    begin
      secs := Abs(SecondsBetween(found[0].UTC, found[nf - 1].UTC));
      sb.Add('');
      sb.Add(Format('Delta first -> last: %dd %.2d:%.2d:%.2d (%d s)',
        [secs div 86400, (secs mod 86400) div 3600, (secs mod 3600) div 60,
         secs mod 60, secs]));
    end;
    Result := sb.Text;
  finally
    sb.Free;
  end;
end;

end.
