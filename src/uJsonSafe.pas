unit uJsonSafe;

{$mode objfpc}{$H+}

// Lecture JSON pour entree NON FIABLE. GetJSON de la FCL rend le PREMIER
// document et ignore ce qui suit (`{"a":1} {"b":2}` passe pour valide), et son
// parseur descend en recursion: une imbrication profonde deborde la pile.

interface

uses
  Classes, SysUtils, fpjson;

const
  JSON_MAX_DEPTH = 256;

type
  EJsonSafe = class(Exception);

// profondeur de crochets hors chaines
function JsonTooDeep(const S: string; AMax: Integer): Boolean;

// joStrict: refuse le contenu qui traine apres le document. Leve comme GetJSON.
function SafeGetJSON(const S: string; AMaxDepth: Integer = JSON_MAX_DEPTH): TJSONData;

implementation

uses
  jsonparser, jsonscanner;

function JsonTooDeep(const S: string; AMax: Integer): Boolean;
var
  i, d: Integer;
  q: Boolean;
begin
  Result := True;
  d := 0;
  q := False;
  i := 1;
  while i <= Length(S) do
  begin
    if q then
    begin
      if S[i] = '\' then Inc(i)
      else if S[i] = '"' then q := False;
    end
    else
      case S[i] of
        '"': q := True;
        '[', '{': begin Inc(d); if d > AMax then Exit; end;
        ']', '}': Dec(d);
      end;
    Inc(i);
  end;
  Result := False;
end;

function SafeGetJSON(const S: string; AMaxDepth: Integer): TJSONData;
var
  p: TJSONParser;
begin
  if JsonTooDeep(S, AMaxDepth) then
    raise EJsonSafe.Create('JSON nesting too deep');
  p := TJSONParser.Create(S, [joUTF8, joStrict]);
  try
    Result := p.Parse;
  finally
    p.Free;
  end;
end;

end.
