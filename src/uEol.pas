unit uEol;

{$mode objfpc}{$H+}

// EOL par document: le buffer editeur ne stocke pas de fins de ligne et sa
// serialisation sort en EOL plateforme, un fichier LF repartirait en CRLF.

interface

type
  TEolKind = (eolCRLF, eolLF, eolCR);

const
  {$IFDEF WINDOWS}
  PlatformEol = eolCRLF;
  {$ELSE}
  PlatformEol = eolLF;
  {$ENDIF}

// EOL dominant (un CRLF = UNE fin). Egalite -> CRLF puis LF puis CR.
// AMaxScan > 0 borne le scan.
function DetectEol(const S: string; ADefault: TEolKind;
  AMaxScan: SizeInt = 0): TEolKind;

// rend la chaine d'origine, sans copie, si rien a changer
function ForceEol(const S: string; AKind: TEolKind): string;

function EolName(AKind: TEolKind): string;
function EolStr(AKind: TEolKind): string;

implementation

function EolName(AKind: TEolKind): string;
begin
  case AKind of
    eolCRLF: Result := 'CRLF';
    eolLF: Result := 'LF';
  else
    Result := 'CR';
  end;
end;

function EolStr(AKind: TEolKind): string;
begin
  case AKind of
    eolCRLF: Result := #13#10;
    eolLF: Result := #10;
  else
    Result := #13;
  end;
end;

function DetectEol(const S: string; ADefault: TEolKind;
  AMaxScan: SizeInt): TEolKind;
var
  i, n: SizeInt;
  crlf, lf, cr: SizeInt;
begin
  n := Length(S);
  if (AMaxScan > 0) and (AMaxScan < n) then n := AMaxScan;
  crlf := 0; lf := 0; cr := 0;
  i := 1;
  while i <= n do
  begin
    case S[i] of
      #13:
        if (i < n) and (S[i + 1] = #10) then
        begin
          Inc(crlf);
          Inc(i);
        end
        else
          Inc(cr);
      #10: Inc(lf);
    end;
    Inc(i);
  end;
  if (crlf > 0) and (crlf >= lf) and (crlf >= cr) then Exit(eolCRLF);
  if (lf > 0) and (lf >= cr) then Exit(eolLF);
  if cr > 0 then Exit(eolCR);
  Result := ADefault;
end;

function ForceEol(const S: string; AKind: TEolKind): string;
var
  eol: string;
  i, n, breaks, dirty, outLen, p: SizeInt;
begin
  eol := EolStr(AKind);
  n := Length(S);
  // passe 1: compter, pour dimensionner la sortie une seule fois
  breaks := 0; dirty := 0; outLen := n;
  i := 1;
  while i <= n do
  begin
    case S[i] of
      #13:
        begin
          Inc(breaks);
          if (i < n) and (S[i + 1] = #10) then
          begin
            Dec(outLen, 2);
            if AKind <> eolCRLF then Inc(dirty);
            Inc(i);
          end
          else
          begin
            Dec(outLen);
            if AKind <> eolCR then Inc(dirty);
          end;
        end;
      #10:
        begin
          Inc(breaks);
          Dec(outLen);
          if AKind <> eolLF then Inc(dirty);
        end;
    end;
    Inc(i);
  end;
  if dirty = 0 then Exit(S);
  outLen := outLen + breaks * Length(eol);
  SetLength(Result, outLen);
  p := 1;
  i := 1;
  while i <= n do
  begin
    case S[i] of
      #13:
        begin
          Move(eol[1], Result[p], Length(eol));
          Inc(p, Length(eol));
          if (i < n) and (S[i + 1] = #10) then Inc(i);
        end;
      #10:
        begin
          Move(eol[1], Result[p], Length(eol));
          Inc(p, Length(eol));
        end;
    else
      Result[p] := S[i];
      Inc(p);
    end;
    Inc(i);
  end;
end;

end.
