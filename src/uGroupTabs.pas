unit uGroupTabs;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Controls, Menus, Clipbrd,
  uDocTabBar, uDocumentManager, uDocument;

type
  // drop hors de la barre: uMain hit-teste le pane cible
  TTabDropEvent = procedure(ADocIndex: Integer; const AScreenPt: TPoint) of object;

  // Branche une barre du kit sur un groupe du manager. La barre parle en
  // index d'onglet, le manager en index de doc: ne pas les confondre.
  TGroupTabs = class(TComponent)
  private
    FBar: TDocTabBar;
    FMgr: TDocumentManager;
    FGroup: Integer;
    FPopup: TPopupMenu;
    FMoveItem: TMenuItem;
    FCtxIndex: Integer;   // index de DOC
    FRecIndex: Integer;   // index de DOC
    FOnTabDrop: TTabDropEvent;
    function DocIndexOf(ATab: Integer): Integer;
    procedure SyncDim;
    procedure BuildPopup;
    function BarCount(Sender: TObject): Integer;
    procedure BarInfo(Sender: TObject; AIndex: Integer; var AInfo: TDocTabInfo);
    procedure BarActivate(Sender: TObject; AIndex: Integer);
    procedure BarClose(Sender: TObject; AIndex: Integer);
    procedure BarNew(Sender: TObject);
    procedure BarMove(Sender: TObject; AIndex, ANewIndex: Integer);
    procedure BarDropOutside(Sender: TObject; AIndex: Integer; const AScreenPt: TPoint);
    procedure BarContextMenu(Sender: TObject; AIndex: Integer; const AScreenPt: TPoint);
    procedure CtxClose(Sender: TObject);
    procedure CtxCloseOthers(Sender: TObject);
    procedure CtxCloseRight(Sender: TObject);
    procedure CtxCloseUnmodified(Sender: TObject);
    procedure CtxNewFile(Sender: TObject);
    procedure CtxCopyPath(Sender: TObject);
    procedure CtxMoveGroup(Sender: TObject);
  public
    constructor Create(AOwner: TComponent); override;
    procedure Attach(AMgr: TDocumentManager; AGroup: Integer = 0);
    procedure Refresh;
    procedure Invalidate;
    procedure SetRecordingIndex(AIndex: Integer);
    property Bar: TDocTabBar read FBar;
    property OnTabDrop: TTabDropEvent read FOnTabDrop write FOnTabDrop;
  end;

implementation

constructor TGroupTabs.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FCtxIndex := -1;
  FRecIndex := -1;
  FBar := TDocTabBar.Create(Self);
  FBar.OnTabCount := @BarCount;
  FBar.OnTabInfo := @BarInfo;
  FBar.OnTabActivate := @BarActivate;
  FBar.OnTabClose := @BarClose;
  FBar.OnNewTab := @BarNew;
  FBar.OnTabMove := @BarMove;
  FBar.OnTabDropOutside := @BarDropOutside;
  FBar.OnTabContextMenu := @BarContextMenu;
  BuildPopup;
end;

procedure TGroupTabs.Attach(AMgr: TDocumentManager; AGroup: Integer);
begin
  FMgr := AMgr;
  FGroup := AGroup;
end;

procedure TGroupTabs.SyncDim;
begin
  if FMgr <> nil then
    FBar.Dimmed := FMgr.Split and (FMgr.ActiveGroup <> FGroup);
end;

procedure TGroupTabs.Refresh;
begin
  SyncDim;
  FBar.RefreshBar;
end;

procedure TGroupTabs.Invalidate;
begin
  SyncDim;
  FBar.Invalidate;
end;

procedure TGroupTabs.SetRecordingIndex(AIndex: Integer);
begin
  if AIndex = FRecIndex then Exit;
  FRecIndex := AIndex;
  FBar.Invalidate;
end;

// -1 si l'onglet n'existe plus (liste changee depuis la derniere peinture)
function TGroupTabs.DocIndexOf(ATab: Integer): Integer;
var
  i, n: Integer;
begin
  Result := -1;
  if (FMgr = nil) or (ATab < 0) then Exit;
  n := 0;
  for i := 0 to FMgr.Count - 1 do
    if FMgr.Docs[i].Group = FGroup then
    begin
      if n = ATab then Exit(i);
      Inc(n);
    end;
end;

function TGroupTabs.BarCount(Sender: TObject): Integer;
var
  i: Integer;
begin
  Result := 0;
  if FMgr = nil then Exit;
  for i := 0 to FMgr.Count - 1 do
    if FMgr.Docs[i].Group = FGroup then Inc(Result);
end;

procedure TGroupTabs.BarInfo(Sender: TObject; AIndex: Integer; var AInfo: TDocTabInfo);
var
  di: Integer;
  doc: TDocument;
begin
  di := DocIndexOf(AIndex);
  if di < 0 then Exit;
  doc := FMgr.Docs[di];
  AInfo.Caption := doc.DisplayName;
  AInfo.Active := di = FMgr.GroupActiveIndex(FGroup);
  AInfo.Modified := doc.Modified;
  AInfo.ReadOnly := doc.ReadOnly;
  AInfo.Recording := di = FRecIndex;
end;

procedure TGroupTabs.BarActivate(Sender: TObject; AIndex: Integer);
begin
  FMgr.Activate(DocIndexOf(AIndex));
end;

procedure TGroupTabs.BarClose(Sender: TObject; AIndex: Integer);
begin
  FMgr.CloseDoc(DocIndexOf(AIndex));
end;

procedure TGroupTabs.BarNew(Sender: TObject);
begin
  if FMgr <> nil then FMgr.NewFile(FGroup);
end;

procedure TGroupTabs.BarMove(Sender: TObject; AIndex, ANewIndex: Integer);
begin
  FMgr.MoveDocInGroup(DocIndexOf(AIndex), ANewIndex);
end;

procedure TGroupTabs.BarDropOutside(Sender: TObject; AIndex: Integer;
  const AScreenPt: TPoint);
var
  di: Integer;
begin
  di := DocIndexOf(AIndex);
  if (di >= 0) and Assigned(FOnTabDrop) then
    FOnTabDrop(di, AScreenPt);
end;

procedure TGroupTabs.BarContextMenu(Sender: TObject; AIndex: Integer;
  const AScreenPt: TPoint);
var
  di: Integer;
begin
  // bande vide: pas de menu
  di := DocIndexOf(AIndex);
  if di < 0 then Exit;
  FCtxIndex := di;
  FMgr.Activate(di);
  FMoveItem.Visible := FMgr.Split;
  FPopup.PopUp(AScreenPt.X, AScreenPt.Y);
end;

procedure TGroupTabs.BuildPopup;

  function AddItem(const ACaption: string; AHandler: TNotifyEvent): TMenuItem;
  begin
    Result := TMenuItem.Create(FPopup);
    Result.Caption := ACaption;
    Result.OnClick := AHandler;
    FPopup.Items.Add(Result);
  end;

  procedure AddSep;
  var
    mi: TMenuItem;
  begin
    mi := TMenuItem.Create(FPopup);
    mi.Caption := '-';
    FPopup.Items.Add(mi);
  end;

begin
  FPopup := TPopupMenu.Create(Self);
  AddItem('Close Tab', @CtxClose);
  AddItem('Close Other Tabs', @CtxCloseOthers);
  AddItem('Close Tabs to the Right', @CtxCloseRight);
  AddItem('Close Unmodified Tabs', @CtxCloseUnmodified);
  AddSep;
  FMoveItem := AddItem('Move to Other Group', @CtxMoveGroup);
  AddItem('New File', @CtxNewFile);
  AddItem('Copy File Path', @CtxCopyPath);
end;

procedure TGroupTabs.CtxClose(Sender: TObject);
begin
  if (FCtxIndex >= 0) and (FCtxIndex < FMgr.Count) then FMgr.CloseDoc(FCtxIndex);
end;

procedure TGroupTabs.CtxCloseOthers(Sender: TObject);
begin
  if (FCtxIndex >= 0) and (FCtxIndex < FMgr.Count) then FMgr.CloseOthers(FCtxIndex);
end;

procedure TGroupTabs.CtxCloseRight(Sender: TObject);
begin
  if (FCtxIndex >= 0) and (FCtxIndex < FMgr.Count) then FMgr.CloseToRight(FCtxIndex);
end;

procedure TGroupTabs.CtxCloseUnmodified(Sender: TObject);
begin
  FMgr.CloseUnmodified(FGroup);
end;

procedure TGroupTabs.CtxNewFile(Sender: TObject);
begin
  FMgr.NewFile(FGroup);
end;

procedure TGroupTabs.CtxMoveGroup(Sender: TObject);
begin
  if (FCtxIndex >= 0) and (FCtxIndex < FMgr.Count) then FMgr.MoveToOtherGroup(FCtxIndex);
end;

procedure TGroupTabs.CtxCopyPath(Sender: TObject);
begin
  if (FCtxIndex >= 0) and (FCtxIndex < FMgr.Count) and
     not FMgr.Docs[FCtxIndex].Untitled then
    Clipboard.AsText := FMgr.Docs[FCtxIndex].FileName;
end;

end.
