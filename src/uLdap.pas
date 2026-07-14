unit uLdap;

{$mode objfpc}{$H+}

// Valeurs userPassword OpenLDAP, format slappasswd. Sale = base64(digest(pwd+sel) ++ sel).
// Le clair n'est jamais conserve ici : l'appelant le saisit masque et le zeroise.

interface

type
  // lpsSASL : pas un hash, la valeur est une identite SASL stockee telle quelle
  TLdapPwScheme = (lpsSSHA, lpsSSHA256, lpsSSHA512, lpsSHA, lpsSMD5, lpsMD5,
    lpsCrypt, lpsSASL);

function LdapUserPassword(AScheme: TLdapPwScheme; const APassword: RawByteString): string;

implementation

uses
  SysUtils, base64, md5, sha1, uSha2, uBcrypt, uSecRand;

type
  ELdapError = class(Exception);

const
  SALT_LEN = 8;

function RandBytes(ALen: Integer): RawByteString;
begin
  SetLength(Result, ALen);
  if (ALen > 0) and not SecureRandomBytes(Result[1], ALen) then
    raise ELdapError.Create('Secure random source unavailable');
end;

function Md5Raw(const S: RawByteString): RawByteString;
var
  ctx: TMD5Context;
  dig: TMD5Digest;
  p: Pointer;
begin
  MD5Init(ctx);
  if S <> '' then begin p := Pointer(S); MD5Update(ctx, p^, Length(S)); end;
  MD5Final(ctx, dig);
  SetLength(Result, SizeOf(dig));
  Move(dig[0], Result[1], SizeOf(dig));
end;

function Sha1Raw(const S: RawByteString): RawByteString;
var
  ctx: TSHA1Context;
  dig: TSHA1Digest;
  p: Pointer;
begin
  SHA1Init(ctx);
  if S <> '' then begin p := Pointer(S); SHA1Update(ctx, p^, Length(S)); end;
  SHA1Final(ctx, dig);
  SetLength(Result, SizeOf(dig));
  Move(dig[0], Result[1], SizeOf(dig));
end;

function Sha256Raw(const S: RawByteString): RawByteString;
var
  ctx: TSHA256Ctx;
  dig: array[0..31] of Byte;
  p: Pointer;
begin
  SHA256Init(ctx);
  if S <> '' then begin p := Pointer(S); SHA256Update(ctx, p^, Length(S)); end;
  SHA256Final(ctx, dig);
  SetLength(Result, 32);
  Move(dig[0], Result[1], 32);
end;

function Sha512Raw(const S: RawByteString): RawByteString;
var
  ctx: TSHA512Ctx;
  dig: array[0..63] of Byte;
  p: Pointer;
begin
  SHA512Init(ctx);
  if S <> '' then begin p := Pointer(S); SHA512Update(ctx, p^, Length(S)); end;
  SHA512Final(ctx, dig);
  SetLength(Result, 64);
  Move(dig[0], Result[1], 64);
end;

function LdapUserPassword(AScheme: TLdapPwScheme; const APassword: RawByteString): string;
var
  salt: RawByteString;
  bsalt: array[0..15] of Byte;
begin
  case AScheme of
    lpsSHA:
      Result := '{SHA}' + EncodeStringBase64(Sha1Raw(APassword));
    lpsMD5:
      Result := '{MD5}' + EncodeStringBase64(Md5Raw(APassword));
    lpsSSHA:
      begin
        salt := RandBytes(SALT_LEN);
        Result := '{SSHA}' + EncodeStringBase64(Sha1Raw(APassword + salt) + salt);
      end;
    lpsSMD5:
      begin
        salt := RandBytes(SALT_LEN);
        Result := '{SMD5}' + EncodeStringBase64(Md5Raw(APassword + salt) + salt);
      end;
    lpsSSHA256:
      begin
        salt := RandBytes(SALT_LEN);
        Result := '{SSHA256}' + EncodeStringBase64(Sha256Raw(APassword + salt) + salt);
      end;
    lpsSSHA512:
      begin
        salt := RandBytes(SALT_LEN);
        Result := '{SSHA512}' + EncodeStringBase64(Sha512Raw(APassword + salt) + salt);
      end;
    lpsCrypt:
      begin
        if not SecureRandomBytes(bsalt[0], 16) then
          raise ELdapError.Create('Secure random source unavailable');
        Result := '{CRYPT}' + BcryptHash(APassword, 10, bsalt[0]);
      end;
    lpsSASL:
      Result := '{SASL}' + APassword;
  end;
end;

end.
