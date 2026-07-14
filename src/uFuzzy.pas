unit uFuzzy;

{$mode objfpc}{$H+}

// Matching fuzzy de la command palette. Le greedy est relance depuis CHAQUE
// occurrence du premier caractere: partir de la 1re seule rate des matches.

interface

type
  TFuzzyPos = array of SizeInt; // positions (octets, base 1) des matches

function FuzzyMatch(const APattern, AText: string; out AScore: Integer;
  out APos: TFuzzyPos): Boolean;

implementation

function Fold(C: Char): Char; inline;
begin
  if C in ['A'..'Z'] then
    Result := Chr(Ord(C) + 32)
  else
    Result := C;
end;

function IsWordChar(C: Char): Boolean; inline;
begin
  Result := C in ['a'..'z', 'A'..'Z', '0'..'9'];
end;

const
  SC_CHAR  = 10; // par caractere matche
  SC_CONS  = 15; // consecutif au match precedent
  SC_WORD  = 20; // en debut de mot

function TryFrom(const APat, AText: string; AFrom: SizeInt;
  out APos: TFuzzyPos): Integer;
var
  pi, ti, n: SizeInt;
begin
  Result := Low(Integer);
  SetLength(APos, Length(APat));
  n := 0;
  ti := AFrom;
  for pi := 1 to Length(APat) do
  begin
    while (ti <= Length(AText)) and (Fold(AText[ti]) <> APat[pi]) do
      Inc(ti);
    if ti > Length(AText) then Exit;
    APos[n] := ti;
    Inc(n);
    Inc(ti);
  end;
  Result := 0;
  for pi := 0 to n - 1 do
  begin
    Inc(Result, SC_CHAR);
    if (pi > 0) and (APos[pi] = APos[pi - 1] + 1) then
      Inc(Result, SC_CONS);
    if (APos[pi] = 1) or not IsWordChar(AText[APos[pi] - 1]) then
      Inc(Result, SC_WORD);
  end;
  // penalite douce: les libelles sont des chemins, le mot vise est souvent en fin
  if n > 0 then
    Dec(Result, (APos[0] - 1) div 4);
  Dec(Result, Length(AText) div 4);
end;

function FuzzyMatch(const APattern, AText: string; out AScore: Integer;
  out APos: TFuzzyPos): Boolean;
var
  pat: string;
  i: SizeInt;
  sc: Integer;
  ps: TFuzzyPos;
begin
  pat := '';
  for i := 1 to Length(APattern) do
    if APattern[i] <> ' ' then
      pat := pat + Fold(APattern[i]);
  APos := nil;
  if pat = '' then
  begin
    AScore := 0;
    Exit(True); // motif vide = tout matche
  end;
  AScore := Low(Integer);
  Result := False;
  for i := 1 to Length(AText) do
    if Fold(AText[i]) = pat[1] then
    begin
      sc := TryFrom(pat, AText, i, ps);
      if sc > AScore then
      begin
        AScore := sc;
        APos := ps;
        Result := True;
      end;
    end;
end;

end.
