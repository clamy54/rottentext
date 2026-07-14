unit uFindBar;

{$mode objfpc}{$H+}

// Barre Find/Replace, sans regex. SynEdit n'a ni preserve case ni recherche
// bornee a une region: faits main (SearchReplaceEx + bornes).
// Doc hex: recherche dans la THexView, replace refuse une autre longueur.

interface

uses
  Classes, SysUtils, Types, Controls, Graphics, StdCtrls, Forms, ExtCtrls,
  LCLType, LCLIntf, LazUTF8, SynEdit, SynEditTypes, uTheme, uDocumentManager,
  uDocument, uHexView;

type
  TMatchInfoEvent = procedure(const AInfo: string) of object;

  TFindBar = class(TCustomControl)
  private
    FMgr: TDocumentManager;
    FOnMatchInfo: TMatchInfoEvent;
    FFindEdit, FReplaceEdit: TEdit;
    FReplaceMode: Boolean;
    FOptCase, FOptWord, FOptWrap, FOptInSel, FOptHighlight, FOptPreserve: Boolean;
    FOptHexSeq: Boolean;  // motif = sequence d'octets ('DE AD BE EF')
    FSelB, FSelE: TPoint; // region "in selection"
    FBound: TSynEdit;     // editeur qui porte le highlight de recherche
    FActiveRef: TSynEdit;
    FNotFound: Boolean;
    FToggleR: array[0..4] of TRect; // Aa, "", wrap, insel, highlight
    FPresR: TRect;
    FBtnR: array[0..3] of TRect;    // Find, Find Prev, Replace, Replace All
    FCloseR: TRect;
    FHot: Integer; // -1 rien, 0..4 toggles, 5 AB, 10..13 boutons, 20 croix
    // hints a la main: l'API LCL ne bascule pas la bulle entre zones d'un
    // meme controle
    FHintWin: THintWindow;
    FHintTimer: TTimer;
    FHintShown: Boolean;
    procedure HintTimerTick(Sender: TObject);
    procedure ShowZoneHint;
    procedure HideZoneHint;
    function ActiveSyn: TSynEdit;
    function ActiveHex: THexView;
    function InHexMode: Boolean;
    function HexPattern(const S: string; out ABytes: TBytes): Boolean;
    function MarkMatches(AHex: THexView; const APat: TBytes): Boolean;
    procedure HexFind(ABack: Boolean; AFrom: Int64 = -1);
    procedure HexReplaceNext;
    procedure HexReplaceAll;
    function BaseOptions: TSynSearchOptions;
    function CmpPt(const A, B: TPoint): Integer;
    procedure RecountMatches;
    function SelMatches(syn: TSynEdit): Boolean;
    function ApplyCase(const AMatch, ARepl: string): string;
    function FindFrom(syn: TSynEdit; const AStart: TPoint; ABack: Boolean): Boolean;
    procedure CaptureRegion;
    procedure UpdateLayout;
    procedure BindHighlightTarget(ASyn: TSynEdit);
    procedure UpdateHighlight;
    procedure SetNotFound(AValue: Boolean);
    procedure EditKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure EditChange(Sender: TObject);
    function HitTest(X, Y: Integer): Integer;
    function HintFor(AItem: Integer): string;
    procedure DrawButton(const R: TRect; const ACaption: string; AHot: Boolean);
    procedure DrawToggle(AIdx: Integer; const R: TRect; AOn, AHot: Boolean);
  protected
    procedure Paint; override;
    procedure Resize; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseLeave; override;
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
  public
    constructor Create(AOwner: TComponent); override;
    procedure Attach(AMgr: TDocumentManager);
    procedure ActiveDocChanged;
    procedure RefreshTheme;
    procedure ShowFind;
    procedure ShowReplace;
    procedure HideBar;
    procedure FindNext;
    procedure FindPrev;
    procedure ReplaceNext;
    procedure ReplaceAll;
    property OnMatchInfo: TMatchInfoEvent read FOnMatchInfo write FOnMatchInfo;
  end;

implementation

const
  ROW_H  = 34;
  TGL_SZ = 24;
  PAD    = 5;

constructor TFindBar.Create(AOwner: TComponent);

  function MakeEdit: TEdit;
  begin
    Result := TEdit.Create(Self);
    Result.Parent := Self;
    // sans ca le TEdit re-impose sa hauteur: "ChangeBounds loop detected"
    Result.AutoSize := False;
    Result.BorderStyle := bsNone;
    Result.Color := clBorder;
    Result.Font.Name := RTFontName;
    Result.Font.Size := 10;
    Result.Font.Quality := fqCleartype;
    Result.Font.Color := clEditorFg;
    Result.OnKeyDown := @EditKeyDown;
    Result.OnChange := @EditChange;
  end;

begin
  inherited Create(AOwner);
  Color := clStatusBg;
  Height := ROW_H;
  Visible := False;
  FHot := -1;
  FOptWrap := True;
  FOptHighlight := True;
  FHintTimer := TTimer.Create(Self);
  FHintTimer.Enabled := False;
  FHintTimer.Interval := 500;
  FHintTimer.OnTimer := @HintTimerTick;
  Font.Name := RTFontName;
  Font.Size := 9;
  Font.Quality := fqCleartype;
  FFindEdit := MakeEdit;
  FReplaceEdit := MakeEdit;
  FReplaceEdit.Visible := False;
end;

procedure TFindBar.RefreshTheme;
begin
  Color := clStatusBg;
  FFindEdit.Color := clBorder;
  FFindEdit.Font.Color := clEditorFg;
  FReplaceEdit.Color := clBorder;
  FReplaceEdit.Font.Color := clEditorFg;
  Invalidate;
end;

procedure TFindBar.Attach(AMgr: TDocumentManager);
begin
  FMgr := AMgr;
end;

function TFindBar.ActiveSyn: TSynEdit;
begin
  // le SynEdit d'un doc hex est cache et vide: ne jamais chercher dedans
  if (FMgr <> nil) and (FMgr.ActiveDoc <> nil) and not FMgr.ActiveDoc.IsHex then
    Result := FMgr.ActiveDoc.View.Syn
  else
    Result := nil;
end;

function TFindBar.ActiveHex: THexView;
begin
  if (FMgr <> nil) and (FMgr.ActiveDoc <> nil) and FMgr.ActiveDoc.IsHex then
    Result := FMgr.ActiveDoc.HexView
  else
    Result := nil;
end;

function TFindBar.InHexMode: Boolean;
begin
  Result := ActiveHex <> nil;
end;

function TFindBar.BaseOptions: TSynSearchOptions;
begin
  Result := [];
  if FOptCase then Include(Result, ssoMatchCase);
  if FOptWord then Include(Result, ssoWholeWord);
end;

// ------------------------------------------------------------ recherche hex

// repli de casse ASCII seulement, comme le moteur de uHexView
function FoldA(AB: Byte): Byte; inline;
begin
  if (AB >= Ord('a')) and (AB <= Ord('z')) then Result := AB - 32 else Result := AB;
end;

function TFindBar.HexPattern(const S: string; out ABytes: TBytes): Boolean;
var
  i: Integer;
begin
  if FOptHexSeq then Exit(ParseHexBytes(S, ABytes));
  ABytes := nil;
  SetLength(ABytes, Length(S));
  for i := 1 to Length(S) do
    ABytes[i - 1] := Ord(S[i]);
  Result := Length(ABytes) > 0;
end;

// le mark colle-t-il encore au motif? une ancre perimee sauterait des matches
function TFindBar.MarkMatches(AHex: THexView; const APat: TBytes): Boolean;
var
  cur: TBytes;
  i: Integer;
  exact: Boolean;
begin
  Result := False;
  if (AHex.MarkLen <> Length(APat)) or (Length(APat) = 0) then Exit;
  cur := AHex.ReadOverlaid(AHex.MarkOfs, AHex.MarkLen);
  if Length(cur) <> Length(APat) then Exit;
  exact := FOptCase or FOptHexSeq;
  for i := 0 to High(APat) do
    if (exact and (cur[i] <> APat[i])) or
       ((not exact) and (FoldA(cur[i]) <> FoldA(APat[i]))) then Exit;
  Result := True;
end;

procedure TFindBar.HexFind(ABack: Boolean; AFrom: Int64);
var
  hx: THexView;
  pat: TBytes;
  from, found: Int64;
begin
  hx := ActiveHex;
  if (hx = nil) or (FFindEdit.Text = '') then Exit;
  if not HexPattern(FFindEdit.Text, pat) then
  begin
    SetNotFound(True);
    Exit;
  end;
  if AFrom >= 0 then
    from := AFrom
  // ancre = le match courant, seulement s'il tient toujours et que le caret
  // est encore dessus
  else if (hx.CaretOfs = hx.MarkOfs) and MarkMatches(hx, pat) then
  begin
    if ABack then from := hx.MarkOfs - 1 else from := hx.MarkOfs + 1;
  end
  else
    from := hx.CaretOfs;
  found := hx.FindPattern(pat, from, ABack, FOptCase or FOptHexSeq);
  if (found < 0) and FOptWrap then
  begin
    if ABack then from := hx.FileSize - 1 else from := 0;
    found := hx.FindPattern(pat, from, ABack, FOptCase or FOptHexSeq);
  end;
  if found >= 0 then
  begin
    hx.GotoOffset(found);
    hx.SetMark(found, Length(pat));
  end;
  SetNotFound(found < 0);
end;

procedure TFindBar.HexReplaceNext;
var
  hx: THexView;
  pat, rep: TBytes;
  from: Int64;
begin
  hx := ActiveHex;
  if (hx = nil) or (FFindEdit.Text = '') then Exit;
  // ecrasement: le remplacement doit faire exactement la longueur du motif
  if not HexPattern(FFindEdit.Text, pat) or
     not HexPattern(FReplaceEdit.Text, rep) or
     (Length(rep) <> Length(pat)) then
  begin
    SetNotFound(True);
    Exit;
  end;
  // reprendre APRES le match ecrase: MarkOfs+1 pourrait re-matcher dedans
  if (hx.CaretOfs = hx.MarkOfs) and MarkMatches(hx, pat) then
  begin
    hx.WriteBytes(hx.MarkOfs, rep);
    from := hx.MarkOfs + Length(pat);
    hx.SetMark(-1, 0);
    HexFind(False, from);
  end
  else
    HexFind(False);
end;

procedure TFindBar.HexReplaceAll;
const
  FLUSH_AT = 1024 * 1024; // borne memoire du lot d'edits
var
  hx: THexView;
  pat, rep, cur: TBytes;
  batch: array of TByteEdit;
  from, found: Int64;
  n, k, i: Integer;
begin
  hx := ActiveHex;
  if (hx = nil) or (FFindEdit.Text = '') then Exit;
  if not HexPattern(FFindEdit.Text, pat) or
     not HexPattern(FReplaceEdit.Text, rep) or
     (Length(rep) <> Length(pat)) then
  begin
    SetNotFound(True);
    Exit;
  end;
  // lot trie applique en bloc: un WriteBytes par match serait quadratique
  n := 0;
  k := 0;
  batch := nil;
  from := 0;
  repeat
    found := hx.FindPattern(pat, from, False, FOptCase or FOptHexSeq);
    if found < 0 then Break;
    cur := hx.ReadOverlaid(found, Length(rep));
    for i := 0 to High(rep) do
      if (i < Length(cur)) and (cur[i] <> rep[i]) then
      begin
        if k >= Length(batch) then
          SetLength(batch, (k + Length(rep)) * 2);
        batch[k].Ofs := found + i;
        batch[k].Val := rep[i];
        Inc(k);
      end;
    Inc(n);
    from := found + Length(pat); // meme longueur: rien ne se decale
    if k >= FLUSH_AT then
    begin
      SetLength(batch, k);
      hx.ApplySortedEdits(batch);
      batch := nil;
      k := 0;
    end;
  until False;
  SetLength(batch, k);
  hx.ApplySortedEdits(batch);
  hx.SetMark(-1, 0);
  SetNotFound(n = 0);
end;

// ------------------------------------------------------------- layout/paint

procedure TFindBar.UpdateLayout;
var
  x, y, w, btnW, editR, lblW: Integer;
begin
  // Canvas sans handle (barre cachee au boot) = "Control has no parent window"
  if not HandleAllocated then Exit;
  Canvas.Font := Font;
  btnW := Canvas.TextWidth('Replace All') + 24;
  x := PAD;
  y := (ROW_H - TGL_SZ) div 2;
  for w := 0 to 4 do
  begin
    FToggleR[w] := Rect(x, y, x + TGL_SZ, y + TGL_SZ);
    Inc(x, TGL_SZ + 3);
  end;
  Inc(x, 7);
  lblW := 0;
  if FReplaceMode then
    lblW := Canvas.TextWidth('Replace:') + 8;
  FCloseR := Rect(ClientWidth - 24, 5, ClientWidth - 6, 23);
  editR := ClientWidth - 30 - btnW - btnW - 16;
  w := editR - x - lblW;
  if w < 68 then
  begin
    w := 68;
    editR := x + lblW + w;
  end;
  if FFindEdit.BoundsRect <> Bounds(x + lblW + 4, y + 3, w - 8, TGL_SZ - 6) then
    FFindEdit.SetBounds(x + lblW + 4, y + 3, w - 8, TGL_SZ - 6);
  FBtnR[0] := Rect(editR + 8, y, editR + 8 + btnW, y + TGL_SZ);
  FBtnR[1] := Rect(FBtnR[0].Right + 6, y, FBtnR[0].Right + 6 + btnW, y + TGL_SZ);
  if FReplaceMode then
  begin
    y := ROW_H + (ROW_H - TGL_SZ) div 2;
    FPresR := Rect(PAD, y, PAD + TGL_SZ, y + TGL_SZ);
    if FReplaceEdit.BoundsRect <> Bounds(FFindEdit.Left, y + 3, FFindEdit.Width, TGL_SZ - 6) then
      FReplaceEdit.SetBounds(FFindEdit.Left, y + 3, FFindEdit.Width, TGL_SZ - 6);
    FBtnR[2] := Rect(editR + 8, y, editR + 8 + btnW, y + TGL_SZ);
    FBtnR[3] := Rect(FBtnR[2].Right + 6, y, FBtnR[2].Right + 6 + btnW, y + TGL_SZ);
  end;
  FReplaceEdit.Visible := FReplaceMode and Visible;
end;

procedure TFindBar.Resize;
begin
  inherited Resize;
  UpdateLayout;
end;

// survol calcule depuis les seules couleurs du bouton: la barre ne depend
// d'aucune autre couleur du theme
function BlendCol(A, B: TColor; APct: Integer): TColor;
var
  ra, ga, ba, rb, gb, bb: Byte;
begin
  RedGreenBlue(ColorToRGB(A), ra, ga, ba);
  RedGreenBlue(ColorToRGB(B), rb, gb, bb);
  Result := RGBToColor(ra + (rb - ra) * APct div 100,
    ga + (gb - ga) * APct div 100, ba + (bb - ba) * APct div 100);
end;

procedure TFindBar.DrawButton(const R: TRect; const ACaption: string; AHot: Boolean);
begin
  if AHot then
    Canvas.Brush.Color := BlendCol(clFindBtn, clFindBtnText, 22)
  else
    Canvas.Brush.Color := clFindBtn;
  Canvas.FillRect(R);
  Canvas.Brush.Style := bsClear;
  Canvas.Font.Color := clFindBtnText;
  Canvas.TextOut(R.Left + (R.Right - R.Left - Canvas.TextWidth(ACaption)) div 2,
    R.Top + (R.Bottom - R.Top - Canvas.TextHeight('Ag')) div 2, ACaption);
  Canvas.Brush.Style := bsSolid;
end;

// 0 Aa, 1 "", 2 wrap, 3 in selection, 4 highlight, 5 AB, 6 0x
procedure TFindBar.DrawToggle(AIdx: Integer; const R: TRect; AOn, AHot: Boolean);
var
  g: string;
  cx, cy: Integer;
  col: TColor;
begin
  if AOn then
    Canvas.Brush.Color := clFindToggleOn
  else if AHot then
    Canvas.Brush.Color := BlendCol(clFindToggleOff, clFindToggleOffText, 20)
  else
    Canvas.Brush.Color := clFindToggleOff;
  Canvas.FillRect(R);
  if AOn then col := clFindToggleOnText else col := clFindToggleOffText;
  cx := (R.Left + R.Right) div 2;
  cy := (R.Top + R.Bottom) div 2;
  case AIdx of
    0, 1, 5, 6:
      begin
        case AIdx of
          0: g := 'Aa';
          1: g := '""';
          5: g := 'AB';
          6: g := '0x';
        end;
        Canvas.Brush.Style := bsClear;
        Canvas.Font.Color := col;
        Canvas.TextOut(R.Left + (R.Right - R.Left - Canvas.TextWidth(g)) div 2,
          R.Top + (R.Bottom - R.Top - Canvas.TextHeight('Ag')) div 2, g);
        Canvas.Brush.Style := bsSolid;
      end;
    2:
      begin
        Canvas.Pen.Color := col;
        Canvas.Line(cx - 5, cy - 3, cx + 5, cy - 3);
        Canvas.Line(cx + 5, cy - 3, cx + 5, cy + 3);
        Canvas.Line(cx + 5, cy + 3, cx - 5, cy + 3);
        Canvas.Line(cx - 5, cy + 3, cx - 2, cy);
        Canvas.Line(cx - 5, cy + 3, cx - 2, cy + 6);
      end;
    3:
      begin
        Canvas.Pen.Color := col;
        Canvas.Frame(cx - 6, cy - 6, cx + 7, cy + 7);
        Canvas.Brush.Color := col;
        Canvas.FillRect(cx - 4, cy - 2, cx + 5, cy + 3);
      end;
    4:
      begin
        Canvas.Pen.Color := col;
        Canvas.Frame(cx - 6, cy - 5, cx + 7, cy + 6);
      end;
  end;
end;

procedure TFindBar.Paint;
var
  R: TRect;
  ty: Integer;
begin
  UpdateLayout;
  Canvas.Brush.Color := clStatusBg;
  Canvas.FillRect(ClientRect);
  Canvas.Font := Font;

  if InHexMode then
  begin
    // en hex seuls Aa / 0x / wrap ont un sens
    DrawToggle(0, FToggleR[0], FOptCase and not FOptHexSeq, FHot = 0);
    DrawToggle(6, FToggleR[1], FOptHexSeq, FHot = 6);
    DrawToggle(2, FToggleR[2], FOptWrap, FHot = 2);
  end
  else
  begin
    DrawToggle(0, FToggleR[0], FOptCase, FHot = 0);
    DrawToggle(1, FToggleR[1], FOptWord, FHot = 1);
    DrawToggle(2, FToggleR[2], FOptWrap, FHot = 2);
    DrawToggle(3, FToggleR[3], FOptInSel, FHot = 3);
    DrawToggle(4, FToggleR[4], FOptHighlight, FHot = 4);
  end;

  R := FFindEdit.BoundsRect;
  InflateRect(R, 4, 3);
  if FNotFound then
    Canvas.Pen.Color := clCodeVariable
  else
    Canvas.Pen.Color := clSelectionBg;
  Canvas.Brush.Color := clBorder;
  Canvas.Rectangle(R);

  DrawButton(FBtnR[0], 'Find', FHot = 10);
  DrawButton(FBtnR[1], 'Find Prev', FHot = 11);

  if FReplaceMode then
  begin
    if not InHexMode then
      DrawToggle(5, FPresR, FOptPreserve, FHot = 5);
    R := FReplaceEdit.BoundsRect;
    InflateRect(R, 4, 3);
    Canvas.Pen.Color := clSelectionBg;
    Canvas.Brush.Color := clBorder;
    Canvas.Rectangle(R);
    Canvas.Brush.Style := bsClear;
    Canvas.Font.Color := clStatusText;
    ty := (ROW_H - Canvas.TextHeight('Ag')) div 2;
    Canvas.TextOut(FFindEdit.Left - 8 - Canvas.TextWidth('Find:'), ty, 'Find:');
    Canvas.TextOut(FReplaceEdit.Left - 8 - Canvas.TextWidth('Replace:'),
      ROW_H + ty, 'Replace:');
    Canvas.Brush.Style := bsSolid;
    DrawButton(FBtnR[2], 'Replace', FHot = 12);
    DrawButton(FBtnR[3], 'Replace All', FHot = 13);
  end;

  Canvas.Brush.Style := bsClear;
  if FHot = 20 then
    Canvas.Font.Color := clEditorFg
  else
    Canvas.Font.Color := clStatusText;
  Canvas.TextOut(FCloseR.Left + 4,
    FCloseR.Top + (FCloseR.Bottom - FCloseR.Top - Canvas.TextHeight('x')) div 2, 'x');
  Canvas.Brush.Style := bsSolid;
end;

// ---------------------------------------------------------------- interaction

function TFindBar.HitTest(X, Y: Integer): Integer;
var
  i: Integer;
  pt: TPoint;
begin
  pt := Point(X, Y);
  // croix d'abord: en fenetre etroite les boutons passent dessous
  if PtInRect(FCloseR, pt) then Exit(20);
  if InHexMode then
  begin
    if PtInRect(FToggleR[0], pt) then Exit(0);
    if PtInRect(FToggleR[1], pt) then Exit(6);
    if PtInRect(FToggleR[2], pt) then Exit(2);
  end
  else
  begin
    for i := 0 to 4 do
      if PtInRect(FToggleR[i], pt) then Exit(i);
    if FReplaceMode and PtInRect(FPresR, pt) then Exit(5);
  end;
  for i := 0 to 3 do
    if ((i < 2) or FReplaceMode) and PtInRect(FBtnR[i], pt) then Exit(10 + i);
  Result := -1;
end;

function TFindBar.HintFor(AItem: Integer): string;
begin
  case AItem of
    0: Result := 'Case sensitive';
    1: Result := 'Whole word';
    2: Result := 'Wrap';
    3: Result := 'In selection';
    4: Result := 'Highlight matches';
    5: Result := 'Preserve case';
    6: Result := 'Hex bytes (DE AD BE EF)';
    10: Result := 'Find next';
    11: Result := 'Find previous';
    12: Result := 'Replace current match';
    13: Result := 'Replace all matches';
    20: Result := 'Close';
  else
    Result := '';
  end;
end;

procedure TFindBar.ShowZoneHint;
var
  s: string;
  r: TRect;
  p: TPoint;
begin
  s := HintFor(FHot);
  if s = '' then begin HideZoneHint; Exit; end;
  if FHintWin = nil then
    FHintWin := THintWindow.Create(Self);
  r := FHintWin.CalcHintRect(240, s, nil);
  p := Mouse.CursorPos;
  Types.OffsetRect(r, p.X, p.Y - r.Bottom - 8); // au-dessus du curseur
  FHintWin.ActivateHint(r, s);
  FHintShown := True;
end;

procedure TFindBar.HideZoneHint;
begin
  FHintTimer.Enabled := False;
  if FHintWin <> nil then
    FHintWin.Hide;
  FHintShown := False;
end;

procedure TFindBar.HintTimerTick(Sender: TObject);
begin
  FHintTimer.Enabled := False;
  ShowZoneHint;
end;

procedure TFindBar.MouseMove(Shift: TShiftState; X, Y: Integer);
var
  h: Integer;
begin
  inherited MouseMove(Shift, X, Y);
  h := HitTest(X, Y);
  if h <> FHot then
  begin
    FHot := h;
    if HintFor(h) = '' then
      HideZoneHint
    else if FHintShown then
      ShowZoneHint // bulle deja sortie: bascule immediate
    else
    begin
      FHintTimer.Enabled := False;
      FHintTimer.Enabled := True; // delai avant premiere apparition
    end;
    Invalidate;
  end;
end;

procedure TFindBar.MouseLeave;
begin
  inherited MouseLeave;
  HideZoneHint;
  if FHot <> -1 then begin FHot := -1; Invalidate; end;
end;

procedure TFindBar.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseDown(Button, Shift, X, Y);
  HideZoneHint;
  if Button <> mbLeft then Exit;
  case HitTest(X, Y) of
    0: begin FOptCase := not FOptCase; UpdateHighlight; RecountMatches; Invalidate; end;
    1: begin FOptWord := not FOptWord; UpdateHighlight; RecountMatches; Invalidate; end;
    2: begin FOptWrap := not FOptWrap; Invalidate; end;
    3: begin
         FOptInSel := not FOptInSel;
         if FOptInSel then CaptureRegion;
         RecountMatches;
         Invalidate;
       end;
    4: begin FOptHighlight := not FOptHighlight; UpdateHighlight; Invalidate; end;
    5: begin FOptPreserve := not FOptPreserve; Invalidate; end;
    6: begin
         FOptHexSeq := not FOptHexSeq;
         SetNotFound(False);
         if ActiveHex <> nil then
           ActiveHex.SetMark(-1, 0); // le sens du motif change avec le mode
         Invalidate;
       end;
    10: FindNext;
    11: FindPrev;
    12: ReplaceNext;
    13: ReplaceAll;
    20: HideBar;
  end;
end;

procedure TFindBar.EditKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  case Key of
    VK_RETURN:
      begin
        if Sender = FReplaceEdit then
          ReplaceNext
        else if ssShift in Shift then
          FindPrev
        else
          FindNext;
        Key := 0;
      end;
    VK_ESCAPE: begin HideBar; Key := 0; end;
  end;
end;

procedure TFindBar.EditChange(Sender: TObject);
var
  b: TBytes;
begin
  SetNotFound(False);
  if InHexMode then
  begin
    // motif change: la marque n'est plus une ancre valide
    if Sender = FFindEdit then
      ActiveHex.SetMark(-1, 0);
    if FOptHexSeq and (Sender = FFindEdit) and (FFindEdit.Text <> '') then
      SetNotFound(not ParseHexBytes(FFindEdit.Text, b));
    Exit; // pas de highlight en vue hex
  end;
  UpdateHighlight;
  RecountMatches;
end;

// ------------------------------------------------------------------ recherche

function TFindBar.CmpPt(const A, B: TPoint): Integer;
begin
  if A.Y <> B.Y then
  begin
    if A.Y < B.Y then Exit(-1) else Exit(1);
  end;
  if A.X < B.X then Exit(-1);
  if A.X > B.X then Exit(1);
  Result := 0;
end;

// compte les occurrences sans perturber caret/selection (sauve/restaure)
procedure TFindBar.RecountMatches;
const
  MAX_COUNT = 100000; // borne anti-gel, au-dela on affiche "N+"
var
  syn: TSynEdit;
  opts: TSynSearchOptions;
  savB, savE, savC, start, mb, me, curPos: TPoint;
  n, idx, savTop, savLeft: Integer;
  onCur: Boolean;
  info: string;
begin
  if not Assigned(FOnMatchInfo) then Exit;
  if InHexMode or (not Visible) or (FFindEdit.Text = '') then
  begin
    FOnMatchInfo('');
    Exit;
  end;
  syn := ActiveSyn;
  if syn = nil then begin FOnMatchInfo(''); Exit; end;
  if (FMgr.ActiveDoc <> nil) and FMgr.ActiveDoc.LargeFile then
  begin
    FOnMatchInfo(''); // scan complet a chaque frappe: trop cher sur gros fichier
    Exit;
  end;

  savB := syn.BlockBegin; savE := syn.BlockEnd; savC := syn.CaretXY;
  savTop := syn.TopLine; savLeft := syn.LeftChar; // le scan peut faire defiler
  onCur := syn.SelAvail and SelMatches(syn);
  curPos := savB;
  opts := BaseOptions;
  n := 0; idx := 0;
  if FOptInSel then start := FSelB else start := Point(1, 1);
  syn.BeginUpdate(False); // sinon la selection flickerait pendant le scan
  try
    while syn.SearchReplaceEx(FFindEdit.Text, '', opts, start) > 0 do
    begin
      mb := syn.BlockBegin; me := syn.BlockEnd;
      if FOptInSel and (CmpPt(me, FSelE) > 0) then Break;
      Inc(n);
      if onCur and (CmpPt(mb, curPos) = 0) then idx := n;
      start := me;                 // matches disjoints
      if n >= MAX_COUNT then Break;
    end;
    syn.CaretXY := savC;
    syn.BlockBegin := savB;
    syn.BlockEnd := savE;
    syn.TopLine := savTop;
    syn.LeftChar := savLeft;
  finally
    syn.EndUpdate;
  end;

  if n = 0 then
    info := ''
  else if n >= MAX_COUNT then
    info := IntToStr(MAX_COUNT) + '+ matches'
  else if idx > 0 then
    info := Format('%d/%d matches', [idx, n])
  else
    info := Format('%d matches', [n]);
  FOnMatchInfo(info);
end;

procedure TFindBar.CaptureRegion;
var
  syn: TSynEdit;
begin
  syn := ActiveSyn;
  if syn = nil then Exit;
  if syn.SelAvail then
  begin
    FSelB := syn.BlockBegin;
    FSelE := syn.BlockEnd;
  end
  else
  begin
    // borne REELLE et pas MaxInt: Inc(FSelE.X, delta) wrapperait en negatif
    // ({$Q-}) et sauterait les matches suivants
    FSelB := Point(1, 1);
    if syn.Lines.Count > 0 then
      FSelE := Point(Length(syn.Lines[syn.Lines.Count - 1]) + 1, syn.Lines.Count)
    else
      FSelE := Point(1, 1);
  end;
end;

procedure TFindBar.SetNotFound(AValue: Boolean);
begin
  if FNotFound = AValue then Exit;
  FNotFound := AValue;
  Invalidate;
end;

// pas de RemoveFreeNotification: FBound et FActiveRef visent souvent le meme
// editeur et FreeNotification deduplique, retirer l'un casserait l'autre
procedure TFindBar.BindHighlightTarget(ASyn: TSynEdit);
begin
  if ASyn = FBound then Exit;
  if FBound <> nil then
    FBound.SetHighlightSearch('', []);
  FBound := ASyn;
  if FBound <> nil then
    FBound.FreeNotification(Self);
end;

procedure TFindBar.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited Notification(AComponent, Operation);
  if Operation = opRemove then
  begin
    if AComponent = FBound then FBound := nil;
    if AComponent = FActiveRef then FActiveRef := nil;
  end;
end;

procedure TFindBar.UpdateHighlight;
var
  syn: TSynEdit;
begin
  syn := ActiveSyn;
  if (syn = nil) or not (Visible and FOptHighlight and (FFindEdit.Text <> '')) then
  begin
    BindHighlightTarget(nil);
    Exit;
  end;
  BindHighlightTarget(syn);
  syn.SetHighlightSearch(FFindEdit.Text, BaseOptions);
end;

// OnActiveChanged sert aussi a Save As / Syntax / View sur le MEME doc: ne
// desarmer "in selection" que si l'editeur change vraiment
procedure TFindBar.ActiveDocChanged;
var
  syn: TSynEdit;
begin
  syn := ActiveSyn;
  if syn <> FActiveRef then
  begin
    FActiveRef := syn;
    if FActiveRef <> nil then
      FActiveRef.FreeNotification(Self);
    if FOptInSel then
      FOptInSel := False; // la region appartenait a l'ancien doc
  end;
  UpdateHighlight;
  RecountMatches;
  Invalidate; // le jeu de toggles change entre doc texte et doc hex
end;

function TFindBar.FindFrom(syn: TSynEdit; const AStart: TPoint; ABack: Boolean): Boolean;
var
  opts: TSynSearchOptions;
  savB, savE, savC: TPoint;
begin
  savB := syn.BlockBegin; savE := syn.BlockEnd; savC := syn.CaretXY;
  opts := BaseOptions;
  if ABack then Include(opts, ssoBackwards);
  Result := syn.SearchReplaceEx(FFindEdit.Text, '', opts, AStart) > 0;
  if Result and FOptInSel then
  begin
    if ABack then
      Result := CmpPt(syn.BlockBegin, FSelB) >= 0
    else
      Result := CmpPt(syn.BlockEnd, FSelE) <= 0;
  end;
  if not Result then
  begin
    syn.CaretXY := savC;
    syn.BlockBegin := savB;
    syn.BlockEnd := savE;
  end;
end;

procedure TFindBar.FindNext;
var
  syn: TSynEdit;
  start: TPoint;
  found: Boolean;
begin
  if InHexMode then
  begin
    HexFind(False);
    Exit;
  end;
  syn := ActiveSyn;
  if (syn = nil) or (FFindEdit.Text = '') then Exit;
  if syn.SelAvail then start := syn.BlockEnd else start := syn.CaretXY;
  if FOptInSel and (CmpPt(start, FSelB) < 0) then start := FSelB;
  found := FindFrom(syn, start, False);
  if (not found) and FOptWrap then
  begin
    if FOptInSel then start := FSelB else start := Point(1, 1);
    found := FindFrom(syn, start, False);
  end;
  SetNotFound(not found);
  UpdateHighlight;
  RecountMatches;
end;

procedure TFindBar.FindPrev;
var
  syn: TSynEdit;
  start: TPoint;
  found: Boolean;
begin
  if InHexMode then
  begin
    HexFind(True);
    Exit;
  end;
  syn := ActiveSyn;
  if (syn = nil) or (FFindEdit.Text = '') then Exit;
  if syn.SelAvail then start := syn.BlockBegin else start := syn.CaretXY;
  if FOptInSel and (CmpPt(start, FSelE) > 0) then start := FSelE;
  found := FindFrom(syn, start, True);
  if (not found) and FOptWrap then
  begin
    if FOptInSel then start := FSelE else start := Point(MaxInt, syn.Lines.Count);
    found := FindFrom(syn, start, True);
  end;
  SetNotFound(not found);
  UpdateHighlight;
  RecountMatches;
end;

function TFindBar.SelMatches(syn: TSynEdit): Boolean;
begin
  if FOptCase then
    Result := syn.SelText = FFindEdit.Text
  else
    Result := SameText(syn.SelText, FFindEdit.Text);
end;

// LazUTF8 partout: un index d'octet [1] casserait les accents. Chaque branche
// exige une vraie lettre casee, sinon "123" partirait en minuscules.
function TFindBar.ApplyCase(const AMatch, ARepl: string): string;
var
  c1: string;
begin
  Result := ARepl;
  if (AMatch = '') or (ARepl = '') then Exit;
  if (AMatch = UTF8UpperCase(AMatch)) and (AMatch <> UTF8LowerCase(AMatch)) then
    Exit(UTF8UpperCase(ARepl));
  if (AMatch = UTF8LowerCase(AMatch)) and (AMatch <> UTF8UpperCase(AMatch)) then
    Exit(UTF8LowerCase(ARepl));
  c1 := UTF8Copy(AMatch, 1, 1);
  if (c1 = UTF8UpperCase(c1)) and (c1 <> UTF8LowerCase(c1)) and
     (UTF8Copy(AMatch, 2, MaxInt) = UTF8LowerCase(UTF8Copy(AMatch, 2, MaxInt))) then
    Result := UTF8UpperCase(UTF8Copy(ARepl, 1, 1)) +
      UTF8LowerCase(UTF8Copy(ARepl, 2, MaxInt));
end;

// en mode "in selection", une selection hors region est refusee
procedure TFindBar.ReplaceNext;
var
  syn: TSynEdit;
  repl: string;
  oldLen: Integer;
begin
  if InHexMode then
  begin
    HexReplaceNext;
    Exit;
  end;
  syn := ActiveSyn;
  if (syn = nil) or (FFindEdit.Text = '') then Exit;
  if syn.SelAvail and SelMatches(syn) and
     ((not FOptInSel) or ((CmpPt(syn.BlockBegin, FSelB) >= 0) and
                          (CmpPt(syn.BlockEnd, FSelE) <= 0))) then
  begin
    repl := FReplaceEdit.Text;
    if FOptPreserve then
      repl := ApplyCase(syn.SelText, repl);
    oldLen := Length(syn.SelText);
    syn.SelText := repl;
    // la borne de region glisse si le remplacement change la longueur
    if FOptInSel and (syn.CaretY = FSelE.Y) then
      Inc(FSelE.X, Length(repl) - oldLen);
  end;
  FindNext;
end;

procedure TFindBar.ReplaceAll;
var
  syn: TSynEdit;
  start: TPoint;
  repl: string;
  n, delta: Integer;
begin
  if InHexMode then
  begin
    HexReplaceAll;
    Exit;
  end;
  syn := ActiveSyn;
  if (syn = nil) or (FFindEdit.Text = '') then Exit;
  // boucle manuelle: preserve case et region n'existent pas dans SynEdit
  n := 0;
  if FOptInSel then start := FSelB else start := Point(1, 1);
  syn.BeginUndoBlock;
  syn.BeginUpdate(False);
  try
    while FindFrom(syn, start, False) do
    begin
      repl := FReplaceEdit.Text;
      if FOptPreserve then
        repl := ApplyCase(syn.SelText, repl);
      delta := Length(repl) - Length(syn.SelText);
      syn.SelText := repl;
      Inc(n);
      start := syn.CaretXY;
      // la borne de region glisse si le remplacement change la longueur
      if FOptInSel and (start.Y = FSelE.Y) then
        Inc(FSelE.X, delta);
    end;
  finally
    syn.EndUpdate;
    syn.EndUndoBlock;
  end;
  SetNotFound(n = 0);
  UpdateHighlight;
  RecountMatches;
end;

// ------------------------------------------------------------------ show/hide

procedure TFindBar.ShowFind;
var
  syn: TSynEdit;
begin
  FReplaceMode := False;
  Height := ROW_H;
  syn := ActiveSyn;
  if syn <> nil then
  begin
    if syn.SelAvail and (syn.BlockBegin.Y <> syn.BlockEnd.Y) then
    begin
      FOptInSel := True;
      CaptureRegion;
    end
    else if syn.SelAvail then
      FFindEdit.Text := syn.SelText;
  end;
  Visible := True;
  Top := 0; // les alBottom sont empiles par Top: rester au-dessus de la status bar
  HandleNeeded; // le handle doit exister avant tout Canvas/SetFocus
  UpdateLayout;
  SetNotFound(False);
  UpdateHighlight;
  RecountMatches;
  if FFindEdit.CanFocus then FFindEdit.SetFocus;
  if FFindEdit.HandleAllocated then
    FFindEdit.SelectAll;
end;

procedure TFindBar.ShowReplace;
begin
  ShowFind;
  FReplaceMode := True;
  Height := ROW_H * 2;
  Top := 0; // changer la hauteur re-trie les alBottom
  UpdateLayout;
  Invalidate;
end;

procedure TFindBar.HideBar;
var
  syn: TSynEdit;
  hx: THexView;
begin
  HideZoneHint;
  Visible := False;
  FOptInSel := False;
  if Assigned(FOnMatchInfo) then FOnMatchInfo('');
  BindHighlightTarget(nil);
  hx := ActiveHex;
  if hx <> nil then
  begin
    hx.SetMark(-1, 0);
    if hx.CanFocus then hx.SetFocus;
    Exit;
  end;
  syn := ActiveSyn;
  if (syn <> nil) and syn.CanFocus then
    syn.SetFocus;
end;

end.
