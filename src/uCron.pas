unit uCron;

{$mode objfpc}{$H+}

// Explique un cron Vixie 5 champs ou un OnCalendar= systemd (sous-ensemble :
// `~` fin de mois non supporte, timezone finale ignoree avec note).
// Prochains runs : scan par JOUR borne a SCAN_YEARS (pas de gel sur une
// expression jamais vraie), heure locale naive, DST non modelise.

interface

uses
  Classes, SysUtils, DateUtils;

const
  SCAN_YEARS = 5;

// '' + AErr sur erreur de syntaxe
function ScheduleReport(const AExpr: string; ANow: TDateTime; ACount: Integer;
  out AErr: string): string;

implementation

const
  MonNames: array[1..12] of string =
    ('jan', 'feb', 'mar', 'apr', 'may', 'jun',
     'jul', 'aug', 'sep', 'oct', 'nov', 'dec');
  MonFull: array[1..12] of string =
    ('January', 'February', 'March', 'April', 'May', 'June',
     'July', 'August', 'September', 'October', 'November', 'December');
  // cron : 0 = dimanche (7 accepte, replie sur 0)
  DowNames: array[0..6] of string =
    ('sun', 'mon', 'tue', 'wed', 'thu', 'fri', 'sat');
  DowFull: array[0..6] of string =
    ('Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday',
     'Saturday');

type
  TCronSpec = record
    Min, Hour, Dom, Mon, Dow: Int64; // bitmasks
    DomStar, DowStar: Boolean;       // `*` nu (semantique OR de Vixie)
  end;

  TPart = record
    Lo, Hi, Step: Integer;
  end;
  TParts = array of TPart;
  TCalSpec = record
    AnyDow: Boolean;
    DowMask: Integer; // bits 0..6, 0 = lundi (convention systemd)
    Y, M, D, H, Mi, S: TParts;
    TzNote: string;
  end;

type
  TStrArr = array of string;

function BitSet(M: Int64; V: Integer): Boolean; inline;
begin
  Result := (M and (Int64(1) shl V)) <> 0;
end;

function SplitCh(const S: string; ASep: Char): TStrArr;
var
  i, start, n: Integer;
begin
  Result := nil;
  start := 1;
  for i := 1 to Length(S) + 1 do
    if (i > Length(S)) or (S[i] = ASep) then
    begin
      n := Length(Result);
      SetLength(Result, n + 1);
      Result[n] := Copy(S, start, i - start);
      start := i + 1;
    end;
end;

function SplitWS(const S: string): TStrArr;
var
  i, start, n: Integer;
begin
  Result := nil;
  i := 1;
  while i <= Length(S) do
  begin
    while (i <= Length(S)) and (S[i] in [' ', #9]) do Inc(i);
    if i > Length(S) then Break;
    start := i;
    while (i <= Length(S)) and not (S[i] in [' ', #9]) do Inc(i);
    n := Length(Result);
    SetLength(Result, n + 1);
    Result[n] := Copy(S, start, i - start);
  end;
end;

// prefixe 3 lettres insensible a la casse: 'monday' matche 'mon'
function NameVal(const S: string; const ANames: array of string;
  ABase: Integer): Integer;
var
  i: Integer;
  t: string;
begin
  Result := -1;
  if Length(S) < 3 then Exit;
  t := LowerCase(Copy(S, 1, 3));
  for i := 0 to High(ANames) do
    if ANames[i] = t then Exit(i + ABase);
end;

function FieldVal(const S: string; ALo, AHi: Integer;
  const ANames: array of string; ABase: Integer): Integer;
var
  v, code: Integer;
begin
  Val(S, v, code);
  if code = 0 then
  begin
    if (v < ALo) or (v > AHi) then Exit(-1);
    Exit(v);
  end;
  Result := NameVal(S, ANames, ABase);
  if (Result < ALo) or (Result > AHi) then Result := -1;
end;

function ParseCronField(const S: string; ALo, AHi: Integer;
  const ANames: array of string; ABase: Integer;
  out AMask: Int64; out AStar: Boolean; out AErr: string): Boolean;
var
  items: TStrArr;
  it, rng: string;
  i, p, step, a, b, v: Integer;
begin
  Result := False;
  AMask := 0;
  AStar := False;
  AErr := '';
  if S = '' then begin AErr := 'empty field'; Exit; end;
  items := SplitCh(S, ',');
  for i := 0 to High(items) do
  begin
    it := items[i];
    if it = '' then begin AErr := 'empty list item'; Exit; end;
    step := 1;
    p := Pos('/', it);
    if p > 0 then
    begin
      Val(Copy(it, p + 1, MaxInt), step, v);
      if (v <> 0) or (step < 1) then
        begin AErr := 'bad step in "' + it + '"'; Exit; end;
      it := Copy(it, 1, p - 1);
    end;
    if (it = '*') or (it = '?') then // `?` Quartz tolere comme `*`
    begin
      a := ALo; b := AHi;
      if (Length(items) = 1) and (step = 1) then AStar := True;
    end
    else
    begin
      rng := '';
      p := Pos('-', it);
      if p > 0 then
      begin
        rng := Copy(it, p + 1, MaxInt);
        it := Copy(it, 1, p - 1);
      end;
      a := FieldVal(it, ALo, AHi, ANames, ABase);
      if a < 0 then begin AErr := 'bad value "' + it + '"'; Exit; end;
      if rng <> '' then
      begin
        b := FieldVal(rng, ALo, AHi, ANames, ABase);
        if b < 0 then begin AErr := 'bad value "' + rng + '"'; Exit; end;
        if b < a then begin AErr := 'inverted range "' + it + '-' + rng + '"'; Exit; end;
      end
      else if step > 1 then
        b := AHi // `a/s` = de a a la borne haute (Vixie)
      else
        b := a;
    end;
    v := a;
    while v <= b do
    begin
      AMask := AMask or (Int64(1) shl v);
      Inc(v, step);
    end;
  end;
  Result := True;
end;

function ParseCron(const AFields: array of string; out ASpec: TCronSpec;
  out AErr: string): Boolean;
var
  star: Boolean;
begin
  Result := False;
  ASpec := Default(TCronSpec);
  if not ParseCronField(AFields[0], 0, 59, [], 0, ASpec.Min, star, AErr) then
    begin AErr := 'minute: ' + AErr; Exit; end;
  if not ParseCronField(AFields[1], 0, 23, [], 0, ASpec.Hour, star, AErr) then
    begin AErr := 'hour: ' + AErr; Exit; end;
  if not ParseCronField(AFields[2], 1, 31, [], 0, ASpec.Dom, ASpec.DomStar, AErr) then
    begin AErr := 'day of month: ' + AErr; Exit; end;
  if not ParseCronField(AFields[3], 1, 12, MonNames, 1, ASpec.Mon, star, AErr) then
    begin AErr := 'month: ' + AErr; Exit; end;
  if not ParseCronField(AFields[4], 0, 7, DowNames, 0, ASpec.Dow, ASpec.DowStar, AErr) then
    begin AErr := 'day of week: ' + AErr; Exit; end;
  if BitSet(ASpec.Dow, 7) then
    ASpec.Dow := (ASpec.Dow or 1) and not (Int64(1) shl 7);
  Result := True;
end;

// dom ET dow restreints = OU, pas ET (regle Vixie)
function CronDayMatch(const ASpec: TCronSpec; AY, AM, AD: Word): Boolean;
var
  dw: Integer;
begin
  if not BitSet(ASpec.Mon, AM) then Exit(False);
  dw := SysUtils.DayOfWeek(EncodeDate(AY, AM, AD)) - 1; // 0 = dimanche
  if ASpec.DomStar and ASpec.DowStar then Exit(True);
  if ASpec.DomStar then Exit(BitSet(ASpec.Dow, dw));
  if ASpec.DowStar then Exit(BitSet(ASpec.Dom, AD));
  Result := BitSet(ASpec.Dom, AD) or BitSet(ASpec.Dow, dw);
end;

// 0 si aucun run sous SCAN_YEARS
function NextCron(const ASpec: TCronSpec; AFrom: TDateTime): TDateTime;
var
  d, limit: TDateTime;
  y, mo, dd: Word;
  h, mi, h0, m0: Integer;
  first: Boolean;
begin
  Result := 0;
  d := IncMinute(RecodeSecond(RecodeMilliSecond(AFrom, 0), 0), 1);
  limit := IncYear(AFrom, SCAN_YEARS);
  first := True;
  while d < limit do
  begin
    DecodeDate(d, y, mo, dd);
    if CronDayMatch(ASpec, y, mo, dd) then
    begin
      if first then begin h0 := HourOf(d); m0 := MinuteOf(d); end
      else begin h0 := 0; m0 := 0; end;
      for h := h0 to 23 do
        if BitSet(ASpec.Hour, h) then
        begin
          if h > h0 then m0 := 0;
          for mi := m0 to 59 do
            if BitSet(ASpec.Min, mi) then
              Exit(EncodeDateTime(y, mo, dd, h, mi, 0, 0));
        end;
    end;
    d := IncDay(RecodeTime(d, 0, 0, 0, 0), 1);
    first := False;
  end;
end;

function PartsMatch(const P: TParts; V: Integer): Boolean;
var
  i: Integer;
begin
  if Length(P) = 0 then Exit(True); // `*`
  for i := 0 to High(P) do
    if (V >= P[i].Lo) and (V <= P[i].Hi) and
       ((V - P[i].Lo) mod P[i].Step = 0) then Exit(True);
  Result := False;
end;

function ParseCalParts(const S: string; ALo, AHi: Integer; out P: TParts;
  out AErr: string): Boolean;
var
  items: TStrArr;
  it, rng: string;
  i, pp, code, n: Integer;
  prt: TPart;
begin
  Result := False;
  P := nil;
  AErr := '';
  if S = '' then begin AErr := 'empty component'; Exit; end;
  if Pos('~', S) > 0 then
    begin AErr := 'last-day-of-month "~" not supported'; Exit; end;
  if S = '*' then Exit(True);
  items := SplitCh(S, ',');
  for i := 0 to High(items) do
  begin
    it := items[i];
    if it = '' then begin AErr := 'empty list item'; Exit; end;
    prt.Step := 1;
    pp := Pos('/', it);
    if pp > 0 then
    begin
      Val(Copy(it, pp + 1, MaxInt), prt.Step, code);
      if (code <> 0) or (prt.Step < 1) then
        begin AErr := 'bad step in "' + it + '"'; Exit; end;
      it := Copy(it, 1, pp - 1);
    end;
    if it = '*' then
    begin
      prt.Lo := ALo; prt.Hi := AHi;
    end
    else
    begin
      pp := Pos('..', it);
      if pp > 0 then
      begin
        rng := Copy(it, pp + 2, MaxInt);
        it := Copy(it, 1, pp - 1);
      end
      else
        rng := '';
      Val(it, prt.Lo, code);
      if (code <> 0) or (prt.Lo < ALo) or (prt.Lo > AHi) then
        begin AErr := 'bad value "' + it + '"'; Exit; end;
      if rng <> '' then
      begin
        Val(rng, prt.Hi, code);
        if (code <> 0) or (prt.Hi < prt.Lo) or (prt.Hi > AHi) then
          begin AErr := 'bad range end "' + rng + '"'; Exit; end;
      end
      else if prt.Step > 1 then
        prt.Hi := AHi
      else
        prt.Hi := prt.Lo;
    end;
    n := Length(P);
    SetLength(P, n + 1);
    P[n] := prt;
  end;
  Result := True;
end;

function ParseCalDow(const S: string; out AMask: Integer;
  out AErr: string): Boolean;
var
  items: TStrArr;
  it, rng: string;
  i, p, a, b, v: Integer;
const
  // systemd numerote lundi = 0
  SysDow: array[0..6] of string =
    ('mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun');
begin
  Result := False;
  AMask := 0;
  AErr := '';
  items := SplitCh(S, ',');
  for i := 0 to High(items) do
  begin
    it := items[i];
    p := Pos('..', it);
    if p > 0 then
    begin
      rng := Copy(it, p + 2, MaxInt);
      it := Copy(it, 1, p - 1);
    end
    else
      rng := '';
    a := NameVal(it, SysDow, 0);
    if a < 0 then begin AErr := 'bad day name "' + it + '"'; Exit; end;
    if rng <> '' then
    begin
      b := NameVal(rng, SysDow, 0);
      if b < 0 then begin AErr := 'bad day name "' + rng + '"'; Exit; end;
      if b < a then begin AErr := 'inverted day range'; Exit; end;
    end
    else
      b := a;
    for v := a to b do
      AMask := AMask or (1 shl v);
  end;
  Result := True;
end;

// noms speciaux systemd.time(7)
function CalSpecialForm(const S: string): string;
var
  t: string;
begin
  t := LowerCase(S);
  if t = 'minutely' then Exit('*-*-* *:*:00');
  if t = 'hourly' then Exit('*-*-* *:00:00');
  if (t = 'daily') or (t = 'midnight') then Exit('*-*-* 00:00:00');
  if t = 'weekly' then Exit('Mon *-*-* 00:00:00');
  if t = 'monthly' then Exit('*-*-01 00:00:00');
  if (t = 'yearly') or (t = 'annually') then Exit('*-01-01 00:00:00');
  if t = 'quarterly' then Exit('*-01,04,07,10-01 00:00:00');
  if t = 'semiannually' then Exit('*-01,07-01 00:00:00');
  Result := '';
end;

function ParseCalendar(const AExpr: string; out ASpec: TCalSpec;
  out ANorm: string; out AErr: string): Boolean;
var
  toks, parts: TStrArr;
  i, n: Integer;
  t, datePart, timePart, dowPart: string;
begin
  Result := False;
  ASpec := Default(TCalSpec);
  ASpec.AnyDow := True;
  AErr := '';
  ANorm := Trim(AExpr);
  t := CalSpecialForm(ANorm);
  if t <> '' then ANorm := t;
  datePart := ''; timePart := ''; dowPart := '';
  toks := SplitWS(ANorm);
  for i := 0 to High(toks) do
  begin
    t := toks[i];
    if Pos(':', t) > 0 then
    begin
      if timePart <> '' then begin AErr := 'two time parts'; Exit; end;
      timePart := t;
    end
    else if (Pos('-', t) > 0) or (t = '*') then
    begin
      if datePart <> '' then begin AErr := 'two date parts'; Exit; end;
      datePart := t;
    end
    else if (t <> '') and (t[1] in ['A'..'Z', 'a'..'z']) then
    begin
      // dow avant la date, sinon timezone finale (ignoree)
      if (dowPart = '') and (datePart = '') and (timePart = '') then
        dowPart := t
      else
        ASpec.TzNote := t;
    end
    else
    begin
      AErr := 'unrecognized token "' + t + '"';
      Exit;
    end;
  end;
  if (datePart = '') and (timePart = '') and (dowPart = '') then
    begin AErr := 'empty calendar expression'; Exit; end;
  if dowPart <> '' then
  begin
    if not ParseCalDow(dowPart, ASpec.DowMask, AErr) then Exit;
    ASpec.AnyDow := False;
  end;
  // date absente = tous les jours
  if (datePart = '') or (datePart = '*') then
  begin
    ASpec.Y := nil; ASpec.M := nil; ASpec.D := nil;
  end
  else
  begin
    parts := SplitCh(datePart, '-');
    n := Length(parts);
    if (n < 2) or (n > 3) then
      begin AErr := 'date must be [YYYY-]MM-DD'; Exit; end;
    if n = 3 then
    begin
      if not ParseCalParts(parts[0], 1970, 2199, ASpec.Y, AErr) then
        begin AErr := 'year: ' + AErr; Exit; end;
      if not ParseCalParts(parts[1], 1, 12, ASpec.M, AErr) then
        begin AErr := 'month: ' + AErr; Exit; end;
      if not ParseCalParts(parts[2], 1, 31, ASpec.D, AErr) then
        begin AErr := 'day: ' + AErr; Exit; end;
    end
    else
    begin
      if not ParseCalParts(parts[0], 1, 12, ASpec.M, AErr) then
        begin AErr := 'month: ' + AErr; Exit; end;
      if not ParseCalParts(parts[1], 1, 31, ASpec.D, AErr) then
        begin AErr := 'day: ' + AErr; Exit; end;
    end;
  end;
  // heure absente = 00:00:00 (convention systemd)
  if timePart = '' then timePart := '00:00:00';
  parts := SplitCh(timePart, ':');
  n := Length(parts);
  if (n < 2) or (n > 3) then
    begin AErr := 'time must be HH:MM[:SS]'; Exit; end;
  if not ParseCalParts(parts[0], 0, 23, ASpec.H, AErr) then
    begin AErr := 'hour: ' + AErr; Exit; end;
  if not ParseCalParts(parts[1], 0, 59, ASpec.Mi, AErr) then
    begin AErr := 'minute: ' + AErr; Exit; end;
  if n = 3 then
  begin
    if not ParseCalParts(parts[2], 0, 59, ASpec.S, AErr) then
      begin AErr := 'second: ' + AErr; Exit; end;
  end
  else
  begin
    SetLength(ASpec.S, 1);
    ASpec.S[0].Lo := 0; ASpec.S[0].Hi := 0; ASpec.S[0].Step := 1;
  end;
  Result := True;
end;

function NextCal(const ASpec: TCalSpec; AFrom: TDateTime): TDateTime;
var
  d, limit: TDateTime;
  y, mo, dd: Word;
  h, mi, s, h0, m0, s0, dw: Integer;
  first: Boolean;
begin
  Result := 0;
  d := IncSecond(RecodeMilliSecond(AFrom, 0), 1);
  limit := IncYear(AFrom, SCAN_YEARS);
  first := True;
  while d < limit do
  begin
    DecodeDate(d, y, mo, dd);
    dw := (SysUtils.DayOfWeek(d) + 5) mod 7; // 0 = lundi (systemd)
    if PartsMatch(ASpec.Y, y) and PartsMatch(ASpec.M, mo) and
       PartsMatch(ASpec.D, dd) and
       (ASpec.AnyDow or ((ASpec.DowMask and (1 shl dw)) <> 0)) then
    begin
      if first then
      begin
        h0 := HourOf(d); m0 := MinuteOf(d); s0 := SecondOf(d);
      end
      else
      begin
        h0 := 0; m0 := 0; s0 := 0;
      end;
      for h := h0 to 23 do
        if PartsMatch(ASpec.H, h) then
        begin
          if h > h0 then m0 := 0;
          for mi := m0 to 59 do
            if PartsMatch(ASpec.Mi, mi) then
            begin
              if (h > h0) or (mi > m0) then s0 := 0;
              for s := s0 to 59 do
                if PartsMatch(ASpec.S, s) then
                  Exit(EncodeDateTime(y, mo, dd, h, mi, s, 0));
            end;
        end;
    end;
    d := IncDay(RecodeTime(d, 0, 0, 0, 0), 1);
    first := False;
  end;
end;

// AKind: 0 = nombre, 1 = mois, 2 = jour
function DescMask(AMask: Int64; ALo, AHi, AKind: Integer;
  const AUnit: string): string;
var
  vals: array of Integer;
  i, n, step: Integer;
  uniform, contig: Boolean;

  function Nm(V: Integer): string;
  begin
    case AKind of
      1: Result := MonFull[V];
      2: Result := DowFull[V];
    else
      Result := IntToStr(V);
    end;
  end;

begin
  vals := nil;
  for i := ALo to AHi do
    if BitSet(AMask, i) then
    begin
      n := Length(vals);
      SetLength(vals, n + 1);
      vals[n] := i;
    end;
  n := Length(vals);
  if n = 0 then Exit('never');
  if n = AHi - ALo + 1 then Exit('every ' + AUnit);
  if n = 1 then Exit(Nm(vals[0]));
  contig := vals[n - 1] - vals[0] = n - 1;
  if contig then Exit(Nm(vals[0]) + ' through ' + Nm(vals[n - 1]));
  step := vals[1] - vals[0];
  uniform := True;
  for i := 2 to n - 1 do
    if vals[i] - vals[i - 1] <> step then begin uniform := False; Break; end;
  if uniform and (n > 2) then
  begin
    Result := Format('every %d %ss from %s', [step, AUnit, Nm(vals[0])]);
    Exit;
  end;
  Result := '';
  for i := 0 to n - 1 do
  begin
    if i > 0 then Result := Result + ', ';
    if i = 16 then begin Result := Result + '...'; Break; end;
    Result := Result + Nm(vals[i]);
  end;
end;

function DescParts(const P: TParts; ALo, AHi: Integer;
  const AUnit: string): string;
var
  i: Integer;
begin
  if Length(P) = 0 then Exit('every ' + AUnit);
  Result := '';
  for i := 0 to High(P) do
  begin
    if i > 0 then Result := Result + ', ';
    if (P[i].Lo = ALo) and (P[i].Hi = AHi) and (P[i].Step > 1) then
      Result := Result + Format('every %d %ss', [P[i].Step, AUnit])
    else if P[i].Lo = P[i].Hi then
      Result := Result + IntToStr(P[i].Lo)
    else if P[i].Step > 1 then
      Result := Result + Format('%d..%d step %d', [P[i].Lo, P[i].Hi, P[i].Step])
    else
      Result := Result + Format('%d..%d', [P[i].Lo, P[i].Hi]);
  end;
end;

function HumanDelta(AFrom, ATo: TDateTime): string;
var
  secs: Int64;
  d, h, m: Int64;
begin
  secs := SecondsBetween(AFrom, ATo);
  d := secs div 86400;
  h := (secs mod 86400) div 3600;
  m := (secs mod 3600) div 60;
  if d > 0 then Result := Format('%dd %dh', [d, h])
  else if h > 0 then Result := Format('%dh %dm', [h, m])
  else if m > 0 then Result := Format('%dm', [m])
  else Result := Format('%ds', [secs mod 60]);
end;

function FmtRun(AWhen: TDateTime): string;
begin
  Result := DowNames[SysUtils.DayOfWeek(AWhen) - 1];
  Result[1] := UpCase(Result[1]);
  Result := Result + FormatDateTime(' yyyy-mm-dd hh:nn:ss', AWhen);
end;

function CronReport(const AFields: array of string; const ACmd: string;
  ANow: TDateTime; ACount: Integer; out AErr: string): string;
var
  spec: TCronSpec;
  outp: TStringList;
  i: Integer;
  t: TDateTime;
begin
  Result := '';
  if not ParseCron(AFields, spec, AErr) then Exit;
  outp := TStringList.Create;
  outp.TextLineBreakStyle := tlbsLF;
  try
    outp.Add(Format('cron: %s %s %s %s %s', [AFields[0], AFields[1],
      AFields[2], AFields[3], AFields[4]]));
    outp.Add('  minute        ' + DescMask(spec.Min, 0, 59, 0, 'minute'));
    outp.Add('  hour          ' + DescMask(spec.Hour, 0, 23, 0, 'hour'));
    outp.Add('  day of month  ' + DescMask(spec.Dom, 1, 31, 0, 'day'));
    outp.Add('  month         ' + DescMask(spec.Mon, 1, 12, 1, 'month'));
    outp.Add('  day of week   ' + DescMask(spec.Dow, 0, 6, 2, 'day'));
    if ACmd <> '' then
      outp.Add('  command       ' + ACmd);
    if (not spec.DomStar) and (not spec.DowStar) then
      outp.Add('  note: day-of-month AND day-of-week restricted -> runs when'
        + ' EITHER matches (Vixie cron)');
    outp.Add('next runs (local time):');
    t := ANow;
    for i := 1 to ACount do
    begin
      t := NextCron(spec, t);
      if t = 0 then
      begin
        outp.Add(Format('  (no run within %d years)', [SCAN_YEARS]));
        Break;
      end;
      if i = 1 then
        outp.Add('  ' + FmtRun(t) + '   (in ' + HumanDelta(ANow, t) + ')')
      else
        outp.Add('  ' + FmtRun(t));
    end;
    outp.Add('note: local time, DST transitions not modeled');
    Result := outp.Text;
  finally
    outp.Free;
  end;
end;

function CalReport(const AExpr: string; ANow: TDateTime; ACount: Integer;
  out AErr: string): string;
var
  spec: TCalSpec;
  outp: TStringList;
  norm, s: string;
  i, b: Integer;
  t: TDateTime;
const
  SysDowUp: array[0..6] of string =
    ('Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun');
begin
  Result := '';
  if not ParseCalendar(AExpr, spec, norm, AErr) then Exit;
  outp := TStringList.Create;
  outp.TextLineBreakStyle := tlbsLF;
  try
    outp.Add('OnCalendar: ' + norm);
    if not spec.AnyDow then
    begin
      s := '';
      for b := 0 to 6 do
        if (spec.DowMask and (1 shl b)) <> 0 then
        begin
          if s <> '' then s := s + ', ';
          s := s + SysDowUp[b];
        end;
      outp.Add('  day of week   ' + s);
    end;
    if Length(spec.Y) > 0 then
      outp.Add('  year          ' + DescParts(spec.Y, 1970, 2199, 'year'));
    outp.Add('  month         ' + DescParts(spec.M, 1, 12, 'month'));
    outp.Add('  day           ' + DescParts(spec.D, 1, 31, 'day'));
    outp.Add('  hour          ' + DescParts(spec.H, 0, 23, 'hour'));
    outp.Add('  minute        ' + DescParts(spec.Mi, 0, 59, 'minute'));
    outp.Add('  second        ' + DescParts(spec.S, 0, 59, 'second'));
    if spec.TzNote <> '' then
      outp.Add('  note: timezone "' + spec.TzNote
        + '" ignored, computed as local time');
    outp.Add('next runs (local time):');
    t := ANow;
    for i := 1 to ACount do
    begin
      t := NextCal(spec, t);
      if t = 0 then
      begin
        outp.Add(Format('  (no run within %d years)', [SCAN_YEARS]));
        Break;
      end;
      if i = 1 then
        outp.Add('  ' + FmtRun(t) + '   (in ' + HumanDelta(ANow, t) + ')')
      else
        outp.Add('  ' + FmtRun(t));
    end;
    outp.Add('note: local time, DST transitions not modeled');
    Result := outp.Text;
  finally
    outp.Free;
  end;
end;

function ScheduleReport(const AExpr: string; ANow: TDateTime; ACount: Integer;
  out AErr: string): string;
var
  s, cmd: string;
  toks: TStrArr;
  fields: array[0..4] of string;
  i, p: Integer;
  cronish: Boolean;
const
  Macros: array[0..7, 0..1] of string = (
    ('@yearly', '0 0 1 1 *'), ('@annually', '0 0 1 1 *'),
    ('@monthly', '0 0 1 * *'), ('@weekly', '0 0 * * 0'),
    ('@daily', '0 0 * * *'), ('@midnight', '0 0 * * *'),
    ('@hourly', '0 * * * *'), ('@reboot', ''));
begin
  Result := '';
  AErr := '';
  if ACount < 1 then ACount := 10;
  s := Trim(AExpr);
  p := Pos('=', s);
  if (p > 0) and SameText(Trim(Copy(s, 1, p - 1)), 'OnCalendar') then
    s := Trim(Copy(s, p + 1, MaxInt));
  if s = '' then begin AErr := 'empty expression'; Exit; end;

  if s[1] = '@' then
  begin
    p := Pos(' ', s);
    if p = 0 then p := Length(s) + 1;
    cmd := Trim(Copy(s, p, MaxInt));
    for i := 0 to High(Macros) do
      if SameText(Copy(s, 1, p - 1), Macros[i, 0]) then
      begin
        if Macros[i, 1] = '' then // @reboot : pas de calendrier
        begin
          Result := 'cron: @reboot' + LineEnding
            + '  runs once at daemon startup, no calendar schedule'
            + LineEnding;
          if cmd <> '' then
            Result := Result + '  command       ' + cmd + LineEnding;
          Exit;
        end;
        toks := SplitWS(Macros[i, 1]);
        for p := 0 to 4 do fields[p] := toks[p];
        Exit(CronReport(fields, cmd, ANow, ACount, AErr));
      end;
    AErr := 'unknown macro "' + s + '"';
    Exit;
  end;

  // un champ cron ne contient jamais ':' ni '..' : 5 tokens sans ca = cron, le
  // reste = commande (sinon 'curl https://...' partirait dans OnCalendar)
  toks := SplitWS(s);
  cronish := Length(toks) >= 5;
  if cronish then
    for i := 0 to 4 do
      if (Pos(':', toks[i]) > 0) or (Pos('..', toks[i]) > 0) then
        cronish := False;
  if cronish then
  begin
    for i := 0 to 4 do
      fields[i] := toks[i];
    cmd := '';
    for i := 5 to High(toks) do
    begin
      if cmd <> '' then cmd := cmd + ' ';
      cmd := cmd + toks[i];
    end;
    Exit(CronReport(fields, cmd, ANow, ACount, AErr));
  end;

  // >= 2 tirets = date systemd seule ('*-12-25'), que cron ne produit jamais
  if (Pos(':', s) > 0) or (CalSpecialForm(s) <> '') or (Pos('..', s) > 0) or
     (Length(s) - Length(StringReplace(s, '-', '', [rfReplaceAll])) >= 2) then
    Exit(CalReport(s, ANow, ACount, AErr));

  AErr := 'expected 5 cron fields (min hour dom mon dow), a crontab line,'
    + ' or an OnCalendar= expression';
end;

end.
