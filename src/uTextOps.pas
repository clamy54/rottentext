unit uTextOps;

{$mode objfpc}{$H+}

// Transformations de texte pures : casse UTF-8, re-indentation de collage,
// tri de lignes, lorem ipsum, expansion des tabulations.

interface

uses
  Classes, SysUtils, LazUTF8, LazUnicode;

function LeadingWS(const S: string): string;
// un saut final produit un dernier element vide
procedure SplitLines(const S: string; AOut: TStrings);
// indentation RELATIVE du bloc conservee, re-basee sur ABase
function ReindentForPaste(const AClip, ABase: string): string;
function UTF8SwapCase(const S: string): string;
// mot = lettres casees + chiffres
function UTF8TitleCase(const S: string): string;
procedure SortLinesCI(AList: TStringList);
// lorem de MEME FORME : mots entiers jusqu'a la longueur d'origine de chaque
// ligne, jamais tronques. Selection sans texte : lignes remplies a ADefWidth.
function LoremFill(const S: string; ADefWidth: Integer = 78): string;
// Expansion par TAQUETS (expand(1)) : un tab avance jusqu'a la prochaine colonne
// multiple de ATabWidth, ce n'est PAS ATabWidth espaces fixes. Colonne comptee
// comme l'editeur : un COMBINANT vaut zero (IsCombining = le predicat SynEdit).
// AStartCol = colonne d'ecran de la 1re ligne (selection debutant en colonne 20).
function ExpandTabs(const S: string; ATabWidth: Integer;
  AStartCol: Integer = 0): string;

implementation

function LeadingWS(const S: string): string;
var
  i: Integer;
begin
  i := 1;
  while (i <= Length(S)) and (S[i] in [' ', #9]) do
    Inc(i);
  Result := Copy(S, 1, i - 1);
end;

procedure SplitLines(const S: string; AOut: TStrings);
var
  i, start: Integer;
begin
  AOut.Clear;
  start := 1;
  i := 1;
  while i <= Length(S) do
  begin
    if S[i] in [#13, #10] then
    begin
      AOut.Add(Copy(S, start, i - start));
      if (S[i] = #13) and (i < Length(S)) and (S[i+1] = #10) then
        Inc(i);
      start := i + 1;
    end;
    Inc(i);
  end;
  AOut.Add(Copy(S, start, Length(S) - start + 1));
end;

function ReindentForPaste(const AClip, ABase: string): string;
var
  sl: TStringList;
  common, ws: string;
  i, n: Integer;
begin
  sl := TStringList.Create;
  try
    SplitLines(AClip, sl);
    if sl.Count <= 1 then Exit(AClip);
    // prefixe blanc commun aux lignes non vides (comparaison exacte)
    common := '';
    n := -1;
    for i := 0 to sl.Count - 1 do
    begin
      if Trim(sl[i]) = '' then Continue;
      ws := LeadingWS(sl[i]);
      if n < 0 then
        common := ws
      else
        while (common <> '') and (Copy(ws, 1, Length(common)) <> common) do
          SetLength(common, Length(common) - 1);
      n := 0;
    end;
    Result := '';
    for i := 0 to sl.Count - 1 do
    begin
      if i > 0 then Result := Result + LineEnding;
      ws := sl[i];
      if Trim(ws) = '' then
        ws := ''
      else
      begin
        if Copy(ws, 1, Length(common)) = common then
          Delete(ws, 1, Length(common));
        if i > 0 then ws := ABase + ws;
      end;
      Result := Result + ws;
    end;
  finally
    sl.Free;
  end;
end;

function UTF8SwapCase(const S: string): string;
var
  i, n: SizeInt; // en Integer, un S proche de 2 Gio wrappe en index negatif
  ch, up, lo: string;
begin
  Result := '';
  i := 1;
  while i <= Length(S) do
  begin
    n := UTF8CodepointSize(@S[i]);
    ch := Copy(S, i, n);
    up := UTF8UpperCase(ch);
    lo := UTF8LowerCase(ch);
    if (ch = up) and (ch <> lo) then
      Result := Result + lo
    else if (ch = lo) and (ch <> up) then
      Result := Result + up
    else
      Result := Result + ch;
    Inc(i, n);
  end;
end;

function UTF8TitleCase(const S: string): string;
var
  i, n: SizeInt; // idem UTF8SwapCase
  ch, up, lo: string;
  inWord: Boolean;
begin
  Result := '';
  inWord := False;
  i := 1;
  while i <= Length(S) do
  begin
    n := UTF8CodepointSize(@S[i]);
    ch := Copy(S, i, n);
    up := UTF8UpperCase(ch);
    lo := UTF8LowerCase(ch);
    if up <> lo then
    begin
      if inWord then
        Result := Result + lo
      else
        Result := Result + up;
      inWord := True;
    end
    else
    begin
      Result := Result + ch;
      // un chiffre ne coupe pas le mot : "foo1bar" -> "Foo1bar"
      inWord := (n = 1) and (ch[1] in ['0'..'9']);
    end;
    Inc(i, n);
  end;
end;

function CompareCI(List: TStringList; Index1, Index2: Integer): Integer;
begin
  Result := UTF8CompareText(List[Index1], List[Index2]);
end;

procedure SortLinesCI(AList: TStringList);
begin
  AList.CustomSort(@CompareCI);
end;

const
  // cycle en boucle : laborum. -> Lorem
  LOREM_WORDS: array[0..68] of string = (
    'Lorem', 'ipsum', 'dolor', 'sit', 'amet,', 'consectetur', 'adipiscing',
    'elit,', 'sed', 'do', 'eiusmod', 'tempor', 'incididunt', 'ut', 'labore',
    'et', 'dolore', 'magna', 'aliqua.', 'Ut', 'enim', 'ad', 'minim',
    'veniam,', 'quis', 'nostrud', 'exercitation', 'ullamco', 'laboris',
    'nisi', 'ut', 'aliquip', 'ex', 'ea', 'commodo', 'consequat.', 'Duis',
    'aute', 'irure', 'dolor', 'in', 'reprehenderit', 'in', 'voluptate',
    'velit', 'esse', 'cillum', 'dolore', 'eu', 'fugiat', 'nulla',
    'pariatur.', 'Excepteur', 'sint', 'occaecat', 'cupidatat', 'non',
    'proident,', 'sunt', 'in', 'culpa', 'qui', 'officia', 'deserunt',
    'mollit', 'anim', 'id', 'est', 'laborum.');

function ExpandTabs(const S: string; ATabWidth: Integer;
  AStartCol: Integer): string;
var
  // en Integer, l'expansion d'un gros buffer deborde: SetLength negatif + OOB
  i, n, col, pad, outLen, k, j: SizeInt;
begin
  if ATabWidth < 1 then ATabWidth := 1;
  if AStartCol < 0 then AStartCol := 0;
  if Pos(#9, S) = 0 then Exit(S); // pas de copie

  // passe 1: taille exacte de la sortie
  outLen := 0;
  col := AStartCol;
  i := 1;
  while i <= Length(S) do
    case S[i] of
      #9:
        begin
          pad := ATabWidth - (col mod ATabWidth); // 1..ATabWidth
          Inc(outLen, pad);
          Inc(col, pad);
          Inc(i);
        end;
      #10, #13:
        begin
          Inc(outLen);
          col := 0;
          Inc(i);
        end;
      else
        begin
          n := UTF8CodepointSize(@S[i]);
          Inc(outLen, n);
          if not IsCombining(@S[i]) then Inc(col); // combinant = zero colonne
          Inc(i, n);
        end;
    end;

  SetLength(Result, outLen);
  j := 1;
  col := AStartCol;
  i := 1;
  while i <= Length(S) do
    case S[i] of
      #9:
        begin
          pad := ATabWidth - (col mod ATabWidth);
          for k := 1 to pad do
          begin
            Result[j] := ' ';
            Inc(j);
          end;
          Inc(col, pad);
          Inc(i);
        end;
      #10, #13:
        begin
          Result[j] := S[i];
          Inc(j);
          col := 0;
          Inc(i);
        end;
      else
        begin
          n := UTF8CodepointSize(@S[i]);
          for k := 0 to n - 1 do
          begin
            Result[j] := S[i + k];
            Inc(j);
          end;
          if not IsCombining(@S[i]) then Inc(col);
          Inc(i, n);
        end;
    end;
end;

function LoremFill(const S: string; ADefWidth: Integer): string;
var
  lines: TStringList;
  i, target, idx, need: Integer;
  cur, w: string;
  allBlank: Boolean;
begin
  lines := TStringList.Create;
  try
    SplitLines(S, lines);
    allBlank := True;
    for i := 0 to lines.Count - 1 do
      if Trim(lines[i]) <> '' then begin allBlank := False; Break; end;
    idx := 0;
    for i := 0 to lines.Count - 1 do
    begin
      // cible en CARACTERES; le lorem est ASCII, Length(cur) compte juste
      if allBlank then target := ADefWidth
      else target := UTF8Length(lines[i]);
      cur := '';
      while True do
      begin
        w := LOREM_WORDS[idx mod Length(LOREM_WORDS)];
        need := Length(w);
        if cur <> '' then Inc(need); // espace de jointure
        if Length(cur) + need > target then Break;
        if cur <> '' then cur := cur + ' ';
        cur := cur + w;
        Inc(idx);
      end;
      lines[i] := cur;
    end;
    lines.SkipLastLineBreak := True;
    Result := lines.Text;
  finally
    lines.Free;
  end;
end;

end.
