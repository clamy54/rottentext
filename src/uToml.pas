unit uToml;

{$mode objfpc}{$H+}

// Scanner TOML, PAS un parseur complet : structure lue sur une ligne MASQUEE
// (chaines videes, `#` coupe hors chaine, positions 1:1). Plafond 8 Mo.
// HEURISTIQUE : types non valides, collisions cle pointee vs table non vues.

interface

uses
  Classes, SysUtils;

const
  TOML_MAX_BYTES = 8 * 1024 * 1024;

function TomlValidate(const AText: string): string;
function TomlSortKeys(const AText: string): string;
function TomlFindDuplicates(const AText: string): string;

implementation

type
  TMlState = (msNone, msBasic, msLiteral); // """ / ''' en cours
  TTomlKind = (tkBlank, tkComment, tkHeader, tkArrayHeader, tkEntry, tkBad);

  TTomlUnit = record
    Kind: TTomlKind;
    Line: Integer;   // 1-based
    Count: Integer;  // lignes consommees, continuations comprises
    Key: string;
    Why: string;
  end;
  TTomlUnits = array of TTomlUnit;
  TIntArr = array of Integer;

// delimiteurs de quote CONSERVES : sans eux une cle quotee passerait pour une
// valeur sans cle. AOpenStr = chaine simple non fermee en fin de ligne.
function MaskToml(const L: string; var AState: TMlState;
  out AOpenStr: Boolean): string;
var
  i, n: Integer;
begin
  AOpenStr := False;
  n := Length(L);
  Result := L;
  i := 1;
  while i <= n do
  begin
    case AState of
      msBasic:
        begin
          if (i + 2 <= n) and (L[i] = '"') and (L[i + 1] = '"') and
             (L[i + 2] = '"') then
          begin
            Inc(i, 3);
            AState := msNone;
          end
          else
          begin
            Result[i] := ' ';
            Inc(i);
          end;
          Continue;
        end;
      msLiteral:
        begin
          if (i + 2 <= n) and (L[i] = '''') and (L[i + 1] = '''') and
             (L[i + 2] = '''') then
          begin
            Inc(i, 3);
            AState := msNone;
          end
          else
          begin
            Result[i] := ' ';
            Inc(i);
          end;
          Continue;
        end;
    end;
    if (i + 2 <= n) and (L[i] = '"') and (L[i + 1] = '"') and (L[i + 2] = '"') then
    begin
      Inc(i, 3);
      AState := msBasic;
    end
    else if (i + 2 <= n) and (L[i] = '''') and (L[i + 1] = '''') and
            (L[i + 2] = '''') then
    begin
      Inc(i, 3);
      AState := msLiteral;
    end
    else if L[i] = '"' then
    begin
      Inc(i);
      AOpenStr := True;
      while i <= n do
      begin
        if L[i] = '\' then
        begin
          Result[i] := ' ';
          Inc(i);
          if i <= n then begin Result[i] := ' '; Inc(i); end;
          Continue;
        end;
        if L[i] = '"' then begin Inc(i); AOpenStr := False; Break; end;
        Result[i] := ' ';
        Inc(i);
      end;
    end
    else if L[i] = '''' then
    begin
      Inc(i);
      AOpenStr := True;
      while i <= n do
      begin
        if L[i] = '''' then begin Inc(i); AOpenStr := False; Break; end;
        Result[i] := ' ';
        Inc(i);
      end;
    end
    else if L[i] = '#' then
    begin
      while i <= n do
      begin
        Result[i] := ' ';
        Inc(i);
      end;
    end
    else
      Inc(i);
  end;
end;

function BracketNet(const M: string): Integer;
var
  i: Integer;
begin
  Result := 0;
  for i := 1 to Length(M) do
    case M[i] of
      '[', '{': Inc(Result);
      ']', '}': Dec(Result);
    end;
end;

function ValidMaskedKey(const S: string): Boolean;
var
  i: Integer;
  t: string;
begin
  t := Trim(S);
  Result := t <> '';
  for i := 1 to Length(t) do
    if not (t[i] in ['A'..'Z', 'a'..'z', '0'..'9', '_', '-', '.', '"', '''',
                     ' ', #9]) then
      Exit(False);
end;

// une entree multi-ligne = UNE unite, deplacee entiere au tri
function ScanToml(const AText: string; out AUnits: TTomlUnits;
  out ATrailOpen: Boolean; out ABadStr: TIntArr): Integer;
var
  lines: TStringList;
  st: TMlState;
  i, n, eq, net, consumed: Integer;
  raw, m, t: string;
  u: TTomlUnit;
  openStr: Boolean;

  procedure Push(const AU: TTomlUnit);
  begin
    n := Length(AUnits);
    SetLength(AUnits, n + 1);
    AUnits[n] := AU;
  end;

  procedure BadStr(ALine: Integer);
  begin
    n := Length(ABadStr);
    SetLength(ABadStr, n + 1);
    ABadStr[n] := ALine;
  end;

begin
  AUnits := nil;
  ATrailOpen := False;
  ABadStr := nil;
  lines := TStringList.Create;
  lines.TextLineBreakStyle := tlbsLF;
  try
    lines.Text := AText;
    Result := lines.Count;
    st := msNone;
    i := 0;
    while i < lines.Count do
    begin
      raw := lines[i];
      m := MaskToml(raw, st, openStr);
      if openStr then BadStr(i + 1);
      u := Default(TTomlUnit);
      u.Line := i + 1;
      u.Count := 1;
      t := Trim(m);
      if t = '' then
      begin
        if Trim(raw) = '' then u.Kind := tkBlank
        else u.Kind := tkComment;
        Push(u);
        Inc(i);
        Continue;
      end;
      if t[1] = '[' then
      begin
        if (Length(t) >= 4) and (t[2] = '[') and
           (Copy(t, Length(t) - 1, 2) = ']]') then
        begin
          u.Kind := tkArrayHeader;
          eq := Pos('[[', m);
          net := Pos(']]', m);
          u.Key := Trim(Copy(raw, eq + 2, net - eq - 2));
        end
        else if t[Length(t)] = ']' then
        begin
          u.Kind := tkHeader;
          eq := Pos('[', m);
          net := LastDelimiter(']', m);
          u.Key := Trim(Copy(raw, eq + 1, net - eq - 1));
        end
        else
        begin
          u.Kind := tkBad;
          u.Why := 'bad table header';
        end;
        if (u.Kind <> tkBad) and (u.Key = '') then
        begin
          u.Kind := tkBad;
          u.Why := 'empty table name';
        end;
        Push(u);
        Inc(i);
        Continue;
      end;
      eq := Pos('=', m);
      if eq = 0 then
      begin
        u.Kind := tkBad;
        u.Why := 'not a key = value, table or comment';
        Push(u);
        Inc(i);
        Continue;
      end;
      if not ValidMaskedKey(Copy(m, 1, eq - 1)) then
      begin
        u.Kind := tkBad;
        if Trim(Copy(m, 1, eq - 1)) = '' then u.Why := 'value without a key'
        else u.Why := 'bad key';
        Push(u);
        Inc(i);
        Continue;
      end;
      u.Kind := tkEntry;
      u.Key := Trim(Copy(raw, 1, eq - 1));
      // continuation : chaine multi-ligne ouverte et/ou brackets non soldes
      net := BracketNet(Copy(m, eq + 1, MaxInt));
      consumed := 1;
      while ((st <> msNone) or (net > 0)) and (i + consumed < lines.Count) do
      begin
        m := MaskToml(lines[i + consumed], st, openStr);
        if openStr then BadStr(i + consumed + 1);
        Inc(net, BracketNet(m));
        Inc(consumed);
      end;
      if (st <> msNone) or (net > 0) then
        ATrailOpen := True;
      u.Count := consumed;
      Push(u);
      Inc(i, consumed);
    end;
  finally
    lines.Free;
  end;
end;

function TomlValidate(const AText: string): string;
const
  MAX_SHOWN = 20;
var
  units: TTomlUnits;
  outp: TStringList;
  i, nTab, nKey, nBad: Integer;
  trailOpen: Boolean;
  badStr: TIntArr;
begin
  if Length(AText) > TOML_MAX_BYTES then
    Exit(Format('text too large for the TOML scanner (max %d MB)',
      [TOML_MAX_BYTES div (1024 * 1024)]));
  ScanToml(AText, units, trailOpen, badStr);
  outp := TStringList.Create;
  outp.TextLineBreakStyle := tlbsLF;
  try
    nTab := 0; nKey := 0; nBad := 0;
    for i := 0 to High(units) do
      case units[i].Kind of
        tkHeader, tkArrayHeader: Inc(nTab);
        tkEntry: Inc(nKey);
        tkBad:
          begin
            Inc(nBad);
            if nBad <= MAX_SHOWN then
              outp.Add(Format('  line %d: %s', [units[i].Line, units[i].Why]));
          end;
      end;
    for i := 0 to High(badStr) do
    begin
      Inc(nBad);
      if nBad <= MAX_SHOWN then
        outp.Add(Format('  line %d: unterminated string', [badStr[i]]));
    end;
    if trailOpen then
    begin
      Inc(nBad);
      outp.Add('  unterminated multi-line value at end of file');
    end;
    if nBad = 0 then
      Result := Format('TOML OK: %d table(s), %d key(s). (subset check,'
        + ' values not type-validated)', [nTab, nKey])
    else
    begin
      if nBad > MAX_SHOWN + 1 then
        outp.Add(Format('  ... and %d more', [nBad - MAX_SHOWN]));
      Result := Format('%d problem(s):', [nBad]) + LineEnding + outp.Text;
    end;
  finally
    outp.Free;
  end;
end;

function TomlSortKeys(const AText: string): string;
type
  TUnit = record
    Key: string;
    Idx: Integer;
    Block: TStringList; // commentaires/vides precedents + lignes de l'entree
  end;
var
  lines, pending, outp: TStringList;
  units: array of TUnit;
  scan: TTomlUnits;
  trailOpen: Boolean;
  badStr: TIntArr;
  i, k, n: Integer;

  function UnitLess(const A, B: TUnit): Boolean;
  var
    c: Integer;
  begin
    c := CompareText(A.Key, B.Key);
    if c = 0 then c := CompareStr(A.Key, B.Key);
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
  if Length(AText) > TOML_MAX_BYTES then Exit(AText);
  lines := TStringList.Create;
  lines.TextLineBreakStyle := tlbsLF;
  pending := TStringList.Create;
  pending.TextLineBreakStyle := tlbsLF;
  outp := TStringList.Create;
  outp.TextLineBreakStyle := tlbsLF;
  units := nil;
  try
    lines.Text := AText;
    ScanToml(AText, scan, trailOpen, badStr);
    for i := 0 to High(scan) do
      case scan[i].Kind of
        tkEntry:
          begin
            n := Length(units);
            SetLength(units, n + 1);
            units[n].Key := scan[i].Key;
            units[n].Idx := n;
            units[n].Block := TStringList.Create;
            units[n].Block.TextLineBreakStyle := tlbsLF;
            units[n].Block.AddStrings(pending);
            for k := scan[i].Line - 1 to scan[i].Line + scan[i].Count - 2 do
              units[n].Block.Add(lines[k]);
            pending.Clear;
          end;
        tkHeader, tkArrayHeader:
          begin
            FlushSection;
            outp.Add(lines[scan[i].Line - 1]);
          end;
      else
        // vides, commentaires, lignes cassees : collent a ce qui SUIT
        for k := scan[i].Line - 1 to scan[i].Line + scan[i].Count - 2 do
          pending.Add(lines[k]);
      end;
    FlushSection;
    Result := outp.Text;
  finally
    for i := 0 to High(units) do
      if units[i].Block <> nil then units[i].Block.Free;
    lines.Free; pending.Free; outp.Free;
  end;
end;

function TomlFindDuplicates(const AText: string): string;
var
  scan: TTomlUnits;
  trailOpen: Boolean;
  badStr: TIntArr;
  keys, lineNos, outp: TStringList;
  i, k, cnt, arrInst: Integer;
  sect, qk: string;

  // un '=' dans une cle/table casserait le decoupage name=value TStringList
  function MapName(const S: string): string;
  begin
    Result := StringReplace(S, '=', #1, [rfReplaceAll]);
  end;

  procedure Bump(const AQk: string; ALine: Integer);
  begin
    k := lineNos.IndexOfName(MapName(AQk));
    if k < 0 then
    begin
      keys.Add(AQk);
      lineNos.Add(MapName(AQk) + '=' + IntToStr(ALine));
    end
    else
      lineNos.ValueFromIndex[k] :=
        lineNos.ValueFromIndex[k] + ' ' + IntToStr(ALine);
  end;

begin
  if Length(AText) > TOML_MAX_BYTES then Exit('(text too large)');
  ScanToml(AText, scan, trailOpen, badStr);
  keys := TStringList.Create;
  lineNos := TStringList.Create;
  lineNos.CaseSensitive := True; // cles TOML sensibles a la casse
  outp := TStringList.Create;
  outp.TextLineBreakStyle := tlbsLF;
  try
    sect := '';
    arrInst := 0;
    for i := 0 to High(scan) do
      case scan[i].Kind of
        tkHeader:
          begin
            sect := scan[i].Key;
            // [t] redeclare = illegal en TOML
            Bump('[' + scan[i].Key + ']', scan[i].Line);
          end;
        tkArrayHeader:
          begin
            // [[t]] repete = legal : chaque occurrence est un scope NEUF
            Inc(arrInst);
            sect := scan[i].Key + '#' + IntToStr(arrInst);
          end;
        tkEntry:
          begin
            if sect = '' then qk := scan[i].Key
            else qk := '[' + sect + '] ' + scan[i].Key;
            Bump(qk, scan[i].Line);
          end;
      end;
    outp.Add('# TOML duplicates (same table, case-sensitive; [[t]] scopes'
      + ' are separate)');
    cnt := 0;
    for i := 0 to keys.Count - 1 do
    begin
      k := lineNos.IndexOfName(MapName(keys[i]));
      if k < 0 then Continue;
      if Pos(' ', lineNos.ValueFromIndex[k]) > 0 then
      begin
        outp.Add('  ' + keys[i] + '  -> lines ' +
          StringReplace(Trim(lineNos.ValueFromIndex[k]), ' ', ', ',
            [rfReplaceAll]));
        Inc(cnt);
      end;
    end;
    if cnt = 0 then outp.Add('  (none)');
    Result := outp.Text;
  finally
    keys.Free; lineNos.Free; outp.Free;
  end;
end;

end.
