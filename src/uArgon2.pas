unit uArgon2;

{$mode objfpc}{$H+}
{$Q-}{$R-}

// Argon2id (RFC 9106) en Pascal pur, avec BLAKE2b (RFC 7693). Fils de calcul
// simules en sequentiel : le resultat est identique, seule la duree change.
// Sortie au format PHC, celui de libargon2 et de libsodium :
//   $argon2id$v=19$m=4096,t=3,p=1$<sel b64 sans =>$<hash b64 sans =>

interface

// AMemKiB = memoire en KiB (m), ATime = passes (t), APar = fils (p)
function Argon2idRaw(const APassword, ASalt: RawByteString;
  ATime, AMemKiB, APar, AHashLen: Integer): RawByteString;
// avec cle secrete (K) et donnees associees (X) : vecteurs de la RFC
function Argon2idRawEx(const APassword, ASalt, ASecret, AData: RawByteString;
  ATime, AMemKiB, APar, AHashLen: Integer): RawByteString;
function Argon2idPhc(const APassword, ASalt: RawByteString;
  ATime, AMemKiB, APar, AHashLen: Integer): string;
// BLAKE2b non cle, sortie de AOutLen octets (1..64)
function Blake2b(const AData: RawByteString; AOutLen: Integer): RawByteString;

implementation

uses
  SysUtils;

type
  TBlock = array[0..127] of QWord;   // 1 KiB
  PBlock = ^TBlock;

const
  B2_IV: array[0..7] of QWord = (
    QWord($6A09E667F3BCC908), QWord($BB67AE8584CAA73B),
    QWord($3C6EF372FE94F82B), QWord($A54FF53A5F1D36F1),
    QWord($510E527FADE682D1), QWord($9B05688C2B3E6C1F),
    QWord($1F83D9ABFB41BD6B), QWord($5BE0CD19137E2179));
  B2_SIGMA: array[0..11, 0..15] of Byte = (
    (0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15),
    (14, 10, 4, 8, 9, 15, 13, 6, 1, 12, 0, 2, 11, 7, 5, 3),
    (11, 8, 12, 0, 5, 2, 15, 13, 10, 14, 3, 6, 7, 1, 9, 4),
    (7, 9, 3, 1, 13, 12, 11, 14, 2, 6, 5, 10, 4, 0, 15, 8),
    (9, 0, 5, 7, 2, 4, 10, 15, 14, 1, 11, 12, 6, 8, 3, 13),
    (2, 12, 6, 10, 0, 11, 8, 3, 4, 13, 7, 5, 15, 14, 1, 9),
    (12, 5, 1, 15, 14, 13, 4, 10, 0, 7, 6, 3, 9, 2, 8, 11),
    (13, 11, 7, 14, 12, 1, 3, 9, 5, 0, 15, 4, 8, 6, 2, 10),
    (6, 15, 14, 9, 11, 3, 0, 8, 12, 2, 13, 7, 1, 4, 10, 5),
    (10, 2, 8, 4, 7, 6, 1, 5, 15, 11, 9, 14, 3, 12, 13, 0),
    (0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15),
    (14, 10, 4, 8, 9, 15, 13, 6, 1, 12, 0, 2, 11, 7, 5, 3));

function RotR64(X: QWord; N: Integer): QWord; inline;
begin
  Result := (X shr N) or (X shl (64 - N));
end;

// ---------- BLAKE2b

type
  TB2State = record
    H: array[0..7] of QWord;
    T: array[0..1] of QWord;
    Buf: array[0..127] of Byte;
    BufLen: Integer;
    OutLen: Integer;
  end;

procedure B2Compress(var S: TB2State; const ABlock; ALast: Boolean);
var
  m: array[0..15] of QWord;
  v: array[0..15] of QWord;
  i, r: Integer;

  procedure G(a, b, c, d: Integer; x, y: QWord); inline;
  begin
    v[a] := v[a] + v[b] + x;
    v[d] := RotR64(v[d] xor v[a], 32);
    v[c] := v[c] + v[d];
    v[b] := RotR64(v[b] xor v[c], 24);
    v[a] := v[a] + v[b] + y;
    v[d] := RotR64(v[d] xor v[a], 16);
    v[c] := v[c] + v[d];
    v[b] := RotR64(v[b] xor v[c], 63);
  end;

begin
  Move(ABlock, m, 128); // little-endian natif
  for i := 0 to 7 do v[i] := S.H[i];
  for i := 0 to 7 do v[8 + i] := B2_IV[i];
  v[12] := v[12] xor S.T[0];
  v[13] := v[13] xor S.T[1];
  if ALast then v[14] := not v[14];
  for r := 0 to 11 do
  begin
    G(0, 4, 8, 12, m[B2_SIGMA[r, 0]], m[B2_SIGMA[r, 1]]);
    G(1, 5, 9, 13, m[B2_SIGMA[r, 2]], m[B2_SIGMA[r, 3]]);
    G(2, 6, 10, 14, m[B2_SIGMA[r, 4]], m[B2_SIGMA[r, 5]]);
    G(3, 7, 11, 15, m[B2_SIGMA[r, 6]], m[B2_SIGMA[r, 7]]);
    G(0, 5, 10, 15, m[B2_SIGMA[r, 8]], m[B2_SIGMA[r, 9]]);
    G(1, 6, 11, 12, m[B2_SIGMA[r, 10]], m[B2_SIGMA[r, 11]]);
    G(2, 7, 8, 13, m[B2_SIGMA[r, 12]], m[B2_SIGMA[r, 13]]);
    G(3, 4, 9, 14, m[B2_SIGMA[r, 14]], m[B2_SIGMA[r, 15]]);
  end;
  for i := 0 to 7 do S.H[i] := S.H[i] xor v[i] xor v[i + 8];
end;

procedure B2Init(out S: TB2State; AOutLen: Integer);
var
  i: Integer;
begin
  FillChar(S, SizeOf(S), 0);
  for i := 0 to 7 do S.H[i] := B2_IV[i];
  // parametres : digest_length, key_length=0, fanout=1, depth=1
  S.H[0] := S.H[0] xor QWord($01010000) xor QWord(AOutLen);
  S.OutLen := AOutLen;
end;

procedure B2Update(var S: TB2State; const AData; ALen: Integer);
var
  p: PByte;
  n: Integer;
begin
  p := @AData;
  while ALen > 0 do
  begin
    if S.BufLen = 128 then
    begin
      Inc(S.T[0], 128);
      if S.T[0] < 128 then Inc(S.T[1]);
      B2Compress(S, S.Buf, False);
      S.BufLen := 0;
    end;
    n := 128 - S.BufLen;
    if n > ALen then n := ALen;
    Move(p^, S.Buf[S.BufLen], n);
    Inc(S.BufLen, n);
    Inc(p, n);
    Dec(ALen, n);
  end;
end;

procedure B2Final(var S: TB2State; out AOut);
var
  full: array[0..63] of Byte;
  i: Integer;
begin
  Inc(S.T[0], S.BufLen);
  if S.T[0] < QWord(S.BufLen) then Inc(S.T[1]);
  FillChar(S.Buf[S.BufLen], 128 - S.BufLen, 0);
  B2Compress(S, S.Buf, True);
  for i := 0 to 7 do Move(S.H[i], full[i * 8], 8);
  Move(full, AOut, S.OutLen);
  FillChar(S, SizeOf(S), 0);
end;

function Blake2b(const AData: RawByteString; AOutLen: Integer): RawByteString;
var
  s: TB2State;
begin
  if (AOutLen < 1) or (AOutLen > 64) then
    raise Exception.Create('Blake2b: bad output length');
  B2Init(s, AOutLen);
  if AData <> '' then B2Update(s, AData[1], Length(AData));
  SetLength(Result, AOutLen);
  B2Final(s, Result[1]);
end;

// H' de la RFC 9106 : sortie de longueur arbitraire par chainage de BLAKE2b
function B2Long(const AData: RawByteString; AOutLen: Integer): RawByteString;
var
  s: TB2State;
  len32: LongWord;
  v, prev: RawByteString;
  pos, r: Integer;
begin
  len32 := AOutLen;
  if AOutLen <= 64 then
  begin
    B2Init(s, AOutLen);
    B2Update(s, len32, 4);
    if AData <> '' then B2Update(s, AData[1], Length(AData));
    SetLength(Result, AOutLen);
    B2Final(s, Result[1]);
    Exit;
  end;
  SetLength(Result, AOutLen);
  B2Init(s, 64);
  B2Update(s, len32, 4);
  if AData <> '' then B2Update(s, AData[1], Length(AData));
  SetLength(v, 64);
  B2Final(s, v[1]);
  Move(v[1], Result[1], 32);
  pos := 32;
  r := AOutLen - 32;
  while r > 64 do
  begin
    prev := v;
    v := Blake2b(prev, 64);
    Move(v[1], Result[pos + 1], 32);
    Inc(pos, 32);
    Dec(r, 32);
  end;
  prev := v;
  v := Blake2b(prev, r);
  Move(v[1], Result[pos + 1], r);
end;

// ---------- Argon2

procedure BlockXor(var D: TBlock; const S: TBlock); inline;
var
  i: Integer;
begin
  for i := 0 to 127 do D[i] := D[i] xor S[i];
end;

// G de BLAKE2b modifie : multiplication 32x32 en plus (RFC 9106 3.6)
procedure GB(var a, b, c, d: QWord); inline;
begin
  a := a + b + 2 * (a and $FFFFFFFF) * (b and $FFFFFFFF);
  d := RotR64(d xor a, 32);
  c := c + d + 2 * (c and $FFFFFFFF) * (d and $FFFFFFFF);
  b := RotR64(b xor c, 24);
  a := a + b + 2 * (a and $FFFFFFFF) * (b and $FFFFFFFF);
  d := RotR64(d xor a, 16);
  c := c + d + 2 * (c and $FFFFFFFF) * (d and $FFFFFFFF);
  b := RotR64(b xor c, 63);
end;

procedure P(var v0, v1, v2, v3, v4, v5, v6, v7, v8, v9, v10, v11, v12, v13,
  v14, v15: QWord); inline;
begin
  GB(v0, v4, v8, v12);
  GB(v1, v5, v9, v13);
  GB(v2, v6, v10, v14);
  GB(v3, v7, v11, v15);
  GB(v0, v5, v10, v15);
  GB(v1, v6, v11, v12);
  GB(v2, v7, v8, v13);
  GB(v3, v4, v9, v14);
end;

// fonction de compression G(X, Y) : R = X xor Y, P sur lignes puis colonnes
procedure Compress(const X, Y: TBlock; var AOut: TBlock; AXorOut: Boolean);
var
  r, z: TBlock;
  i, j: Integer;
begin
  for i := 0 to 127 do r[i] := X[i] xor Y[i];
  z := r;
  for i := 0 to 7 do // lignes de 16 mots
  begin
    j := i * 16;
    P(z[j], z[j + 1], z[j + 2], z[j + 3], z[j + 4], z[j + 5], z[j + 6], z[j + 7],
      z[j + 8], z[j + 9], z[j + 10], z[j + 11], z[j + 12], z[j + 13], z[j + 14], z[j + 15]);
  end;
  for i := 0 to 7 do // colonnes : mots 2i, 2i+1, 2i+16, 2i+17, ...
  begin
    j := i * 2;
    P(z[j], z[j + 1], z[j + 16], z[j + 17], z[j + 32], z[j + 33], z[j + 48], z[j + 49],
      z[j + 64], z[j + 65], z[j + 80], z[j + 81], z[j + 96], z[j + 97], z[j + 112], z[j + 113]);
  end;
  if AXorOut then
    for i := 0 to 127 do AOut[i] := AOut[i] xor r[i] xor z[i]
  else
    for i := 0 to 127 do AOut[i] := r[i] xor z[i];
end;

function Argon2idRaw(const APassword, ASalt: RawByteString;
  ATime, AMemKiB, APar, AHashLen: Integer): RawByteString;
begin
  Result := Argon2idRawEx(APassword, ASalt, '', '', ATime, AMemKiB, APar, AHashLen);
end;

function Argon2idRawEx(const APassword, ASalt, ASecret, AData: RawByteString;
  ATime, AMemKiB, APar, AHashLen: Integer): RawByteString;
const
  ARGON2_ID = 2;
  VERSION = $13;
  SYNC_POINTS = 4;
var
  mem: array of TBlock;
  mPrime, q, segLen, lanes: Integer;
  h0: RawByteString;
  s: TB2State;
  buf: RawByteString;
  pass, slice, lane, idx, i, j, refLane, refIdx, startIdx: Integer;
  pseudo: QWord;
  j1, j2: LongWord;
  refAreaSize, relPos, prevIdx, curIdx: Int64;
  addrBlock, inputBlock, zeroBlock: TBlock;
  dataIndep: Boolean;
  fin: TBlock;
  le32: LongWord;

  procedure Put32(var St: TB2State; V: LongWord);
  begin
    le32 := V;
    B2Update(St, le32, 4);
  end;

  procedure NextAddresses;
  begin
    Inc(inputBlock[6]);
    Compress(zeroBlock, inputBlock, addrBlock, False);
    Compress(zeroBlock, addrBlock, addrBlock, False);
  end;

begin
  if (APar < 1) or (ATime < 1) or (AHashLen < 4) or (AMemKiB < 8 * APar) then
    raise Exception.Create('Argon2: bad parameters');
  lanes := APar;
  // m' = 4p * floor(m / 4p)
  mPrime := (AMemKiB div (SYNC_POINTS * lanes)) * (SYNC_POINTS * lanes);
  q := mPrime div lanes;
  segLen := q div SYNC_POINTS;
  SetLength(mem, mPrime);

  // H0 = H(p, T, m, t, v, y, |P|, P, |S|, S, |K|, K, |X|, X)
  B2Init(s, 64);
  Put32(s, lanes); Put32(s, AHashLen); Put32(s, AMemKiB); Put32(s, ATime);
  Put32(s, VERSION); Put32(s, ARGON2_ID);
  Put32(s, Length(APassword));
  if APassword <> '' then B2Update(s, APassword[1], Length(APassword));
  Put32(s, Length(ASalt));
  if ASalt <> '' then B2Update(s, ASalt[1], Length(ASalt));
  Put32(s, Length(ASecret));
  if ASecret <> '' then B2Update(s, ASecret[1], Length(ASecret));
  Put32(s, Length(AData));
  if AData <> '' then B2Update(s, AData[1], Length(AData));
  SetLength(h0, 64);
  B2Final(s, h0[1]);

  // B[i][0] = H'(H0 || 0 || i), B[i][1] = H'(H0 || 1 || i)
  for lane := 0 to lanes - 1 do
    for j := 0 to 1 do
    begin
      buf := h0;
      SetLength(buf, 72);
      le32 := j; Move(le32, buf[65], 4);
      le32 := lane; Move(le32, buf[69], 4);
      buf := B2Long(buf, 1024);
      Move(buf[1], mem[lane * q + j], 1024);
    end;

  FillChar(zeroBlock, SizeOf(zeroBlock), 0);
  for pass := 0 to ATime - 1 do
    for slice := 0 to SYNC_POINTS - 1 do
      for lane := 0 to lanes - 1 do
      begin
        // argon2id : independant des donnees sur la premiere moitie du 1er passage
        dataIndep := (pass = 0) and (slice < SYNC_POINTS div 2);
        if dataIndep then
        begin
          FillChar(inputBlock, SizeOf(inputBlock), 0);
          inputBlock[0] := pass; inputBlock[1] := lane; inputBlock[2] := slice;
          inputBlock[3] := mPrime; inputBlock[4] := ATime; inputBlock[5] := ARGON2_ID;
          inputBlock[6] := 0;
        end;
        if (pass = 0) and (slice = 0) then startIdx := 2 else startIdx := 0;
        curIdx := lane * q + slice * segLen + startIdx;
        if (curIdx mod q) = 0 then prevIdx := curIdx + q - 1 else prevIdx := curIdx - 1;
        for idx := startIdx to segLen - 1 do
        begin
          if (curIdx mod q) = 0 then prevIdx := curIdx + q - 1 else prevIdx := curIdx - 1;
          if dataIndep then
          begin
            // bloc d'adresses au debut du segment (qui commence a 2 sur le
            // tout premier) puis tous les 128 blocs
            if ((idx mod 128) = 0) or (idx = startIdx) then NextAddresses;
            pseudo := addrBlock[idx mod 128];
          end
          else
            pseudo := mem[prevIdx][0];
          j1 := LongWord(pseudo and $FFFFFFFF);
          j2 := LongWord(pseudo shr 32);
          if (pass = 0) and (slice = 0) then refLane := lane
          else refLane := Integer(j2 mod LongWord(lanes));
          // taille de la zone de reference (RFC 9106 3.4.1.2)
          if pass = 0 then
          begin
            if slice = 0 then refAreaSize := idx - 1
            else if refLane = lane then refAreaSize := slice * segLen + idx - 1
            else if idx = 0 then refAreaSize := slice * segLen - 1
            else refAreaSize := slice * segLen;
          end
          else
          begin
            if refLane = lane then refAreaSize := q - segLen + idx - 1
            else if idx = 0 then refAreaSize := q - segLen - 1
            else refAreaSize := q - segLen;
          end;
          // x = j1^2 / 2^32 ; y = area*x / 2^32 ; zz = area - 1 - y
          relPos := (QWord(j1) * QWord(j1)) shr 32;
          relPos := (refAreaSize * relPos) shr 32;
          relPos := refAreaSize - 1 - relPos;
          if pass = 0 then i := 0
          else i := ((slice + 1) mod SYNC_POINTS) * segLen;
          refIdx := Integer((i + relPos) mod q);
          Compress(mem[prevIdx], mem[refLane * q + refIdx], mem[curIdx], pass > 0);
          Inc(curIdx);
        end;
      end;

  // C = xor des derniers blocs de chaque piste, tag = H'(C)
  fin := mem[q - 1];
  for lane := 1 to lanes - 1 do BlockXor(fin, mem[lane * q + q - 1]);
  SetLength(buf, 1024);
  Move(fin, buf[1], 1024);
  Result := B2Long(buf, AHashLen);
  // memoire de travail effacee : elle derive du mot de passe
  for i := 0 to High(mem) do FillChar(mem[i], SizeOf(TBlock), 0);
  FillChar(fin, SizeOf(fin), 0);
  FillChar(h0[1], Length(h0), 0);
  FillChar(buf[1], Length(buf), 0);
end;

// base64 standard sans '=' (PHC)
function B64NoPad(const S: RawByteString): string;
const
  T = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
var
  i, n: Integer;
  a, b, c: Byte;
begin
  Result := '';
  i := 1;
  n := Length(S);
  while i <= n do
  begin
    a := Ord(S[i]);
    if i + 1 <= n then b := Ord(S[i + 1]) else b := 0;
    if i + 2 <= n then c := Ord(S[i + 2]) else c := 0;
    Result := Result + T[(a shr 2) + 1] + T[((a and 3) shl 4 or (b shr 4)) + 1];
    if i + 1 <= n then Result := Result + T[((b and 15) shl 2 or (c shr 6)) + 1];
    if i + 2 <= n then Result := Result + T[(c and 63) + 1];
    Inc(i, 3);
  end;
end;

function Argon2idPhc(const APassword, ASalt: RawByteString;
  ATime, AMemKiB, APar, AHashLen: Integer): string;
begin
  Result := Format('$argon2id$v=19$m=%d,t=%d,p=%d$%s$%s',
    [AMemKiB, ATime, APar, B64NoPad(ASalt),
     B64NoPad(Argon2idRaw(APassword, ASalt, ATime, AMemKiB, APar, AHashLen))]);
end;

end.
