unit uCsvView;

{$mode objfpc}{$H+}

// Onglet tableur sur un TCsvTable: grille dessinee aux couleurs du theme,
// edition de cellule en place, lignes/colonnes entieres (selection, insertion,
// suppression, deplacement, presse-papiers), tri, recherche cellule par
// cellule, annulation par instantane. Pas de formules, ce n'est pas Excel et
// ca ne le deviendra pas.

interface

uses
  Classes, SysUtils, Math, Controls, Graphics, Grids, LCLType, Clipbrd,
  LazUTF8, Forms, Dialogs, uCsv, uTheme, uRtMessage;

type
  TCsvSelKind = (skNone, skRows, skCols);
  TCsvCellFn = function(const S: string): string of object;
  // macro: touches recues par la grille + valeur validee d'une cellule editee
  TCsvMacroKind = (mkKey, mkEdit);
  TCsvMacroStep = record
    Kind: TCsvMacroKind;
    Key: Word;
    Shift: TShiftState;
    Text: string;
  end;

  TCsvView = class(TDrawGrid)
  private
    FTable: TCsvTable;
    FHasHeader: Boolean;
    FSortCol: Integer;
    FSortDesc: Boolean;
    FOnEdited: TNotifyEvent;
    FOnCaretMove: TNotifyEvent;
    // occurrence courante de la recherche, dans la cellule (FMatchCol, FMatchRow)
    FMatchCol, FMatchRow, FMatchStart, FMatchLen: Integer;
    FReplaced: Boolean; // la "marque" est le texte remplace: reprendre apres
    // selection de lignes ou colonnes entieres, indices grille, FSelA = ancre
    FSelKind: TCsvSelKind;
    FSelA, FSelB: Integer;
    FDragKind: TCsvSelKind; // glisser sur les en-tetes en cours
    // lignes/colonnes coupees ou copiees; FClipText = ce qu'on a mis dans le
    // presse-papiers systeme, pour savoir si le Coller est encore le notre
    FClipKind: TCsvSelKind;
    FClipRows: array of TCsvRow;
    FClipText: string;
    FUndo, FRedo: TList;
    FEditSnap: Boolean; // instantane deja pris pour l'edition en cours
    FEatChar: Boolean;  // touche consommee dans KeyDown, son caractere suit encore
    FMacro: array of TCsvMacroStep;
    FRecording, FPlaying: Boolean;
    FEditOrig: string;  // valeur de la cellule a l'ouverture de l'editeur
    FEditCol, FEditRow: Integer;
    FOnMacroChange: TNotifyEvent;
    procedure MacroAdd(AKind: TCsvMacroKind; AKey: Word; AShift: TShiftState; const AText: string);
    function DataRow(AGridRow: Integer): Integer;
    function CellAt(AGridCol, AGridRow: Integer): string;
    procedure PutCell(AGridCol, AGridRow: Integer; const AValue: string);
    procedure SetHasHeader(AValue: Boolean);
    procedure SyncDims;
    procedure Edited;
    procedure ClearMatch;
    function ColLabel(ACol: Integer): string;
    procedure DoGetEditText(Sender: TObject; ACol, ARow: Integer; var Value: string);
    function SelLo: Integer;
    function SelHi: Integer;
    function SelCount: Integer;
    procedure SetSel(AKind: TCsvSelKind; AAnchor, AExtent: Integer);
    procedure PushUndo;
    procedure DropLastUndo;
    procedure ClearList(AList: TList);
    procedure AfterStructural;
    function SortColumn(ACol: Integer; ADesc: Boolean): Boolean;
    function CurRowsRange(out AIdx, ACount: Integer): Boolean; // en indices table
    function CurColsRange(out AIdx, ACount: Integer): Boolean;
    // memes bornes qu'au parsing, sinon on fabrique un fichier qu'on refusera
    function CanGrow(AMoreRows, AMoreCols: Integer): Boolean;
  protected
    procedure DrawCell(ACol, ARow: Integer; ARect: TRect; AState: TGridDrawState); override;
    procedure SetEditText(ACol, ARow: Longint; const Value: string); override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure AfterMoveSelection(const prevCol, prevRow: Integer); override;
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
    procedure UTF8KeyPress(var UTF8Key: TUTF8Char); override;
    procedure EditorShow(const SelAll: Boolean); override;
    procedure EditorHide; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    // AKeepHeader: rechargement, le choix d'en-tete de l'utilisateur survit
    procedure LoadText(const AText, AHint: string; AKeepHeader: Boolean = False);
    function Text(ATrailingEol: Boolean; const AEol: string = #10): string;
    procedure InvalidateMatch; // motif de recherche change
    procedure ShowView;
    procedure HideView;
    procedure RefreshTheme;
    procedure FitColumns;
    // cellule courante
    procedure ClearCell;
    procedure CopyCell;
    procedure CutCell;
    procedure PasteCell;
    // selection lignes/colonnes (ou la ligne/colonne courante sans selection)
    procedure SelectRow;
    procedure SelectCol;
    procedure ClearSel;
    function HasSel: Boolean;
    procedure CopySel;      // cellule si pas de selection
    procedure CutSel;
    procedure PasteSel;     // lignes/colonnes si c'est notre lot, sinon cellule
    procedure DeleteSel;    // vide la cellule si pas de selection
    procedure DuplicateSel;
    procedure InsertRows(ABelow: Boolean);
    procedure InsertCols(ARight: Boolean);
    // ACols: colonnes meme sans selection (Alt+gauche/droite)
    procedure MoveSel(ADelta: Integer; ACols: Boolean = False);
    procedure SortCurrent(ADesc: Boolean);
    // AFn sur chaque cellule de la selection (ou la cellule courante); une
    // exception remet tout en l'etat et remonte
    procedure TransformSel(AFn: TCsvCellFn);
    // macro clavier: touches de la grille et cellules validees, pas la souris
    procedure MacroStart;
    procedure MacroStop;
    procedure MacroPlay;
    function MacroRecording: Boolean;
    function MacroEmpty: Boolean;
    procedure Undo;
    procedure Redo;
    function CanUndo: Boolean;
    function CanRedo: Boolean;
    // coordonnees 1-based dans les donnees (en-tete exclu)
    procedure GotoCell(ACol, ARow: Integer);
    function CurCol: Integer;
    function CurRow: Integer;
    function DataRowCount: Integer;
    function FindNext(const APat: string; ACase, AWord, ABack, AWrap: Boolean): Boolean;
    function ReplaceCurrent(const APat, ARepl: string; ACase, AWord: Boolean): Boolean;
    function ReplaceAll(const APat, ARepl: string; ACase, AWord: Boolean): Integer;
    property Table: TCsvTable read FTable;
    property HasHeader: Boolean read FHasHeader write SetHasHeader;
    property SelKind: TCsvSelKind read FSelKind;
    property OnEdited: TNotifyEvent read FOnEdited write FOnEdited;
    property OnCaretMove: TNotifyEvent read FOnCaretMove write FOnCaretMove;
    property OnMacroChange: TNotifyEvent read FOnMacroChange write FOnMacroChange;
  end;

var
  RTCsvOpen: Integer = 0; // ouverture d'un .csv: 0 demander, 1 texte, 2 table

function IsCsvName(const AFileName: string): Boolean;

implementation

const
  UNDO_MAX = 50;
  UNDO_CELLS = 20000000; // ~160 Mo de pointeurs, l'historique n'ira pas plus loin

type
  TCtrlCracker = class(TWinControl);

function IsCsvName(const AFileName: string): Boolean;
var
  e: string;
begin
  e := LowerCase(ExtractFileExt(AFileName));
  Result := (e = '.csv') or (e = '.tsv');
end;

function WordCh(const S: string; X: Integer): Boolean;
begin
  Result := (X >= 1) and (X <= Length(S)) and
    ((S[X] in ['A'..'Z', 'a'..'z', '0'..'9', '_']) or (S[X] >= #$80));
end;

// borne d'affichage: une cellule de 100 Mo (quote jamais fermee) repeinte a
// chaque coup de molette, non merci
function Disp(const S: string): string;
var
  n: Integer;
begin
  if Length(S) <= 512 then Exit(S);
  n := 512;
  while (n > 1) and ((Ord(S[n + 1]) and $C0) = $80) do Dec(n);
  Result := Copy(S, 1, n) + '...';
end;

// position (1-based, octets) de l'occurrence suivante a partir de AFrom, ou
// precedente strictement avant AFrom si ABack. 0 = rien.
function MatchIn(const S, APat: string; AFrom: Integer; ACase, AWord, ABack: Boolean): Integer;
var
  hs, hp: string;
  p, best: Integer;
begin
  Result := 0;
  if (APat = '') or (S = '') then Exit;
  if ACase then begin hs := S; hp := APat; end
  else
  begin
    hs := UTF8LowerCase(S);
    hp := UTF8LowerCase(APat);
    // pliage qui change la longueur (rare): les positions ne vaudraient plus rien
    if (Length(hs) <> Length(S)) or (Length(hp) <> Length(APat)) then
    begin
      hs := S;
      hp := APat;
    end;
  end;
  if AFrom < 1 then AFrom := 1;
  best := 0;
  p := 1;
  repeat
    p := Pos(hp, hs, p);
    if p = 0 then Break;
    if (not AWord) or (not WordCh(hs, p - 1) and not WordCh(hs, p + Length(hp))) then
    begin
      if ABack then
      begin
        if p < AFrom then best := p else Break;
      end
      else if p >= AFrom then
      begin
        best := p;
        Break;
      end;
    end;
    Inc(p);
  until p > Length(hs);
  Result := best;
end;

constructor TCsvView.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FTable := TCsvTable.Create;
  FUndo := TList.Create;
  FRedo := TList.Create;
  FSortCol := -1;
  FMatchCol := -1;
  FixedCols := 1;
  FixedRows := 1;
  ColCount := 2;
  RowCount := 2;
  BorderStyle := bsNone;
  Options := [goEditing, goColSizing, goThumbTracking, goSmoothScroll,
    goDrawFocusSelected, goTabs];
  Flat := True;
  DefaultDrawing := False;
  FocusRectVisible := False;
  AutoFillColumns := False;
  FastEditing := True;
  AutoAdvance := aaNone; // Entree gere dans KeyDown, pas deux deplacements
  DefaultRowHeight := 22;
  // via l'evenement: c'est la que la grille memorise l'ancienne valeur pour Echap
  OnGetEditText := @DoGetEditText;
  RefreshTheme;
end;

destructor TCsvView.Destroy;
begin
  ClearList(FUndo);
  ClearList(FRedo);
  FUndo.Free;
  FRedo.Free;
  FTable.Free;
  inherited Destroy;
end;

procedure TCsvView.DoGetEditText(Sender: TObject; ACol, ARow: Integer; var Value: string);
begin
  Value := CellAt(ACol, ARow);
end;

function TCsvView.DataRow(AGridRow: Integer): Integer;
begin
  Result := AGridRow - 1 + Ord(FHasHeader);
end;

function TCsvView.DataRowCount: Integer;
begin
  Result := FTable.RowCount - Ord(FHasHeader);
  if Result < 0 then Result := 0;
end;

function TCsvView.CellAt(AGridCol, AGridRow: Integer): string;
begin
  Result := FTable[DataRow(AGridRow), AGridCol - 1];
end;

procedure TCsvView.PutCell(AGridCol, AGridRow: Integer; const AValue: string);
begin
  if FTable[DataRow(AGridRow), AGridCol - 1] = AValue then Exit;
  FTable[DataRow(AGridRow), AGridCol - 1] := AValue;
  Edited;
  InvalidateCell(AGridCol, AGridRow);
end;

procedure TCsvView.Edited;
begin
  if Assigned(FOnEdited) then FOnEdited(Self);
end;

procedure TCsvView.ClearMatch;
begin
  FMatchCol := -1;
  FMatchLen := 0;
  FReplaced := False;
end;

procedure TCsvView.SyncDims;
var
  n: Integer;
begin
  n := FTable.ColCount;
  if n < 1 then n := 1;
  ColCount := n + 1;
  n := DataRowCount;
  if n < 1 then n := 1;
  RowCount := n + 1;
end;

procedure TCsvView.SetHasHeader(AValue: Boolean);
begin
  if FHasHeader = AValue then Exit;
  if EditorMode then EditorMode := False; // sinon l'editeur ecrit dans la ligne d'a cote
  FHasHeader := AValue;
  ClearMatch;
  ClearSel;
  SyncDims;
  Invalidate;
end;

procedure TCsvView.LoadText(const AText, AHint: string; AKeepHeader: Boolean);
var
  t: TCsvTable;
begin
  if EditorMode then EditorMode := False;
  // table temporaire: un fichier refuse ne remplace pas celle qu'on a
  t := TCsvTable.Create;
  try
    t.Parse(AText, AHint);
  except
    t.Free;
    raise;
  end;
  FTable.Free;
  FTable := t;
  // beaucoup de CSV n'ont pas de noms de champs: pas d'en-tete sans preuve
  if not AKeepHeader then FHasHeader := FTable.GuessHeader;
  ClearList(FUndo);
  ClearList(FRedo);
  FSortCol := -1;
  FSelKind := skNone;
  FDragKind := skNone;
  ClearMatch;
  SyncDims;
  FitColumns;
  Col := 1;
  Row := 1;
  Invalidate;
end;

function TCsvView.Text(ATrailingEol: Boolean; const AEol: string): string;
begin
  Result := FTable.Serialize(ATrailingEol, AEol);
end;

procedure TCsvView.InvalidateMatch;
begin
  ClearMatch;
end;

// pas de noms de champs: C1, C2, C3, ca vaut mieux qu'un en-tete invente
function TCsvView.ColLabel(ACol: Integer): string;
begin
  Result := 'C' + IntToStr(ACol + 1);
end;

procedure TCsvView.FitColumns;
var
  bmp: TBitmap;
  c, r, w, last: Integer;
begin
  bmp := TBitmap.Create;
  try
    bmp.Canvas.Font.Assign(Font);
    last := DataRowCount;
    if last > 200 then last := 200;
    ColWidths[0] := bmp.Canvas.TextWidth(IntToStr(FTable.RowCount + 1)) + 16;
    for c := 1 to ColCount - 1 do
    begin
      if FHasHeader then w := bmp.Canvas.TextWidth(Disp(FTable[0, c - 1]))
      else w := bmp.Canvas.TextWidth(ColLabel(c - 1));
      for r := 1 to last do
        w := Max(w, bmp.Canvas.TextWidth(Disp(CellAt(c, r))));
      w := w + 14;
      if w < 48 then w := 48;
      if w > 360 then w := 360;
      ColWidths[c] := w;
    end;
  finally
    bmp.Free;
  end;
end;

// meme police et meme taille que l'editeur (theme ou preference)
procedure TCsvView.RefreshTheme;
begin
  Color := clEditorBg;
  if RSEditorFontName <> '' then Font.Name := RSEditorFontName;
  Font.Size := RSEditorFontSize;
  Font.Color := clEditorFg;
  Font.Quality := fqCleartype;
  DefaultRowHeight := Round(RSEditorFontSize * 96 / 72) + 8;
  Invalidate;
end;

// ------------------------------------------------------------------ selection

function TCsvView.SelLo: Integer;
begin
  Result := Min(FSelA, FSelB);
end;

function TCsvView.SelHi: Integer;
begin
  Result := Max(FSelA, FSelB);
end;

function TCsvView.SelCount: Integer;
begin
  if FSelKind = skNone then Exit(0);
  Result := SelHi - SelLo + 1;
end;

function TCsvView.HasSel: Boolean;
begin
  Result := FSelKind <> skNone;
end;

procedure TCsvView.SetSel(AKind: TCsvSelKind; AAnchor, AExtent: Integer);
begin
  if EditorMode then EditorMode := False;
  FSelKind := AKind;
  FSelA := AAnchor;
  FSelB := AExtent;
  Invalidate;
end;

procedure TCsvView.ClearSel;
begin
  if FSelKind = skNone then Exit;
  FSelKind := skNone;
  Invalidate;
end;

procedure TCsvView.SelectRow;
begin
  if Row < 1 then Exit;
  SetSel(skRows, Row, Row);
end;

procedure TCsvView.SelectCol;
begin
  if Col < 1 then Exit;
  SetSel(skCols, Col, Col);
end;

// sans selection, la ligne/colonne courante fait l'affaire
function TCsvView.CurRowsRange(out AIdx, ACount: Integer): Boolean;
begin
  Result := False;
  if FSelKind = skCols then Exit;
  if FSelKind = skRows then
  begin
    AIdx := DataRow(SelLo);
    ACount := SelCount;
  end
  else
  begin
    AIdx := DataRow(Row);
    ACount := 1;
  end;
  Result := (AIdx >= 0) and (AIdx < FTable.RowCount);
end;

function TCsvView.CurColsRange(out AIdx, ACount: Integer): Boolean;
begin
  Result := False;
  if FSelKind = skRows then Exit;
  if FSelKind = skCols then
  begin
    AIdx := SelLo - 1;
    ACount := SelCount;
  end
  else
  begin
    AIdx := Col - 1;
    ACount := 1;
  end;
  Result := (AIdx >= 0) and (AIdx < FTable.ColCount);
end;

// ----------------------------------------------------------------- annulation

procedure TCsvView.ClearList(AList: TList);
var
  i: Integer;
begin
  for i := 0 to AList.Count - 1 do TObject(AList[i]).Free;
  AList.Clear;
end;

// un instantane coute un pointeur par cellule: budget global, pas un compte.
// Macro en relecture: un seul instantane pour tout, pris avant
procedure TCsvView.PushUndo;
var
  snap: TCsvTable;
  budget: Int64;
  i, drop: Integer;
begin
  if FPlaying then Exit;
  snap := TCsvTable.Create;
  snap.Assign(FTable);
  FUndo.Add(snap);
  budget := 0;
  drop := 0;
  for i := FUndo.Count - 1 downto 0 do
  begin
    budget := budget + Int64(TCsvTable(FUndo[i]).RowCount) * (TCsvTable(FUndo[i]).ColCount + 1);
    if ((budget > UNDO_CELLS) and (i < FUndo.Count - 1)) or (FUndo.Count - i > UNDO_MAX) then
    begin
      drop := i + 1;
      Break;
    end;
  end;
  while drop > 0 do
  begin
    TObject(FUndo[0]).Free;
    FUndo.Delete(0);
    Dec(drop);
  end;
  ClearList(FRedo);
end;

// operation qui n'a finalement rien change: l'instantane ne sert a rien
procedure TCsvView.DropLastUndo;
begin
  if FPlaying or (FUndo.Count = 0) then Exit;
  TObject(FUndo[FUndo.Count - 1]).Free;
  FUndo.Delete(FUndo.Count - 1);
end;

function TCsvView.CanUndo: Boolean;
begin
  Result := FUndo.Count > 0;
end;

function TCsvView.CanRedo: Boolean;
begin
  Result := FRedo.Count > 0;
end;

procedure TCsvView.Undo;
var
  snap: TCsvTable;
begin
  if FUndo.Count = 0 then Exit;
  if EditorMode then EditorMode := False;
  snap := TCsvTable.Create;
  snap.Assign(FTable);
  FRedo.Add(snap);
  FTable.Assign(TCsvTable(FUndo[FUndo.Count - 1]));
  TObject(FUndo[FUndo.Count - 1]).Free;
  FUndo.Delete(FUndo.Count - 1);
  FEditSnap := False;
  AfterStructural;
end;

procedure TCsvView.Redo;
var
  snap: TCsvTable;
begin
  if FRedo.Count = 0 then Exit;
  if EditorMode then EditorMode := False;
  snap := TCsvTable.Create;
  snap.Assign(FTable);
  FUndo.Add(snap);
  FTable.Assign(TCsvTable(FRedo[FRedo.Count - 1]));
  TObject(FRedo[FRedo.Count - 1]).Free;
  FRedo.Delete(FRedo.Count - 1);
  FEditSnap := False;
  AfterStructural;
end;

// apres toute operation qui change la forme de la table
procedure TCsvView.AfterStructural;
begin
  ClearMatch;
  SyncDims;
  if Col > ColCount - 1 then Col := ColCount - 1;
  if Row > RowCount - 1 then Row := RowCount - 1;
  if FSelKind = skRows then
  begin
    if SelHi > RowCount - 1 then ClearSel;
  end
  else if FSelKind = skCols then
    if SelHi > ColCount - 1 then ClearSel;
  Edited;
  Invalidate;
  if Assigned(FOnCaretMove) then FOnCaretMove(Self);
end;

// --------------------------------------------------------------------- dessin

procedure TCsvView.DrawCell(ACol, ARow: Integer; ARect: TRect; AState: TGridDrawState);
var
  s: string;
  ts: TTextStyle;
  h, cx, cy, tr: Integer;
  insel: Boolean;
begin
  Canvas.Font.Assign(Font);
  insel := ((FSelKind = skRows) and (ARow >= SelLo) and (ARow <= SelHi)) or
           ((FSelKind = skCols) and (ACol >= SelLo) and (ACol <= SelHi));
  if (ARow = 0) or (ACol = 0) then
  begin
    Canvas.Brush.Color := clGutterBg;
    Canvas.Font.Color := clGutterFg;
    if insel then
    begin
      Canvas.Brush.Color := clSelectionBg;
      Canvas.Font.Color := clSelectionFg;
    end;
    if ARow = 0 then
    begin
      if ACol = 0 then s := ''
      else if FHasHeader then s := FTable[0, ACol - 1]
      else s := ColLabel(ACol - 1);
    end
    else
    begin
      s := IntToStr(DataRow(ARow) + 1);
      if (ARow = Row) and not insel then Canvas.Font.Color := clGutterFgCur;
    end;
  end
  else
  begin
    if insel or ((ACol = Col) and (ARow = Row)) then
    begin
      Canvas.Brush.Color := clSelectionBg;
      Canvas.Font.Color := clSelectionFg;
    end
    else
    begin
      if ARow = Row then Canvas.Brush.Color := clCurrentLine
      else Canvas.Brush.Color := clEditorBg;
      Canvas.Font.Color := clEditorFg;
    end;
    s := CellAt(ACol, ARow);
  end;
  Canvas.Brush.Style := bsSolid;
  Canvas.FillRect(ARect);
  Canvas.Pen.Color := clBorder;
  Canvas.Line(ARect.Right - 1, ARect.Top, ARect.Right - 1, ARect.Bottom);
  Canvas.Line(ARect.Left, ARect.Bottom - 1, ARect.Right, ARect.Bottom - 1);
  tr := ARect.Right - 4;
  if (ARow = 0) and (ACol - 1 = FSortCol) then
  begin
    h := (ARect.Bottom - ARect.Top) div 5;
    if h < 3 then h := 3;
    cx := ARect.Right - 8 - h;
    cy := (ARect.Top + ARect.Bottom) div 2;
    Canvas.Pen.Color := Canvas.Font.Color;
    Canvas.Brush.Color := Canvas.Font.Color;
    if FSortDesc then
      Canvas.Polygon([Point(cx - h, cy - h div 2), Point(cx + h, cy - h div 2), Point(cx, cy + h div 2 + 1)])
    else
      Canvas.Polygon([Point(cx - h, cy + h div 2), Point(cx + h, cy + h div 2), Point(cx, cy - h div 2 - 1)]);
    tr := cx - h - 4;
  end;
  if s = '' then Exit;
  // une cellule multi-ligne s'affiche sur une ligne, le reste au tableur du voisin
  s := StringReplace(StringReplace(Disp(s), #13, '', [rfReplaceAll]), #10, ' ', [rfReplaceAll]);
  ts := Canvas.TextStyle;
  ts.Layout := tlCenter;
  ts.Clipping := True;
  ts.SingleLine := True;
  ts.Wordbreak := False;
  ts.EndEllipsis := True;
  if ACol = 0 then ts.Alignment := taRightJustify else ts.Alignment := taLeftJustify;
  Canvas.Brush.Style := bsClear;
  Canvas.TextRect(Rect(ARect.Left + 5, ARect.Top, tr, ARect.Bottom), ARect.Left + 5, ARect.Top, s, ts);
  Canvas.Brush.Style := bsSolid;
end;

// ------------------------------------------------------------------- edition

procedure TCsvView.EditorShow(const SelAll: Boolean);
begin
  // l'editeur ecrit a chaque frappe: l'instantane se prend avant la premiere
  if not FEditSnap then
  begin
    PushUndo;
    FEditSnap := True;
  end;
  FEditCol := Col;
  FEditRow := Row;
  FEditOrig := CellAt(Col, Row);
  inherited EditorShow(SelAll);
  if Editor = nil then Exit;
  TCtrlCracker(Editor).Color := clEditorBg;
  TCtrlCracker(Editor).Font.Assign(Font);
  TCtrlCracker(Editor).Font.Color := clEditorFg;
end;

// la macro retient la valeur finale de la cellule, pas les frappes: Backspace
// et compagnie se rejouent mal, un texte se recolle toujours
procedure TCsvView.EditorHide;
begin
  inherited EditorHide;
  if FRecording and (not FPlaying) and (FEditCol >= 1) and (FEditRow >= 1) and
     (CellAt(FEditCol, FEditRow) <> FEditOrig) then
    MacroAdd(mkEdit, 0, [], CellAt(FEditCol, FEditRow));
  FEditCol := 0;
  // deux editions a la souris sans touche entre elles: chacune son instantane
  if not FPlaying then FEditSnap := False;
end;

procedure TCsvView.MacroAdd(AKind: TCsvMacroKind; AKey: Word; AShift: TShiftState; const AText: string);
begin
  SetLength(FMacro, Length(FMacro) + 1);
  FMacro[High(FMacro)].Kind := AKind;
  FMacro[High(FMacro)].Key := AKey;
  FMacro[High(FMacro)].Shift := AShift;
  FMacro[High(FMacro)].Text := AText;
end;

procedure TCsvView.MacroStart;
begin
  if FRecording or FPlaying then Exit;
  FMacro := nil;
  FRecording := True;
  if Assigned(FOnMacroChange) then FOnMacroChange(Self);
end;

procedure TCsvView.MacroStop;
begin
  if not FRecording then Exit;
  if EditorMode then EditorMode := False;
  FRecording := False;
  if Assigned(FOnMacroChange) then FOnMacroChange(Self);
end;

function TCsvView.MacroRecording: Boolean;
begin
  Result := FRecording;
end;

function TCsvView.MacroEmpty: Boolean;
begin
  Result := Length(FMacro) = 0;
end;

// un seul instantane pour toute la relecture: Ctrl+Z defait la macro entiere
procedure TCsvView.MacroPlay;
var
  i: Integer;
  k: Word;
begin
  if FRecording or FPlaying or (Length(FMacro) = 0) then Exit;
  if EditorMode then EditorMode := False;
  PushUndo;
  FPlaying := True;
  try
    for i := 0 to High(FMacro) do
      case FMacro[i].Kind of
        mkEdit:
          begin
            if EditorMode then EditorMode := False;
            if (Col >= 1) and (Row >= 1) then PutCell(Col, Row, FMacro[i].Text);
          end;
        mkKey:
          begin
            k := FMacro[i].Key;
            KeyDown(k, FMacro[i].Shift);
          end;
      end;
  finally
    FPlaying := False;
    FEditSnap := False;
    if EditorMode then EditorMode := False;
  end;
  Invalidate;
end;

procedure TCsvView.SetEditText(ACol, ARow: Longint; const Value: string);
begin
  if (ACol < 1) or (ARow < 1) then Exit;
  PutCell(ACol, ARow, Value);
  ClearMatch;
end;

function TCsvView.SortColumn(ACol: Integer; ADesc: Boolean): Boolean;
begin
  Result := False;
  if (ACol < 0) or (DataRowCount < 2) then Exit;
  PushUndo;
  FSortCol := ACol;
  FSortDesc := ADesc;
  if FTable.SortByColumn(ACol, ADesc, Ord(FHasHeader)) then
  begin
    Edited;
    Result := True;
  end
  else
    DropLastUndo;
  ClearMatch;
  Invalidate;
end;

procedure TCsvView.TransformSel(AFn: TCsvCellFn);
var
  c, r, c1, c2, r1, r2: Integer;
  s, v: string;
  touched: Boolean;
begin
  if EditorMode then EditorMode := False;
  c1 := Col; c2 := Col; r1 := Row; r2 := Row;
  if FSelKind = skRows then begin c1 := 1; c2 := ColCount - 1; r1 := SelLo; r2 := SelHi; end
  else if FSelKind = skCols then begin c1 := SelLo; c2 := SelHi; r1 := 1; r2 := RowCount - 1; end;
  if (c1 < 1) or (r1 < 1) then Exit;
  PushUndo;
  touched := False;
  try
    for r := r1 to r2 do
      for c := c1 to c2 do
      begin
        s := CellAt(c, r);
        v := AFn(s);
        if v <> s then
        begin
          FTable[DataRow(r), c - 1] := v;
          touched := True;
        end;
      end;
  except
    // une cellule a refuse: on ne laisse pas la moitie transformee
    FTable.Assign(TCsvTable(FUndo[FUndo.Count - 1]));
    DropLastUndo;
    Invalidate;
    raise;
  end;
  ClearMatch;
  if touched then
  begin
    Edited;
    Invalidate;
  end
  else
    DropLastUndo;
end;

procedure TCsvView.SortCurrent(ADesc: Boolean);
var
  c: Integer;
begin
  if FSelKind = skCols then c := SelLo - 1 else c := Col - 1;
  SortColumn(c, ADesc);
end;

// clic gauche sur un numero de ligne ou une tete de colonne = selection
// entiere, Maj etend depuis l'ancre, glisser etend aussi. Clic droit sur une
// tete de colonne = tri, re-clic = inverse: l'ordre change pour de bon, c'est
// ce qui part sur le disque. Clic dans une cellule = fin de la selection.
procedure TCsvView.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  c, r: Integer;
begin
  MouseToCell(X, Y, c, r);
  if (Button = mbRight) and (r = 0) and (c >= 1) then
  begin
    if FSortCol = c - 1 then SortColumn(c - 1, not FSortDesc)
    else SortColumn(c - 1, False);
    Exit;
  end;
  if Button = mbLeft then
  begin
    if (c >= 1) and (r >= 1) then ClearSel
    // curseur double fleche = la grille va redimensionner, pas selectionner
    else if (r = 0) and (c >= 1) and (Cursor <> crHSplit) then
    begin
      if (ssShift in Shift) and (FSelKind = skCols) then SetSel(skCols, FSelA, c)
      else SetSel(skCols, c, c);
      FDragKind := skCols;
      Col := c;
    end
    else if (c = 0) and (r >= 1) then
    begin
      if (ssShift in Shift) and (FSelKind = skRows) then SetSel(skRows, FSelA, r)
      else SetSel(skRows, r, r);
      FDragKind := skRows;
      Row := r;
    end;
  end;
  inherited MouseDown(Button, Shift, X, Y);
end;

procedure TCsvView.MouseMove(Shift: TShiftState; X, Y: Integer);
var
  c, r: Integer;
begin
  inherited MouseMove(Shift, X, Y);
  if (FDragKind = skNone) or not (ssLeft in Shift) then Exit;
  MouseToCell(X, Y, c, r);
  if (FDragKind = skRows) and (r >= 1) and (r <> FSelB) then
  begin
    FSelB := r;
    Row := r;
    Invalidate;
  end
  else if (FDragKind = skCols) and (c >= 1) and (c <> FSelB) then
  begin
    FSelB := c;
    Col := c;
    Invalidate;
  end;
end;

procedure TCsvView.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseUp(Button, Shift, X, Y);
  FDragKind := skNone;
end;

procedure TCsvView.AfterMoveSelection(const prevCol, prevRow: Integer);
begin
  inherited AfterMoveSelection(prevCol, prevRow);
  if prevRow <> Row then Invalidate; // bande de ligne courante
  if Assigned(FOnCaretMove) then FOnCaretMove(Self);
end;

procedure TCsvView.KeyDown(var Key: Word; Shift: TShiftState);
var
  rec: Boolean;
begin
  rec := FRecording and not FPlaying;
  // Entree = valider et descendre, convention tableur; la grille LCL file a droite
  if (Key = VK_RETURN) and (Shift = []) then
  begin
    if EditorMode then EditorMode := False; // enregistre la cellule AVANT la touche
    if rec then MacroAdd(mkKey, Key, Shift, '');
    FEditSnap := False;
    if Row < RowCount - 1 then Row := Row + 1;
    Key := 0;
    Exit;
  end;
  if EditorMode then
  begin
    if rec and (Key in [VK_ESCAPE, VK_TAB]) then MacroAdd(mkKey, Key, Shift, '');
    inherited KeyDown(Key, Shift);
    Exit;
  end;
  if rec then MacroAdd(mkKey, Key, Shift, '');
  FEditSnap := False;
  case Key of
    VK_ESCAPE: if HasSel then begin ClearSel; Key := 0; Exit; end;
    VK_DELETE: if Shift = [] then begin DeleteSel; Key := 0; Exit; end;
    VK_INSERT:
      if Shift = [] then
      begin
        if FSelKind = skCols then InsertCols(False) else InsertRows(False);
        Key := 0;
        Exit;
      end;
    VK_SPACE:
      begin
        // le WM_CHAR de l'espace arrive quand meme et ouvrirait l'editeur
        if Shift = [ssShift] then begin SelectRow; FEatChar := True; Key := 0; Exit; end;
        if Shift = [ssModifier] then begin SelectCol; FEatChar := True; Key := 0; Exit; end;
      end;
    VK_HOME: if Shift = [ssModifier] then begin ClearSel; GotoCell(1, 1); Key := 0; Exit; end;
    VK_END: if Shift = [ssModifier] then begin ClearSel; GotoCell(ColCount - 1, RowCount - 1); Key := 0; Exit; end;
    VK_UP, VK_DOWN:
      begin
        if Shift = [ssAlt] then
        begin
          MoveSel(Ord(Key = VK_DOWN) * 2 - 1);
          Key := 0;
          Exit;
        end;
        // Maj+haut/bas etend une selection de lignes, sinon simple deplacement
        if (Shift = [ssShift]) and (FSelKind = skRows) then
        begin
          if (Key = VK_UP) and (FSelB > 1) then Dec(FSelB);
          if (Key = VK_DOWN) and (FSelB < RowCount - 1) then Inc(FSelB);
          Row := FSelB;
          Invalidate;
          Key := 0;
          Exit;
        end;
      end;
    VK_LEFT, VK_RIGHT:
      begin
        if Shift = [ssAlt] then
        begin
          MoveSel(Ord(Key = VK_RIGHT) * 2 - 1, True);
          Key := 0;
          Exit;
        end;
        if (Shift = [ssShift]) and (FSelKind = skCols) then
        begin
          if (Key = VK_LEFT) and (FSelB > 1) then Dec(FSelB);
          if (Key = VK_RIGHT) and (FSelB < ColCount - 1) then Inc(FSelB);
          Col := FSelB;
          Invalidate;
          Key := 0;
          Exit;
        end;
      end;
    // les raccourcis du menu ne passent pas par la form (menu non attache): a nous
    VK_Z: if Shift = [ssModifier] then begin Undo; Key := 0; Exit; end;
    VK_Y: if Shift = [ssModifier] then begin Redo; Key := 0; Exit; end;
    VK_C: if Shift = [ssModifier] then begin CopySel; Key := 0; Exit; end;
    VK_X: if Shift = [ssModifier] then begin CutSel; Key := 0; Exit; end;
    VK_V: if Shift = [ssModifier] then begin PasteSel; Key := 0; Exit; end;
  end;
  // toute navigation ordinaire lache la selection de lignes/colonnes
  if Key in [VK_UP, VK_DOWN, VK_LEFT, VK_RIGHT, VK_HOME, VK_END, VK_PRIOR, VK_NEXT, VK_TAB] then
    ClearSel;
  inherited KeyDown(Key, Shift);
end;

procedure TCsvView.UTF8KeyPress(var UTF8Key: TUTF8Char);
begin
  if FEatChar then
  begin
    FEatChar := False;
    UTF8Key := '';
    Exit;
  end;
  inherited UTF8KeyPress(UTF8Key);
end;

// ------------------------------------------------------------------- cellule

procedure TCsvView.ClearCell;
begin
  if (Col < 1) or (Row < 1) then Exit;
  if CellAt(Col, Row) = '' then Exit;
  PushUndo;
  PutCell(Col, Row, '');
  ClearMatch;
end;

procedure TCsvView.CopyCell;
begin
  if (Col < 1) or (Row < 1) then Exit;
  FClipKind := skNone;
  Clipboard.AsText := CellAt(Col, Row);
end;

procedure TCsvView.CutCell;
begin
  CopyCell;
  ClearCell;
end;

procedure TCsvView.PasteCell;
var
  s: string;
begin
  if (Col < 1) or (Row < 1) then Exit;
  s := Clipboard.AsText;
  // saut final d'une ligne copiee ailleurs: pas dans la cellule
  while (s <> '') and (s[Length(s)] in [#10, #13]) do SetLength(s, Length(s) - 1);
  if s = CellAt(Col, Row) then Exit;
  PushUndo;
  PutCell(Col, Row, s);
  ClearMatch;
end;

// ---------------------------------------------------- lignes/colonnes entieres

procedure TCsvView.CopySel;
var
  i, idx, n, r: Integer;
  sb: TStringBuilder;
  rw: TCsvRow;
begin
  if FSelKind = skNone then begin CopyCell; Exit; end;
  SetLength(FClipRows, 0);
  sb := TStringBuilder.Create;
  try
    if FSelKind = skRows then
    begin
      CurRowsRange(idx, n);
      SetLength(FClipRows, n);
      for i := 0 to n - 1 do
      begin
        FClipRows[i] := FTable.GetRow(idx + i);
        rw := FClipRows[i];
        for r := 0 to High(rw) do
        begin
          if r > 0 then sb.Append(FTable.Delim);
          sb.Append(FTable.QuoteField(rw[r]));
        end;
        sb.Append(LineEnding);
      end;
    end
    else
    begin
      CurColsRange(idx, n);
      SetLength(FClipRows, n);
      for i := 0 to n - 1 do
        FClipRows[i] := FTable.GetColumn(idx + i);
      // une valeur par ligne, colonnes cote a cote
      for r := 0 to FTable.RowCount - 1 do
      begin
        for i := 0 to n - 1 do
        begin
          if i > 0 then sb.Append(FTable.Delim);
          sb.Append(FTable.QuoteField(FClipRows[i][r]));
        end;
        sb.Append(LineEnding);
      end;
    end;
    FClipText := sb.ToString;
  finally
    sb.Free;
  end;
  FClipKind := FSelKind;
  Clipboard.AsText := FClipText;
end;

procedure TCsvView.CutSel;
begin
  if FSelKind = skNone then begin CutCell; Exit; end;
  CopySel;
  DeleteSel;
end;

procedure TCsvView.DeleteSel;
var
  idx, n: Integer;
begin
  if FSelKind = skNone then begin ClearCell; Exit; end;
  PushUndo;
  if FSelKind = skRows then
  begin
    if CurRowsRange(idx, n) then FTable.DeleteRows(idx, n);
  end
  else if CurColsRange(idx, n) then
    FTable.DeleteCols(idx, n);
  FSelKind := skNone;
  AfterStructural;
end;

// colle notre lot de lignes/colonnes devant la position courante, si le
// presse-papiers est encore ce qu'on y a mis; sinon c'est un collage de cellule
function TCsvView.CanGrow(AMoreRows, AMoreCols: Integer): Boolean;
var
  r, c: Int64;
begin
  r := FTable.RowCount + AMoreRows;
  c := Max(FTable.ColCount, 1) + AMoreCols;
  Result := (r <= CsvMaxRows) and (c <= CsvMaxCols) and (r * c <= CsvMaxCells);
  if not Result then
    RtMessageDlg('RottenText',
      Format('The table would exceed %d rows, %d columns or %d cells.',
        [CsvMaxRows, CsvMaxCols, CsvMaxCells]), mtWarning, [mbOK], 0);
end;

procedure TCsvView.PasteSel;
var
  i, idx: Integer;
begin
  if (FClipKind = skNone) or (Length(FClipRows) = 0) or (Clipboard.AsText <> FClipText) then
  begin
    PasteCell;
    Exit;
  end;
  if FClipKind = skRows then
  begin
    if not CanGrow(Length(FClipRows), 0) then Exit;
  end
  else if not CanGrow(0, Length(FClipRows)) then Exit;
  if EditorMode then EditorMode := False;
  PushUndo;
  if FClipKind = skRows then
  begin
    if FSelKind = skRows then idx := DataRow(SelLo) else idx := DataRow(Row);
    for i := 0 to High(FClipRows) do
      FTable.InsertRow(idx + i, FClipRows[i]);
    FSelKind := skRows;
    FSelA := idx + 1 - Ord(FHasHeader);
    FSelB := FSelA + High(FClipRows);
  end
  else
  begin
    if FSelKind = skCols then idx := SelLo - 1 else idx := Col - 1;
    for i := 0 to High(FClipRows) do
      FTable.InsertCol(idx + i, FClipRows[i]);
    FSelKind := skCols;
    FSelA := idx + 1;
    FSelB := FSelA + High(FClipRows);
  end;
  AfterStructural;
end;

procedure TCsvView.DuplicateSel;
var
  idx, n, i: Integer;
  rows: array of TCsvRow;
begin
  if FSelKind = skCols then
  begin
    if not CurColsRange(idx, n) then Exit;
    if not CanGrow(0, n) then Exit;
    PushUndo;
    SetLength(rows, n);
    for i := 0 to n - 1 do rows[i] := FTable.GetColumn(idx + i);
    for i := 0 to n - 1 do FTable.InsertCol(idx + n + i, rows[i]);
    FSelA := idx + n + 1;
    FSelB := FSelA + n - 1;
  end
  else
  begin
    if not CurRowsRange(idx, n) then Exit;
    if not CanGrow(n, 0) then Exit;
    PushUndo;
    SetLength(rows, n);
    for i := 0 to n - 1 do rows[i] := FTable.GetRow(idx + i);
    for i := 0 to n - 1 do FTable.InsertRow(idx + n + i, rows[i]);
    FSelKind := skRows;
    FSelA := idx + n + 1 - Ord(FHasHeader);
    FSelB := FSelA + n - 1;
  end;
  AfterStructural;
end;

procedure TCsvView.InsertRows(ABelow: Boolean);
var
  idx, n, i: Integer;
begin
  if not CurRowsRange(idx, n) then
  begin
    idx := FTable.RowCount;
    n := 1;
  end;
  if ABelow then idx := idx + n;
  if FSelKind <> skRows then n := 1;
  if not CanGrow(n, 0) then Exit;
  PushUndo;
  for i := 0 to n - 1 do FTable.InsertRow(idx, nil);
  FSelKind := skNone;
  AfterStructural;
  Row := idx + 1 - Ord(FHasHeader);
end;

procedure TCsvView.InsertCols(ARight: Boolean);
var
  idx, n, i: Integer;
begin
  if not CurColsRange(idx, n) then
  begin
    idx := FTable.ColCount;
    n := 1;
  end;
  if ARight then idx := idx + n;
  if FSelKind <> skCols then n := 1;
  if not CanGrow(0, n) then Exit;
  PushUndo;
  for i := 0 to n - 1 do FTable.InsertCol(idx, nil);
  FSelKind := skNone;
  AfterStructural;
  Col := idx + 1;
end;

procedure TCsvView.MoveSel(ADelta: Integer; ACols: Boolean);
var
  idx, n: Integer;
  ok: Boolean;
begin
  PushUndo;
  ok := False;
  if (FSelKind = skCols) or (ACols and (FSelKind = skNone)) then
  begin
    if CurColsRange(idx, n) then ok := FTable.MoveCols(idx, n, ADelta);
    if ok then
    begin
      FSelA := FSelA + ADelta;
      FSelB := FSelB + ADelta;
      Col := Col + ADelta;
    end;
  end
  else
  begin
    if CurRowsRange(idx, n) then ok := FTable.MoveRows(idx, n, ADelta);
    if ok then
    begin
      if FSelKind = skRows then
      begin
        FSelA := FSelA + ADelta;
        FSelB := FSelB + ADelta;
      end;
      Row := Row + ADelta;
    end;
  end;
  if ok then AfterStructural
  else DropLastUndo; // bute sur le bord: rien n'a bouge
end;

// ---------------------------------------------------------------- navigation

procedure TCsvView.GotoCell(ACol, ARow: Integer);
begin
  if ACol < 1 then ACol := 1;
  if ACol > ColCount - 1 then ACol := ColCount - 1;
  if ARow < 1 then ARow := 1;
  if ARow > RowCount - 1 then ARow := RowCount - 1;
  Col := ACol;
  Row := ARow;
end;

function TCsvView.CurCol: Integer;
begin
  Result := Col;
end;

function TCsvView.CurRow: Integer;
begin
  Result := Row;
end;

procedure TCsvView.ShowView;
var
  frm: TCustomForm;
begin
  Visible := True;
  BringToFront;
  Invalidate;
  frm := GetParentForm(Self);
  if (frm <> nil) and frm.Visible and CanFocus then
    SetFocus;
end;

procedure TCsvView.HideView;
begin
  if EditorMode then EditorMode := False;
  Visible := False;
end;

// ---------------------------------------------------------------- recherche

function TCsvView.FindNext(const APat: string; ACase, AWord, ABack, AWrap: Boolean): Boolean;
var
  c, r, from, p, steps, total: Integer;
  cols, rows: Integer;
  s: string;
begin
  Result := False;
  if APat = '' then Exit;
  cols := ColCount - 1;
  rows := RowCount - 1;
  c := Col; r := Row;
  if c < 1 then c := 1;
  if r < 1 then r := 1;
  // ancre: l'occurrence courante si elle tient toujours
  if (FMatchCol = c) and (FMatchRow = r) and (FMatchLen > 0) then
  begin
    if ABack then from := FMatchStart // MatchIn rend strictement avant
    else if FReplaced then from := FMatchStart + FMatchLen
    else from := FMatchStart + 1;
  end
  else if ABack then from := MaxInt
  else from := 1;
  total := cols * rows;
  if AWrap then steps := total + 1 else steps := total;
  while steps > 0 do
  begin
    s := CellAt(c, r);
    if ABack and (from = MaxInt) then from := Length(s) + 1;
    p := MatchIn(s, APat, from, ACase, AWord, ABack);
    if p > 0 then
    begin
      ClearSel;
      Col := c;
      Row := r;
      FMatchCol := c; FMatchRow := r;
      FMatchStart := p; FMatchLen := Length(APat);
      FReplaced := False;
      Exit(True);
    end;
    Dec(steps);
    if ABack then
    begin
      Dec(c);
      if c < 1 then begin c := cols; Dec(r); end;
      if r < 1 then
      begin
        if not AWrap then Break;
        r := rows;
      end;
      from := MaxInt;
    end
    else
    begin
      Inc(c);
      if c > cols then begin c := 1; Inc(r); end;
      if r > rows then
      begin
        if not AWrap then Break;
        r := 1;
      end;
      from := 1;
    end;
  end;
  ClearMatch;
end;

function TCsvView.ReplaceCurrent(const APat, ARepl: string; ACase, AWord: Boolean): Boolean;
var
  s: string;
begin
  Result := False;
  if (FMatchLen = 0) or FReplaced or (FMatchCol <> Col) or (FMatchRow <> Row) or
     (Length(APat) <> FMatchLen) then Exit;
  s := CellAt(Col, Row);
  // la cellule a pu etre editee depuis: on ne remplace que si le motif y est encore
  if MatchIn(s, APat, FMatchStart, ACase, AWord, False) <> FMatchStart then Exit;
  s := Copy(s, 1, FMatchStart - 1) + ARepl + Copy(s, FMatchStart + FMatchLen, MaxInt);
  PushUndo;
  PutCell(Col, Row, s);
  FMatchLen := Length(ARepl);
  FReplaced := True;
  Result := True;
end;

function TCsvView.ReplaceAll(const APat, ARepl: string; ACase, AWord: Boolean): Integer;
var
  c, r, p, from: Integer;
  s: string;
begin
  Result := 0;
  if APat = '' then Exit;
  PushUndo;
  for r := 1 to RowCount - 1 do
    for c := 1 to ColCount - 1 do
    begin
      s := CellAt(c, r);
      from := 1;
      repeat
        p := MatchIn(s, APat, from, ACase, AWord, False);
        if p = 0 then Break;
        s := Copy(s, 1, p - 1) + ARepl + Copy(s, p + Length(APat), MaxInt);
        from := p + Length(ARepl);
        Inc(Result);
      until False;
      if s <> CellAt(c, r) then
        FTable[DataRow(r), c - 1] := s;
    end;
  ClearMatch;
  if Result > 0 then
  begin
    Edited;
    Invalidate;
  end
  else
    DropLastUndo;
end;

end.
