unit uCsv;

{$mode objfpc}{$H+}

// Table CSV en memoire, RFC 4180 lu avec indulgence. Cellules verbatim, "007"
// reste "007": on n'est pas Excel, on ne devine pas des dates.

interface

uses
  Classes, SysUtils, Math, LazUTF8;

const
  CsvTableMaxBytes = 128 * 1024 * 1024; // au-dela, texte seulement
  CsvMaxCols = 4096;
  CsvMaxRows = 1000000;    // une chaine par cellule: 1 Mo de lignes vides = 80 Mo
  // borne aussi lignes x colonnes: la grille LCL alloue un pointeur par case du
  // rectangle complet, cellules absentes comprises
  CsvMaxCells = 4000000;

type
  TCsvRow = array of string;
  ECsvTooBig = class(Exception);

  TCsvTable = class
  private
    FRows: array of TCsvRow;
    FQuoted: array of array of Boolean; // cellule lue entre quotes: re-emise telle quelle
    FRowCount: Integer;
    FColCount: Integer;
    FDelim: Char;
    FQuoteAll: Boolean;
    function GetCell(ARow, ACol: Integer): string;
    procedure SetCell(ARow, ACol: Integer; const AValue: string);
    procedure RecalcCols;
    procedure EnsureQ(ARow: Integer); // FQuoted[r] a la taille de la ligne
  public
    constructor Create;
    procedure Clear;
    // AHint: extension du fichier, '.tsv' pousse la tabulation. Leve au-dela
    // de CsvMaxRows/Cols/Cells, la table est alors vide.
    procedure Parse(const AText: string; const AHint: string = '');
    // AEol entre les enregistrements seulement, les cellules gardent leurs sauts
    function Serialize(ATrailingEol: Boolean; const AEol: string = #10): string;
    function QuoteField(const S: string): string;
    procedure AppendRow(const ARow: TCsvRow);
    // ADesc: inverse. AFirst: premiere ligne triee (1 = en-tete epargne).
    // False = l'ordre n'a pas bouge
    function SortByColumn(ACol: Integer; ADesc: Boolean; AFirst: Integer): Boolean;
    function ColumnIsNumeric(ACol, AFirst: Integer): Boolean;
    // premiere ligne = noms de champs ? Oui seulement si elle est textuelle la
    // ou le reste est numerique; sans nombre nulle part, on ne devine pas
    function GuessHeader: Boolean;
    function RowLength(ARow: Integer): Integer;
    function GetRow(ARow: Integer): TCsvRow;
    function GetColumn(ACol: Integer): TCsvRow;
    // AIdx = position de la nouvelle ligne (0..RowCount)
    procedure InsertRow(AIdx: Integer; const ARow: TCsvRow);
    procedure DeleteRows(AIdx, ACount: Integer);
    // ADelta: -1 vers le haut, +1 vers le bas ; False = bute sur le bord
    function MoveRows(AIdx, ACount, ADelta: Integer): Boolean;
    // colonnes: une ligne trop courte pour atteindre l'index n'est pas touchee
    procedure InsertCol(AIdx: Integer; const AValues: TCsvRow);
    procedure DeleteCols(AIdx, ACount: Integer);
    function MoveCols(AIdx, ACount, ADelta: Integer): Boolean;
    // instantane: tableaux copies, chaines partagees (refcount), pas les octets
    procedure Assign(ASrc: TCsvTable);
    property RowCount: Integer read FRowCount;
    property ColCount: Integer read FColCount;
    property Delim: Char read FDelim write FDelim;
    property QuoteAll: Boolean read FQuoteAll write FQuoteAll;
    property Cells[ARow, ACol: Integer]: string read GetCell write SetCell; default;
  end;

function SniffDelim(const AText: string; const AHint: string): Char;

implementation

const
  CANDIDATES: array[0..3] of Char = (',', ';', #9, '|');

function CsvToFloat(const S: string; ADelim: Char; out V: Double): Boolean; forward;

// separateur: celui qui donne le meme nombre de colonnes sur les premieres
// lignes, sinon le plus bavard
function SniffDelim(const AText: string; const AHint: string): Char;
var
  cnt: array[0..3, 0..19] of Integer;
  lines, i, k, n, best, bestScore, score: Integer;
  inq: Boolean;
  c: Char;
begin
  FillChar(cnt, SizeOf(cnt), 0);
  lines := 0; inq := False;
  for i := 1 to Length(AText) do
  begin
    c := AText[i];
    if c = '"' then inq := not inq
    else if not inq then
    begin
      if c = #10 then
      begin
        Inc(lines);
        if lines >= 20 then Break;
      end
      else if c <> #13 then
        for k := 0 to 3 do
          if c = CANDIDATES[k] then Inc(cnt[k, lines]);
    end;
  end;
  if lines < 20 then Inc(lines);
  best := 0; bestScore := -1;
  for k := 0 to 3 do
  begin
    if cnt[k, 0] = 0 then Continue;
    score := 0;
    n := cnt[k, 0];
    for i := 0 to lines - 1 do
      if cnt[k, i] = n then Inc(score, 1000) else Inc(score, cnt[k, i]);
    // ex aequo: la tabulation gagne pour un .tsv
    if (k = 2) and SameText(AHint, '.tsv') then Inc(score, 500000);
    if score > bestScore then
    begin
      bestScore := score;
      best := k;
    end;
  end;
  if bestScore < 0 then
  begin
    if SameText(AHint, '.tsv') then Exit(#9);
    Exit(',');
  end;
  Result := CANDIDATES[best];
end;

constructor TCsvTable.Create;
begin
  FDelim := ',';
end;

procedure TCsvTable.Clear;
begin
  FRows := nil;
  FQuoted := nil;
  FRowCount := 0;
  FColCount := 0;
end;

function TCsvTable.GetCell(ARow, ACol: Integer): string;
begin
  if (ARow < 0) or (ARow >= FRowCount) or (ACol < 0) or
     (ACol >= Length(FRows[ARow])) then
    Exit('');
  Result := FRows[ARow][ACol];
end;

procedure TCsvTable.SetCell(ARow, ACol: Integer; const AValue: string);
begin
  if (ARow < 0) or (ACol < 0) then Exit;
  while ARow >= FRowCount do AppendRow(nil);
  if ACol >= Length(FRows[ARow]) then
    SetLength(FRows[ARow], ACol + 1);
  EnsureQ(ARow);
  FRows[ARow][ACol] := AValue;
  FQuoted[ARow][ACol] := False; // editee: quotes selon le contenu
  if ACol >= FColCount then FColCount := ACol + 1;
end;

procedure TCsvTable.AppendRow(const ARow: TCsvRow);
begin
  if FRowCount >= Length(FRows) then
  begin
    SetLength(FRows, FRowCount * 2 + 16);
    SetLength(FQuoted, Length(FRows));
  end;
  FRows[FRowCount] := Copy(ARow);
  FQuoted[FRowCount] := nil;
  SetLength(FQuoted[FRowCount], Length(ARow));
  Inc(FRowCount);
  if Length(ARow) > FColCount then FColCount := Length(ARow);
end;

function TCsvTable.GuessHeader: Boolean;
var
  c, r, last: Integer;
  v: Double;
  s: string;
  evidence: Boolean;
begin
  Result := False;
  if FRowCount < 2 then Exit;
  evidence := False;
  last := Min(FRowCount - 1, 200);
  for c := 0 to FColCount - 1 do
  begin
    s := GetCell(0, c);
    if Trim(s) = '' then Exit;                 // un nom de champ vide, non
    if CsvToFloat(s, FDelim, v) then Exit;     // un nombre en tete, non plus
    if not evidence then
      for r := 1 to last do
        if CsvToFloat(GetCell(r, c), FDelim, v) then
        begin
          evidence := True;
          Break;
        end;
  end;
  Result := evidence;
end;

function TCsvTable.RowLength(ARow: Integer): Integer;
begin
  if (ARow < 0) or (ARow >= FRowCount) then Exit(0);
  Result := Length(FRows[ARow]);
end;

function TCsvTable.GetRow(ARow: Integer): TCsvRow;
begin
  if (ARow < 0) or (ARow >= FRowCount) then Exit(nil);
  Result := Copy(FRows[ARow]);
end;

function TCsvTable.GetColumn(ACol: Integer): TCsvRow;
var
  r: Integer;
begin
  SetLength(Result, FRowCount);
  for r := 0 to FRowCount - 1 do Result[r] := GetCell(r, ACol);
end;

procedure TCsvTable.EnsureQ(ARow: Integer);
begin
  if Length(FQuoted[ARow]) <> Length(FRows[ARow]) then
    SetLength(FQuoted[ARow], Length(FRows[ARow]));
end;

procedure TCsvTable.RecalcCols;
var
  r: Integer;
begin
  FColCount := 0;
  for r := 0 to FRowCount - 1 do
    if Length(FRows[r]) > FColCount then FColCount := Length(FRows[r]);
end;

procedure TCsvTable.InsertRow(AIdx: Integer; const ARow: TCsvRow);
var
  r: Integer;
begin
  if AIdx < 0 then AIdx := 0;
  if AIdx > FRowCount then AIdx := FRowCount;
  AppendRow(nil);
  for r := FRowCount - 1 downto AIdx + 1 do
  begin
    FRows[r] := FRows[r - 1];
    FQuoted[r] := FQuoted[r - 1];
  end;
  FRows[AIdx] := Copy(ARow);
  FQuoted[AIdx] := nil;
  SetLength(FQuoted[AIdx], Length(ARow));
  if Length(ARow) > FColCount then FColCount := Length(ARow);
end;

procedure TCsvTable.DeleteRows(AIdx, ACount: Integer);
var
  r: Integer;
begin
  if (AIdx < 0) or (AIdx >= FRowCount) or (ACount <= 0) then Exit;
  if AIdx + ACount > FRowCount then ACount := FRowCount - AIdx;
  for r := AIdx to FRowCount - ACount - 1 do
  begin
    FRows[r] := FRows[r + ACount];
    FQuoted[r] := FQuoted[r + ACount];
  end;
  for r := FRowCount - ACount to FRowCount - 1 do
  begin
    FRows[r] := nil;
    FQuoted[r] := nil;
  end;
  Dec(FRowCount, ACount);
  RecalcCols;
end;

function TCsvTable.MoveRows(AIdx, ACount, ADelta: Integer): Boolean;
var
  i, src, dst: Integer;
  row: TCsvRow;
  q: array of Boolean;
begin
  Result := False;
  if (AIdx < 0) or (ACount <= 0) or (AIdx + ACount > FRowCount) then Exit;
  if (ADelta < 0) and (AIdx = 0) then Exit;
  if (ADelta > 0) and (AIdx + ACount >= FRowCount) then Exit;
  if ADelta < 0 then
  begin
    src := AIdx - 1; dst := AIdx + ACount - 1;
    row := FRows[src]; q := FQuoted[src];
    for i := src to dst - 1 do begin FRows[i] := FRows[i + 1]; FQuoted[i] := FQuoted[i + 1]; end;
    FRows[dst] := row; FQuoted[dst] := q;
  end
  else
  begin
    src := AIdx + ACount; dst := AIdx;
    row := FRows[src]; q := FQuoted[src];
    for i := src downto dst + 1 do begin FRows[i] := FRows[i - 1]; FQuoted[i] := FQuoted[i - 1]; end;
    FRows[dst] := row; FQuoted[dst] := q;
  end;
  Result := True;
end;

function RangeBlank(const ARow: TCsvRow; ALo, AHi: Integer): Boolean;
var
  i: Integer;
begin
  for i := ALo to AHi do
    if (i < Length(ARow)) and (ARow[i] <> '') then Exit(False);
  Result := True;
end;

procedure TCsvTable.InsertCol(AIdx: Integer; const AValues: TCsvRow);
var
  r, c, n: Integer;
begin
  if AIdx < 0 then AIdx := 0;
  for r := 0 to FRowCount - 1 do
  begin
    n := Length(FRows[r]);
    // ligne qui n'atteint pas la colonne: on ne lui colle pas un separateur
    // pour rien. Une ligne vide non plus, sauf si c'est la fin de toutes les
    // lignes (colonne ajoutee a droite de la derniere)
    if (r >= Length(AValues)) or (AValues[r] = '') then
    begin
      if n < AIdx then Continue;
      if (n = AIdx) and (n < FColCount) and RangeBlank(FRows[r], 0, n - 1) then Continue;
    end;
    if n < AIdx then n := AIdx;
    SetLength(FRows[r], n + 1);
    EnsureQ(r);
    for c := n downto AIdx + 1 do
    begin
      FRows[r][c] := FRows[r][c - 1];
      FQuoted[r][c] := FQuoted[r][c - 1];
    end;
    if r < Length(AValues) then FRows[r][AIdx] := AValues[r] else FRows[r][AIdx] := '';
    FQuoted[r][AIdx] := False;
  end;
  RecalcCols;
end;

procedure TCsvTable.DeleteCols(AIdx, ACount: Integer);
var
  r, c, n, k: Integer;
begin
  if (AIdx < 0) or (ACount <= 0) then Exit;
  for r := 0 to FRowCount - 1 do
  begin
    n := Length(FRows[r]);
    if n <= AIdx then Continue;
    EnsureQ(r);
    k := ACount;
    if AIdx + k > n then k := n - AIdx;
    for c := AIdx to n - k - 1 do
    begin
      FRows[r][c] := FRows[r][c + k];
      FQuoted[r][c] := FQuoted[r][c + k];
    end;
    SetLength(FRows[r], n - k);
    SetLength(FQuoted[r], n - k);
  end;
  RecalcCols;
end;

function TCsvTable.MoveCols(AIdx, ACount, ADelta: Integer): Boolean;
var
  r, i, src, dst, need: Integer;
  v: string;
  q: Boolean;
begin
  Result := False;
  if (AIdx < 0) or (ACount <= 0) or (AIdx + ACount > FColCount) then Exit;
  if (ADelta < 0) and (AIdx = 0) then Exit;
  if (ADelta > 0) and (AIdx + ACount >= FColCount) then Exit;
  if ADelta < 0 then need := AIdx + ACount else need := AIdx + ACount + 1;
  for r := 0 to FRowCount - 1 do
  begin
    // ligne trop courte pour atteindre la plage, ou vide dedans: rien a deplacer
    if Length(FRows[r]) <= AIdx - Ord(ADelta < 0) then Continue;
    if RangeBlank(FRows[r], AIdx - Ord(ADelta < 0), AIdx + ACount - Ord(ADelta < 0)) then Continue;
    if Length(FRows[r]) < need then SetLength(FRows[r], need);
    EnsureQ(r);
    if ADelta < 0 then
    begin
      src := AIdx - 1; dst := AIdx + ACount - 1;
      v := FRows[r][src]; q := FQuoted[r][src];
      for i := src to dst - 1 do begin FRows[r][i] := FRows[r][i + 1]; FQuoted[r][i] := FQuoted[r][i + 1]; end;
      FRows[r][dst] := v; FQuoted[r][dst] := q;
    end
    else
    begin
      src := AIdx + ACount; dst := AIdx;
      v := FRows[r][src]; q := FQuoted[r][src];
      for i := src downto dst + 1 do begin FRows[r][i] := FRows[r][i - 1]; FQuoted[r][i] := FQuoted[r][i - 1]; end;
      FRows[r][dst] := v; FQuoted[r][dst] := q;
    end;
  end;
  RecalcCols;
  Result := True;
end;

procedure TCsvTable.Assign(ASrc: TCsvTable);
var
  r: Integer;
begin
  FRowCount := ASrc.FRowCount;
  FColCount := ASrc.FColCount;
  FDelim := ASrc.FDelim;
  FQuoteAll := ASrc.FQuoteAll;
  SetLength(FRows, FRowCount);
  SetLength(FQuoted, FRowCount);
  for r := 0 to FRowCount - 1 do
  begin
    FRows[r] := Copy(ASrc.FRows[r]);
    FQuoted[r] := Copy(ASrc.FQuoted[r]);
  end;
end;

procedure TCsvTable.Parse(const AText: string; const AHint: string);
var
  i, n, fields, quoted, ncells: Integer;
  inq, wasq, rowOpen: Boolean;
  f: string;
  row: TCsvRow;
  rowq: array of Boolean;
  c: Char;

  procedure EndField;
  begin
    // avant d'allouer: une ligne d'un million de virgules ne doit rien couter
    if Length(row) >= CsvMaxCols then
    begin
      Clear;
      raise ECsvTooBig.CreateFmt('more than %d columns, open it as text', [CsvMaxCols]);
    end;
    SetLength(row, Length(row) + 1);
    SetLength(rowq, Length(row));
    row[High(row)] := f;
    rowq[High(row)] := wasq;
    f := '';
    Inc(fields);
    if wasq then Inc(quoted);
    wasq := False;
  end;

  procedure EndRow;
  begin
    AppendRow(row);
    FQuoted[FRowCount - 1] := Copy(rowq);
    ncells := ncells + Length(row);
    row := nil;
    rowq := nil;
    rowOpen := False;
    if (FRowCount > CsvMaxRows) or (ncells > CsvMaxCells) or
       (Int64(FRowCount) * Max(FColCount, 1) > CsvMaxCells) then
    begin
      Clear;
      raise ECsvTooBig.CreateFmt('more than %d rows, %d columns or %d cells, open it as text',
        [CsvMaxRows, CsvMaxCols, CsvMaxCells]);
    end;
  end;

begin
  Clear;
  FDelim := SniffDelim(AText, AHint);
  n := Length(AText);
  i := 1;
  f := ''; row := nil; rowq := nil;
  inq := False; wasq := False; rowOpen := False;
  fields := 0; quoted := 0; ncells := 0;
  while i <= n do
  begin
    c := AText[i];
    if inq then
    begin
      if c = '"' then
      begin
        if (i < n) and (AText[i + 1] = '"') then
        begin
          f := f + '"';
          Inc(i);
        end
        else
          inq := False;
      end
      else
        f := f + c;
    end
    else if (c = '"') and (f = '') and not wasq then
    begin
      inq := True;
      wasq := True;
      rowOpen := True;
    end
    else if c = FDelim then
    begin
      EndField;
      rowOpen := True;
    end
    else if (c = #13) or (c = #10) then
    begin
      if (c = #13) and (i < n) and (AText[i + 1] = #10) then Inc(i);
      EndField;
      EndRow;
    end
    else
    begin
      f := f + c;
      rowOpen := True;
    end;
    Inc(i);
  end;
  // derniere ligne sans saut final (ou quote jamais fermee: on garde ce qu'on a)
  if rowOpen or (f <> '') or inq then
  begin
    EndField;
    EndRow;
  end;
  // tout quote a la lecture = tout quote au save, le fichier garde sa tete
  FQuoteAll := (fields > 0) and (quoted = fields);
end;

function TCsvTable.QuoteField(const S: string): string;
var
  need: Boolean;
begin
  need := FQuoteAll;
  if not need then
    need := (Pos(FDelim, S) > 0) or (Pos('"', S) > 0) or (Pos(#10, S) > 0) or
      (Pos(#13, S) > 0);
  if need then
    Result := '"' + StringReplace(S, '"', '""', [rfReplaceAll]) + '"'
  else
    Result := S;
end;

function TCsvTable.Serialize(ATrailingEol: Boolean; const AEol: string): string;
var
  r, c: Integer;
  sb: TStringBuilder;
begin
  sb := TStringBuilder.Create;
  try
    for r := 0 to FRowCount - 1 do
    begin
      for c := 0 to High(FRows[r]) do
      begin
        if c > 0 then sb.Append(FDelim);
        // lue entre quotes et pas touchee: on la rend comme on l'a trouvee
        if (c < Length(FQuoted[r])) and FQuoted[r][c] then
          sb.Append('"' + StringReplace(FRows[r][c], '"', '""', [rfReplaceAll]) + '"')
        else
          sb.Append(QuoteField(FRows[r][c]));
      end;
      // "a" + EOL + "" relu = une seule ligne: la derniere vide s'ecrit ""
      if (r = FRowCount - 1) and (not ATrailingEol) and (r > 0) and
         (Length(FRows[r]) = 1) and (FRows[r][0] = '') then
        sb.Append('""');
      if (r < FRowCount - 1) or ATrailingEol then sb.Append(AEol);
    end;
    Result := sb.ToString;
  finally
    sb.Free;
  end;
end;

function CsvToFloat(const S: string; ADelim: Char; out V: Double): Boolean;
var
  t: string;
  fs: TFormatSettings;
begin
  fs := DefaultFormatSettings;
  fs.DecimalSeparator := '.';
  fs.ThousandSeparator := #0;
  t := Trim(S);
  // virgule decimale plausible quand elle ne sert pas de separateur
  if (ADelim <> ',') and (Pos(',', t) > 0) and (Pos('.', t) = 0) then
    t := StringReplace(t, ',', '.', []);
  // nan/inf passent TryStrToFloat; comparer un NaN leve EInvalidOp
  Result := TryStrToFloat(t, V, fs) and not (IsNan(V) or IsInfinite(V));
end;

function TCsvTable.ColumnIsNumeric(ACol, AFirst: Integer): Boolean;
var
  r, seen: Integer;
  v: Double;
  s: string;
begin
  Result := False;
  seen := 0;
  for r := AFirst to FRowCount - 1 do
  begin
    s := GetCell(r, ACol);
    if Trim(s) = '' then Continue;
    if not CsvToFloat(s, FDelim, v) then Exit;
    Inc(seen);
  end;
  Result := seen > 0;
end;

// entier litteral (signe, chiffres): un Double confond 9007199254740993 et
// ...992, ce qui est exactement la tete d'un identifiant 64 bits
function IsIntLit(const S: string; out ANeg: Boolean; out ADigits: string): Boolean;
var
  t: string;
  i, p: Integer;
begin
  Result := False;
  t := Trim(S);
  if t = '' then Exit;
  ANeg := t[1] = '-';
  p := 1;
  if t[1] in ['-', '+'] then p := 2;
  if p > Length(t) then Exit;
  for i := p to Length(t) do
    if not (t[i] in ['0'..'9']) then Exit;
  i := p;
  while (i < Length(t)) and (t[i] = '0') do Inc(i);
  ADigits := Copy(t, i, MaxInt);
  if ADigits = '0' then ANeg := False;
  Result := True;
end;

function IntLitCmp(ANegA: Boolean; const A: string; ANegB: Boolean; const B: string): Integer;
begin
  if ANegA <> ANegB then
  begin
    if ANegA then Exit(-1) else Exit(1);
  end;
  if Length(A) <> Length(B) then
  begin
    if Length(A) < Length(B) then Result := -1 else Result := 1;
  end
  else
    Result := CompareStr(A, B);
  if ANegA then Result := -Result;
end;

function TCsvTable.SortByColumn(ACol: Integer; ADesc: Boolean; AFirst: Integer): Boolean;
var
  idx, tmp: array of Integer;
  numeric: Boolean;
  n, i: Integer;
  sorted: array of TCsvRow;
  sortedq: array of array of Boolean;

  function Cmp(A, B: Integer): Integer;
  var
    sa, sb, da, db: string;
    va, vb: Double;
    ea, eb, na, nb: Boolean;
  begin
    sa := GetCell(A, ACol);
    sb := GetCell(B, ACol);
    ea := Trim(sa) = '';
    eb := Trim(sb) = '';
    // vides toujours en queue, quel que soit le sens
    if ea or eb then
    begin
      if ea and eb then Exit(0);
      if ea then Exit(1) else Exit(-1);
    end;
    if numeric then
    begin
      if IsIntLit(sa, na, da) and IsIntLit(sb, nb, db) then
        Result := IntLitCmp(na, da, nb, db)
      else
      begin
        CsvToFloat(sa, FDelim, va);
        CsvToFloat(sb, FDelim, vb);
        if va < vb then Result := -1 else if va > vb then Result := 1 else Result := 0;
      end;
    end
    else
      Result := UTF8CompareText(sa, sb);
    if ADesc then Result := -Result;
  end;

  // tri fusion: stable, deux lignes egales gardent leur ordre du fichier
  procedure Merge(lo, mid, hi: Integer);
  var
    a, b, k: Integer;
  begin
    a := lo; b := mid; k := lo;
    while (a < mid) and (b < hi) do
    begin
      if Cmp(idx[b], idx[a]) < 0 then begin tmp[k] := idx[b]; Inc(b); end
      else begin tmp[k] := idx[a]; Inc(a); end;
      Inc(k);
    end;
    while a < mid do begin tmp[k] := idx[a]; Inc(a); Inc(k); end;
    while b < hi do begin tmp[k] := idx[b]; Inc(b); Inc(k); end;
    for k := lo to hi - 1 do idx[k] := tmp[k];
  end;

  procedure MSort(lo, hi: Integer);
  var
    mid: Integer;
  begin
    if hi - lo < 2 then Exit;
    mid := (lo + hi) div 2;
    MSort(lo, mid);
    MSort(mid, hi);
    Merge(lo, mid, hi);
  end;

begin
  Result := False;
  if AFirst < 0 then AFirst := 0;
  n := FRowCount - AFirst;
  if n < 2 then Exit;
  numeric := ColumnIsNumeric(ACol, AFirst);
  SetLength(idx, n);
  SetLength(tmp, n);
  for i := 0 to n - 1 do idx[i] := AFirst + i;
  MSort(0, n);
  for i := 0 to n - 1 do
    if idx[i] <> AFirst + i then Result := True;
  if not Result then Exit;
  SetLength(sorted, n);
  SetLength(sortedq, n);
  for i := 0 to n - 1 do
  begin
    sorted[i] := FRows[idx[i]];
    sortedq[i] := FQuoted[idx[i]];
  end;
  for i := 0 to n - 1 do
  begin
    FRows[AFirst + i] := sorted[i];
    FQuoted[AFirst + i] := sortedq[i];
  end;
end;

end.
