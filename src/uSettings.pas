unit uSettings;

{$mode objfpc}{$H+}

// Reglages persistes (settings.json, ecriture atomique). Fichier semi-fiable:
// plafond de taille, valeurs bornees, casse = defauts.

interface

procedure SettingsLoad; // apres LoadEmbeddedFonts, avant CreateForm
procedure SettingsSave;

var
  SetWinValid: Boolean = False;
  SetWinX: Integer = 0;
  SetWinY: Integer = 0;
  SetWinW: Integer = 0;
  SetWinH: Integer = 0;
  SetWinMax: Boolean = False;
  SetSideBarVisible: Boolean = False;

implementation

uses
  Classes, SysUtils, fpjson, jsonparser, uSafeSave, uThemeLoad, uEditorView;

const
  MAX_SETTINGS_BYTES = 64 * 1024;

function SettingsFile: string;
begin
  Result := IncludeTrailingPathDelimiter(GetAppConfigDir(False)) + 'settings.json';
end;

function JInt(AObj: TJSONObject; const AKey: string; ADef: Integer): Integer;
var
  jd: TJSONData;
begin
  Result := ADef;
  jd := AObj.Find(AKey);
  if (jd <> nil) and (jd.JSONType = jtNumber) then
    try
      Result := jd.AsInteger;
    except
      Result := ADef;
    end;
end;

function JBool(AObj: TJSONObject; const AKey: string; ADef: Boolean): Boolean;
var
  jd: TJSONData;
begin
  Result := ADef;
  jd := AObj.Find(AKey);
  if (jd <> nil) and (jd.JSONType = jtBoolean) then
    Result := jd.AsBoolean;
end;

function JStr(AObj: TJSONObject; const AKey: string): string;
var
  jd: TJSONData;
begin
  Result := '';
  jd := AObj.Find(AKey);
  if (jd <> nil) and (jd.JSONType = jtString) then
    Result := jd.AsString;
end;

function ClampI(V, AMin, AMax: Integer): Integer;
begin
  Result := V;
  if Result < AMin then Result := AMin;
  if Result > AMax then Result := AMax;
end;

// GetJSON refuse un BOM UTF-8 (fichier edite a la main sous Windows)
procedure StripBom(var S: string);
begin
  if (Length(S) >= 3) and (S[1] = #$EF) and (S[2] = #$BB) and (S[3] = #$BF) then
    Delete(S, 1, 3);
end;

procedure SettingsLoad;
var
  fs: TFileStream;
  data: string;
  root: TJSONData;
  obj: TJSONObject;
  themed: Boolean;
begin
  // rattrapage des configs nees avant le durcissement (0644/0755); tourne a
  // chaque lancement, couvre aussi les fenetres hors session
  MakePrivateDir(GetAppConfigDir(False));
  MakePrivateFile(SettingsFile);
  themed := False;
  root := nil;
  try
    try
      fs := TFileStream.Create(SettingsFile, fmOpenRead or fmShareDenyNone);
      try
        if (fs.Size > 0) and (fs.Size <= MAX_SETTINGS_BYTES) then
        begin
          SetLength(data, fs.Size);
          fs.ReadBuffer(data[1], fs.Size);
        end;
      finally
        fs.Free;
      end;
      StripBom(data);
      if data <> '' then
      begin
        root := GetJSON(data);
        if (root <> nil) and (root.JSONType = jtObject) then
        begin
          obj := TJSONObject(root);
          themed := ApplyThemeFile(ExtractFileName(JStr(obj, 'theme')));
          RTTabWidth := ClampI(JInt(obj, 'tabWidth', RTTabWidth), 1, 16);
          RTWordWrap := JBool(obj, 'wordWrap', RTWordWrap);
          RTWrapColumn := ClampI(JInt(obj, 'wrapColumn', RTWrapColumn), 0, 1000);
          RTShowInvisibles := JBool(obj, 'showInvisibles', RTShowInvisibles);
          RTMapTabToSpace := JBool(obj, 'mapTabToSpace', RTMapTabToSpace);
          SetSideBarVisible := JBool(obj, 'sideBar', False);
          SetWinMax := JBool(obj, 'winMax', False);
          SetWinX := JInt(obj, 'winX', 0);
          SetWinY := JInt(obj, 'winY', 0);
          SetWinW := ClampI(JInt(obj, 'winW', 0), 0, 20000);
          SetWinH := ClampI(JInt(obj, 'winH', 0), 0, 20000);
          SetWinValid := (SetWinW >= 400) and (SetWinH >= 300);
        end;
      end;
    except
      ; // fichier absent/corrompu: defauts
    end;
  finally
    root.Free;
  end;
  if not themed then
    ApplyDefaultTheme;
end;

procedure SettingsSave;
var
  obj: TJSONObject;
  st: TStream;
  tmp, data, tf: string;
begin
  tmp := '';
  try
    obj := TJSONObject.Create;
    try
      tf := CurrentThemeFile;
      if tf <> '' then
        obj.Add('theme', tf);
      obj.Add('tabWidth', RTTabWidth);
      obj.Add('wordWrap', RTWordWrap);
      obj.Add('wrapColumn', RTWrapColumn);
      obj.Add('showInvisibles', RTShowInvisibles);
      obj.Add('mapTabToSpace', RTMapTabToSpace);
      obj.Add('sideBar', SetSideBarVisible);
      if SetWinValid then
      begin
        obj.Add('winX', SetWinX);
        obj.Add('winY', SetWinY);
        obj.Add('winW', SetWinW);
        obj.Add('winH', SetWinH);
        obj.Add('winMax', SetWinMax);
      end;
      data := obj.FormatJSON;
    finally
      obj.Free;
    end;
    ForceDirectories(GetAppConfigDir(False));
    MakePrivateDir(GetAppConfigDir(False));
    st := CreateTempIn(SettingsFile, tmp);
    try
      if data <> '' then
        st.WriteBuffer(data[1], Length(data));
    finally
      st.Free;
    end;
    if not ReplaceByRenamePrivate(tmp, SettingsFile) then
      DeleteFile(tmp);
  except
    // best effort, mais pas de temp laisse trainer sur exception
    if tmp <> '' then DeleteFile(tmp);
  end;
end;

end.
