unit uTf;

{$mode objfpc}{$H+}

// Scanner Terraform lineaire (pas de regex), PAS un parseur HCL : seuls les
// blocs `variable "name" {}` racine sont lus, sur une ligne MASQUEE (chaines et
// ${} vides) pour que le comptage de braces ne se fasse pas piper par une
// chaine. HEURISTIQUE : expressions non evaluees, templating non vu.

interface

uses
  Classes, SysUtils;

type
  TTfVar = record
    Name: string;
    TypeStr: string;
    HasDefault: Boolean;
    DefaultStr: string;   // verbatim, heredoc compris
    Description: string;
    Sensitive: Boolean;
    Line: Integer;
  end;
  TTfVars = array of TTfVar;

const
  TF_MAX_BYTES = 8 * 1024 * 1024;  // entree non fiable : plafonds durs
  TF_MAX_VARS  = 4096;
  TF_MAX_VALUE = 64 * 1024;

function TfScanVariables(const AText: string; out AVars: TTfVars; out AErr: string): Boolean;
function TfListVariables(const AText: string; out AErr: string): string;
function TfVarsSkeleton(const AText: string; out AErr: string): string;
function TfFindDuplicates(const AText: string; out AErr: string): string;

implementation

// positions 1:1 avec la ligne brute jusqu'a la coupe de commentaire
function MaskLine(const ALine: string; var AInBlock: Boolean): string;
var
  i, n, interp: Integer;
  inStr, inStr2: Boolean;
begin
  Result := '';
  n := Length(ALine);
  i := 1;
  inStr := False; inStr2 := False; interp := 0;
  while i <= n do
  begin
    if AInBlock then
    begin
      if (i < n) and (ALine[i] = '*') and (ALine[i + 1] = '/') then
      begin
        AInBlock := False;
        Result := Result + '  ';
        Inc(i, 2);
      end
      else begin Result := Result + ' '; Inc(i); end;
      Continue;
    end;
    if interp > 0 then // ${ } : du code dans une chaine, jamais compte
    begin
      if inStr2 then
      begin
        if (ALine[i] = '\') and (i < n) then
        begin Result := Result + '  '; Inc(i, 2); Continue; end;
        if ALine[i] = '"' then inStr2 := False;
        Result := Result + ' ';
      end
      else
        case ALine[i] of
          '"': begin inStr2 := True; Result := Result + ' '; end;
          '{': begin Inc(interp); Result := Result + ' '; end;
          '}': begin Dec(interp); Result := Result + ' '; end;
        else
          Result := Result + ' ';
        end;
      Inc(i);
      Continue;
    end;
    if inStr then
    begin
      if (ALine[i] = '\') and (i < n) then
      begin Result := Result + '  '; Inc(i, 2); Continue; end;
      if (ALine[i] = '$') and (i < n) and (ALine[i + 1] = '{') then
      begin interp := 1; Result := Result + '  '; Inc(i, 2); Continue; end;
      if ALine[i] = '"' then begin inStr := False; Result := Result + '"'; end
      else Result := Result + ' ';
      Inc(i);
      Continue;
    end;
    case ALine[i] of
      '"': begin inStr := True; Result := Result + '"'; end;
      '#': Break;
      '/':
        if (i < n) and (ALine[i + 1] = '/') then Break
        else if (i < n) and (ALine[i + 1] = '*') then
        begin AInBlock := True; Result := Result + '  '; Inc(i); end
        else Result := Result + '/';
    else
      Result := Result + ALine[i];
    end;
    Inc(i);
  end;
end;

function BraceNet(const S: string): Integer;
var
  i: Integer;
begin
  Result := 0;
  for i := 1 to Length(S) do
    case S[i] of
      '{': Inc(Result);
      '}': Dec(Result);
    end;
end;

function BracketNet(const S: string): Integer;
var
  i: Integer;
begin
  Result := 0;
  for i := 1 to Length(S) do
    case S[i] of
      '{', '[', '(': Inc(Result);
      '}', ']', ')': Dec(Result);
    end;
end;

function PosNetReaches(const S: string; ATarget: Integer): Integer;
var
  i, net: Integer;
begin
  Result := 0;
  net := 0;
  for i := 1 to Length(S) do
    case S[i] of
      '{', '[', '(': begin Inc(net); if net = ATarget then Exit(i); end;
      '}', ']', ')': begin Dec(net); if net = ATarget then Exit(i); end;
    end;
end;

// le '}' qui ferme le BLOC, pas la valeur : cas du one-liner
function FirstUnbalancedClose(const S: string): Integer;
var
  i, net: Integer;
begin
  Result := 0;
  net := 0;
  for i := 1 to Length(S) do
    case S[i] of
      '{': Inc(net);
      '}': begin Dec(net); if net < 0 then Exit(i); end;
    end;
end;

// le nom se lit dans la ligne BRUTE : le masque a vide les chaines
function VarHeader(const AMasked, ARaw: string; out AName: string;
  out ABrace: Integer): Boolean;
var
  i, n, q1, q2: Integer;
begin
  Result := False;
  AName := ''; ABrace := 0;
  n := Length(AMasked);
  i := 1;
  while (i <= n) and (AMasked[i] in [' ', #9]) do Inc(i);
  if Copy(AMasked, i, 8) <> 'variable' then Exit;
  Inc(i, 8);
  if (i <= n) and not (AMasked[i] in [' ', #9, '"']) then Exit;
  while (i <= n) and (AMasked[i] in [' ', #9]) do Inc(i);
  if (i > n) or (AMasked[i] <> '"') then Exit;
  q1 := i;
  q2 := q1 + 1;
  while (q2 <= n) and (AMasked[q2] <> '"') do Inc(q2);
  if q2 > n then Exit;
  AName := Copy(ARaw, q1 + 1, q2 - q1 - 1);
  i := q2 + 1;
  while (i <= n) and (AMasked[i] in [' ', #9]) do Inc(i);
  if (i <= n) then
  begin
    if AMasked[i] <> '{' then Exit;
    ABrace := i;
  end;
  Result := AName <> '';
end;

function AttrLine(const S: string; out AKey: string; out AValPos: Integer): Boolean;
var
  i, n, ks: Integer;
begin
  Result := False;
  AKey := ''; AValPos := 0;
  n := Length(S);
  i := 1;
  while (i <= n) and (S[i] in [' ', #9]) do Inc(i);
  ks := i;
  while (i <= n) and (S[i] in ['a'..'z', 'A'..'Z', '0'..'9', '_', '-']) do Inc(i);
  if i = ks then Exit;
  AKey := LowerCase(Copy(S, ks, i - ks));
  while (i <= n) and (S[i] in [' ', #9]) do Inc(i);
  if (i > n) or (S[i] <> '=') then Exit;
  if (i < n) and (S[i + 1] = '=') then Exit; // '==' : une expression, pas un attribut
  AValPos := i + 1;
  Result := True;
end;

function HeredocTerm(const AVal: string): string;
var
  t: string;
  i, n: Integer;
begin
  Result := '';
  t := AVal;
  if Copy(t, 1, 2) <> '<<' then Exit;
  Delete(t, 1, 2);
  if (t <> '') and (t[1] = '-') then Delete(t, 1, 1);
  n := Length(t);
  i := 1;
  while (i <= n) and (t[i] in ['a'..'z', 'A'..'Z', '0'..'9', '_']) do Inc(i);
  Result := Copy(t, 1, i - 1);
end;

function Unquote(const S: string): string;
begin
  Result := Trim(S);
  if (Length(Result) >= 2) and (Result[1] = '"') and (Result[Length(Result)] = '"') then
  begin
    Result := Copy(Result, 2, Length(Result) - 2);
    Result := StringReplace(Result, '\"', '"', [rfReplaceAll]);
    Result := StringReplace(Result, '\\', '\', [rfReplaceAll]);
  end;
end;

function OneLineVal(const S: string): string;
var
  i: Integer;
  sp: Boolean;
begin
  Result := '';
  sp := False;
  for i := 1 to Length(S) do
    if S[i] in [' ', #9, #10, #13] then
    begin
      if not sp and (Result <> '') then Result := Result + ' ';
      sp := True;
    end
    else
    begin
      Result := Result + S[i];
      sp := False;
    end;
  Result := TrimRight(Result);
  if Length(Result) > 100 then Result := Copy(Result, 1, 97) + '...';
end;

function TfScanVariables(const AText: string; out AVars: TTfVars; out AErr: string): Boolean;
var
  lines: TStringList;
  li, cnt, depth, relDepth, p, bp: Integer;
  inBlock, inVar, awaitBrace: Boolean;
  raw, m, t, name: string;
  cur: TTfVar;
  capKey, capVal, capHeredoc: string;
  capNet: Integer;
  capOver: Boolean;

  procedure AppendCap(const S: string);
  begin
    if capOver then Exit;
    if Length(capVal) + Length(S) > TF_MAX_VALUE then
    begin
      capVal := capVal + LineEnding + '# (value truncated)';
      capOver := True;
      Exit;
    end;
    if capVal = '' then capVal := S
    else capVal := capVal + LineEnding + S;
  end;

  procedure StoreAttr(const AKey, AVal: string);
  begin
    if AKey = 'type' then cur.TypeStr := AVal
    else if AKey = 'default' then
    begin
      cur.HasDefault := True;
      cur.DefaultStr := AVal;
    end
    else if AKey = 'description' then cur.Description := Unquote(AVal)
    else if AKey = 'sensitive' then cur.Sensitive := SameText(Trim(AVal), 'true');
  end;

  function WantedKey(const K: string): Boolean;
  begin
    Result := (K = 'type') or (K = 'default') or (K = 'description') or
      (K = 'sensitive');
  end;

  procedure EndVar;
  begin
    if (cur.Name <> '') and (cnt < TF_MAX_VARS) then
    begin
      if cnt >= Length(AVars) then SetLength(AVars, cnt + 32);
      AVars[cnt] := cur;
      Inc(cnt);
    end;
    cur := Default(TTfVar);
    inVar := False;
    relDepth := 0;
  end;

  procedure InVarLine(const mL, rL: string);
  var
    key, val, vm, hterm: string;
    vs, q, net: Integer;
  begin
    if (relDepth = 1) and AttrLine(mL, key, vs) and WantedKey(key) then
    begin
      vm := Copy(mL, vs, MaxInt);
      q := FirstUnbalancedClose(vm);
      if q > 0 then vm := Copy(vm, 1, q - 1);
      val := Trim(Copy(rL, vs, Length(vm)));
      hterm := HeredocTerm(val);
      if hterm <> '' then
      begin
        capKey := key; capVal := val; capHeredoc := hterm;
        capNet := 0; capOver := False;
      end
      else
      begin
        net := BracketNet(vm);
        if net > 0 then // valeur multi-ligne : suite prise par le main loop
        begin
          capKey := key; capVal := val; capNet := net; capOver := False;
        end
        else
          StoreAttr(key, val);
      end;
      if q > 0 then
      begin
        relDepth := relDepth + BraceNet(Copy(mL, vs + q - 1, MaxInt));
        if relDepth <= 0 then EndVar;
      end;
      Exit;
    end;
    relDepth := relDepth + BraceNet(mL);
    if relDepth <= 0 then EndVar;
  end;

begin
  AVars := nil;
  AErr := '';
  Result := False;
  if Length(AText) > TF_MAX_BYTES then
  begin
    AErr := Format('text too large for the Terraform scanner (max %d MB)',
      [TF_MAX_BYTES div (1024 * 1024)]);
    Exit;
  end;
  lines := TStringList.Create;
  try
    lines.Text := AText;
    cnt := 0; depth := 0; relDepth := 0;
    inBlock := False; inVar := False; awaitBrace := False;
    cur := Default(TTfVar);
    capKey := ''; capVal := ''; capHeredoc := ''; capNet := 0; capOver := False;
    for li := 0 to lines.Count - 1 do
    begin
      raw := lines[li];
      if capHeredoc <> '' then // heredoc : lignes BRUTES, un #! n'y est pas un commentaire
      begin
        AppendCap(raw);
        if Trim(raw) = capHeredoc then
        begin
          StoreAttr(capKey, capVal);
          capKey := ''; capVal := ''; capHeredoc := '';
        end;
        Continue;
      end;
      m := MaskLine(raw, inBlock);
      if capKey <> '' then
      begin
        p := PosNetReaches(m, -capNet);
        if p > 0 then
        begin
          AppendCap(TrimRight(Copy(raw, 1, p)));
          StoreAttr(capKey, capVal);
          capKey := ''; capVal := '';
          if inVar then InVarLine(Copy(m, p + 1, MaxInt), Copy(raw, p + 1, MaxInt));
        end
        else
        begin
          capNet := capNet + BracketNet(m);
          AppendCap(raw);
        end;
        Continue;
      end;
      if inVar then
      begin
        InVarLine(m, raw);
        Continue;
      end;
      if awaitBrace then
      begin
        t := TrimLeft(m);
        if t = '' then Continue;
        if t[1] = '{' then
        begin
          awaitBrace := False;
          inVar := True;
          relDepth := 1;
          p := Pos('{', m);
          InVarLine(Copy(m, p + 1, MaxInt), Copy(raw, p + 1, MaxInt));
          Continue;
        end;
        awaitBrace := False;
        cur := Default(TTfVar);
      end;
      if (depth = 0) and VarHeader(m, raw, name, bp) then
      begin
        if cnt >= TF_MAX_VARS then Break;
        cur := Default(TTfVar);
        cur.Name := name;
        cur.Line := li + 1;
        if bp > 0 then
        begin
          inVar := True;
          relDepth := 1;
          InVarLine(Copy(m, bp + 1, MaxInt), Copy(raw, bp + 1, MaxInt));
        end
        else
          awaitBrace := True;
        Continue;
      end;
      depth := depth + BraceNet(m);
      if depth < 0 then depth := 0;
    end;
    if capKey <> '' then StoreAttr(capKey, capVal);
    if inVar then EndVar;
    SetLength(AVars, cnt);
    if cnt = 0 then
    begin
      AErr := 'no variable "..." blocks found (is this a .tf file?)';
      Exit;
    end;
    Result := True;
  finally
    lines.Free;
  end;
end;

function TfListVariables(const AText: string; out AErr: string): string;
var
  vars: TTfVars;
  sl: TStringList;
  i, req, sens: Integer;
begin
  Result := '';
  if not TfScanVariables(AText, vars, AErr) then Exit;
  req := 0; sens := 0;
  for i := 0 to High(vars) do
  begin
    if not vars[i].HasDefault then Inc(req);
    if vars[i].Sensitive then Inc(sens);
  end;
  sl := TStringList.Create;
  try
    sl.Add(Format('# terraform variables: %d declared (%d required, %d sensitive)',
      [Length(vars), req, sens]));
    sl.Add('# heuristic scan: root-level variable blocks only');
    for i := 0 to High(vars) do
    begin
      sl.Add('');
      sl.Add(Format('variable "%s"  (line %d)', [vars[i].Name, vars[i].Line]));
      if vars[i].TypeStr <> '' then
        sl.Add('  type:        ' + OneLineVal(vars[i].TypeStr));
      // le default d'une variable sensible ne sort JAMAIS en clair
      if vars[i].HasDefault then
      begin
        if vars[i].Sensitive then
          sl.Add('  default:     (redacted, sensitive)')
        else
          sl.Add('  default:     ' + OneLineVal(vars[i].DefaultStr));
      end
      else
        sl.Add('  default:     (none, required)');
      if vars[i].Sensitive then
        sl.Add('  sensitive:   true');
      if vars[i].Description <> '' then
        sl.Add('  description: ' + OneLineVal(vars[i].Description));
    end;
    Result := sl.Text;
  finally
    sl.Free;
  end;
end;

function PlaceholderFor(const ATypeStr: string): string;
var
  t: string;
begin
  t := LowerCase(Trim(ATypeStr));
  if Copy(t, 1, 6) = 'number' then Result := '0'
  else if Copy(t, 1, 4) = 'bool' then Result := 'false'
  else if (Copy(t, 1, 4) = 'list') or (Copy(t, 1, 3) = 'set') or
    (Copy(t, 1, 5) = 'tuple') then Result := '[]'
  else if (Copy(t, 1, 3) = 'map') or (Copy(t, 1, 6) = 'object') then Result := '{}'
  else Result := '""';
end;

function TfVarsSkeleton(const AText: string; out AErr: string): string;
var
  vars: TTfVars;
  sl, dl: TStringList;
  i, j, req: Integer;
  ln: string;
begin
  Result := '';
  if not TfScanVariables(AText, vars, AErr) then Exit;
  req := 0;
  for i := 0 to High(vars) do
    if not vars[i].HasDefault then Inc(req);
  sl := TStringList.Create;
  try
    sl.Add(Format('# terraform.tfvars skeleton: %d variables (%d required, %d optional)',
      [Length(vars), req, Length(vars) - req]));
    sl.Add('# generated from variable blocks, heuristic scan');
    if req > 0 then
    begin
      sl.Add('');
      sl.Add('# --- required (no default) ---');
      for i := 0 to High(vars) do
      begin
        if vars[i].HasDefault then Continue;
        sl.Add('');
        // sans OneLineVal, une description heredoc deviendrait du contenu ACTIF
        if vars[i].Description <> '' then
          sl.Add('# ' + OneLineVal(vars[i].Description));
        ln := vars[i].Name + ' = ' + PlaceholderFor(vars[i].TypeStr);
        if vars[i].TypeStr <> '' then
          ln := ln + '  # ' + OneLineVal(vars[i].TypeStr);
        if vars[i].Sensitive then
        begin
          if vars[i].TypeStr <> '' then ln := ln + ', sensitive'
          else ln := ln + '  # sensitive';
        end;
        sl.Add(ln);
      end;
    end;
    if req < Length(vars) then
    begin
      sl.Add('');
      sl.Add('# --- optional (default shown, uncomment to override) ---');
      for i := 0 to High(vars) do
      begin
        if not vars[i].HasDefault then Continue;
        sl.Add('');
        if vars[i].Description <> '' then
          sl.Add('# ' + OneLineVal(vars[i].Description));
        if vars[i].Sensitive then
          // jamais le default d'une variable sensible dans le squelette
          sl.Add('# ' + vars[i].Name + ' = ' + PlaceholderFor(vars[i].TypeStr)
            + '  # sensitive, default redacted')
        else
        begin
          dl := TStringList.Create;
          try
            dl.Text := vars[i].DefaultStr;
            if dl.Count = 0 then dl.Add('');
            dl[0] := vars[i].Name + ' = ' + dl[0];
            for j := 0 to dl.Count - 1 do
              sl.Add('# ' + dl[j]);
          finally
            dl.Free;
          end;
        end;
      end;
    end;
    Result := sl.Text;
  finally
    sl.Free;
  end;
end;

function TfFindDuplicates(const AText: string; out AErr: string): string;
var
  vars: TTfVars;
  sl: TStringList;
  seen: array of Boolean;
  i, j, n: Integer;
  lns: string;
  found: Boolean;
begin
  Result := '';
  if not TfScanVariables(AText, vars, AErr) then Exit;
  sl := TStringList.Create;
  try
    sl.Add('# duplicate terraform variables');
    sl.Add('');
    SetLength(seen, Length(vars));
    found := False;
    for i := 0 to High(vars) do
    begin
      if seen[i] then Continue;
      n := 1;
      lns := IntToStr(vars[i].Line);
      for j := i + 1 to High(vars) do
        if vars[j].Name = vars[i].Name then
        begin
          seen[j] := True;
          Inc(n);
          lns := lns + ', ' + IntToStr(vars[j].Line);
        end;
      if n > 1 then
      begin
        found := True;
        sl.Add(Format('variable "%s": declared %dx (lines %s)',
          [vars[i].Name, n, lns]));
      end;
    end;
    if not found then sl.Add('(none)');
    Result := sl.Text;
  finally
    sl.Free;
  end;
end;

end.
