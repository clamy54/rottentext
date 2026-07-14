unit uDiff;

{$mode objfpc}{$H+}

// Diff de lignes (LCS) : prefixe et suffixe communs retires, DP sur le seul
// milieu qui differe. Milieu > CELL_CAP : rendu grossier en bloc (del + add).

interface

uses
  Classes;

type
  TDiffKind = (dkEqual, dkDelete, dkAdd);
  TDiffOp = record
    Kind: TDiffKind;
    Text: string;
    LeftNo, RightNo: Integer;   // n de ligne 1-base, 0 = sans objet
  end;
  TDiffOps = array of TDiffOp;

  TDiffRowKind = (drEqual, drChange, drDel, drAdd);
  TDiffRow = record
    Kind: TDiffRowKind;
    Left, Right: string;         // '' si filler
    HasLeft, HasRight: Boolean;  // False du cote filler
    LeftNo, RightNo: Integer;    // n de ligne d'origine 1-base, 0 = filler
  end;
  TDiffRows = array of TDiffRow;
  TIntArray = array of Integer;

function DiffLines(A, B: TStrings): TDiffOps;
function DiffSummary(const AOps: TDiffOps): string;
function BuildDiffRows(A, B: TStrings): TDiffRows;
// nb de lignes inchange : les fillers restes vides sont retires. Sinon les
// fillers ne sont plus retracables et AEditedLeft est rendu verbatim.
procedure IntegrateLeft(const ARows: TDiffRows; AEditedLeft, ADest: TStrings);
// re-aligne apres une edition STRUCTURELLE de la gauche. Les LeftNo rendus
// renumerotent le contenu gauche COURANT. ARowOfEdited[i] = rangee 0-base de
// la ligne i du buffer edite, -1 si filler retire.
function RealignRows(const AOldRows: TDiffRows; AEditedLeft, ARightOrig: TStrings;
  out ARowOfEdited: TIntArray): TDiffRows;
// ne remplace que le segment qui differe : n'invalide pas la coloration du reste
procedure PatchLines(ACur, ADesired: TStrings);

implementation

uses
  SysUtils, Math;

const
  CELL_CAP = 16000000;   // cellules de DP: au-dela, rendu en bloc

procedure Push(var Ops: TDiffOps; AKind: TDiffKind; const AText: string;
  ALeft, ARight: Integer);
var
  n: Integer;
begin
  n := Length(Ops);
  SetLength(Ops, n + 1);
  Ops[n].Kind := AKind;
  Ops[n].Text := AText;
  Ops[n].LeftNo := ALeft;
  Ops[n].RightNo := ARight;
end;

function DiffLines(A, B: TStrings): TDiffOps;
var
  n, m, lo, hiA, hiB, midA, midB, i, j: Integer;
  dp: array of array of Integer;
begin
  Result := nil;
  n := A.Count;
  m := B.Count;
  lo := 0;
  while (lo < n) and (lo < m) and (A[lo] = B[lo]) do Inc(lo);
  hiA := n - 1;
  hiB := m - 1;
  while (hiA >= lo) and (hiB >= lo) and (A[hiA] = B[hiB]) do
  begin
    Dec(hiA); Dec(hiB);
  end;
  for i := 0 to lo - 1 do
    Push(Result, dkEqual, A[i], i + 1, i + 1);

  midA := hiA - lo + 1;
  midB := hiB - lo + 1;
  if midA <= 0 then
  begin
    for j := lo to hiB do Push(Result, dkAdd, B[j], 0, j + 1);
  end
  else if midB <= 0 then
  begin
    for i := lo to hiA do Push(Result, dkDelete, A[i], i + 1, 0);
  end
  else if Int64(midA) * midB > CELL_CAP then
  begin
    for i := lo to hiA do Push(Result, dkDelete, A[i], i + 1, 0);
    for j := lo to hiB do Push(Result, dkAdd, B[j], 0, j + 1);
  end
  else
  begin
    // dp[i,j] = LCS(A_mid[i..], B_mid[j..])
    SetLength(dp, midA + 1, midB + 1);
    for i := midA - 1 downto 0 do
      for j := midB - 1 downto 0 do
        if A[lo + i] = B[lo + j] then
          dp[i][j] := dp[i + 1][j + 1] + 1
        else if dp[i + 1][j] >= dp[i][j + 1] then
          dp[i][j] := dp[i + 1][j]
        else
          dp[i][j] := dp[i][j + 1];
    i := 0; j := 0;
    while (i < midA) and (j < midB) do
      if A[lo + i] = B[lo + j] then
      begin
        Push(Result, dkEqual, A[lo + i], lo + i + 1, lo + j + 1);
        Inc(i); Inc(j);
      end
      else if dp[i + 1][j] >= dp[i][j + 1] then
      begin
        Push(Result, dkDelete, A[lo + i], lo + i + 1, 0);
        Inc(i);
      end
      else
      begin
        Push(Result, dkAdd, B[lo + j], 0, lo + j + 1);
        Inc(j);
      end;
    while i < midA do begin Push(Result, dkDelete, A[lo + i], lo + i + 1, 0); Inc(i); end;
    while j < midB do begin Push(Result, dkAdd, B[lo + j], 0, lo + j + 1); Inc(j); end;
  end;

  for i := hiA + 1 to n - 1 do
    Push(Result, dkEqual, A[i], i + 1, (i - (hiA + 1)) + (hiB + 1) + 1);
end;

function DiffSummary(const AOps: TDiffOps): string;
var
  i, del, add: Integer;
begin
  del := 0; add := 0;
  for i := 0 to High(AOps) do
    case AOps[i].Kind of
      dkDelete: Inc(del);
      dkAdd: Inc(add);
    end;
  if (del = 0) and (add = 0) then Result := 'identical'
  else Result := Format('%d removed, %d added', [del, add]);
end;

procedure PushRow(var Rows: TDiffRows; AKind: TDiffRowKind;
  const ALeft, ARight: string; AHasL, AHasR: Boolean; ALeftNo, ARightNo: Integer);
var
  n: Integer;
begin
  n := Length(Rows);
  SetLength(Rows, n + 1);
  Rows[n].Kind := AKind;
  Rows[n].Left := ALeft;
  Rows[n].Right := ARight;
  Rows[n].HasLeft := AHasL;
  Rows[n].HasRight := AHasR;
  Rows[n].LeftNo := ALeftNo;
  Rows[n].RightNo := ARightNo;
end;

// le backtrack LCS entremele del/add : collecter le bloc ENTIER avant d'apparier
function BuildDiffRows(A, B: TStrings): TDiffRows;
var
  ops: TDiffOps;
  dels, adds: array of Integer;
  i, k, nd, na: Integer;
begin
  Result := nil;
  ops := DiffLines(A, B);
  i := 0;
  while i < Length(ops) do
  begin
    if ops[i].Kind = dkEqual then
    begin
      PushRow(Result, drEqual, ops[i].Text, ops[i].Text, True, True,
        ops[i].LeftNo, ops[i].RightNo);
      Inc(i);
    end
    else
    begin
      SetLength(dels, 0);
      SetLength(adds, 0);
      while (i < Length(ops)) and (ops[i].Kind <> dkEqual) do
      begin
        if ops[i].Kind = dkDelete then
        begin SetLength(dels, Length(dels) + 1); dels[High(dels)] := i; end
        else
        begin SetLength(adds, Length(adds) + 1); adds[High(adds)] := i; end;
        Inc(i);
      end;
      nd := Length(dels);
      na := Length(adds);
      for k := 0 to Max(nd, na) - 1 do
        if (k < nd) and (k < na) then
          PushRow(Result, drChange, ops[dels[k]].Text, ops[adds[k]].Text,
            True, True, ops[dels[k]].LeftNo, ops[adds[k]].RightNo)
        else if k < nd then
          PushRow(Result, drDel, ops[dels[k]].Text, '', True, False,
            ops[dels[k]].LeftNo, 0)
        else
          PushRow(Result, drAdd, '', ops[adds[k]].Text, False, True,
            0, ops[adds[k]].RightNo);
    end;
  end;
end;

procedure IntegrateLeft(const ARows: TDiffRows; AEditedLeft, ADest: TStrings);
var
  i: Integer;
begin
  ADest.Clear;
  if AEditedLeft.Count = Length(ARows) then
  begin
    for i := 0 to AEditedLeft.Count - 1 do
      if ARows[i].HasLeft or (AEditedLeft[i] <> '') then
        ADest.Add(AEditedLeft[i]);
  end
  else
    ADest.Assign(AEditedLeft);
end;

function RealignRows(const AOldRows: TDiffRows; AEditedLeft, ARightOrig: TStrings;
  out ARowOfEdited: TIntArray): TDiffRows;
var
  oldLeft, realLeft: TStringList;
  ops: TDiffOps;
  realOf, rowOfReal: TIntArray; // ligne editee -> index realLeft ; realLeft -> rangee
  i, k: Integer;
begin
  oldLeft := TStringList.Create;
  realLeft := TStringList.Create;
  try
    for i := 0 to High(AOldRows) do
      oldLeft.Add(AOldRows[i].Left);
    SetLength(realOf, AEditedLeft.Count);
    for i := 0 to High(realOf) do
      realOf[i] := -1;
    // LeftNo = rangee d'origine, RightNo = ligne du buffer edite (1-base)
    ops := DiffLines(oldLeft, AEditedLeft);
    for k := 0 to High(ops) do
      case ops[k].Kind of
        dkEqual:
          if AOldRows[ops[k].LeftNo - 1].HasLeft or (ops[k].Text <> '') then
          begin
            realOf[ops[k].RightNo - 1] := realLeft.Count;
            realLeft.Add(ops[k].Text);
          end;
          // sinon: filler reste vide, retire
        dkAdd:
        begin
          realOf[ops[k].RightNo - 1] := realLeft.Count;
          realLeft.Add(ops[k].Text);
        end;
      end;
    Result := BuildDiffRows(realLeft, ARightOrig);
    SetLength(rowOfReal, realLeft.Count);
    for i := 0 to High(rowOfReal) do
      rowOfReal[i] := -1;
    for k := 0 to High(Result) do
      if Result[k].HasLeft then
        rowOfReal[Result[k].LeftNo - 1] := k;
    SetLength(ARowOfEdited, AEditedLeft.Count);
    for i := 0 to High(ARowOfEdited) do
      if realOf[i] >= 0 then
        ARowOfEdited[i] := rowOfReal[realOf[i]]
      else
        ARowOfEdited[i] := -1;
  finally
    oldLeft.Free;
    realLeft.Free;
  end;
end;

procedure PatchLines(ACur, ADesired: TStrings);
var
  f, tc, td, n, i: Integer;
begin
  f := 0;
  while (f < ACur.Count) and (f < ADesired.Count) and (ACur[f] = ADesired[f]) do
    Inc(f);
  tc := ACur.Count;
  td := ADesired.Count;
  while (tc > f) and (td > f) and (ACur[tc - 1] = ADesired[td - 1]) do
  begin
    Dec(tc); Dec(td);
  end;
  n := Min(tc - f, td - f);
  for i := 0 to n - 1 do
    if ACur[f + i] <> ADesired[f + i] then
      ACur[f + i] := ADesired[f + i];
  if td - f > n then
    for i := n to td - f - 1 do
      ACur.Insert(f + i, ADesired[f + i])
  else
    for i := 1 to (tc - f) - n do
      ACur.Delete(f + n);
end;

end.
