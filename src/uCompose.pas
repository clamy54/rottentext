unit uCompose;

{$mode objfpc}{$H+}

// Aides Docker / Compose. HEURISTIQUE : `services:` a la racine seulement,
// ni `x-*`, ni include, ni extends, ni profiles.

interface

uses
  Classes, SysUtils;

// [registry[:port]/]repo[:tag][@digest]. Le tag = dernier ':' APRES le dernier
// '/' : sinon c'est le port du registry.
function SplitImageRef(const ARef: string; out ARepo, ATag, ADigest: string): Boolean;

function ImageTagOnLine(const ALine: string): string;

// rend la ligne INCHANGEE si ce n'est pas une ligne image
function ComposeRetagLine(const ALine, ANewTag: string): string;

function ComposeListImages(const AText: string; out AErr: string): string;

function ComposeEnvDotenv(const AText: string; out AErr: string): string;

implementation

uses
  uYaml, uEnv;

function LastPosCh(c: Char; const S: string): Integer;
var
  i: Integer;
begin
  Result := 0;
  for i := Length(S) downto 1 do
    if S[i] = c then Exit(i);
end;

function SplitImageRef(const ARef: string; out ARepo, ATag, ADigest: string): Boolean;
var
  s: string;
  at, slash, colon: Integer;
begin
  ARepo := ''; ATag := ''; ADigest := '';
  s := Trim(ARef);
  if s = '' then Exit(False);
  at := Pos('@', s);
  if at > 0 then
  begin
    ADigest := Copy(s, at + 1, MaxInt);
    s := Copy(s, 1, at - 1);
  end;
  slash := LastPosCh('/', s);
  colon := LastPosCh(':', s);
  if colon > slash then // vrai tag, pas un port de registry
  begin
    ATag := Copy(s, colon + 1, MaxInt);
    ARepo := Copy(s, 1, colon - 1);
  end
  else
    ARepo := s;
  Result := ARepo <> '';
end;

// APrefix (indent, `- `, `image:`) et AComment sont PRESERVES au retag
function ParseImageLine(const ALine: string; out APrefix, AValue, AComment: string;
  out AQuote: Char): Boolean;
var
  n, i, colon, vs, ve: Integer;
  key, valpart: string;
begin
  Result := False;
  APrefix := ''; AValue := ''; AComment := ''; AQuote := #0;
  n := Length(ALine);
  i := 1;
  while (i <= n) and (ALine[i] in [' ', #9]) do Inc(i);
  if (i <= n) and (ALine[i] = '-') then
  begin
    Inc(i);
    while (i <= n) and (ALine[i] in [' ', #9]) do Inc(i);
  end;
  key := '';
  while (i <= n) and (ALine[i] <> ':') do begin key := key + ALine[i]; Inc(i); end;
  if (i > n) or (ALine[i] <> ':') then Exit;
  colon := i;
  if not SameText(Trim(key), 'image') then Exit;
  vs := colon + 1;
  while (vs <= n) and (ALine[vs] in [' ', #9]) do Inc(vs);
  APrefix := Copy(ALine, 1, vs - 1);
  valpart := Copy(ALine, vs, MaxInt);
  if valpart = '' then Exit;
  if (valpart[1] = '"') or (valpart[1] = '''') then
  begin
    AQuote := valpart[1];
    ve := 2;
    while (ve <= Length(valpart)) and (valpart[ve] <> AQuote) do Inc(ve);
    AValue := Copy(valpart, 2, ve - 2);
    AComment := Copy(valpart, ve + 1, MaxInt);
  end
  else
  begin
    // la ref n'a pas d'espace : elle finit au 1er blanc, le reste = commentaire
    ve := 1;
    while (ve <= Length(valpart)) and (valpart[ve] <> ' ') and (valpart[ve] <> #9) do
      Inc(ve);
    AValue := Copy(valpart, 1, ve - 1);
    AComment := Copy(valpart, ve, MaxInt);
  end;
  Result := AValue <> '';
end;

function ImageTagOnLine(const ALine: string): string;
var
  pref, val, cmt: string;
  q: Char;
  repo, tag, dig: string;
begin
  Result := '';
  if not ParseImageLine(ALine, pref, val, cmt, q) then Exit;
  if SplitImageRef(val, repo, tag, dig) then Result := tag;
end;

function ComposeRetagLine(const ALine, ANewTag: string): string;
var
  pref, val, cmt: string;
  q: Char;
  repo, tag, dig, nv: string;
begin
  Result := ALine;
  if not ParseImageLine(ALine, pref, val, cmt, q) then Exit;
  if not SplitImageRef(val, repo, tag, dig) then Exit;
  nv := repo + ':' + ANewTag;
  if dig <> '' then nv := nv + '@' + dig;
  if q <> #0 then nv := q + nv + q;
  Result := pref + nv + cmt;
end;

function ServicesOf(ARoot: TYamlNode): TYamlNode;
begin
  Result := nil;
  if (ARoot = nil) or (ARoot.Kind <> ykMap) then Exit;
  Result := ARoot.ChildByKey('services');
  if (Result <> nil) and (Result.Kind <> ykMap) then Result := nil;
end;

function ComposeListImages(const AText: string; out AErr: string): string;
var
  root, svcs, svc, img: TYamlNode;
  sl, tags: TStringList;
  i: Integer;
  repo, tag, dig, ref: string;
begin
  Result := '';
  root := YamlParse(AText, AErr);
  if root = nil then Exit;
  try
    svcs := ServicesOf(root);
    if svcs = nil then
    begin
      AErr := 'no top-level services: mapping (is this a compose file?)';
      Exit;
    end;
    sl := TStringList.Create;
    tags := TStringList.Create;
    tags.Sorted := True;
    tags.Duplicates := dupIgnore;
    try
      sl.Add('# docker compose images');
      sl.Add('');
      for i := 0 to High(svcs.Keys) do
      begin
        svc := svcs.Vals[i];
        if (svc = nil) or (svc.Kind <> ykMap) then Continue;
        img := svc.ChildByKey('image');
        if (img = nil) or (img.Kind <> ykScalar) then
        begin
          sl.Add(Format('  %-20s (no image:, built from context?)', [svcs.Keys[i]]));
          Continue;
        end;
        ref := img.Scalar;
        sl.Add(Format('  %-20s %s', [svcs.Keys[i], ref]));
        if SplitImageRef(ref, repo, tag, dig) then
          if dig <> '' then tags.Add(repo + ' @' + Copy(dig, 1, 19) + '...')
          else if tag <> '' then tags.Add(repo + ' : ' + tag)
          else tags.Add(repo + ' : (latest, implicit)');
      end;
      sl.Add('');
      sl.Add('=== unique repo/tag ===');
      if tags.Count = 0 then sl.Add('  (none)') else sl.AddStrings(tags);
      Result := sl.Text;
    finally
      sl.Free; tags.Free;
    end;
  finally
    root.Free;
  end;
end;

// via EmitEnvLine : un scalaire YAML multi-lignes ne peut pas injecter de ligne
procedure AddEnv(ADest: TStringList; const AKey, AVal: string; AHasVal: Boolean);
begin
  if Trim(AKey) = '' then Exit;
  if AHasVal then ADest.Add(EmitEnvLine(AKey, AVal))
  else ADest.Add(EmitEnvLine(AKey, ''));
end;

function ComposeEnvDotenv(const AText: string; out AErr: string): string;
var
  root, svcs, svc, env, item: TYamlNode;
  sl: TStringList;
  i, j, eq: Integer;
  ln: string;
begin
  Result := '';
  root := YamlParse(AText, AErr);
  if root = nil then Exit;
  try
    svcs := ServicesOf(root);
    if svcs = nil then
    begin
      AErr := 'no top-level services: mapping (is this a compose file?)';
      Exit;
    end;
    sl := TStringList.Create;
    try
      for i := 0 to High(svcs.Keys) do
      begin
        svc := svcs.Vals[i];
        if (svc = nil) or (svc.Kind <> ykMap) then Continue;
        env := svc.ChildByKey('environment');
        if env = nil then Continue;
        sl.Add('# service: ' + svcs.Keys[i]);
        if env.Kind = ykList then
          for j := 0 to High(env.Items) do
          begin
            item := env.Items[j];
            if item.Kind <> ykScalar then Continue;
            ln := item.Scalar;
            eq := Pos('=', ln);
            if eq > 0 then AddEnv(sl, Copy(ln, 1, eq - 1), Copy(ln, eq + 1, MaxInt), True)
            else AddEnv(sl, ln, '', False); // "- KEY" = passe l'env de l'hote
          end
        else if env.Kind = ykMap then
          for j := 0 to High(env.Keys) do
            if env.Vals[j].Kind = ykScalar then
              AddEnv(sl, env.Keys[j], env.Vals[j].Scalar, True)
            else
              AddEnv(sl, env.Keys[j], '', True);
        sl.Add('');
      end;
      if sl.Count = 0 then sl.Add('# no environment: found in any service');
      Result := sl.Text;
    finally
      sl.Free;
    end;
  finally
    root.Free;
  end;
end;

end.
