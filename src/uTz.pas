unit uTz;

{$mode objfpc}{$H+}

// Decalage local A LA DATE donnee, pas celui d'aujourd'hui : GetLocalTimeOffset
// de la RTL prend l'instant present, un log de juillet lu en janvier sortait
// en heure d'hiver. Windows : API de zone avec ses regles d'ete/hiver ;
// Unix : localtime_r/mktime de la libc (tm_gmtoff). Repli sur la RTL si l'OS
// refuse la date.

interface

uses
  SysUtils, DateUtils;

function UtcToLocalAt(AUtc: TDateTime): TDateTime;
function LocalToUtcAt(ALocal: TDateTime): TDateTime;
// minutes a l'est de Greenwich a cet instant UTC : local = utc + Result
function LocalOffsetAt(AUtc: TDateTime): Integer;

implementation

{$IFDEF WINDOWS}
function SystemTimeToTzSpecificLocalTime(lpTz: Pointer; const lpUtc: TSystemTime;
  out lpLocal: TSystemTime): LongBool; stdcall; external 'kernel32.dll';
function TzSpecificLocalTimeToSystemTime(lpTz: Pointer; const lpLocal: TSystemTime;
  out lpUtc: TSystemTime): LongBool; stdcall; external 'kernel32.dll';

function UtcToLocalAt(AUtc: TDateTime): TDateTime;
var
  st, lt: TSystemTime;
begin
  DateTimeToSystemTime(AUtc, st);
  if SystemTimeToTzSpecificLocalTime(nil, st, lt) then
    Result := SystemTimeToDateTime(lt)
  else
    Result := UniversalTimeToLocal(AUtc);
end;

function LocalToUtcAt(ALocal: TDateTime): TDateTime;
var
  st, lt: TSystemTime;
begin
  DateTimeToSystemTime(ALocal, lt);
  if TzSpecificLocalTimeToSystemTime(nil, lt, st) then
    Result := SystemTimeToDateTime(st)
  else
    Result := LocalTimeToUniversal(ALocal);
end;

{$ELSE}

uses
  BaseUnix, Unix;

type
  Ptm = ^Ttm;
  Ttm = record
    tm_sec, tm_min, tm_hour, tm_mday, tm_mon, tm_year, tm_wday, tm_yday,
    tm_isdst: cint;
    tm_gmtoff: clong;   // glibc et BSD/macOS : apres tm_isdst
    tm_zone: PChar;
  end;

function localtime_r(t: ptime_t; tm: Ptm): Ptm; cdecl; external 'c';
function mktime(tm: Ptm): time_t; cdecl; external 'c';

function UtcToLocalAt(AUtc: TDateTime): TDateTime;
var
  t: time_t;
  tm: Ttm;
begin
  t := DateTimeToUnix(AUtc);
  if localtime_r(@t, @tm) = nil then Exit(UniversalTimeToLocal(AUtc));
  Result := AUtc + tm.tm_gmtoff / 86400.0;
end;

function LocalToUtcAt(ALocal: TDateTime): TDateTime;
var
  t: time_t;
  tm: Ttm;
  y, mo, d, h, n, s, ms: Word;
begin
  DecodeDateTime(ALocal, y, mo, d, h, n, s, ms);
  FillChar(tm, SizeOf(tm), 0);
  tm.tm_year := y - 1900; tm.tm_mon := mo - 1; tm.tm_mday := d;
  tm.tm_hour := h; tm.tm_min := n; tm.tm_sec := s;
  tm.tm_isdst := -1; // la libc decide de l'heure d'ete
  t := mktime(@tm);
  if t = -1 then Exit(LocalTimeToUniversal(ALocal));
  Result := UnixToDateTime(t) + ms / 86400000.0;
end;
{$ENDIF}

function LocalOffsetAt(AUtc: TDateTime): Integer;
begin
  Result := Round((UtcToLocalAt(AUtc) - AUtc) * 1440);
end;

end.
