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
  Classes, SysUtils, base64;

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

function HexNib(c: Char; out V: Integer): Boolean;
begin
  Result := True;
  case c of
    '0'..'9': V := Ord(c) - Ord('0');
    'a'..'f': V := Ord(c) - Ord('a') + 10;
    'A'..'F': V := Ord(c) - Ord('A') + 10;
    else begin V := 0; Result := False; end;
  end;
end;

function RdnAttrValue(const ADn: string; out AAttr, AValue: string): Boolean;
var
  sep, eq, i, hi, lo: Integer;
  first, dec: string;
begin
  AAttr := ''; AValue := '';
  // premier separateur NON echappe (cn=Doe\, John,ou=... ; `+` = RDN multiple)
  sep := 0;
  i := 1;
  while i <= Length(ADn) do
  begin
    if ADn[i] = '\' then Inc(i)
    else if (ADn[i] = ',') or (ADn[i] = '+') then begin sep := i; Break; end;
    Inc(i);
  end;
  if sep > 0 then first := Copy(ADn, 1, sep - 1) else first := ADn;
  first := Trim(first);
  eq := Pos('=', first);
  if eq = 0 then Exit(False);
  AAttr := Trim(Copy(first, 1, eq - 1));
  AValue := Trim(Copy(first, eq + 1, MaxInt));
  // RFC 4514 : \XX est un octet hex, \X un caractere echappe
  dec := '';
  i := 1;
  while i <= Length(AValue) do
  begin
    if (AValue[i] = '\') and (i < Length(AValue)) then
    begin
      if (i + 2 <= Length(AValue)) and HexNib(AValue[i + 1], hi) and
         HexNib(AValue[i + 2], lo) then
      begin
        dec := dec + Chr(hi * 16 + lo);
        Inc(i, 3);
        Continue;
      end;
      dec := dec + AValue[i + 1];
      Inc(i, 2);
      Continue;
    end;
    dec := dec + AValue[i];
    Inc(i);
  end;
  AValue := dec;
  Result := (AAttr <> '') and (AValue <> '');
end;

// composants du PREMIER RDN. Un RDN multi-value (uid=a+cn=b) exige que
// CHAQUE composant existe comme attribut, sinon le serveur refuse l'entree.
procedure RdnComponents(const ADn: string; AAttrs, AValues: TStrings);
var
  i, start: Integer;
  piece, a, v: string;

  procedure Take(const P: string);
  begin
    if Trim(P) = '' then Exit;
    if RdnAttrValue(Trim(P), a, v) then
    begin
      AAttrs.Add(a);
      AValues.Add(v);
    end;
  end;

begin
  start := 1;
  i := 1;
  while i <= Length(ADn) do
  begin
    if ADn[i] = '\' then Inc(i)
    else if ADn[i] = ',' then Break
    else if ADn[i] = '+' then
    begin
      Take(Copy(ADn, start, i - start));
      start := i + 1;
    end;
    Inc(i);
  end;
  piece := Copy(ADn, start, i - start);
  Take(piece);
end;

// valeur du composant AAttr du premier RDN, a defaut celle du premier
// composant (description=x+cn=g -> cn: g, pas cn: x)
function RdnValueFor(const ADn, AAttr: string): string;
var
  at, vl: TStringList;
  i: Integer;
begin
  Result := '';
  at := TStringList.Create;
  vl := TStringList.Create;
  try
    RdnComponents(ADn, at, vl);
    for i := 0 to at.Count - 1 do
      if SameText(at[i], AAttr) then Exit(vl[i]);
    if at.Count > 0 then Result := vl[0];
  finally
    at.Free;
    vl.Free;
  end;
end;

// composants du RDN autres que (AAttr, AVal) deja emis par l'appelant. Le
// filtre porte sur le couple: description=x+cn=g emet description: x
function EmitRdnExtras(const ADn, AAttr, AVal: string): string;
var
  at, vl: TStringList;
  i: Integer;
  skipped: Boolean;
begin
  Result := '';
  skipped := False;
  at := TStringList.Create;
  vl := TStringList.Create;
  try
    RdnComponents(ADn, at, vl);
    for i := 0 to at.Count - 1 do
      if not skipped and SameText(at[i], AAttr) and (vl[i] = AVal) then
        skipped := True
      else
        Result := Result + EmitAttr(at[i], vl[i]);
  finally
    at.Free;
    vl.Free;
  end;
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
  dc := RdnValueFor(ADn, 'dc');
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
var
  v: string;
begin
  Result := EmitAttr('dn', ADn);
  Result := Result + 'objectClass: top' + LineEnding;
  Result := Result + 'objectClass: organizationalUnit' + LineEnding;
  v := RdnValueFor(ADn, 'ou');
  Result := Result + EmitAttr('ou', v);
  Result := Result + EmitRdnExtras(ADn, 'ou', v);
  Result := Result + EmitAttr('description', ADescription);
  Result := Result + LineEnding;
end;

function BuildLdifGroup(const ADn, AGidNumber, AMembers, ADescription: string): string;
var
  norm, m, v: string;
  i: Integer;
begin
  Result := EmitAttr('dn', ADn);
  Result := Result + 'objectClass: top' + LineEnding;
  Result := Result + 'objectClass: posixGroup' + LineEnding;
  v := RdnValueFor(ADn, 'cn');
  Result := Result + EmitAttr('cn', v);
  Result := Result + EmitRdnExtras(ADn, 'cn', v);
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
  norm, mdn, v: string;
  i: Integer;
begin
  Result := EmitAttr('dn', ADn);
  Result := Result + 'objectClass: top' + LineEnding;
  Result := Result + 'objectClass: groupOfNames' + LineEnding;
  v := RdnValueFor(ADn, 'cn');
  Result := Result + EmitAttr('cn', v);
  Result := Result + EmitRdnExtras(ADn, 'cn', v);
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
  val: string;
begin
  // uid pris sur le composant uid= s'il existe (cn=Alice+uid=alice), sinon
  // sur le premier; les autres composants (cn=svc) sortent en extras
  val := RdnValueFor(ADn, 'uid');
  Result := EmitAttr('dn', ADn);
  Result := Result + 'objectClass: top' + LineEnding;
  Result := Result + 'objectClass: account' + LineEnding;
  if AUserPassword <> '' then
    Result := Result + 'objectClass: simpleSecurityObject' + LineEnding;
  Result := Result + EmitAttr('uid', val);        // account : uid MUST
  Result := Result + EmitRdnExtras(ADn, 'uid', val);
  Result := Result + EmitAttr('userPassword', AUserPassword);
  Result := Result + EmitAttr('description', ADescription);
  Result := Result + LineEnding;
end;

end.
