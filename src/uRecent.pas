unit uRecent;

{$mode objfpc}{$H+}

// MRU (File > Open Recent), recent.json en ecriture atomique. Une fenetre = un
// process: le fichier est relu avant chaque ajout et a chaque popup du menu
// (fusion inter-fenetres, dernier ecrivain gagne). Best effort de bout en bout.

interface

uses
  Classes, SysUtils;

const
  MAX_RECENT = 15;

var
  // restaurer une session ne doit pas reordonner la MRU
  RecentSuspended: Boolean = False;

procedure RecentReload;
procedure RecentAdd(const APath: string);
procedure RecentClear;
function RecentCount: Integer;
function RecentPath(AIndex: Integer): string;    // chemin BRUT (pour ouvrir)
function RecentDisplay(AIndex: Integer): string; // assaini (libelle de menu)

implementation

uses
  fpjson, jsonparser, uSafeSave;

const
  MAX_FILE_BYTES = 64 * 1024;
  MAX_ENTRY_LEN  = 4096; // chemin plus long = entree ignoree

var
  FList: TStringList;

// un chemin POSIX peut contenir des controles: pas de caption multi-lignes
function SanitizeEntry(const S: string): string;
var
  i: Integer;
begin
  Result := '';
  for i := 1 to Length(S) do
  begin
    if S[i] >= ' ' then
      Result := Result + S[i]
    else
      Result := Result + ' ';
    if Length(Result) >= 200 then Break;
  end;
  Result := Trim(Result);
end;

function RecentFileJson: string;
begin
  Result := IncludeTrailingPathDelimiter(GetAppConfigDir(False)) + 'recent.json';
end;

function RecentFileLegacy: string;
begin
  Result := IncludeTrailingPathDelimiter(GetAppConfigDir(False)) + 'recent.txt';
end;

function ReadWhole(const AFile: string; out AData: string): Boolean;
var
  fs: TFileStream;
begin
  Result := False;
  AData := '';
  fs := TFileStream.Create(AFile, fmOpenRead or fmShareDenyNone);
  try
    if (fs.Size <= 0) or (fs.Size > MAX_FILE_BYTES) then Exit;
    SetLength(AData, fs.Size);
    fs.ReadBuffer(AData[1], fs.Size);
    Result := True;
  finally
    fs.Free;
  end;
end;

function EntryOK(const S: string): Boolean;
begin
  Result := (S <> '') and (Length(S) <= MAX_ENTRY_LEN) and
    (SanitizeEntry(S) <> ''); // que des controles/espaces = dechet
end;

procedure LoadLegacy;
var
  data, entry: string;
  sl: TStringList;
  i: Integer;
begin
  if not ReadWhole(RecentFileLegacy, data) then Exit;
  sl := TStringList.Create;
  try
    sl.Text := data;
    for i := 0 to sl.Count - 1 do
    begin
      entry := Trim(sl[i]);
      if not EntryOK(entry) then Continue;
      FList.Add(entry);
      if FList.Count >= MAX_RECENT then Break;
    end;
  finally
    sl.Free;
  end;
end;

procedure RecentReload;
var
  data: string;
  root: TJSONData;
  arr: TJSONArray;
  i: Integer;
  entry: string;
begin
  FList.Clear;
  MakePrivateFile(RecentFileJson); // rattrapage d'avant le durcissement
  root := nil;
  try
    try
      if not FileExists(RecentFileJson) then
      begin
        // migration depuis l'ancien recent.txt (ligne par ligne)
        if FileExists(RecentFileLegacy) then LoadLegacy;
        Exit;
      end;
      if not ReadWhole(RecentFileJson, data) then Exit;
      // GetJSON refuse un BOM UTF-8
      if (Length(data) >= 3) and (data[1] = #$EF) and (data[2] = #$BB) and
         (data[3] = #$BF) then
        Delete(data, 1, 3);
      root := GetJSON(data);
      if (root = nil) or (root.JSONType <> jtArray) then Exit;
      arr := TJSONArray(root);
      for i := 0 to arr.Count - 1 do
      begin
        if arr[i].JSONType <> jtString then Continue;
        entry := arr[i].AsString;
        if not EntryOK(entry) then Continue;
        FList.Add(entry);
        if FList.Count >= MAX_RECENT then Break;
      end;
    except
      FList.Clear; // fichier corrompu/verrouille: liste vide, pas d'erreur
    end;
  finally
    // sans le finally, un Exit (JSON non-tableau) fuit l'arbre a chaque popup
    root.Free;
  end;
end;

procedure SaveList;
var
  st: TStream;
  tmp, data: string;
  arr: TJSONArray;
  i: Integer;
begin
  tmp := '';
  try
    ForceDirectories(GetAppConfigDir(False));
    MakePrivateDir(GetAppConfigDir(False));
    arr := TJSONArray.Create;
    try
      for i := 0 to FList.Count - 1 do
        arr.Add(FList[i]);
      data := arr.FormatJSON;
    finally
      arr.Free;
    end;
    st := CreateTempIn(RecentFileJson, tmp);
    try
      if data <> '' then
        st.WriteBuffer(data[1], Length(data));
    finally
      st.Free;
    end;
    if not ReplaceByRenamePrivate(tmp, RecentFileJson) then
      DeleteFile(tmp);
  except
    // best effort, mais pas de temp laisse trainer sur exception
    if tmp <> '' then DeleteFile(tmp);
  end;
end;

procedure RecentAdd(const APath: string);
var
  full: string;
  i: Integer;
begin
  if RecentSuspended then Exit;
  if APath = '' then Exit;
  full := ExpandFileName(APath);
  if not EntryOK(full) then Exit;
  RecentReload; // fusion avec ce que les autres fenetres ont ecrit
  for i := FList.Count - 1 downto 0 do
    if SameFileName(FList[i], full) then
      FList.Delete(i);
  FList.Insert(0, full);
  while FList.Count > MAX_RECENT do
    FList.Delete(FList.Count - 1);
  SaveList;
end;

procedure RecentClear;
begin
  FList.Clear;
  SaveList;
end;

function RecentCount: Integer;
begin
  Result := FList.Count;
end;

function RecentPath(AIndex: Integer): string;
begin
  if (AIndex >= 0) and (AIndex < FList.Count) then
    Result := FList[AIndex]
  else
    Result := '';
end;

function RecentDisplay(AIndex: Integer): string;
begin
  Result := SanitizeEntry(RecentPath(AIndex));
end;

initialization
  FList := TStringList.Create;
  RecentReload;

finalization
  FList.Free;

end.
