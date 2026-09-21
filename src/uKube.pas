unit uKube;

{$mode objfpc}{$H+}

// Secret / ConfigMap Kubernetes <-> lignes KEY=value. Gabarit YAML fixe.

interface

uses
  Classes, SysUtils;

function SecretEncode(const AName, ANamespace: string; AEnv: TStrings): string;

function SecretDecode(const AYaml: string; out AErr: string): string;

// ConfigMap : data en CLAIR (pas de base64), binaryData decode.
function ConfigMapEncode(const AName, ANamespace: string; AEnv: TStrings): string;
function ConfigMapDecode(const AYaml: string; out AErr: string): string;

// RFC 1123 subdomain. Garde-fou UI avant l'encode.
function ValidK8sName(const S: string): Boolean;

implementation

uses
  uYaml, uOps, uEnv;

procedure EmitCmValue(ARes: TStringList; const AKey, AVal: string); forward;

function ValidK8sLabel(const S: string): Boolean;
var
  i: Integer;
begin
  Result := False;
  if (S = '') or (Length(S) > 63) then Exit;
  if not (S[1] in ['a'..'z', '0'..'9']) then Exit;
  if not (S[Length(S)] in ['a'..'z', '0'..'9']) then Exit;
  for i := 2 to Length(S) - 1 do
    if not (S[i] in ['a'..'z', '0'..'9', '-']) then Exit;
  Result := True;
end;

// chaque label entre points doit valider : foo..bar / foo-.bar sont refuses
function ValidK8sName(const S: string): Boolean;
var
  start, i: Integer;
begin
  Result := False;
  if (S = '') or (Length(S) > 253) then Exit;
  start := 1;
  for i := 1 to Length(S) + 1 do
    if (i > Length(S)) or (S[i] = '.') then
    begin
      if not ValidK8sLabel(Copy(S, start, i - start)) then Exit;
      start := i + 1;
    end;
  Result := True;
end;

// le nom part BRUT dans le YAML : un `foo: bar` casserait le manifest
procedure EmitMeta(ARes: TStringList; const AName, ANamespace, ADefault: string);
var
  n, ns, clean: string;
  i: Integer;
begin
  n := Trim(AName);
  if n = '' then n := ADefault;
  if not ValidK8sName(n) then
  begin
    clean := n;
    for i := 1 to Length(clean) do
      if clean[i] < ' ' then clean[i] := ' ';
    if Length(clean) > 60 then clean := Copy(clean, 1, 60) + '...';
    ARes.Add('# requested name "' + clean
      + '" is not a valid Kubernetes name (RFC 1123), using "' + ADefault + '"');
    n := ADefault;
  end;
  ARes.Add('metadata:');
  ARes.Add('  name: ' + n);
  ns := Trim(ANamespace);
  if ns <> '' then
  begin
    if ValidK8sLabel(ns) then
      ARes.Add('  namespace: ' + ns)
    else
      ARes.Add('  # invalid namespace omitted');
  end;
end;

function ValidSecretKey(const K: string): Boolean;
var
  i: Integer;
begin
  Result := K <> '';
  for i := 1 to Length(K) do
    if not (K[i] in ['A'..'Z', 'a'..'z', '0'..'9', '-', '_', '.']) then
      Exit(False);
end;

function SecretEncode(const AName, ANamespace: string; AEnv: TStrings): string;
var
  res: TStringList;
  i: Integer;
  key, val: string;
  exp: Boolean;
  kind: TEnvKind;
begin
  res := TStringList.Create;
  res.TextLineBreakStyle := tlbsLF;
  try
    res.Add('apiVersion: v1');
    res.Add('kind: Secret');
    EmitMeta(res, AName, ANamespace, 'my-secret');
    res.Add('type: Opaque');
    res.Add('data:');
    i := 0;
    while i < AEnv.Count do
    begin
      Inc(i, EnvEntryAt(AEnv, i, key, val, exp, kind));
      if kind = ekOther then
      begin
        res.Add('  # skipped (not KEY=value): ' + Copy(Trim(AEnv[i - 1]), 1, 80));
        Continue;
      end;
      if kind <> ekEntry then Continue;
      val := EnvDecodeValue(Trim(val));
      if not ValidSecretKey(key) then
      begin
        res.Add('  # skipped invalid key: ' + key);
        Continue;
      end;
      res.Add('  ' + key + ': ' + B64Encode(val));
    end;
    Result := res.Text;
  finally
    res.Free;
  end;
end;

// `# --- doc N: nom ---` quand le manifeste porte plusieurs ressources
procedure EmitDocHeader(ARes: TStringList; ADoc: TYamlNode; AIdx, ACount: Integer);
var
  meta, nm: TYamlNode;
  s: string;
begin
  if ACount < 2 then Exit;
  s := Format('# --- document %d', [AIdx + 1]);
  meta := ADoc.ChildByKey('metadata');
  if (meta <> nil) and (meta.Kind = ykMap) then
  begin
    nm := meta.ChildByKey('name');
    if (nm <> nil) and (nm.Kind = ykScalar) and (nm.Scalar <> '') then
      // le nom vient du fichier : pas de saut de ligne dans un commentaire
      s := s + ': ' + StringReplace(StringReplace(nm.Scalar,
        #13, ' ', [rfReplaceAll]), #10, ' ', [rfReplaceAll]);
  end;
  ARes.Add(s + ' ---');
end;

function SecretDecode(const AYaml: string; out AErr: string): string;
var
  docs: TYamlDocs;
  root, data, sdata: TYamlNode;
  res: TStringList;
  i, di, found: Integer;
  dec: RawByteString;
begin
  AErr := '';
  Result := '';
  docs := YamlParseDocs(AYaml, AErr);
  if AErr <> '' then Exit;
  try
    found := 0;
    res := TStringList.Create;
    res.TextLineBreakStyle := tlbsLF;
    try
      for di := 0 to High(docs) do
      begin
        root := docs[di];
        if root.Kind <> ykMap then Continue;
        data := root.ChildByKey('data');
        sdata := root.ChildByKey('stringData');
        if ((data = nil) or (data.Kind <> ykMap)) and
           ((sdata = nil) or (sdata.Kind <> ykMap)) then Continue;
        Inc(found);
        EmitDocHeader(res, root, di, Length(docs));
        if (data <> nil) and (data.Kind = ykMap) then
          for i := 0 to High(data.Keys) do
          begin
            if data.Vals[i].Kind <> ykScalar then
            begin
              res.Add(data.Keys[i] + '=<non-scalar>');
              Continue;
            end;
            try
              dec := B64Decode(Trim(data.Vals[i].Scalar));
              EmitCmValue(res, data.Keys[i], dec);
            except
              res.Add(data.Keys[i] + '=<invalid base64>');
            end;
          end;
        if (sdata <> nil) and (sdata.Kind = ykMap) then
          for i := 0 to High(sdata.Keys) do
            if sdata.Vals[i].Kind = ykScalar then
              EmitCmValue(res, sdata.Keys[i], sdata.Vals[i].Scalar);
      end;
      if found = 0 then
      begin
        AErr := 'no data / stringData mapping found';
        Exit;
      end;
      Result := res.Text;
    finally
      res.Free;
    end;
  finally
    YamlFreeDocs(docs);
  end;
end;

function ConfigMapEncode(const AName, ANamespace: string; AEnv: TStrings): string;
var
  res: TStringList;
  i: Integer;
  key, val: string;
  exp: Boolean;
  kind: TEnvKind;
begin
  res := TStringList.Create;
  res.TextLineBreakStyle := tlbsLF;
  try
    res.Add('apiVersion: v1');
    res.Add('kind: ConfigMap');
    EmitMeta(res, AName, ANamespace, 'my-configmap');
    res.Add('data:');
    i := 0;
    while i < AEnv.Count do
    begin
      // meme lecteur que les autres outils .env : commentaire de fin coupe,
      // valeur citee multi-ligne rassemblee
      Inc(i, EnvEntryAt(AEnv, i, key, val, exp, kind));
      if kind = ekOther then
      begin
        res.Add('  # skipped (not KEY=value): ' + Copy(Trim(AEnv[i - 1]), 1, 80));
        Continue;
      end;
      if kind <> ekEntry then Continue;
      val := EnvDecodeValue(Trim(val));
      if not ValidSecretKey(key) then
      begin
        res.Add('  # skipped invalid key: ' + key);
        Continue;
      end;
      // quote YAML sinon true/123 cesseraient d'etre des strings ;
      // multi-ligne en bloc | (script, PEM) plutot qu'une ligne d'echappes
      YamlEmitScalar(res, '  ' + key + ': ', val, 2);
    end;
    Result := res.Text;
  finally
    res.Free;
  end;
end;

procedure EmitCmValue(ARes: TStringList; const AKey, AVal: string);
begin
  // EmitEnvLine quote et echappe : une valeur multi-ligne (PEM, kubeconfig)
  // recopiee brute injecterait des lignes AUTRE=valeur dans le .env de sortie
  ARes.Add(EmitEnvLine(AKey, AVal));
end;

function ConfigMapDecode(const AYaml: string; out AErr: string): string;
var
  docs: TYamlDocs;
  root, data, bdata: TYamlNode;
  res: TStringList;
  i, di, found: Integer;
  dec: RawByteString;
begin
  AErr := '';
  Result := '';
  docs := YamlParseDocs(AYaml, AErr);
  if AErr <> '' then Exit;
  try
    found := 0;
    res := TStringList.Create;
    res.TextLineBreakStyle := tlbsLF;
    try
      for di := 0 to High(docs) do
      begin
        root := docs[di];
        if root.Kind <> ykMap then Continue;
        data := root.ChildByKey('data');
        bdata := root.ChildByKey('binaryData');
        if ((data = nil) or (data.Kind <> ykMap)) and
           ((bdata = nil) or (bdata.Kind <> ykMap)) then Continue;
        Inc(found);
        EmitDocHeader(res, root, di, Length(docs));
        if (data <> nil) and (data.Kind = ykMap) then
          for i := 0 to High(data.Keys) do
            if data.Vals[i].Kind = ykScalar then
              EmitCmValue(res, data.Keys[i], data.Vals[i].Scalar)
            else
              res.Add(data.Keys[i] + '=<non-scalar>');
        if (bdata <> nil) and (bdata.Kind = ykMap) then
          for i := 0 to High(bdata.Keys) do
          begin
            if bdata.Vals[i].Kind <> ykScalar then
            begin
              res.Add(bdata.Keys[i] + '=<non-scalar>');
              Continue;
            end;
            try
              dec := B64Decode(Trim(bdata.Vals[i].Scalar));
              EmitCmValue(res, bdata.Keys[i], dec);
            except
              res.Add(bdata.Keys[i] + '=<invalid base64>');
            end;
          end;
      end;
      if found = 0 then
      begin
        AErr := 'no data / binaryData mapping found';
        Exit;
      end;
      Result := res.Text;
    finally
      res.Free;
    end;
  finally
    YamlFreeDocs(docs);
  end;
end;

end.
