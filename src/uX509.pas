unit uX509;

{$mode objfpc}{$H+}

// Parseur DER/ASN.1 X.509. Lecture SEULE : la signature n'est JAMAIS verifiee.
// Entree hostile : longueurs bornees au buffer avant usage, plafonds X509_MAX_*,
// parcours iteratif, parse casse = EX509Error.

interface

uses
  Classes, SysUtils;

const
  X509_MAX_DER   = 256 * 1024; // un cert reel fait 1-8 Ko
  X509_MAX_CERTS = 16;         // chaine PEM

function X509ReportFromText(const AText: string; ANowUtc: TDateTime;
  out AErr: string): string;

function X509ReportFromFile(const AFile: string; ANowUtc: TDateTime;
  out AErr: string): string;

implementation

uses
  StrUtils, DateUtils, sha1, uSha2, uOps;

type
  EX509Error = class(Exception);

  TTlv = record
    Cls: Byte;           // 0 universal, 1 application, 2 context, 3 private
    Constructed: Boolean;
    Tag: Integer;
    ValOfs: Integer;
    ValLen: Integer;
    EndOfs: Integer;
  end;

  TCertInfo = record
    Version: Integer;
    SerialHex: string;
    SigAlg: string;
    Issuer, Subject: string;
    NotBefore, NotAfter: TDateTime; // UTC
    PubKey: string;
    HasBC, IsCA: Boolean;
    PathLen: Integer;               // -1 = absent
    KeyUsage, ExtKeyUsage, San, Ski, Aki: string;
    Sha256Fp, Sha1Fp: string;
  end;

function ReadTlv(const B: TBytes; AOfs, ALimit: Integer): TTlv;
var
  p, n, i, len: Integer;
  id: Byte;
begin
  p := AOfs;
  if (p < 0) or (p + 2 > ALimit) then
    raise EX509Error.Create('truncated DER (header)');
  id := B[p];
  Result.Cls := id shr 6;
  Result.Constructed := (id and $20) <> 0;
  Result.Tag := id and $1F;
  if Result.Tag = $1F then
    raise EX509Error.Create('high-tag-number form not supported');
  Inc(p);
  if B[p] < $80 then
  begin
    len := B[p];
    Inc(p);
  end
  else
  begin
    n := B[p] and $7F;
    if n = 0 then
      raise EX509Error.Create('indefinite length (not DER)');
    if n > 4 then
      raise EX509Error.Create('length too large');
    Inc(p);
    if p + n > ALimit then
      raise EX509Error.Create('truncated DER (length)');
    len := 0;
    for i := 1 to n do
    begin
      if len > (MaxInt shr 8) then
        raise EX509Error.Create('length overflow');
      len := (len shl 8) or B[p];
      Inc(p);
    end;
  end;
  // borne par SOUSTRACTION : "p + len" deborde en silence sous {$Q-}
  if (len < 0) or (len > ALimit - p) then
    raise EX509Error.Create('value exceeds buffer');
  Result.ValOfs := p;
  Result.ValLen := len;
  Result.EndOfs := p + len;
end;

function Expect(const B: TBytes; AOfs, ALimit, ATag: Integer;
  const AWhat: string): TTlv;
begin
  Result := ReadTlv(B, AOfs, ALimit);
  if (Result.Cls <> 0) or (Result.Tag <> ATag) then
    raise EX509Error.Create('expected ' + AWhat);
end;

function HexColon(const B: TBytes; AOfs, ALen: Integer): string;
const
  H = '0123456789ABCDEF';
var
  i: Integer;
begin
  Result := '';
  for i := 0 to ALen - 1 do
  begin
    if i > 0 then Result := Result + ':';
    Result := Result + H[(B[AOfs + i] shr 4) + 1] + H[(B[AOfs + i] and $F) + 1];
  end;
end;

function CleanStr(const S: string): string;
var
  i: Integer;
begin
  Result := S;
  for i := 1 to Length(Result) do
    if Result[i] < ' ' then Result[i] := ' ';
  if Length(Result) > 512 then
    Result := Copy(Result, 1, 512) + '...';
end;

// Le 1er sous-identifiant (40*X + Y) est encode en base-128 comme les autres :
// le lire sur UN octet (div/mod 40) casse des que 40*X+Y >= 128.
function OidToStr(const B: TBytes; AOfs, ALen: Integer): string;
var
  i: Integer;
  v: QWord; // 35 bits: deborderait un Cardinal sous {$Q-}
  nb: Integer;
  first: Boolean;
begin
  Result := '';
  if ALen <= 0 then Exit('?');
  v := 0;
  nb := 0;
  first := True;
  for i := 0 to ALen - 1 do
  begin
    if nb >= 5 then raise EX509Error.Create('OID arc too large');
    v := (v shl 7) or (B[AOfs + i] and $7F);
    Inc(nb);
    if (B[AOfs + i] and $80) = 0 then
    begin
      if first then
      begin
        if v < 40 then
          Result := '0.' + IntToStr(v)
        else if v < 80 then
          Result := '1.' + IntToStr(v - 40)
        else
          Result := '2.' + IntToStr(v - 80);
        first := False;
      end
      else
        Result := Result + '.' + IntToStr(v);
      v := 0;
      nb := 0;
    end;
  end;
  if Result = '' then Result := '?';
end;

function OidName(const AOid: string): string;
begin
  if AOid = '1.2.840.113549.1.1.11' then Exit('sha256WithRSAEncryption');
  if AOid = '1.2.840.113549.1.1.12' then Exit('sha384WithRSAEncryption');
  if AOid = '1.2.840.113549.1.1.13' then Exit('sha512WithRSAEncryption');
  if AOid = '1.2.840.113549.1.1.5'  then Exit('sha1WithRSAEncryption (weak)');
  if AOid = '1.2.840.113549.1.1.4'  then Exit('md5WithRSAEncryption (broken)');
  if AOid = '1.2.840.113549.1.1.10' then Exit('rsassa-pss');
  if AOid = '1.2.840.10045.4.3.2'   then Exit('ecdsa-with-SHA256');
  if AOid = '1.2.840.10045.4.3.3'   then Exit('ecdsa-with-SHA384');
  if AOid = '1.2.840.10045.4.3.4'   then Exit('ecdsa-with-SHA512');
  if AOid = '1.2.840.10045.4.1'     then Exit('ecdsa-with-SHA1 (weak)');
  if AOid = '1.3.101.112'           then Exit('Ed25519');
  if AOid = '1.3.101.113'           then Exit('Ed448');
  if AOid = '1.2.840.113549.1.1.1'  then Exit('RSA');
  if AOid = '1.2.840.10045.2.1'     then Exit('EC');
  if AOid = '1.2.840.10045.3.1.7'   then Exit('P-256');
  if AOid = '1.3.132.0.34'          then Exit('P-384');
  if AOid = '1.3.132.0.35'          then Exit('P-521');
  if AOid = '1.3.132.0.10'          then Exit('secp256k1');
  if AOid = '1.3.6.1.5.5.7.3.1'     then Exit('serverAuth');
  if AOid = '1.3.6.1.5.5.7.3.2'     then Exit('clientAuth');
  if AOid = '1.3.6.1.5.5.7.3.3'     then Exit('codeSigning');
  if AOid = '1.3.6.1.5.5.7.3.4'     then Exit('emailProtection');
  if AOid = '1.3.6.1.5.5.7.3.8'     then Exit('timeStamping');
  if AOid = '1.3.6.1.5.5.7.3.9'     then Exit('OCSPSigning');
  Result := AOid;
end;

function DnAttrName(const AOid: string): string;
begin
  if AOid = '2.5.4.3'  then Exit('CN');
  if AOid = '2.5.4.6'  then Exit('C');
  if AOid = '2.5.4.7'  then Exit('L');
  if AOid = '2.5.4.8'  then Exit('ST');
  if AOid = '2.5.4.10' then Exit('O');
  if AOid = '2.5.4.11' then Exit('OU');
  if AOid = '2.5.4.5'  then Exit('serialNumber');
  if AOid = '2.5.4.97' then Exit('organizationIdentifier');
  if AOid = '1.2.840.113549.1.9.1' then Exit('emailAddress');
  if AOid = '0.9.2342.19200300.100.1.25' then Exit('DC');
  Result := AOid;
end;

function Asn1StrValue(const B: TBytes; const T: TTlv): string;
var
  i: Integer;
  w: UnicodeString;
begin
  case T.Tag of
    30: // BMPString UTF-16BE
      begin
        w := '';
        i := T.ValOfs;
        while i + 1 < T.EndOfs do
        begin
          w := w + WideChar((B[i] shl 8) or B[i + 1]);
          Inc(i, 2);
        end;
        Result := UTF8Encode(w);
      end;
    20: // T61String : approx Latin-1
      begin
        w := '';
        for i := T.ValOfs to T.EndOfs - 1 do
          w := w + WideChar(B[i]);
        Result := UTF8Encode(w);
      end;
  else
    // PrintableString(19) / UTF8String(12) / IA5String(22) : brut
    SetLength(Result, T.ValLen);
    if T.ValLen > 0 then
      Move(B[T.ValOfs], Result[1], T.ValLen);
  end;
  Result := CleanStr(Result);
end;

// Name = SEQ of RDN (SET of SEQ{OID, value})
function ParseDn(const B: TBytes; const TName: TTlv): string;
var
  p, q: Integer;
  rdn, atv, oid, val: TTlv;
  n: Integer;
begin
  Result := '';
  p := TName.ValOfs;
  n := 0;
  while p < TName.EndOfs do
  begin
    Inc(n);
    if n > 64 then raise EX509Error.Create('DN too long');
    rdn := ReadTlv(B, p, TName.EndOfs); // SET
    q := rdn.ValOfs;
    while q < rdn.EndOfs do
    begin
      atv := ReadTlv(B, q, rdn.EndOfs); // SEQ { OID, ANY }
      oid := Expect(B, atv.ValOfs, atv.EndOfs, 6, 'OID in DN');
      val := ReadTlv(B, oid.EndOfs, atv.EndOfs);
      if Result <> '' then Result := Result + ', ';
      Result := Result + DnAttrName(OidToStr(B, oid.ValOfs, oid.ValLen)) +
        '=' + Asn1StrValue(B, val);
      q := atv.EndOfs;
    end;
    p := rdn.EndOfs;
  end;
  if Result = '' then Result := '(empty)';
end;

// UTCTime YYMMDDHHMMSSZ / GeneralizedTime YYYYMMDDHHMMSSZ
function ParseAsn1Time(const B: TBytes; const T: TTlv): TDateTime;
var
  s: string;
  y, mo, d, h, mi, se: Integer;

  function D2(i: Integer): Integer;
  begin
    if (i + 1 > Length(s)) or not (s[i] in ['0'..'9']) or
       not (s[i + 1] in ['0'..'9']) then
      raise EX509Error.Create('bad time');
    Result := (Ord(s[i]) - 48) * 10 + Ord(s[i + 1]) - 48;
  end;

begin
  SetLength(s, T.ValLen);
  if T.ValLen > 0 then Move(B[T.ValOfs], s[1], T.ValLen);
  if T.Tag = 23 then // YY < 50 = 20xx sinon 19xx (RFC 5280)
  begin
    y := D2(1);
    if y < 50 then y := 2000 + y else y := 1900 + y;
    mo := D2(3); d := D2(5); h := D2(7); mi := D2(9);
    if (Length(s) >= 12) and (s[11] in ['0'..'9']) then se := D2(11) else se := 0;
  end
  else if T.Tag = 24 then // GeneralizedTime
  begin
    y := D2(1) * 100 + D2(3);
    mo := D2(5); d := D2(7); h := D2(9); mi := D2(11);
    if (Length(s) >= 14) and (s[13] in ['0'..'9']) then se := D2(13) else se := 0;
  end
  else
    raise EX509Error.Create('unexpected time type');
  if not TryEncodeDateTime(y, mo, d, h, mi, se, 0, Result) then
    raise EX509Error.Create('invalid date in certificate');
end;

procedure ParseSan(const B: TBytes; const TVal: TTlv; var AInfo: TCertInfo);
var
  seq, gn: TTlv;
  p, i, n: Integer;
  s, ip: string;
begin
  seq := Expect(B, TVal.ValOfs, TVal.EndOfs, 16, 'SAN sequence');
  p := seq.ValOfs;
  n := 0;
  while p < seq.EndOfs do
  begin
    Inc(n);
    if n > 256 then raise EX509Error.Create('too many SAN entries');
    gn := ReadTlv(B, p, seq.EndOfs);
    if gn.Cls = 2 then // context-specific = GeneralName
      case gn.Tag of
        2: // dNSName
          begin
            SetLength(s, gn.ValLen);
            if gn.ValLen > 0 then Move(B[gn.ValOfs], s[1], gn.ValLen);
            if AInfo.San <> '' then AInfo.San := AInfo.San + ', ';
            AInfo.San := AInfo.San + 'DNS:' + CleanStr(s);
          end;
        1: // rfc822Name
          begin
            SetLength(s, gn.ValLen);
            if gn.ValLen > 0 then Move(B[gn.ValOfs], s[1], gn.ValLen);
            if AInfo.San <> '' then AInfo.San := AInfo.San + ', ';
            AInfo.San := AInfo.San + 'email:' + CleanStr(s);
          end;
        6: // uniformResourceIdentifier
          begin
            SetLength(s, gn.ValLen);
            if gn.ValLen > 0 then Move(B[gn.ValOfs], s[1], gn.ValLen);
            if AInfo.San <> '' then AInfo.San := AInfo.San + ', ';
            AInfo.San := AInfo.San + 'URI:' + CleanStr(s);
          end;
        7: // iPAddress : 4 = v4, 16 = v6
          begin
            ip := '';
            if gn.ValLen = 4 then
            begin
              for i := 0 to 3 do
              begin
                if i > 0 then ip := ip + '.';
                ip := ip + IntToStr(B[gn.ValOfs + i]);
              end;
            end
            else if gn.ValLen = 16 then
            begin
              for i := 0 to 7 do
              begin
                if i > 0 then ip := ip + ':';
                ip := ip + LowerCase(IntToHex(
                  (B[gn.ValOfs + i * 2] shl 8) or B[gn.ValOfs + i * 2 + 1], 1));
              end;
            end
            else
              ip := '(bad length)';
            if AInfo.San <> '' then AInfo.San := AInfo.San + ', ';
            AInfo.San := AInfo.San + 'IP:' + ip;
          end;
      end;
    p := gn.EndOfs;
  end;
end;

procedure ParseKeyUsage(const B: TBytes; const TVal: TTlv; var AInfo: TCertInfo);
const
  NAMES: array[0..8] of string = ('digitalSignature', 'nonRepudiation',
    'keyEncipherment', 'dataEncipherment', 'keyAgreement', 'keyCertSign',
    'cRLSign', 'encipherOnly', 'decipherOnly');
var
  bits: TTlv;
  i, bitCount: Integer;
  by: Byte;
begin
  bits := Expect(B, TVal.ValOfs, TVal.EndOfs, 3, 'keyUsage bit string');
  if bits.ValLen < 2 then Exit;
  bitCount := (bits.ValLen - 1) * 8 - B[bits.ValOfs]; // 1er octet = bits inutilises (DER)
  for i := 0 to 8 do
  begin
    if i >= bitCount then Break;
    by := B[bits.ValOfs + 1 + (i div 8)];
    if (by and ($80 shr (i mod 8))) <> 0 then
    begin
      if AInfo.KeyUsage <> '' then AInfo.KeyUsage := AInfo.KeyUsage + ', ';
      AInfo.KeyUsage := AInfo.KeyUsage + NAMES[i];
    end;
  end;
end;

procedure ParseExtKeyUsage(const B: TBytes; const TVal: TTlv; var AInfo: TCertInfo);
var
  seq, o: TTlv;
  p, n: Integer;
begin
  seq := Expect(B, TVal.ValOfs, TVal.EndOfs, 16, 'EKU sequence');
  p := seq.ValOfs;
  n := 0;
  while p < seq.EndOfs do
  begin
    Inc(n);
    if n > 32 then Break;
    o := Expect(B, p, seq.EndOfs, 6, 'EKU OID');
    if AInfo.ExtKeyUsage <> '' then AInfo.ExtKeyUsage := AInfo.ExtKeyUsage + ', ';
    AInfo.ExtKeyUsage := AInfo.ExtKeyUsage + OidName(OidToStr(B, o.ValOfs, o.ValLen));
    p := o.EndOfs;
  end;
end;

procedure ParseBasicConstraints(const B: TBytes; const TVal: TTlv; var AInfo: TCertInfo);
var
  seq, t: TTlv;
  p: Integer;
begin
  AInfo.HasBC := True;
  AInfo.IsCA := False;
  AInfo.PathLen := -1;
  seq := Expect(B, TVal.ValOfs, TVal.EndOfs, 16, 'basicConstraints');
  p := seq.ValOfs;
  if p >= seq.EndOfs then Exit; // SEQUENCE {} = pas CA
  t := ReadTlv(B, p, seq.EndOfs);
  if (t.Cls = 0) and (t.Tag = 1) and (t.ValLen = 1) then // BOOLEAN cA
  begin
    AInfo.IsCA := B[t.ValOfs] <> 0;
    p := t.EndOfs;
    if p < seq.EndOfs then t := ReadTlv(B, p, seq.EndOfs) else Exit;
  end;
  if (t.Cls = 0) and (t.Tag = 2) and (t.ValLen >= 1) and (t.ValLen <= 4) then
  begin
    AInfo.PathLen := 0;
    for p := t.ValOfs to t.EndOfs - 1 do
      AInfo.PathLen := (AInfo.PathLen shl 8) or B[p];
  end;
end;

function ParseSpki(const B: TBytes; const TSpki: TTlv): string;
var
  alg, oid, params, bits, rsa, modu: TTlv;
  algOid: string;
  nbits: Integer;
begin
  alg := Expect(B, TSpki.ValOfs, TSpki.EndOfs, 16, 'SPKI algorithm');
  oid := Expect(B, alg.ValOfs, alg.EndOfs, 6, 'SPKI OID');
  algOid := OidToStr(B, oid.ValOfs, oid.ValLen);
  bits := Expect(B, alg.EndOfs, TSpki.EndOfs, 3, 'SPKI bit string');

  if algOid = '1.2.840.113549.1.1.1' then
  begin
    // BIT STRING : 1er octet = bits inutilises, puis SEQ { modulus, exponent }
    if bits.ValLen < 2 then Exit('RSA (malformed)');
    try
      rsa := Expect(B, bits.ValOfs + 1, bits.EndOfs, 16, 'RSA key');
      modu := Expect(B, rsa.ValOfs, rsa.EndOfs, 2, 'RSA modulus');
      nbits := modu.ValLen * 8;
      // INTEGER positif : l'octet 00 de tete ne compte pas
      if (modu.ValLen > 0) and (B[modu.ValOfs] = 0) then Dec(nbits, 8);
      Result := 'RSA ' + IntToStr(nbits) + ' bits';
    except
      Result := 'RSA (unreadable key)';
    end;
  end
  else if algOid = '1.2.840.10045.2.1' then // EC : courbe nommee dans params
  begin
    Result := 'EC';
    if alg.EndOfs > oid.EndOfs then
    begin
      params := ReadTlv(B, oid.EndOfs, alg.EndOfs);
      if (params.Cls = 0) and (params.Tag = 6) then
        Result := 'EC ' + OidName(OidToStr(B, params.ValOfs, params.ValLen));
    end;
  end
  else
    Result := OidName(algOid);
end;

function ParseCert(const ADer: TBytes; ANowUtc: TDateTime): TCertInfo;
var
  n: Integer;
  cert, tbs, t, sigalg, oid, ext, extSeq, extOid, extVal, boolT: TTlv;
  p: Integer;
  extId: string;
  raw: RawByteString;
  sha1d: TSHA1Digest;
  i: Integer;
begin
  // pas de FillChar : le record porte des chaines managees
  Result := Default(TCertInfo);
  Result.PathLen := -1;
  Result.Version := 1;
  n := Length(ADer);
  if n = 0 then raise EX509Error.Create('empty certificate');
  if n > X509_MAX_DER then raise EX509Error.Create('certificate too large');

  SetLength(raw, n);
  Move(ADer[0], raw[1], n);
  Result.Sha256Fp := UpperCase(SHA256Hex(raw));
  sha1d := SHA1String(raw);
  Result.Sha1Fp := '';
  for i := 0 to 19 do
    Result.Sha1Fp := Result.Sha1Fp + IntToHex(sha1d[i], 2);

  cert := Expect(ADer, 0, n, 16, 'certificate sequence');
  tbs := Expect(ADer, cert.ValOfs, cert.EndOfs, 16, 'tbsCertificate');

  p := tbs.ValOfs;
  // [0] EXPLICIT version (optionnel)
  t := ReadTlv(ADer, p, tbs.EndOfs);
  if (t.Cls = 2) and (t.Tag = 0) then
  begin
    boolT := Expect(ADer, t.ValOfs, t.EndOfs, 2, 'version integer');
    if boolT.ValLen = 1 then Result.Version := ADer[boolT.ValOfs] + 1;
    p := t.EndOfs;
    t := ReadTlv(ADer, p, tbs.EndOfs);
  end;
  if (t.Cls <> 0) or (t.Tag <> 2) then
    raise EX509Error.Create('expected serial number');
  if t.ValLen > 64 then
    raise EX509Error.Create('serial too large');
  Result.SerialHex := HexColon(ADer, t.ValOfs, t.ValLen);
  p := t.EndOfs;

  sigalg := Expect(ADer, p, tbs.EndOfs, 16, 'signature algorithm');
  oid := Expect(ADer, sigalg.ValOfs, sigalg.EndOfs, 6, 'signature OID');
  Result.SigAlg := OidName(OidToStr(ADer, oid.ValOfs, oid.ValLen));
  p := sigalg.EndOfs;

  t := Expect(ADer, p, tbs.EndOfs, 16, 'issuer name');
  Result.Issuer := ParseDn(ADer, t);
  p := t.EndOfs;

  t := Expect(ADer, p, tbs.EndOfs, 16, 'validity');
  boolT := ReadTlv(ADer, t.ValOfs, t.EndOfs);
  Result.NotBefore := ParseAsn1Time(ADer, boolT);
  boolT := ReadTlv(ADer, boolT.EndOfs, t.EndOfs);
  Result.NotAfter := ParseAsn1Time(ADer, boolT);
  p := t.EndOfs;

  t := Expect(ADer, p, tbs.EndOfs, 16, 'subject name');
  Result.Subject := ParseDn(ADer, t);
  p := t.EndOfs;

  t := Expect(ADer, p, tbs.EndOfs, 16, 'subjectPublicKeyInfo');
  Result.PubKey := ParseSpki(ADer, t);
  p := t.EndOfs;

  // [1]/[2] uniqueID sautes, [3] extensions
  while p < tbs.EndOfs do
  begin
    t := ReadTlv(ADer, p, tbs.EndOfs);
    if (t.Cls = 2) and (t.Tag = 3) then
    begin
      extSeq := Expect(ADer, t.ValOfs, t.EndOfs, 16, 'extensions sequence');
      p := extSeq.ValOfs;
      n := 0;
      while p < extSeq.EndOfs do
      begin
        Inc(n);
        if n > 64 then Break;
        ext := ReadTlv(ADer, p, extSeq.EndOfs); // SEQ { OID, [crit], OCTET STR }
        extOid := Expect(ADer, ext.ValOfs, ext.EndOfs, 6, 'extension OID');
        extId := OidToStr(ADer, extOid.ValOfs, extOid.ValLen);
        extVal := ReadTlv(ADer, extOid.EndOfs, ext.EndOfs);
        if (extVal.Cls = 0) and (extVal.Tag = 1) then // BOOLEAN critical
          extVal := ReadTlv(ADer, extVal.EndOfs, ext.EndOfs);
        if (extVal.Cls = 0) and (extVal.Tag = 4) then // OCTET STRING
        try
          if extId = '2.5.29.17' then ParseSan(ADer, extVal, Result)
          else if extId = '2.5.29.15' then ParseKeyUsage(ADer, extVal, Result)
          else if extId = '2.5.29.37' then ParseExtKeyUsage(ADer, extVal, Result)
          else if extId = '2.5.29.19' then ParseBasicConstraints(ADer, extVal, Result)
          else if extId = '2.5.29.14' then // SKI = OCTET STRING
          begin
            boolT := Expect(ADer, extVal.ValOfs, extVal.EndOfs, 4, 'SKI');
            if boolT.ValLen <= 64 then
              Result.Ski := HexColon(ADer, boolT.ValOfs, boolT.ValLen);
          end
          else if extId = '2.5.29.35' then // AKI = SEQ { [0] keyId, ... }
          begin
            boolT := Expect(ADer, extVal.ValOfs, extVal.EndOfs, 16, 'AKI');
            if boolT.ValLen > 0 then
            begin
              boolT := ReadTlv(ADer, boolT.ValOfs, boolT.EndOfs);
              if (boolT.Cls = 2) and (boolT.Tag = 0) and (boolT.ValLen <= 64) then
                Result.Aki := HexColon(ADer, boolT.ValOfs, boolT.ValLen);
            end;
          end;
        except
          on EX509Error do ; // extension malformee : ignoree, le cert reste lisible
        end;
        p := ext.EndOfs;
      end;
    end;
    p := t.EndOfs;
  end;
end;

function FmtUtc(const D: TDateTime): string;
begin
  Result := FormatDateTime('yyyy-mm-dd hh:nn:ss', D) + ' UTC';
end;

function ReportCert(const C: TCertInfo; ANowUtc: TDateTime): string;
var
  sl: TStringList;
  days: Integer;
begin
  sl := TStringList.Create;
  try
    sl.Add('Subject:       ' + C.Subject);
    sl.Add('Issuer:        ' + C.Issuer);
    sl.Add('Serial:        ' + C.SerialHex);
    sl.Add('Version:       ' + IntToStr(C.Version));
    sl.Add('Validity:');
    sl.Add('  Not Before:  ' + FmtUtc(C.NotBefore));
    sl.Add('  Not After:   ' + FmtUtc(C.NotAfter));
    if ANowUtc < C.NotBefore then
      sl.Add('  Status:      NOT YET VALID (starts in ' +
        IntToStr(DaysBetween(ANowUtc, C.NotBefore)) + ' day(s))')
    else if ANowUtc > C.NotAfter then
      sl.Add('  Status:      EXPIRED ' +
        IntToStr(DaysBetween(C.NotAfter, ANowUtc)) + ' day(s) ago')
    else
    begin
      days := DaysBetween(ANowUtc, C.NotAfter);
      if days <= 30 then
        sl.Add('  Status:      valid, EXPIRES SOON (' + IntToStr(days) + ' day(s))')
      else
        sl.Add('  Status:      valid (expires in ' + IntToStr(days) + ' day(s))');
    end;
    sl.Add('Public Key:    ' + C.PubKey);
    sl.Add('Signature:     ' + C.SigAlg);
    if C.HasBC then
    begin
      if C.IsCA then
      begin
        if C.PathLen >= 0 then
          sl.Add('CA:            yes (pathlen ' + IntToStr(C.PathLen) + ')')
        else
          sl.Add('CA:            yes');
      end
      else
        sl.Add('CA:            no');
    end;
    if C.KeyUsage <> '' then sl.Add('Key Usage:     ' + C.KeyUsage);
    if C.ExtKeyUsage <> '' then sl.Add('Ext Key Usage: ' + C.ExtKeyUsage);
    if C.San <> '' then sl.Add('SAN:           ' + C.San);
    if C.Ski <> '' then sl.Add('SKI:           ' + C.Ski);
    if C.Aki <> '' then sl.Add('AKI:           ' + C.Aki);
    sl.Add('Fingerprints:');
    sl.Add('  SHA-256:     ' + C.Sha256Fp);
    sl.Add('  SHA-1:       ' + C.Sha1Fp);
    Result := sl.Text;
  finally
    sl.Free;
  end;
end;

type
  TDerList = array of TBytes;

function ExtractPemCerts(const AText: string): TDerList;
const
  BM = '-----BEGIN CERTIFICATE-----';
  EM = '-----END CERTIFICATE-----';
var
  p, e, i, k: Integer;
  b64: string;
  raw: RawByteString;
  der: TBytes;
begin
  Result := nil;
  p := 1;
  while Length(Result) < X509_MAX_CERTS do
  begin
    p := PosEx(BM, AText, p);
    if p = 0 then Break;
    e := PosEx(EM, AText, p + Length(BM));
    if e = 0 then Break;
    SetLength(b64, e - (p + Length(BM)));
    k := 0;
    for i := p + Length(BM) to e - 1 do
      if not (AText[i] in [' ', #9, #10, #13]) then
      begin
        Inc(k);
        b64[k] := AText[i];
      end;
    SetLength(b64, k);
    p := e + Length(EM);
    if (b64 = '') or (Length(b64) > (X509_MAX_DER div 3) * 4 + 8) then Continue;
    try
      raw := B64Decode(b64);
    except
      Continue; // bloc casse : ignore
    end;
    if raw = '' then Continue;
    der := nil;
    SetLength(der, Length(raw));
    Move(raw[1], der[0], Length(raw));
    SetLength(Result, Length(Result) + 1);
    Result[High(Result)] := der;
  end;
end;

function ReportAll(const ADers: TDerList; ANowUtc: TDateTime;
  out AErr: string): string;
var
  sl: TStringList;
  i, okCount: Integer;
  info: TCertInfo;
begin
  AErr := '';
  Result := '';
  okCount := 0;
  sl := TStringList.Create;
  try
    sl.Add('# X.509 certificate report (read-only, signatures NOT verified)');
    sl.Add('');
    for i := 0 to High(ADers) do
    begin
      if Length(ADers) > 1 then
        sl.Add(Format('=== Certificate %d of %d ===', [i + 1, Length(ADers)]));
      try
        info := ParseCert(ADers[i], ANowUtc);
        sl.Add(TrimRight(ReportCert(info, ANowUtc)));
        Inc(okCount);
      except
        on ex: EX509Error do
          sl.Add('  parse error: ' + ex.Message);
      end;
      sl.Add('');
    end;
    if okCount = 0 then
      AErr := 'no readable certificate'
    else
      Result := sl.Text;
  finally
    sl.Free;
  end;
end;

function X509ReportFromText(const AText: string; ANowUtc: TDateTime;
  out AErr: string): string;
var
  ders: TDerList;
begin
  Result := '';
  AErr := '';
  ders := ExtractPemCerts(AText);
  if Length(ders) = 0 then
  begin
    AErr := 'no PEM certificate block (-----BEGIN CERTIFICATE-----) found';
    Exit;
  end;
  Result := ReportAll(ders, ANowUtc, AErr);
end;

function X509ReportFromFile(const AFile: string; ANowUtc: TDateTime;
  out AErr: string): string;
var
  fs: TFileStream;
  buf: TBytes;
  ders: TDerList;
  txt: string;
begin
  Result := '';
  AErr := '';
  buf := nil;
  try
    fs := TFileStream.Create(AFile, fmOpenRead or fmShareDenyWrite);
    try
      if fs.Size > X509_MAX_DER * X509_MAX_CERTS then
      begin
        AErr := 'file too large';
        Exit;
      end;
      SetLength(buf, fs.Size);
      if fs.Size > 0 then fs.ReadBuffer(buf[0], fs.Size);
    finally
      fs.Free;
    end;
  except
    on ex: Exception do
    begin
      AErr := ex.Message;
      Exit;
    end;
  end;
  if Length(buf) = 0 then
  begin
    AErr := 'empty file';
    Exit;
  end;
  if buf[0] = $30 then // DER brut, sinon PEM
  begin
    ders := nil;
    SetLength(ders, 1);
    ders[0] := buf;
    Result := ReportAll(ders, ANowUtc, AErr);
    Exit;
  end;
  SetLength(txt, Length(buf));
  Move(buf[0], txt[1], Length(buf));
  Result := X509ReportFromText(txt, ANowUtc, AErr);
end;

end.
