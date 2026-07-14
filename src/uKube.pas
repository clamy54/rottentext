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
  uYaml, uOps;

function StripEnvQuotes(const S: string): string;
begin
  Result := S;
  if Length(Result) >= 2 then
    if ((Result[1] = '"') and (Result[Length(Result)] = '"')) or
       ((Result[1] = '''') and (Result[Length(Result)] = '''')) then
      Result := Copy(Result, 2, Length(Result) - 2);
end;

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
  i, eq: Integer;
  ln, key, val: string;
begin
  res := TStringList.Create;
  try
    res.Add('apiVersion: v1');
    res.Add('kind: Secret');
    EmitMeta(res, AName, ANamespace, 'my-secret');
    res.Add('type: Opaque');
    res.Add('data:');
    for i := 0 to AEnv.Count - 1 do
    begin
      ln := AEnv[i];
      if (Trim(ln) = '') or (Trim(ln)[1] = '#') then Continue;
      if Copy(TrimLeft(ln), 1, 7) = 'export ' then
        ln := Copy(TrimLeft(ln), 8, MaxInt);
      eq := Pos('=', ln);
      if eq = 0 then Continue;
      key := Trim(Copy(ln, 1, eq - 1));
      val := StripEnvQuotes(Trim(Copy(ln, eq + 1, MaxInt)));
      if not ValidSecretKey(key) then Continue;
      res.Add('  ' + key + ': ' + B64Encode(val));
    end;
    Result := res.Text;
  finally
    res.Free;
  end;
end;

function SecretDecode(const AYaml: string; out AErr: string): string;
var
  root, data, sdata: TYamlNode;
  res: TStringList;
  i: Integer;
  dec: RawByteString;
begin
  AErr := '';
  Result := '';
  root := YamlParse(AYaml, AErr);
  if root = nil then Exit;
  try
    if root.Kind <> ykMap then
    begin
      AErr := 'not a Kubernetes manifest (expected a mapping)';
      Exit;
    end;
    data := root.ChildByKey('data');
    sdata := root.ChildByKey('stringData');
    if ((data = nil) or (data.Kind <> ykMap)) and
       ((sdata = nil) or (sdata.Kind <> ykMap)) then
    begin
      AErr := 'no data / stringData mapping found';
      Exit;
    end;
    res := TStringList.Create;
    try
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
            res.Add(data.Keys[i] + '=' + dec);
          except
            res.Add(data.Keys[i] + '=<invalid base64>');
          end;
        end;
      if (sdata <> nil) and (sdata.Kind = ykMap) then
        for i := 0 to High(sdata.Keys) do
          if sdata.Vals[i].Kind = ykScalar then
            res.Add(sdata.Keys[i] + '=' + sdata.Vals[i].Scalar);
      Result := res.Text;
    finally
      res.Free;
    end;
  finally
    root.Free;
  end;
end;

function ConfigMapEncode(const AName, ANamespace: string; AEnv: TStrings): string;
var
  res: TStringList;
  i, eq: Integer;
  ln, key, val: string;
begin
  res := TStringList.Create;
  res.TextLineBreakStyle := tlbsLF;
  try
    res.Add('apiVersion: v1');
    res.Add('kind: ConfigMap');
    EmitMeta(res, AName, ANamespace, 'my-configmap');
    res.Add('data:');
    for i := 0 to AEnv.Count - 1 do
    begin
      ln := AEnv[i];
      if (Trim(ln) = '') or (Trim(ln)[1] = '#') then Continue;
      if Copy(TrimLeft(ln), 1, 7) = 'export ' then
        ln := Copy(TrimLeft(ln), 8, MaxInt);
      eq := Pos('=', ln);
      if eq = 0 then Continue;
      key := Trim(Copy(ln, 1, eq - 1));
      val := StripEnvQuotes(Trim(Copy(ln, eq + 1, MaxInt)));
      if not ValidSecretKey(key) then Continue;
      // quote YAML sinon true/123 cesseraient d'etre des strings
      res.Add('  ' + key + ': ' + YamlQuoteScalar(val));
    end;
    Result := res.Text;
  finally
    res.Free;
  end;
end;

procedure EmitCmValue(ARes: TStringList; const AKey, AVal: string);
begin
  if (Pos(#10, AVal) = 0) and (Pos(#13, AVal) = 0) then
    ARes.Add(AKey + '=' + AVal)
  else
  begin
    ARes.Add('# --- ' + AKey + ' (multi-line) ---');
    ARes.AddText(AVal);
    ARes.Add('# --- end ' + AKey + ' ---');
  end;
end;

function ConfigMapDecode(const AYaml: string; out AErr: string): string;
var
  root, data, bdata: TYamlNode;
  res: TStringList;
  i: Integer;
  dec: RawByteString;
begin
  AErr := '';
  Result := '';
  root := YamlParse(AYaml, AErr);
  if root = nil then Exit;
  try
    if root.Kind <> ykMap then
    begin
      AErr := 'not a Kubernetes manifest (expected a mapping)';
      Exit;
    end;
    data := root.ChildByKey('data');
    bdata := root.ChildByKey('binaryData');
    if ((data = nil) or (data.Kind <> ykMap)) and
       ((bdata = nil) or (bdata.Kind <> ykMap)) then
    begin
      AErr := 'no data / binaryData mapping found';
      Exit;
    end;
    res := TStringList.Create;
    res.TextLineBreakStyle := tlbsLF;
    try
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
      Result := res.Text;
    finally
      res.Free;
    end;
  finally
    root.Free;
  end;
end;

end.
