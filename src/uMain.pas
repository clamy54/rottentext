unit uMain;

{$mode objfpc}{$H+}
{$IFDEF DARWIN}{$modeswitch objectivec1}{$ENDIF}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, ExtCtrls, LCLType, LCLVersion,
  Menus,
  Dialogs, {$IFDEF DARWIN}CocoaConfig,{$ENDIF} uTheme, uMenuBar, uTabBar,
  uStatusBar, uMinimap, uScrollbar,
  uActions, uDocumentManager, uDocument, uEditorView, uHighlight, uFindBar,
  uEncoding, uHexView, uSideBar, uSettings, uSession, uEol, uPalette,
  uInstance;

const
  RT_VERSION = '1.1';

type
  TPaneUI = record
    Panel: TPanel;
    Tabs: TTabBar;
    Host: TPanel;
    Right: TPanel;
    Map: TMinimap;
    Bar: TVScrollbar;
  end;

  TfrmMain = class(TForm)
  private
    FMenuBar: TRTMenuBar;
    FStatusBar: TRTStatusBar;
    FFindBar: TFindBar;
    FSideBar: TSideBar;
    FContent: TPanel;
    FPanes: array[0..1] of TPaneUI;
    FSplitter: TPanel;
    FMgr: TDocumentManager;
    FActions: TAppActions;
    FPalette: TCommandPalette;
    FChordK: Boolean;
    FSessionWin: Boolean; // lancee SANS argument: seule elle porte la session
    FSessionDone: Boolean;
    FSessTimer: TTimer;
    FIpcTimer: TTimer;
    FPendingOpen: array of string;
    FPendingTimer: TTimer;
    FPendingDropped: Integer;
    FBootShown: Boolean; // OnShow refire a chaque Show (cycle hide/show macOS)
    {$IFDEF DARWIN}
    FQuitting: Boolean; // quit VOULU (menu app, Cmd+Q, Dock), pas bouton rouge
    {$IF lcl_fullversion >= 4080000}
    FQuitHooked: Boolean; // item Quit du menu app re-cible (voir uDarwinQuit)
    {$ENDIF}
    procedure DarwinQuit(Data: PtrInt);
    {$IF lcl_fullversion >= 4080000}
    procedure QueryEndSessionHandler(var Cancel: Boolean);
    {$ENDIF}
    {$ENDIF}
    procedure BuildUI;
    procedure BuildPane(AIndex: Integer);
    procedure SyncSplitWidth;
    procedure UpdateSplitConstraint;
    procedure ContentResized(Sender: TObject);
    procedure SideBarResized(Sender: TObject);
    procedure RefreshTabs;
    procedure UpdatePaneBind(AIndex: Integer);
    procedure HandleSideOpen(const AFileName: string);
    procedure HandleSideActivate(AIndex: Integer);
    procedure HandleSideClose(AIndex: Integer);
    procedure SyncSideOpenFiles;
    procedure HandleOpenFolder(const APath: string);
    procedure HandleToggleSideBar(Sender: TObject);
    procedure HandleToggleSplit(Sender: TObject);
    procedure HandleThemeChanged(Sender: TObject);
    procedure HandleCommandPalette(Sender: TObject);
    procedure HandlePaletteFocus(Sender: TObject);
    procedure HandlePaneMouse(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Integer);
    procedure HandleTabDrop(ADocIndex: Integer; const AScreenPt: TPoint);
    function GroupAtScreen(const P: TPoint): Integer;
    procedure HandleListChanged(Sender: TObject);
    procedure HandleActiveChanged(Sender: TObject);
    procedure HandleDocChanged(Sender: TObject);
    procedure UpdateCaption;
    procedure FormShowHandler(Sender: TObject);
    procedure FormActivateHandler(Sender: TObject);
    procedure FormCloseQueryHandler(Sender: TObject; var CanClose: Boolean);
    procedure FormKeyDownHandler(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure HandleMacroState(Sender: TObject);
    procedure HandleHexCaret(Sender: TObject);
    function DocMutationBlocked: Boolean;
    procedure SessionTick(Sender: TObject);
    procedure InstanceTick(Sender: TObject);
    procedure PendingOpenTick(Sender: TObject);
    procedure OpenDropped(const APath: string);
    procedure DropFilesHandler(Sender: TObject; const FileNames: array of string);
    procedure CaptureWindowSettings;
  public
    constructor Create(AOwner: TComponent); override;
  end;

var
  frmMain: TfrmMain;

implementation

{$IFDEF DARWIN}
uses
  CocoaAll{$IF lcl_fullversion >= 4080000}, uDarwinQuit{$ENDIF};
{$ENDIF}

constructor TfrmMain.Create(AOwner: TComponent);
begin
  inherited CreateNew(AOwner);
  BuildUI;
end;

const
  MIN_PANE_W = 160;

procedure TfrmMain.BuildPane(AIndex: Integer);
begin
  FPanes[AIndex].Panel := TPanel.Create(Self);
  FPanes[AIndex].Panel.BevelOuter := bvNone;
  FPanes[AIndex].Panel.Color := clEditorBg;
  FPanes[AIndex].Panel.Parent := FContent;

  FPanes[AIndex].Tabs := TTabBar.Create(Self);
  FPanes[AIndex].Tabs.Parent := FPanes[AIndex].Panel;
  FPanes[AIndex].Tabs.Align := alTop;
  FPanes[AIndex].Tabs.Height := 35;
  FPanes[AIndex].Tabs.OnTabDrop := @HandleTabDrop;

  FPanes[AIndex].Host := TPanel.Create(Self);
  FPanes[AIndex].Host.Parent := FPanes[AIndex].Panel;
  FPanes[AIndex].Host.Align := alClient;
  FPanes[AIndex].Host.BevelOuter := bvNone;
  FPanes[AIndex].Host.Color := clEditorBg;
  FPanes[AIndex].Host.DoubleBuffered := True;
  FPanes[AIndex].Host.OnMouseDown := @HandlePaneMouse;

  // l'ordre des siblings alRight n'est pas fiable en LCL: passer par un conteneur
  FPanes[AIndex].Right := TPanel.Create(Self);
  FPanes[AIndex].Right.Parent := FPanes[AIndex].Host;
  FPanes[AIndex].Right.Align := alRight;
  FPanes[AIndex].Right.Width := 134;
  FPanes[AIndex].Right.BevelOuter := bvNone;
  FPanes[AIndex].Right.Color := clEditorBg;

  FPanes[AIndex].Bar := TVScrollbar.Create(Self);
  FPanes[AIndex].Bar.Parent := FPanes[AIndex].Right;
  FPanes[AIndex].Bar.Align := alRight;
  FPanes[AIndex].Bar.Width := 14;

  FPanes[AIndex].Map := TMinimap.Create(Self);
  FPanes[AIndex].Map.Parent := FPanes[AIndex].Right;
  FPanes[AIndex].Map.Align := alClient;
end;

procedure TfrmMain.BuildUI;
var
  wx, wy, ww, wh: Integer;
begin
  FSessionWin := ParamCount = 0;
  Caption := 'RottenText';
  // rect sauve hors ecran (moniteur debranche): repli sur le defaut centre
  wx := SetWinX; wy := SetWinY; ww := SetWinW; wh := SetWinH;
  if SetWinValid and (ww >= 300) and (wh >= 200) and
     (wx >= Screen.DesktopLeft) and (wy >= Screen.DesktopTop) and
     (wx + ww <= Screen.DesktopLeft + Screen.DesktopWidth) and
     (wy + wh <= Screen.DesktopTop + Screen.DesktopHeight) then
  begin
    SetInitialBounds(wx, wy, ww, wh);
    Position := poDesigned;
    if SetWinMax then WindowState := wsMaximized;
  end
  else
  begin
    SetInitialBounds(0, 0, 1100, 720);
    Position := poScreenCenter;
    if SetWinValid and SetWinMax then WindowState := wsMaximized;
  end;
  Color := clEditorBg;
  KeyPreview := True;
  OnKeyDown := @FormKeyDownHandler;
  OnShow := @FormShowHandler;
  // Form.OnActivate ne refire pas au retour de focus d'un mono-fenetre
  Application.OnActivate := @FormActivateHandler;
  OnCloseQuery := @FormCloseQueryHandler;

  FMenuBar := TRTMenuBar.Create(Self);
  FMenuBar.Parent := Self;
  FMenuBar.Align := alTop;
  FMenuBar.Height := 26;

  FStatusBar := TRTStatusBar.Create(Self);
  FStatusBar.Parent := Self;
  FStatusBar.Align := alBottom;
  FStatusBar.Height := 24;

  // alBottom stacke par Top: forcer l'ordre au-dessus de la status bar
  FFindBar := TFindBar.Create(Self);
  FFindBar.Parent := Self;
  FFindBar.Align := alBottom;
  FFindBar.Top := FStatusBar.Top - FFindBar.Height;

  FSideBar := TSideBar.Create(Self);
  FSideBar.Parent := Self;
  FSideBar.Align := alLeft;
  FSideBar.Width := 260;
  FSideBar.Visible := SetSideBarVisible;
  FSideBar.OnOpenFile := @HandleSideOpen;
  FSideBar.OnActivateFile := @HandleSideActivate;
  FSideBar.OnCloseFile := @HandleSideClose;
  FSideBar.OnResize := @SideBarResized;

  // conteneur: un pane alTop pose sur la form passerait AU-DESSUS de la side bar
  FContent := TPanel.Create(Self);
  FContent.Parent := Self;
  FContent.Align := alClient;
  FContent.BevelOuter := bvNone;
  FContent.Color := clEditorBg;
  FContent.OnResize := @ContentResized;

  BuildPane(0);
  FPanes[0].Panel.Align := alClient;

  FMgr := TDocumentManager.Create(FPanes[0].Host);
  FMgr.OnListChanged := @HandleListChanged;
  FMgr.OnActiveChanged := @HandleActiveChanged;
  FMgr.OnDocChanged := @HandleDocChanged;
  FMgr.OnOpenFolder := @HandleOpenFolder;

  FActions := TAppActions.Create(FMgr, Self);
  FActions.OnMacroStateChange := @HandleMacroState;
  FActions.OnToggleSideBar := @HandleToggleSideBar;
  FActions.OnToggleSplit := @HandleToggleSplit;
  FActions.OnThemeChanged := @HandleThemeChanged;
  FActions.OnCommandPalette := @HandleCommandPalette;

  // cree en dernier: l'overlay flottant doit passer au-dessus du reste
  FPalette := TCommandPalette.Create(Self);
  FPalette.Parent := Self;
  FPalette.OnRestoreFocus := @HandlePaletteFocus;
  FFindBar.Attach(FMgr);
  FFindBar.OnMatchInfo := @FStatusBar.SetFindInfo;
  FActions.AttachFindBar(FFindBar);
  FMenuBar.Attach(FActions);
  {$IFDEF DARWIN}
  // menus dans la barre globale; la barre custom reste le constructeur de l'arbre
  FMenuBar.AttachNative(Self);
  FMenuBar.Visible := False;
  {$IF lcl_fullversion >= 4080000}
  // 4.8: plus de onQuitApp. Quit Dock/extinction passe par QueryEndSession,
  // Cmd+Q par l'item Quit re-cible au premier Show (voir uDarwinQuit)
  Application.OnQueryEndSession := @QueryEndSessionHandler;
  {$ELSE}
  CocoaConfigApplication.events.onQuitApp := @DarwinQuit;
  {$ENDIF}
  {$ENDIF}
  FActions.SetSideBarChecked(FSideBar.Visible);
  FPanes[0].Tabs.Attach(FMgr, 0);
  if not ((ParamCount >= 1) and FileExists(ParamStr(1))) then
    FMgr.NewFile;
  if FSessionWin then
  begin
    FSessTimer := TTimer.Create(Self);
    FSessTimer.Interval := 60000;
    FSessTimer.OnTimer := @SessionTick;
    FSessTimer.Enabled := True;
  end;
  // toute fenetre tente le serveur IPC, meme lancee avec un argument (uInstance arbitre)
  if InstanceServerStart then
  begin
    FIpcTimer := TTimer.Create(Self);
    FIpcTimer.Interval := 300;
    FIpcTimer.OnTimer := @InstanceTick;
    FIpcTimer.Enabled := True;
  end;
  AllowDropFiles := True;
  OnDropFiles := @DropFilesHandler;
  FPendingTimer := TTimer.Create(Self);
  FPendingTimer.Interval := 200;
  FPendingTimer.OnTimer := @PendingOpenTick;
  FPendingTimer.Enabled := False;
end;

procedure TfrmMain.UpdateCaption;
var
  doc: TDocument;
begin
  doc := FMgr.ActiveDoc;
  if doc = nil then
    Caption := 'RottenText'
  else
    Caption := doc.DisplayName + ' - RottenText';
end;

procedure TfrmMain.FormShowHandler(Sender: TObject);
var
  sess: TSession;
begin
  {$IFDEF DARWIN}{$IF lcl_fullversion >= 4080000}
  // le menu app n'existe qu'une fois le menu principal pose par Cocoa
  if not FQuitHooked then
    FQuitHooked := DarwinQuitHookInstall(@DarwinQuit);
  {$ENDIF}{$ENDIF}
  if FSessionWin and not FSessionDone then
  begin
    FSessionDone := True;
    if SessionLoad(sess) then
    begin
      if sess.Split and not FMgr.Split then
        HandleToggleSplit(nil);
      SessionRestoreInto(FMgr, sess);
    end;
  end;
  // RottenText <fichier|dossier> (le --blank d'une New Window ne matche rien)
  if (ParamCount >= 1) and not FBootShown then
  begin
    if DirectoryExists(ParamStr(1)) then
      HandleOpenFolder(ExpandFileName(ParamStr(1)))
    else if FileExists(ParamStr(1)) then
      FMgr.OpenFile(ParamStr(1));
  end;
  if FMgr.ActiveDoc <> nil then
    FMgr.ActiveDoc.ShowDoc;
  FBootShown := True;
end;

// jamais avant la restauration: on ecraserait la session par l'onglet du boot
procedure TfrmMain.SessionTick(Sender: TObject);
begin
  if FSessionDone then
    SessionSaveFrom(FMgr);
end;

function TfrmMain.DocMutationBlocked: Boolean;
begin
  Result := (Application.ModalLevel > 0) or ActionModalActive;
end;

procedure TfrmMain.InstanceTick(Sender: TObject);
const
  MAX_OPEN_PER_TICK = 8;
var
  p: string;
  n: Integer;
begin
  if not FBootShown then Exit;
  // canal VIDE sans acquitter: le client expire et ouvre sa propre fenetre
  if DocMutationBlocked then
  begin
    InstanceServerDrain;
    Exit;
  end;
  n := 0;
  while (n < MAX_OPEN_PER_TICK) and InstanceServerPoll(p) do
  begin
    FMgr.OpenFile(p);
    Inc(n);
  end;
  if n > 0 then
  begin
    if not Visible then Show;
    {$IFDEF DARWIN}
    // c'est un autre process qui a ouvert le fichier: personne n'a active l'app
    NSApplication.sharedApplication.activateIgnoringOtherApps(True);
    {$ENDIF}
    BringToFront;
  end;
end;

procedure TfrmMain.OpenDropped(const APath: string);
begin
  if DirectoryExists(APath) then
    HandleOpenFolder(APath)
  else if FileExists(APath) then
    FMgr.OpenFile(APath);
end;

procedure TfrmMain.PendingOpenTick(Sender: TObject);
var
  todo: array of string;
  i, dropped: Integer;
begin
  if DocMutationBlocked then Exit;
  FPendingTimer.Enabled := False;
  todo := FPendingOpen; // vider AVANT d'ouvrir: OpenFile peut re-entrer ici
  FPendingOpen := nil;
  dropped := FPendingDropped;
  FPendingDropped := 0;
  for i := 0 to High(todo) do
    OpenDropped(todo[i]);
  if dropped > 0 then
    MessageDlg('RottenText',
      Format('%d file(s) received while busy were not opened (queue full).',
        [dropped]), mtWarning, [mbOK], 0);
end;

// recoit aussi le "Ouvrir avec" de LaunchServices sous macOS
procedure TfrmMain.DropFilesHandler(Sender: TObject;
  const FileNames: array of string);
const
  MAX_PENDING = 64;
var
  i, n: Integer;
begin
  // evenement systeme sans repli, il arrive MEME sous modale: mis en file
  if DocMutationBlocked then
  begin
    for i := 0 to High(FileNames) do
    begin
      n := Length(FPendingOpen);
      if n >= MAX_PENDING then
      begin
        Inc(FPendingDropped, High(FileNames) - i + 1);
        Break;
      end;
      SetLength(FPendingOpen, n + 1);
      FPendingOpen[n] := FileNames[i];
    end;
    if (Length(FPendingOpen) > 0) or (FPendingDropped > 0) then
      FPendingTimer.Enabled := True;
    Exit;
  end;
  for i := 0 to High(FileNames) do
    OpenDropped(FileNames[i]);
end;

procedure TfrmMain.CaptureWindowSettings;
begin
  // Restored*: la geometrie normale, meme fenetre maximisee
  SetWinX := RestoredLeft;
  SetWinY := RestoredTop;
  SetWinW := RestoredWidth;
  SetWinH := RestoredHeight;
  SetWinMax := WindowState = wsMaximized;
  SetWinValid := True;
  SetSideBarVisible := FSideBar.Visible;
end;

procedure TfrmMain.FormActivateHandler(Sender: TObject);
begin
  {$IFDEF DARWIN}{$IF lcl_fullversion >= 4080000}
  // filet: si le premier Show a couru avant la pose du menu principal
  if not FQuitHooked then
    FQuitHooked := DarwinQuitHookInstall(@DarwinQuit);
  {$ENDIF}{$ENDIF}
  // CheckExternalChanges peut FERMER un doc tenu par une action: use-after-free
  if DocMutationBlocked then Exit;
  {$IFDEF DARWIN}
  if FBootShown and not Visible and not FQuitting then
  begin
    if FMgr.Count = 0 then FMgr.NewFile;
    Show;
  end;
  {$ENDIF}
  if FMgr <> nil then FMgr.CheckExternalChanges;
end;

{$IFDEF DARWIN}
procedure TfrmMain.DarwinQuit(Data: PtrInt);
begin
  FQuitting := True;
  Close;
end;

{$IF lcl_fullversion >= 4080000}
// quit par Apple Event (Dock, extinction, osascript): 4.8 enchaine sur un
// Terminate sec, sans CloseQuery. Prompts et sauvegarde de session ici.
procedure TfrmMain.QueryEndSessionHandler(var Cancel: Boolean);
begin
  FQuitting := True;
  Cancel := not CloseQuery; // remet FQuitting a False si refus
end;
{$ENDIF}
{$ENDIF}

procedure TfrmMain.HandleSideOpen(const AFileName: string);
begin
  if DocMutationBlocked then Exit;
  FMgr.OpenFile(AFileName);
end;

procedure TfrmMain.HandleSideActivate(AIndex: Integer);
begin
  if (AIndex >= 0) and (AIndex < FMgr.Count) then FMgr.Activate(AIndex);
end;

procedure TfrmMain.HandleSideClose(AIndex: Integer);
begin
  if DocMutationBlocked then Exit;
  if (AIndex >= 0) and (AIndex < FMgr.Count) then FMgr.CloseDoc(AIndex);
end;

procedure TfrmMain.SyncSideOpenFiles;
var
  arr: array of TSideOpenFile;
  i, act: Integer;
  d: TDocument;
begin
  if FSideBar = nil then Exit;
  SetLength(arr, FMgr.Count);
  act := FMgr.ActiveIndex;
  for i := 0 to FMgr.Count - 1 do
  begin
    d := FMgr.Docs[i];
    arr[i].Name := d.DisplayName;
    arr[i].Modified := d.Modified;
    arr[i].ReadOnly := d.ReadOnly;
    arr[i].Active := i = act;
  end;
  FSideBar.SetOpenFiles(arr);
end;

procedure TfrmMain.HandleOpenFolder(const APath: string);
begin
  FSideBar.SetRoot(APath);
  if not FSideBar.Visible then
  begin
    FSideBar.Visible := True;
    FActions.SetSideBarChecked(True);
    UpdateSplitConstraint;
  end;
end;

procedure TfrmMain.HandleToggleSideBar(Sender: TObject);
begin
  FSideBar.Visible := not FSideBar.Visible;
  if FSideBar.Visible then SyncSideOpenFiles;
  FActions.SetSideBarChecked(FSideBar.Visible);
  UpdateSplitConstraint;
  if FSessionWin then
  begin
    SetSideBarVisible := FSideBar.Visible;
    SettingsSave;
  end;
end;

procedure TfrmMain.SyncSplitWidth;
var
  avail, w, maxW: Integer;
begin
  if (FPanes[1].Panel = nil) or not FPanes[1].Panel.Visible then Exit;
  avail := FContent.ClientWidth - FSplitter.Width;
  w := avail div 2;
  // caper le pane droit: le gauche est alClient, un plancher ne le protege pas
  maxW := avail - MIN_PANE_W;
  if w > maxW then w := maxW;
  if w < MIN_PANE_W then w := MIN_PANE_W;
  FPanes[1].Panel.Width := w;
  // l'ordre des alRight n'est pas fiable: forcer le splitter par son Left
  FSplitter.Left := FPanes[1].Panel.Left - FSplitter.Width;
end;

// la side bar entre dans la largeur mini, sinon deux panes n'y tiennent plus
procedure TfrmMain.UpdateSplitConstraint;
var
  sb: Integer;
begin
  if (FSplitter = nil) or not FMgr.Split then
  begin
    Constraints.MinWidth := 0;
    Exit;
  end;
  sb := 0;
  if FSideBar.Visible then sb := FSideBar.Width;
  Constraints.MinWidth := sb + 2 * MIN_PANE_W + FSplitter.Width + 60;
end;

procedure TfrmMain.ContentResized(Sender: TObject);
begin
  SyncSplitWidth;
end;

procedure TfrmMain.SideBarResized(Sender: TObject);
begin
  UpdateSplitConstraint;
end;

// pane 1 jamais detruit (il possede des vues re-parentees), seulement masque
procedure TfrmMain.HandleToggleSplit(Sender: TObject);
begin
  if not FMgr.Split then
  begin
    if FPanes[1].Panel = nil then
    begin
      BuildPane(1);
      FPanes[1].Panel.Align := alRight;
      FSplitter := TPanel.Create(Self);
      FSplitter.Parent := FContent;
      FSplitter.Align := alRight;
      FSplitter.Width := 4;
      FSplitter.BevelOuter := bvNone;
      FSplitter.Color := clTabStrip;
      FPanes[1].Tabs.Attach(FMgr, 1);
      FMgr.SetGroupHost(1, FPanes[1].Host);
    end
    else
    begin
      FPanes[1].Panel.Visible := True;
      FSplitter.Visible := True;
    end;
    FMgr.SetSplit(True);
    UpdateSplitConstraint; // apres SetSplit: il teste FMgr.Split
    SyncSplitWidth;
  end
  else
  begin
    FMgr.SetSplit(False); // re-parente les docs du groupe 1 avant qu'on cache le pane
    FPanes[1].Panel.Visible := False;
    FSplitter.Visible := False;
    UpdateSplitConstraint;
  end;
  FActions.SetSplitChecked(FMgr.Split);
end;

// re-appliquer la ou les couleurs sont posees a la creation, ailleurs elles sont lues au Paint
procedure TfrmMain.HandleThemeChanged(Sender: TObject);
var
  i: Integer;
  d: TDocument;
begin
  Color := clEditorBg;
  FContent.Color := clEditorBg;
  if FSplitter <> nil then FSplitter.Color := clTabStrip;
  for i := 0 to 1 do
    if FPanes[i].Panel <> nil then
    begin
      FPanes[i].Panel.Color := clEditorBg;
      FPanes[i].Host.Color := clEditorBg;
      FPanes[i].Right.Color := clEditorBg;
      FPanes[i].Tabs.RefreshTheme;
      FPanes[i].Map.RefreshTheme;
      FPanes[i].Bar.Color := clEditorBg;
      FPanes[i].Bar.Invalidate;
    end;
  ReapplyScopeTheme;
  for i := 0 to FMgr.Count - 1 do
  begin
    d := FMgr.Docs[i];
    d.View.RefreshTheme;
    if d.HexView <> nil then
    begin
      d.HexView.Color := clEditorBg;
      d.HexView.Invalidate;
    end;
  end;
  FMenuBar.Invalidate;
  FStatusBar.Invalidate;
  FFindBar.RefreshTheme;
  FSideBar.RefreshTheme;
  FPalette.RefreshTheme;
end;

procedure TfrmMain.HandleCommandPalette(Sender: TObject);
begin
  // fenetre cachee (macOS): l'overlay n'a pas de fenetre ou se dessiner
  if not Visible then Exit;
  if FPalette.Visible then
    FPalette.ClosePalette
  else
    FPalette.OpenPalette(FMenuBar);
end;

// les handlers de menu executes ensuite lisent la vue focusee
procedure TfrmMain.HandlePaletteFocus(Sender: TObject);
var
  doc: TDocument;
begin
  doc := FMgr.ActiveDoc;
  if doc = nil then Exit;
  if doc.IsHex then
  begin
    if (doc.HexView <> nil) and doc.HexView.CanFocus then
      doc.HexView.SetFocus;
  end
  else if doc.View.Syn.CanFocus then
    doc.View.Syn.SetFocus;
end;

procedure TfrmMain.HandlePaneMouse(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
begin
  if Sender = FPanes[1].Host then
    FMgr.ActivateGroup(1)
  else
    FMgr.ActivateGroup(0);
end;

function TfrmMain.GroupAtScreen(const P: TPoint): Integer;
var
  i: Integer;
  pt: TPoint;
begin
  Result := -1;
  for i := 0 to 1 do
    if (FPanes[i].Panel <> nil) and FPanes[i].Panel.Visible then
    begin
      pt := FPanes[i].Panel.ScreenToClient(P);
      if (pt.X >= 0) and (pt.Y >= 0) and
         (pt.X < FPanes[i].Panel.Width) and (pt.Y < FPanes[i].Panel.Height) then
        Exit(i);
    end;
end;

procedure TfrmMain.HandleTabDrop(ADocIndex: Integer; const AScreenPt: TPoint);
var
  target: Integer;
begin
  if not FMgr.Split then Exit;
  if (ADocIndex < 0) or (ADocIndex >= FMgr.Count) then Exit;
  target := GroupAtScreen(AScreenPt);
  if target < 0 then Exit;
  if FMgr.Docs[ADocIndex].Group <> target then
    FMgr.MoveToOtherGroup(ADocIndex);
end;

procedure TfrmMain.FormCloseQueryHandler(Sender: TObject; var CanClose: Boolean);
begin
  {$IFDEF DARWIN}
  // bouton rouge: fermer le CONTENU puis cacher la fenetre, l'app survit
  if not FQuitting then
  begin
    CanClose := False;
    if FMgr.CloseAll then
    begin
      if FSessionWin then
      begin
        SessionSaveFrom(FMgr);
        CaptureWindowSettings;
        SettingsSave;
      end;
      Hide;
    end;
    Exit;
  end;
  {$ENDIF}
  // fenetre de session: les untitled partent dans la session, pas de prompt
  if FSessionWin then
    CanClose := FMgr.CanCloseAll(True)
  else
    CanClose := FMgr.CanCloseAll;
  if not CanClose then
  begin
    {$IFDEF DARWIN}FQuitting := False;{$ENDIF}
    Exit;
  end;
  if FSessionWin then
  begin
    // session non ecrite: repli sur les prompts, sinon les notes sont perdues
    if not SessionSaveFrom(FMgr) then
    begin
      MessageDlg('RottenText',
        'The session could not be saved: unsaved tabs will not be restored' +
        LineEnding + 'at next launch. Save them now if needed.',
        mtWarning, [mbOK], 0);
      CanClose := FMgr.CanCloseUntitled;
      if not CanClose then
      begin
        {$IFDEF DARWIN}FQuitting := False;{$ENDIF}
        Exit;
      end;
      SessionSaveFrom(FMgr);
    end;
    CaptureWindowSettings;
    SettingsSave;
  end;
end;

procedure TfrmMain.RefreshTabs;
begin
  FPanes[0].Tabs.Refresh;
  if FPanes[1].Tabs <> nil then FPanes[1].Tabs.Refresh;
end;

procedure TfrmMain.HandleListChanged(Sender: TObject);
begin
  {$IFDEF DARWIN}
  // dernier onglet ferme = fenetre cachee; un doc cree ou ouvert la re-montre
  if FBootShown and not FQuitting then
  begin
    if (FMgr.Count = 0) and Visible then
      Hide
    else if (FMgr.Count > 0) and not Visible then
      Show;
  end;
  {$ENDIF}
  RefreshTabs;
  SyncSideOpenFiles;
  if FActions <> nil then
  begin
    FActions.SyncMacroEditors;
    HandleMacroState(nil); // l'index de la pastille REC a pu glisser
  end;
end;

procedure TfrmMain.HandleMacroState(Sender: TObject);
begin
  FPanes[0].Tabs.SetRecordingIndex(FActions.MacroRecordingIndex);
  if FPanes[1].Tabs <> nil then
    FPanes[1].Tabs.SetRecordingIndex(FActions.MacroRecordingIndex);
end;

procedure TfrmMain.UpdatePaneBind(AIndex: Integer);
var
  doc: TDocument;
begin
  if FPanes[AIndex].Panel = nil then Exit;
  doc := FMgr.GroupDoc(AIndex);
  if (doc <> nil) and doc.IsHex then
  begin
    FPanes[AIndex].Map.Bind(nil);
    FPanes[AIndex].Bar.Bind(nil);
    FPanes[AIndex].Right.Visible := False;
    doc.HexView.OnCaretMove := @HandleHexCaret;
  end
  else if doc <> nil then
  begin
    FPanes[AIndex].Right.Visible := True;
    // gros fichier: la minimap ne colore pas, le scan serait paye une 2e fois
    FPanes[AIndex].Map.NoHighlight := doc.LargeFile;
    FPanes[AIndex].Map.Bind(doc.View.Syn);
    FPanes[AIndex].Map.SyncHighlighter;
    FPanes[AIndex].Bar.Bind(doc.View.Syn);
  end
  else
  begin
    FPanes[AIndex].Map.Bind(nil);
    FPanes[AIndex].Bar.Bind(nil);
    FPanes[AIndex].Right.Visible := False;
  end;
end;

procedure TfrmMain.HandleActiveChanged(Sender: TObject);
var
  doc: TDocument;
begin
  RefreshTabs;
  UpdateCaption;
  SyncSideOpenFiles;
  if FActions <> nil then
    FActions.UpdateFileItems;
  FFindBar.ActiveDocChanged;
  UpdatePaneBind(0);
  UpdatePaneBind(1);
  doc := FMgr.ActiveDoc;
  if (doc <> nil) and not doc.Untitled then
    FSideBar.SelectPath(doc.FileName)
  else
    FSideBar.SelectPath('');
  if (doc <> nil) and doc.IsHex then
  begin
    FStatusBar.Bind(nil);
    FStatusBar.SetFileType('Plain Text');
    FStatusBar.SetEncoding('Hexadecimal');
    FStatusBar.SetEol('');
    HandleHexCaret(doc.HexView);
  end
  else if doc <> nil then
  begin
    FStatusBar.SetLeftOverride('');
    FStatusBar.Bind(doc.View.Syn);
    FStatusBar.SetFileType(LanguageLabel(doc.View.Syn.Highlighter));
    FStatusBar.SetEncoding(Encodings[doc.Encoding].Caption);
    FStatusBar.SetEol(EolName(doc.Eol));
  end
  else
  begin
    FStatusBar.SetLeftOverride('');
    FStatusBar.Bind(nil);
    FStatusBar.SetFileType('Plain Text');
    FStatusBar.SetEncoding('');
    FStatusBar.SetEol('');
  end;
end;

procedure TfrmMain.HandleHexCaret(Sender: TObject);
var
  hv: THexView;
begin
  // en split, une vue hex peut vivre dans le pane inactif
  if (FMgr.ActiveDoc = nil) or (FMgr.ActiveDoc.HexView <> Sender) then Exit;
  hv := Sender as THexView;
  FStatusBar.SetLeftOverride(Format('Offset 0x%s / %d bytes',
    [IntToHex(hv.CaretOfs, hv.OfsDigits), hv.FileSize]));
end;

procedure TfrmMain.HandleDocChanged(Sender: TObject);
var
  doc: TDocument;
begin
  FPanes[0].Tabs.Invalidate;
  if FPanes[1].Tabs <> nil then FPanes[1].Tabs.Invalidate;
  UpdateCaption;
  SyncSideOpenFiles;
  if FActions <> nil then
    FActions.UpdateFileItems;
  doc := FMgr.ActiveDoc;
  if (doc <> nil) and not doc.IsHex then
    FStatusBar.SetEol(EolName(doc.Eol));
end;

procedure TfrmMain.FormKeyDownHandler(Sender: TObject; var Key: Word; Shift: TShiftState);
var
  v: TEditorView;
begin
  // palette ouverte: sans ce court-circuit le KeyPreview mangerait Esc, F3, F9
  if (FPalette <> nil) and FPalette.Visible then Exit;
  v := nil;
  if (FMgr.ActiveDoc <> nil) and not FMgr.ActiveDoc.IsHex then
    v := FMgr.ActiveDoc.View;
  // chord Ctrl+K: un modificateur seul ne le casse pas, toute autre touche si
  if FChordK then
  begin
    case Key of
      VK_CONTROL, VK_SHIFT, VK_MENU, VK_LWIN, VK_RWIN: Exit;
    end;
    FChordK := False;
    if ssModifier in Shift then
      case Key of
        VK_B: begin HandleToggleSideBar(nil); Key := 0; Exit; end;
        VK_U: begin FActions.EditUpperCase(nil); Key := 0; Exit; end;
        VK_L: begin FActions.EditLowerCase(nil); Key := 0; Exit; end;
      end;
  end;
  // ssModifier = Ctrl (Windows/Linux) ou Cmd (macOS)
  if (ssModifier in Shift) and (ssAlt in Shift) then
    case Key of
      VK_UP:   begin if v <> nil then v.MultiAddLine(-1); Key := 0; end;
      VK_DOWN: begin if v <> nil then v.MultiAddLine(1); Key := 0; end;
    end
  else if ssModifier in Shift then
    case Key of
      VK_N:
        begin
          if ssShift in Shift then FActions.FileNewWindow(nil) else FMgr.NewFile;
          Key := 0;
        end;
      VK_O: begin FMgr.OpenDialog; Key := 0; end;
      VK_W:
        begin
          if ssShift in Shift then Close else FMgr.CloseDoc(FMgr.ActiveIndex);
          Key := 0;
        end;
      VK_S:
        begin
          if ssShift in Shift then FMgr.SaveActiveAs else FMgr.SaveActive;
          Key := 0;
        end;
      VK_F: begin FFindBar.ShowFind; Key := 0; end;
      // sur mac Cmd+H = Hide macOS, le remplacer passe par Cmd+Alt+F
      // (DarwinFixShortcuts); en 4.8 le KeyDown LCL court AVANT le menu
      {$IFNDEF DARWIN}
      VK_H: begin FFindBar.ShowReplace; Key := 0; end;
      {$ENDIF}
      VK_G: begin FActions.FindGotoOffset(nil); Key := 0; end;
      VK_K:
        begin
          if ssShift in Shift then FActions.EditDeleteLine(nil)
          else FChordK := True;
          Key := 0;
        end;
      VK_V:
        if ssShift in Shift then // Ctrl+V simple laisse au SynEdit
        begin
          FActions.EditPasteIndent(nil);
          Key := 0;
        end;
      VK_M:
        begin
          if ssShift in Shift then FActions.MacroPlayback(nil)
          else FActions.MacroToggleRecord(nil);
          Key := 0;
        end;
      VK_B:
        if ssShift in Shift then
        begin
          FActions.SelExpandBrackets(nil);
          Key := 0;
        end;
      VK_P:
        if ssShift in Shift then
        begin
          HandleCommandPalette(nil);
          Key := 0;
        end;
      VK_OEM_2: begin FActions.EditToggleComment(nil); Key := 0; end;
      VK_L:
        begin
          if v <> nil then
            if ssShift in Shift then v.MultiSplitLines else v.ExpandToLine;
          Key := 0;
        end;
      VK_D: begin if v <> nil then v.ExpandToWord; Key := 0; end;
      {$IFNDEF DARWIN} // sur mac Cmd+Q = Quit du menu app natif
      VK_Q: begin FActions.FileQuit(nil); Key := 0; end;
      {$ENDIF}
      VK_TAB:
        begin
          if ssShift in Shift then FMgr.ActivatePrev else FMgr.ActivateNext;
          Key := 0;
        end;
      VK_1:
        begin
          if ssShift in Shift then FMgr.MoveActiveToGroup(0)
          else FMgr.ActivateGroup(0);
          Key := 0;
        end;
      VK_2:
        begin
          if ssShift in Shift then FMgr.MoveActiveToGroup(1)
          else FMgr.ActivateGroup(1);
          Key := 0;
        end;
    end
  else if (ssAlt in Shift) and (ssShift in Shift) then
    case Key of
      VK_1: begin if FMgr.Split then HandleToggleSplit(nil); Key := 0; end;
      VK_2: begin if not FMgr.Split then HandleToggleSplit(nil); Key := 0; end;
    end
  else
    case Key of
      VK_F3:
        begin
          if ssShift in Shift then FFindBar.FindPrev else FFindBar.FindNext;
          Key := 0;
        end;
      VK_F9: begin FActions.EditSortLines(nil); Key := 0; end;
      VK_ESCAPE:
        begin
          if FFindBar.Visible then
            FFindBar.HideBar
          else if v <> nil then
            v.MultiClear;
          Key := 0;
        end;
    end;
end;

end.
