unit uMinimap;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Controls, Graphics, StdCtrls, Forms,
  SynEdit, SynEditTypes, SynEditMiscClasses, LazSynEditText, uTheme;

type
  // Second SynEdit minuscule en lecture seule, miroir de l'editeur actif.
  // Son buffer n'est PAS partage avec lui (voir Bind).
  TMinimap = class(TCustomControl)
  private
    FMini: TSynEdit;
    FEditor: TSynEdit;
    FDragging: Boolean;
    FRefreshQueued: Boolean;
    FPendingFull: Boolean;
    FNoHighlight: Boolean;
    procedure DoAsyncRefresh(Data: PtrInt);
    procedure EditorStatus(Sender: TObject; Changes: TSynStatusChanges);
    procedure LinesChanged(Sender: TSynEditStrings; aIndex, aCount: Integer);
    procedure LineCountChanged(Sender: TSynEditStrings; aIndex, aCount: Integer);
    procedure EditorCleared(Sender: TObject);
    procedure MiniSpecialLine(Sender: TObject; Line: integer; var Special: boolean;
      Markup: TSynSelectedColor);
    procedure SyncView;
    procedure JumpToY(Y: Integer);
    procedure UnbindInternal;
  protected
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure Bind(AEditor: TSynEdit);
    procedure RefreshContent;
    procedure QueueRefresh;
    procedure SyncHighlighter;
    procedure RefreshTheme;
    // a poser AVANT Bind, sinon le scan du buffer est paye deux fois
    property NoHighlight: Boolean read FNoHighlight write FNoHighlight;
  end;

implementation

type
  TSynAccess = class(TSynEdit); // expose ViewedTextBuffer (protege en 4.8)

  // Sous Cocoa un controle DESACTIVE avale les clics au lieu de les laisser
  // retomber sur le parent: la mini reste ACTIVE et relaie sa souris.
  TMiniSyn = class(TSynEdit)
  protected
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    function DoMouseWheel(Shift: TShiftState; WheelDelta: Integer;
      MousePos: TPoint): Boolean; override;
  end;

procedure TMiniSyn.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  if Parent is TMinimap then
    TMinimap(Parent).MouseDown(Button, Shift, X + Left, Y + Top);
end;

procedure TMiniSyn.MouseMove(Shift: TShiftState; X, Y: Integer);
begin
  if Parent is TMinimap then
    TMinimap(Parent).MouseMove(Shift, X + Left, Y + Top);
end;

procedure TMiniSyn.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  if Parent is TMinimap then
    TMinimap(Parent).MouseUp(Button, Shift, X + Left, Y + Top);
end;

function TMiniSyn.DoMouseWheel(Shift: TShiftState; WheelDelta: Integer;
  MousePos: TPoint): Boolean;
var
  ed: TSynEdit;
begin
  Result := True; // scroller la mini elle-meme desynchroniserait le viewport
  if Parent is TMinimap then
  begin
    ed := TMinimap(Parent).FEditor;
    if ed <> nil then
      TSynAccess(ed).DoMouseWheel(Shift, WheelDelta, MousePos);
  end;
end;

function Buf(AEd: TSynEdit): TSynEditStringsLinked; inline;
begin
  Result := TSynAccess(AEd).ViewedTextBuffer;
end;

constructor TMinimap.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  Width := 120;
  Color := clEditorBg;

  FMini := TMiniSyn.Create(Self);
  FMini.Parent := Self;
  FMini.Align := alClient;
  FMini.ReadOnly := True;
  FMini.Cursor := crDefault;
  FMini.BorderStyle := bsNone;
  FMini.ScrollBars := ssNone;
  FMini.Font.Quality := fqNonAntialiased;
  FMini.Color := clEditorBg;
  FMini.Gutter.Visible := False;
  FMini.TabStop := False;
  FMini.MouseActions.Clear;
  FMini.MouseSelActions.Clear;
  ApplyEditorTheme(FMini);
  // ApplyEditorTheme pose la taille de l'editeur: la mini la reforce a 2
  FMini.Font.Name := RTEditorFont;
  FMini.Font.Size := 2;
  FMini.RightEdge := 0;
  FMini.OnSpecialLineMarkup := @MiniSpecialLine;
end;

destructor TMinimap.Destroy;
begin
  Application.RemoveAsyncCalls(Self);
  UnbindInternal;
  FMini.Free;
  inherited Destroy;
end;

procedure TMinimap.RefreshTheme;
begin
  Color := clEditorBg;
  FMini.Color := clEditorBg;
  ApplyEditorTheme(FMini);
  FMini.Font.Name := RTEditorFont;
  FMini.Font.Size := 2;
  FMini.Invalidate;
  Invalidate;
end;

procedure TMinimap.UnbindInternal;
begin
  if FEditor <> nil then
  begin
    Buf(FEditor).RemoveChangeHandler(senrLineChange, @LinesChanged);
    Buf(FEditor).RemoveChangeHandler(senrLineCount, @LineCountChanged);
    Buf(FEditor).RemoveNotifyHandler(senrCleared, @EditorCleared);
    FEditor.UnRegisterStatusChangedHandler(@EditorStatus);
    FEditor.RemoveFreeNotification(Self);
    FEditor := nil;
  end;
  FPendingFull := False;
  FMini.Highlighter := nil;
  FMini.ClearAll;
end;

// Buffer propre, jamais partage: ShareTextBufferFrom sur un editeur qui a deja
// du contenu leve une AV dans SynEdit.
procedure TMinimap.Bind(AEditor: TSynEdit);
begin
  if FEditor = AEditor then Exit;
  UnbindInternal;
  FEditor := AEditor;
  if FEditor <> nil then
  begin
    FEditor.FreeNotification(Self);
    FEditor.RegisterStatusChangedHandler(@EditorStatus,
      [scTopLine, scLinesInWindow, scCaretY]);
    // miroir incremental: un Assign complet a chaque frappe re-tokenise tout le
    // doc (plusieurs secondes par rafale sur 1M lignes)
    Buf(FEditor).AddChangeHandler(senrLineChange, @LinesChanged);
    Buf(FEditor).AddChangeHandler(senrLineCount, @LineCountChanged);
    Buf(FEditor).AddNotifyHandler(senrCleared, @EditorCleared);
    RefreshContent;
  end;
end;

procedure TMinimap.RefreshContent;
begin
  if FEditor = nil then Exit;
  FPendingFull := False;
  if FNoHighlight then
    FMini.Highlighter := nil
  else
    FMini.Highlighter := FEditor.Highlighter;
  FMini.Lines.Assign(FEditor.Lines);
  SyncView;
end;

procedure TMinimap.LinesChanged(Sender: TSynEditStrings; aIndex, aCount: Integer);
var
  eb, mb: TSynEditStringsLinked;
  i, last: Integer;
begin
  if (FEditor = nil) or FPendingFull then Exit;
  eb := Buf(FEditor);
  mb := Buf(FMini);
  if mb.Count <> eb.Count then
  begin
    FPendingFull := True;
    QueueRefresh;
    Exit;
  end;
  if aIndex < 0 then aIndex := 0;
  last := aIndex + aCount - 1;
  if last > eb.Count - 1 then last := eb.Count - 1;
  mb.UndoList.Lock; // le mini ne doit pas accumuler d'undo
  try
    for i := aIndex to last do
      if mb[i] <> eb[i] then
        mb[i] := eb[i];
  finally
    mb.UndoList.Unlock;
  end;
end;

procedure TMinimap.LineCountChanged(Sender: TSynEditStrings; aIndex, aCount: Integer);
var
  eb, mb: TSynEditStringsLinked;
  i, idx: Integer;
  s: string;
begin
  if (FEditor = nil) or FPendingFull then Exit;
  eb := Buf(FEditor);
  mb := Buf(FMini);
  // changement massif (load/revert): resync complet coalesce, pas plus cher
  if (aCount > 5000) or (aCount < -5000) then
  begin
    FPendingFull := True;
    QueueRefresh;
    Exit;
  end;
  mb.UndoList.Lock;
  try
    if aCount > 0 then
      for i := 0 to aCount - 1 do
      begin
        idx := aIndex + i;
        if idx > mb.Count then idx := mb.Count;
        if aIndex + i < eb.Count then s := eb[aIndex + i] else s := '';
        mb.Insert(idx, s);
      end
    else
      for i := 1 to -aCount do
        if aIndex < mb.Count then
          mb.Delete(aIndex);
  finally
    mb.UndoList.Unlock;
  end;
  if mb.Count <> eb.Count then
  begin
    FPendingFull := True;
    QueueRefresh;
  end
  else
    SyncView;
end;

procedure TMinimap.EditorCleared(Sender: TObject);
begin
  if (FEditor = nil) or FPendingFull then Exit;
  FMini.ClearAll;
end;

procedure TMinimap.QueueRefresh;
begin
  if FRefreshQueued or (FEditor = nil) then Exit;
  FRefreshQueued := True;
  Application.QueueAsyncCall(@DoAsyncRefresh, 0);
end;

procedure TMinimap.DoAsyncRefresh(Data: PtrInt);
begin
  FRefreshQueued := False;
  RefreshContent;
end;

procedure TMinimap.SyncHighlighter;
begin
  if FEditor = nil then Exit;
  if FNoHighlight then
    FMini.Highlighter := nil
  else
    FMini.Highlighter := FEditor.Highlighter;
end;

procedure TMinimap.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited Notification(AComponent, Operation);
  if (Operation = opRemove) and (AComponent = FEditor) then
  begin
    // l'editeur meurt avec son buffer: ne PAS toucher aux handlers du buffer
    FMini.Highlighter := nil;
    FMini.ClearAll;
    FEditor := nil;
    FPendingFull := False;
  end;
end;

procedure TMinimap.EditorStatus(Sender: TObject; Changes: TSynStatusChanges);
begin
  SyncView;
end;

procedure TMinimap.SyncView;
var
  total, miniVis, edVis, maxTop: Integer;
begin
  if FEditor = nil then Exit;
  total := FEditor.Lines.Count;
  miniVis := FMini.LinesInWindow;
  edVis := FEditor.LinesInWindow;
  if total <= miniVis then
    FMini.TopLine := 1
  else
  begin
    maxTop := total - miniVis + 1;
    if total - edVis > 0 then
      // Int64 obligatoire: le produit deborde 2^31 des ~46000 lignes scrollees
      FMini.TopLine := 1 + Round((FEditor.TopLine - 1) * Int64(maxTop - 1) / (total - edVis))
    else
      FMini.TopLine := 1;
    if FMini.TopLine < 1 then FMini.TopLine := 1;
    if FMini.TopLine > maxTop then FMini.TopLine := maxTop;
  end;
  FMini.Invalidate;
end;

procedure TMinimap.MiniSpecialLine(Sender: TObject; Line: integer;
  var Special: boolean; Markup: TSynSelectedColor);
begin
  if (FEditor <> nil) and (Line >= FEditor.TopLine)
     and (Line < FEditor.TopLine + FEditor.LinesInWindow) then
  begin
    Special := True;
    Markup.Background := clMinimapViewport;
    Markup.Foreground := clNone; // garder la coloration syntaxique des tokens
  end;
end;

procedure TMinimap.JumpToY(Y: Integer);
var
  line: Integer;
begin
  if FEditor = nil then Exit;
  line := FMini.TopLine + (Y div FMini.LineHeight);
  FEditor.TopLine := line - FEditor.LinesInWindow div 2;
  if FEditor.CanFocus then
    FEditor.SetFocus;
end;

procedure TMinimap.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseDown(Button, Shift, X, Y);
  if Button = mbLeft then
  begin
    FDragging := True;
    JumpToY(Y);
  end;
end;

procedure TMinimap.MouseMove(Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseMove(Shift, X, Y);
  if FDragging then
    JumpToY(Y);
end;

procedure TMinimap.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseUp(Button, Shift, X, Y);
  FDragging := False;
end;

end.
