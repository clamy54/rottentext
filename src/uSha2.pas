unit uSha2;

{$mode objfpc}{$H+}
{$Q-}{$R-}  // arithmetique modulaire (hash): pas de controle overflow/range

// SHA-2 conforme aux vecteurs NIST.

interface

type
  TSHA256Ctx = record
    H: array[0..7] of DWord;
    Buf: array[0..63] of Byte;
    Len: Cardinal;
    Total: QWord;
    OutBytes: Integer;
  end;

  TSHA512Ctx = record
    H: array[0..7] of QWord;
    Buf: array[0..127] of Byte;
    Len: Cardinal;
    Total: QWord;
    OutBytes: Integer;
  end;

procedure SHA256Init(out C: TSHA256Ctx; A224: Boolean = False);
procedure SHA256Update(var C: TSHA256Ctx; const ABuf; ALen: PtrUInt);
procedure SHA256Final(var C: TSHA256Ctx; out ADigest);  // ecrit C.OutBytes octets

procedure SHA512Init(out C: TSHA512Ctx; A384: Boolean = False);
procedure SHA512Update(var C: TSHA512Ctx; const ABuf; ALen: PtrUInt);
procedure SHA512Final(var C: TSHA512Ctx; out ADigest);  // ecrit C.OutBytes octets

function BytesToHex(const ABuf; ALen: Integer): string;

function SHA224Hex(const S: RawByteString): string;
function SHA256Hex(const S: RawByteString): string;
function SHA384Hex(const S: RawByteString): string;
function SHA512Hex(const S: RawByteString): string;

function SHA256FileHex(const AFile: string; A224: Boolean = False): string;
function SHA512FileHex(const AFile: string; A384: Boolean = False): string;

implementation

uses
  Classes, SysUtils;

const
  K256: array[0..63] of DWord = (
    $428a2f98, $71374491, $b5c0fbcf, $e9b5dba5, $3956c25b, $59f111f1, $923f82a4, $ab1c5ed5,
    $d807aa98, $12835b01, $243185be, $550c7dc3, $72be5d74, $80deb1fe, $9bdc06a7, $c19bf174,
    $e49b69c1, $efbe4786, $0fc19dc6, $240ca1cc, $2de92c6f, $4a7484aa, $5cb0a9dc, $76f988da,
    $983e5152, $a831c66d, $b00327c8, $bf597fc7, $c6e00bf3, $d5a79147, $06ca6351, $14292967,
    $27b70a85, $2e1b2138, $4d2c6dfc, $53380d13, $650a7354, $766a0abb, $81c2c92e, $92722c85,
    $a2bfe8a1, $a81a664b, $c24b8b70, $c76c51a3, $d192e819, $d6990624, $f40e3585, $106aa070,
    $19a4c116, $1e376c08, $2748774c, $34b0bcb5, $391c0cb3, $4ed8aa4a, $5b9cca4f, $682e6ff3,
    $748f82ee, $78a5636f, $84c87814, $8cc70208, $90befffa, $a4506ceb, $bef9a3f7, $c67178f2);

  IV256: array[0..7] of DWord = (
    $6a09e667, $bb67ae85, $3c6ef372, $a54ff53a, $510e527f, $9b05688c, $1f83d9ab, $5be0cd19);
  IV224: array[0..7] of DWord = (
    $c1059ed8, $367cd507, $3070dd17, $f70e5939, $ffc00b31, $68581511, $64f98fa7, $befa4fa4);

  K512: array[0..79] of QWord = (
    QWord($428a2f98d728ae22), QWord($7137449123ef65cd), QWord($b5c0fbcfec4d3b2f), QWord($e9b5dba58189dbbc),
    QWord($3956c25bf348b538), QWord($59f111f1b605d019), QWord($923f82a4af194f9b), QWord($ab1c5ed5da6d8118),
    QWord($d807aa98a3030242), QWord($12835b0145706fbe), QWord($243185be4ee4b28c), QWord($550c7dc3d5ffb4e2),
    QWord($72be5d74f27b896f), QWord($80deb1fe3b1696b1), QWord($9bdc06a725c71235), QWord($c19bf174cf692694),
    QWord($e49b69c19ef14ad2), QWord($efbe4786384f25e3), QWord($0fc19dc68b8cd5b5), QWord($240ca1cc77ac9c65),
    QWord($2de92c6f592b0275), QWord($4a7484aa6ea6e483), QWord($5cb0a9dcbd41fbd4), QWord($76f988da831153b5),
    QWord($983e5152ee66dfab), QWord($a831c66d2db43210), QWord($b00327c898fb213f), QWord($bf597fc7beef0ee4),
    QWord($c6e00bf33da88fc2), QWord($d5a79147930aa725), QWord($06ca6351e003826f), QWord($142929670a0e6e70),
    QWord($27b70a8546d22ffc), QWord($2e1b21385c26c926), QWord($4d2c6dfc5ac42aed), QWord($53380d139d95b3df),
    QWord($650a73548baf63de), QWord($766a0abb3c77b2a8), QWord($81c2c92e47edaee6), QWord($92722c851482353b),
    QWord($a2bfe8a14cf10364), QWord($a81a664bbc423001), QWord($c24b8b70d0f89791), QWord($c76c51a30654be30),
    QWord($d192e819d6ef5218), QWord($d69906245565a910), QWord($f40e35855771202a), QWord($106aa07032bbd1b8),
    QWord($19a4c116b8d2d0c8), QWord($1e376c085141ab53), QWord($2748774cdf8eeb99), QWord($34b0bcb5e19b48a8),
    QWord($391c0cb3c5c95a63), QWord($4ed8aa4ae3418acb), QWord($5b9cca4f7763e373), QWord($682e6ff3d6b2b8a3),
    QWord($748f82ee5defb2fc), QWord($78a5636f43172f60), QWord($84c87814a1f0ab72), QWord($8cc702081a6439ec),
    QWord($90befffa23631e28), QWord($a4506cebde82bde9), QWord($bef9a3f7b2c67915), QWord($c67178f2e372532b),
    QWord($ca273eceea26619c), QWord($d186b8c721c0c207), QWord($eada7dd6cde0eb1e), QWord($f57d4f7fee6ed178),
    QWord($06f067aa72176fba), QWord($0a637dc5a2c898a6), QWord($113f9804bef90dae), QWord($1b710b35131c471b),
    QWord($28db77f523047d84), QWord($32caab7b40c72493), QWord($3c9ebe0a15c9bebc), QWord($431d67c49c100d4c),
    QWord($4cc5d4becb3e42b6), QWord($597f299cfc657e2a), QWord($5fcb6fab3ad6faec), QWord($6c44198c4a475817));

  IV512: array[0..7] of QWord = (
    QWord($6a09e667f3bcc908), QWord($bb67ae8584caa73b), QWord($3c6ef372fe94f82b), QWord($a54ff53a5f1d36f1),
    QWord($510e527fade682d1), QWord($9b05688c2b3e6c1f), QWord($1f83d9abfb41bd6b), QWord($5be0cd19137e2179));
  IV384: array[0..7] of QWord = (
    QWord($cbbb9d5dc1059ed8), QWord($629a292a367cd507), QWord($9159015a3070dd17), QWord($152fecd8f70e5939),
    QWord($67332667ffc00b31), QWord($8eb44a8768581511), QWord($db0c2e0d64f98fa7), QWord($47b5481dbefa4fa4));

const
  HEXD: array[0..15] of Char = '0123456789abcdef';

function BytesToHex(const ABuf; ALen: Integer): string;
var
  p: PByte;
  i: Integer;
begin
  p := @ABuf;
  SetLength(Result, ALen * 2);
  for i := 0 to ALen - 1 do
  begin
    Result[i * 2 + 1] := HEXD[p[i] shr 4];
    Result[i * 2 + 2] := HEXD[p[i] and $0F];
  end;
end;

function ROTR32(x: DWord; n: Byte): DWord; inline;
begin
  Result := (x shr n) or (x shl (32 - n));
end;

procedure SHA256Block(var Ctx: TSHA256Ctx; P: PByte);
var
  W: array[0..63] of DWord;
  a, b, c, d, e, f, g, h, t1, t2: DWord;
  i: Integer;
begin
  for i := 0 to 15 do
    W[i] := (DWord(P[i * 4]) shl 24) or (DWord(P[i * 4 + 1]) shl 16) or
            (DWord(P[i * 4 + 2]) shl 8) or DWord(P[i * 4 + 3]);
  for i := 16 to 63 do
    W[i] := (ROTR32(W[i - 2], 17) xor ROTR32(W[i - 2], 19) xor (W[i - 2] shr 10)) +
            W[i - 7] +
            (ROTR32(W[i - 15], 7) xor ROTR32(W[i - 15], 18) xor (W[i - 15] shr 3)) +
            W[i - 16];
  a := Ctx.H[0]; b := Ctx.H[1]; c := Ctx.H[2]; d := Ctx.H[3];
  e := Ctx.H[4]; f := Ctx.H[5]; g := Ctx.H[6]; h := Ctx.H[7];
  for i := 0 to 63 do
  begin
    t1 := h + (ROTR32(e, 6) xor ROTR32(e, 11) xor ROTR32(e, 25)) +
          ((e and f) xor ((not e) and g)) + K256[i] + W[i];
    t2 := (ROTR32(a, 2) xor ROTR32(a, 13) xor ROTR32(a, 22)) +
          ((a and b) xor (a and c) xor (b and c));
    h := g; g := f; f := e; e := d + t1;
    d := c; c := b; b := a; a := t1 + t2;
  end;
  Inc(Ctx.H[0], a); Inc(Ctx.H[1], b); Inc(Ctx.H[2], c); Inc(Ctx.H[3], d);
  Inc(Ctx.H[4], e); Inc(Ctx.H[5], f); Inc(Ctx.H[6], g); Inc(Ctx.H[7], h);
end;

procedure SHA256Init(out C: TSHA256Ctx; A224: Boolean);
var
  i: Integer;
begin
  if A224 then
  begin
    for i := 0 to 7 do C.H[i] := IV224[i];
    C.OutBytes := 28;
  end
  else
  begin
    for i := 0 to 7 do C.H[i] := IV256[i];
    C.OutBytes := 32;
  end;
  C.Len := 0;
  C.Total := 0;
end;

procedure SHA256Update(var C: TSHA256Ctx; const ABuf; ALen: PtrUInt);
var
  p: PByte;
  take: PtrUInt;
begin
  p := @ABuf;
  Inc(C.Total, ALen);
  while ALen > 0 do
  begin
    if (C.Len = 0) and (ALen >= 64) then
    begin
      SHA256Block(C, p);
      Inc(p, 64);
      Dec(ALen, 64);
    end
    else
    begin
      take := 64 - C.Len;
      if take > ALen then take := ALen;
      Move(p^, C.Buf[C.Len], take);
      Inc(C.Len, take);
      Inc(p, take);
      Dec(ALen, take);
      if C.Len = 64 then
      begin
        SHA256Block(C, @C.Buf[0]);
        C.Len := 0;
      end;
    end;
  end;
end;

procedure SHA256Final(var C: TSHA256Ctx; out ADigest);
var
  bits: QWord;
  pad: Integer;
  lenbuf: array[0..7] of Byte;
  i: Integer;
  one: Byte;
  o: PByte;
begin
  bits := C.Total * 8;
  for i := 0 to 7 do
    lenbuf[7 - i] := Byte(bits shr (i * 8));
  one := $80;
  SHA256Update(C, one, 1);
  if C.Len <= 56 then pad := 56 - C.Len else pad := 120 - C.Len;
  while pad > 0 do
  begin
    one := 0;
    SHA256Update(C, one, 1);
    Dec(pad);
  end;
  SHA256Update(C, lenbuf[0], 8);
  o := @ADigest;
  for i := 0 to (C.OutBytes div 4) - 1 do
  begin
    o[i * 4]     := Byte(C.H[i] shr 24);
    o[i * 4 + 1] := Byte(C.H[i] shr 16);
    o[i * 4 + 2] := Byte(C.H[i] shr 8);
    o[i * 4 + 3] := Byte(C.H[i]);
  end;
end;

function ROTR64(x: QWord; n: Byte): QWord; inline;
begin
  Result := (x shr n) or (x shl (64 - n));
end;

procedure SHA512Block(var Ctx: TSHA512Ctx; P: PByte);
var
  W: array[0..79] of QWord;
  a, b, c, d, e, f, g, h, t1, t2: QWord;
  i: Integer;
begin
  for i := 0 to 15 do
    W[i] := (QWord(P[i * 8]) shl 56) or (QWord(P[i * 8 + 1]) shl 48) or
            (QWord(P[i * 8 + 2]) shl 40) or (QWord(P[i * 8 + 3]) shl 32) or
            (QWord(P[i * 8 + 4]) shl 24) or (QWord(P[i * 8 + 5]) shl 16) or
            (QWord(P[i * 8 + 6]) shl 8) or QWord(P[i * 8 + 7]);
  for i := 16 to 79 do
    W[i] := (ROTR64(W[i - 2], 19) xor ROTR64(W[i - 2], 61) xor (W[i - 2] shr 6)) +
            W[i - 7] +
            (ROTR64(W[i - 15], 1) xor ROTR64(W[i - 15], 8) xor (W[i - 15] shr 7)) +
            W[i - 16];
  a := Ctx.H[0]; b := Ctx.H[1]; c := Ctx.H[2]; d := Ctx.H[3];
  e := Ctx.H[4]; f := Ctx.H[5]; g := Ctx.H[6]; h := Ctx.H[7];
  for i := 0 to 79 do
  begin
    t1 := h + (ROTR64(e, 14) xor ROTR64(e, 18) xor ROTR64(e, 41)) +
          ((e and f) xor ((not e) and g)) + K512[i] + W[i];
    t2 := (ROTR64(a, 28) xor ROTR64(a, 34) xor ROTR64(a, 39)) +
          ((a and b) xor (a and c) xor (b and c));
    h := g; g := f; f := e; e := d + t1;
    d := c; c := b; b := a; a := t1 + t2;
  end;
  Inc(Ctx.H[0], a); Inc(Ctx.H[1], b); Inc(Ctx.H[2], c); Inc(Ctx.H[3], d);
  Inc(Ctx.H[4], e); Inc(Ctx.H[5], f); Inc(Ctx.H[6], g); Inc(Ctx.H[7], h);
end;

procedure SHA512Init(out C: TSHA512Ctx; A384: Boolean);
var
  i: Integer;
begin
  if A384 then
  begin
    for i := 0 to 7 do C.H[i] := IV384[i];
    C.OutBytes := 48;
  end
  else
  begin
    for i := 0 to 7 do C.H[i] := IV512[i];
    C.OutBytes := 64;
  end;
  C.Len := 0;
  C.Total := 0;
end;

procedure SHA512Update(var C: TSHA512Ctx; const ABuf; ALen: PtrUInt);
var
  p: PByte;
  take: PtrUInt;
begin
  p := @ABuf;
  Inc(C.Total, ALen);
  while ALen > 0 do
  begin
    if (C.Len = 0) and (ALen >= 128) then
    begin
      SHA512Block(C, p);
      Inc(p, 128);
      Dec(ALen, 128);
    end
    else
    begin
      take := 128 - C.Len;
      if take > ALen then take := ALen;
      Move(p^, C.Buf[C.Len], take);
      Inc(C.Len, take);
      Inc(p, take);
      Dec(ALen, take);
      if C.Len = 128 then
      begin
        SHA512Block(C, @C.Buf[0]);
        C.Len := 0;
      end;
    end;
  end;
end;

procedure SHA512Final(var C: TSHA512Ctx; out ADigest);
var
  bits: QWord;
  pad: Integer;
  lenbuf: array[0..15] of Byte;
  i: Integer;
  one: Byte;
  o: PByte;
begin
  bits := C.Total * 8;
  for i := 0 to 15 do lenbuf[i] := 0;
  for i := 0 to 7 do
    lenbuf[15 - i] := Byte(bits shr (i * 8));
  one := $80;
  SHA512Update(C, one, 1);
  if C.Len <= 112 then pad := 112 - C.Len else pad := 240 - C.Len;
  while pad > 0 do
  begin
    one := 0;
    SHA512Update(C, one, 1);
    Dec(pad);
  end;
  SHA512Update(C, lenbuf[0], 16);
  o := @ADigest;
  for i := 0 to (C.OutBytes div 8) - 1 do
  begin
    o[i * 8]     := Byte(C.H[i] shr 56);
    o[i * 8 + 1] := Byte(C.H[i] shr 48);
    o[i * 8 + 2] := Byte(C.H[i] shr 40);
    o[i * 8 + 3] := Byte(C.H[i] shr 32);
    o[i * 8 + 4] := Byte(C.H[i] shr 24);
    o[i * 8 + 5] := Byte(C.H[i] shr 16);
    o[i * 8 + 6] := Byte(C.H[i] shr 8);
    o[i * 8 + 7] := Byte(C.H[i]);
  end;
end;

function SHA256HexInner(const S: RawByteString; A224: Boolean): string;
var
  c: TSHA256Ctx;
  d: array[0..31] of Byte;
begin
  SHA256Init(c, A224);
  if Length(S) > 0 then SHA256Update(c, S[1], Length(S));
  SHA256Final(c, d[0]);
  Result := BytesToHex(d[0], c.OutBytes);
end;

function SHA512HexInner(const S: RawByteString; A384: Boolean): string;
var
  c: TSHA512Ctx;
  d: array[0..63] of Byte;
begin
  SHA512Init(c, A384);
  if Length(S) > 0 then SHA512Update(c, S[1], Length(S));
  SHA512Final(c, d[0]);
  Result := BytesToHex(d[0], c.OutBytes);
end;

function SHA224Hex(const S: RawByteString): string;
begin
  Result := SHA256HexInner(S, True);
end;

function SHA256Hex(const S: RawByteString): string;
begin
  Result := SHA256HexInner(S, False);
end;

function SHA384Hex(const S: RawByteString): string;
begin
  Result := SHA512HexInner(S, True);
end;

function SHA512Hex(const S: RawByteString): string;
begin
  Result := SHA512HexInner(S, False);
end;

function SHA256FileHex(const AFile: string; A224: Boolean): string;
var
  fs: TFileStream;
  c: TSHA256Ctx;
  d: array[0..31] of Byte;
  buf: array[0..65535] of Byte;
  n: LongInt;
begin
  SHA256Init(c, A224);
  fs := TFileStream.Create(AFile, fmOpenRead or fmShareDenyNone);
  try
    repeat
      n := fs.Read(buf[0], SizeOf(buf));
      if n > 0 then SHA256Update(c, buf[0], n);
    until n <= 0;
  finally
    fs.Free;
  end;
  SHA256Final(c, d[0]);
  Result := BytesToHex(d[0], c.OutBytes);
end;

function SHA512FileHex(const AFile: string; A384: Boolean): string;
var
  fs: TFileStream;
  c: TSHA512Ctx;
  d: array[0..63] of Byte;
  buf: array[0..65535] of Byte;
  n: LongInt;
begin
  SHA512Init(c, A384);
  fs := TFileStream.Create(AFile, fmOpenRead or fmShareDenyNone);
  try
    repeat
      n := fs.Read(buf[0], SizeOf(buf));
      if n > 0 then SHA512Update(c, buf[0], n);
    until n <= 0;
  finally
    fs.Free;
  end;
  SHA512Final(c, d[0]);
  Result := BytesToHex(d[0], c.OutBytes);
end;

end.
