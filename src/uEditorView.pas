unit uEditorView;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Controls, Forms, Graphics, StdCtrls,
  SynEdit, SynEditTypes, SynEditKeyCmds, SynEditMiscProcs, uWrapView,
  SynGutterLineNumber, SynEditPointClasses, SynPluginMultiCaret, uTheme;

type
  // sous-classe pour atteindre le caret d'ecran (protected)
  TRTSynEdit = class(TSynEdit)
  protected
    procedure DoEnter; override;
    procedure DoExit; override;
  public
    procedure SetupSteadyCaret(AColor: TColor);
    // SynEdit n'a qu'une couleur de selection: on la swappe au focus
    procedure SyncSelectionFocus;
  end;

  // AddCaretAtLogPos (public) ne survit pas: seul le chemin interne
  // (AddCaret + SelectionObj) marche, d'ou l'acces aux protected
  TRTMultiCaret = class(TSynPluginMultiCaret)
  public
    procedure SelectionToCarets;
  end;

  TEditorView = class
  private
    FSyn: TSynEdit;
    FWrap: TLazSynEditLineWrapPlugin;
    FMulti: TRTMultiCaret;
    FLineNum: TSynGutterLineNumber;
    FLargeFile: Boolean;
    FOnChange: TNotifyEvent;
    procedure InternalChange(Sender: TObject);
    function GutterWidthChars: Integer;
    procedure UpdateGutterWidth;
    procedure FormatLineNumber(Sender: TSynGutterLineNumber; ALine: Integer;
      out AText: string; const ALineInfo: TSynEditGutterLineInfo);
  public
    // ALargeFile doit etre connu AVANT la creation: le plugin wrap est
    // impossible a retirer apres coup, il ne faut donc jamais le creer
    constructor Create(AParent: TWinControl; ALargeFile: Boolean = False);
    destructor Destroy; override;
    procedure ShowView;
    procedure HideView;
    procedure ApplyViewSettings;
    procedure RefreshTheme;
    procedure MultiClear;
    procedure MultiSplitLines;
    procedure MultiAddLine(ADelta: Integer); // -1 = ligne au-dessus, +1 = dessous
    procedure ExpandToLine;
    procedure ExpandToWord;
    property Syn: TSynEdit read FSyn;
    property LargeFile: Boolean read FLargeFile write FLargeFile;
    property OnChange: TNotifyEvent read FOnChange write FOnChange;
  end;

// Reglages du menu View, globaux (pas par vue).
var
  RTTabWidth: Integer = 4;
  RTWordWrap: Boolean = True;
  RTWrapColumn: Integer = 0; // 0 = auto (largeur fenetre, pas de regle)
  RTShowInvisibles: Boolean = False;
  RTMapTabToSpace: Boolean = True; // a decocher pour editer un Makefile

implementation

// copie du handler souris natif emcPluginMultiCaretSelectionToCarets
procedure TRTMultiCaret.SelectionToCarets;
var
  i, j: Integer;
begin
  if not SelectionObj.SelAvail then Exit;
  j := SelectionObj.LastLineBytePos.y;
  i := SelectionObj.FirstLineBytePos.y;
  if i = j then Exit;
  SelectionObj.Clear;
  CaretObj.LineBytePos := Point(Length(ViewedTextBuffer[ToIdx(j)]) + 1, j);
  while i < j do
  begin
    AddCaret(Length(ViewedTextBuffer[ToIdx(i)]) + 1, i, 0);
    Inc(i);
  end;
  if CaretsCount > 0 then
    ActiveMode := DefaultMode;
end;

procedure TRTSynEdit.SyncSelectionFocus;
begin
  // la LCL envoie un CM_EXIT pendant la destruction, SelectedColor est deja libere -> AV
  if csDestroying in ComponentState then Exit;
  if Focused then
    SelectedColor.Background := clSelectionBg
  else
    SelectedColor.Background := clSelectionInactive;
end;

procedure TRTSynEdit.DoEnter;
begin
  inherited DoEnter;
  SyncSelectionFocus;
end;

procedure TRTSynEdit.DoExit;
begin
  inherited DoExit;
  SyncSelectionFocus;
end;

procedure TRTSynEdit.SetupSteadyCaret(AColor: TColor);
begin
  ScreenCaret.ChangePainter(TSynEditScreenCaretPainterInternal);
  if ScreenCaret.Painter is TSynEditScreenCaretPainterInternal then
    TSynEditScreenCaretPainterInternal(ScreenCaret.Painter).Color := AColor;
  ScreenCaret.PaintTimer.Interval := 0;
end;

constructor TEditorView.Create(AParent: TWinControl; ALargeFile: Boolean);
var
  i: Integer;
begin
  FLargeFile := ALargeFile;
  // tout configurer SANS parent, attacher en dernier: sinon le controle est
  // realise petit puis redimensionne (flicker a l'ouverture d'onglet)
  FSyn := TRTSynEdit.Create(AParent);
  FSyn.Visible := False;
  FSyn.BorderStyle := bsNone;
  FSyn.Font.Name := RTEditorFont;
  FSyn.Font.Size := RTEditorSize;
  FSyn.Font.Quality := fqCleartype;
  FSyn.ScrollBars := ssNone; // scrollbar verticale custom (uScrollbar)
  FMulti := TRTMultiCaret.Create(FSyn);
  FMulti.Color := clCaret;
  ApplyEditorTheme(FSyn);
  TRTSynEdit(FSyn).SyncSelectionFocus;
  ApplyViewSettings;

  for i := 0 to FSyn.Gutter.Parts.Count - 1 do
    if FSyn.Gutter.Parts[i] is TSynGutterLineNumber then
      FLineNum := TSynGutterLineNumber(FSyn.Gutter.Parts[i]);
  if FLineNum <> nil then
  begin
    FLineNum.OnFormatLineNumber := @FormatLineNumber;
    UpdateGutterWidth;
  end;

  // un SynEdit neuf a 0 ligne: sans ca le "1" du gutter n'apparait qu'a la 1re frappe
  if FSyn.Lines.Count = 0 then
    FSyn.Lines.Add('');

  FSyn.OnChange := @InternalChange;

  FSyn.Align := alClient;
  AParent.DisableAlign;
  FSyn.Parent := AParent;
  FSyn.BoundsRect := AParent.ClientRect;
  AParent.EnableAlign;

  TRTSynEdit(FSyn).SetupSteadyCaret(clCaret);
end;

destructor TEditorView.Destroy;
begin
  // liberer l'editeur declenche OnChange / un paint du gutter: ces handlers liraient FSyn detruit
  FSyn.OnChange := nil;
  if FLineNum <> nil then
    FLineNum.OnFormatLineNumber := nil;
  FSyn.Free;
  inherited Destroy;
end;

// 2 de marge + numero + 2 espaces: la cellule inversee de la ligne courante
// doit remplir toute la colonne
function TEditorView.GutterWidthChars: Integer;
begin
  Result := Length(IntToStr(FSyn.Lines.Count)) + 4;
  if Result < 6 then Result := 6;
end;

procedure TEditorView.UpdateGutterWidth;
begin
  FLineNum.DigitCount := GutterWidthChars;
end;

procedure TEditorView.FormatLineNumber(Sender: TSynGutterLineNumber;
  ALine: Integer; out AText: string; const ALineInfo: TSynEditGutterLineInfo);
var
  num: string;
  field: Integer;
begin
  num := IntToStr(ALine);
  field := GutterWidthChars - 2;
  while Length(num) < field do
    num := ' ' + num;
  AText := num + '  ';
end;

procedure TEditorView.RefreshTheme;
begin
  ApplyEditorTheme(FSyn);
  // ApplyEditorTheme pose la couleur "focus": re-attenuer derriere
  TRTSynEdit(FSyn).SyncSelectionFocus;
  FMulti.Color := clCaret;
  TRTSynEdit(FSyn).SetupSteadyCaret(clCaret);
  FSyn.Invalidate;
end;

procedure TEditorView.ApplyViewSettings;
const
  // detruire le plugin wrap a chaud = AV: "wrap off" = colonne enorme
  NOWRAP_COL = 100000;
begin
  FSyn.TabWidth := RTTabWidth;
  // le plugin wrap valide son layout de facon SYNCHRONE sur tout le buffer
  // (156 Mo = 7 s): jamais cree pour une vue nee gros fichier
  if (FWrap = nil) and not FLargeFile then
    FWrap := TLazSynEditLineWrapPlugin.Create(FSyn);
  if FWrap <> nil then
  begin
    if RTWordWrap and not FLargeFile then
      FWrap.FixedWrapColumn := RTWrapColumn
    else
      FWrap.FixedWrapColumn := NOWRAP_COL;
  end;
  if RTMapTabToSpace then
    FSyn.Options := FSyn.Options + [eoTabsToSpaces]
  else
    FSyn.Options := FSyn.Options - [eoTabsToSpaces];
  // VisibleSpecialChars ne rend RIEN sans eoShowSpecialChars
  if RTShowInvisibles then
  begin
    FSyn.VisibleSpecialChars := [vscSpace, vscTabAtLast];
    FSyn.Options := FSyn.Options + [eoShowSpecialChars];
  end
  else
    FSyn.Options := FSyn.Options - [eoShowSpecialChars];
  if RTWordWrap and (RTWrapColumn > 0) then
  begin
    FSyn.RightEdge := RTWrapColumn;
    FSyn.RightEdgeColor := clRightEdge;
    FSyn.Options := FSyn.Options - [eoHideRightMargin];
  end
  else
    FSyn.Options := FSyn.Options + [eoHideRightMargin];
end;

procedure TEditorView.MultiClear;
begin
  FSyn.CommandProcessor(ecPluginMultiCaretClearAll, '', nil);
end;

procedure TEditorView.MultiSplitLines;
begin
  FMulti.SelectionToCarets;
end;

procedure TEditorView.MultiAddLine(ADelta: Integer);
begin
  if (FSyn.CaretY + ADelta < 1) or (FSyn.CaretY + ADelta > FSyn.Lines.Count) then Exit;
  // marquer le caret puis bouger PAR COMMANDE: un CaretXY direct ne survit pas
  FSyn.CommandProcessor(ecPluginMultiCaretSetCaret, '', nil);
  if ADelta < 0 then
    FSyn.CommandProcessor(ecUp, '', nil)
  else
    FSyn.CommandProcessor(ecDown, '', nil);
end;

procedure TEditorView.ExpandToLine;
var
  b, e: TPoint;
begin
  if FSyn.SelAvail then
  begin
    b := FSyn.BlockBegin;
    e := FSyn.BlockEnd;
  end
  else
  begin
    b := FSyn.PhysicalToLogicalPos(FSyn.CaretXY);
    e := b;
  end;
  FSyn.BlockBegin := Point(1, b.Y);
  if e.Y < FSyn.Lines.Count then
    FSyn.BlockEnd := Point(1, e.Y + 1) // englobe le saut de ligne
  else
    FSyn.BlockEnd := Point(Length(FSyn.Lines[e.Y - 1]) + 1, e.Y);
  FSyn.CaretXY := FSyn.LogicalToPhysicalPos(FSyn.BlockEnd);
end;

// 1er appui: le mot sous le caret; suivants: l'occurrence suivante
procedure TEditorView.ExpandToWord;
begin
  if not FSyn.SelAvail then
    FSyn.SelectWord
  else
  begin
    if FSyn.SearchReplace(FSyn.SelText, '', [ssoMatchCase, ssoFindContinue]) = 0 then
      FSyn.SearchReplace(FSyn.SelText, '', [ssoMatchCase, ssoEntireScope]); // wrap
  end;
end;

procedure TEditorView.InternalChange(Sender: TObject);
begin
  if FLineNum <> nil then
    UpdateGutterWidth;
  if Assigned(FOnChange) then
    FOnChange(FSyn);
end;

procedure TEditorView.ShowView;
var
  frm: TCustomForm;
begin
  FSyn.Visible := True;
  FSyn.BringToFront;
  // recalculer le gutter maintenant que les metriques de police sont valides
  if FLineNum <> nil then
  begin
    FLineNum.DigitCount := 2;
    UpdateGutterWidth;
  end;
  FSyn.Invalidate;
  frm := GetParentForm(FSyn);
  if (frm <> nil) and frm.Visible and FSyn.CanFocus then
    FSyn.SetFocus;
end;

procedure TEditorView.HideView;
begin
  FSyn.Visible := False;
end;

end.
