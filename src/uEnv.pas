unit uEnv;

{$mode objfpc}{$H+}

// Outils .env (dotenv : `KEY=value`, `export ` tolere, `#` = commentaire).
// EnvRedact = HEURISTIQUE best-effort : a relire avant partage.

interface

uses
  Classes, SysUtils;

function EnvSortKeys(const AText: string): string;
function EnvFindDuplicates(const AText: string): string;
function EnvRedact(const AText: string): string;
function EnvToJson(const AText: string): string;
function EnvFromJson(const AText: string; out AErr: string): string;

// idempotents : une valeur deja quotee n'est jamais re-quotee
function EnvQuoteValues(const AText: string): string;
function EnvUnquoteValues(const AText: string): string;

// FromYaml : map racine seulement, valeurs imbriquees sautees, commentaires perdus.
function EnvToYaml(const AText: string): string;
function EnvFromYaml(const AText: string; out AErr: string): string;

// cle validee + valeur quotee/echappee : le seul emetteur .env anti-injection
function EmitEnvLine(const AKey, AValue: string): string;

implementation

uses
  StrUtils, fpjson, jsonparser, uYaml;

type
  TEnvKind = (ekBlank, ekComment, ekEntry, ekOther);

function ValidEnvKey(const K: string): Boolean;
var
  i: Integer;
begin
  Result := False;
  if K = '' then Exit;
  if not (K[1] in ['A'..'Z', 'a'..'z', '_']) then Exit;
  for i := 2 to Length(K) do
    if not (K[i] in ['A'..'Z', 'a'..'z', '0'..'9', '_', '.', '-']) then Exit;
  Result := True;
end;

function ClassifyEnv(const ALine: string; out AKey, AVal: string;
  out AExport: Boolean): TEnvKind;
var
  work: string;
  eq: Integer;
begin
  AKey := ''; AVal := ''; AExport := False;
  if Trim(ALine) = '' then Exit(ekBlank);
  if TrimLeft(ALine)[1] = '#' then Exit(ekComment);
  work := TrimLeft(ALine);
  if Copy(work, 1, 7) = 'export ' then
  begin
    AExport := True;
    work := TrimLeft(Copy(work, 8, MaxInt));
  end;
  eq := Pos('=', work);
  if eq = 0 then Exit(ekOther);
  AKey := Trim(Copy(work, 1, eq - 1));
  if not ValidEnvKey(AKey) then Exit(ekOther);
  AVal := Copy(work, eq + 1, MaxInt);
  Result := ekEntry;
end;

function StripQuotes(const S: string): string;
begin
  Result := S;
  if Length(Result) >= 2 then
    if ((Result[1] = '"') and (Result[Length(Result)] = '"')) or
       ((Result[1] = '''') and (Result[Length(Result)] = '''')) then
      Result := Copy(Result, 2, Length(Result) - 2);
end;

function SplitLines(const AText: string): TStringList;
begin
  Result := TStringList.Create;
  Result.TextLineBreakStyle := tlbsLF;
  Result.Text := AText;
end;

function EnvSortKeys(const AText: string): string;
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
  key, val: string; exp: Boolean;

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

begin
  lines := SplitLines(AText);
  pending := TStringList.Create;
  pending.TextLineBreakStyle := tlbsLF;
  outp := TStringList.Create;
  outp.TextLineBreakStyle := tlbsLF;
  units := nil;
  try
    for i := 0 to lines.Count - 1 do
      if ClassifyEnv(lines[i], key, val, exp) = ekEntry then
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
      end
      else
        pending.Add(lines[i]);

    if Length(units) > 1 then
      QSort(0, High(units));

    for i := 0 to High(units) do
    begin
      outp.AddStrings(units[i].Block);
      units[i].Block.Free;
      units[i].Block := nil;
    end;
    outp.AddStrings(pending);
    Result := outp.Text;
  finally
    for i := 0 to High(units) do
      if units[i].Block <> nil then units[i].Block.Free;
    lines.Free; pending.Free; outp.Free;
  end;
end;

function EnvFindDuplicates(const AText: string): string;
var
  lines, keys, lineNos, outp: TStringList;
  i, k, cnt: Integer;
  key, val, upk: string; exp: Boolean;
begin
  lines := SplitLines(AText);
  keys := TStringList.Create;
  lineNos := TStringList.Create;   // key(upper) -> "n1 n2 n3"
  lineNos.CaseSensitive := True;
  outp := TStringList.Create;
  outp.TextLineBreakStyle := tlbsLF;
  try
    for i := 0 to lines.Count - 1 do
      if ClassifyEnv(lines[i], key, val, exp) = ekEntry then
      begin
        upk := UpperCase(key);
        k := lineNos.IndexOfName(upk);
        if k < 0 then
        begin
          keys.Add(key);
          lineNos.Add(upk + '=' + IntToStr(i + 1));
        end
        else
          lineNos.ValueFromIndex[k] := lineNos.ValueFromIndex[k] + ' ' + IntToStr(i + 1);
      end;

    outp.Add('# .env duplicate keys (dotenv: last one wins)');
    cnt := 0;
    for i := 0 to keys.Count - 1 do
    begin
      k := lineNos.IndexOfName(UpperCase(keys[i]));
      if k < 0 then Continue;
      if Pos(' ', lineNos.ValueFromIndex[k]) > 0 then // au moins 2 numeros
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

// heuristique, sur-masquage assume. URL/URI/DSN absents : une URL publique
// n'est pas un secret, seuls ses creds le sont (RedactUrlCreds).
function LooksSecret(const AKey: string): Boolean;
const
  MARKERS: array[0..12] of string =
    ('PASS', 'PWD', 'SECRET', 'TOKEN', 'APIKEY', 'API_KEY', 'ACCESS_KEY',
     'PRIVATE', 'CREDENTIAL', 'PASSPHRASE', 'AUTH', 'COOKIE', 'SESSION');
var
  up: string;
  i: Integer;
begin
  Result := False;
  up := UpperCase(AKey);
  for i := 0 to High(MARKERS) do
    if Pos(MARKERS[i], up) > 0 then Exit(True);
end;

// & ; = \ , ( ) exclus : legaux dans un pass ou un DN LDAP. Biais assume :
// `host:port,x@mail` est indiscernable d'un pass, donc sur-masque.
function IsUserinfoEnd(c: Char): Boolean; inline;
begin
  Result := c in ['/', '?', '#', ' ', #9, #13, #10, '"', ''''];
end;

function RedactUrlCreds(const S: string; out AChanged: Boolean): string;
var
  i, n, j, atPos, colonPos: Integer;
  res: string;
begin
  AChanged := False;
  n := Length(S);
  res := '';
  i := 1;
  while i <= n do
  begin
    if (i + 2 <= n) and (S[i] = ':') and (S[i + 1] = '/') and (S[i + 2] = '/') then
    begin
      j := i + 3;
      atPos := 0; colonPos := 0;
      while j <= n do
      begin
        if S[j] = '@' then begin atPos := j; Break; end;
        if IsUserinfoEnd(S[j]) then Break;
        if (S[j] = ':') and (colonPos = 0) then colonPos := j;
        Inc(j);
      end;
      if (atPos > 0) and (colonPos > 0) then
      begin
        res := res + '://' + Copy(S, i + 3, colonPos - (i + 3) + 1) + '****';
        AChanged := True;
        i := atPos;
        Continue;
      end;
      res := res + '://';
      Inc(i, 3);
    end
    else
    begin
      res := res + S[i];
      Inc(i);
    end;
  end;
  Result := res;
end;

function EnvRedact(const AText: string): string;
var
  lines, outp: TStringList;
  i: Integer;
  key, val, ln: string;
  exp, changed: Boolean;
begin
  lines := SplitLines(AText);
  outp := TStringList.Create;
  outp.TextLineBreakStyle := tlbsLF;
  try
    for i := 0 to lines.Count - 1 do
    begin
      ln := lines[i];
      if (ClassifyEnv(ln, key, val, exp) = ekEntry) and LooksSecret(key) then
      begin
        if exp then outp.Add('export ' + key + '=****')
        else outp.Add(key + '=****');
      end
      else
        // verbatim, mais une URL a creds fuiterait : scrubee meme en commentaire
        outp.Add(RedactUrlCreds(ln, changed));
    end;
    Result := outp.Text;
  finally
    lines.Free; outp.Free;
  end;
end;

function EnvToJson(const AText: string): string;
var
  lines: TStringList;
  obj: TJSONObject;
  i, k: Integer;
  key, val: string; exp: Boolean;
begin
  lines := SplitLines(AText);
  obj := TJSONObject.Create;
  try
    for i := 0 to lines.Count - 1 do
      if ClassifyEnv(lines[i], key, val, exp) = ekEntry then
      begin
        val := StripQuotes(Trim(val));
        // dotenv : dernier gagne
        k := obj.IndexOfName(key);
        if k >= 0 then obj.Delete(k);
        obj.Add(key, val); // toujours une chaine : .env n'a pas de types
      end;
    Result := obj.FormatJSON;
  finally
    obj.Free;
    lines.Free;
  end;
end;

// CR/LF -> quotes obligatoires : anti-injection de ligne
function NeedsEnvQuote(const S: string): Boolean;
begin
  Result := (Pos(#10, S) > 0) or (Pos(#13, S) > 0) or (Pos(' ', S) > 0) or
    (Pos(#9, S) > 0) or (Pos('#', S) > 0) or (Pos('=', S) > 0) or (S <> Trim(S));
end;

function EnvQuote(const S: string): string;
var
  t: string;
begin
  t := StringReplace(S, '\', '\\', [rfReplaceAll]);
  t := StringReplace(t, '"', '\"', [rfReplaceAll]);
  t := StringReplace(t, #13, '\r', [rfReplaceAll]);
  t := StringReplace(t, #10, '\n', [rfReplaceAll]);
  t := StringReplace(t, #9, '\t', [rfReplaceAll]);
  Result := '"' + t + '"';
end;

function OneLine(const S: string): string;
var
  i: Integer;
begin
  Result := S;
  for i := 1 to Length(Result) do
    if Result[i] < ' ' then Result[i] := ' ';
  if Length(Result) > 80 then Result := Copy(Result, 1, 80) + '...';
end;

function EmitEnvLine(const AKey, AValue: string): string;
var
  k: string;
begin
  k := Trim(AKey);
  if not ValidEnvKey(k) then
    Exit('# skipped invalid key: ' + OneLine(AKey));
  if NeedsEnvQuote(AValue) then
    Result := k + '=' + EnvQuote(AValue)
  else
    Result := k + '=' + AValue;
end;

function EnvFromJson(const AText: string; out AErr: string): string;
var
  data: string;
  root: TJSONData;
  obj: TJSONObject;
  outp: TStringList;
  i, skipped: Integer;
  jd: TJSONData;
  v: string;
begin
  AErr := '';
  Result := '';
  data := AText;
  // BOM UTF-8 : GetJSON le refuse
  if (Length(data) >= 3) and (data[1] = #$EF) and (data[2] = #$BB) and
     (data[3] = #$BF) then Delete(data, 1, 3);
  root := nil;
  try
    try
      root := GetJSON(data);
    except
      on ex: Exception do begin AErr := ex.Message; Exit; end;
    end;
    if (root = nil) or (root.JSONType <> jtObject) then
    begin
      AErr := 'expected a flat JSON object';
      Exit;
    end;
    obj := TJSONObject(root);
    outp := TStringList.Create;
    outp.TextLineBreakStyle := tlbsLF;
    try
      skipped := 0;
      for i := 0 to obj.Count - 1 do
      begin
        jd := obj.Items[i];
        if jd.JSONType in [jtObject, jtArray] then
        begin
          Inc(skipped);
          Continue;
        end;
        if jd.JSONType = jtNull then v := '' else v := jd.AsString;
        outp.Add(EmitEnvLine(obj.Names[i], v));
      end;
      if skipped > 0 then
        outp.Add('# ' + IntToStr(skipped) + ' nested value(s) skipped (not flat)');
      Result := outp.Text;
    finally
      outp.Free;
    end;
  finally
    root.Free;
  end;
end;

function IsQuoted(const S: string): Boolean;
begin
  Result := (Length(S) >= 2) and
    (((S[1] = '"') and (S[Length(S)] = '"')) or
     ((S[1] = '''') and (S[Length(S)] = '''')));
end;

function EnvQuoteValues(const AText: string): string;
var
  lines, outp: TStringList;
  i: Integer;
  key, val, v, pfx: string;
  exp: Boolean;
begin
  lines := SplitLines(AText);
  outp := TStringList.Create;
  outp.TextLineBreakStyle := tlbsLF;
  try
    for i := 0 to lines.Count - 1 do
      if ClassifyEnv(lines[i], key, val, exp) = ekEntry then
      begin
        v := Trim(val);
        // re-quoter double-echapperait les \" internes
        if IsQuoted(v) then
          outp.Add(lines[i])
        else
        begin
          if exp then pfx := 'export ' else pfx := '';
          outp.Add(pfx + key + '=' + EnvQuote(v));
        end;
      end
      else
        outp.Add(lines[i]);
    Result := outp.Text;
  finally
    lines.Free; outp.Free;
  end;
end;

// la valeur nue reparse-t-elle a l'identique ? sinon on garde les quotes
function SafeBare(const S: string): Boolean;
var
  i: Integer;
begin
  Result := False;
  if S = '' then Exit; // K= marche mais K="" dit mieux l'intention, garde
  for i := 1 to Length(S) do
    if S[i] in [' ', #9, '#', '"', '''', '\'] then Exit;
  Result := True;
end;

function EnvUnquoteValues(const AText: string): string;
var
  lines, outp: TStringList;
  i: Integer;
  key, val, v, inner, pfx: string;
  exp: Boolean;
begin
  lines := SplitLines(AText);
  outp := TStringList.Create;
  outp.TextLineBreakStyle := tlbsLF;
  try
    for i := 0 to lines.Count - 1 do
      if ClassifyEnv(lines[i], key, val, exp) = ekEntry then
      begin
        v := Trim(val);
        inner := Copy(v, 2, Length(v) - 2);
        if IsQuoted(v) and SafeBare(inner) then
        begin
          if exp then pfx := 'export ' else pfx := '';
          outp.Add(pfx + key + '=' + inner);
        end
        else
          outp.Add(lines[i]);
      end
      else
        outp.Add(lines[i]);
    Result := outp.Text;
  finally
    lines.Free; outp.Free;
  end;
end;

function EnvToYaml(const AText: string): string;
var
  lines, outp: TStringList;
  i: Integer;
  key, val: string;
  exp: Boolean;
begin
  lines := SplitLines(AText);
  outp := TStringList.Create;
  outp.TextLineBreakStyle := tlbsLF;
  try
    for i := 0 to lines.Count - 1 do
      case ClassifyEnv(lines[i], key, val, exp) of
        ekEntry: outp.Add(key + ': ' + YamlQuoteScalar(StripQuotes(Trim(val))));
        ekBlank: outp.Add('');
        ekComment: outp.Add(lines[i]);
      else
        outp.Add('# skipped (not KEY=value): ' + OneLine(lines[i]));
      end;
    Result := outp.Text;
  finally
    lines.Free; outp.Free;
  end;
end;

function EnvFromYaml(const AText: string; out AErr: string): string;
var
  root: TYamlNode;
  outp: TStringList;
  i, skipped: Integer;
begin
  AErr := '';
  Result := '';
  root := YamlParse(AText, AErr);
  if root = nil then Exit;
  try
    if root.Kind <> ykMap then
    begin
      AErr := 'expected a flat YAML mapping at the root';
      Exit;
    end;
    outp := TStringList.Create;
    outp.TextLineBreakStyle := tlbsLF;
    try
      skipped := 0;
      for i := 0 to High(root.Keys) do
        if root.Vals[i].Kind = ykScalar then
          outp.Add(EmitEnvLine(root.Keys[i], root.Vals[i].Scalar))
        else
          Inc(skipped);
      if skipped > 0 then
        outp.Add('# ' + IntToStr(skipped) + ' nested value(s) skipped (not flat)');
      Result := outp.Text;
    finally
      outp.Free;
    end;
  finally
    root.Free;
  end;
end;

end.
