unit uEncoding;

{$mode objfpc}{$H+}

// Texte interne = UTF-8, conversion aux I/O. La table est limitee a ce que
// LConvEncoding sait convertir. UTF-16 fait main: les tables ucs2* de
// LConvEncoding sont BMP-only (surrogates perdus).

interface

uses
  Classes, SysUtils, LazUTF8, LConvEncoding;

type
  TRTBom = (bomNone, bomUTF8, bomUTF16LE, bomUTF16BE);

  TRTEncInfo = record
    Caption: string;
    ConvId: string;  // id LConvEncoding; 'utf16le'/'utf16be' geres a la main
    Bom: TRTBom;
  end;

const
  ENC_UTF8         = 0;
  ENC_UTF8_BOM     = 1;
  ENC_UTF16LE      = 2;
  ENC_UTF16LE_BOM  = 3;
  ENC_UTF16BE      = 4;
  ENC_UTF16BE_BOM  = 5;
  ENC_UNICODE_LAST = 5;  // separateur de menu apres cette entree
  ENC_WESTERN      = 37; // fallback si ni BOM ni UTF-8 valide

  Encodings: array[0..37] of TRTEncInfo = (
    (Caption: 'UTF-8';              ConvId: 'utf8';    Bom: bomNone),
    (Caption: 'UTF-8 with BOM';     ConvId: 'utf8';    Bom: bomUTF8),
    (Caption: 'UTF-16 LE';          ConvId: 'utf16le'; Bom: bomNone),
    (Caption: 'UTF-16 LE with BOM'; ConvId: 'utf16le'; Bom: bomUTF16LE),
    (Caption: 'UTF-16 BE';          ConvId: 'utf16be'; Bom: bomNone),
    (Caption: 'UTF-16 BE with BOM'; ConvId: 'utf16be'; Bom: bomUTF16BE),
    (Caption: 'Arabic (Windows 1256)';           ConvId: 'cp1256';    Bom: bomNone),
    (Caption: 'Baltic (ISO 8859-4)';             ConvId: 'iso88594';  Bom: bomNone),
    (Caption: 'Baltic (Windows 1257)';           ConvId: 'cp1257';    Bom: bomNone),
    (Caption: 'Celtic (ISO 8859-14)';            ConvId: 'iso885914'; Bom: bomNone),
    (Caption: 'Central European (ISO 8859-2)';   ConvId: 'iso88592';  Bom: bomNone),
    (Caption: 'Central European (Windows 1250)'; ConvId: 'cp1250';    Bom: bomNone),
    (Caption: 'Chinese Simplified (GBK)';        ConvId: 'cp936';     Bom: bomNone),
    (Caption: 'Chinese Traditional (Big5)';      ConvId: 'cp950';     Bom: bomNone),
    (Caption: 'Cyrillic (ISO 8859-5)';           ConvId: 'iso88595';  Bom: bomNone),
    (Caption: 'Cyrillic (KOI8-R)';               ConvId: 'koi8r';     Bom: bomNone),
    (Caption: 'Cyrillic (KOI8-U)';               ConvId: 'koi8u';     Bom: bomNone),
    (Caption: 'Cyrillic (Windows 1251)';         ConvId: 'cp1251';    Bom: bomNone),
    (Caption: 'Cyrillic (Windows 866)';          ConvId: 'cp866';     Bom: bomNone),
    (Caption: 'DOS (CP 437)';                    ConvId: 'cp437';     Bom: bomNone),
    (Caption: 'Estonian (ISO 8859-13)';          ConvId: 'iso885913'; Bom: bomNone),
    (Caption: 'Greek (ISO 8859-7)';              ConvId: 'iso88597';  Bom: bomNone),
    (Caption: 'Greek (Windows 1253)';            ConvId: 'cp1253';    Bom: bomNone),
    (Caption: 'Hebrew (Windows 1255)';           ConvId: 'cp1255';    Bom: bomNone),
    (Caption: 'Japanese (Shift-JIS)';            ConvId: 'cp932';     Bom: bomNone),
    (Caption: 'Korean (Windows 949)';            ConvId: 'cp949';     Bom: bomNone),
    (Caption: 'Nordic (ISO 8859-10)';            ConvId: 'iso885910'; Bom: bomNone),
    (Caption: 'Nordic (Windows 865)';            ConvId: 'cp865';     Bom: bomNone),
    (Caption: 'Romanian (ISO 8859-16)';          ConvId: 'iso885916'; Bom: bomNone),
    (Caption: 'Thai (Windows 874)';              ConvId: 'cp874';     Bom: bomNone),
    (Caption: 'Turkish (ISO 8859-9)';            ConvId: 'iso88599';  Bom: bomNone),
    (Caption: 'Turkish (Windows 1254)';          ConvId: 'cp1254';    Bom: bomNone),
    (Caption: 'Vietnamese (Windows 1258)';       ConvId: 'cp1258';    Bom: bomNone),
    (Caption: 'Western (ISO 8859-1)';            ConvId: 'iso88591';  Bom: bomNone),
    (Caption: 'Western (ISO 8859-15)';           ConvId: 'iso885915'; Bom: bomNone),
    (Caption: 'Western (ISO 8859-3)';            ConvId: 'iso88593';  Bom: bomNone),
    (Caption: 'Western (Mac Roman)';             ConvId: 'macintosh'; Bom: bomNone),
    (Caption: 'Western (Windows 1252)';          ConvId: 'cp1252';    Bom: bomNone)
  );

// BOM, sinon UTF-8 si valide, sinon Windows-1252. UTF-16 sans BOM jamais devine.
function DetectEncoding(const ARaw: string): Integer;
// Heuristique UTF-16 sans BOM, pour ne pas envoyer du texte en vue hex. -1 = non.
function DetectUTF16NoBom(const ARaw: string): Integer;
function DecodeToUTF8(const ARaw: string; AEnc: Integer): string;
function EncodeFromUTF8(const AText: string; AEnc: Integer): string;
// octet nul dans la tete du fichier
function LooksBinary(const ARaw: string): Boolean;

implementation

function HasBom(const ARaw: string; ABom: TRTBom): Boolean;
begin
  case ABom of
    bomUTF8:    Result := (Length(ARaw) >= 3) and (ARaw[1] = #$EF) and
                          (ARaw[2] = #$BB) and (ARaw[3] = #$BF);
    bomUTF16LE: Result := (Length(ARaw) >= 2) and (ARaw[1] = #$FF) and (ARaw[2] = #$FE);
    bomUTF16BE: Result := (Length(ARaw) >= 2) and (ARaw[1] = #$FE) and (ARaw[2] = #$FF);
  else
    Result := False;
  end;
end;

function DetectEncoding(const ARaw: string): Integer;
begin
  if HasBom(ARaw, bomUTF8) then Exit(ENC_UTF8_BOM);
  if HasBom(ARaw, bomUTF16LE) then Exit(ENC_UTF16LE_BOM);
  if HasBom(ARaw, bomUTF16BE) then Exit(ENC_UTF16BE_BOM);
  if FindInvalidUTF8Codepoint(PChar(ARaw), Length(ARaw)) < 0 then
    Exit(ENC_UTF8);
  Result := ENC_WESTERN;
end;

function DetectUTF16NoBom(const ARaw: string): Integer;
var
  i, n, nw, zBE, zLE, z: Integer;
  big: Boolean;
  w, w2: Word;

  function WordAt(AIdx: Integer): Word; // 0-based
  begin
    if big then
      Result := (Ord(ARaw[AIdx * 2 + 1]) shl 8) or Ord(ARaw[AIdx * 2 + 2])
    else
      Result := (Ord(ARaw[AIdx * 2 + 2]) shl 8) or Ord(ARaw[AIdx * 2 + 1]);
  end;

begin
  Result := -1;
  n := Length(ARaw);
  if (n < 16) or Odd(n) then Exit;
  zBE := 0;
  zLE := 0;
  for i := 1 to n do
    if ARaw[i] = #0 then
      if Odd(i) then Inc(zBE) else Inc(zLE); // 1-based impair = 0-based pair
  z := zBE + zLE;
  // >= 30% de nuls (latin ~50%) et 90% du meme cote: les runs de 00 d'un
  // binaire chargent les deux parites et echouent ici
  if z < (n * 3) div 10 then Exit;
  if zBE * 10 >= z * 9 then big := True
  else if zLE * 10 >= z * 9 then big := False
  else Exit;
  // un binaire structure (01 00 02 00...) a la bonne parite: valider les code units
  nw := n div 2;
  i := 0;
  while i < nw do
  begin
    w := WordAt(i);
    if w = 0 then Exit;
    if (w < 32) and (w <> 9) and (w <> 10) and (w <> 13) then Exit;
    if (w >= $D800) and (w <= $DBFF) then
    begin
      if i + 1 >= nw then Break; // tete tronquee en pleine paire de surrogates
      w2 := WordAt(i + 1);
      if (w2 < $DC00) or (w2 > $DFFF) then Exit;
      Inc(i);
    end
    else if (w >= $DC00) and (w <= $DFFF) then Exit;
    Inc(i);
  end;
  if big then Result := ENC_UTF16BE else Result := ENC_UTF16LE;
end;

function UTF16BytesToUTF8(const ARaw: string; ABig: Boolean): string;
var
  u: UnicodeString;
  i, n: Integer;
  b0, b1: Word;
begin
  n := Length(ARaw) div 2; // octet impair final ignore
  SetLength(u, n);
  for i := 0 to n - 1 do
  begin
    b0 := Ord(ARaw[i * 2 + 1]);
    b1 := Ord(ARaw[i * 2 + 2]);
    if ABig then
      u[i + 1] := WideChar(b0 shl 8 or b1)
    else
      u[i + 1] := WideChar(b1 shl 8 or b0);
  end;
  Result := UTF16ToUTF8(u);
end;

function UTF8ToUTF16Bytes(const AText: string; ABig: Boolean): string;
var
  u: UnicodeString;
  i: Integer;
  w: Word;
begin
  u := UTF8ToUTF16(AText);
  SetLength(Result, Length(u) * 2);
  for i := 1 to Length(u) do
  begin
    w := Ord(u[i]);
    if ABig then
    begin
      Result[i * 2 - 1] := Chr(w shr 8);
      Result[i * 2]     := Chr(w and $FF);
    end
    else
    begin
      Result[i * 2 - 1] := Chr(w and $FF);
      Result[i * 2]     := Chr(w shr 8);
    end;
  end;
end;

function DecodeToUTF8(const ARaw: string; AEnc: Integer): string;
var
  raw: string;
  bom: TRTBom;
begin
  raw := ARaw;
  bom := Encodings[AEnc].Bom;
  if HasBom(raw, bom) then
    case bom of
      bomUTF8: Delete(raw, 1, 3);
      bomUTF16LE, bomUTF16BE: Delete(raw, 1, 2);
    end;
  case Encodings[AEnc].ConvId of
    'utf8':    Result := raw;
    'utf16le': Result := UTF16BytesToUTF8(raw, False);
    'utf16be': Result := UTF16BytesToUTF8(raw, True);
  else
    Result := ConvertEncoding(raw, Encodings[AEnc].ConvId, EncodingUTF8);
  end;
end;

function EncodeFromUTF8(const AText: string; AEnc: Integer): string;
begin
  case Encodings[AEnc].ConvId of
    'utf8':    Result := AText;
    'utf16le': Result := UTF8ToUTF16Bytes(AText, False);
    'utf16be': Result := UTF8ToUTF16Bytes(AText, True);
  else
    Result := ConvertEncoding(AText, EncodingUTF8, Encodings[AEnc].ConvId);
  end;
  case Encodings[AEnc].Bom of
    bomUTF8:    Result := #$EF#$BB#$BF + Result;
    bomUTF16LE: Result := #$FF#$FE + Result;
    bomUTF16BE: Result := #$FE#$FF + Result;
  end;
end;

function LooksBinary(const ARaw: string): Boolean;
var
  i, n: Integer;
begin
  n := Length(ARaw);
  if n > 8192 then n := 8192;
  for i := 1 to n do
    if ARaw[i] = #0 then Exit(True);
  // un UTF-16 est plein de nuls: son BOM doit le disculper AVANT cet appel
  Result := False;
end;

end.
