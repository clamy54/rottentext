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

type
  TEnvKind = (ekBlank, ekComment, ekEntry, ekOther);

// une entree a partir de la ligne AIdx, AVEC ses lignes de continuation
// (valeur citee ouverte ici, refermee plus bas : PEM, script). Rend le nombre
// de lignes consommees (>= 1). AVal garde ses quotes, EnvDecodeValue les ote.
function EnvEntryAt(ALines: TStrings; AIdx: Integer; out AKey, AVal: string;
  out AExport: Boolean; out AKind: TEnvKind): Integer;

// partage valeur / commentaire de fin (` #` hors quotes, rendu avec son
// espace de tete, '' si aucun)
procedure EnvSplitComment(const S: string; out AValue, AComment: string);
// coupe un commentaire de fin de valeur (` #` hors quotes). Quote non fermee
// = valeur multi-ligne : rien n'est coupe.
function EnvStripComment(const S: string): string;

// lecture d'une valeur dotenv : doubles quotes = echappes \n \t \r \" \\
// developpees (ce qu'EmitEnvLine ecrit, sinon JSON -> .env -> JSON rendait
// des backslashes litteraux), simples quotes = verbatim, nu = verbatim.
// Un \x inconnu reste \x : un "C:\path" ecrit a la main garde son backslash.
function EnvDecodeValue(const S: string): string;

implementation

uses
  StrUtils, fpjson, jsonparser, uJsonSafe, uYaml;

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

procedure EnvSplitComment(const S: string; out AValue, AComment: string);
var
  i, st: Integer;
  q: Char;
begin
  AComment := '';
  // la citation peut etre precedee d'espaces : `K= "texte # contenu"`
  st := 1;
  while (st <= Length(S)) and (S[st] in [' ', #9]) do Inc(st);
  q := #0;
  if (st <= Length(S)) and (S[st] in ['"', '''']) then q := S[st];
  i := 1;
  if q <> #0 then i := st + 1;
  while i <= Length(S) do
  begin
    if q <> #0 then
    begin
      // `\'` echappe aussi entre apostrophes, comme dans EnvOpenQuote
      if S[i] = '\' then Inc(i)
      else if S[i] = q then q := #0;
    end
    else if (S[i] = '#') and ((i = 1) or (S[i - 1] = ' ') or (S[i - 1] = #9)) then
    begin
      AValue := TrimRight(Copy(S, 1, i - 1));
      AComment := ' ' + Copy(S, i, MaxInt);
      Exit;
    end;
    Inc(i);
  end;
  AValue := TrimRight(S);
end;

function EnvStripComment(const S: string): string;
var
  c: string;
begin
  EnvSplitComment(S, Result, c);
end;

// quote ouverte et jamais refermee : la valeur continue sur les lignes suivantes
// `\'` traite comme un echappement (compose l'accepte). Biais assume: en
// doutant on avale une ligne de plus plutot que de laisser fuir un corps de cle.
function EnvOpenQuote(const S: string): Char;
var
  i, st: Integer;
begin
  Result := #0;
  st := 1;
  while (st <= Length(S)) and (S[st] in [' ', #9]) do Inc(st);
  if (st > Length(S)) or not (S[st] in ['"', '''']) then Exit;
  Result := S[st];
  i := st + 1;
  while i <= Length(S) do
  begin
    if S[i] = '\' then Inc(i)
    else if S[i] = Result then Exit(#0);
    Inc(i);
  end;
end;

function EnvClosesQuote(const S: string; AQuote: Char): Boolean;
var
  i: Integer;
begin
  Result := False;
  i := 1;
  while i <= Length(S) do
  begin
    if S[i] = '\' then Inc(i)
    else if S[i] = AQuote then Exit(True);
    Inc(i);
  end;
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
  // `K=value # note` : le commentaire n'appartient pas a la valeur
  AVal := EnvStripComment(Copy(work, eq + 1, MaxInt));
  Result := ekEntry;
end;

function EnvDecodeValue(const S: string): string;
var
  i: Integer;
begin
  if (Length(S) >= 2) and (S[1] = '''') and (S[Length(S)] = '''') then
    Exit(Copy(S, 2, Length(S) - 2));
  if (Length(S) < 2) or (S[1] <> '"') or (S[Length(S)] <> '"') then
    Exit(S);
  Result := '';
  i := 2;
  while i <= Length(S) - 1 do
  begin
    if (S[i] = '\') and (i < Length(S) - 1) then
      case S[i + 1] of
        'n': begin Result := Result + #10; Inc(i, 2); Continue; end;
        'r': begin Result := Result + #13; Inc(i, 2); Continue; end;
        't': begin Result := Result + #9;  Inc(i, 2); Continue; end;
        '"': begin Result := Result + '"'; Inc(i, 2); Continue; end;
        '\': begin Result := Result + '\'; Inc(i, 2); Continue; end;
      end;
    Result := Result + S[i];
    Inc(i);
  end;
end;

function EnvEntryAt(ALines: TStrings; AIdx: Integer; out AKey, AVal: string;
  out AExport: Boolean; out AKind: TEnvKind): Integer;
var
  q: Char;
  j: Integer;
  first: string;
begin
  Result := 1;
  AKind := ClassifyEnv(ALines[AIdx], AKey, AVal, AExport);
  if AKind <> ekEntry then Exit;
  q := EnvOpenQuote(AVal);
  if q = #0 then Exit;
  first := AVal;
  j := AIdx + 1;
  while j < ALines.Count do
  begin
    AVal := AVal + #10 + ALines[j];
    Inc(Result);
    if EnvClosesQuote(ALines[j], q) then
    begin
      // refermee : un commentaire apres la quote de fin saute maintenant
      AVal := EnvStripComment(AVal);
      Exit;
    end;
    Inc(j);
  end;
  // jamais refermee : ligne cassee (dotenv la rejette), pas une valeur qui
  // avalerait le reste du fichier
  Result := 1;
  AVal := first;
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
  i, j, n, used: Integer;
  key, val: string; exp: Boolean;
  kind: TEnvKind;

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
    i := 0;
    while i < lines.Count do
    begin
      used := EnvEntryAt(lines, i, key, val, exp, kind);
      if kind = ekEntry then
      begin
        n := Length(units);
        SetLength(units, n + 1);
        units[n].Key := key;
        units[n].Idx := n;
        units[n].Block := TStringList.Create;
        units[n].Block.TextLineBreakStyle := tlbsLF;
        units[n].Block.AddStrings(pending);
        // une valeur multi-ligne voyage avec sa cle, sinon le tri eparpille
        // le corps d'un PEM entre les autres entrees
        for j := 0 to used - 1 do
          units[n].Block.Add(lines[i + j]);
        pending.Clear;
      end
      else
        pending.Add(lines[i]);
      Inc(i, used);
    end;

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
  i, k, cnt, used: Integer;
  key, val, upk: string; exp: Boolean;
  kind: TEnvKind;
begin
  lines := SplitLines(AText);
  keys := TStringList.Create;
  lineNos := TStringList.Create;   // key(upper) -> "n1 n2 n3"
  lineNos.CaseSensitive := True;
  outp := TStringList.Create;
  outp.TextLineBreakStyle := tlbsLF;
  try
    i := 0;
    while i < lines.Count do
    begin
      used := EnvEntryAt(lines, i, key, val, exp, kind);
      if kind = ekEntry then
      begin
        upk := key; // KEY et key sont deux variables (dotenv, shell)
        k := lineNos.IndexOfName(upk);
        if k < 0 then
        begin
          keys.Add(key);
          lineNos.Add(upk + '=' + IntToStr(i + 1));
        end
        else
          lineNos.ValueFromIndex[k] := lineNos.ValueFromIndex[k] + ' ' + IntToStr(i + 1);
      end;
      Inc(i, used); // le corps d'une valeur multi-ligne n'est pas une cle
    end;

    outp.Add('# .env duplicate keys (dotenv: last one wins)');
    cnt := 0;
    for i := 0 to keys.Count - 1 do
    begin
      k := lineNos.IndexOfName(keys[i]);
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
  i, j, used: Integer;
  key, val: string;
  exp, changed: Boolean;
  kind: TEnvKind;
begin
  lines := SplitLines(AText);
  outp := TStringList.Create;
  outp.TextLineBreakStyle := tlbsLF;
  try
    i := 0;
    while i < lines.Count do
    begin
      used := EnvEntryAt(lines, i, key, val, exp, kind);
      if (kind = ekEntry) and LooksSecret(key) then
      begin
        // le corps d'un secret multi-ligne (PEM) n'est jamais recopie ; une
        // quote jamais refermee compte pour une ligne, le reste du fichier
        // n'est pas avale
        if exp then outp.Add('export ' + key + '=****')
        else outp.Add(key + '=****');
      end
      else
        // verbatim, mais une URL a creds fuiterait : scrubee meme en commentaire
        for j := 0 to used - 1 do
          outp.Add(RedactUrlCreds(lines[i + j], changed));
      Inc(i, used);
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
  kind: TEnvKind;
begin
  lines := SplitLines(AText);
  obj := TJSONObject.Create;
  try
    i := 0;
    while i < lines.Count do
    begin
      Inc(i, EnvEntryAt(lines, i, key, val, exp, kind));
      if kind <> ekEntry then Continue;
      val := EnvDecodeValue(Trim(val));
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
    (Pos(#9, S) > 0) or (Pos('#', S) > 0) or (Pos('=', S) > 0) or (S <> Trim(S)) or
    // "x" nu serait relu comme x : les quotes de la valeur passent en echappes
    ((S <> '') and (S[1] in ['"', '''']));
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
    Exit('# skipped invalid key: ' + OneLine(AKey + '=' + AValue));
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
      root := SafeGetJSON(data);
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
  i, j, used: Integer;
  key, val, v, pfx, cmt: string;
  exp: Boolean;
  kind: TEnvKind;
begin
  lines := SplitLines(AText);
  outp := TStringList.Create;
  outp.TextLineBreakStyle := tlbsLF;
  try
    i := 0;
    while i < lines.Count do
    begin
      used := EnvEntryAt(lines, i, key, val, exp, kind);
      v := Trim(val);
      // re-quoter double-echapperait les \" internes ; une valeur sur
      // plusieurs lignes est deja quotee par construction
      if (kind = ekEntry) and (used = 1) and not IsQuoted(v) then
      begin
        if exp then pfx := 'export ' else pfx := '';
        // ClassifyEnv a coupe le ` # note` : le remettre, il appartient a l'utilisateur
        EnvSplitComment(Copy(lines[i], Pos('=', lines[i]) + 1, MaxInt), v, cmt);
        outp.Add(pfx + key + '=' + EnvQuote(Trim(v)) + cmt);
      end
      else
        for j := 0 to used - 1 do
          outp.Add(lines[i + j]);
      Inc(i, used);
    end;
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
  i, j, used: Integer;
  key, val, v, inner, pfx, cmt: string;
  exp: Boolean;
  kind: TEnvKind;
begin
  lines := SplitLines(AText);
  outp := TStringList.Create;
  outp.TextLineBreakStyle := tlbsLF;
  try
    i := 0;
    while i < lines.Count do
    begin
      used := EnvEntryAt(lines, i, key, val, exp, kind);
      v := Trim(val);
      inner := Copy(v, 2, Length(v) - 2);
      if (kind = ekEntry) and (used = 1) and IsQuoted(v) and SafeBare(inner) then
      begin
        if exp then pfx := 'export ' else pfx := '';
        EnvSplitComment(Copy(lines[i], Pos('=', lines[i]) + 1, MaxInt), v, cmt);
        outp.Add(pfx + key + '=' + inner + cmt);
      end
      else
        for j := 0 to used - 1 do
          outp.Add(lines[i + j]);
      Inc(i, used);
    end;
    Result := outp.Text;
  finally
    lines.Free; outp.Free;
  end;
end;

function EnvToYaml(const AText: string): string;
var
  lines, outp, last: TStringList;
  i, st: Integer;
  key, val: string;
  exp: Boolean;
  kind: TEnvKind;
begin
  lines := SplitLines(AText);
  outp := TStringList.Create;
  outp.TextLineBreakStyle := tlbsLF;
  last := TStringList.Create;
  last.CaseSensitive := True;
  try
    // dotenv : dernier gagne. Emettre les deux ferait un YAML a cle en
    // double, que tout parseur refuse
    i := 0;
    while i < lines.Count do
    begin
      st := i;
      Inc(i, EnvEntryAt(lines, i, key, val, exp, kind));
      if kind = ekEntry then last.Values[key] := IntToStr(st);
    end;
    i := 0;
    while i < lines.Count do
    begin
      st := i;
      Inc(i, EnvEntryAt(lines, i, key, val, exp, kind));
      case kind of
        ekEntry:
          if last.Values[key] = IntToStr(st) then
            YamlEmitScalar(outp, key + ': ', EnvDecodeValue(Trim(val)), 0)
          else
            outp.Add('# duplicate key ' + key + ' (last one wins)');
        ekBlank: outp.Add('');
        ekComment: outp.Add(lines[st]);
      else
        outp.Add('# skipped (not KEY=value): ' + OneLine(lines[st]));
      end;
    end;
    Result := outp.Text;
  finally
    lines.Free; outp.Free; last.Free;
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
