unit uDiffView;

{$mode objfpc}{$H+}

// Modal: deux SynEdit cote a cote, alignes ligne a ligne par des fillers, les
// rangees qui different sont teintees. Pane gauche editable, droit en lecture
// seule. Le re-diff live d'une insertion/suppression vide l'undo des deux panes.

interface

uses
  Classes, SynEditHighlighter;

// True si la gauche a ete editee ET que l'utilisateur veut integrer: AResult
// recoit alors le contenu gauche nettoye de ses fillers.
function ShowDiffView(ALeft, ARight: TStrings;
  const ALeftName, ARightName: string; AHighlighter: TSynCustomHighlighter;
  AResult: TStrings): Boolean;

implementation

uses
  SysUtils, Graphics, Controls, Forms, ExtCtrls, StdCtrls, LCLType, Dialogs,
  SynEdit, SynEditTypes, SynGutterLineNumber, SynEditMiscClasses,
  uTheme, uDiff;

type
  TDiffViewForm = class(TForm)
  public
    FLeft, FRight: TSynEdit;
    FSplit: TSplitter;
    FRows: TDiffRows;
    FRightOrig: TStringList;  // droite d'origine (sans filler), base du re-diff
    FDiffBg: TColor;
    FField: Integer;          // largeur du numero de ligne dans le gutter
    FSyncing: Boolean;
    FRealigning: Boolean;     // patch en cours: couper LeftChanged
    FRealignQueued: Boolean;
    FRealignSkipped: Boolean; // buffer trop gros: l'alignement a derive
    FIntegrate: Boolean;
    FUserSplit: Boolean;      // splitter drague: ne plus le recentrer
    destructor Destroy; override;
    procedure FmtLeftNum(Sender: TSynGutterLineNumber; ALine: Integer;
      out AText: string; const ALineInfo: TSynEditGutterLineInfo);
    procedure FmtRightNum(Sender: TSynGutterLineNumber; ALine: Integer;
      out AText: string; const ALineInfo: TSynEditGutterLineInfo);
    procedure LeftSpecial(Sender: TObject; Line: integer;
      var Special: boolean; Markup: TSynSelectedColor);
    procedure RightSpecial(Sender: TObject; Line: integer;
      var Special: boolean; Markup: TSynSelectedColor);
    procedure LeftStatus(Sender: TObject; Changes: TSynStatusChanges);
    procedure RightStatus(Sender: TObject; Changes: TSynStatusChanges);
    procedure LeftChanged(Sender: TObject);
    procedure RealignAsync(Data: PtrInt);
    procedure Realign;
    procedure SplitMoved(Sender: TObject);
    procedure FormResized(Sender: TObject);
    procedure KeyHandler(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure CloseQueryHandler(Sender: TObject; var CanClose: Boolean);
    procedure DoSync(ASrc, ADst: TSynEdit);
    function RowDiffers(AIdx: Integer): Boolean;
    procedure BuildIntegrated(ADest: TStrings);
  end;

function Lum(c: TColor): Integer;
begin
  c := ColorToRGB(c);
  Result := (Red(c) * 30 + Green(c) * 59 + Blue(c) * 11) div 100;
end;

function Mix(c1, c2: TColor; t: Double): TColor;
begin
  c1 := ColorToRGB(c1);
  c2 := ColorToRGB(c2);
  Result := RGBToColor(
    Round(Red(c1)   + (Red(c2)   - Red(c1))   * t),
    Round(Green(c1) + (Green(c2) - Green(c1)) * t),
    Round(Blue(c1)  + (Blue(c2)  - Blue(c1))  * t));
end;

// derivee du theme: eclaircir sur fond sombre, assombrir sur fond clair
function DiffBackground: TColor;
begin
  if Lum(clEditorBg) < 128 then
    Result := Mix(clEditorBg, clWhite, 0.16)
  else
    Result := Mix(clEditorBg, clBlack, 0.10);
end;

procedure TDiffViewForm.DoSync(ASrc, ADst: TSynEdit);
begin
  if FSyncing then Exit;
  FSyncing := True;
  try
    if ADst.TopLine <> ASrc.TopLine then ADst.TopLine := ASrc.TopLine;
    if ADst.LeftChar <> ASrc.LeftChar then ADst.LeftChar := ASrc.LeftChar;
  finally
    FSyncing := False;
  end;
end;

procedure TDiffViewForm.LeftStatus(Sender: TObject; Changes: TSynStatusChanges);
begin
  if Changes * [scTopLine, scLeftChar] <> [] then DoSync(FLeft, FRight);
end;

procedure TDiffViewForm.RightStatus(Sender: TObject; Changes: TSynStatusChanges);
begin
  if Changes * [scTopLine, scLeftChar] <> [] then DoSync(FRight, FLeft);
end;

procedure TDiffViewForm.FmtLeftNum(Sender: TSynGutterLineNumber; ALine: Integer;
  out AText: string; const ALineInfo: TSynEditGutterLineInfo);
var
  num: string;
begin
  if (ALine >= 1) and (ALine <= Length(FRows)) and FRows[ALine - 1].HasLeft then
  begin
    num := IntToStr(FRows[ALine - 1].LeftNo);
    while Length(num) < FField do num := ' ' + num;
    AText := ' ' + num + '  ';
  end
  else
    AText := StringOfChar(' ', FField + 3);
end;

procedure TDiffViewForm.FmtRightNum(Sender: TSynGutterLineNumber; ALine: Integer;
  out AText: string; const ALineInfo: TSynEditGutterLineInfo);
var
  num: string;
begin
  if (ALine >= 1) and (ALine <= Length(FRows)) and FRows[ALine - 1].HasRight then
  begin
    num := IntToStr(FRows[ALine - 1].RightNo);
    while Length(num) < FField do num := ' ' + num;
    AText := ' ' + num + '  ';
  end
  else
    AText := StringOfChar(' ', FField + 3);
end;

// compare le texte COURANT des deux panes, pas le diff fige a l'ouverture: une
// ligne rendue identique perd sa teinte tout de suite
function TDiffViewForm.RowDiffers(AIdx: Integer): Boolean;
begin
  if AIdx < 0 then Exit(False);
  if (AIdx >= FLeft.Lines.Count) or (AIdx >= FRight.Lines.Count) then Exit(True);
  Result := FLeft.Lines[AIdx] <> FRight.Lines[AIdx];
end;

procedure TDiffViewForm.LeftSpecial(Sender: TObject; Line: integer;
  var Special: boolean; Markup: TSynSelectedColor);
begin
  if RowDiffers(Line - 1) then
  begin
    Special := True;
    Markup.Background := FDiffBg;
    Markup.Foreground := clNone; // garder la coloration syntaxique des tokens
  end;
end;

procedure TDiffViewForm.RightSpecial(Sender: TObject; Line: integer;
  var Special: boolean; Markup: TSynSelectedColor);
begin
  if RowDiffers(Line - 1) then
  begin
    Special := True;
    Markup.Background := FDiffBg;
    Markup.Foreground := clNone;
  end;
end;

function BuildAligned(const ARows: TDiffRows; ALeftSide: Boolean): TStringList;
var
  k: Integer;
begin
  Result := TStringList.Create;
  for k := 0 to High(ARows) do
    if ALeftSide then Result.Add(ARows[k].Left)
    else Result.Add(ARows[k].Right);
  if Result.Count = 0 then Result.Add('');
end;

function GutterNum(S: TSynEdit): TSynGutterLineNumber;
var
  i: Integer;
begin
  Result := nil;
  for i := 0 to S.Gutter.Parts.Count - 1 do
    if S.Gutter.Parts[i] is TSynGutterLineNumber then
      Result := TSynGutterLineNumber(S.Gutter.Parts[i]);
end;

destructor TDiffViewForm.Destroy;
begin
  Application.RemoveAsyncCalls(Self);
  FRightOrig.Free;
  inherited Destroy;
end;

// le pane droit ne se repeint pas seul; un nombre de lignes change exige un
// re-diff, poste en async (jamais muter le buffer dans l'OnChange en cours)
procedure TDiffViewForm.LeftChanged(Sender: TObject);
const
  REALIGN_MAX = 100000; // au-dela, re-diff par frappe = gel
begin
  if FRealigning then Exit;
  if FLeft.Lines.Count <> Length(FRows) then
  begin
    if (FLeft.Lines.Count <= REALIGN_MAX) and (Length(FRows) <= REALIGN_MAX) then
    begin
      if not FRealignQueued then
      begin
        FRealignQueued := True;
        Application.QueueAsyncCall(@RealignAsync, 0);
      end;
    end
    else
    begin
      // le flag reste pose: un compte redevenu egal ne prouve pas l'alignement
      FRealignSkipped := True;
      if FRight <> nil then FRight.Invalidate;
    end;
  end
  else if FRight <> nil then
    FRight.Invalidate;
end;

procedure TDiffViewForm.RealignAsync(Data: PtrInt);
begin
  FRealignQueued := False;
  if csDestroying in ComponentState then Exit;
  Realign;
end;

procedure TDiffViewForm.Realign;
var
  rowOf: TIntArray;
  desired: TStringList;
  ln: TSynGutterLineNumber;
  caretX, caretRow, topLn, maxNo, fld, i, r, k: Integer;
begin
  if (FLeft = nil) or (FRight = nil) then Exit;
  FRealigning := True;
  FLeft.BeginUpdate;
  FRight.BeginUpdate;
  try
    caretX := FLeft.CaretX;
    caretRow := FLeft.CaretY - 1; // ligne de buffer 0-base
    topLn := FLeft.TopLine;
    FRows := RealignRows(FRows, FLeft.Lines, FRightOrig, rowOf);
    desired := BuildAligned(FRows, True);
    try
      PatchLines(FLeft.Lines, desired);
    finally
      desired.Free;
    end;
    desired := BuildAligned(FRows, False);
    try
      PatchLines(FRight.Lines, desired);
    finally
      desired.Free;
    end;
    // ligne disparue en filler: prendre la plus proche au-dessus, sinon dessous
    r := 0;
    if Length(rowOf) > 0 then
    begin
      if caretRow > High(rowOf) then caretRow := High(rowOf);
      if caretRow < 0 then caretRow := 0;
      i := caretRow;
      while (i >= 0) and (rowOf[i] < 0) do Dec(i);
      if i < 0 then
      begin
        i := caretRow + 1;
        while (i <= High(rowOf)) and (rowOf[i] < 0) do Inc(i);
        if i > High(rowOf) then i := -1;
      end;
      if i >= 0 then r := rowOf[i];
    end;
    FLeft.CaretXY := Point(caretX, r + 1);
    FLeft.TopLine := topLn;
    // le gutter peut avoir besoin d'un chiffre de plus
    maxNo := 1;
    for k := 0 to High(FRows) do
    begin
      if FRows[k].LeftNo > maxNo then maxNo := FRows[k].LeftNo;
      if FRows[k].RightNo > maxNo then maxNo := FRows[k].RightNo;
    end;
    fld := Length(IntToStr(maxNo));
    if fld < 2 then fld := 2;
    if fld <> FField then
    begin
      FField := fld;
      ln := GutterNum(FLeft);
      if ln <> nil then ln.DigitCount := FField + 3;
      ln := GutterNum(FRight);
      if ln <> nil then ln.DigitCount := FField + 3;
    end;
  finally
    FRight.EndUpdate;
    FLeft.EndUpdate;
    FRealigning := False;
  end;
  // fillers deplaces = positions d'undo fausses, l'historique repart de zero.
  // HORS du BeginUpdate: son undo block doit se refermer avant qu'on le vide
  FLeft.ClearUndo;
  FRight.ClearUndo;
  DoSync(FLeft, FRight);
  FLeft.Invalidate;
  FRight.Invalidate;
end;

procedure TDiffViewForm.SplitMoved(Sender: TObject);
begin
  FUserSplit := True;
end;

// tant que le splitter n'a pas ete drague, la separation reste au milieu
procedure TDiffViewForm.FormResized(Sender: TObject);
begin
  if FUserSplit or (FLeft = nil) or (FSplit = nil) then Exit;
  FLeft.Width := (ClientWidth - FSplit.Width) div 2;
end;

procedure TDiffViewForm.KeyHandler(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if Key = VK_ESCAPE then
  begin
    Key := 0;
    Close;
  end;
end;

// re-diff saute = integration verbatim (fillers devenus lignes vides): le dire
procedure TDiffViewForm.CloseQueryHandler(Sender: TObject; var CanClose: Boolean);
var
  msg: string;
begin
  if (FLeft <> nil) and FLeft.Modified then
  begin
    if FRealignSkipped then
      msg := 'The left side was edited, but the alignment could not follow ' +
        'the inserted/deleted lines (too large for live re-diff).' + LineEnding +
        'Integrating will keep the alignment filler lines as real empty lines.' +
        LineEnding + 'Integrate into the original document anyway?'
    else
      msg := 'The left side was edited. Integrate the changes into the ' +
        'original document?';
    case MessageDlg('RottenText', msg, mtConfirmation,
      [mbYes, mbNo, mbCancel], 0) of
      mrYes: FIntegrate := True;
      mrNo:  FIntegrate := False;
      else   CanClose := False; // Cancel: on reste dans le diff
    end;
  end;
end;

// realignement saute = FRows PERIME: IntegrateLeft ne juge que sur le nombre de
// lignes et prendrait des lignes vides de l'utilisateur pour des fillers
procedure TDiffViewForm.BuildIntegrated(ADest: TStrings);
begin
  if FRealignSkipped then
    ADest.Assign(FLeft.Lines)
  else
    IntegrateLeft(FRows, FLeft.Lines, ADest);
end;

procedure ConfigPane(f: TDiffViewForm; S: TSynEdit; AHl: TSynCustomHighlighter;
  ALeftSide: Boolean);
var
  i: Integer;
  ln: TSynGutterLineNumber;
begin
  S.BorderStyle := bsNone;
  S.ReadOnly := not ALeftSide;
  ApplyEditorTheme(S);
  S.Font.Quality := fqCleartype; // ApplyEditorTheme ne pose pas la qualite
  S.Highlighter := AHl;
  ln := nil;
  for i := 0 to S.Gutter.Parts.Count - 1 do
    if S.Gutter.Parts[i] is TSynGutterLineNumber then
      ln := TSynGutterLineNumber(S.Gutter.Parts[i]);
  if ln <> nil then
  begin
    ln.DigitCount := f.FField + 3;
    if ALeftSide then ln.OnFormatLineNumber := @f.FmtLeftNum
    else ln.OnFormatLineNumber := @f.FmtRightNum;
  end;
  if ALeftSide then
  begin
    S.OnSpecialLineMarkup := @f.LeftSpecial;
    S.OnStatusChange := @f.LeftStatus;
  end
  else
  begin
    S.OnSpecialLineMarkup := @f.RightSpecial;
    S.OnStatusChange := @f.RightStatus;
  end;
end;

function ShowDiffView(ALeft, ARight: TStrings;
  const ALeftName, ARightName: string; AHighlighter: TSynCustomHighlighter;
  AResult: TStrings): Boolean;
var
  f: TDiffViewForm;
  info: TPanel;
  lbl: TLabel;
  ll, rl: TStringList;
  maxNo, removed, added, k: Integer;
  summary: string;
begin
  Result := False;
  f := TDiffViewForm.CreateNew(nil);
  try
    f.FRows := BuildDiffRows(ALeft, ARight);
    f.FRightOrig := TStringList.Create; // base du re-diff
    f.FRightOrig.Assign(ARight);
    f.FDiffBg := DiffBackground;
    maxNo := ALeft.Count;
    if ARight.Count > maxNo then maxNo := ARight.Count;
    if maxNo < 1 then maxNo := 1;
    f.FField := Length(IntToStr(maxNo));
    if f.FField < 2 then f.FField := 2;

    f.Caption := 'Diff:  ' + ALeftName + '   vs   ' + ARightName;
    f.Position := poScreenCenter;
    f.ClientWidth := 1040;
    f.ClientHeight := 700;
    f.KeyPreview := True;
    f.OnKeyDown := @f.KeyHandler;
    f.OnCloseQuery := @f.CloseQueryHandler;
    f.OnResize := @f.FormResized;
    f.Color := clEditorBg;

    removed := 0; added := 0;
    for k := 0 to High(f.FRows) do
      case f.FRows[k].Kind of
        drChange: begin Inc(removed); Inc(added); end;
        drDel:    Inc(removed);
        drAdd:    Inc(added);
      end;
    if (removed = 0) and (added = 0) then summary := 'files are identical'
    else summary := Format('%d removed, %d added', [removed, added]);

    info := TPanel.Create(f);
    info.Parent := f;
    info.Align := alTop;
    info.Height := 26;
    info.BevelOuter := bvNone;
    info.Color := clStatusBg;
    lbl := TLabel.Create(f);
    lbl.Parent := info;
    lbl.Align := alClient;
    lbl.Layout := tlCenter;
    lbl.BorderSpacing.Left := 10;
    lbl.Font.Color := clStatusText;
    lbl.Caption := summary + '        [' + ALeftName + ' - editable]   vs   [' +
      ARightName + ']        (Esc to close)';

    f.FLeft := TSynEdit.Create(f);
    f.FLeft.Parent := f;
    f.FLeft.Align := alLeft;
    f.FLeft.Width := f.ClientWidth div 2;
    f.FLeft.ScrollBars := ssHorizontal; // une seule barre verticale, a droite

    f.FSplit := TSplitter.Create(f);
    f.FSplit.Parent := f;
    f.FSplit.Align := alLeft;
    f.FSplit.Left := f.FLeft.Width + 1;
    f.FSplit.Width := 3;
    f.FSplit.Color := clBorder;
    f.FSplit.ResizeStyle := rsUpdate;
    f.FSplit.OnMoved := @f.SplitMoved;

    f.FRight := TSynEdit.Create(f);
    f.FRight.Parent := f;
    f.FRight.Align := alClient;
    f.FRight.ScrollBars := ssBoth;

    ConfigPane(f, f.FLeft, AHighlighter, True);
    ConfigPane(f, f.FRight, AHighlighter, False);

    ll := BuildAligned(f.FRows, True);
    rl := BuildAligned(f.FRows, False);
    try
      f.FLeft.Lines.Assign(ll);
      f.FRight.Lines.Assign(rl);
    finally
      ll.Free;
      rl.Free;
    end;
    f.FLeft.Modified := False; // l'Assign a marque modifie: repartir propre
    f.FLeft.OnChange := @f.LeftChanged;

    f.ShowModal;

    if f.FIntegrate then
    begin
      f.BuildIntegrated(AResult);
      Result := True;
    end;
  finally
    f.Free;
  end;
end;

end.
