unit uOps;

{$mode objfpc}{$H+}

// Boite a outils ops, pure (sans LCL). Le cablage UI vit dans uActions.

interface

uses
  Classes, SysUtils;

type
  EOpsError = class(Exception);
  TOpsHash = (ohMD5, ohSHA1, ohSHA256, ohSHA512);

function HashText(AKind: TOpsHash; const S: RawByteString): string;
function HashFile(AKind: TOpsHash; const AFile: string): string;
function HashName(AKind: TOpsHash): string;
function HMACHex(AKind: TOpsHash; const AKey, AMessage: RawByteString): string;

function B64Encode(const S: RawByteString): string;
function B64Decode(const S: string): RawByteString;
function B64UrlEncode(const S: RawByteString): string;
function B64UrlDecode(const S: string): RawByteString;
function UrlEncode(const S: RawByteString): string;
function UrlDecode(const S: string): RawByteString;
function HtmlEncode(const S: RawByteString): string;
function HtmlDecode(const S: string): string;
function HexEncode(const S: RawByteString): string;
function HexDecode(const S: string): RawByteString;

function EscapeBash(const S: string): string;
function EscapePowerShell(const S: string): string;
function EscapeJSON(const S: string): string;
function EscapeYAML(const S: string): string;
function EscapeSQL(const S: string): string;
function EscapeSedPattern(const S: string): string;
function EscapeSedReplacement(const S: string): string;
function EscapeRegex(const S: string): string;
function EscapeSystemdExec(const S: string): string;
function EscapeNginxQuoted(const S: string): string;

function ModeToOctal(const AMode: string): string;
function OctalToMode(const AOctal: string): string;
function ChmodConvert(const S: string): string;
function UmaskReport(const AUmask: string): string;

// aleatoire fort : levent EOpsError si la source OS echoue
function GenPassword(ALen: Integer): string;
function GenUUIDv4: string;
function GenTokenHex(ABytes: Integer): string;
function GenTokenB64(ABytes: Integer): string;
function GenTokenB64Url(ABytes: Integer): string;
function GenApiKey(const APrefix: string; ABytes: Integer): string;
function NowUnixSeconds: Int64;
function NowISO8601(AUTC: Boolean): string;

function HtpasswdBcrypt(const AUser, APassword: RawByteString; ACost: Integer): string;
function Apr1Crypt(const APassword, ASalt: RawByteString): string;
function HtpasswdApr1(const AUser, APassword: RawByteString): string;
function HtpasswdSha(const AUser, APassword: RawByteString): string;

function JsonValidate(const S: string; out AError: string): Boolean;
function JsonFormat(const S: string; out AResult, AError: string): Boolean;
function JsonMinify(const S: string; out AResult, AError: string): Boolean;
function JsonSortKeys(const S: string; out AResult, AError: string): Boolean;

function XmlValidate(const S: string; out AError: string): Boolean;
function XmlFormat(const S: string; out AResult, AError: string): Boolean;

function ToLF(const S: string): string;
function ToCRLF(const S: string): string;
function ToCR(const S: string): string;

implementation

uses
  DateUtils, base64, md5, sha1, fpjson, jsonparser, uSha2, uBcrypt, uSecRand,
  DOM, XMLRead, XMLWrite;

const
  HEXL: array[0..15] of Char = '0123456789abcdef';

function HexOf(const S: RawByteString): string;
var
  i: SizeInt;   // Integer: l'index de sortie i*2 wrappe des ~1 Gio d'entree
  b: Byte;
begin
  SetLength(Result, Length(S) * 2);
  for i := 1 to Length(S) do
  begin
    b := Byte(S[i]);
    Result[i * 2 - 1] := HEXL[b shr 4];
    Result[i * 2] := HEXL[b and $0F];
  end;
end;

function HashRawS(AKind: TOpsHash; const S: RawByteString): RawByteString;
var
  m: TMD5Digest;
  s1: TSHA1Digest;
  c2: TSHA256Ctx;
  c5: TSHA512Ctx;
begin
  case AKind of
    ohMD5:
      begin
        m := MD5String(S);
        SetLength(Result, 16);
        Move(m, Result[1], 16);
      end;
    ohSHA1:
      begin
        s1 := SHA1String(S);
        SetLength(Result, 20);
        Move(s1, Result[1], 20);
      end;
    ohSHA256:
      begin
        SetLength(Result, 32);
        SHA256Init(c2, False);
        if S <> '' then SHA256Update(c2, S[1], Length(S));
        SHA256Final(c2, Result[1]);
      end;
    ohSHA512:
      begin
        SetLength(Result, 64);
        SHA512Init(c5, False);
        if S <> '' then SHA512Update(c5, S[1], Length(S));
        SHA512Final(c5, Result[1]);
      end;
  end;
end;

function HashText(AKind: TOpsHash; const S: RawByteString): string;
begin
  Result := HexOf(HashRawS(AKind, S));
end;

function HashName(AKind: TOpsHash): string;
begin
  case AKind of
    ohMD5: Result := 'md5';
    ohSHA1: Result := 'sha1';
    ohSHA256: Result := 'sha256';
    else Result := 'sha512';
  end;
end;

function HashFile(AKind: TOpsHash; const AFile: string): string;
var
  fs: TFileStream;
  buf: array[0..65535] of Byte;
  n: LongInt;
  mc: TMD5Context; md: TMD5Digest;
  sc: TSHA1Context; sd: TSHA1Digest;
begin
  case AKind of
    ohSHA256: Exit(SHA256FileHex(AFile));
    ohSHA512: Exit(SHA512FileHex(AFile));
  end;
  fs := TFileStream.Create(AFile, fmOpenRead or fmShareDenyNone);
  try
    if AKind = ohMD5 then MD5Init(mc) else SHA1Init(sc);
    repeat
      n := fs.Read(buf[0], SizeOf(buf));
      if n > 0 then
        if AKind = ohMD5 then MD5Update(mc, buf[0], n) else SHA1Update(sc, buf[0], n);
    until n <= 0;
  finally
    fs.Free;
  end;
  if AKind = ohMD5 then
  begin
    MD5Final(mc, md);
    SetLength(Result, 16); Move(md, Result[1], 16);
  end
  else
  begin
    SHA1Final(sc, sd);
    SetLength(Result, 20); Move(sd, Result[1], 20);
  end;
  Result := HexOf(Result);
end;

function HMACHex(AKind: TOpsHash; const AKey, AMessage: RawByteString): string;
var
  bs, i: Integer;
  key, ipad, opad: RawByteString;
begin
  if AKind = ohSHA512 then bs := 128 else bs := 64;
  key := AKey;
  if Length(key) > bs then key := HashRawS(AKind, key);
  if Length(key) < bs then
  begin
    i := Length(key);
    SetLength(key, bs);
    FillChar(key[i + 1], bs - i, 0);
  end;
  SetLength(ipad, bs);
  SetLength(opad, bs);
  for i := 1 to bs do
  begin
    ipad[i] := Chr(Byte(key[i]) xor $36);
    opad[i] := Chr(Byte(key[i]) xor $5C);
  end;
  Result := HexOf(HashRawS(AKind, opad + HashRawS(AKind, ipad + AMessage)));
end;

function B64Encode(const S: RawByteString): string;
begin
  Result := EncodeStringBase64(S);
end;

function B64Decode(const S: string): RawByteString;
begin
  Result := DecodeStringBase64(S);
end;

function B64UrlEncode(const S: RawByteString): string;
begin
  Result := EncodeStringBase64(S);
  Result := StringReplace(Result, '+', '-', [rfReplaceAll]);
  Result := StringReplace(Result, '/', '_', [rfReplaceAll]);
  Result := StringReplace(Result, '=', '', [rfReplaceAll]);
end;

function B64UrlDecode(const S: string): RawByteString;
var
  t: string;
begin
  t := StringReplace(S, '-', '+', [rfReplaceAll]);
  t := StringReplace(t, '_', '/', [rfReplaceAll]);
  while (Length(t) mod 4) <> 0 do t := t + '=';
  Result := DecodeStringBase64(t);
end;

function UrlEncode(const S: RawByteString): string;
var
  i: Integer;
  b: Byte;
begin
  Result := '';
  for i := 1 to Length(S) do
  begin
    b := Byte(S[i]);
    if (Char(b) in ['A'..'Z', 'a'..'z', '0'..'9', '-', '_', '.', '~']) then
      Result := Result + Char(b)
    else
      Result := Result + '%' + IntToHex(b, 2);   // hex majuscule (RFC 3986)
  end;
end;

function HexVal(c: Char): Integer;
begin
  case c of
    '0'..'9': Result := Ord(c) - Ord('0');
    'a'..'f': Result := Ord(c) - Ord('a') + 10;
    'A'..'F': Result := Ord(c) - Ord('A') + 10;
    else Result := -1;
  end;
end;

function UrlDecode(const S: string): RawByteString;
var
  i, h1, h2: Integer;
begin
  Result := '';
  i := 1;
  while i <= Length(S) do
  begin
    if (S[i] = '%') and (i + 2 <= Length(S)) then
    begin
      h1 := HexVal(S[i + 1]);
      h2 := HexVal(S[i + 2]);
      if (h1 >= 0) and (h2 >= 0) then
      begin
        Result := Result + Chr(h1 * 16 + h2);
        Inc(i, 3);
        Continue;
      end;
    end;
    Result := Result + S[i];
    Inc(i);
  end;
end;

function HtmlEncode(const S: RawByteString): string;
var
  i: Integer;
begin
  Result := '';
  for i := 1 to Length(S) do
    case S[i] of
      '&': Result := Result + '&amp;';
      '<': Result := Result + '&lt;';
      '>': Result := Result + '&gt;';
      '"': Result := Result + '&quot;';
      '''': Result := Result + '&#39;';
      else Result := Result + S[i];
    end;
end;

function CodepointToUTF8(cp: Integer): string;
begin
  if cp < $80 then
    Result := Chr(cp)
  else if cp < $800 then
    Result := Chr($C0 or (cp shr 6)) + Chr($80 or (cp and $3F))
  else if cp < $10000 then
    Result := Chr($E0 or (cp shr 12)) + Chr($80 or ((cp shr 6) and $3F)) +
              Chr($80 or (cp and $3F))
  else if cp <= $10FFFF then
    Result := Chr($F0 or (cp shr 18)) + Chr($80 or ((cp shr 12) and $3F)) +
              Chr($80 or ((cp shr 6) and $3F)) + Chr($80 or (cp and $3F))
  else
    Result := '';
end;

function HtmlDecode(const S: string): string;
var
  i, j, code: Integer;
  ent, low: string;
begin
  Result := '';
  i := 1;
  while i <= Length(S) do
  begin
    if S[i] = '&' then
    begin
      j := i + 1;
      while (j <= Length(S)) and (S[j] <> ';') and (j - i <= 10) do Inc(j);
      if (j <= Length(S)) and (S[j] = ';') then
      begin
        ent := Copy(S, i + 1, j - i - 1);
        low := LowerCase(ent);
        if (Length(ent) >= 2) and (ent[1] = '#') then
        begin
          if (ent[2] = 'x') or (ent[2] = 'X') then
            code := StrToIntDef('$' + Copy(ent, 3, Length(ent)), -1)
          else
            code := StrToIntDef(Copy(ent, 2, Length(ent)), -1);
          if code >= 0 then
          begin
            Result := Result + CodepointToUTF8(code);
            i := j + 1;
            Continue;
          end;
        end
        else if low = 'amp' then begin Result := Result + '&'; i := j + 1; Continue; end
        else if low = 'lt' then begin Result := Result + '<'; i := j + 1; Continue; end
        else if low = 'gt' then begin Result := Result + '>'; i := j + 1; Continue; end
        else if low = 'quot' then begin Result := Result + '"'; i := j + 1; Continue; end
        else if (low = 'apos') or (low = '#39') then begin Result := Result + ''''; i := j + 1; Continue; end
        else if low = 'nbsp' then begin Result := Result + ' '; i := j + 1; Continue; end;
      end;
    end;
    Result := Result + S[i];
    Inc(i);
  end;
end;

function HexEncode(const S: RawByteString): string;
begin
  Result := HexOf(S);
end;

function HexDecode(const S: string): RawByteString;
var
  i, h1, h2: Integer;
  nibs: string;
begin
  nibs := '';
  for i := 1 to Length(S) do
    if HexVal(S[i]) >= 0 then
      nibs := nibs + S[i]
    else if not (S[i] in [' ', #9, #10, #13]) then
      raise EOpsError.Create('Hex input contains a non-hex character');
  if (Length(nibs) mod 2) <> 0 then
    raise EOpsError.Create('Hex string has an odd number of digits');
  Result := '';
  i := 1;
  while i < Length(nibs) do
  begin
    h1 := HexVal(nibs[i]);
    h2 := HexVal(nibs[i + 1]);
    Result := Result + Chr(h1 * 16 + h2);
    Inc(i, 2);
  end;
end;

function EscapeBash(const S: string): string;
begin
  Result := '''' + StringReplace(S, '''', '''\''''', [rfReplaceAll]) + '''';
end;

function EscapePowerShell(const S: string): string;
const
  // PowerShell ferme une chaine '...' sur ces quotes Unicode comme sur le ' ASCII
  SMART: array[0..3] of string = (
    #$E2#$80#$98, #$E2#$80#$99, #$E2#$80#$9A, #$E2#$80#$9B);
var
  body: string;
  i: Integer;
begin
  body := StringReplace(S, '''', '''''', [rfReplaceAll]);
  for i := 0 to High(SMART) do
    body := StringReplace(body, SMART[i], SMART[i] + SMART[i], [rfReplaceAll]);
  Result := '''' + body + '''';
end;

function EscapeJSON(const S: string): string;
var
  i: Integer;
  c: Char;
begin
  Result := '"';
  for i := 1 to Length(S) do
  begin
    c := S[i];
    case c of
      '"': Result := Result + '\"';
      '\': Result := Result + '\\';
      #8: Result := Result + '\b';
      #9: Result := Result + '\t';
      #10: Result := Result + '\n';
      #12: Result := Result + '\f';
      #13: Result := Result + '\r';
      else
        if c < ' ' then
          Result := Result + '\u' + LowerCase(IntToHex(Ord(c), 4))
        else
          Result := Result + c;
    end;
  end;
  Result := Result + '"';
end;

function EscapeYAML(const S: string): string;
var
  i: Integer;
  c: Char;
begin
  Result := '"';
  for i := 1 to Length(S) do
  begin
    c := S[i];
    case c of
      '"': Result := Result + '\"';
      '\': Result := Result + '\\';
      #9: Result := Result + '\t';
      #10: Result := Result + '\n';
      #13: Result := Result + '\r';
      else
        if c < ' ' then
          Result := Result + '\x' + LowerCase(IntToHex(Ord(c), 2))
        else
          Result := Result + c;
    end;
  end;
  Result := Result + '"';
end;

function EscapeSQL(const S: string): string;
begin
  // ANSI seulement : sur MySQL (backslash-escapes) une valeur finissant par \ reste injectable
  Result := '''' + StringReplace(S, '''', '''''', [rfReplaceAll]) + '''';
end;

function EscChars(const S, ASpecials: string): string;
var
  i: Integer;
begin
  Result := '';
  for i := 1 to Length(S) do
  begin
    if Pos(S[i], ASpecials) > 0 then Result := Result + '\';
    Result := Result + S[i];
  end;
end;

function EscapeSedPattern(const S: string): string;
begin
  Result := EscChars(S, '\.*[]^$/');
end;

function EscapeSedReplacement(const S: string): string;
begin
  Result := EscChars(S, '\&/');
end;

function EscapeRegex(const S: string): string;
begin
  Result := EscChars(S, '\.^$|?*+()[]{}');
end;

function EscapeSystemdExec(const S: string): string;
begin
  Result := StringReplace(S, '%', '%%', [rfReplaceAll]);
  Result := StringReplace(Result, '$', '$$', [rfReplaceAll]);
end;

function EscapeNginxQuoted(const S: string): string;
begin
  // le $ nginx reste interpole : la conf n'offre aucun echappement pour lui
  Result := '"' + StringReplace(StringReplace(S, '\', '\\', [rfReplaceAll]),
    '"', '\"', [rfReplaceAll]) + '"';
end;

function ModeToOctal(const AMode: string): string;
var
  s: string;
  v: array[0..2] of Integer;
  spec, t, i: Integer;
  c: Char;
begin
  s := Trim(AMode);
  // type de fichier en tete (ls -l) tolere : -rwxr-x--- / drwxr-xr-x
  if (Length(s) = 10) and (s[1] in ['-', 'd', 'l', 'b', 'c', 's', 'p']) then
    Delete(s, 1, 1);
  if Length(s) <> 9 then
    raise EOpsError.Create('Symbolic mode must be 9 characters (rwxr-x---)');
  spec := 0;
  for t := 0 to 2 do
  begin
    v[t] := 0;
    for i := 1 to 3 do
    begin
      c := s[t * 3 + i];
      case i of
        1: if c = 'r' then v[t] := v[t] + 4
           else if c <> '-' then raise EOpsError.Create('Bad mode char: ' + c);
        2: if c = 'w' then v[t] := v[t] + 2
           else if c <> '-' then raise EOpsError.Create('Bad mode char: ' + c);
        3: case c of
             'x': v[t] := v[t] + 1;
             '-': ;
             's', 'S':
               begin
                 if t = 2 then raise EOpsError.Create('s is not valid in the other triad');
                 if c = 's' then v[t] := v[t] + 1;
                 if t = 0 then spec := spec + 4 else spec := spec + 2;
               end;
             't', 'T':
               begin
                 if t <> 2 then raise EOpsError.Create('t is only valid in the other triad');
                 if c = 't' then v[t] := v[t] + 1;
                 spec := spec + 1;
               end;
             else raise EOpsError.Create('Bad mode char: ' + c);
           end;
      end;
    end;
  end;
  Result := Format('%d%d%d', [v[0], v[1], v[2]]);
  if spec > 0 then Result := IntToStr(spec) + Result;
end;

function OctalToMode(const AOctal: string): string;
const
  RWX: array[0..7] of string =
    ('---', '--x', '-w-', '-wx', 'r--', 'r-x', 'rw-', 'rwx');
var
  s: string;
  i, spec: Integer;
  d: array[0..2] of Integer;
begin
  s := Trim(AOctal);
  if (Length(s) < 3) or (Length(s) > 4) then
    raise EOpsError.Create('Octal mode must be 3 or 4 digits');
  for i := 1 to Length(s) do
    if not (s[i] in ['0'..'7']) then
      raise EOpsError.Create('Bad octal digit: ' + s[i]);
  spec := 0;
  if Length(s) = 4 then
  begin
    spec := Ord(s[1]) - Ord('0');
    Delete(s, 1, 1);
  end;
  for i := 0 to 2 do
    d[i] := Ord(s[i + 1]) - Ord('0');
  Result := RWX[d[0]] + RWX[d[1]] + RWX[d[2]];
  // bits speciaux : minuscule si le x sous-jacent est pose, majuscule sinon
  if (spec and 4) <> 0 then
    if Result[3] = 'x' then Result[3] := 's' else Result[3] := 'S';
  if (spec and 2) <> 0 then
    if Result[6] = 'x' then Result[6] := 's' else Result[6] := 'S';
  if (spec and 1) <> 0 then
    if Result[9] = 'x' then Result[9] := 't' else Result[9] := 'T';
end;

function ChmodConvert(const S: string): string;
var
  t: string;
  i: Integer;
  oct: Boolean;
begin
  t := Trim(S);
  if t = '' then raise EOpsError.Create('Empty mode');
  oct := (Length(t) >= 3) and (Length(t) <= 4);
  if oct then
    for i := 1 to Length(t) do
      if not (t[i] in ['0'..'7']) then begin oct := False; Break; end;
  if oct then Result := OctalToMode(t)
  else Result := ModeToOctal(t);
end;

function UmaskReport(const AUmask: string): string;
var
  s: string;
  i, m: Integer;
  fOct, dOct: array[0..2] of Integer;
  fs, ds: string;
begin
  s := Trim(AUmask);
  if (Length(s) < 1) or (Length(s) > 4) then
    raise EOpsError.Create('umask must be 1 to 4 octal digits');
  for i := 1 to Length(s) do
    if not (s[i] in ['0'..'7']) then
      raise EOpsError.Create('Bad octal digit: ' + s[i]);
  while Length(s) < 3 do s := '0' + s;
  if Length(s) = 4 then Delete(s, 1, 1);
  fs := ''; ds := '';
  for i := 0 to 2 do
  begin
    m := Ord(s[i + 1]) - Ord('0');
    fOct[i] := 6 and (not m);
    dOct[i] := 7 and (not m);
    fs := fs + IntToStr(fOct[i]);
    ds := ds + IntToStr(dOct[i]);
  end;
  Result := Format('umask %s -> files %s (%s), dirs %s (%s)',
    [s, fs, OctalToMode(fs), ds, OctalToMode(ds)]);
end;

function GenPassword(ALen: Integer): string;
const
  CS = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789' +
       '!@#$%^&*()-_=+[]{};:,.?';
var
  n, limit, i: Integer;
  b: Byte;
begin
  Result := '';
  if ALen <= 0 then Exit;
  n := Length(CS);
  limit := 256 - (256 mod n);   // rejet anti-biais modulo
  i := 0;
  while i < ALen do
  begin
    if not SecureRandomBytes(b, 1) then
      raise EOpsError.Create('Secure random source unavailable');
    if b >= limit then Continue;
    Result := Result + CS[(b mod n) + 1];
    Inc(i);
  end;
end;

function GenUUIDv4: string;
var
  b: array[0..15] of Byte;
begin
  if not SecureRandomBytes(b[0], 16) then
    raise EOpsError.Create('Secure random source unavailable');
  b[6] := (b[6] and $0F) or $40;   // version 4
  b[8] := (b[8] and $3F) or $80;   // variant RFC 4122
  Result := LowerCase(Format(
    '%.2x%.2x%.2x%.2x-%.2x%.2x-%.2x%.2x-%.2x%.2x-%.2x%.2x%.2x%.2x%.2x%.2x',
    [b[0], b[1], b[2], b[3], b[4], b[5], b[6], b[7],
     b[8], b[9], b[10], b[11], b[12], b[13], b[14], b[15]]));
end;

function RandRaw(ABytes: Integer): RawByteString;
begin
  if (ABytes <= 0) or (ABytes > 4096) then
    raise EOpsError.Create('Byte count must be 1..4096');
  SetLength(Result, ABytes);
  if not SecureRandomBytes(Result[1], ABytes) then
    raise EOpsError.Create('Secure random source unavailable');
end;

function GenTokenHex(ABytes: Integer): string;
begin
  Result := HexOf(RandRaw(ABytes));
end;

function GenTokenB64(ABytes: Integer): string;
begin
  Result := EncodeStringBase64(RandRaw(ABytes));
end;

function GenTokenB64Url(ABytes: Integer): string;
var
  i: Integer;
begin
  Result := EncodeStringBase64(RandRaw(ABytes));
  for i := 1 to Length(Result) do
    case Result[i] of
      '+': Result[i] := '-';
      '/': Result[i] := '_';
    end;
  while (Result <> '') and (Result[Length(Result)] = '=') do
    SetLength(Result, Length(Result) - 1);
end;

function GenApiKey(const APrefix: string; ABytes: Integer): string;
var
  p: string;
begin
  p := Trim(APrefix);
  if p = '' then p := 'key';
  Result := p + '_' + GenTokenB64Url(ABytes);
end;

function NowUnixSeconds: Int64;
begin
  Result := DateTimeToUnix(LocalTimeToUniversal(Now));
end;

function NowISO8601(AUTC: Boolean): string;
var
  bias, disp: Integer;
  sign: Char;
begin
  if AUTC then
    Result := FormatDateTime('yyyy-mm-dd"T"hh:nn:ss', LocalTimeToUniversal(Now)) + 'Z'
  else
  begin
    bias := GetLocalTimeOffset;   // minutes : UTC = local + bias
    disp := -bias;
    if disp >= 0 then sign := '+' else sign := '-';
    Result := FormatDateTime('yyyy-mm-dd"T"hh:nn:ss', Now) +
      Format('%s%.2d:%.2d', [sign, Abs(disp) div 60, Abs(disp) mod 60]);
  end;
end;

function HtpasswdBcrypt(const AUser, APassword: RawByteString; ACost: Integer): string;
var
  salt: array[0..15] of Byte;
begin
  if (ACost < 4) or (ACost > 31) then ACost := 10;
  if not SecureRandomBytes(salt[0], 16) then
    raise EOpsError.Create('Secure random source unavailable');
  Result := AUser + ':' + BcryptHash(APassword, ACost, salt[0]);
end;

const
  ITOA64 = './0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz';

procedure To64(var ADest: string; AVal: LongWord; ACount: Integer);
begin
  while ACount > 0 do
  begin
    ADest := ADest + ITOA64[(AVal and $3F) + 1];
    AVal := AVal shr 6;
    Dec(ACount);
  end;
end;

procedure UpdS(var ACtx: TMD5Context; const S: RawByteString); inline;
var
  p: Pointer;
begin
  if S <> '' then
  begin
    p := Pointer(S);   // MD5Update prend un var Buf, pas un const
    MD5Update(ACtx, p^, Length(S));
  end;
end;

// md5crypt (Poul-Henning Kamp) ; magic '$apr1$' = Apache.
function CryptMD5(const APw, ASalt, AMagic: RawByteString): string;
var
  ctx, ctx1: TMD5Context;
  fin, alt: TMD5Digest;
  pl, i: Integer;
  zero, fb: Byte;
  p: string;
begin
  zero := 0;
  MD5Init(ctx);
  UpdS(ctx, APw);
  UpdS(ctx, AMagic);
  UpdS(ctx, ASalt);

  MD5Init(ctx1);
  UpdS(ctx1, APw);
  UpdS(ctx1, ASalt);
  UpdS(ctx1, APw);
  MD5Final(ctx1, alt);

  pl := Length(APw);
  while pl > 0 do
  begin
    if pl > 16 then MD5Update(ctx, alt, 16) else MD5Update(ctx, alt, pl);
    Dec(pl, 16);
  end;

  i := Length(APw);
  while i <> 0 do
  begin
    if (i and 1) <> 0 then MD5Update(ctx, zero, 1)
    else begin fb := Byte(APw[1]); MD5Update(ctx, fb, 1); end;
    i := i shr 1;
  end;
  MD5Final(ctx, fin);

  for i := 0 to 999 do
  begin
    MD5Init(ctx1);
    if (i and 1) <> 0 then UpdS(ctx1, APw) else MD5Update(ctx1, fin, 16);
    if (i mod 3) <> 0 then UpdS(ctx1, ASalt);
    if (i mod 7) <> 0 then UpdS(ctx1, APw);
    if (i and 1) <> 0 then MD5Update(ctx1, fin, 16) else UpdS(ctx1, APw);
    MD5Final(ctx1, fin);
  end;

  p := '';
  To64(p, (LongWord(fin[0]) shl 16) or (LongWord(fin[6]) shl 8) or fin[12], 4);
  To64(p, (LongWord(fin[1]) shl 16) or (LongWord(fin[7]) shl 8) or fin[13], 4);
  To64(p, (LongWord(fin[2]) shl 16) or (LongWord(fin[8]) shl 8) or fin[14], 4);
  To64(p, (LongWord(fin[3]) shl 16) or (LongWord(fin[9]) shl 8) or fin[15], 4);
  To64(p, (LongWord(fin[4]) shl 16) or (LongWord(fin[10]) shl 8) or fin[5], 4);
  To64(p, fin[11], 2);

  Result := AMagic + ASalt + '$' + p;
end;

function Apr1Crypt(const APassword, ASalt: RawByteString): string;
var
  s: RawByteString;
begin
  s := ASalt;
  if Length(s) > 8 then SetLength(s, 8);
  Result := CryptMD5(APassword, s, '$apr1$');
end;

function RandSalt(ALen: Integer): string;
var
  i: Integer;
  b: Byte;
begin
  Result := '';
  for i := 1 to ALen do
  begin
    if not SecureRandomBytes(b, 1) then
      raise EOpsError.Create('Secure random source unavailable');
    Result := Result + ITOA64[(b mod 64) + 1];
  end;
end;

function HtpasswdApr1(const AUser, APassword: RawByteString): string;
begin
  Result := AUser + ':' + Apr1Crypt(APassword, RandSalt(8));
end;

function HtpasswdSha(const AUser, APassword: RawByteString): string;
begin
  Result := AUser + ':{SHA}' + EncodeStringBase64(HashRawS(ohSHA1, APassword));
end;

function JsonValidate(const S: string; out AError: string): Boolean;
var
  d: TJSONData;
begin
  AError := '';
  d := nil;
  try
    d := GetJSON(S);
    Result := d <> nil;
    if not Result then AError := 'empty document';
  except
    on E: Exception do
    begin
      Result := False;
      AError := E.Message;
    end;
  end;
  d.Free;
end;

function JsonFormat(const S: string; out AResult, AError: string): Boolean;
var
  d: TJSONData;
begin
  AError := '';
  AResult := '';
  d := nil;
  try
    d := GetJSON(S);
    if d = nil then begin AError := 'empty document'; Exit(False); end;
    AResult := d.FormatJSON;
    Result := True;
  except
    on E: Exception do
    begin
      Result := False;
      AError := E.Message;
    end;
  end;
  d.Free;
end;

// ordre TOTAL (CI, casse, index d'origine) : quicksort instable mais deterministe
function JsonNameCompare(List: TStringList; Index1, Index2: Integer): Integer;
begin
  Result := CompareText(List[Index1], List[Index2]);
  if Result = 0 then Result := CompareStr(List[Index1], List[Index2]);
  if Result = 0 then
    Result := PtrInt(List.Objects[Index1]) - PtrInt(List.Objects[Index2]);
end;

// fpjson n'expose pas de reorder in place : on reconstruit l'arbre
function SortJsonNode(D: TJSONData): TJSONData;
var
  obj, nobj: TJSONObject;
  arr, narr: TJSONArray;
  names: TStringList;
  i: Integer;
begin
  case D.JSONType of
    jtObject:
      begin
        obj := TJSONObject(D);
        names := TStringList.Create;
        try
          for i := 0 to obj.Count - 1 do
            names.AddObject(obj.Names[i], TObject(PtrInt(i)));
          names.CustomSort(@JsonNameCompare);
          nobj := TJSONObject.Create;
          try
            for i := 0 to names.Count - 1 do
              nobj.Add(names[i],
                SortJsonNode(obj.Items[PtrInt(names.Objects[i])]));
          except
            nobj.Free;
            raise;
          end;
          Result := nobj;
        finally
          names.Free;
        end;
      end;
    jtArray:
      begin
        arr := TJSONArray(D);
        narr := TJSONArray.Create;
        try
          for i := 0 to arr.Count - 1 do
            narr.Add(SortJsonNode(arr.Items[i]));
        except
          narr.Free;
          raise;
        end;
        Result := narr;
      end;
  else
    Result := D.Clone;
  end;
end;

function JsonSortKeys(const S: string; out AResult, AError: string): Boolean;
var
  d, sorted: TJSONData;
begin
  AError := '';
  AResult := '';
  d := nil;
  try
    d := GetJSON(S);
    if d = nil then begin AError := 'empty document'; Exit(False); end;
    sorted := SortJsonNode(d);
    try
      AResult := sorted.FormatJSON;
    finally
      sorted.Free;
    end;
    Result := True;
  except
    on E: Exception do
    begin
      Result := False;
      AError := E.Message;
    end;
  end;
  d.Free;
end;

function JsonMinify(const S: string; out AResult, AError: string): Boolean;
var
  d: TJSONData;
  oldC: Boolean;
begin
  AError := '';
  AResult := '';
  d := nil;
  try
    d := GetJSON(S);
    if d = nil then begin AError := 'empty document'; Exit(False); end;
    oldC := TJSONData.CompressedJSON;   // AsJSON met des espaces par defaut
    TJSONData.CompressedJSON := True;
    try
      AResult := d.AsJSON;
    finally
      TJSONData.CompressedJSON := oldC;
    end;
    Result := True;
  except
    on E: Exception do
    begin
      Result := False;
      AError := E.Message;
    end;
  end;
  d.Free;
end;

// DOCTYPE/ENTITY rejetes avant parse : ReadXMLFile developpe les entites internes (billion laughs)
function XmlHasDoctype(const S: string): Boolean;
var
  i: Integer;
  w: string;
begin
  Result := False;
  // -7 : '<!ENTITY' fait 8 octets et doit tenir jusqu'a Length(S) inclus
  for i := 1 to Length(S) - 7 do
    if (S[i] = '<') and (S[i + 1] = '!') then
    begin
      w := UpperCase(Copy(S, i + 2, 7));
      if (w = 'DOCTYPE') or (Copy(w, 1, 6) = 'ENTITY') then Exit(True);
    end;
end;

function XmlValidate(const S: string; out AError: string): Boolean;
var
  doc: TXMLDocument;
  ss: TStringStream;
begin
  AError := '';
  doc := nil;
  if XmlHasDoctype(S) then
  begin
    AError := 'DOCTYPE/ENTITY declarations are not supported (entity expansion risk)';
    Exit(False);
  end;
  ss := TStringStream.Create(S);
  try
    try
      ReadXMLFile(doc, ss);
      Result := (doc <> nil) and (doc.DocumentElement <> nil);
      if not Result then AError := 'no root element';
    except
      on E: Exception do begin Result := False; AError := E.Message; end;
    end;
  finally
    ss.Free;
    doc.Free;
  end;
end;

function XmlFormat(const S: string; out AResult, AError: string): Boolean;
var
  doc: TXMLDocument;
  inS, outS: TStringStream;
begin
  AError := '';
  AResult := '';
  doc := nil;
  if XmlHasDoctype(S) then
  begin
    AError := 'DOCTYPE/ENTITY declarations are not supported (entity expansion risk)';
    Exit(False);
  end;
  inS := TStringStream.Create(S);
  outS := TStringStream.Create('');
  try
    try
      ReadXMLFile(doc, inS);
      if (doc = nil) or (doc.DocumentElement = nil) then
      begin
        AError := 'no root element';
        Exit(False);
      end;
      WriteXMLFile(doc, outS);
      AResult := outS.DataString;
      Result := True;
    except
      on E: Exception do begin Result := False; AError := E.Message; end;
    end;
  finally
    inS.Free;
    outS.Free;
    doc.Free;
  end;
end;

function NormalizeEOL(const S, AEol: string): string;
var
  i, o, k, n, el: Integer;
begin
  n := Length(S);
  el := Length(AEol);
  SetLength(Result, n * (el + 1));
  o := 0;
  i := 1;
  while i <= n do
  begin
    if S[i] = #13 then
    begin
      for k := 1 to el do begin Inc(o); Result[o] := AEol[k]; end;
      if (i < n) and (S[i + 1] = #10) then Inc(i);
    end
    else if S[i] = #10 then
    begin
      for k := 1 to el do begin Inc(o); Result[o] := AEol[k]; end;
    end
    else
    begin
      Inc(o);
      Result[o] := S[i];
    end;
    Inc(i);
  end;
  SetLength(Result, o);
end;

function ToLF(const S: string): string;
begin
  Result := NormalizeEOL(S, #10);
end;

function ToCRLF(const S: string): string;
begin
  Result := NormalizeEOL(S, #13#10);
end;

function ToCR(const S: string): string;
begin
  Result := NormalizeEOL(S, #13);
end;

end.
