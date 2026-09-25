unit uEditorView;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Controls, Forms, Graphics, StdCtrls, Clipbrd, LCLType,
  SynEdit, SynEditTypes, SynEditKeyCmds, SynEditMiscProcs, SynEditMouseCmds, uWrapView,
  SynGutterLineNumber, SynEditPointClasses, SynPluginMultiCaret, uTheme;

// La selection part dans le presse-papiers sur GESTE utilisateur seulement
// (souris, commande clavier de selection): les outils font SelectAll +
// SelText pour reecrire le document, ca n'est pas une copie voulue.
// X11: SynEdit publie aussi PRIMARY, et le clic milieu dans l'editeur colle
// le presse-papiers (usage terminal) plutot que PRIMARY.
{$IF defined(UNIX) and not defined(DARWIN)}
  {$DEFINE X11_PRIMARY}
{$ENDIF}

type
  // sous-classe pour atteindre le caret d'ecran (protected)
  TRTSynEdit = class(TSynEdit)
  private
    procedure CmdDone(Sender: TObject; AfterProcessing: Boolean;
      var Handled: Boolean; var Command: TSynEditorCommand;
      var AChar: TUTF8Char; Data: Pointer; HandlerData: Pointer);
  protected
    procedure DoEnter; override;
    procedure DoExit; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState;
      X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState;
      X, Y: Integer); override;
  public
    procedure HookCopyOnSelect;
    procedure CopySelection;
    procedure SetupSteadyCaret(AColor: TColor);
    // SynEdit n'a qu'une couleur de selection: on la swappe au focus
    procedure SyncSelectionFocus;
    procedure SetSelectionFocus(AFocused: Boolean);
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
  RTCopyOnSelect: Boolean = True;  // selection -> presse-papiers

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

procedure TRTSynEdit.SetSelectionFocus(AFocused: Boolean);
begin
  // la LCL envoie un CM_EXIT pendant la destruction, SelectedColor est deja libere -> AV
  if csDestroying in ComponentState then Exit;
  if AFocused then
    SelectedColor.Background := clSelectionBg
  else
    SelectedColor.Background := clSelectionInactive;
end;

procedure TRTSynEdit.SyncSelectionFocus;
begin
  SetSelectionFocus(Focused);
end;

// se fier a l'evenement, pas a Focused: sur Cocoa 4.8 le flag n'est pas
// encore pose quand DoEnter fire, la couleur active n'arrivait jamais
procedure TRTSynEdit.DoEnter;
begin
  inherited DoEnter;
  SetSelectionFocus(True);
end;

procedure TRTSynEdit.DoExit;
begin
  inherited DoExit;
  SetSelectionFocus(False);
end;

procedure TRTSynEdit.HookCopyOnSelect;
{$IFDEF X11_PRIMARY}
var
  i: Integer;
{$ENDIF}
begin
  RegisterCommandHandler(@CmdDone, nil, [hcfPostExec]);
  {$IFDEF X11_PRIMARY}
  // clic milieu = presse-papiers (MouseDown), pas PRIMARY: on retire l'action
  // native, sinon les deux collaient
  for i := MouseActions.Count - 1 downto 0 do
    if MouseActions.Items[i].Command = emcPasteSelection then
      MouseActions.Delete(i);
  {$ENDIF}
end;

procedure TRTSynEdit.MouseDown(Button: TMouseButton; Shift: TShiftState;
  X, Y: Integer);
begin
  inherited MouseDown(Button, Shift, X, Y);
  {$IFDEF X11_PRIMARY}
  if (Button = mbMiddle) and not ReadOnly and (Clipboard.AsText <> '') then
  begin
    if CanFocus then SetFocus;
    CaretXY := PixelsToRowColumn(Point(X, Y));
    BlockBegin := LogicalCaretXY;
    BlockEnd := BlockBegin;
    PasteFromClipboard;
  end;
  {$ENDIF}
end;

procedure TRTSynEdit.CopySelection;
begin
  if RTCopyOnSelect and SelAvail then
    Clipboard.AsText := SelText;
end;

// Shift+fleches, Ctrl+A clavier ou menu: toutes des commandes ecSel*
procedure TRTSynEdit.CmdDone(Sender: TObject; AfterProcessing: Boolean;
  var Handled: Boolean; var Command: TSynEditorCommand;
  var AChar: TUTF8Char; Data: Pointer; HandlerData: Pointer);
begin
  if AfterProcessing and (Command >= ecSelectionStart) and
     (Command <= ecSelectionEnd) then
    CopySelection;
end;

// glisser, double/triple clic, Shift+clic: la selection est faite au relachement
procedure TRTSynEdit.MouseUp(Button: TMouseButton; Shift: TShiftState;
  X, Y: Integer);
begin
  inherited MouseUp(Button, Shift, X, Y);
  if Button = mbLeft then
    CopySelection;
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
  TRTSynEdit(FSyn).HookCopyOnSelect;

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
  TRTSynEdit(FSyn).CopySelection; // geste menu/raccourci, pas un outil
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
  TRTSynEdit(FSyn).CopySelection;
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
