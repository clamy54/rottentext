unit uYaml;

{$mode objfpc}{$H+}

// Mini-YAML : sous-ensemble BLOC seulement (un doc, pas de flow non vide).
// Ancres/alias jamais expanses (gardes litteraux) : pas de "billion laughs".
// Entree non fiable : plafonds taille/lignes/profondeur -> EYamlError.

interface

uses
  Classes, SysUtils;

type
  EYamlError = class(Exception);

  TYamlKind = (ykScalar, ykMap, ykList);

  TYamlNode = class
  public
    Kind: TYamlKind;
    Scalar: string;
    // scalaire tel qu'ecrit (une ligne, commentaire retire) : reemis tel quel
    // sinon 8080 / true / [a, b] ressortent quotes = type change. '' = aucun
    Raw: string;
    Keys: array of string;
    KeyRaws: array of string;   // idem pour les cles (on: / 80: / "80":)
    Vals: array of TYamlNode;   // paralleles a Keys
    Items: array of TYamlNode;
    constructor Create(AKind: TYamlKind);
    destructor Destroy; override;
    function Count: Integer;
    function ChildByKey(const AKey: string): TYamlNode;
    procedure SetPair(const AKey: string; ANode: TYamlNode; const ARaw: string = '');
    procedure PushItem(ANode: TYamlNode);
  end;

// nil + AErr si malforme. L'appelant possede et libere la racine.
function YamlParse(const AText: string; out AErr: string): TYamlNode;

procedure YamlFlatten(ANode: TYamlNode; ADest: TStrings);

procedure YamlFlattenKV(ANode: TYamlNode; AKeys, AVals: TStrings);

function YamlValuesDiff(A, B: TYamlNode; const ANameA, ANameB: string): string;

function YamlEmit(ANode: TYamlNode): string;

// IN PLACE. Les listes gardent leur ordre.
procedure YamlSortKeys(ANode: TYamlNode);

function YamlQuoteScalar(const S: string): string;

// APrefix + scalaire ; multi-ligne = bloc litteral |, contenu a AIndent+2
procedure YamlEmitScalar(ASL: TStrings; const APrefix, S: string; AIndent: Integer);

const
  YAML_MAX_BYTES = 8 * 1024 * 1024;
  YAML_MAX_LINES = 400000;
  YAML_MAX_DEPTH = 100;

implementation

constructor TYamlNode.Create(AKind: TYamlKind);
begin
  inherited Create;
  Kind := AKind;
end;

destructor TYamlNode.Destroy;
var
  i: Integer;
begin
  for i := 0 to High(Vals) do Vals[i].Free;
  for i := 0 to High(Items) do Items[i].Free;
  inherited Destroy;
end;

function TYamlNode.Count: Integer;
begin
  case Kind of
    ykMap:  Result := Length(Keys);
    ykList: Result := Length(Items);
    else    Result := 0;
  end;
end;

function TYamlNode.ChildByKey(const AKey: string): TYamlNode;
var
  i: Integer;
begin
  Result := nil;
  for i := 0 to High(Keys) do
    if Keys[i] = AKey then Exit(Vals[i]);
end;

procedure TYamlNode.SetPair(const AKey: string; ANode: TYamlNode; const ARaw: string);
var
  i, n: Integer;
begin
  for i := 0 to High(Keys) do
    if Keys[i] = AKey then
    begin
      // cle en double : dernier gagne
      Vals[i].Free;
      Vals[i] := ANode;
      KeyRaws[i] := ARaw;
      Exit;
    end;
  n := Length(Keys);
  SetLength(Keys, n + 1);
  SetLength(KeyRaws, n + 1);
  SetLength(Vals, n + 1);
  Keys[n] := AKey;
  KeyRaws[n] := ARaw;
  Vals[n] := ANode;
end;

procedure TYamlNode.PushItem(ANode: TYamlNode);
var
  n: Integer;
begin
  n := Length(Items);
  SetLength(Items, n + 1);
  Items[n] := ANode;
end;

type
  TYLine = record
    Indent: Integer;
    Content: string;   // sans indentation, commentaire inclus
    Blank: Boolean;    // vide ou commentaire seul -> saute structurellement
    Empty: Boolean;    // vraiment vide (Blank couvre aussi # et ---)
    LineNo: Integer;
  end;
  TYLines = array of TYLine;

// un `#` n'ouvre un commentaire qu'en tete ou apres un blanc, hors quote
function StripComment(const S: string): string;
var
  i: Integer;
  q: Char;
begin
  q := #0;
  i := 1;
  while i <= Length(S) do
  begin
    if q <> #0 then
    begin
      if S[i] = q then q := #0;
    end
    // une quote n'ouvre qu'en tete de scalaire : don't panic # note
    else if ((S[i] = '"') or (S[i] = '''')) and
            ((i = 1) or (S[i - 1] in [' ', #9, '-', '['])) then
      q := S[i]
    else if (S[i] = '#') and ((i = 1) or (S[i - 1] = ' ') or (S[i - 1] = #9)) then
    begin
      Result := TrimRight(Copy(S, 1, i - 1));
      Exit;
    end;
    Inc(i);
  end;
  Result := TrimRight(S);
end;

procedure Preprocess(const AText: string; out L: TYLines);
var
  raw: TStringList;
  i, j, ind: Integer;
  ln, body: string;
begin
  raw := TStringList.Create;
  try
    raw.TextLineBreakStyle := tlbsLF;
    raw.Text := StringReplace(StringReplace(AText, #13#10, #10, [rfReplaceAll]),
      #13, #10, [rfReplaceAll]);
    if raw.Count > YAML_MAX_LINES then
      raise EYamlError.CreateFmt('too many lines (%d)', [raw.Count]);
    SetLength(L, raw.Count);
    for i := 0 to raw.Count - 1 do
    begin
      ln := raw[i];
      // seuls les espaces indentent ; une tab reste dans le contenu (Makefile
      // dans un bloc |) et n'est refusee que sur une ligne structurelle
      ind := 0;
      j := 1;
      while (j <= Length(ln)) and (ln[j] = ' ') do
      begin
        Inc(ind);
        Inc(j);
      end;
      body := Copy(ln, j, MaxInt);
      L[i].LineNo := i + 1;
      L[i].Indent := ind;
      L[i].Content := body;
      L[i].Empty := Trim(body) = '';
      L[i].Blank := L[i].Empty or (body[1] = '#') or (body = '---') or (body = '...');
    end;
  finally
    raw.Free;
  end;
end;

// retire l'ancre de tete `&nom` ; un alias `*nom` reste LITTERAL, jamais resolu
function StripLeadingAnchor(const S: string): string;
var
  t: string;
  i: Integer;
begin
  t := Trim(S);
  if (t <> '') and (t[1] = '&') then
  begin
    i := 2;
    while (i <= Length(t)) and (t[i] <> ' ') do Inc(i);
    Result := Trim(Copy(t, i, MaxInt));
  end
  else
    Result := t;
end;

// \xXX \uXXXX \UXXXXXXXX -> UTF-8 ; hex incomplet = texte garde tel quel
function HexEscape(const T: string; var I: Integer; ADigits: Integer): string;
var
  k, v: Integer;
begin
  Result := '';
  if I + ADigits > Length(T) then Exit;
  v := 0;
  for k := 1 to ADigits do
    case T[I + k] of
      '0'..'9': v := v * 16 + Ord(T[I + k]) - Ord('0');
      'a'..'f': v := v * 16 + Ord(T[I + k]) - Ord('a') + 10;
      'A'..'F': v := v * 16 + Ord(T[I + k]) - Ord('A') + 10;
      else Exit;
    end;
  if (v > $10FFFF) or ((v >= $D800) and (v <= $DFFF)) then Exit;
  if v < $10000 then
    Result := UTF8Encode(UnicodeString(WideChar(v)))
  else
    Result := UTF8Encode(UnicodeString(WideChar($D800 + ((v - $10000) shr 10)))
      + UnicodeString(WideChar($DC00 + ((v - $10000) and $3FF))));
  Inc(I, ADigits);
end;

function Unquote(const S: string): string;
var
  t, h: string;
  i: Integer;
  c: Char;
begin
  t := Trim(S);
  if Length(t) >= 2 then
  begin
    if (t[1] = '''') and (t[Length(t)] = '''') then
    begin
      Result := StringReplace(Copy(t, 2, Length(t) - 2), '''''', '''', [rfReplaceAll]);
      Exit;
    end;
    if (t[1] = '"') and (t[Length(t)] = '"') then
    begin
      Result := '';
      i := 2;
      while i <= Length(t) - 1 do
      begin
        c := t[i];
        if (c = '\') and (i < Length(t) - 1) then
        begin
          Inc(i);
          case t[i] of
            'n': Result := Result + #10;
            't': Result := Result + #9;
            'r': Result := Result + #13;
            '"': Result := Result + '"';
            '\': Result := Result + '\';
            '0': Result := Result + #0;
            'x', 'u', 'U':
              begin
                case t[i] of
                  'x': h := HexEscape(t, i, 2);
                  'u': h := HexEscape(t, i, 4);
                  else h := HexEscape(t, i, 8);
                end;
                if h = '' then Result := Result + '\' + t[i]
                else Result := Result + h;
              end;
            else Result := Result + t[i];
          end;
        end
        else
          Result := Result + c;
        Inc(i);
      end;
      Exit;
    end;
  end;
  Result := t;
end;

// 0 si la ligne n'est pas une entree de map
function MapColon(const S: string): Integer;
var
  i: Integer;
  q: Char;
begin
  Result := 0;
  q := #0;
  i := 1;
  while i <= Length(S) do
  begin
    if q <> #0 then
    begin
      if S[i] = q then q := #0;
    end
    else if ((S[i] = '"') or (S[i] = '''')) and
            ((i = 1) or (S[i - 1] in [' ', #9, '-', '['])) then
      q := S[i]
    else if S[i] = ':' then
    begin
      if (i = Length(S)) or (S[i + 1] = ' ') then Exit(i);
    end;
    Inc(i);
  end;
end;

function IsListLine(const S: string): Boolean;
begin
  Result := (S = '-') or ((Length(S) >= 2) and (S[1] = '-') and (S[2] = ' '));
end;

function BlockScalarChar(const S: string; out AChomp: Char): Char;
var
  t: string;
  i: Integer;
begin
  Result := #0;
  AChomp := #0;
  t := Trim(S);
  if (t = '') or ((t[1] <> '|') and (t[1] <> '>')) then Exit;
  for i := 2 to Length(t) do
    if not (t[i] in ['+', '-', '0'..'9']) then Exit;
  Result := t[1];
  for i := 2 to Length(t) do
    if (t[i] = '+') or (t[i] = '-') then AChomp := t[i];
end;

type
  TYamlParser = class
    L: TYLines;
    N: Integer;
    procedure SkipBlanks(var idx: Integer);
    procedure CheckTab(idx: Integer);
    function PlainContinuation(var idx: Integer; blockIndent: Integer;
      const AFirst: string): string;
    function ParseBlockScalar(var idx: Integer; blockIndent: Integer;
      kindCh, chomp: Char): string;
    function ParseNode(var idx: Integer; minIndent, depth: Integer): TYamlNode;
  end;

procedure TYamlParser.SkipBlanks(var idx: Integer);
begin
  while (idx < N) and L[idx].Blank do Inc(idx);
end;

procedure TYamlParser.CheckTab(idx: Integer);
begin
  if (L[idx].Content <> '') and (L[idx].Content[1] = #9) then
    raise EYamlError.CreateFmt('tab in indentation, line %d', [L[idx].LineNo]);
end;

// scalaire nu replie sur des lignes plus indentees : `desc: un long`
// / `  texte` = une valeur. idx pointe APRES la premiere ligne, avance sur
// chaque ligne absorbee. Quotes multi-lignes non gerees (restent une erreur)
function TYamlParser.PlainContinuation(var idx: Integer; blockIndent: Integer;
  const AFirst: string): string;
var
  c: string;
begin
  Result := AFirst;
  if (AFirst = '') or (AFirst[1] in ['"', '''', '[', '{', '*']) then Exit;
  while idx < N do
  begin
    if L[idx].Empty then Break;
    if L[idx].Blank or (L[idx].Indent <= blockIndent) then Break;
    c := StripComment(L[idx].Content);
    if (c = '') or IsListLine(c) or (MapColon(c) > 0) then Break;
    Result := Result + ' ' + c;
    Inc(idx);
  end;
end;

function TYamlParser.ParseBlockScalar(var idx: Integer; blockIndent: Integer;
  kindCh, chomp: Char): string;
var
  first, rel, trail: Integer;
  parts: TStringList;
  sb: TStringBuilder;
  i: Integer;
begin
  parts := TStringList.Create;
  try
    first := -1;
    while idx < N do
    begin
      if L[idx].Empty then
      begin
        parts.Add('');
        Inc(idx);
        Continue;
      end;
      // un # ou --- plus indente est du contenu (#!/bin/bash en tete de
      // script), moins indente ferme le bloc
      if L[idx].Indent <= blockIndent then Break;
      if first < 0 then first := L[idx].Indent;
      rel := L[idx].Indent - first;
      if rel < 0 then rel := 0;
      parts.Add(StringOfChar(' ', rel) + L[idx].Content);
      Inc(idx);
    end;
    trail := 0;
    while (parts.Count > 0) and (parts[parts.Count - 1] = '') do
    begin
      parts.Delete(parts.Count - 1);
      Inc(trail);
    end;

    // pas de concat : `txt := txt + parts[i]` est O(n^2) sur un gros bloc
    sb := TStringBuilder.Create;
    try
      if kindCh = '>' then
      begin
        for i := 0 to parts.Count - 1 do
          if parts[i] = '' then
            sb.Append(#10)
          else if (sb.Length = 0) or (sb.Chars[sb.Length - 1] = #10) then
            sb.Append(parts[i])
          else
          begin
            sb.Append(' ');
            sb.Append(parts[i]);
          end;
      end
      else
      begin
        for i := 0 to parts.Count - 1 do
        begin
          if i > 0 then sb.Append(#10);
          sb.Append(parts[i]);
        end;
      end;
      // chomp : - rien, defaut = 1 seul \n final, + garde tout
      if (parts.Count > 0) and (chomp <> '-') then
      begin
        sb.Append(#10);
        if chomp = '+' then
          for i := 1 to trail do sb.Append(#10);
      end;
      Result := sb.ToString;
    finally
      sb.Free;
    end;
  finally
    parts.Free;
  end;
end;

function TYamlParser.ParseNode(var idx: Integer; minIndent, depth: Integer): TYamlNode;
var
  blockIndent, colon: Integer;
  c, key, keyRaw, rest: string;
  kindCh, chomp: Char;
  itemNode, child: TYamlNode;
begin
  Result := nil;
  if depth > YAML_MAX_DEPTH then
    raise EYamlError.Create('nesting too deep');
  SkipBlanks(idx);
  if idx >= N then Exit;
  if L[idx].Indent < minIndent then Exit;

  CheckTab(idx);
  blockIndent := L[idx].Indent;
  c := StripComment(L[idx].Content);

  if IsListLine(c) then
  begin
    Result := TYamlNode.Create(ykList);
    while True do
    begin
      SkipBlanks(idx);
      if idx >= N then Break;
      if L[idx].Indent <> blockIndent then Break;
      CheckTab(idx);
      c := StripComment(L[idx].Content);
      if not IsListLine(c) then Break;
      rest := StripLeadingAnchor(Trim(Copy(c, 2, MaxInt)));
      if rest = '' then
      begin
        Inc(idx);
        child := ParseNode(idx, blockIndent + 1, depth + 1);
        if child = nil then child := TYamlNode.Create(ykScalar);
        Result.PushItem(child);
      end
      else if MapColon(rest) > 0 then
      begin
        // map compacte `- key: v` : reecrite en `key: v` a l'indent REEL du
        // contenu (`-   key:` ou `- &a key:` = les freres ne sont pas a +2)
        colon := blockIndent + Length(c) - Length(rest);
        L[idx].Content := rest;
        L[idx].Indent := colon;
        child := ParseNode(idx, colon, depth + 1);
        if child = nil then child := TYamlNode.Create(ykScalar);
        Result.PushItem(child);
      end
      else
      begin
        kindCh := BlockScalarChar(rest, chomp);
        if kindCh <> #0 then
        begin
          Inc(idx);
          itemNode := TYamlNode.Create(ykScalar);
          itemNode.Scalar := ParseBlockScalar(idx, blockIndent, kindCh, chomp);
          Result.PushItem(itemNode);
        end
        else
        begin
          itemNode := TYamlNode.Create(ykScalar);
          if rest = '[]' then itemNode.Kind := ykList
          else if rest = '{}' then itemNode.Kind := ykMap
          else
          begin
            Inc(idx);
            rest := PlainContinuation(idx, blockIndent, rest);
            itemNode.Scalar := Unquote(rest);
            itemNode.Raw := rest;
            Dec(idx);
          end;
          Result.PushItem(itemNode);
          Inc(idx);
        end;
      end;
    end;
    Exit;
  end;

  colon := MapColon(c);
  if colon > 0 then
  begin
    Result := TYamlNode.Create(ykMap);
    while True do
    begin
      SkipBlanks(idx);
      if idx >= N then Break;
      if L[idx].Indent <> blockIndent then Break;
      CheckTab(idx);
      c := StripComment(L[idx].Content);
      if IsListLine(c) then Break;
      colon := MapColon(c);
      if colon = 0 then Break;
      keyRaw := Trim(Copy(c, 1, colon - 1));
      key := Unquote(keyRaw);
      rest := StripLeadingAnchor(Trim(Copy(c, colon + 1, MaxInt)));

      if rest = '' then
      begin
        Inc(idx);
        child := ParseNode(idx, blockIndent + 1, depth + 1);
        if child = nil then child := TYamlNode.Create(ykScalar);
        Result.SetPair(key, child, keyRaw);
      end
      else
      begin
        kindCh := BlockScalarChar(rest, chomp);
        if kindCh <> #0 then
        begin
          Inc(idx);
          child := TYamlNode.Create(ykScalar);
          child.Scalar := ParseBlockScalar(idx, blockIndent, kindCh, chomp);
          Result.SetPair(key, child, keyRaw);
        end
        else
        begin
          child := TYamlNode.Create(ykScalar);
          if rest = '[]' then child.Kind := ykList
          else if rest = '{}' then child.Kind := ykMap
          else
          begin
            Inc(idx);
            rest := PlainContinuation(idx, blockIndent, rest);
            child.Scalar := Unquote(rest);
            child.Raw := rest;
            Dec(idx);
          end;
          Result.SetPair(key, child, keyRaw);
          Inc(idx);
        end;
      end;
    end;
    Exit;
  end;

  Result := TYamlNode.Create(ykScalar);
  kindCh := BlockScalarChar(c, chomp);
  if kindCh <> #0 then
  begin
    Inc(idx);
    Result.Scalar := ParseBlockScalar(idx, blockIndent - 1, kindCh, chomp);
    Exit;
  end;
  Inc(idx);
  c := PlainContinuation(idx, blockIndent, c);
  Result.Scalar := Unquote(c);
  Result.Raw := c;
end;

function YamlParse(const AText: string; out AErr: string): TYamlNode;
var
  p: TYamlParser;
  idx: Integer;
begin
  Result := nil;
  AErr := '';
  if Length(AText) > YAML_MAX_BYTES then
  begin
    AErr := 'input too large';
    Exit;
  end;
  p := TYamlParser.Create;
  try
    try
      Preprocess(AText, p.L);
      p.N := Length(p.L);
      idx := 0;
      p.SkipBlanks(idx);
      if idx >= p.N then
        Result := TYamlNode.Create(ykMap)
      else
      begin
        Result := p.ParseNode(idx, 0, 0);
        // rien ne doit rester: les boucles map/liste sortent en silence sur
        // une ligne qui ne colle pas, Validate dirait OK sur un fichier a
        // moitie parse et les outils travailleraient sur un arbre ampute
        p.SkipBlanks(idx);
        if idx < p.N then
          raise EYamlError.CreateFmt('unparsed content at line %d',
            [p.L[idx].LineNo]);
      end;
      if Result = nil then
        Result := TYamlNode.Create(ykMap);
    except
      on ex: EYamlError do
      begin
        AErr := ex.Message;
        FreeAndNil(Result);
      end;
      on ex: Exception do
      begin
        AErr := ex.Message;
        FreeAndNil(Result);
      end;
    end;
  finally
    p.Free;
  end;
end;

procedure FlattenInto(ANode: TYamlNode; const APrefix: string; ADest: TStrings);
var
  i: Integer;
  np: string;
begin
  case ANode.Kind of
    ykScalar:
      if APrefix = '' then ADest.Add(ANode.Scalar)
      else ADest.Add(APrefix + ': ' + ANode.Scalar);
    ykMap:
      if ANode.Count = 0 then
      begin
        if APrefix <> '' then ADest.Add(APrefix + ': {}');
      end
      else
        for i := 0 to High(ANode.Keys) do
        begin
          if APrefix = '' then np := ANode.Keys[i]
          else np := APrefix + '.' + ANode.Keys[i];
          FlattenInto(ANode.Vals[i], np, ADest);
        end;
    ykList:
      if ANode.Count = 0 then
      begin
        if APrefix <> '' then ADest.Add(APrefix + ': []');
      end
      else
        for i := 0 to High(ANode.Items) do
          FlattenInto(ANode.Items[i], APrefix + '[' + IntToStr(i) + ']', ADest);
  end;
end;

procedure YamlFlatten(ANode: TYamlNode; ADest: TStrings);
begin
  if ANode = nil then Exit;
  FlattenInto(ANode, '', ADest);
end;

procedure FlattenKVInto(ANode: TYamlNode; const APrefix: string;
  AKeys, AVals: TStrings);
var
  i: Integer;
  np: string;
begin
  case ANode.Kind of
    ykScalar:
      begin
        AKeys.Add(APrefix);
        AVals.Add(ANode.Scalar);
      end;
    ykMap:
      if ANode.Count = 0 then
      begin
        if APrefix <> '' then begin AKeys.Add(APrefix); AVals.Add('{}'); end;
      end
      else
        for i := 0 to High(ANode.Keys) do
        begin
          if APrefix = '' then np := ANode.Keys[i]
          else np := APrefix + '.' + ANode.Keys[i];
          FlattenKVInto(ANode.Vals[i], np, AKeys, AVals);
        end;
    ykList:
      if ANode.Count = 0 then
      begin
        if APrefix <> '' then begin AKeys.Add(APrefix); AVals.Add('[]'); end;
      end
      else
        for i := 0 to High(ANode.Items) do
          FlattenKVInto(ANode.Items[i], APrefix + '[' + IntToStr(i) + ']', AKeys, AVals);
  end;
end;

procedure YamlFlattenKV(ANode: TYamlNode; AKeys, AVals: TStrings);
begin
  if ANode = nil then Exit;
  FlattenKVInto(ANode, '', AKeys, AVals);
end;

function LooksNumeric(const S: string): Boolean;
var
  i: Integer;
  dot: Boolean;
begin
  Result := False;
  if S = '' then Exit;
  dot := False;
  for i := 1 to Length(S) do
    if S[i] = '.' then
    begin
      if dot then Exit;
      dot := True;
    end
    else if not (S[i] in ['0'..'9', '+', '-']) then
      Exit;
  Result := True;
end;

function NeedsQuote(const S: string): Boolean;
var
  low: string;
begin
  if S = '' then Exit(True);
  if (S[1] = ' ') or (S[Length(S)] = ' ') then Exit(True);
  if S[1] in ['!', '&', '*', '?', ':', ',', '[', ']', '{', '}', '#', '|',
              '>', '@', '%', '"', '''', '`', '-'] then Exit(True);
  // chiffre/./+ en tete : 1e3, 0755 (octal yaml 1.1), 0x1F, 1_000, .inf,
  // dates -> quote systematique, un go-yaml les typerait
  if S[1] in ['0'..'9', '.', '+'] then Exit(True);
  if (Pos(': ', S) > 0) or (Pos(' #', S) > 0) then Exit(True);
  if (Pos(#10, S) > 0) or (Pos(#13, S) > 0) or (Pos(#9, S) > 0) then Exit(True);
  low := LowerCase(S);
  if (low = 'true') or (low = 'false') or (low = 'null') or (low = '~') or
     (low = 'yes') or (low = 'no') or (low = 'on') or (low = 'off') or
     (low = 'y') or (low = 'n') then Exit(True);
  if LooksNumeric(S) then Exit(True);
  Result := False;
end;

function QuoteScalar(const S: string): string;
begin
  if not NeedsQuote(S) then Exit(S);
  // CR/tab echappes aussi: un CR litteral casserait la structure de lignes
  // (Unquote les decode deja, round-trip stable)
  Result := '"' + StringReplace(StringReplace(StringReplace(StringReplace(
    StringReplace(S,
    '\', '\\', [rfReplaceAll]),
    '"', '\"', [rfReplaceAll]),
    #13, '\r', [rfReplaceAll]),
    #10, '\n', [rfReplaceAll]),
    #9, '\t', [rfReplaceAll]) + '"';
end;

function YamlQuoteScalar(const S: string): string;
begin
  Result := QuoteScalar(S);
end;

procedure YamlEmitScalar(ASL: TStrings; const APrefix, S: string; AIndent: Integer);
var
  i, n, k: Integer;
  body, pad, hdr: string;
  lines: TStringList;
begin
  // bloc litteral seulement si le texte s'y prete : \n present, pas de \r,
  // premiere ligne non vide sans espace de tete (l'indentation est deduite
  // de cette ligne). Sinon double-quote sur une ligne
  n := 0;
  i := Length(S);
  while (i >= 1) and (S[i] = #10) do begin Inc(n); Dec(i); end;
  body := Copy(S, 1, i);
  k := 1;
  while (k <= Length(body)) and (body[k] = #10) do Inc(k);
  if (Pos(#10, S) = 0) or (Pos(#13, S) > 0) or (body = '') or (body[k] = ' ') then
  begin
    ASL.Add(APrefix + QuoteScalar(S));
    Exit;
  end;
  case n of
    0: hdr := '|-';
    1: hdr := '|';
    else hdr := '|+';
  end;
  ASL.Add(TrimRight(APrefix) + ' ' + hdr);
  pad := StringOfChar(' ', AIndent + 2);
  lines := TStringList.Create;
  try
    lines.TextLineBreakStyle := tlbsLF;
    lines.Text := body;
    for i := 0 to lines.Count - 1 do
      if lines[i] = '' then ASL.Add('') else ASL.Add(pad + lines[i]);
  finally
    lines.Free;
  end;
  for i := 2 to n do ASL.Add('');
end;

procedure EmitScalarNode(ASL: TStrings; const APrefix: string; ANode: TYamlNode;
  AIndent: Integer);
begin
  if ANode.Raw <> '' then ASL.Add(APrefix + ANode.Raw)
  else YamlEmitScalar(ASL, APrefix, ANode.Scalar, AIndent);
end;

function EmitKey(ANode: TYamlNode; AIdx: Integer): string;
begin
  if (AIdx <= High(ANode.KeyRaws)) and (ANode.KeyRaws[AIdx] <> '') then
    Result := ANode.KeyRaws[AIdx]
  else
    Result := QuoteScalar(ANode.Keys[AIdx]);
end;

procedure EmitInto(ANode: TYamlNode; AIndent: Integer; ASL: TStrings); forward;

procedure EmitPair(const AKey: string; AVal: TYamlNode; AIndent: Integer; ASL: TStrings);
var
  pad, k: string;
begin
  pad := StringOfChar(' ', AIndent);
  k := AKey;
  case AVal.Kind of
    ykScalar:
      EmitScalarNode(ASL, pad + k + ': ', AVal, AIndent);
    ykMap:
      if AVal.Count = 0 then ASL.Add(pad + k + ': {}')
      else begin ASL.Add(pad + k + ':'); EmitInto(AVal, AIndent + 2, ASL); end;
    ykList:
      if AVal.Count = 0 then ASL.Add(pad + k + ': []')
      else begin ASL.Add(pad + k + ':'); EmitInto(AVal, AIndent + 2, ASL); end;
  end;
end;

procedure EmitItem(AItem: TYamlNode; AIndent: Integer; ASL: TStrings);
var
  pad: string;
begin
  pad := StringOfChar(' ', AIndent);
  case AItem.Kind of
    ykScalar: EmitScalarNode(ASL, pad + '- ', AItem, AIndent);
    ykMap:
      if AItem.Count = 0 then ASL.Add(pad + '- {}')
      else begin ASL.Add(pad + '-'); EmitInto(AItem, AIndent + 2, ASL); end;
    ykList:
      if AItem.Count = 0 then ASL.Add(pad + '- []')
      else begin ASL.Add(pad + '-'); EmitInto(AItem, AIndent + 2, ASL); end;
  end;
end;

procedure EmitInto(ANode: TYamlNode; AIndent: Integer; ASL: TStrings);
var
  i: Integer;
begin
  // 1 frame de pile par niveau : un arbre bati a la main deborderait
  if AIndent > 2 * YAML_MAX_DEPTH then Exit;
  case ANode.Kind of
    ykScalar: EmitScalarNode(ASL, StringOfChar(' ', AIndent), ANode, AIndent);
    ykMap:
      for i := 0 to High(ANode.Keys) do
        EmitPair(EmitKey(ANode, i), ANode.Vals[i], AIndent, ASL);
    ykList:
      for i := 0 to High(ANode.Items) do
        EmitItem(ANode.Items[i], AIndent, ASL);
  end;
end;

function YamlEmit(ANode: TYamlNode): string;
var
  sl: TStringList;
begin
  Result := '';
  if ANode = nil then Exit;
  sl := TStringList.Create;
  try
    if (ANode.Kind = ykMap) and (ANode.Count = 0) then sl.Add('{}')
    else if (ANode.Kind = ykList) and (ANode.Count = 0) then sl.Add('[]')
    else EmitInto(ANode, 0, sl);
    Result := sl.Text;
  finally
    sl.Free;
  end;
end;

function OneLine(const S: string): string;
begin
  Result := StringReplace(StringReplace(S, #13, ' ', [rfReplaceAll]), #10, '\n', [rfReplaceAll]);
end;

function YamlValuesDiff(A, B: TYamlNode; const ANameA, ANameB: string): string;
var
  ka, va, kb, vb: TStringList;
  onlyA, onlyB, changed: TStringList;
  res: TStringList;
  i, j: Integer;
begin
  ka := TStringList.Create; va := TStringList.Create;
  kb := TStringList.Create; vb := TStringList.Create;
  onlyA := TStringList.Create; onlyB := TStringList.Create;
  changed := TStringList.Create; res := TStringList.Create;
  try
    ka.CaseSensitive := True; kb.CaseSensitive := True;
    YamlFlattenKV(A, ka, va);
    YamlFlattenKV(B, kb, vb);
    for i := 0 to ka.Count - 1 do
    begin
      j := kb.IndexOf(ka[i]);
      if j < 0 then
        onlyA.Add('  ' + ka[i] + ': ' + OneLine(va[i]))
      else if vb[j] <> va[i] then
        changed.Add('  ' + ka[i] + ': ' + OneLine(va[i]) + '  =>  ' + OneLine(vb[j]));
    end;
    for i := 0 to kb.Count - 1 do
      if ka.IndexOf(kb[i]) < 0 then
        onlyB.Add('  ' + kb[i] + ': ' + OneLine(vb[i]));

    res.Add('# YAML values diff');
    res.Add('#   A = ' + ANameA);
    res.Add('#   B = ' + ANameB);
    res.Add(Format('#   %d only in A, %d only in B, %d changed',
      [onlyA.Count, onlyB.Count, changed.Count]));
    res.Add('');
    res.Add('=== only in A (' + ANameA + ') ===');
    if onlyA.Count = 0 then res.Add('  (none)') else res.AddStrings(onlyA);
    res.Add('');
    res.Add('=== only in B (' + ANameB + ') ===');
    if onlyB.Count = 0 then res.Add('  (none)') else res.AddStrings(onlyB);
    res.Add('');
    res.Add('=== changed (A => B) ===');
    if changed.Count = 0 then res.Add('  (none)') else res.AddStrings(changed);
    Result := res.Text;
  finally
    ka.Free; va.Free; kb.Free; vb.Free;
    onlyA.Free; onlyB.Free; changed.Free; res.Free;
  end;
end;

procedure YamlSortKeys(ANode: TYamlNode);
var
  idx: array of Integer;

  // ordre TOTAL : le quicksort n'est pas stable, mais rien ne compare egal
  function LessThan(A, B: Integer): Boolean;
  var
    c: Integer;
  begin
    c := CompareText(ANode.Keys[A], ANode.Keys[B]);
    if c = 0 then c := CompareStr(ANode.Keys[A], ANode.Keys[B]);
    if c = 0 then c := A - B;
    Result := c < 0;
  end;

  procedure QSort(L, R: Integer);
  var
    i, j, p, t: Integer;
  begin
    while L < R do
    begin
      i := L; j := R; p := idx[(L + R) div 2];
      repeat
        while LessThan(idx[i], p) do Inc(i);
        while LessThan(p, idx[j]) do Dec(j);
        if i <= j then
        begin
          t := idx[i]; idx[i] := idx[j]; idx[j] := t;
          Inc(i); Dec(j);
        end;
      until i > j;
      // recurse sur la petite moitie : pile bornee a log n
      if j - L < R - i then begin QSort(L, j); L := i; end
      else begin QSort(i, R); R := j; end;
    end;
  end;

var
  i: Integer;
  nk, nr: array of string;
  nv: array of TYamlNode;
begin
  if ANode = nil then Exit;
  case ANode.Kind of
    ykMap:
      begin
        for i := 0 to High(ANode.Vals) do YamlSortKeys(ANode.Vals[i]);
        if Length(ANode.Keys) < 2 then Exit;
        SetLength(idx, Length(ANode.Keys));
        for i := 0 to High(idx) do idx[i] := i;
        QSort(0, High(idx));
        SetLength(nk, Length(ANode.Keys));
        SetLength(nr, Length(ANode.Keys));
        SetLength(nv, Length(ANode.Vals));
        for i := 0 to High(idx) do
        begin
          nk[i] := ANode.Keys[idx[i]];
          if idx[i] <= High(ANode.KeyRaws) then nr[i] := ANode.KeyRaws[idx[i]];
          nv[i] := ANode.Vals[idx[i]];
        end;
        ANode.Keys := nk;
        ANode.KeyRaws := nr;
        ANode.Vals := nv;
      end;
    ykList:
      for i := 0 to High(ANode.Items) do YamlSortKeys(ANode.Items[i]);
  end;
end;

end.
