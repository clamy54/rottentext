unit uLdap;

{$mode objfpc}{$H+}

// Valeurs userPassword OpenLDAP, format slappasswd. Sale = base64(digest(pwd+sel) ++ sel).
// Le clair n'est jamais conserve ici : l'appelant le saisit masque et le zeroise.

interface

type
  // lpsSASL : pas un hash, la valeur est une identite SASL stockee telle quelle
  // lpsArgon2Lib* : {ARGON2} avec les parametres PAR DEFAUT du module
  // pw-argon2 d'OpenLDAP selon la bibliotheque de compilation (le hash porte
  // ses parametres, la verification marche dans les deux cas ; on aligne le
  // cout sur ce que le serveur produirait lui-meme)
  TLdapPwScheme = (lpsSSHA, lpsSSHA256, lpsSSHA512, lpsSHA, lpsSMD5, lpsMD5,
    lpsCrypt, lpsSASL, lpsArgon2LibArgon2, lpsArgon2LibSodium);

function LdapUserPassword(AScheme: TLdapPwScheme; const APassword: RawByteString): string;

implementation

uses
  SysUtils, base64, md5, sha1, uSha2, uBcrypt, uArgon2, uSecRand;

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
  salted: string;

  // clair + sel dans UN tampon local, zeroise apres hachage
  function PwSalt: string;
  begin
    salted := APassword + salt;
    Result := salted;
  end;

begin
  salted := '';
  case AScheme of
    lpsSHA:
      Result := '{SHA}' + EncodeStringBase64(Sha1Raw(APassword));
    lpsMD5:
      Result := '{MD5}' + EncodeStringBase64(Md5Raw(APassword));
    lpsSSHA:
      begin
        salt := RandBytes(SALT_LEN);
        Result := '{SSHA}' + EncodeStringBase64(Sha1Raw(PwSalt) + salt);
      end;
    lpsSMD5:
      begin
        salt := RandBytes(SALT_LEN);
        Result := '{SMD5}' + EncodeStringBase64(Md5Raw(PwSalt) + salt);
      end;
    lpsSSHA256:
      begin
        salt := RandBytes(SALT_LEN);
        Result := '{SSHA256}' + EncodeStringBase64(Sha256Raw(PwSalt) + salt);
      end;
    lpsSSHA512:
      begin
        salt := RandBytes(SALT_LEN);
        Result := '{SSHA512}' + EncodeStringBase64(Sha512Raw(PwSalt) + salt);
      end;
    lpsCrypt:
      begin
        if not SecureRandomBytes(bsalt[0], 16) then
          raise ELdapError.Create('Secure random source unavailable');
        Result := '{CRYPT}' + BcryptHash(APassword, 10, bsalt[0]);
      end;
    lpsSASL:
      Result := '{SASL}' + APassword;
    // servers/slapd/pwmods/argon2.c : SLAPD_ARGON2_ITERATIONS 5,
    // SLAPD_ARGON2_MEMORY 7168 (KiB), PARALLELISM 1, SALT 16, HASH 32
    lpsArgon2LibArgon2:
      Result := '{ARGON2}' + Argon2idPhc(APassword, RandBytes(16), 5, 7168, 1, 32);
    // meme fichier, branche libsodium : crypto_pwhash_argon2id_OPSLIMIT_INTERACTIVE
    // = 2, MEMLIMIT_INTERACTIVE = 64 MiB, SALTBYTES 16, hash 32
    lpsArgon2LibSodium:
      Result := '{ARGON2}' + Argon2idPhc(APassword, RandBytes(16), 2, 65536, 1, 32);
  end;
  if salted <> '' then FillChar(salted[1], Length(salted), 0);
end;

end.
