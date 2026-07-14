unit uThemeLoad;

{$mode objfpc}{$H+}

// Themes JSON plats du dossier themes/, a cote de l'exe. Un fichier theme est
// une entree NON FIABLE: parse sous try/except, plafonds, seules les chaines
// "#RRGGBB" strictes sont acceptees. Theme casse = couleurs courantes intactes.

interface

uses
  Classes, SysUtils;

function ThemeCount: Integer;
function ThemeName(AIndex: Integer): string;
function CurrentTheme: Integer; // -1 = defauts du code (aucun fichier applique)
function CurrentThemeFile: string;
function ApplyTheme(AIndex: Integer): Boolean;
// ciblage par NOM DE FICHIER: le champ "name" du JSON est editable
function ApplyThemeFile(const AFileName: string): Boolean;
// a appeler APRES LoadEmbeddedFonts: ResolveMonaspace a besoin des polices chargees
procedure ApplyDefaultTheme;

implementation

uses
  fpjson, jsonparser, Graphics, uTheme, uFontEmbed;

const
  MAX_THEME_BYTES = 256 * 1024;
  MAX_THEMES      = 64;
  MAX_NAME_LEN    = 64;
  DEFAULT_THEME_FILE = 'rotten.json';

type
  PColor = ^TColor;
  TColorEntry = record
    Key: string;
    P: PColor;
    Def: TColor; // defaut du code, photographie a l'init
  end;
  TThemeFile = record
    FileName: string; // nom simple, jamais un chemin
    Display: string;
  end;

var
  Reg: array of TColorEntry;
  Themes: array of TThemeFile;
  FCurrent: Integer = -1;

function ThemesDir: string;
begin
  Result := IncludeTrailingPathDelimiter(
    IncludeTrailingPathDelimiter(ExtractFilePath(ParamStr(0))) + 'themes');
end;

procedure R(const AKey: string; var C: TColor);
begin
  SetLength(Reg, Length(Reg) + 1);
  Reg[High(Reg)].Key := AKey;
  Reg[High(Reg)].P := @C;
  Reg[High(Reg)].Def := C;
end;

// le BOM UTF-8 est retire: GetJSON refuse un flux qui en porte un
function ReadCapped(const AName: string; out AData: string): Boolean;
var
  fs: TFileStream;
begin
  Result := False;
  AData := '';
  try
    fs := TFileStream.Create(ThemesDir + AName, fmOpenRead or fmShareDenyWrite);
    try
      if (fs.Size <= 0) or (fs.Size > MAX_THEME_BYTES) then Exit;
      SetLength(AData, fs.Size);
      fs.ReadBuffer(AData[1], fs.Size);
      Result := True;
    finally
      fs.Free;
    end;
    if (Length(AData) >= 3) and (AData[1] = #$EF) and (AData[2] = #$BB) and
       (AData[3] = #$BF) then
      Delete(AData, 1, 3);
  except
    Result := False;
    AData := '';
  end;
end;

function ParseColorStr(const S: string; out C: TColor): Boolean;
var
  i, v: Integer;
begin
  Result := False;
  if (Length(S) <> 7) or (S[1] <> '#') then Exit;
  for i := 2 to 7 do
    if not (S[i] in ['0'..'9', 'a'..'f', 'A'..'F']) then Exit;
  v := StrToInt('$' + Copy(S, 2, 6));
  C := RGBToColor((v shr 16) and $FF, (v shr 8) and $FF, v and $FF);
  Result := True;
end;

// toutes les cles presentes et egales aux defauts du code
function ThemeIsDefaults(const AFileName: string): Boolean;
var
  data: string;
  root: TJSONData;
  obj: TJSONObject;
  jd: TJSONData;
  i: Integer;
  c: TColor;
begin
  Result := False;
  if not ReadCapped(AFileName, data) then Exit;
  root := nil;
  try
    try
      root := GetJSON(data);
    except
      Exit;
    end;
    if (root = nil) or (root.JSONType <> jtObject) then Exit;
    obj := TJSONObject(root);
    for i := 0 to High(Reg) do
    begin
      jd := obj.Find(Reg[i].Key);
      if (jd = nil) or (jd.JSONType <> jtString) then Exit;
      if not ParseColorStr(jd.AsString, c) then Exit;
      if c <> Reg[i].Def then Exit;
    end;
    Result := True;
  finally
    root.Free;
  end;
end;

function SanitizeName(const S, AFallback: string): string;
var
  i: Integer;
begin
  Result := '';
  for i := 1 to Length(S) do
    if S[i] >= ' ' then Result := Result + S[i];
  Result := Trim(Result);
  if Length(Result) > MAX_NAME_LEN then SetLength(Result, MAX_NAME_LEN);
  if Result = '' then Result := AFallback;
end;

function ThemeCount: Integer;
begin
  Result := Length(Themes);
end;

function ThemeName(AIndex: Integer): string;
begin
  if (AIndex >= 0) and (AIndex < Length(Themes)) then
    Result := Themes[AIndex].Display
  else
    Result := '';
end;

function CurrentTheme: Integer;
begin
  Result := FCurrent;
end;

// whitelist Monaspace: hors liste, on garde la valeur courante
procedure ApplyFontKey(AObj: TJSONObject; const AKey: string; var ADest: string);
var
  jd: TJSONData;
  full: string;
begin
  jd := AObj.Find(AKey);
  if (jd = nil) or (jd.JSONType <> jtString) then Exit;
  full := ResolveMonaspace(jd.AsString);
  if full <> '' then ADest := full;
end;

procedure ApplySizeKey(AObj: TJSONObject; const AKey: string; var ADest: Integer);
var
  jd: TJSONData;
  n: Integer;
begin
  jd := AObj.Find(AKey);
  if (jd = nil) or (jd.JSONType <> jtNumber) then Exit;
  n := jd.AsInteger;
  if (n >= 6) and (n <= 72) then ADest := n; // police geante = gel
end;

function ApplyTheme(AIndex: Integer): Boolean;
var
  data, s: string;
  root: TJSONData;
  obj: TJSONObject;
  jd: TJSONData;
  i: Integer;
  c: TColor;
  vals: array of TColor;
  selFg: TColor;
  edF, tbF, sdF: string;
  edS, tbS, sdS: Integer;
begin
  Result := False;
  if (AIndex < 0) or (AIndex >= Length(Themes)) then Exit;
  if not ReadCapped(Themes[AIndex].FileName, data) then Exit;
  root := nil;
  try
    // tout dans des LOCAUX: une exception ici ne doit laisser aucune globale
    // uTheme a moitie posee
    try
      root := GetJSON(data);
      if (root = nil) or (root.JSONType <> jtObject) then Exit;
      obj := TJSONObject(root);
      // repartir des defauts: une cle absente ne doit pas heriter du theme precedent
      SetLength(vals, Length(Reg));
      for i := 0 to High(Reg) do
      begin
        vals[i] := Reg[i].Def;
        jd := obj.Find(Reg[i].Key);
        if (jd <> nil) and (jd.JSONType = jtString) then
        begin
          s := jd.AsString;
          if ParseColorStr(s, c) then vals[i] := c;
        end;
      end;
      edF := RTFontName; edS := RT_EDITOR_SIZE_DEF;
      tbF := RTFontName; tbS := RT_TAB_SIZE_DEF;
      sdF := RTFontName; sdS := RT_SIDE_SIZE_DEF;
      ApplyFontKey(obj, 'editorFont', edF);
      ApplySizeKey(obj, 'editorFontSize', edS);
      ApplyFontKey(obj, 'tabFont', tbF);
      ApplySizeKey(obj, 'tabFontSize', tbS);
      ApplyFontKey(obj, 'sideFont', sdF);
      ApplySizeKey(obj, 'sideFontSize', sdS);
      // hors du Reg: son defaut n'est pas un #RRGGBB et il ne doit pas entrer
      // dans ThemeIsDefaults
      selFg := clWhite;
      jd := obj.Find('selectionFg');
      if (jd <> nil) and (jd.JSONType = jtString) and ParseColorStr(jd.AsString, c) then
        selFg := c;
    except
      Exit; // rien n'est commite
    end;
    // commit: plus rien ne peut echouer
    for i := 0 to High(Reg) do Reg[i].P^ := vals[i];
    clSelectionFg := selFg;
    RTEditorFont := edF; RTEditorSize := edS;
    RTTabFont := tbF;    RTTabSize := tbS;
    RTSideFont := sdF;   RTSideSize := sdS;
    FCurrent := AIndex;
    Result := True;
  finally
    root.Free;
  end;
end;

function ApplyThemeFile(const AFileName: string): Boolean;
var
  i: Integer;
begin
  Result := False;
  if AFileName = '' then Exit;
  for i := 0 to High(Themes) do
    if SameText(Themes[i].FileName, AFileName) then
      Exit(ApplyTheme(i));
end;

procedure ApplyDefaultTheme;
begin
  ApplyThemeFile(DEFAULT_THEME_FILE);
end;

function CurrentThemeFile: string;
begin
  if (FCurrent >= 0) and (FCurrent < Length(Themes)) then
    Result := Themes[FCurrent].FileName
  else
    Result := '';
end;

procedure ScanThemes;
var
  sr: TSearchRec;
  data, nm: string;
  root: TJSONData;
  i, j: Integer;
  tmp: TThemeFile;
begin
  SetLength(Themes, 0);
  if SysUtils.FindFirst(ThemesDir + '*.json', faAnyFile, sr) = 0 then
  begin
    repeat
      if (sr.Attr and faDirectory) <> 0 then Continue;
      if Length(Themes) >= MAX_THEMES then Break;
      nm := ChangeFileExt(sr.Name, '');
      // le "name" du JSON prime s'il est lisible
      if ReadCapped(sr.Name, data) then
      begin
        root := nil;
        try
          try
            root := GetJSON(data);
            if (root <> nil) and (root.JSONType = jtObject) then
              nm := SanitizeName(TJSONObject(root).Get('name', nm), nm);
          except
            ; // nom de fichier en repli
          end;
        finally
          root.Free;
        end;
        SetLength(Themes, Length(Themes) + 1);
        Themes[High(Themes)].FileName := sr.Name;
        Themes[High(Themes)].Display := nm;
      end;
    until SysUtils.FindNext(sr) <> 0;
    SysUtils.FindClose(sr);
  end;
  for i := 0 to High(Themes) - 1 do
    for j := i + 1 to High(Themes) do
      if CompareText(Themes[j].Display, Themes[i].Display) < 0 then
      begin
        tmp := Themes[i];
        Themes[i] := Themes[j];
        Themes[j] := tmp;
      end;
  // theme coche au depart: celui qui vaut les defauts du code, pas celui qui
  // porte le bon nom
  for i := 0 to High(Themes) do
    if ThemeIsDefaults(Themes[i].FileName) then
    begin
      FCurrent := i;
      Break;
    end;
end;

initialization
  // l'initialization d'uTheme a deja tourne: les vars portent les defauts
  R('editorBg', clEditorBg);
  R('editorFg', clEditorFg);
  R('currentLine', clCurrentLine);
  R('selectionBg', clSelectionBg);
  R('selectionInactive', clSelectionInactive);
  R('caret', clCaret);
  R('gutterBg', clGutterBg);
  R('gutterFg', clGutterFg);
  R('gutterFgCur', clGutterFgCur);
  R('gutterCurBg', clGutterCurBg);
  R('rightEdge', clRightEdge);
  R('tabStrip', clTabStrip);
  R('tabActive', clTabActive);
  R('tabInactive', clTabInactive);
  R('tabHover', clTabHover);
  R('tabActiveText', clTabActiveText);
  R('tabInactiveText', clTabInactiveText);
  R('tabActiveDim', clTabActiveDim);
  R('tabActiveTextDim', clTabActiveTextDim);
  R('modifiedDot', clModifiedDot);
  R('tabIcon', clTabIcon);
  R('tabIconHi', clTabIconHi);
  R('tabGlyph', clTabGlyph);
  R('macroRec', clMacroRec);
  R('tabLock', clTabLock);
  R('tabLockMod', clTabLockMod);
  R('menuBg', clMenuBg);
  R('menuText', clMenuText);
  R('menuHover', clMenuHover);
  R('menuPopupBg', clMenuPopupBg);
  R('menuDisabled', clMenuDisabled);
  R('statusBg', clStatusBg);
  R('statusText', clStatusText);
  R('minimapViewport', clMinimapViewport);
  R('border', clBorder);
  R('findOutline', clFindOutline);
  R('findBtn', clFindBtn);
  R('findBtnText', clFindBtnText);
  R('findToggleOn', clFindToggleOn);
  R('findToggleOnText', clFindToggleOnText);
  R('findToggleOff', clFindToggleOff);
  R('findToggleOffText', clFindToggleOffText);
  R('sideBg', clSideBg);
  R('sideHeader', clSideHeader);
  R('sideText', clSideText);
  R('sideTextHi', clSideTextHi);
  R('sideHover', clSideHover);
  R('sideSel', clSideSel);
  R('codeComment', clCodeComment);
  R('codeString', clCodeString);
  R('codeNumber', clCodeNumber);
  R('codeConstant', clCodeConstant);
  R('codeKeyword', clCodeKeyword);
  R('codeType', clCodeType);
  R('codeFunction', clCodeFunction);
  R('codeOperator', clCodeOperator);
  R('codeVariable', clCodeVariable);
  R('codeInvalid', clCodeInvalid);
  ScanThemes;

end.
