unit uScrollbar;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Controls, Graphics, SynEdit, SynEditTypes, uTheme;

type
  // Scrollbar verticale custom pilotant le TopLine de l'editeur lie.
  TVScrollbar = class(TCustomControl)
  private
    FEditor: TSynEdit;
    FDragging: Boolean;
    FDragOffset: Integer;
    FHover: Boolean;
    function ThumbRect: TRect;
    procedure EditorStatus(Sender: TObject; Changes: TSynStatusChanges);
    procedure ScrollToThumbTop(AThumbTop: Integer);
  protected
    procedure Paint; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseLeave; override;
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
  public
    constructor Create(AOwner: TComponent); override;
    procedure Bind(AEditor: TSynEdit);
  end;

implementation

constructor TVScrollbar.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  Width := 14;
  Color := clEditorBg;
end;

procedure TVScrollbar.Bind(AEditor: TSynEdit);
begin
  if FEditor = AEditor then Exit;
  if FEditor <> nil then
  begin
    FEditor.UnRegisterStatusChangedHandler(@EditorStatus);
    FEditor.RemoveFreeNotification(Self);
  end;
  FEditor := AEditor;
  if FEditor <> nil then
  begin
    FEditor.FreeNotification(Self);
    FEditor.RegisterStatusChangedHandler(@EditorStatus, [scTopLine, scLinesInWindow]);
  end;
  Invalidate;
end;

procedure TVScrollbar.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited Notification(AComponent, Operation);
  if (Operation = opRemove) and (AComponent = FEditor) then
    FEditor := nil;
end;

procedure TVScrollbar.EditorStatus(Sender: TObject; Changes: TSynStatusChanges);
begin
  Invalidate;
end;

function TVScrollbar.ThumbRect: TRect;
var
  total, vis, h, thumbTop, thumbH: Integer;
begin
  Result := Rect(0, 0, 0, 0);
  if FEditor = nil then Exit;
  total := FEditor.Lines.Count;
  if total < 1 then total := 1;
  vis := FEditor.LinesInWindow;
  h := ClientHeight;
  if (vis >= total) or (h <= 0) then Exit; // tout tient: pas de thumb
  thumbH := Round(vis / total * h);
  if thumbH < 24 then thumbH := 24;
  // inverse exact de ScrollToThumbTop, sinon le thumb decroche quand thumbH
  // est clampe a 24
  thumbTop := Round((FEditor.TopLine - 1) / (total - vis) * (h - thumbH));
  if thumbTop + thumbH > h then thumbTop := h - thumbH;
  if thumbTop < 0 then thumbTop := 0;
  Result := Rect(3, thumbTop, ClientWidth - 3, thumbTop + thumbH);
end;

procedure TVScrollbar.Paint;
var
  r: TRect;
  c: TColor;
begin
  Canvas.Brush.Color := clEditorBg;
  Canvas.FillRect(ClientRect);
  r := ThumbRect;
  if r.Bottom > r.Top then
  begin
    if FHover or FDragging then c := clTabStrip else c := clTabHover;
    Canvas.Brush.Color := c;
    Canvas.Pen.Color := c;
    Canvas.RoundRect(r.Left, r.Top, r.Right, r.Bottom, 6, 6);
  end;
end;

procedure TVScrollbar.ScrollToThumbTop(AThumbTop: Integer);
var
  total, vis, h, thumbH: Integer;
  frac: Double;
begin
  if FEditor = nil then Exit;
  total := FEditor.Lines.Count;
  if total < 1 then total := 1;
  vis := FEditor.LinesInWindow;
  h := ClientHeight;
  thumbH := Round(vis / total * h);
  if thumbH < 24 then thumbH := 24;
  if h - thumbH <= 0 then Exit;
  frac := AThumbTop / (h - thumbH);
  if frac < 0 then frac := 0;
  if frac > 1 then frac := 1;
  FEditor.TopLine := 1 + Round(frac * (total - vis));
end;

procedure TVScrollbar.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  r: TRect;
begin
  inherited MouseDown(Button, Shift, X, Y);
  if (FEditor = nil) or (Button <> mbLeft) then Exit;
  r := ThumbRect;
  if (Y >= r.Top) and (Y < r.Bottom) then
  begin
    FDragging := True;
    FDragOffset := Y - r.Top;
  end
  else
  begin
    if Y < r.Top then
      FEditor.TopLine := FEditor.TopLine - FEditor.LinesInWindow
    else
      FEditor.TopLine := FEditor.TopLine + FEditor.LinesInWindow;
  end;
end;

procedure TVScrollbar.MouseMove(Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseMove(Shift, X, Y);
  if FDragging then
    ScrollToThumbTop(Y - FDragOffset)
  else if not FHover then
  begin
    FHover := True;
    Invalidate;
  end;
end;

procedure TVScrollbar.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseUp(Button, Shift, X, Y);
  FDragging := False;
end;

procedure TVScrollbar.MouseLeave;
begin
  inherited MouseLeave;
  if FHover then
  begin
    FHover := False;
    Invalidate;
  end;
end;

end.
