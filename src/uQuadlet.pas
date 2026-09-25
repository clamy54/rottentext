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

  function HexV(c: Char): Integer;
  begin
    case c of
      '0'..'9': Result := Ord(c) - 48;
      'a'..'f': Result := Ord(c) - 87;
      'A'..'F': Result := Ord(c) - 55;
    else Result := -1;
    end;
  end;

  // \uXXXX / \UXXXXXXXX -> UTF-8
  function U8(cp: Cardinal): string;
  begin
    if cp < $80 then Result := Chr(cp)
    else if cp < $800 then
      Result := Chr($C0 or (cp shr 6)) + Chr($80 or (cp and $3F))
    else if cp < $10000 then
      Result := Chr($E0 or (cp shr 12)) + Chr($80 or ((cp shr 6) and $3F)) +
        Chr($80 or (cp and $3F))
    else
      Result := Chr($F0 or (cp shr 18)) + Chr($80 or ((cp shr 12) and $3F)) +
        Chr($80 or ((cp shr 6) and $3F)) + Chr($80 or (cp and $3F));
  end;

  // echappes C de systemd.syntax(7) ; inconnu = garde tel quel
  procedure Escape;
  var
    k, v, d: Integer;
    cp: Cardinal;
  begin
    case AVal[i + 1] of
      'a': tok := tok + #7;
      'b': tok := tok + #8;
      'f': tok := tok + #12;
      'n': tok := tok + #10;
      'r': tok := tok + #13;
      't': tok := tok + #9;
      'v': tok := tok + #11;
      's': tok := tok + ' ';
      '\', '"', '''': tok := tok + AVal[i + 1];
      'x':
        if (i + 3 <= n) and (HexV(AVal[i + 2]) >= 0) and (HexV(AVal[i + 3]) >= 0) then
        begin
          tok := tok + Chr(HexV(AVal[i + 2]) * 16 + HexV(AVal[i + 3]));
          Inc(i, 2);
        end
        else tok := tok + '\x';
      '0'..'7':
        if (i + 3 <= n) and (AVal[i + 2] in ['0'..'7']) and (AVal[i + 3] in ['0'..'7']) then
        begin
          tok := tok + Chr((Ord(AVal[i + 1]) - 48) * 64 + (Ord(AVal[i + 2]) - 48) * 8 +
            Ord(AVal[i + 3]) - 48);
          Inc(i, 2);
        end
        else tok := tok + '\' + AVal[i + 1];
      'u', 'U':
        begin
          if AVal[i + 1] = 'u' then k := 4 else k := 8;
          cp := 0; v := 0;
          if i + 1 + k <= n then
            for d := 1 to k do
            begin
              v := HexV(AVal[i + 1 + d]);
              if v < 0 then Break;
              cp := cp * 16 + Cardinal(v);
            end;
          if (i + 1 + k <= n) and (v >= 0) and (cp <= $10FFFF) and
             not ((cp >= $D800) and (cp <= $DFFF)) then
          begin
            tok := tok + U8(cp);
            Inc(i, k);
          end
          else tok := tok + '\' + AVal[i + 1];
        end;
    else
      tok := tok + '\' + AVal[i + 1];
    end;
    Inc(i, 2);
  end;

  procedure Flush;
  begin
    if tok <> '' then
    begin
      eq := Pos('=', tok);
      if eq > 0 then
        ADest.Add(EmitEnvLine(Copy(tok, 1, eq - 1), Copy(tok, eq + 1, MaxInt)))
      else
        ADest.Add('# skipped (no =): ' + tok);
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
      Escape; // "a\nb" gardait juste `anb`
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
  tags.CaseSensitive := True;
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
  seen: Boolean;
  sect, key, val, ln: string;
begin
  Result := '';
  AErr := '';
  lines := TStringList.Create;
  sl := TStringList.Create;
  try
    lines.Text := AText;
    sl.Add('# environment from podman quadlet unit');
    before := sl.Count;
    seen := False;
    sect := '';
    i := 0;
    while i < lines.Count do
    begin
      ln := lines[i];
      Inc(i);
      if IniSection(ln, key) then begin sect := key; Continue; end;
      // Environment= vit dans [Container] (Quadlet) ou [Service] (unite brute)
      if not (SameText(sect, 'Container') or SameText(sect, 'Service')) then Continue;
      if not IniKV(ln, key, val) then Continue;
      // `\` en fin de ligne = suite sur la suivante (systemd) ; sans ca la
      // ligne suivante etait sautee en silence
      while (TrimRight(val) <> '') and (TrimRight(val)[Length(TrimRight(val))] = '\') and
            (i < lines.Count) do
      begin
        val := Copy(TrimRight(val), 1, Length(TrimRight(val)) - 1) + ' ' + lines[i];
        Inc(i);
      end;
      if SameText(key, 'Environment') then
      begin
        seen := True;
        // Environment= vide annule tout ce qui precede (systemd.exec)
        if Trim(val) = '' then
          while sl.Count > before do sl.Delete(sl.Count - 1)
        else
          ParseSystemdEnv(val, sl);
      end
      else if SameText(key, 'EnvironmentFile') then
        sl.Add('# EnvironmentFile: ' + Trim(val) + ' (external, not inlined)');
    end;
    if not seen and (sl.Count = before) then
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
