unit uHexView;

{$mode objfpc}{$H+}

// Vue hex+ASCII virtuelle: seuls les octets visibles sont lus (cache 64 Ko),
// donc aucune limite de taille. Edition par ECRASEMENT, jamais d'insertion:
// les octets modifies vivent dans un overlay trie jusqu'au save.

interface

uses
  Classes, SysUtils, Controls, Forms, Graphics, Dialogs, LCLType, Clipbrd,
  uTheme, uSafeSave;

const
  HEX_BPR = 16; // octets par rangee

type
  THexPane = (hpHex, hpAscii);

  TByteEdit = record
    Ofs: Int64;
    Val: Byte;
  end;

  THexView = class(TCustomControl)
  private
    FFileName: string;
    FStream: TFileStream;
    FSize: Int64;
    FTopRow: Int64;
    FCaret: Int64;
    FSelAnchor: Int64;  // -1 = pas de selection
    FSelActive: Boolean;
    FMouseSel: Boolean;
    FNibbleLo: Boolean; // pane hex: quartet bas en cours de frappe
    FPane: THexPane;
    FOfsDigits: Integer;
    FEdits: array of TByteEdit; // overlay trie par Ofs
    FCache: array of Byte;
    FCacheOfs: Int64;
    FCacheLen: Integer;
    FCw, FRowH: Integer; // metriques police, calculees au Paint
    FMarkOfs: Int64;     // match de recherche surligne (-1 = aucun)
    FMarkLen: Integer;
    FDragging: Boolean;
    FDragOffset: Integer;
    FHoverSB: Boolean;
    FOnEdited: TNotifyEvent;
    FOnCaretMove: TNotifyEvent;
    function TotalRows: Int64;
    function VisibleRows: Integer;
    function MaxTopRow: Int64;
    procedure SetTopRow(AValue: Int64);
    procedure EnsureCache(AOfs: Int64);
    function RawByte(AOfs: Int64): Byte;
    function EditIndexOf(AOfs: Int64; out AIdx: Integer): Boolean;
    procedure SetByteAt(AOfs: Int64; AVal: Byte);
    procedure MoveCaret(ADelta: Int64);
    procedure PlaceCaret(AOfs: Int64);
    procedure EnsureVisible;
    function SelLo: Int64;
    function SelHi: Int64;
    function HasSelection: Boolean;
    procedure ClearSelection;
    function OffsetAtDrag(X, Y: Integer): Int64;
    procedure ApplyNibble(ADigit: Integer);
    function ThumbRect: TRect;
    procedure ScrollToThumbTop(AThumbTop: Integer);
    function XHex: Integer;
    function XAscii: Integer;
    function HexCellX(ACol: Integer): Integer;
  protected
    procedure Paint; override;
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
    procedure KeyPress(var Key: char); override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseLeave; override;
    function DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean; override;
    procedure Resize; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure LoadFile(const AFileName: string);
    procedure SaveInPlace;
    procedure SaveCopyAs(const AFileName: string);
    procedure ShowView;
    procedure HideView;
    function EditCount: Integer;
    // fenetre d'octets avec l'overlay applique
    function ReadOverlaid(AOfs: Int64; ALen: Integer): TBytes;
    procedure WriteBytes(AOfs: Int64; const ABytes: array of Byte);
    // edits TRIES et uniques: fusion en une passe, pas de decalage par octet
    procedure ApplySortedEdits(const ANew: array of TByteEdit);
    // blocs chevauches, overlay compris; -1 si rien. ACaseSens=False replie a-z
    function FindPattern(const APat: TBytes; AFrom: Int64;
      ABack, ACaseSens: Boolean): Int64;
    procedure SetMark(AOfs: Int64; ALen: Integer); // len<=0 efface
    procedure GotoOffset(AOfs: Int64);
    procedure SelectAll;
    procedure CopySelection; // hex ou texte selon le pane actif
    property FileName: string read FFileName;
    property FileSize: Int64 read FSize;
    property CaretOfs: Int64 read FCaret;
    property MarkOfs: Int64 read FMarkOfs;
    property MarkLen: Integer read FMarkLen;
    property OfsDigits: Integer read FOfsDigits;
    property OnEdited: TNotifyEvent read FOnEdited write FOnEdited;
    property OnCaretMove: TNotifyEvent read FOnCaretMove write FOnCaretMove;
    property OnEnter; // suivi du groupe actif
  end;

// 'DE AD be ef' ou 'DEADBEEF' -> octets; nombre de chiffres pair exige
function ParseHexBytes(const S: string; out ABytes: TBytes): Boolean;

implementation

const
  CACHE_BLK = 65536;
  SB_W = 14;  // bande scrollbar
  ML = 8;     // marge gauche
  MAX_COPY = 1024 * 1024;

function ParseHexBytes(const S: string; out ABytes: TBytes): Boolean;
var
  i, n, d, hi: Integer;
begin
  ABytes := nil;
  SetLength(ABytes, (Length(S) + 1) div 2);
  n := 0;
  hi := -1;
  d := 0;
  for i := 1 to Length(S) do
  begin
    case S[i] of
      ' ', #9: Continue;
      '0'..'9': d := Ord(S[i]) - Ord('0');
      'a'..'f': d := Ord(S[i]) - Ord('a') + 10;
      'A'..'F': d := Ord(S[i]) - Ord('A') + 10;
    else
      Exit(False);
    end;
    if hi < 0 then
      hi := d
    else
    begin
      ABytes[n] := Byte((hi shl 4) or d);
      Inc(n);
      hi := -1;
    end;
  end;
  SetLength(ABytes, n);
  Result := (hi < 0) and (n > 0);
end;

constructor THexView.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  ControlStyle := ControlStyle + [csOpaque];
  DoubleBuffered := True;
  TabStop := True;
  Color := clEditorBg;
  Font.Name := RTFontName;
  Font.Size := 11;
  Font.Quality := fqCleartype;
  SetLength(FCache, CACHE_BLK);
  FOfsDigits := 8;
  FMarkOfs := -1;
  FSelAnchor := -1;
end;

destructor THexView.Destroy;
begin
  FStream.Free;
  inherited Destroy;
end;

procedure THexView.LoadFile(const AFileName: string);
var
  ns: TFileStream;
begin
  // ouvrir AVANT de lacher l'ancien: un echec laisse la vue sur son stream
  ns := TFileStream.Create(AFileName, fmOpenRead or fmShareDenyNone);
  FStream.Free;
  FStream := ns;
  FFileName := AFileName;
  FSize := FStream.Size;
  SetLength(FEdits, 0);
  FCacheLen := 0;
  FTopRow := 0;
  FCaret := 0;
  FSelAnchor := -1;
  FSelActive := False;
  FMouseSel := False;
  FNibbleLo := False;
  FPane := hpHex;
  FMarkOfs := -1;
  FMarkLen := 0;
  FOfsDigits := 8;
  while (FOfsDigits < 16) and (FSize > Int64(1) shl (4 * FOfsDigits)) do
    Inc(FOfsDigits);
  Invalidate;
  if Assigned(FOnCaretMove) then FOnCaretMove(Self);
end;

function THexView.EditCount: Integer;
begin
  Result := Length(FEdits);
end;

// ---------- acces octets

procedure THexView.EnsureCache(AOfs: Int64);
var
  blk: Int64;
begin
  blk := (AOfs div CACHE_BLK) * CACHE_BLK;
  if (FCacheLen > 0) and (FCacheOfs = blk) then Exit;
  FCacheLen := 0;
  if FStream = nil then Exit;
  FStream.Position := blk;
  FCacheLen := FStream.Read(FCache[0], CACHE_BLK);
  FCacheOfs := blk;
end;

function THexView.RawByte(AOfs: Int64): Byte;
begin
  EnsureCache(AOfs);
  if (AOfs >= FCacheOfs) and (AOfs < FCacheOfs + FCacheLen) then
    Result := FCache[AOfs - FCacheOfs]
  else
    Result := 0;
end;

function THexView.EditIndexOf(AOfs: Int64; out AIdx: Integer): Boolean;
var
  lo, hi, mid: Integer;
begin
  lo := 0;
  hi := High(FEdits);
  while lo <= hi do
  begin
    mid := (lo + hi) div 2;
    if FEdits[mid].Ofs = AOfs then
    begin
      AIdx := mid;
      Exit(True);
    end;
    if FEdits[mid].Ofs < AOfs then lo := mid + 1 else hi := mid - 1;
  end;
  AIdx := lo; // point d'insertion
  Result := False;
end;

function THexView.ReadOverlaid(AOfs: Int64; ALen: Integer): TBytes;
var
  n, m, idx: Integer;
  p: Int64;
begin
  Result := nil;
  if AOfs < 0 then AOfs := 0;
  if AOfs + ALen > FSize then ALen := Integer(FSize - AOfs);
  if ALen <= 0 then Exit;
  SetLength(Result, ALen);
  n := 0;
  while n < ALen do
  begin
    p := AOfs + n;
    EnsureCache(p);
    m := FCacheLen - Integer(p - FCacheOfs);
    if m <= 0 then Break;
    if m > ALen - n then m := ALen - n;
    Move(FCache[p - FCacheOfs], Result[n], m);
    Inc(n, m);
  end;
  SetLength(Result, n);
  EditIndexOf(AOfs, idx); // premier edit >= AOfs
  while (idx <= High(FEdits)) and (FEdits[idx].Ofs < AOfs + n) do
  begin
    Result[FEdits[idx].Ofs - AOfs] := FEdits[idx].Val;
    Inc(idx);
  end;
end;

procedure THexView.SetByteAt(AOfs: Int64; AVal: Byte);
var
  idx, i: Integer;
begin
  if (AOfs < 0) or (AOfs >= FSize) then Exit;
  if EditIndexOf(AOfs, idx) then
  begin
    if AVal = RawByte(AOfs) then
    begin
      // retour a l'octet d'origine: l'edit disparait
      for i := idx to High(FEdits) - 1 do
        FEdits[i] := FEdits[i + 1];
      SetLength(FEdits, Length(FEdits) - 1);
    end
    else
      FEdits[idx].Val := AVal;
  end
  else if AVal <> RawByte(AOfs) then
  begin
    SetLength(FEdits, Length(FEdits) + 1);
    for i := High(FEdits) downto idx + 1 do
      FEdits[i] := FEdits[i - 1];
    FEdits[idx].Ofs := AOfs;
    FEdits[idx].Val := AVal;
  end
  else
    Exit;
  Invalidate;
  if Assigned(FOnEdited) then FOnEdited(Self);
end;

procedure THexView.WriteBytes(AOfs: Int64; const ABytes: array of Byte);
var
  i: Integer;
begin
  for i := 0 to High(ABytes) do
    SetByteAt(AOfs + i, ABytes[i]);
end;

procedure THexView.ApplySortedEdits(const ANew: array of TByteEdit);
var
  merged: array of TByteEdit;
  take: TByteEdit;
  i, j, k: Integer;
  useNew: Boolean;
begin
  if Length(ANew) = 0 then Exit;
  SetLength(merged, Length(FEdits) + Length(ANew));
  i := 0;
  j := 0;
  k := 0;
  while (i < Length(FEdits)) or (j < Length(ANew)) do
  begin
    if j > High(ANew) then
      useNew := False
    else if i > High(FEdits) then
      useNew := True
    else if ANew[j].Ofs = FEdits[i].Ofs then
    begin
      useNew := True;
      Inc(i); // meme offset: le nouveau gagne
    end
    else
      useNew := ANew[j].Ofs < FEdits[i].Ofs;
    if useNew then
    begin
      take := ANew[j];
      Inc(j);
    end
    else
    begin
      take := FEdits[i];
      Inc(i);
    end;
    // un octet identique a l'original n'est pas un edit
    if take.Val <> RawByte(take.Ofs) then
    begin
      merged[k] := take;
      Inc(k);
    end;
  end;
  SetLength(merged, k);
  FEdits := merged;
  Invalidate;
  if Assigned(FOnEdited) then FOnEdited(Self);
end;

// ---------- recherche

function FoldByte(AB: Byte; ACaseSens: Boolean): Byte; inline;
begin
  if (not ACaseSens) and (AB >= Ord('a')) and (AB <= Ord('z')) then
    Result := AB - 32
  else
    Result := AB;
end;

function MatchAt(const ABuf: TBytes; AIdx: Integer; const APat: TBytes;
  ACaseSens: Boolean): Boolean;
var
  j: Integer;
begin
  if AIdx + Length(APat) > Length(ABuf) then Exit(False);
  for j := 0 to High(APat) do
    if FoldByte(ABuf[AIdx + j], ACaseSens) <> FoldByte(APat[j], ACaseSens) then
      Exit(False);
  Result := True;
end;

function THexView.FindPattern(const APat: TBytes; AFrom: Int64;
  ABack, ACaseSens: Boolean): Int64;
const
  BLK = 1024 * 1024;
var
  buf: TBytes;
  base, hi: Int64;
  i, n, m: Integer;
begin
  Result := -1;
  m := Length(APat);
  if (m = 0) or (m > FSize) then Exit;
  if not ABack then
  begin
    if AFrom < 0 then AFrom := 0;
    base := AFrom;
    while base <= FSize - m do
    begin
      buf := ReadOverlaid(base, BLK);
      n := Length(buf);
      if n < m then Break;
      for i := 0 to n - m do
        if MatchAt(buf, i, APat, ACaseSens) then Exit(base + i);
      base := base + (n - m + 1); // bloc suivant, chevauche de m-1 octets
    end;
  end
  else
  begin
    // AFrom = dernier depart de match autorise
    hi := AFrom;
    if hi > FSize - m then hi := FSize - m;
    while hi >= 0 do
    begin
      base := hi - BLK;
      if base < 0 then base := 0;
      buf := ReadOverlaid(base, Integer(hi - base) + m);
      for i := Integer(hi - base) downto 0 do
        if MatchAt(buf, i, APat, ACaseSens) then Exit(base + i);
      if base = 0 then Break;
      hi := base - 1;
    end;
  end;
end;

procedure THexView.SetMark(AOfs: Int64; ALen: Integer);
begin
  if ALen <= 0 then
  begin
    AOfs := -1;
    ALen := 0;
  end;
  if (FMarkOfs = AOfs) and (FMarkLen = ALen) then Exit;
  FMarkOfs := AOfs;
  FMarkLen := ALen;
  Invalidate;
end;

// ---------- sauvegarde

procedure THexView.SaveInPlace;
var
  ws: TFileStream;
  i: Integer;
begin
  if Length(FEdits) = 0 then Exit;
  ws := TFileStream.Create(FFileName, fmOpenReadWrite or fmShareDenyNone);
  try
    // les offsets d'edit datent du load: si la taille a change en externe, les
    // seek+write viseraient des offsets perimes (fichier a trous)
    if ws.Size <> FSize then
      raise EStreamError.CreateFmt(
        '%s changed size on disk (%d -> %d bytes) since it was opened.' +
        LineEnding + 'Use Save As to write your edits to a new file.',
        [FFileName, FSize, ws.Size]);
    for i := 0 to High(FEdits) do
    begin
      ws.Position := FEdits[i].Ofs;
      ws.WriteBuffer(FEdits[i].Val, 1);
    end;
  finally
    ws.Free;
  end;
  SetLength(FEdits, 0);
  FCacheLen := 0;
  Invalidate;
end;

procedure THexView.SaveCopyAs(const AFileName: string);
const
  BLK = 1024 * 1024;
var
  os: TStream;
  buf: TBytes;
  ofs, c, t: Int64;
  tmp, origName: string;
  ok, reopened: Boolean;
begin
  // un save precedent a pu vider l'etat: ne jamais ecrire un fichier vide
  if FStream = nil then
    raise EStreamError.Create(
      'Hex view is not loaded (a previous save failed); cannot save.');
  if SameFileName(AFileName, FFileName) then
  begin
    SaveInPlace;
    Exit;
  end;
  // toujours temp + rename: une destination qui est un alias de la source
  // (hardlink, chemin 8.3) serait TRONQUEE par un fmCreate avant relecture
  os := CreateTempIn(AFileName, tmp);
  try
    try
      ofs := 0;
      while ofs < FSize do
      begin
        buf := ReadOverlaid(ofs, BLK);
        // ReadOverlaid rend 0 octet sur ECHEC de lecture, pas seulement en EOF:
        // le prendre pour une fin de fichier ecrirait une copie tronquee
        if Length(buf) = 0 then
          raise EStreamError.CreateFmt('Read failed at offset %d of %s',
            [ofs, FFileName]);
        os.WriteBuffer(buf[0], Length(buf));
        Inc(ofs, Length(buf));
      end;
    finally
      os.Free;
    end;
  except
    DeleteFile(tmp);
    raise;
  end;
  c := FCaret;
  t := FTopRow;
  // la destination peut etre un alias de la source: lacher notre handle avant
  FreeAndNil(FStream);
  ok := ReplaceByRename(tmp, AFileName);
  if not ok then
  begin
    // source et destination intactes, edits toujours en memoire
    origName := FFileName;
    reopened := False;
    try
      FStream := TFileStream.Create(FFileName, fmOpenRead or fmShareDenyNone);
      reopened := True;
    except
    end;
    if reopened then
    begin
      DeleteFile(tmp);
      raise EStreamError.CreateFmt('Cannot save as %s', [AFileName]);
    end;
    // double echec: basculer la vue sur le TEMP (copie complete) plutot que la
    // vider, sinon un retry Save As ecrirait un fichier vide. tmp CONSERVE.
    try
      LoadFile(tmp);
    except
      FStream := nil;
      FSize := 0;
      SetLength(FEdits, 0);
      FCacheLen := 0;
    end;
    raise EStreamError.CreateFmt(
      'Cannot save as %s and cannot reopen %s.' + LineEnding +
      'Your full edited copy is preserved (and shown if possible) in:' +
      LineEnding + '%s', [AFileName, origName, tmp]);
  end;
  // le save est FAIT: une reouverture ratee (verrou, antivirus) ne doit pas
  // remonter d'erreur, elle ferait croire a un echec du save
  try
    LoadFile(AFileName);
  except
    Sleep(150);
    try
      LoadFile(AFileName);
    except
      FFileName := AFileName;
      FSize := 0;
      SetLength(FEdits, 0);
      FCacheLen := 0;
      FTopRow := 0;
      FCaret := 0;
      FMarkOfs := -1;
      FMarkLen := 0;
      Invalidate;
      MessageDlg('RottenText',
        Format('Saved %s, but reopening it failed (file locked?).' + LineEnding +
          'Use File > Revert File to reload it.', [AFileName]),
        mtWarning, [mbOK], 0);
    end;
  end;
  SetTopRow(t);
  PlaceCaret(c);
end;

// ---------- geometrie

function THexView.TotalRows: Int64;
begin
  Result := (FSize + HEX_BPR - 1) div HEX_BPR;
end;

function THexView.VisibleRows: Integer;
var
  rh: Integer;
begin
  rh := FRowH;
  if rh <= 0 then rh := 17;
  Result := ClientHeight div rh;
  if Result < 1 then Result := 1;
end;

function THexView.MaxTopRow: Int64;
begin
  Result := TotalRows - VisibleRows;
  if Result < 0 then Result := 0;
end;

procedure THexView.SetTopRow(AValue: Int64);
begin
  if AValue < 0 then AValue := 0;
  if AValue > MaxTopRow then AValue := MaxTopRow;
  if AValue = FTopRow then Exit;
  FTopRow := AValue;
  Invalidate;
end;

function THexView.XHex: Integer;
begin
  Result := ML + (FOfsDigits + 2) * FCw;
end;

function THexView.HexCellX(ACol: Integer): Integer;
begin
  Result := XHex + (ACol * 3 + Ord(ACol >= 8)) * FCw; // gap au milieu
end;

function THexView.XAscii: Integer;
begin
  Result := XHex + (HEX_BPR * 3 + 1 + 2) * FCw;
end;

// ---------- caret

procedure THexView.PlaceCaret(AOfs: Int64);
begin
  if FSize <= 0 then Exit;
  if AOfs < 0 then AOfs := 0;
  if AOfs > FSize - 1 then AOfs := FSize - 1;
  FCaret := AOfs;
  FNibbleLo := False;
  EnsureVisible;
  Invalidate;
  if Assigned(FOnCaretMove) then FOnCaretMove(Self);
end;

procedure THexView.MoveCaret(ADelta: Int64);
begin
  PlaceCaret(FCaret + ADelta);
end;

procedure THexView.GotoOffset(AOfs: Int64);
begin
  ClearSelection; // un saut n'etend pas la selection courante
  PlaceCaret(AOfs);
end;

procedure THexView.EnsureVisible;
var
  row: Int64;
  vis: Integer;
begin
  row := FCaret div HEX_BPR;
  vis := VisibleRows;
  if row < FTopRow then
    SetTopRow(row)
  else if row >= FTopRow + vis then
    SetTopRow(row - vis + 1);
end;

// ---------- selection

function THexView.SelLo: Int64;
begin
  if FSelAnchor < FCaret then Result := FSelAnchor else Result := FCaret;
end;

function THexView.SelHi: Int64;
begin
  if FSelAnchor > FCaret then Result := FSelAnchor else Result := FCaret;
end;

function THexView.HasSelection: Boolean;
begin
  // ne PAS deduire de anchor <> caret: une selection d'UN octet est valide.
  // Les cas fantomes sont neutralises a la source (KeyDown / MouseDown).
  Result := FSelActive and (FSelAnchor >= 0);
end;

procedure THexView.ClearSelection;
begin
  if not FSelActive then Exit;
  FSelActive := False;
  FSelAnchor := -1;
  Invalidate;
end;

procedure THexView.SelectAll;
begin
  if FSize <= 0 then Exit;
  FSelAnchor := 0;
  FSelActive := True;
  PlaceCaret(FSize - 1);
end;

procedure THexView.CopySelection;
var
  lo, hi, selLen: Int64;
  n, i, k: Integer;
  data: TBytes;
  s: string;
  b: Byte;

  function HexDigit(AV: Byte): Char;
  begin
    if AV < 10 then Result := Chr(Ord('0') + AV)
    else Result := Chr(Ord('A') + AV - 10);
  end;

begin
  if not HasSelection then Exit;
  lo := SelLo;
  hi := SelHi;
  // Int64 obligatoire: une selection > 2 Go deborderait un Integer en negatif
  // et passerait sous le plafond
  selLen := hi - lo + 1;
  if selLen > MAX_COPY then
  begin
    MessageDlg('RottenText',
      Format('Selection too large to copy (%d bytes, max %d).', [selLen, MAX_COPY]),
      mtWarning, [mbOK], 0);
    Exit;
  end;
  n := Integer(selLen);
  data := ReadOverlaid(lo, n);
  n := Length(data);
  if n = 0 then Exit;
  if FPane = hpAscii then
  begin
    SetLength(s, n);
    for i := 0 to n - 1 do
      if (data[i] >= 32) and (data[i] <= 126) then s[i + 1] := Chr(data[i])
      else s[i + 1] := '.';
  end
  else
  begin
    SetLength(s, n * 3 - 1);
    k := 1;
    for i := 0 to n - 1 do
    begin
      b := data[i];
      s[k] := HexDigit(b shr 4);
      s[k + 1] := HexDigit(b and $0F);
      Inc(k, 2);
      if i < n - 1 then
      begin
        s[k] := ' ';
        Inc(k);
      end;
    end;
  end;
  Clipboard.AsText := s;
end;

// octet vise par un drag: clampe a la grille, pane fige sur celui du depart
function THexView.OffsetAtDrag(X, Y: Integer): Int64;
var
  row: Int64;
  col: Integer;
begin
  if (FCw <= 0) or (FRowH <= 0) then Exit(FCaret);
  if Y < 0 then row := FTopRow - 1
  else row := FTopRow + Y div FRowH;
  if FPane = hpAscii then
    col := (X - XAscii) div FCw
  else
    col := (X - XHex) div (3 * FCw); // gap du milieu ignore, approx suffisante
  if col < 0 then col := 0;
  if col > HEX_BPR - 1 then col := HEX_BPR - 1;
  Result := row * HEX_BPR + col;
  if Result < 0 then Result := 0;
  if Result > FSize - 1 then Result := FSize - 1;
end;

// ---------- clavier

procedure THexView.KeyDown(var Key: Word; Shift: TShiftState);
var
  shiftMove: Boolean;
begin
  inherited KeyDown(Key, Shift);
  if ssModifier in Shift then
    case Key of
      VK_A: begin SelectAll; Key := 0; Exit; end;
      VK_C: begin CopySelection; Key := 0; Exit; end;
    end;
  // l'ancre est posee AVANT le deplacement
  shiftMove := False;
  case Key of
    VK_LEFT, VK_RIGHT, VK_UP, VK_DOWN, VK_PRIOR, VK_NEXT, VK_HOME, VK_END:
      if ssShift in Shift then
      begin
        shiftMove := True;
        if not FSelActive then FSelAnchor := FCaret;
      end
      else
      begin
        FSelActive := False;
        FSelAnchor := -1;
      end;
  end;
  case Key of
    VK_LEFT:  MoveCaret(-1);
    VK_RIGHT: MoveCaret(1);
    VK_UP:    MoveCaret(-HEX_BPR);
    VK_DOWN:  MoveCaret(HEX_BPR);
    VK_PRIOR: MoveCaret(-Int64(VisibleRows) * HEX_BPR);
    VK_NEXT:  MoveCaret(Int64(VisibleRows) * HEX_BPR);
    VK_HOME:
      if ssModifier in Shift then PlaceCaret(0)
      else PlaceCaret(FCaret - FCaret mod HEX_BPR);
    VK_END:
      if ssModifier in Shift then PlaceCaret(FSize - 1)
      else PlaceCaret(FCaret - FCaret mod HEX_BPR + HEX_BPR - 1);
    VK_TAB:
      begin
        if FPane = hpHex then FPane := hpAscii else FPane := hpHex;
        FNibbleLo := False;
        Invalidate;
      end;
  else
    Exit; // pas a nous, ne pas manger la touche
  end;
  // caret clampe ou revenu pile sur l'ancre = selection vide, pas d'octet fantome
  if shiftMove then
    FSelActive := (FSelAnchor >= 0) and (FCaret <> FSelAnchor);
  Key := 0;
end;

procedure THexView.ApplyNibble(ADigit: Integer);
var
  idx: Integer;
  b: Byte;
begin
  if EditIndexOf(FCaret, idx) then b := FEdits[idx].Val else b := RawByte(FCaret);
  if not FNibbleLo then
  begin
    SetByteAt(FCaret, (ADigit shl 4) or (b and $0F));
    FNibbleLo := True;
    Invalidate;
  end
  else
  begin
    SetByteAt(FCaret, (b and $F0) or ADigit);
    MoveCaret(1); // remet FNibbleLo a False
  end;
end;

procedure THexView.KeyPress(var Key: char);
var
  c: char;
begin
  inherited KeyPress(Key);
  if FSize <= 0 then Exit;
  if FPane = hpHex then
  begin
    c := UpCase(Key);
    case c of
      '0'..'9': begin ClearSelection; ApplyNibble(Ord(c) - Ord('0')); end;
      'A'..'F': begin ClearSelection; ApplyNibble(Ord(c) - Ord('A') + 10); end;
    else
      Exit;
    end;
    Key := #0;
  end
  else if (Key >= #32) and (Key <= #126) then
  begin
    // pane ASCII: 7 bits seulement, au-dela il faut passer par le pane hex
    ClearSelection;
    SetByteAt(FCaret, Ord(Key));
    MoveCaret(1);
    Key := #0;
  end;
end;

// ---------- souris + scrollbar

function THexView.ThumbRect: TRect;
var
  total, vis: Int64;
  h, thumbH, thumbTop: Integer;
begin
  Result := Rect(0, 0, 0, 0);
  total := TotalRows;
  vis := VisibleRows;
  h := ClientHeight;
  if (total <= vis) or (h <= 0) then Exit;
  thumbH := Round(vis / total * h);
  if thumbH < 24 then thumbH := 24;
  thumbTop := Round(FTopRow / (total - vis) * (h - thumbH));
  if thumbTop + thumbH > h then thumbTop := h - thumbH;
  if thumbTop < 0 then thumbTop := 0;
  Result := Rect(ClientWidth - SB_W + 3, thumbTop, ClientWidth - 3, thumbTop + thumbH);
end;

procedure THexView.ScrollToThumbTop(AThumbTop: Integer);
var
  total, vis: Int64;
  h, thumbH: Integer;
  frac: Double;
begin
  total := TotalRows;
  vis := VisibleRows;
  h := ClientHeight;
  if total <= vis then Exit;
  thumbH := Round(vis / total * h);
  if thumbH < 24 then thumbH := 24;
  if h - thumbH <= 0 then Exit;
  frac := AThumbTop / (h - thumbH);
  if frac < 0 then frac := 0;
  if frac > 1 then frac := 1;
  SetTopRow(Round(frac * (total - vis)));
end;

procedure THexView.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  r: TRect;
  row, o: Int64;
  col, nib: Integer;
  nibLo: Boolean;
begin
  inherited MouseDown(Button, Shift, X, Y);
  if Button <> mbLeft then Exit;
  SetFocus;
  if X >= ClientWidth - SB_W then
  begin
    r := ThumbRect;
    if (Y >= r.Top) and (Y < r.Bottom) then
    begin
      FDragging := True;
      FDragOffset := Y - r.Top;
    end
    else if Y < r.Top then
      SetTopRow(FTopRow - VisibleRows)
    else
      SetTopRow(FTopRow + VisibleRows);
    Exit;
  end;
  if (FCw <= 0) or (FRowH <= 0) or (FSize <= 0) then Exit;
  row := FTopRow + Y div FRowH;
  o := -1;
  nibLo := False;
  if (X >= XAscii) and (X < XAscii + HEX_BPR * FCw) then
  begin
    FPane := hpAscii;
    col := (X - XAscii) div FCw;
    o := row * HEX_BPR + col;
  end
  else if X >= XHex then
    for col := 0 to HEX_BPR - 1 do
      if (X >= HexCellX(col)) and (X < HexCellX(col) + 3 * FCw) then
      begin
        FPane := hpHex;
        nib := (X - HexCellX(col)) div FCw;
        o := row * HEX_BPR + col;
        nibLo := nib = 1;
        Break;
      end;
  if o < 0 then Exit;
  if o > FSize - 1 then o := FSize - 1;
  if ssShift in Shift then
  begin
    if not FSelActive then FSelAnchor := FCaret;
  end
  else
  begin
    FSelActive := False;
    FSelAnchor := o;
  end;
  FMouseSel := True;
  PlaceCaret(o);
  // shift-clic pile sur l'ancre = pas de selection
  if ssShift in Shift then
    FSelActive := (FSelAnchor >= 0) and (o <> FSelAnchor);
  FNibbleLo := nibLo and (FPane = hpHex);
  Invalidate;
end;

procedure THexView.MouseMove(Shift: TShiftState; X, Y: Integer);
var
  hov: Boolean;
  o: Int64;
begin
  inherited MouseMove(Shift, X, Y);
  if FDragging then
  begin
    ScrollToThumbTop(Y - FDragOffset);
    Exit;
  end;
  if FMouseSel and (ssLeft in Shift) then
  begin
    o := OffsetAtDrag(X, Y);
    if o <> FCaret then
    begin
      FSelActive := o <> FSelAnchor; // revenu sur l'ancre = plus de selection
      PlaceCaret(o); // EnsureVisible: auto-scroll pres des bords
    end;
    Exit;
  end;
  hov := X >= ClientWidth - SB_W;
  if hov <> FHoverSB then
  begin
    FHoverSB := hov;
    Invalidate;
  end;
end;

procedure THexView.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseUp(Button, Shift, X, Y);
  FDragging := False;
  FMouseSel := False;
end;

procedure THexView.MouseLeave;
begin
  inherited MouseLeave;
  if FHoverSB then
  begin
    FHoverSB := False;
    Invalidate;
  end;
end;

function THexView.DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean;
begin
  SetTopRow(FTopRow - (WheelDelta div 120) * 3);
  Result := True;
end;

procedure THexView.Resize;
begin
  inherited Resize;
  SetTopRow(FTopRow); // reclamp si la fenetre grandit
  Invalidate;
end;

// ---------- affichage

procedure THexView.ShowView;
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

procedure THexView.HideView;
begin
  Visible := False;
end;

procedure THexView.Paint;
var
  r, cnt, col, y, idx, ax: Integer;
  rowOfs, o: Int64;
  v: Byte;
  edited, insel: Boolean;
  s, ch: string;
  cb: TColor;
  tr: TRect;
begin
  Canvas.Font := Font;
  FCw := Canvas.TextWidth('0');
  FRowH := Canvas.TextHeight('Ag') + 2;
  Canvas.Brush.Color := clEditorBg;
  Canvas.FillRect(ClientRect);
  Canvas.Brush.Style := bsClear;

  for r := 0 to VisibleRows do
  begin
    rowOfs := (FTopRow + r) * HEX_BPR;
    if rowOfs >= FSize then Break;
    y := r * FRowH + 1;
    cnt := HEX_BPR;
    if rowOfs + cnt > FSize then cnt := Integer(FSize - rowOfs);
    Canvas.Font.Color := clGutterFg;
    Canvas.TextOut(ML, y, IntToHex(rowOfs, FOfsDigits));
    for col := 0 to cnt - 1 do
    begin
      o := rowOfs + col;
      edited := EditIndexOf(o, idx);
      if edited then v := FEdits[idx].Val else v := RawByte(o);
      if edited then cb := clCodeNumber
      else if v = 0 then cb := clCodeComment
      else cb := clEditorFg;
      s := IntToHex(v, 2);

      // fond sous les deux panes: match de recherche OU selection
      insel := ((FMarkLen > 0) and (o >= FMarkOfs) and (o < FMarkOfs + FMarkLen)) or
               (HasSelection and (o >= SelLo) and (o <= SelHi));
      if insel then
      begin
        Canvas.Brush.Style := bsSolid;
        Canvas.Brush.Color := clSelectionBg;
        Canvas.FillRect(Rect(HexCellX(col) - 1, y - 1,
          HexCellX(col) + 2 * FCw + 1, y - 1 + FRowH));
        Canvas.FillRect(Rect(XAscii + col * FCw, y - 1,
          XAscii + (col + 1) * FCw, y - 1 + FRowH));
        Canvas.Brush.Style := bsClear;
        // la selection ecrase la couleur de l'octet, sinon glyphe illisible
        // sur un fond de selection clair
        cb := clSelectionFg;
      end;

      if o = FCaret then
      begin
        if FPane = hpHex then
        begin
          // bloc inverse sur le quartet actif
          tr.Left := HexCellX(col) + Ord(FNibbleLo) * FCw;
          tr.Top := y - 1;
          tr.Right := tr.Left + FCw;
          tr.Bottom := tr.Top + FRowH;
          Canvas.Brush.Style := bsSolid;
          Canvas.Brush.Color := clCaret;
          Canvas.FillRect(tr);
          Canvas.Brush.Style := bsClear;
          if FNibbleLo then
          begin
            Canvas.Font.Color := cb;
            Canvas.TextOut(HexCellX(col), y, s[1]);
            Canvas.Font.Color := clEditorBg;
            Canvas.TextOut(HexCellX(col) + FCw, y, s[2]);
          end
          else
          begin
            Canvas.Font.Color := clEditorBg;
            Canvas.TextOut(HexCellX(col), y, s[1]);
            Canvas.Font.Color := cb;
            Canvas.TextOut(HexCellX(col) + FCw, y, s[2]);
          end;
        end
        else
        begin
          Canvas.Font.Color := cb;
          Canvas.TextOut(HexCellX(col), y, s);
          tr := Rect(HexCellX(col) - 1, y - 1, HexCellX(col) + 2 * FCw + 1, y - 1 + FRowH);
          Canvas.Brush.Style := bsSolid;
          Canvas.Brush.Color := clGutterCurBg;
          Canvas.FrameRect(tr);
          Canvas.Brush.Style := bsClear;
        end;
      end
      else
      begin
        Canvas.Font.Color := cb;
        Canvas.TextOut(HexCellX(col), y, s);
      end;

      ax := XAscii + col * FCw;
      if (v >= 32) and (v <= 126) then
        ch := Chr(v)
      else
      begin
        ch := '.';
        if not (edited or insel) then cb := clCodeComment;
      end;
      if o = FCaret then
      begin
        if FPane = hpAscii then
        begin
          tr := Rect(ax, y - 1, ax + FCw, y - 1 + FRowH);
          Canvas.Brush.Style := bsSolid;
          Canvas.Brush.Color := clCaret;
          Canvas.FillRect(tr);
          Canvas.Brush.Style := bsClear;
          Canvas.Font.Color := clEditorBg;
          Canvas.TextOut(ax, y, ch);
        end
        else
        begin
          Canvas.Font.Color := cb;
          Canvas.TextOut(ax, y, ch);
          tr := Rect(ax - 1, y - 1, ax + FCw + 1, y - 1 + FRowH);
          Canvas.Brush.Style := bsSolid;
          Canvas.Brush.Color := clGutterCurBg;
          Canvas.FrameRect(tr);
          Canvas.Brush.Style := bsClear;
        end;
      end
      else
      begin
        Canvas.Font.Color := cb;
        Canvas.TextOut(ax, y, ch);
      end;
    end;
  end;

  tr := ThumbRect;
  if tr.Bottom > tr.Top then
  begin
    Canvas.Brush.Style := bsSolid;
    if FHoverSB or FDragging then Canvas.Brush.Color := clTabStrip
    else Canvas.Brush.Color := clTabHover;
    Canvas.Pen.Color := Canvas.Brush.Color;
    Canvas.RoundRect(tr.Left, tr.Top, tr.Right, tr.Bottom, 6, 6);
  end;
  Canvas.Brush.Style := bsSolid;
end;

end.
