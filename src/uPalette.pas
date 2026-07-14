unit uPalette;

{$mode objfpc}{$H+}

// Command palette. Les commandes sont collectees a l'ouverture en marchant les
// popups de la menu bar: pas de registre de commandes a maintenir.

interface

uses
  Classes, SysUtils, Controls, Graphics, StdCtrls, Menus, LCLType, LCLProc,
  Types, uTheme, uFuzzy, uMenuBar;

type
  TPalCmd = record
    Path: string;   // "File > Save As..."
    Sc: string;
    Item: TMenuItem;
  end;

  TPalHit = record
    Cmd: Integer;   // index dans FCmds
    Score: Integer;
    Pos: TFuzzyPos;
  end;

  TCommandPalette = class(TCustomControl)
  private
    FEdit: TEdit;
    FCmds: array of TPalCmd;
    FCount: Integer;
    FHits: array of TPalHit;
    FSel, FTop: Integer;
    FClosing: Boolean;
    FOnRestoreFocus: TNotifyEvent;
    procedure CollectFrom(AItem: TMenuItem; const APrefix: string);
    procedure SortHits;
    procedure Refilter;
    procedure UpdateLayout;
    procedure EnsureVisible;
    procedure Execute(AIndex: Integer);
    procedure EditChanged(Sender: TObject);
    procedure EditKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure EditKeyPress(Sender: TObject; var Key: Char);
    procedure EditExited(Sender: TObject);
    function RowAt(Y: Integer): Integer;
  protected
    procedure Paint; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    function DoMouseWheel(Shift: TShiftState; WheelDelta: Integer;
      MousePos: TPoint): Boolean; override;
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
  public
    constructor Create(AOwner: TComponent); override;
    procedure OpenPalette(ABar: TRTMenuBar);
    procedure ClosePalette;
    procedure RefreshTheme;
    property OnRestoreFocus: TNotifyEvent read FOnRestoreFocus write FOnRestoreFocus;
  end;

implementation

const
  PAD      = 6;
  EDIT_H   = 26;
  ROW_H    = 22;
  MAX_ROWS = 12;
  PAL_W    = 560;

constructor TCommandPalette.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  Visible := False;
  Color := clSideBg;
  Font.Name := RTFontName;
  Font.Size := 9;
  Font.Quality := fqCleartype;
  FEdit := TEdit.Create(Self);
  FEdit.Parent := Self;
  FEdit.AutoSize := False; // sinon boucle ChangeBounds (voir uFindBar)
  FEdit.BorderStyle := bsNone;
  FEdit.Color := clEditorBg;
  FEdit.Font.Name := RTFontName;
  FEdit.Font.Size := 10;
  FEdit.Font.Quality := fqCleartype;
  FEdit.Font.Color := clEditorFg;
  FEdit.OnChange := @EditChanged;
  FEdit.OnKeyDown := @EditKeyDown;
  FEdit.OnKeyPress := @EditKeyPress;
  FEdit.OnExit := @EditExited;
end;

procedure TCommandPalette.RefreshTheme;
begin
  Color := clSideBg;
  FEdit.Color := clEditorBg;
  FEdit.Font.Color := clEditorFg;
  Invalidate;
end;

procedure TCommandPalette.CollectFrom(AItem: TMenuItem; const APrefix: string);
var
  i: Integer;
  c: TMenuItem;
begin
  for i := 0 to AItem.Count - 1 do
  begin
    c := AItem[i];
    if (c.Caption = '-') or not c.Visible or not c.Enabled then Continue;
    if c.Count > 0 then
      CollectFrom(c, APrefix + c.Caption + ' > ')
    else if Assigned(c.OnClick) then
    begin
      if FCount >= Length(FCmds) then
        SetLength(FCmds, Length(FCmds) * 2 + 64);
      FCmds[FCount].Path := APrefix + c.Caption;
      if c.ShortCut <> 0 then
        FCmds[FCount].Sc := ShortCutToText(c.ShortCut)
      else
        FCmds[FCount].Sc := '';
      FCmds[FCount].Item := c;
      // les items d'Open Recent sont liberes si le menu File pope pendant que la
      // palette est ouverte
      c.FreeNotification(Self);
      Inc(FCount);
    end;
  end;
end;

procedure TCommandPalette.Notification(AComponent: TComponent; Operation: TOperation);
var
  i: Integer;
begin
  inherited Notification(AComponent, Operation);
  if Operation = opRemove then
    for i := 0 to FCount - 1 do
      if FCmds[i].Item = AComponent then
        FCmds[i].Item := nil;
end;

// ordre total (score desc puis index de collecte): tri deterministe
procedure TCommandPalette.SortHits;

  function Less(const A, B: TPalHit): Boolean;
  begin
    if A.Score <> B.Score then Exit(A.Score > B.Score);
    Result := A.Cmd < B.Cmd;
  end;

  procedure QSort(L, R: Integer);
  var
    i, j: Integer;
    p, t: TPalHit;
  begin
    while L < R do
    begin
      p := FHits[(L + R) div 2];
      i := L;
      j := R;
      repeat
        while Less(FHits[i], p) do Inc(i);
        while Less(p, FHits[j]) do Dec(j);
        if i <= j then
        begin
          t := FHits[i]; FHits[i] := FHits[j]; FHits[j] := t;
          Inc(i);
          Dec(j);
        end;
      until i > j;
      if j - L < R - i then
      begin
        QSort(L, j);
        L := i;
      end
      else
      begin
        QSort(i, R);
        R := j;
      end;
    end;
  end;

begin
  if Length(FHits) > 1 then
    QSort(0, High(FHits));
end;

procedure TCommandPalette.Refilter;
var
  i, n, sc: Integer;
  ps: TFuzzyPos;
begin
  SetLength(FHits, FCount);
  n := 0;
  for i := 0 to FCount - 1 do
    if FuzzyMatch(FEdit.Text, FCmds[i].Path, sc, ps) then
    begin
      FHits[n].Cmd := i;
      FHits[n].Score := sc;
      FHits[n].Pos := ps;
      Inc(n);
    end;
  SetLength(FHits, n);
  SortHits;
  FSel := 0;
  FTop := 0;
  UpdateLayout;
  Invalidate;
end;

procedure TCommandPalette.UpdateLayout;
var
  shown: Integer;
begin
  shown := Length(FHits);
  if shown > MAX_ROWS then shown := MAX_ROWS;
  if shown = 0 then shown := 1;
  Height := PAD + EDIT_H + PAD + shown * ROW_H + PAD;
end;

procedure TCommandPalette.EnsureVisible;
begin
  if FSel < FTop then FTop := FSel;
  if FSel >= FTop + MAX_ROWS then FTop := FSel - MAX_ROWS + 1;
  if FTop < 0 then FTop := 0;
end;

procedure TCommandPalette.OpenPalette(ABar: TRTMenuBar);
var
  i, w: Integer;
begin
  if (Parent = nil) or (ABar = nil) then Exit;
  SetLength(FCmds, 0);
  FCount := 0;
  ABar.RefreshRecent;
  for i := 0 to ABar.MenuCount - 1 do
    CollectFrom(ABar.MenuRoot(i), ABar.MenuTitle(i) + ' > ');
  SetLength(FCmds, FCount);

  w := PAL_W;
  if w > Parent.ClientWidth - 40 then w := Parent.ClientWidth - 40;
  if w < 220 then w := 220;
  SetBounds((Parent.ClientWidth - w) div 2, 30, w, 100);
  FEdit.SetBounds(PAD + 4, PAD + 2, w - 2 * PAD - 8, EDIT_H - 4);
  FEdit.Text := '';
  Refilter;
  Visible := True;
  BringToFront;
  HandleNeeded;
  if FEdit.CanFocus then FEdit.SetFocus;
end;

procedure TCommandPalette.ClosePalette;
begin
  // reentrance: rendre le focus a l'editeur declenche le OnExit du TEdit
  if FClosing or not Visible then Exit;
  FClosing := True;
  try
    Visible := False;
    if Assigned(FOnRestoreFocus) then
      FOnRestoreFocus(Self);
  finally
    FClosing := False;
  end;
end;

procedure TCommandPalette.Execute(AIndex: Integer);
var
  mi: TMenuItem;
begin
  if (AIndex < 0) or (AIndex >= Length(FHits)) then Exit;
  mi := FCmds[FHits[AIndex].Cmd].Item;
  if mi = nil then Exit;
  ClosePalette; // focus rendu AVANT le handler: les actions lisent l'editeur actif
  mi.Click;
end;

procedure TCommandPalette.EditChanged(Sender: TObject);
begin
  if Visible then Refilter;
end;

procedure TCommandPalette.EditKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  case Key of
    VK_ESCAPE: begin ClosePalette; Key := 0; end;
    VK_RETURN: begin Execute(FSel); Key := 0; end;
    VK_DOWN:
      begin
        if FSel < High(FHits) then Inc(FSel);
        EnsureVisible;
        Invalidate;
        Key := 0;
      end;
    VK_UP:
      begin
        if FSel > 0 then Dec(FSel);
        EnsureVisible;
        Invalidate;
        Key := 0;
      end;
    VK_NEXT, VK_PRIOR:
      begin
        if Key = VK_NEXT then Inc(FSel, MAX_ROWS) else Dec(FSel, MAX_ROWS);
        if FSel > High(FHits) then FSel := High(FHits);
        if FSel < 0 then FSel := 0;
        EnsureVisible;
        Invalidate;
        Key := 0;
      end;
    VK_P:
      if (ssModifier in Shift) and (ssShift in Shift) then
      begin
        ClosePalette;
        Key := 0;
      end;
  end;
end;

procedure TCommandPalette.EditKeyPress(Sender: TObject; var Key: Char);
begin
  if Key in [#13, #27] then Key := #0; // pas de bip
end;

procedure TCommandPalette.EditExited(Sender: TObject);
begin
  if not FClosing then
    ClosePalette;
end;

function TCommandPalette.RowAt(Y: Integer): Integer;
var
  y0, idx: Integer;
begin
  Result := -1;
  y0 := PAD + EDIT_H + PAD;
  if Y < y0 then Exit;
  idx := FTop + (Y - y0) div ROW_H;
  if (idx >= FTop) and (idx < FTop + MAX_ROWS) and (idx <= High(FHits)) then
    Result := idx;
end;

procedure TCommandPalette.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  r: Integer;
begin
  inherited MouseDown(Button, Shift, X, Y);
  if Button <> mbLeft then Exit;
  r := RowAt(Y);
  if r >= 0 then
  begin
    FSel := r;
    Execute(r);
  end;
end;

procedure TCommandPalette.MouseMove(Shift: TShiftState; X, Y: Integer);
var
  r: Integer;
begin
  inherited MouseMove(Shift, X, Y);
  r := RowAt(Y);
  if (r >= 0) and (r <> FSel) then
  begin
    FSel := r;
    Invalidate;
  end;
end;

function TCommandPalette.DoMouseWheel(Shift: TShiftState; WheelDelta: Integer;
  MousePos: TPoint): Boolean;
var
  maxTop: Integer;
begin
  maxTop := Length(FHits) - MAX_ROWS;
  if maxTop < 0 then maxTop := 0;
  if WheelDelta > 0 then Dec(FTop, 3) else Inc(FTop, 3);
  if FTop > maxTop then FTop := maxTop;
  if FTop < 0 then FTop := 0;
  Invalidate;
  Result := True;
end;

procedure TCommandPalette.Paint;
var
  i, y, ty, listTop, shown, scW, x: Integer;
  hit: TPalHit;
  rowBg, baseCol, hiCol: TColor;
  r: TRect;
  s, run: string;
  bi, bj: SizeInt;
  pi: Integer;
  m: Boolean;
  trackH, thumbH, thumbY: Integer;
begin
  Canvas.Font := Font;
  Canvas.Brush.Color := clSideBg;
  Canvas.FillRect(ClientRect);
  Canvas.Pen.Color := clFindOutline;
  Canvas.Frame(ClientRect);
  Canvas.Pen.Color := clBorder;
  Canvas.Frame(Rect(PAD, PAD, ClientWidth - PAD, PAD + EDIT_H));
  Canvas.Brush.Color := clEditorBg;
  Canvas.FillRect(Rect(PAD + 1, PAD + 1, ClientWidth - PAD - 1, PAD + EDIT_H - 1));

  listTop := PAD + EDIT_H + PAD;
  shown := Length(FHits) - FTop;
  if shown > MAX_ROWS then shown := MAX_ROWS;

  if Length(FHits) = 0 then
  begin
    Canvas.Brush.Style := bsClear;
    Canvas.Font.Color := clStatusText;
    Canvas.TextOut(PAD + 6, listTop + (ROW_H - Canvas.TextHeight('Ag')) div 2,
      'no matching command');
    Canvas.Brush.Style := bsSolid;
    Exit;
  end;

  for i := 0 to shown - 1 do
  begin
    hit := FHits[FTop + i];
    y := listTop + i * ROW_H;
    r := Rect(1, y, ClientWidth - 1, y + ROW_H);
    if FTop + i = FSel then rowBg := clSideSel else rowBg := clSideBg;
    Canvas.Brush.Color := rowBg;
    Canvas.FillRect(r);
    if FTop + i = FSel then baseCol := clSideTextHi else baseCol := clSideText;
    hiCol := clCaret;
    ty := y + (ROW_H - Canvas.TextHeight('Ag')) div 2;
    Canvas.Brush.Style := bsClear;
    s := FCmds[hit.Cmd].Path;
    x := PAD + 6;
    bi := 1;
    pi := 0;
    while bi <= Length(s) do
    begin
      m := (pi <= High(hit.Pos)) and (hit.Pos[pi] = bi);
      bj := bi;
      while (bj <= Length(s)) and
            (((pi <= High(hit.Pos)) and (hit.Pos[pi] = bj)) = m) do
      begin
        if m then Inc(pi);
        Inc(bj);
      end;
      run := Copy(s, bi, bj - bi);
      if m then Canvas.Font.Color := hiCol else Canvas.Font.Color := baseCol;
      Canvas.TextOut(x, ty, run);
      Inc(x, Canvas.TextWidth(run));
      bi := bj;
      if x > ClientWidth then Break;
    end;
    // le raccourci se repeint PAR-DESSUS un chemin trop long
    if FCmds[hit.Cmd].Sc <> '' then
    begin
      scW := Canvas.TextWidth(FCmds[hit.Cmd].Sc);
      Canvas.Brush.Style := bsSolid;
      Canvas.Brush.Color := rowBg;
      Canvas.FillRect(Rect(ClientWidth - scW - 20, y, ClientWidth - 1, y + ROW_H));
      Canvas.Brush.Style := bsClear;
      Canvas.Font.Color := clStatusText;
      Canvas.TextOut(ClientWidth - scW - 12, ty, FCmds[hit.Cmd].Sc);
    end;
    Canvas.Brush.Style := bsSolid;
  end;

  if Length(FHits) > MAX_ROWS then
  begin
    trackH := MAX_ROWS * ROW_H;
    thumbH := trackH * MAX_ROWS div Length(FHits);
    if thumbH < 20 then thumbH := 20;
    thumbY := listTop + (trackH - thumbH) * FTop div (Length(FHits) - MAX_ROWS);
    Canvas.Brush.Color := clFindOutline;
    Canvas.FillRect(Rect(ClientWidth - 6, thumbY, ClientWidth - 3, thumbY + thumbH));
  end;
end;

end.
