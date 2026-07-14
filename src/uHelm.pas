unit uHelm;

{$mode objfpc}{$H+}

// Aides Helm. Scan LINEAIRE des refs `.Values.*` (pas de regex).
// HEURISTIQUE : le scoping (`with`, `range`, `index .Values`) n'est PAS resolu,
// donc faux positifs et faux negatifs possibles.

interface

uses
  Classes, SysUtils, StrUtils, uYaml;

// L'appelant possede et libere la liste.
function ScanValuesRefs(const AText: string): TStringList;

// Scan recursif d'un templates/. Plafonds : 2000 fichiers, 4 Mo, 32 niveaux.
function ScanValuesRefsInDir(const ADir: string;
  out AFileCount, ASkipped: Integer): TStringList;

function ValuesSkeleton(const AText: string): string;
// NE libere PAS ARefs.
function ValuesSkeletonFromRefs(ARefs: TStringList): string;

// '' si la ligne du caret n'est pas une entree de map.
function RenderValuesPath(ALines: TStrings; ACaretIdx: Integer): string;

// MISSING (utilisee, absente de values) / UNUSED (dans values, jamais reference).
function FindValuesIssues(const ATemplate: string; AValues: TYamlNode): string;
// NE libere PAS ARefs.
function FindValuesIssuesFromRefs(ARefs: TStringList; AValues: TYamlNode): string;

function HelmSnippet(ATag: Integer): string;

// HelmQuoteLine est idempotent et rend la ligne INCHANGEE sans {{ }} a quoter.
function HelmQuoteLine(const ALine: string): string;
function HelmToYamlLine(const AKeyLine, AValuesPath: string): string;
function DefaultValuesPath(const AKeyLine: string): string;

implementation

function IsIdentChar(c: Char): Boolean; inline;
begin
  Result := c in ['A'..'Z', 'a'..'z', '0'..'9', '_'];
end;

function ScanValuesRefs(const AText: string): TStringList;
const
  MARK = '.Values.';
  MAX_SEG = 64;
var
  n, p, j, segn: Integer;
  seg, path: string;
begin
  Result := TStringList.Create;
  Result.Sorted := True;
  Result.Duplicates := dupIgnore;
  n := Length(AText);
  p := 1;
  while p <= n do
  begin
    p := PosEx(MARK, AText, p);
    if p = 0 then Break;
    j := p + Length(MARK); // premier char apres '.Values.'
    path := '';
    segn := 0;
    while True do
    begin
      seg := '';
      while (j <= n) and IsIdentChar(AText[j]) do
      begin
        seg := seg + AText[j];
        Inc(j);
      end;
      if seg = '' then Break;
      if path = '' then path := seg else path := path + '.' + seg;
      Inc(segn);
      // un arbre trop profond deborderait la pile de l'emetteur YAML (recursif)
      if segn >= MAX_SEG then Break;
      if (j < n) and (AText[j] = '.') and IsIdentChar(AText[j + 1]) then
        Inc(j)
      else
        Break;
    end;
    if path <> '' then Result.Add(path);
    p := p + Length(MARK);
  end;
end;

procedure InsertPath(ARoot: TYamlNode; const APath: string);
var
  segs: TStringList;
  cur, child: TYamlNode;
  k: Integer;
begin
  segs := TStringList.Create;
  try
    segs.Delimiter := '.';
    segs.StrictDelimiter := True;
    segs.DelimitedText := APath;
    cur := ARoot;
    for k := 0 to segs.Count - 1 do
    begin
      if segs[k] = '' then Continue;
      if k < segs.Count - 1 then
      begin
        child := cur.ChildByKey(segs[k]);
        if child = nil then
        begin
          child := TYamlNode.Create(ykMap);
          cur.SetPair(segs[k], child);
        end
        else if child.Kind <> ykMap then
        begin
          // feuille promue en map : le plus structure gagne
          child.Kind := ykMap;
          child.Scalar := '';
        end;
        cur := child;
      end
      else
      begin
        // ne pas ecraser une map deja presente
        child := cur.ChildByKey(segs[k]);
        if child = nil then
          cur.SetPair(segs[k], TYamlNode.Create(ykScalar));
      end;
    end;
  finally
    segs.Free;
  end;
end;

function ValuesSkeletonFromRefs(ARefs: TStringList): string;
var
  root: TYamlNode;
  i: Integer;
begin
  if (ARefs = nil) or (ARefs.Count = 0) then
    Exit('# no .Values.* references found');
  root := TYamlNode.Create(ykMap);
  try
    for i := 0 to ARefs.Count - 1 do
      InsertPath(root, ARefs[i]);
    Result := '# values.yaml skeleton (from .Values.* refs)'#10 + YamlEmit(root);
  finally
    root.Free;
  end;
end;

function ValuesSkeleton(const AText: string): string;
var
  refs: TStringList;
begin
  refs := ScanValuesRefs(AText);
  try
    Result := ValuesSkeletonFromRefs(refs);
  finally
    refs.Free;
  end;
end;

const
  HELM_MAX_FILES      = 2000;
  HELM_MAX_FILE_BYTES = 4 * 1024 * 1024;
  HELM_MAX_DEPTH      = 32;
  // borne le TEMPS : sur un dossier choisi par erreur (home, racine d'un repo)
  // on croise des millions d'entrees avant d'atteindre 2000 templates
  HELM_MAX_ENTRIES    = 200000;

function IsTemplateFile(const AName: string): Boolean;
var
  ext: string;
begin
  ext := LowerCase(ExtractFileExt(AName));
  Result := (ext = '.yaml') or (ext = '.yml') or (ext = '.tpl') or (ext = '.txt');
end;

procedure ScanDirInto(const ADir: string; AAcc: TStringList;
  var AFileCount, ASkipped, AEntries: Integer; ADepth: Integer);
var
  sr: TSearchRec;
  full: string;
  fs, refs: TStringList;
  i: Integer;
begin
  if (ADepth > HELM_MAX_DEPTH) or (AFileCount >= HELM_MAX_FILES) or
     (AEntries >= HELM_MAX_ENTRIES) then Exit;
  if SysUtils.FindFirst(IncludeTrailingPathDelimiter(ADir) + '*', faAnyFile, sr) <> 0 then
    Exit;
  try
    repeat
      if (sr.Name = '.') or (sr.Name = '..') then Continue;
      Inc(AEntries);
      if AEntries >= HELM_MAX_ENTRIES then Break;
      full := IncludeTrailingPathDelimiter(ADir) + sr.Name;
      if (sr.Attr and faDirectory) <> 0 then
        ScanDirInto(full, AAcc, AFileCount, ASkipped, AEntries, ADepth + 1)
      else if IsTemplateFile(sr.Name) then
      begin
        if AFileCount >= HELM_MAX_FILES then begin Inc(ASkipped); Continue; end;
        if sr.Size > HELM_MAX_FILE_BYTES then begin Inc(ASkipped); Continue; end;
        fs := TStringList.Create;
        try
          try
            fs.LoadFromFile(full);
            Inc(AFileCount);
            refs := ScanValuesRefs(fs.Text);
            try
              for i := 0 to refs.Count - 1 do AAcc.Add(refs[i]);
            finally
              refs.Free;
            end;
          except
            Inc(ASkipped);
          end;
        finally
          fs.Free;
        end;
      end;
    until SysUtils.FindNext(sr) <> 0;
  finally
    SysUtils.FindClose(sr);
  end;
end;

function ScanValuesRefsInDir(const ADir: string;
  out AFileCount, ASkipped: Integer): TStringList;
var
  entries: Integer;
begin
  Result := TStringList.Create;
  Result.Sorted := True;
  Result.Duplicates := dupIgnore;
  AFileCount := 0;
  ASkipped := 0;
  entries := 0;
  if DirectoryExists(ADir) then
    ScanDirInto(ADir, Result, AFileCount, ASkipped, entries, 0);
end;

// ignore les listes (`- `), les commentaires et les lignes vides
function KeyLine(const S: string; out AIndent: Integer; out AKey: string): Boolean;
var
  i, n: Integer;
  body, k: string;
  q: Char;
begin
  Result := False;
  AKey := '';
  n := Length(S);
  i := 1;
  AIndent := 0;
  while (i <= n) and (S[i] = ' ') do begin Inc(AIndent); Inc(i); end;
  body := Copy(S, i, MaxInt);
  if (body = '') or (body[1] = '#') or (body[1] = '-') then Exit;
  q := #0;
  for i := 1 to Length(body) do
  begin
    if q <> #0 then
    begin
      if body[i] = q then q := #0;
    end
    else if (body[i] = '"') or (body[i] = '''') then
      q := body[i]
    else if body[i] = ':' then
      if (i = Length(body)) or (body[i + 1] = ' ') then
      begin
        k := Trim(Copy(body, 1, i - 1));
        if (Length(k) >= 2) and (((k[1] = '"') and (k[Length(k)] = '"')) or
           ((k[1] = '''') and (k[Length(k)] = ''''))) then
          k := Copy(k, 2, Length(k) - 2);
        AKey := k;
        Exit(k <> '');
      end;
  end;
end;

function RenderValuesPath(ALines: TStrings; ACaretIdx: Integer): string;
var
  i, curInd, ind: Integer;
  key: string;
  parts: TStringList;
begin
  Result := '';
  if (ALines = nil) or (ALines.Count = 0) then Exit;
  i := ACaretIdx;
  if i >= ALines.Count then i := ALines.Count - 1;
  if i < 0 then Exit;
  while (i >= 0) and not KeyLine(ALines[i], curInd, key) do Dec(i);
  if i < 0 then Exit;

  parts := TStringList.Create;
  try
    parts.Delimiter := '.';
    parts.StrictDelimiter := True;
    parts.Insert(0, key);
    Dec(i);
    while (i >= 0) and (curInd > 0) do
    begin
      if KeyLine(ALines[i], ind, key) and (ind < curInd) then
      begin
        parts.Insert(0, key);
        curInd := ind;
      end;
      Dec(i);
    end;
    Result := '.Values.' + parts.DelimitedText;
  finally
    parts.Free;
  end;
end;

// egaux ou l'un prefixe de l'autre : une ref `image` couvre `image.tag`
function PathsIntersect(const A, B: string): Boolean;
begin
  Result := (A = B)
    or ((Length(A) > Length(B)) and (Copy(A, 1, Length(B) + 1) = B + '.'))
    or ((Length(B) > Length(A)) and (Copy(B, 1, Length(A) + 1) = A + '.'));
end;

function FindValuesIssuesFromRefs(ARefs: TStringList; AValues: TYamlNode): string;
var
  vk, vv, missing, unused, res: TStringList;
  i, j: Integer;
  hit: Boolean;
begin
  vk := TStringList.Create; vv := TStringList.Create;
  missing := TStringList.Create; unused := TStringList.Create;
  res := TStringList.Create;
  try
    YamlFlattenKV(AValues, vk, vv);
    for i := 0 to ARefs.Count - 1 do
    begin
      hit := False;
      for j := 0 to vk.Count - 1 do
        if PathsIntersect(ARefs[i], vk[j]) then begin hit := True; Break; end;
      if not hit then missing.Add('  .Values.' + ARefs[i]);
    end;
    for j := 0 to vk.Count - 1 do
    begin
      hit := False;
      for i := 0 to ARefs.Count - 1 do
        if PathsIntersect(vk[j], ARefs[i]) then begin hit := True; Break; end;
      if not hit then unused.Add('  ' + vk[j]);
    end;

    res.Add('# Helm values cross-check (heuristic)');
    res.Add(Format('#   %d template refs, %d values keys', [ARefs.Count, vk.Count]));
    res.Add('#   NOTE: with/range/index .Values scoping is not resolved -> some');
    res.Add('#   entries below may be false positives.');
    res.Add('');
    res.Add('=== MISSING (used in template, absent from values.yaml) ===');
    if missing.Count = 0 then res.Add('  (none)') else res.AddStrings(missing);
    res.Add('');
    res.Add('=== UNUSED (in values.yaml, not referenced by template) ===');
    if unused.Count = 0 then res.Add('  (none)') else res.AddStrings(unused);
    Result := res.Text;
  finally
    vk.Free; vv.Free; missing.Free; unused.Free; res.Free;
  end;
end;

function FindValuesIssues(const ATemplate: string; AValues: TYamlNode): string;
var
  refs: TStringList;
begin
  refs := ScanValuesRefs(ATemplate);
  try
    Result := FindValuesIssuesFromRefs(refs, AValues);
  finally
    refs.Free;
  end;
end;

function HelmSnippet(ATag: Integer): string;
begin
  case ATag of
    0: Result :=
         '{{- if .Values.enabled }}'#10 +
         ''#10 +
         '{{- end }}'#10;
    1: Result :=
         '{{- with .Values.section }}'#10 +
         ''#10 +
         '{{- end }}'#10;
    2: Result :=
         '{{- range .Values.items }}'#10 +
         '- {{ . }}'#10 +
         '{{- end }}'#10;
    3: Result :=
         '{{ include "chart.fullname" . }}'#10;
    4: Result :=
         'labels:'#10 +
         '  {{- include "chart.labels" . | nindent 4 }}'#10;
    5: Result :=
         'selector:'#10 +
         '  matchLabels:'#10 +
         '    {{- include "chart.selectorLabels" . | nindent 6 }}'#10;
    6: Result :=
         'resources:'#10 +
         '  {{- toYaml .Values.resources | nindent 2 }}'#10;
  else
    Result := '';
  end;
end;

function HelmQuoteLine(const ALine: string): string;
var
  startTag, endTag, i, bar: Integer;
  body, expr, lastSeg, tag: string;
  leadDash, trailDash: Boolean;
begin
  Result := ALine;
  startTag := Pos('{{', ALine);
  if startTag = 0 then Exit;
  endTag := PosEx('}}', ALine, startTag + 2);
  if endTag = 0 then Exit;
  body := Trim(Copy(ALine, startTag + 2, endTag - startTag - 2));
  // marqueurs de trim {{- -}} preserves
  leadDash := (body <> '') and (body[1] = '-');
  if leadDash then body := Trim(Copy(body, 2, MaxInt));
  trailDash := (body <> '') and (body[Length(body)] = '-');
  if trailDash then body := Trim(Copy(body, 1, Length(body) - 1));
  expr := Trim(body);
  if expr = '' then Exit;
  // dernier segment de pipe deja 'quote' -> idempotent
  bar := 0;
  for i := Length(expr) downto 1 do
    if expr[i] = '|' then begin bar := i; Break; end;
  if bar > 0 then lastSeg := Trim(Copy(expr, bar + 1, MaxInt)) else lastSeg := '';
  if SameText(lastSeg, 'quote') then Exit;
  expr := expr + ' | quote';
  tag := '{{';
  if leadDash then tag := tag + '-';
  tag := tag + ' ' + expr + ' ';
  if trailDash then tag := tag + '-';
  tag := tag + '}}';
  Result := Copy(ALine, 1, startTag - 1) + tag + Copy(ALine, endTag + 2, MaxInt);
end;

function HelmToYamlLine(const AKeyLine, AValuesPath: string): string;
var
  ind: Integer;
  key: string;
begin
  Result := '';
  if not KeyLine(AKeyLine, ind, key) then Exit;
  // remplace la CLE seule : un bloc enfant existant est a retirer a la main
  Result := StringOfChar(' ', ind) + key + ':'#10 +
    StringOfChar(' ', ind + 2) + '{{- toYaml ' + AValuesPath +
    ' | nindent ' + IntToStr(ind + 2) + ' }}';
end;

function DefaultValuesPath(const AKeyLine: string): string;
var
  ind: Integer;
  key: string;
begin
  if KeyLine(AKeyLine, ind, key) then
    Result := '.Values.' + key
  else
    Result := '';
end;

end.
