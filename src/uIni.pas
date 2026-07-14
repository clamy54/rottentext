unit uIni;

{$mode objfpc}{$H+}

// Aides INI. Parseur maison, PAS IniFiles : TMemIniFile perd commentaires et
// ordre. Un `;` en milieu de valeur y reste (commentaire inline non coupe).

interface

uses
  Classes, SysUtils;

function IniValidate(const AText: string): string;
function IniSortKeys(const AText: string): string;
function IniFindDuplicates(const AText: string): string;

implementation

type
  TIniKind = (ikBlank, ikComment, ikSection, ikEntry, ikBad);

function ClassifyIni(const ALine: string; out AKey, AVal: string): TIniKind;
var
  t: string;
  eq: Integer;
begin
  AKey := ''; AVal := '';
  t := Trim(ALine);
  if t = '' then Exit(ikBlank);
  if (t[1] = ';') or (t[1] = '#') then Exit(ikComment);
  if t[1] = '[' then
  begin
    if (Length(t) < 2) or (t[Length(t)] <> ']') then Exit(ikBad);
    AKey := Trim(Copy(t, 2, Length(t) - 2));
    if AKey = '' then Exit(ikBad);
    Exit(ikSection);
  end;
  eq := Pos('=', t);
  if eq = 0 then Exit(ikBad);
  AKey := Trim(Copy(t, 1, eq - 1));
  if AKey = '' then Exit(ikBad);
  AVal := Copy(t, eq + 1, MaxInt);
  Result := ikEntry;
end;

function SplitLines(const AText: string): TStringList;
begin
  Result := TStringList.Create;
  Result.TextLineBreakStyle := tlbsLF;
  Result.Text := AText;
end;

function IniValidate(const AText: string): string;
const
  MAX_SHOWN = 20;
var
  lines, outp: TStringList;
  i, nSect, nKeys, nBad: Integer;
  key, val, t: string;
begin
  lines := SplitLines(AText);
  outp := TStringList.Create;
  outp.TextLineBreakStyle := tlbsLF;
  try
    nSect := 0; nKeys := 0; nBad := 0;
    for i := 0 to lines.Count - 1 do
      case ClassifyIni(lines[i], key, val) of
        ikSection: Inc(nSect);
        ikEntry: Inc(nKeys);
        ikBad:
          begin
            Inc(nBad);
            if nBad <= MAX_SHOWN then
            begin
              t := Trim(lines[i]);
              if Length(t) > 60 then t := Copy(t, 1, 57) + '...';
              if t[1] = '[' then
                outp.Add(Format('  line %d: bad section header: %s', [i + 1, t]))
              else if t[1] = '=' then
                outp.Add(Format('  line %d: value without a key: %s', [i + 1, t]))
              else
                outp.Add(Format('  line %d: not a key=value, section or comment: %s',
                  [i + 1, t]));
            end;
          end;
      end;
    if nBad = 0 then
      Result := Format('INI OK: %d section(s), %d key(s).', [nSect, nKeys])
    else
    begin
      if nBad > MAX_SHOWN then
        outp.Add(Format('  ... and %d more', [nBad - MAX_SHOWN]));
      Result := Format('%d problem line(s):', [nBad]) + LineEnding + outp.Text;
    end;
  finally
    lines.Free; outp.Free;
  end;
end;

function IniSortKeys(const AText: string): string;
type
  TUnit = record
    Key: string;
    Idx: Integer;
    Block: TStringList; // commentaires/vides precedents + la ligne de cle
  end;
var
  lines, pending, outp: TStringList;
  units: array of TUnit;
  i, n: Integer;
  key, val: string;

  // ordre TOTAL : quicksort deterministe, equivalent-stable
  function UnitLess(const A, B: TUnit): Boolean;
  var
    c: Integer;
  begin
    c := CompareText(A.Key, B.Key);
    if c <> 0 then Exit(c < 0);
    Result := A.Idx < B.Idx;
  end;

  procedure QSort(ALo, AHi: Integer);
  var
    a, b: Integer;
    p, t: TUnit;
  begin
    while ALo < AHi do
    begin
      a := ALo; b := AHi;
      p := units[(ALo + AHi) div 2];
      repeat
        while UnitLess(units[a], p) do Inc(a);
        while UnitLess(p, units[b]) do Dec(b);
        if a <= b then
        begin
          t := units[a]; units[a] := units[b]; units[b] := t;
          Inc(a); Dec(b);
        end;
      until a > b;
      if b - ALo < AHi - a then
      begin
        QSort(ALo, b);
        ALo := a;
      end
      else
      begin
        QSort(a, AHi);
        AHi := b;
      end;
    end;
  end;

  procedure FlushSection;
  var
    a: Integer;
  begin
    if Length(units) > 1 then
      QSort(0, High(units));
    for a := 0 to High(units) do
    begin
      outp.AddStrings(units[a].Block);
      units[a].Block.Free;
      units[a].Block := nil;
    end;
    units := nil;
    outp.AddStrings(pending);
    pending.Clear;
  end;

begin
  lines := SplitLines(AText);
  pending := TStringList.Create;
  pending.TextLineBreakStyle := tlbsLF;
  outp := TStringList.Create;
  outp.TextLineBreakStyle := tlbsLF;
  units := nil;
  try
    for i := 0 to lines.Count - 1 do
      case ClassifyIni(lines[i], key, val) of
        ikEntry:
          begin
            n := Length(units);
            SetLength(units, n + 1);
            units[n].Key := key;
            units[n].Idx := n;
            units[n].Block := TStringList.Create;
            units[n].Block.TextLineBreakStyle := tlbsLF;
            units[n].Block.AddStrings(pending);
            units[n].Block.Add(lines[i]);
            pending.Clear;
          end;
        ikSection:
          begin
            FlushSection;
            outp.Add(lines[i]);
          end;
      else
        // vides, commentaires, lignes malformees : collent a ce qui SUIT
        pending.Add(lines[i]);
      end;
    FlushSection;
    Result := outp.Text;
  finally
    for i := 0 to High(units) do
      if units[i].Block <> nil then units[i].Block.Free;
    lines.Free; pending.Free; outp.Free;
  end;
end;

function IniFindDuplicates(const AText: string): string;
var
  lines, keys, lineNos, outp: TStringList;
  i, k, cnt: Integer;
  key, val, sect, qk: string;

  // un '=' dans un nom de section casserait le decoupage name=value TStringList
  function MapName(const S: string): string;
  begin
    Result := StringReplace(UpperCase(S), '=', #1, [rfReplaceAll]);
  end;

begin
  lines := SplitLines(AText);
  keys := TStringList.Create;
  lineNos := TStringList.Create; // UPPER([sect]key) = "n1 n2 n3"
  lineNos.CaseSensitive := True;
  outp := TStringList.Create;
  outp.TextLineBreakStyle := tlbsLF;
  try
    sect := '';
    for i := 0 to lines.Count - 1 do
      case ClassifyIni(lines[i], key, val) of
        ikSection:
          begin
            sect := key;
            qk := '[' + key + ']';
            k := lineNos.IndexOfName(MapName(qk));
            if k < 0 then
            begin
              keys.Add(qk);
              lineNos.Add(MapName(qk) + '=' + IntToStr(i + 1));
            end
            else
              lineNos.ValueFromIndex[k] :=
                lineNos.ValueFromIndex[k] + ' ' + IntToStr(i + 1);
          end;
        ikEntry:
          begin
            if sect = '' then qk := key else qk := '[' + sect + '] ' + key;
            k := lineNos.IndexOfName(MapName(qk));
            if k < 0 then
            begin
              keys.Add(qk);
              lineNos.Add(MapName(qk) + '=' + IntToStr(i + 1));
            end
            else
              lineNos.ValueFromIndex[k] :=
                lineNos.ValueFromIndex[k] + ' ' + IntToStr(i + 1);
          end;
      end;

    outp.Add('# INI duplicates (same section, case-insensitive)');
    cnt := 0;
    for i := 0 to keys.Count - 1 do
    begin
      k := lineNos.IndexOfName(MapName(keys[i]));
      if k < 0 then Continue;
      if Pos(' ', lineNos.ValueFromIndex[k]) > 0 then
      begin
        outp.Add('  ' + keys[i] + '  -> lines ' +
          StringReplace(Trim(lineNos.ValueFromIndex[k]), ' ', ', ', [rfReplaceAll]));
        Inc(cnt);
      end;
    end;
    if cnt = 0 then outp.Add('  (none)');
    Result := outp.Text;
  finally
    lines.Free; keys.Free; lineNos.Free; outp.Free;
  end;
end;

end.
