unit uLdif;

{$mode objfpc}{$H+}

// Generation d'entrees LDIF. RFC 2849 : une valeur non "safe" (octet < 32 ou > 126,
// debut espace/':'/'<', fin espace) est encodee "attr:: base64(utf8)".
// Le userPassword arrive deja hashe (uLdap) : le clair ne passe jamais ici.

interface

type
  TLdifPerson = record
    Dn: string;
    Cn, Sn, GivenName, DisplayName, Uid, Mail, Telephone, Title, O, Ou,
      Description: string;
    IncPosix: Boolean;
    UidNumber, GidNumber, HomeDir, LoginShell, Gecos: string;
    UserPassword: string;   // deja hashe ('{SSHA}...') ou vide
  end;

// '' si valide, sinon le message d'erreur.
function ValidateLdif(const P: TLdifPerson): string;

function BuildLdif(const P: TLdifPerson): string;
function BuildLdifRoot(const ADn, AOrg, ADescription: string): string;
function BuildLdifOU(const ADn, ADescription: string): string;
function BuildLdifGroup(const ADn, AGidNumber, AMembers, ADescription: string): string;
function BuildLdifGroupOfNames(const ADn, AMembers, ADescription: string): string;
function BuildLdifService(const ADn, AUserPassword, ADescription: string): string;
function RdnValue(const ADn: string): string;
function RdnAttrValue(const ADn: string; out AAttr, AValue: string): Boolean;

implementation

uses
  SysUtils, base64;

function NeedsB64(const V: string): Boolean;
var
  i: Integer;
  b: Byte;
begin
  if V = '' then Exit(False);
  b := Byte(V[1]);
  if (b = Ord(' ')) or (b = Ord(':')) or (b = Ord('<')) then Exit(True);
  if V[Length(V)] = ' ' then Exit(True);
  for i := 1 to Length(V) do
  begin
    b := Byte(V[i]);
    if (b < 32) or (b > 126) then Exit(True);
  end;
  Result := False;
end;

function EmitAttr(const AName, AVal: string): string;
begin
  if AVal = '' then Exit('');
  if NeedsB64(AVal) then
    Result := AName + ':: ' + EncodeStringBase64(AVal) + LineEnding
  else
    Result := AName + ': ' + AVal + LineEnding;
end;

function ValidateLdif(const P: TLdifPerson): string;
begin
  Result := '';
  if Trim(P.Dn) = '' then Exit('DN is required');
  if Trim(P.Cn) = '' then Exit('cn (common name) is required');
  if Trim(P.Sn) = '' then Exit('sn (surname) is required');
  if P.IncPosix then
  begin
    if Trim(P.Uid) = '' then Exit('uid is required for posixAccount');
    if Trim(P.UidNumber) = '' then Exit('uidNumber is required for posixAccount');
    if Trim(P.GidNumber) = '' then Exit('gidNumber is required for posixAccount');
    if Trim(P.HomeDir) = '' then Exit('homeDirectory is required for posixAccount');
  end;
end;

function BuildLdif(const P: TLdifPerson): string;
begin
  Result := EmitAttr('dn', P.Dn);
  Result := Result + 'objectClass: top' + LineEnding;
  Result := Result + 'objectClass: person' + LineEnding;
  Result := Result + 'objectClass: organizationalPerson' + LineEnding;
  Result := Result + 'objectClass: inetOrgPerson' + LineEnding;
  if P.IncPosix then
    Result := Result + 'objectClass: posixAccount' + LineEnding;
  Result := Result + EmitAttr('cn', P.Cn);
  Result := Result + EmitAttr('sn', P.Sn);
  Result := Result + EmitAttr('givenName', P.GivenName);
  Result := Result + EmitAttr('displayName', P.DisplayName);
  Result := Result + EmitAttr('uid', P.Uid);
  Result := Result + EmitAttr('mail', P.Mail);
  Result := Result + EmitAttr('telephoneNumber', P.Telephone);
  Result := Result + EmitAttr('title', P.Title);
  Result := Result + EmitAttr('o', P.O);
  Result := Result + EmitAttr('ou', P.Ou);
  if P.IncPosix then
  begin
    Result := Result + EmitAttr('uidNumber', P.UidNumber);
    Result := Result + EmitAttr('gidNumber', P.GidNumber);
    Result := Result + EmitAttr('homeDirectory', P.HomeDir);
    Result := Result + EmitAttr('loginShell', P.LoginShell);
    Result := Result + EmitAttr('gecos', P.Gecos);
  end;
  Result := Result + EmitAttr('userPassword', P.UserPassword);
  Result := Result + EmitAttr('description', P.Description);
  Result := Result + LineEnding;   // ligne vide = separateur d'entrees LDIF
end;

function RdnAttrValue(const ADn: string; out AAttr, AValue: string): Boolean;
var
  comma, eq: Integer;
  first: string;
begin
  AAttr := ''; AValue := '';
  comma := Pos(',', ADn);
  if comma > 0 then first := Copy(ADn, 1, comma - 1) else first := ADn;
  first := Trim(first);
  eq := Pos('=', first);
  if eq = 0 then Exit(False);
  AAttr := Trim(Copy(first, 1, eq - 1));
  AValue := Trim(Copy(first, eq + 1, MaxInt));
  Result := (AAttr <> '') and (AValue <> '');
end;

function RdnValue(const ADn: string): string;
var
  a, v: string;
begin
  if RdnAttrValue(ADn, a, v) then Result := v else Result := '';
end;

function BuildLdifRoot(const ADn, AOrg, ADescription: string): string;
var
  dc, org: string;
begin
  dc := RdnValue(ADn);
  org := AOrg;
  if org = '' then org := dc;
  Result := EmitAttr('dn', ADn);
  Result := Result + 'objectClass: top' + LineEnding;
  Result := Result + 'objectClass: dcObject' + LineEnding;
  Result := Result + 'objectClass: organization' + LineEnding;
  Result := Result + EmitAttr('dc', dc);
  Result := Result + EmitAttr('o', org);
  Result := Result + EmitAttr('description', ADescription);
  Result := Result + LineEnding;
end;

function BuildLdifOU(const ADn, ADescription: string): string;
begin
  Result := EmitAttr('dn', ADn);
  Result := Result + 'objectClass: top' + LineEnding;
  Result := Result + 'objectClass: organizationalUnit' + LineEnding;
  Result := Result + EmitAttr('ou', RdnValue(ADn));
  Result := Result + EmitAttr('description', ADescription);
  Result := Result + LineEnding;
end;

function BuildLdifGroup(const ADn, AGidNumber, AMembers, ADescription: string): string;
var
  norm, m: string;
  i: Integer;
begin
  Result := EmitAttr('dn', ADn);
  Result := Result + 'objectClass: top' + LineEnding;
  Result := Result + 'objectClass: posixGroup' + LineEnding;
  Result := Result + EmitAttr('cn', RdnValue(ADn));
  Result := Result + EmitAttr('gidNumber', AGidNumber);
  norm := AMembers;
  for i := 1 to Length(norm) do
    if (norm[i] = ',') or (norm[i] = ';') then norm[i] := ' ';
  repeat
    i := Pos(' ', norm);
    if i = 0 then begin m := Trim(norm); norm := ''; end
    else begin m := Trim(Copy(norm, 1, i - 1)); norm := Copy(norm, i + 1, MaxInt); end;
    if m <> '' then Result := Result + EmitAttr('memberUid', m);
  until norm = '';
  Result := Result + EmitAttr('description', ADescription);
  Result := Result + LineEnding;
end;

function BuildLdifGroupOfNames(const ADn, AMembers, ADescription: string): string;
var
  norm, mdn: string;
  i: Integer;
begin
  Result := EmitAttr('dn', ADn);
  Result := Result + 'objectClass: top' + LineEnding;
  Result := Result + 'objectClass: groupOfNames' + LineEnding;
  Result := Result + EmitAttr('cn', RdnValue(ADn));
  // separateur ';' seulement : un DN contient des virgules
  norm := AMembers;
  repeat
    i := Pos(';', norm);
    if i = 0 then begin mdn := Trim(norm); norm := ''; end
    else begin mdn := Trim(Copy(norm, 1, i - 1)); norm := Copy(norm, i + 1, MaxInt); end;
    if mdn <> '' then Result := Result + EmitAttr('member', mdn);
  until norm = '';
  Result := Result + EmitAttr('description', ADescription);
  Result := Result + LineEnding;
end;

function BuildLdifService(const ADn, AUserPassword, ADescription: string): string;
var
  attr, val: string;
begin
  RdnAttrValue(ADn, attr, val);
  Result := EmitAttr('dn', ADn);
  Result := Result + 'objectClass: top' + LineEnding;
  Result := Result + 'objectClass: account' + LineEnding;
  if AUserPassword <> '' then
    Result := Result + 'objectClass: simpleSecurityObject' + LineEnding;
  Result := Result + EmitAttr('uid', val);        // account : uid MUST
  if SameText(attr, 'cn') then
    Result := Result + EmitAttr('cn', val);        // RDN cn= : l'attribut doit exister aussi
  Result := Result + EmitAttr('userPassword', AUserPassword);
  Result := Result + EmitAttr('description', ADescription);
  Result := Result + LineEnding;
end;

end.
