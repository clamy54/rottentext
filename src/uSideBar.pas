unit uSideBar;

{$mode objfpc}{$H+}

// Section OPEN FILES (alimentee par uMain) puis arborescence de fichiers.
// Lecture d'un dossier paresseuse, watch disque sous Windows seulement.

interface

uses
  Classes, SysUtils, Controls, Graphics, LCLType, ExtCtrls, Forms, uTheme;

type
  TOpenFileEvent = procedure(const AFileName: string) of object;
  TSideFileEvent = procedure(AIndex: Integer) of object;

  TSideOpenFile = record
    Name: string;
    Modified: Boolean;
    ReadOnly: Boolean;
    Active: Boolean;
  end;

  TSideNode = class
  public
    Name: string;
    Path: string;
    IsDir: Boolean;
    Expanded: Boolean;
    Loaded: Boolean;
    Depth: Integer;
    Children: TFPList; // of TSideNode
    constructor Create;
    destructor Destroy; override;
    procedure ClearChildren;
  end;

  // listing en cache, valide par le mtime du dossier: seul un dossier qui a
  // change se relit, les autres coutent un stat. Noms deja tries.
  TDirListing = class
  public
    Stamp: Int64; // mtime FILETIME du dossier a la lecture
    Names: array of string;
    Dirs: array of Boolean;
  end;

  TSideRowKind = (srkOpenHdr, srkOpenFile, srkFolderHdr, srkNode);
  TSideRow = record
    Kind: TSideRowKind;
    Idx: Integer;    // srkOpenFile: index dans FOpenFiles
    Node: TSideNode; // srkNode
  end;

  TSideBar = class(TCustomControl)
  private
    FRoot: TSideNode;
    FFlat: TFPList;
    FRows: array of TSideRow;
    FOpenFiles: array of TSideOpenFile;
    FScroll: Integer;
    FHot: Integer;
    FSel: TSideNode;     // selection suivie par NOEUD: les index de FFlat glissent
    FSizing: Boolean;
    FSBDragging: Boolean;
    FSBDragOffset: Integer;
    FOnOpenFile: TOpenFileEvent;
    FOnActivateFile: TSideFileEvent;
    FOnCloseFile: TSideFileEvent;
    FWatch: THandle;
    FWatchTimer: TTimer;
    FWatchDirty: Boolean;
    FRefreshing: Boolean;
    FWatchCooldown: Integer;
    FDirCache: TStringList; // chemin -> TDirListing
    FCacheOK: Boolean;      // volume NTFS/ReFS: mtime de dossier fiable
    procedure CacheClear;
    procedure LoadChildren(ANode: TSideNode);
    procedure RebuildFlat;
    procedure RebuildRows;
    procedure AppendVisible(ANode: TSideNode);
    function RowAt(Y: Integer): Integer;
    function RowsFit: Integer;
    procedure ClampScroll;
    function NeedScrollbar: Boolean;
    function ThumbRect: TRect;
    procedure ScrollToThumb(AThumbTop: Integer);
    function OpenIconRect(ATop: Integer): TRect;
    procedure DrawRow(ARowIdx, ATop: Integer);
    procedure DrawHeader(const ACaption: string; ATop: Integer);
    procedure DrawOpenFile(ARowIdx, AFileIdx, ATop: Integer);
    procedure DrawNode(ARowIdx, ATop: Integer; ANode: TSideNode);
    procedure DrawXGlyph(const R: TRect; C: TColor);
    procedure DrawDotGlyph(const R: TRect; C: TColor);
    procedure DrawLockGlyph(const R: TRect; C: TColor);
    procedure DrawFolderIcon(AX, ACy: Integer; C: TColor);
    procedure DrawFileIcon(AX, ACy: Integer; C: TColor);
    procedure RefreshTree;
    procedure CollectExpandedPaths(ANode: TSideNode; AList: TStringList);
    procedure ReExpand(ANode: TSideNode; AList: TStringList);
    function FindNodeByPath(ANode: TSideNode; const APath: string): TSideNode;
    procedure StartWatch(const APath: string);
    procedure StopWatch;
    procedure WatchTick(Sender: TObject);
  protected
    procedure Paint; override;
    procedure Resize; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseLeave; override;
    function DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure SetRoot(const APath: string);
    procedure RefreshTheme;
    function RootPath: string;
    // ne deplie rien: un fichier sous un dossier plie n'est pas surligne
    procedure SelectPath(const APath: string);
    procedure SetOpenFiles(const AFiles: array of TSideOpenFile);
    property OnOpenFile: TOpenFileEvent read FOnOpenFile write FOnOpenFile;
    property OnActivateFile: TSideFileEvent read FOnActivateFile write FOnActivateFile;
    property OnCloseFile: TSideFileEvent read FOnCloseFile write FOnCloseFile;
  end;

implementation

const
  ROW_H    = 22;
  INDENT   = 14;
  PADX     = 12;
  TRI_W    = 12;
  NODE_ICON_W = 15;
  ICON_SZ  = 16;
  GRIP_W   = 5;  // bord droit saisissable
  SBW      = 6;
  MIN_W    = 140;
  MAX_W    = 600;
  WATCH_MS = 800;
  WATCH_COOLDOWN = 3; // ticks mini entre deux refresh sous churn continu

{$IFDEF WINDOWS}
// declares a la main: l'unite Windows entre en conflit avec TRect/Rect de la LCL
const
  FILE_NOTIFY_CHANGE_FILE_NAME = $00000001;
  FILE_NOTIFY_CHANGE_DIR_NAME  = $00000002;
  WAIT_OBJECT_0 = 0;

function FindFirstChangeNotificationW(lpPathName: PWideChar;
  bWatchSubtree: LongBool; dwNotifyFilter: DWord): THandle; stdcall;
  external 'kernel32' name 'FindFirstChangeNotificationW';
function FindNextChangeNotification(hChangeHandle: THandle): LongBool; stdcall;
  external 'kernel32' name 'FindNextChangeNotification';
function FindCloseChangeNotification(hChangeHandle: THandle): LongBool; stdcall;
  external 'kernel32' name 'FindCloseChangeNotification';
function WaitForSingleObject(hHandle: THandle; dwMilliseconds: DWord): DWord; stdcall;
  external 'kernel32' name 'WaitForSingleObject';

type
  TSBFileTime = record
    dwLow, dwHigh: DWord;
  end;
  TSBFileAttrData = record
    dwFileAttributes: DWord;
    ftCreationTime, ftLastAccessTime, ftLastWriteTime: TSBFileTime;
    nFileSizeHigh, nFileSizeLow: DWord;
  end;

function GetFileAttributesExW(lpFileName: PWideChar; fInfoLevelId: Integer;
  lpFileInformation: Pointer): LongBool; stdcall;
  external 'kernel32' name 'GetFileAttributesExW';
function GetVolumeInformationW(lpRootPathName, lpVolumeNameBuffer: PWideChar;
  nVolumeNameSize: DWord; lpVolumeSerialNumber, lpMaximumComponentLength,
  lpFileSystemFlags: PDWord; lpFileSystemNameBuffer: PWideChar;
  nFileSystemNameSize: DWord): LongBool; stdcall;
  external 'kernel32' name 'GetVolumeInformationW';

function DirStamp(const APath: string): Int64;
var
  fad: TSBFileAttrData;
  w: WideString;
begin
  Result := 0;
  w := UTF8Decode(APath);
  if not GetFileAttributesExW(PWideChar(w), 0, @fad) then Exit;
  Result := (Int64(fad.ftLastWriteTime.dwHigh) shl 32)
            or Int64(fad.ftLastWriteTime.dwLow);
  if Result = 0 then Result := 1; // 0 reste la sentinelle "pas de stamp"
end;

// NTFS/ReFS mettent a jour le mtime d'un dossier quand un enfant direct bouge,
// pas FAT; UNC: semantique du serveur inconnue, donc pas de cache
function VolumeSupportsCache(const APath: string): Boolean;
var
  w: WideString;
  fs: array[0..63] of WideChar;
begin
  Result := False;
  if (Length(APath) < 2) or (APath[2] <> ':') then Exit;
  w := UTF8Decode(Copy(APath, 1, 2)) + '\';
  FillChar(fs{%H-}, SizeOf(fs), 0);
  if not GetVolumeInformationW(PWideChar(w), nil, 0, nil, nil, nil,
    @fs[0], Length(fs)) then Exit;
  Result := (WideString(PWideChar(@fs[0])) = 'NTFS') or
            (WideString(PWideChar(@fs[0])) = 'ReFS');
end;
{$ENDIF}

constructor TSideNode.Create;
begin
  Children := TFPList.Create;
end;

destructor TSideNode.Destroy;
begin
  ClearChildren;
  Children.Free;
  inherited Destroy;
end;

procedure TSideNode.ClearChildren;
var
  i: Integer;
begin
  for i := 0 to Children.Count - 1 do
    TSideNode(Children[i]).Free;
  Children.Clear;
  Loaded := False;
end;

constructor TSideBar.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FFlat := TFPList.Create;
  FHot := -1;
  FSel := nil;
  FWatch := 0;
  FDirCache := TStringList.Create;
  FDirCache.Sorted := True;
  FDirCache.Duplicates := dupIgnore;
  FDirCache.CaseSensitive := False;
  Font.Name := RTSideFont;
  Font.Size := RTSideSize;
  Font.Quality := fqCleartype;
end;

procedure TSideBar.RefreshTheme;
begin
  Font.Name := RTSideFont;
  Font.Size := RTSideSize;
  Invalidate;
end;

destructor TSideBar.Destroy;
begin
  StopWatch;
  CacheClear;
  FDirCache.Free;
  FRoot.Free;
  FFlat.Free;
  inherited Destroy;
end;

procedure TSideBar.SetRoot(const APath: string);
begin
  FSel := nil; // les noeuds vont etre liberes
  FreeAndNil(FRoot);
  FScroll := 0;
  FHot := -1;
  CacheClear;
  {$IFDEF WINDOWS}
  FCacheOK := VolumeSupportsCache(APath);
  {$ELSE}
  FCacheOK := False;
  {$ENDIF}
  FRoot := TSideNode.Create;
  FRoot.Name := ExtractFileName(ExcludeTrailingPathDelimiter(APath));
  if FRoot.Name = '' then // racine de lecteur (D:\)
    FRoot.Name := ExcludeTrailingPathDelimiter(APath);
  FRoot.Path := ExcludeTrailingPathDelimiter(APath);
  FRoot.IsDir := True;
  FRoot.Expanded := True;
  RebuildRows;
  Invalidate;
  StartWatch(FRoot.Path);
end;

function TSideBar.RootPath: string;
begin
  if FRoot = nil then
    Result := ''
  else
    Result := FRoot.Path;
end;

function SameOpenFiles(const A, B: array of TSideOpenFile): Boolean;
var
  i: Integer;
begin
  if Length(A) <> Length(B) then Exit(False);
  for i := 0 to High(A) do
    if (A[i].Name <> B[i].Name) or (A[i].Modified <> B[i].Modified) or
       (A[i].ReadOnly <> B[i].ReadOnly) or (A[i].Active <> B[i].Active) then
      Exit(False);
  Result := True;
end;

procedure TSideBar.SetOpenFiles(const AFiles: array of TSideOpenFile);
var
  i: Integer;
begin
  if SameOpenFiles(FOpenFiles, AFiles) then Exit;
  SetLength(FOpenFiles, Length(AFiles));
  for i := 0 to High(AFiles) do
    FOpenFiles[i] := AFiles[i];
  RebuildRows;
  Invalidate;
end;

procedure TSideBar.SelectPath(const APath: string);
var
  i, row: Integer;
  found: TSideNode;
begin
  if FRoot = nil then Exit;
  found := nil;
  row := -1;
  if APath <> '' then
    for i := 0 to High(FRows) do
      if (FRows[i].Kind = srkNode) and not FRows[i].Node.IsDir and
         SameFileName(FRows[i].Node.Path, APath) then
      begin
        found := FRows[i].Node;
        row := i;
        Break;
      end;
  if found = FSel then Exit;
  FSel := found;
  if row >= 0 then
  begin
    if row < FScroll then
      FScroll := row
    else if row >= FScroll + RowsFit then
      FScroll := row - RowsFit + 1;
    ClampScroll;
  end;
  Invalidate;
end;

function CompareNames(List: TStringList; Index1, Index2: Integer): Integer;
begin
  Result := AnsiCompareText(List[Index1], List[Index2]);
end;

procedure TSideBar.CacheClear;
var
  i: Integer;
begin
  if FDirCache = nil then Exit;
  for i := 0 to FDirCache.Count - 1 do
    FDirCache.Objects[i].Free;
  FDirCache.Clear;
end;

procedure TSideBar.LoadChildren(ANode: TSideNode);
var
  sr: TSearchRec;
  dirs, files: TStringList;
  i: Integer;
  n: TSideNode;
  stamp: Int64;
  ci: Integer;
  lst: TDirListing;

  procedure AddNode(const AName: string; ADir: Boolean);
  begin
    n := TSideNode.Create;
    n.Name := AName;
    n.Path := ANode.Path + PathDelim + AName;
    n.IsDir := ADir;
    n.Depth := ANode.Depth + 1;
    ANode.Children.Add(n);
  end;

begin
  ANode.ClearChildren;
  ANode.Loaded := True;
  // stamp lu AVANT le listing: un changement pendant la lecture le rend perime,
  // le prochain refresh relira (jamais l'inverse)
  stamp := 0;
  {$IFDEF WINDOWS}
  if FCacheOK then
  begin
    stamp := DirStamp(ANode.Path);
    if (stamp <> 0) and FDirCache.Find(ANode.Path, ci) then
    begin
      lst := TDirListing(FDirCache.Objects[ci]);
      if lst.Stamp = stamp then
      begin
        for i := 0 to High(lst.Names) do
          AddNode(lst.Names[i], lst.Dirs[i]);
        Exit;
      end;
    end;
  end;
  {$ENDIF}
  dirs := TStringList.Create;
  files := TStringList.Create;
  try
    if SysUtils.FindFirst(ANode.Path + PathDelim + '*', faAnyFile, sr) = 0 then
    begin
      repeat
        if (sr.Name = '.') or (sr.Name = '..') then Continue;
        if (sr.Attr and faDirectory) <> 0 then
          dirs.Add(sr.Name)
        else
          files.Add(sr.Name);
      until FindNext(sr) <> 0;
      SysUtils.FindClose(sr);
    end;
    dirs.CustomSort(@CompareNames);
    files.CustomSort(@CompareNames);
    for i := 0 to dirs.Count - 1 do
      AddNode(dirs[i], True);
    for i := 0 to files.Count - 1 do
      AddNode(files[i], False);
    {$IFDEF WINDOWS}
    if stamp <> 0 then
    begin
      if FDirCache.Count > 2048 then CacheClear; // garde-fou memoire
      if FDirCache.Find(ANode.Path, ci) then
        lst := TDirListing(FDirCache.Objects[ci])
      else
      begin
        lst := TDirListing.Create;
        FDirCache.AddObject(ANode.Path, lst);
      end;
      lst.Stamp := stamp;
      SetLength(lst.Names, ANode.Children.Count);
      SetLength(lst.Dirs, ANode.Children.Count);
      for i := 0 to ANode.Children.Count - 1 do
      begin
        lst.Names[i] := TSideNode(ANode.Children[i]).Name;
        lst.Dirs[i] := TSideNode(ANode.Children[i]).IsDir;
      end;
    end;
    {$ENDIF}
  finally
    dirs.Free;
    files.Free;
  end;
end;

procedure TSideBar.AppendVisible(ANode: TSideNode);
var
  i: Integer;
begin
  FFlat.Add(ANode);
  if ANode.IsDir and ANode.Expanded then
  begin
    if not ANode.Loaded then
      LoadChildren(ANode);
    for i := 0 to ANode.Children.Count - 1 do
      AppendVisible(TSideNode(ANode.Children[i]));
  end;
end;

procedure TSideBar.RebuildFlat;
begin
  FFlat.Clear;
  if FRoot <> nil then
    AppendVisible(FRoot);
end;

procedure TSideBar.RebuildRows;

  procedure Add(AKind: TSideRowKind; AIdx: Integer; ANode: TSideNode);
  begin
    SetLength(FRows, Length(FRows) + 1);
    FRows[High(FRows)].Kind := AKind;
    FRows[High(FRows)].Idx := AIdx;
    FRows[High(FRows)].Node := ANode;
  end;

var
  i: Integer;
begin
  SetLength(FRows, 0);
  if Length(FOpenFiles) > 0 then
  begin
    Add(srkOpenHdr, -1, nil);
    for i := 0 to High(FOpenFiles) do
      Add(srkOpenFile, i, nil);
  end;
  if FRoot <> nil then
  begin
    Add(srkFolderHdr, -1, nil);
    RebuildFlat;
    for i := 0 to FFlat.Count - 1 do
      Add(srkNode, -1, TSideNode(FFlat[i]));
  end;
  ClampScroll;
end;

function TSideBar.RowsFit: Integer;
begin
  Result := ClientHeight div ROW_H;
  if Result < 1 then Result := 1;
end;

procedure TSideBar.ClampScroll;
begin
  if FScroll > Length(FRows) - RowsFit then
    FScroll := Length(FRows) - RowsFit;
  if FScroll < 0 then
    FScroll := 0;
end;

function TSideBar.RowAt(Y: Integer): Integer;
begin
  Result := -1;
  if Y < 0 then Exit;
  Result := FScroll + Y div ROW_H;
  if (Result < 0) or (Result >= Length(FRows)) then
    Result := -1;
end;

function TSideBar.NeedScrollbar: Boolean;
begin
  Result := Length(FRows) > RowsFit;
end;

function TSideBar.ThumbRect: TRect;
var
  total, vis, h, thumbH, thumbTop, maxScroll: Integer;
begin
  Result := Rect(0, 0, 0, 0);
  total := Length(FRows);
  vis := RowsFit;
  h := ClientHeight;
  if (total <= vis) or (h <= 0) then Exit;
  thumbH := Round(vis / total * h);
  if thumbH < 24 then thumbH := 24;
  maxScroll := total - vis;
  if maxScroll <= 0 then Exit;
  thumbTop := Round(FScroll / maxScroll * (h - thumbH));
  if thumbTop + thumbH > h then thumbTop := h - thumbH;
  if thumbTop < 0 then thumbTop := 0;
  Result := Rect(ClientWidth - GRIP_W - SBW, thumbTop, ClientWidth - GRIP_W, thumbTop + thumbH);
end;

procedure TSideBar.ScrollToThumb(AThumbTop: Integer);
var
  total, vis, h, thumbH: Integer;
  frac: Double;
begin
  total := Length(FRows);
  vis := RowsFit;
  h := ClientHeight;
  if total <= vis then Exit;
  thumbH := Round(vis / total * h);
  if thumbH < 24 then thumbH := 24;
  if h - thumbH <= 0 then Exit;
  frac := AThumbTop / (h - thumbH);
  if frac < 0 then frac := 0;
  if frac > 1 then frac := 1;
  FScroll := Round(frac * (total - vis));
  ClampScroll;
  Invalidate;
end;

// icone a GAUCHE du nom; seul le Right sert au hit test
function TSideBar.OpenIconRect(ATop: Integer): TRect;
var
  t: Integer;
begin
  t := ATop + (ROW_H - ICON_SZ) div 2;
  Result := Rect(PADX, t, PADX + ICON_SZ, t + ICON_SZ);
end;

procedure TSideBar.DrawXGlyph(const R: TRect; C: TColor);
var
  m: Integer;
begin
  Canvas.Pen.Color := C;
  Canvas.Pen.Width := 1;
  m := 4;
  Canvas.Line(R.Left + m, R.Top + m, R.Right - m, R.Bottom - m);
  Canvas.Line(R.Right - m, R.Top + m, R.Left + m, R.Bottom - m);
end;

procedure TSideBar.DrawDotGlyph(const R: TRect; C: TColor);
var
  cx, cy, d: Integer;
begin
  d := 8;
  cx := (R.Left + R.Right) div 2;
  cy := (R.Top + R.Bottom) div 2;
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := C;
  Canvas.Pen.Color := C;
  Canvas.Ellipse(cx - d div 2, cy - d div 2, cx + d div 2, cy + d div 2);
  Canvas.Brush.Style := bsClear;
end;

procedure TSideBar.DrawLockGlyph(const R: TRect; C: TColor);
var
  cx, cy: Integer;
begin
  cx := (R.Left + R.Right) div 2;
  cy := (R.Top + R.Bottom) div 2;
  Canvas.Pen.Color := C;
  Canvas.Brush.Style := bsClear;
  Canvas.Arc(cx - 3, cy - 6, cx + 3, cy + 1, 0, 180 * 16);
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := C;
  Canvas.FillRect(cx - 5, cy - 2, cx + 5, cy + 6);
  Canvas.Brush.Style := bsClear;
end;

procedure TSideBar.DrawFolderIcon(AX, ACy: Integer; C: TColor);
begin
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := C;
  Canvas.Pen.Color := C;
  Canvas.FillRect(AX, ACy - 5, AX + 5, ACy - 3);
  Canvas.FillRect(AX, ACy - 3, AX + 11, ACy + 4);
  Canvas.Brush.Style := bsClear;
end;

procedure TSideBar.DrawFileIcon(AX, ACy: Integer; C: TColor);
begin
  Canvas.Pen.Color := C;
  Canvas.Brush.Style := bsClear;
  Canvas.Polygon([
    Point(AX + 1, ACy - 5), Point(AX + 6, ACy - 5), Point(AX + 9, ACy - 2),
    Point(AX + 9, ACy + 5), Point(AX + 1, ACy + 5)]);
  Canvas.Line(AX + 6, ACy - 5, AX + 6, ACy - 2);
  Canvas.Line(AX + 6, ACy - 2, AX + 9, ACy - 2);
end;

procedure TSideBar.DrawHeader(const ACaption: string; ATop: Integer);
begin
  Canvas.Brush.Style := bsClear;
  Canvas.Font.Color := clSideHeader;
  Canvas.TextOut(PADX, ATop + (ROW_H - Canvas.TextHeight('Ag')) div 2, ACaption);
end;

procedure TSideBar.DrawOpenFile(ARowIdx, AFileIdx, ATop: Integer);
var
  f: TSideOpenFile;
  r, iconR: TRect;
  active, hovered: Boolean;
  tx, ty, clipR, availW: Integer;
  cap: string;
  lockCol: TColor;
begin
  f := FOpenFiles[AFileIdx];
  r := Rect(0, ATop, ClientWidth - 1, ATop + ROW_H);
  active := f.Active;
  hovered := ARowIdx = FHot;
  if active then
  begin
    Canvas.Brush.Color := clSideSel;
    Canvas.FillRect(r);
  end
  else if hovered then
  begin
    Canvas.Brush.Color := clSideHover;
    Canvas.FillRect(r);
  end;
  Canvas.Brush.Style := bsClear;

  // priorite: survol = croix, sinon cadenas > olive > croix
  iconR := OpenIconRect(ATop);
  if hovered then
    DrawXGlyph(iconR, clSideTextHi)
  else if f.ReadOnly then
  begin
    if f.Modified then lockCol := clTabLockMod else lockCol := clTabLock;
    DrawLockGlyph(iconR, lockCol);
  end
  else if f.Modified then
    DrawDotGlyph(iconR, clModifiedDot)
  else
    DrawXGlyph(iconR, clSideText);

  Canvas.Brush.Style := bsClear;
  tx := iconR.Right + 4;
  clipR := ClientWidth - GRIP_W - SBW - 2;
  availW := clipR - tx;
  cap := f.Name;
  while (Canvas.TextWidth(cap) > availW) and (Length(cap) > 1) do
    cap := Copy(cap, 1, Length(cap) - 1);
  if cap <> f.Name then
    cap := Copy(cap, 1, Length(cap) - 1) + '…';
  if active or hovered then
    Canvas.Font.Color := clSideTextHi
  else
    Canvas.Font.Color := clSideText;
  ty := ATop + (ROW_H - Canvas.TextHeight('Ag')) div 2;
  Canvas.TextRect(Rect(tx - 1, ATop, clipR, ATop + ROW_H), tx, ty, cap);
end;

procedure TSideBar.DrawNode(ARowIdx, ATop: Integer; ANode: TSideNode);
var
  r: TRect;
  x, cy: Integer;
begin
  r := Rect(0, ATop, ClientWidth - 1, ATop + ROW_H);
  if ANode = FSel then
  begin
    Canvas.Brush.Color := clSideSel;
    Canvas.FillRect(r);
  end
  else if ARowIdx = FHot then
  begin
    Canvas.Brush.Color := clSideHover;
    Canvas.FillRect(r);
  end;
  Canvas.Brush.Style := bsClear;
  x := PADX + ANode.Depth * INDENT;
  cy := ATop + ROW_H div 2;
  if ANode.IsDir then
  begin
    Canvas.Pen.Color := clSideText;
    Canvas.Brush.Color := clSideText;
    Canvas.Brush.Style := bsSolid;
    if ANode.Expanded then
      Canvas.Polygon([Point(x, cy - 1), Point(x + 7, cy - 1), Point(x + 3, cy + 3)])
    else
      Canvas.Polygon([Point(x + 1, cy - 4), Point(x + 5, cy), Point(x + 1, cy + 4)]);
    Canvas.Brush.Style := bsClear;
  end;
  if ANode.IsDir then
    DrawFolderIcon(x + TRI_W, cy, clSideHeader)
  else
    DrawFileIcon(x + TRI_W, cy, clSideHeader);
  if (ARowIdx = FHot) or (ANode = FSel) then
    Canvas.Font.Color := clSideTextHi
  else
    Canvas.Font.Color := clSideText;
  Canvas.TextRect(r, x + TRI_W + NODE_ICON_W,
    ATop + (ROW_H - Canvas.TextHeight('Ag')) div 2, ANode.Name);
end;

procedure TSideBar.DrawRow(ARowIdx, ATop: Integer);
begin
  case FRows[ARowIdx].Kind of
    srkOpenHdr:   DrawHeader('OPEN FILES', ATop);
    srkFolderHdr: DrawHeader('FOLDERS', ATop);
    srkOpenFile:  DrawOpenFile(ARowIdx, FRows[ARowIdx].Idx, ATop);
    srkNode:      DrawNode(ARowIdx, ATop, FRows[ARowIdx].Node);
  end;
end;

procedure TSideBar.Paint;
var
  i, y: Integer;
  tr: TRect;
begin
  Canvas.Brush.Color := clSideBg;
  Canvas.FillRect(ClientRect);
  Canvas.Pen.Color := clBorder;
  Canvas.Line(ClientWidth - 1, 0, ClientWidth - 1, ClientHeight);

  y := 0;
  i := FScroll;
  while (i <= High(FRows)) and (y < ClientHeight) do
  begin
    DrawRow(i, y);
    Inc(y, ROW_H);
    Inc(i);
  end;

  if NeedScrollbar then
  begin
    tr := ThumbRect;
    if tr.Bottom > tr.Top then
    begin
      Canvas.Brush.Style := bsSolid;
      if FSBDragging then Canvas.Brush.Color := clSideHeader
      else Canvas.Brush.Color := clSideSel;
      Canvas.Pen.Color := Canvas.Brush.Color;
      Canvas.RoundRect(tr.Left, tr.Top + 1, tr.Right, tr.Bottom - 1, 5, 5);
    end;
  end;
  Canvas.Brush.Style := bsSolid;
end;

procedure TSideBar.Resize;
begin
  inherited Resize;
  ClampScroll;
  Invalidate;
end;

procedure TSideBar.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  idx: Integer;
  n: TSideNode;
begin
  inherited MouseDown(Button, Shift, X, Y);
  if Button <> mbLeft then Exit;

  if NeedScrollbar and (X >= ClientWidth - GRIP_W - SBW) and (X < ClientWidth - GRIP_W) then
  begin
    with ThumbRect do
      if (Y >= Top) and (Y < Bottom) then
      begin
        FSBDragging := True;
        FSBDragOffset := Y - Top;
      end
      else if Y < Top then
      begin
        Dec(FScroll, RowsFit); ClampScroll; Invalidate;
      end
      else
      begin
        Inc(FScroll, RowsFit); ClampScroll; Invalidate;
      end;
    Exit;
  end;

  if X >= ClientWidth - GRIP_W then
  begin
    FSizing := True;
    Exit;
  end;

  idx := RowAt(Y);
  if idx < 0 then Exit;
  case FRows[idx].Kind of
    srkOpenFile:
      // icone = fermer, nom = activer
      if X < OpenIconRect(0).Right then
      begin
        if Assigned(FOnCloseFile) then FOnCloseFile(FRows[idx].Idx);
      end
      else
        if Assigned(FOnActivateFile) then FOnActivateFile(FRows[idx].Idx);
    srkNode:
      begin
        n := FRows[idx].Node;
        if n.IsDir then
        begin
          n.Expanded := not n.Expanded;
          RebuildRows;
          Invalidate;
        end
        else
        begin
          FSel := n;
          Invalidate;
          if Assigned(FOnOpenFile) then FOnOpenFile(n.Path);
        end;
      end;
  end;
end;

procedure TSideBar.MouseMove(Shift: TShiftState; X, Y: Integer);
var
  idx, w: Integer;
begin
  inherited MouseMove(Shift, X, Y);
  if FSBDragging then
  begin
    ScrollToThumb(Y - FSBDragOffset);
    Exit;
  end;
  if FSizing then
  begin
    w := X;
    if w < MIN_W then w := MIN_W;
    if w > MAX_W then w := MAX_W;
    if w <> Width then Width := w; // alLeft: seule la largeur compte
    Exit;
  end;
  if X >= ClientWidth - GRIP_W then
    Cursor := crHSplit
  else
    Cursor := crDefault;
  idx := RowAt(Y);
  if idx <> FHot then
  begin
    FHot := idx;
    Invalidate;
  end;
end;

procedure TSideBar.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseUp(Button, Shift, X, Y);
  FSizing := False;
  FSBDragging := False;
end;

procedure TSideBar.MouseLeave;
begin
  inherited MouseLeave;
  if FHot <> -1 then
  begin
    FHot := -1;
    Invalidate;
  end;
end;

function TSideBar.DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean;
begin
  Result := True;
  if WheelDelta > 0 then
    Dec(FScroll, 3)
  else
    Inc(FScroll, 3);
  ClampScroll;
  Invalidate;
end;

// ---------- watch disque

procedure TSideBar.CollectExpandedPaths(ANode: TSideNode; AList: TStringList);
var
  i: Integer;
begin
  if ANode.IsDir and ANode.Expanded then
  begin
    AList.Add(ANode.Path);
    if ANode.Loaded then
      for i := 0 to ANode.Children.Count - 1 do
        CollectExpandedPaths(TSideNode(ANode.Children[i]), AList);
  end;
end;

procedure TSideBar.ReExpand(ANode: TSideNode; AList: TStringList);
var
  i, idx: Integer;
begin
  if not ANode.IsDir then Exit;
  if (ANode = FRoot) or AList.Find(ANode.Path, idx) then
  begin
    ANode.Expanded := True;
    LoadChildren(ANode);
    for i := 0 to ANode.Children.Count - 1 do
      ReExpand(TSideNode(ANode.Children[i]), AList);
  end;
end;

function TSideBar.FindNodeByPath(ANode: TSideNode; const APath: string): TSideNode;
var
  i: Integer;
begin
  Result := nil;
  if SameFileName(ANode.Path, APath) then Exit(ANode);
  for i := 0 to ANode.Children.Count - 1 do
  begin
    Result := FindNodeByPath(TSideNode(ANode.Children[i]), APath);
    if Result <> nil then Exit;
  end;
end;

// reconstruit l'arbre, depliage et selection preserves par CHEMIN
procedure TSideBar.RefreshTree;
var
  expanded: TStringList;
  selPath, rp: string;
begin
  if FRoot = nil then Exit;
  if not DirectoryExists(FRoot.Path) then Exit; // racine disparue: ne rien toucher
  expanded := TStringList.Create;
  try
    expanded.Sorted := True;
    expanded.Duplicates := dupIgnore;
    expanded.CaseSensitive := False;
    CollectExpandedPaths(FRoot, expanded);
    if FSel <> nil then selPath := FSel.Path else selPath := '';
    rp := FRoot.Path;

    FSel := nil; // les noeuds vont etre liberes
    FreeAndNil(FRoot);
    FRoot := TSideNode.Create;
    FRoot.Name := ExtractFileName(ExcludeTrailingPathDelimiter(rp));
    if FRoot.Name = '' then
      FRoot.Name := ExcludeTrailingPathDelimiter(rp);
    FRoot.Path := ExcludeTrailingPathDelimiter(rp);
    FRoot.IsDir := True;
    FRoot.Expanded := True;
    ReExpand(FRoot, expanded);
    RebuildRows;
    if selPath <> '' then
      FSel := FindNodeByPath(FRoot, selPath);
  finally
    expanded.Free;
  end;
  FHot := -1;
  ClampScroll;
  Invalidate;
end;

procedure TSideBar.StartWatch(const APath: string);
{$IFDEF WINDOWS}
var
  w: WideString;
{$ENDIF}
begin
  StopWatch;
  FWatchDirty := False;
  FWatchCooldown := 0;
  {$IFDEF WINDOWS}
  w := UTF8Decode(APath);
  FWatch := FindFirstChangeNotificationW(PWideChar(w), True,
    FILE_NOTIFY_CHANGE_FILE_NAME or FILE_NOTIFY_CHANGE_DIR_NAME);
  if (FWatch = 0) or (FWatch = THandle(-1)) then
  begin
    FWatch := 0;
    Exit;
  end;
  if FWatchTimer = nil then
  begin
    FWatchTimer := TTimer.Create(Self);
    FWatchTimer.Interval := WATCH_MS;
    FWatchTimer.OnTimer := @WatchTick;
  end;
  FWatchTimer.Enabled := True;
  {$ENDIF}
end;

procedure TSideBar.StopWatch;
begin
  {$IFDEF WINDOWS}
  if FWatchTimer <> nil then FWatchTimer.Enabled := False;
  if (FWatch <> 0) and (FWatch <> THandle(-1)) then
    FindCloseChangeNotification(FWatch);
  {$ENDIF}
  FWatch := 0;
end;

procedure TSideBar.WatchTick(Sender: TObject);
begin
  {$IFDEF WINDOWS}
  if (FWatch = 0) or (FWatch = THandle(-1)) then Exit;
  if FWatchCooldown > 0 then Dec(FWatchCooldown);
  if WaitForSingleObject(FWatch, 0) = WAIT_OBJECT_0 then
  begin
    FindNextChangeNotification(FWatch); // re-arme AVANT de relire
    FWatchDirty := True;
  end;
  // fenetre inactive: on reste dirty, le rescan se paiera au retour de focus
  if not Application.Active then Exit;
  // RefreshTree relit les dossiers deplies: cooldown pour ne pas rescanner en
  // boucle sous churn continu (logs, build)
  if FWatchDirty and (FWatchCooldown = 0) and not FRefreshing then
  begin
    FWatchDirty := False;
    FWatchCooldown := WATCH_COOLDOWN;
    FRefreshing := True;
    try
      RefreshTree;
    finally
      FRefreshing := False;
    end;
  end;
  {$ENDIF}
end;

end.
