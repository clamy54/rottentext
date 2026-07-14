unit uQuadlet;

{$mode objfpc}{$H+}

// Aides Podman Quadlet (unite systemd = INI). HEURISTIQUE : cles matchees sans
// tenir compte de la casse (systemd est sensible) ; continuation `\` NON geree.

interface

uses
  Classes, SysUtils;

function QuadletTagOnLine(const ALine: string): string;

// rend la ligne INCHANGEE si ce n'est pas une ligne Image=
function QuadletRetagLine(const ALine, ANewTag: string): string;

function QuadletListImage(const AText: string; out AErr: string): string;

function QuadletEnvDotenv(const AText: string; out AErr: string): string;

implementation

uses
  uCompose, uEnv;

function IniSection(const ALine: string; out ASection: string): Boolean;
var
  t: string;
begin
  Result := False;
  ASection := '';
  t := Trim(ALine);
  if (Length(t) >= 2) and (t[1] = '[') and (t[Length(t)] = ']') then
  begin
    ASection := Copy(t, 2, Length(t) - 2);
    Result := True;
  end;
end;

function IniKV(const ALine: string; out AKey, AVal: string): Boolean;
var
  t: string;
  eq: Integer;
begin
  Result := False;
  AKey := ''; AVal := '';
  t := TrimLeft(ALine);
  if (t = '') or (t[1] = '#') or (t[1] = ';') or (t[1] = '[') then Exit;
  eq := Pos('=', t);
  if eq = 0 then Exit;
  AKey := Trim(Copy(t, 1, eq - 1));
  AVal := Copy(t, eq + 1, MaxInt);
  Result := AKey <> '';
end;

// semantique systemd : N mots KEY=VALUE par ligne, `\` echappe le caractere
// suivant (hello\ world = un mot). Limite : sequences C \n/\t non developpees.
procedure ParseSystemdEnv(const AVal: string; ADest: TStrings);
var
  i, n, eq: Integer;
  q: Char;
  tok: string;
  inq: Boolean;

  procedure Flush;
  begin
    if tok <> '' then
    begin
      eq := Pos('=', tok);
      if eq > 0 then
        ADest.Add(EmitEnvLine(Copy(tok, 1, eq - 1), Copy(tok, eq + 1, MaxInt)));
      tok := '';
    end;
  end;

begin
  n := Length(AVal);
  i := 1; tok := ''; inq := False; q := #0;
  while i <= n do
  begin
    if (AVal[i] = '\') and (i < n) then
    begin
      tok := tok + AVal[i + 1];
      Inc(i, 2);
      Continue;
    end;
    if inq then
    begin
      if AVal[i] = q then inq := False else tok := tok + AVal[i];
    end
    else if (AVal[i] = '"') or (AVal[i] = '''') then
    begin
      inq := True; q := AVal[i];
    end
    else if (AVal[i] = ' ') or (AVal[i] = #9) then
      Flush
    else
      tok := tok + AVal[i];
    Inc(i);
  end;
  Flush;
end;

// APrefix et ASuffix (espaces, quotes) sont PRESERVES au retag
function ParseImageLine(const ALine: string; out APrefix, AValue, ASuffix: string;
  out AQuote: Char): Boolean;
var
  n, i, eq, vs, ve: Integer;
  key, valpart: string;
begin
  Result := False;
  APrefix := ''; AValue := ''; ASuffix := ''; AQuote := #0;
  n := Length(ALine);
  i := 1;
  while (i <= n) and ((ALine[i] = ' ') or (ALine[i] = #9)) do Inc(i);
  eq := Pos('=', ALine);
  if (eq = 0) or (eq < i) then Exit;
  key := Trim(Copy(ALine, i, eq - i));
  if not SameText(key, 'Image') then Exit;
  vs := eq + 1;
  while (vs <= n) and ((ALine[vs] = ' ') or (ALine[vs] = #9)) do Inc(vs);
  APrefix := Copy(ALine, 1, vs - 1);
  valpart := Copy(ALine, vs, MaxInt);
  if valpart = '' then Exit;
  if (valpart[1] = '"') or (valpart[1] = '''') then
  begin
    AQuote := valpart[1];
    ve := 2;
    while (ve <= Length(valpart)) and (valpart[ve] <> AQuote) do Inc(ve);
    AValue := Copy(valpart, 2, ve - 2);
    ASuffix := Copy(valpart, ve + 1, MaxInt);
  end
  else
  begin
    // la ref finit au premier blanc, le reste est garde verbatim
    ve := 1;
    while (ve <= Length(valpart)) and (valpart[ve] <> ' ') and (valpart[ve] <> #9) do
      Inc(ve);
    AValue := Copy(valpart, 1, ve - 1);
    ASuffix := Copy(valpart, ve, MaxInt);
  end;
  Result := AValue <> '';
end;

function QuadletTagOnLine(const ALine: string): string;
var
  pref, val, suf, repo, tag, dig: string;
  q: Char;
begin
  Result := '';
  if not ParseImageLine(ALine, pref, val, suf, q) then Exit;
  if SplitImageRef(val, repo, tag, dig) then Result := tag;
end;

function QuadletRetagLine(const ALine, ANewTag: string): string;
var
  pref, val, suf, repo, tag, dig, nv: string;
  q: Char;
begin
  Result := ALine;
  if not ParseImageLine(ALine, pref, val, suf, q) then Exit;
  if not SplitImageRef(val, repo, tag, dig) then Exit;
  nv := repo + ':' + ANewTag;
  if dig <> '' then nv := nv + '@' + dig;
  if q <> #0 then nv := q + nv + q;
  Result := pref + nv + suf;
end;

function QuadletListImage(const AText: string; out AErr: string): string;
var
  lines, sl, tags: TStringList;
  i: Integer;
  sect, key, val, pref, suf, repo, tag, dig: string;
  q: Char;
  n: Integer;
begin
  Result := '';
  AErr := '';
  lines := TStringList.Create;
  sl := TStringList.Create;
  tags := TStringList.Create;
  tags.Sorted := True;
  tags.Duplicates := dupIgnore;
  try
    lines.Text := AText;
    sect := '';
    n := 0;
    sl.Add('# podman quadlet images');
    sl.Add('');
    for i := 0 to lines.Count - 1 do
    begin
      if IniSection(lines[i], key) then begin sect := key; Continue; end;
      if not SameText(sect, 'Container') then Continue;
      if not ParseImageLine(lines[i], pref, val, suf, q) then Continue;
      Inc(n);
      sl.Add('  Image: ' + val);
      if SplitImageRef(val, repo, tag, dig) then
        if dig <> '' then tags.Add(repo + ' @' + Copy(dig, 1, 19) + '...')
        else if tag <> '' then tags.Add(repo + ' : ' + tag)
        else tags.Add(repo + ' : (latest, implicit)');
    end;
    if n = 0 then
    begin
      AErr := 'no Image= found in a [Container] section (is this a Quadlet unit?)';
      Exit;
    end;
    sl.Add('');
    sl.Add('=== unique repo/tag ===');
    sl.AddStrings(tags);
    Result := sl.Text;
  finally
    lines.Free; sl.Free; tags.Free;
  end;
end;

function QuadletEnvDotenv(const AText: string; out AErr: string): string;
var
  lines, sl: TStringList;
  i, before: Integer;
  sect, key, val: string;
begin
  Result := '';
  AErr := '';
  lines := TStringList.Create;
  sl := TStringList.Create;
  try
    lines.Text := AText;
    sl.Add('# environment from podman quadlet unit');
    before := sl.Count;
    sect := '';
    for i := 0 to lines.Count - 1 do
    begin
      if IniSection(lines[i], key) then begin sect := key; Continue; end;
      // Environment= vit dans [Container] (Quadlet) ou [Service] (unite brute)
      if not (SameText(sect, 'Container') or SameText(sect, 'Service')) then Continue;
      if not IniKV(lines[i], key, val) then Continue;
      if SameText(key, 'Environment') then
        ParseSystemdEnv(val, sl)
      else if SameText(key, 'EnvironmentFile') then
        sl.Add('# EnvironmentFile: ' + Trim(val) + ' (external, not inlined)');
    end;
    if sl.Count = before then
    begin
      AErr := 'no Environment= found in [Container]/[Service]';
      Exit;
    end;
    Result := sl.Text;
  finally
    lines.Free; sl.Free;
  end;
end;

end.
