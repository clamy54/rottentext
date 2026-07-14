unit uTabBar;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Controls, Graphics, Menus, Clipbrd, LCLType, LCLIntf,
  ExtCtrls, uDocumentManager, uDocument, uTheme;

type
  TTabSlot = record
    DocIndex: Integer;
    Full: TRect;
    Close: TRect;
  end;

  // drop hors de la barre: uMain hit-teste le pane cible
  TTabDropEvent = procedure(ADocIndex: Integer; const AScreenPt: TPoint) of object;

  // Une barre par groupe. Un index de slot n'est PAS un index de doc.
  TTabBar = class(TCustomControl)
  private
    FMgr: TDocumentManager;
    FGroup: Integer;
    FSlots: array of TTabSlot;
    FScroll: Integer;
    FHoverTab: Integer;   // index de slot
    FHoverClose: Integer;
    FLeftArrow, FRightArrow, FPlus: TRect;
    FShowArrows: Boolean;
    FTabsLeft, FTabsRight: Integer;
    FContentW: Integer;
    FPopup: TPopupMenu;
    FMoveItem: TMenuItem;
    FCtxIndex: Integer;   // index de DOC
    FRecIndex: Integer;   // index de DOC
    FBlinkOn: Boolean;
    FBlink: TTimer;
    FDragDoc: Integer;    // index de DOC
    FDragStartX: Integer;
    FDragX: Integer;
    FDragging: Boolean;
    FOnTabDrop: TTabDropEvent;
    procedure BlinkTick(Sender: TObject);
    procedure BuildLayout;
    function GapIndex(X: Integer): Integer;
    function DropTargetPos(X, ADragDoc: Integer): Integer;
    function GapX(AGap: Integer): Integer;
    procedure DrawTab(ASlot: Integer);
    procedure DrawGlyphClose(const R: TRect; AColor: TColor);
    procedure DrawGlyphPlus(const R: TRect; AColor: TColor);
    procedure DrawGlyphArrow(const R: TRect; ALeft: Boolean; AColor: TColor);
    procedure DrawDot(const R: TRect; AColor: TColor);
    procedure DrawGlyphLock(const R: TRect; AColor: TColor);
    function TabAt(X: Integer; out AClose: Boolean): Integer;
    procedure ClampScroll;
    procedure EnsureVisible(ADocIndex: Integer);
    procedure BuildPopup;
    procedure CtxClose(Sender: TObject);
    procedure CtxCloseOthers(Sender: TObject);
    procedure CtxCloseRight(Sender: TObject);
    procedure CtxCloseUnmodified(Sender: TObject);
    procedure CtxNewFile(Sender: TObject);
    procedure CtxCopyPath(Sender: TObject);
    procedure CtxMoveGroup(Sender: TObject);
  protected
    procedure Paint; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseLeave; override;
    function DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure Attach(AMgr: TDocumentManager; AGroup: Integer = 0);
    procedure Refresh;
    procedure RefreshTheme;
    procedure SetRecordingIndex(AIndex: Integer);
    property OnTabDrop: TTabDropEvent read FOnTabDrop write FOnTabDrop;
  end;

implementation

const
  TAB_MAXW = 220;
  TAB_MINW = 90;
  PADX     = 11;
  CLOSE_SZ = 16;
  ARROW_W  = 24;
  PLUS_W   = 34;
  DOT_D    = 8;
  DRAG_THRESH = 6;

constructor TTabBar.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FHoverTab := -1;
  FHoverClose := -1;
  FScroll := 0;
  FCtxIndex := -1;
  FRecIndex := -1;
  FDragDoc := -1;
  FBlink := TTimer.Create(Self);
  FBlink.Interval := 500;
  FBlink.Enabled := False;
  FBlink.OnTimer := @BlinkTick;
  Font.Name := RTTabFont;
  Font.Size := RTTabSize;
  Font.Quality := fqCleartype;
  BuildPopup;
end;

procedure TTabBar.RefreshTheme;
begin
  Font.Name := RTTabFont;
  Font.Size := RTTabSize;
  Invalidate;
end;

destructor TTabBar.Destroy;
begin
  FPopup.Free;
  inherited Destroy;
end;

procedure TTabBar.Attach(AMgr: TDocumentManager; AGroup: Integer);
begin
  FMgr := AMgr;
  FGroup := AGroup;
end;

procedure TTabBar.Refresh;
begin
  if FMgr <> nil then
    EnsureVisible(FMgr.GroupActiveIndex(FGroup));
  Invalidate;
end;

procedure TTabBar.SetRecordingIndex(AIndex: Integer);
begin
  if AIndex = FRecIndex then Exit;
  FRecIndex := AIndex;
  FBlinkOn := True;
  FBlink.Enabled := AIndex >= 0;
  Invalidate;
end;

procedure TTabBar.BlinkTick(Sender: TObject);
begin
  FBlinkOn := not FBlinkOn;
  Invalidate;
end;

procedure TTabBar.BuildPopup;

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

procedure TTabBar.CtxClose(Sender: TObject);
begin
  if (FCtxIndex >= 0) and (FCtxIndex < FMgr.Count) then FMgr.CloseDoc(FCtxIndex);
end;

procedure TTabBar.CtxCloseOthers(Sender: TObject);
begin
  if (FCtxIndex >= 0) and (FCtxIndex < FMgr.Count) then FMgr.CloseOthers(FCtxIndex);
end;

procedure TTabBar.CtxCloseRight(Sender: TObject);
begin
  if (FCtxIndex >= 0) and (FCtxIndex < FMgr.Count) then FMgr.CloseToRight(FCtxIndex);
end;

procedure TTabBar.CtxCloseUnmodified(Sender: TObject);
begin
  FMgr.CloseUnmodified(FGroup);
end;

procedure TTabBar.CtxNewFile(Sender: TObject);
begin
  FMgr.NewFile(FGroup);
end;

procedure TTabBar.CtxMoveGroup(Sender: TObject);
begin
  if (FCtxIndex >= 0) and (FCtxIndex < FMgr.Count) then FMgr.MoveToOtherGroup(FCtxIndex);
end;

procedure TTabBar.CtxCopyPath(Sender: TObject);
begin
  if (FCtxIndex >= 0) and (FCtxIndex < FMgr.Count) and
     not FMgr.Docs[FCtxIndex].Untitled then
    Clipboard.AsText := FMgr.Docs[FCtxIndex].FileName;
end;

procedure TTabBar.ClampScroll;
var
  maxScroll: Integer;
begin
  maxScroll := FContentW - (FTabsRight - FTabsLeft);
  if maxScroll < 0 then maxScroll := 0;
  if FScroll > maxScroll then FScroll := maxScroll;
  if FScroll < 0 then FScroll := 0;
end;

procedure TTabBar.BuildLayout;

  function TabW(const ACap: string): Integer;
  begin
    Result := Canvas.TextWidth(ACap) + PADX * 2 + CLOSE_SZ + 6;
    if Result > TAB_MAXW then Result := TAB_MAXW;
    if Result < TAB_MINW then Result := TAB_MINW;
  end;

var
  i, x, tw, slot, n: Integer;
begin
  SetLength(FSlots, 0);
  if FMgr = nil then Exit;
  Canvas.Font := Font;

  FPlus := Rect(ClientWidth - PLUS_W, 0, ClientWidth, ClientHeight);

  FContentW := 0;
  n := 0;
  for i := 0 to FMgr.Count - 1 do
    if FMgr.Docs[i].Group = FGroup then
    begin
      Inc(FContentW, TabW(FMgr.Docs[i].DisplayName));
      Inc(n);
    end;

  FTabsLeft := 0;
  FTabsRight := FPlus.Left;
  FShowArrows := FContentW > (FTabsRight - FTabsLeft);
  if FShowArrows then
  begin
    FLeftArrow := Rect(0, 0, ARROW_W, ClientHeight);
    FRightArrow := Rect(ARROW_W, 0, ARROW_W * 2, ClientHeight);
    FTabsLeft := ARROW_W * 2;
  end;

  ClampScroll;

  SetLength(FSlots, n);
  slot := 0;
  x := FTabsLeft - FScroll;
  for i := 0 to FMgr.Count - 1 do
  begin
    if FMgr.Docs[i].Group <> FGroup then Continue;
    tw := TabW(FMgr.Docs[i].DisplayName);
    FSlots[slot].DocIndex := i;
    FSlots[slot].Full := Rect(x, 0, x + tw, ClientHeight);
    FSlots[slot].Close := Rect(x + tw - CLOSE_SZ - 6,
      (ClientHeight - CLOSE_SZ) div 2, x + tw - 6,
      (ClientHeight - CLOSE_SZ) div 2 + CLOSE_SZ);
    Inc(x, tw);
    Inc(slot);
  end;
end;

function TTabBar.GapIndex(X: Integer): Integer;
var
  i, mid: Integer;
begin
  for i := 0 to High(FSlots) do
  begin
    mid := (FSlots[i].Full.Left + FSlots[i].Full.Right) div 2;
    if X < mid then Exit(i);
  end;
  Result := Length(FSlots);
end;

// le doc est retire avant reinsertion: un gap au-dela de sa position decale de 1
function TTabBar.DropTargetPos(X, ADragDoc: Integer): Integer;
var
  gap, cur, i: Integer;
begin
  BuildLayout;
  gap := GapIndex(X);
  cur := 0;
  // ADragDoc en parametre: MouseUp a deja remis FDragDoc a -1
  for i := 0 to High(FSlots) do
    if FSlots[i].DocIndex = ADragDoc then
    begin
      cur := i;
      Break;
    end;
  if gap > cur then Result := gap - 1 else Result := gap;
end;

function TTabBar.GapX(AGap: Integer): Integer;
begin
  if Length(FSlots) = 0 then
    Result := FTabsLeft
  else if AGap <= 0 then
    Result := FSlots[0].Full.Left
  else if AGap > High(FSlots) then
    Result := FSlots[High(FSlots)].Full.Right
  else
    Result := FSlots[AGap].Full.Left;
end;

procedure TTabBar.EnsureVisible(ADocIndex: Integer);
var
  s, i, slotLeft, slotRight, viewW: Integer;
begin
  BuildLayout;
  s := -1;
  for i := 0 to High(FSlots) do
    if FSlots[i].DocIndex = ADocIndex then
    begin
      s := i;
      Break;
    end;
  if s < 0 then Exit;
  viewW := FTabsRight - FTabsLeft;
  slotLeft := FSlots[s].Full.Left - (FTabsLeft - FScroll);
  slotRight := FSlots[s].Full.Right - (FTabsLeft - FScroll);
  if slotLeft < FScroll then
    FScroll := slotLeft
  else if slotRight > FScroll + viewW then
    FScroll := slotRight - viewW;
  ClampScroll;
end;

procedure TTabBar.DrawGlyphClose(const R: TRect; AColor: TColor);
var
  m: Integer;
begin
  Canvas.Pen.Color := AColor;
  Canvas.Pen.Width := 1;
  m := 4;
  Canvas.Line(R.Left + m, R.Top + m, R.Right - m, R.Bottom - m);
  Canvas.Line(R.Right - m, R.Top + m, R.Left + m, R.Bottom - m);
end;

procedure TTabBar.DrawGlyphPlus(const R: TRect; AColor: TColor);
var
  cx, cy, s: Integer;
begin
  cx := (R.Left + R.Right) div 2;
  cy := (R.Top + R.Bottom) div 2;
  s := 6;
  Canvas.Pen.Color := AColor;
  Canvas.Pen.Width := 1;
  Canvas.Line(cx - s, cy, cx + s + 1, cy);
  Canvas.Line(cx, cy - s, cx, cy + s + 1);
end;

procedure TTabBar.DrawGlyphArrow(const R: TRect; ALeft: Boolean; AColor: TColor);
var
  cx, cy, s: Integer;
begin
  cx := (R.Left + R.Right) div 2;
  cy := (R.Top + R.Bottom) div 2;
  s := 4;
  Canvas.Brush.Color := AColor;
  Canvas.Pen.Color := AColor;
  if ALeft then
    Canvas.Polygon([Point(cx + s, cy - s), Point(cx - s, cy), Point(cx + s, cy + s)])
  else
    Canvas.Polygon([Point(cx - s, cy - s), Point(cx + s, cy), Point(cx - s, cy + s)]);
end;

procedure TTabBar.DrawDot(const R: TRect; AColor: TColor);
begin
  Canvas.Brush.Color := AColor;
  Canvas.Pen.Color := AColor;
  Canvas.Ellipse(R.Left, R.Top, R.Left + DOT_D, R.Top + DOT_D);
end;

procedure TTabBar.DrawGlyphLock(const R: TRect; AColor: TColor);
var
  cx, cy: Integer;
begin
  cx := (R.Left + R.Right) div 2;
  cy := (R.Top + R.Bottom) div 2;
  Canvas.Pen.Color := AColor;
  Canvas.Brush.Style := bsClear;
  Canvas.Arc(cx - 3, cy - 6, cx + 3, cy + 1, 0, 180 * 16);
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := AColor;
  Canvas.FillRect(cx - 5, cy - 2, cx + 5, cy + 6);
end;

procedure TTabBar.DrawTab(ASlot: Integer);
var
  doc: TDocument;
  r: TRect;
  active, hovered, groupFocused: Boolean;
  cap: string;
  bg, iconCol: TColor;
  ty, availW: Integer;
begin
  doc := FMgr.Docs[FSlots[ASlot].DocIndex];
  r := FSlots[ASlot].Full;
  active := FSlots[ASlot].DocIndex = FMgr.GroupActiveIndex(FGroup);
  hovered := ASlot = FHoverTab;
  groupFocused := (not FMgr.Split) or (FMgr.ActiveGroup = FGroup);

  if active and groupFocused then bg := clTabActive
  else if active then bg := clTabActiveDim
  else if hovered then bg := clTabHover
  else bg := clTabInactive;
  Canvas.Brush.Color := bg;
  Canvas.Pen.Color := bg;
  // coins bas rejetes sous la barre: seuls les coins hauts s'arrondissent
  Canvas.RoundRect(r.Left, r.Top, r.Right, ClientHeight + 8, 7, 7);

  if active and not groupFocused then
    Canvas.Font.Color := clTabActiveTextDim
  else if active or hovered then
    Canvas.Font.Color := clTabActiveText
  else
    Canvas.Font.Color := clTabInactiveText;
  Canvas.Brush.Style := bsClear;
  cap := doc.DisplayName;
  availW := (r.Right - PADX - CLOSE_SZ - 6) - (r.Left + PADX);
  while (Canvas.TextWidth(cap) > availW) and (Length(cap) > 1) do
    cap := Copy(cap, 1, Length(cap) - 1);
  if cap <> doc.DisplayName then
    cap := Copy(cap, 1, Length(cap) - 1) + '…';
  ty := (ClientHeight - Canvas.TextHeight('Ag')) div 2;
  Canvas.TextOut(r.Left + PADX, ty, cap);
  Canvas.Brush.Style := bsSolid;

  if active or hovered then iconCol := clTabIconHi else iconCol := clTabIcon;
  if (FSlots[ASlot].DocIndex = FRecIndex) and not hovered then
  begin
    if FBlinkOn then
      DrawDot(Rect(FSlots[ASlot].Close.Left + (CLOSE_SZ - DOT_D) div 2,
        (ClientHeight - DOT_D) div 2, 0, 0), clMacroRec);
  end
  else if doc.ReadOnly and not hovered then
  begin
    if doc.Modified then
      DrawGlyphLock(FSlots[ASlot].Close, clTabLockMod)
    else
      DrawGlyphLock(FSlots[ASlot].Close, clTabLock);
  end
  else if doc.Modified and not hovered then
    DrawDot(Rect(FSlots[ASlot].Close.Left + (CLOSE_SZ - DOT_D) div 2,
      (ClientHeight - DOT_D) div 2, 0, 0), iconCol)
  else
    DrawGlyphClose(FSlots[ASlot].Close, iconCol);
end;

procedure TTabBar.Paint;
var
  i, mx: Integer;
begin
  BuildLayout;

  Canvas.Brush.Color := clTabStrip;
  Canvas.FillRect(ClientRect);

  for i := 0 to High(FSlots) do
    if (FSlots[i].Full.Right > FTabsLeft) and (FSlots[i].Full.Left < FTabsRight) then
      DrawTab(i);

  if FShowArrows then
  begin
    Canvas.Brush.Color := clTabStrip;
    Canvas.FillRect(Rect(0, 0, FTabsLeft, ClientHeight));
    DrawGlyphArrow(FLeftArrow, True, clTabGlyph);
    DrawGlyphArrow(FRightArrow, False, clTabGlyph);
    Canvas.Pen.Color := clBorder;
    Canvas.Line(FTabsLeft - 1, 4, FTabsLeft - 1, ClientHeight - 4);
  end;

  Canvas.Brush.Color := clTabStrip;
  Canvas.FillRect(FPlus);
  DrawGlyphPlus(FPlus, clTabGlyph);

  // marqueur d'insertion pendant un drag
  if FDragging and (FDragX >= 0) and (FDragX < ClientWidth) then
  begin
    mx := GapX(GapIndex(FDragX));
    if mx < FTabsLeft then mx := FTabsLeft;
    if mx > FTabsRight then mx := FTabsRight;
    Canvas.Pen.Color := clCaret;
    Canvas.Pen.Width := 2;
    Canvas.Line(mx, 3, mx, ClientHeight - 3);
    Canvas.Pen.Width := 1;
  end;
end;

function TTabBar.TabAt(X: Integer; out AClose: Boolean): Integer;
var
  i: Integer;
begin
  AClose := False;
  Result := -1;
  for i := 0 to High(FSlots) do
    if (X >= FSlots[i].Full.Left) and (X < FSlots[i].Full.Right)
       and (X >= FTabsLeft) and (X < FTabsRight) then
    begin
      Result := i;
      AClose := (X >= FSlots[i].Close.Left) and (X < FSlots[i].Close.Right);
      Exit;
    end;
end;

procedure TTabBar.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  idx: Integer;
  onClose: Boolean;
  p: TPoint;
begin
  inherited MouseDown(Button, Shift, X, Y);
  if FMgr = nil then Exit;
  FDragDoc := -1;
  FDragging := False;

  if FShowArrows and PtInRect(FLeftArrow, Point(X, Y)) then
  begin
    Dec(FScroll, 120); ClampScroll; Invalidate; Exit;
  end;
  if FShowArrows and PtInRect(FRightArrow, Point(X, Y)) then
  begin
    Inc(FScroll, 120); ClampScroll; Invalidate; Exit;
  end;
  if PtInRect(FPlus, Point(X, Y)) then
  begin
    FMgr.NewFile(FGroup); Exit;
  end;

  idx := TabAt(X, onClose);
  if idx < 0 then
  begin
    if ssDouble in Shift then FMgr.NewFile(FGroup);
    Exit;
  end;

  idx := FSlots[idx].DocIndex;
  if Button = mbLeft then
  begin
    if onClose then
      FMgr.CloseDoc(idx)
    else
    begin
      FMgr.Activate(idx);
      FDragDoc := idx;
      FDragStartX := X;
    end;
  end
  else if Button = mbMiddle then
    FMgr.CloseDoc(idx)
  else if Button = mbRight then
  begin
    FCtxIndex := idx;
    FMgr.Activate(idx);
    FMoveItem.Visible := FMgr.Split;
    p := ClientToScreen(Point(X, Y));
    FPopup.PopUp(p.X, p.Y);
  end;
end;

procedure TTabBar.MouseMove(Shift: TShiftState; X, Y: Integer);
var
  idx, oldTab, oldClose: Integer;
  onClose: Boolean;
begin
  inherited MouseMove(Shift, X, Y);
  // la capture souris LCL garde MouseMove/MouseUp ici meme hors bornes
  if (FDragDoc >= 0) and (ssLeft in Shift) and not FDragging then
    if Abs(X - FDragStartX) > DRAG_THRESH then
    begin
      FDragging := True;
      Cursor := crDrag;
    end;
  if FDragging then
  begin
    FDragX := X;
    Invalidate;
    Exit;
  end;

  oldTab := FHoverTab;
  oldClose := FHoverClose;
  idx := TabAt(X, onClose);
  FHoverTab := idx;
  if onClose then FHoverClose := idx else FHoverClose := -1;
  if (oldTab <> FHoverTab) or (oldClose <> FHoverClose) then
    Invalidate;
end;

procedure TTabBar.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  d: Integer;
begin
  inherited MouseUp(Button, Shift, X, Y);
  if FDragging then
  begin
    FDragging := False;
    Cursor := crDefault;
    d := FDragDoc;
    FDragDoc := -1;
    if d >= 0 then
    begin
      if (X >= 0) and (X < ClientWidth) and (Y >= 0) and (Y < ClientHeight) then
        FMgr.MoveDocInGroup(d, DropTargetPos(X, d))
      else if Assigned(FOnTabDrop) then
        FOnTabDrop(d, ClientToScreen(Point(X, Y)));
    end;
    Invalidate;
  end
  else
    FDragDoc := -1;
end;

procedure TTabBar.MouseLeave;
begin
  inherited MouseLeave;
  if (FHoverTab <> -1) or (FHoverClose <> -1) then
  begin
    FHoverTab := -1;
    FHoverClose := -1;
    Invalidate;
  end;
end;

function TTabBar.DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean;
begin
  Result := True;
  if not FShowArrows then Exit;
  if WheelDelta > 0 then Dec(FScroll, 60) else Inc(FScroll, 60);
  ClampScroll;
  Invalidate;
end;

end.
