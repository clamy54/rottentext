unit uNet;

{$mode objfpc}{$H+}

// Calculateur CIDR v4/v6, formatage IPv6 canonique RFC 5952.
// CidrReport dispatche sur la presence d'un ':' : une adresse avec port
// ("1.2.3.4:80") part donc en v6 et sort une erreur.

interface

uses
  SysUtils;

type
  ENetError = class(Exception);

function CidrReportV4(const AInput: string): string;
function CidrReportV6(const AInput: string): string;
function CidrReport(const AInput: string): string;

implementation

uses
  Classes;

function ParseIPv4(const S: string; out V: LongWord): Boolean;
var
  i, val, dig, cnt: Integer;
begin
  V := 0; val := 0; dig := 0; cnt := 0;
  for i := 1 to Length(S) do
    case S[i] of
      '0'..'9':
        begin
          val := val * 10 + (Ord(S[i]) - Ord('0'));
          Inc(dig);
          if (val > 255) or (dig > 3) then Exit(False);
        end;
      '.':
        begin
          if dig = 0 then Exit(False);
          V := (V shl 8) or LongWord(val);
          Inc(cnt); val := 0; dig := 0;
        end;
      else Exit(False);
    end;
  if dig = 0 then Exit(False);
  V := (V shl 8) or LongWord(val);
  Inc(cnt);
  Result := cnt = 4;
end;

function IPToStr(V: LongWord): string;
begin
  Result := Format('%d.%d.%d.%d',
    [(V shr 24) and $FF, (V shr 16) and $FF, (V shr 8) and $FF, V and $FF]);
end;

function AddrType(V: LongWord): string;
begin
  if (V and $FF000000) = $7F000000 then Exit('loopback');       // 127/8
  if (V and $FFFF0000) = $A9FE0000 then Exit('link-local');     // 169.254/16
  if (V and $FF000000) = $0A000000 then Exit('private');        // 10/8
  if (V and $FFF00000) = $AC100000 then Exit('private');        // 172.16/12
  if (V and $FFFF0000) = $C0A80000 then Exit('private');        // 192.168/16
  if (V and $F0000000) = $E0000000 then Exit('multicast');      // 224/4
  Result := 'public';
end;

function CidrReportV4(const AInput: string): string;
var
  s, ipPart, pfxPart: string;
  slash, prefix: Integer;
  ip, mask, network, broadcast, wildcard, hmin, hmax: LongWord;
  total, usable: QWord;
  sb: TStringList;
begin
  s := Trim(AInput);
  if s = '' then raise ENetError.Create('Empty input');
  slash := Pos('/', s);
  if slash > 0 then
  begin
    ipPart := Trim(Copy(s, 1, slash - 1));
    pfxPart := Trim(Copy(s, slash + 1, MaxInt));
    prefix := StrToIntDef(pfxPart, -1);
    if (pfxPart = '') or (prefix < 0) or (prefix > 32) then
      raise ENetError.Create('Prefix must be 0..32');
  end
  else
  begin
    ipPart := s; prefix := 32;
  end;
  if not ParseIPv4(ipPart, ip) then
    raise ENetError.Create('Invalid IPv4 address');

  if prefix = 0 then mask := 0
  else mask := LongWord($FFFFFFFF) shl (32 - prefix);
  network := ip and mask;
  wildcard := not mask;
  broadcast := network or wildcard;
  total := QWord(1) shl (32 - prefix);
  if prefix >= 31 then
  begin
    hmin := network; hmax := broadcast;
    if prefix = 32 then usable := 1 else usable := 2;   // /31 = point-a-point
  end
  else
  begin
    hmin := network + 1; hmax := broadcast - 1;
    usable := total - 2;
  end;

  sb := TStringList.Create;
  try
    sb.Add(Format('Address:    %s/%d', [IPToStr(ip), prefix]));
    sb.Add(Format('Netmask:    %s = /%d', [IPToStr(mask), prefix]));
    sb.Add(Format('Wildcard:   %s', [IPToStr(wildcard)]));
    sb.Add(Format('Network:    %s/%d', [IPToStr(network), prefix]));
    sb.Add(Format('Broadcast:  %s', [IPToStr(broadcast)]));
    sb.Add(Format('HostMin:    %s', [IPToStr(hmin)]));
    sb.Add(Format('HostMax:    %s', [IPToStr(hmax)]));
    sb.Add(Format('Hosts:      %s usable', [IntToStr(usable)]));
    sb.Add(Format('Total:      %s addresses', [IntToStr(total)]));
    sb.Add(Format('Type:       %s', [AddrType(network)]));
    Result := sb.Text;
  finally
    sb.Free;
  end;
end;

{ ---- IPv6 ---- }

type
  TIPv6 = array[0..15] of Byte;
  TWords8 = array[0..7] of Word;

function ParseHexGroup(const G: string; out W: Word): Boolean;
var
  i, v: Integer;
begin
  Result := False;
  v := 0;
  if (G = '') or (Length(G) > 4) then Exit;
  for i := 1 to Length(G) do
    case G[i] of
      '0'..'9': v := v * 16 + Ord(G[i]) - Ord('0');
      'a'..'f': v := v * 16 + Ord(G[i]) - Ord('a') + 10;
      'A'..'F': v := v * 16 + Ord(G[i]) - Ord('A') + 10;
      else Exit;
    end;
  W := v;
  Result := True;
end;

function ParseGroups(const S: string; var W: TWords8; out N: Integer): Boolean;
var
  i, start: Integer;
  g: string;
  ip4: LongWord;
  wv: Word;
begin
  Result := False;
  N := 0;
  if S = '' then Exit(True);   // bord d'un '::'
  start := 1;
  for i := 1 to Length(S) + 1 do
    if (i > Length(S)) or (S[i] = ':') then
    begin
      g := Copy(S, start, i - start);
      if g = '' then Exit;   // '::' gere par l'appelant, ':' vide = invalide
      if Pos('.', g) > 0 then
      begin
        if i <= Length(S) then Exit;   // IPv4 embarquee = dernier groupe
        if (not ParseIPv4(g, ip4)) or (N > 6) then Exit;
        W[N] := Word(ip4 shr 16); Inc(N);
        W[N] := Word(ip4 and $FFFF); Inc(N);
      end
      else
      begin
        if (not ParseHexGroup(g, wv)) or (N > 7) then Exit;
        W[N] := wv; Inc(N);
      end;
      start := i + 1;
    end;
  Result := True;
end;

function ParseIPv6(const AInput: string; out A: TIPv6): Boolean;
var
  s, l, r: string;
  p, i, nl, nr: Integer;
  wl, wr, w: TWords8;
begin
  Result := False;
  FillChar(A, SizeOf(A), 0);
  FillChar(w{%H-}, SizeOf(w), 0);
  s := Trim(AInput);
  p := Pos('%', s);   // zone (fe80::1%eth0) ignoree
  if p > 0 then s := Copy(s, 1, p - 1);
  if s = '' then Exit;
  p := Pos('::', s);
  if p > 0 then
  begin
    l := Copy(s, 1, p - 1);
    r := Copy(s, p + 2, MaxInt);
    if Pos('::', r) > 0 then Exit;
    if not ParseGroups(l, wl, nl) then Exit;
    if not ParseGroups(r, wr, nr) then Exit;
    if nl + nr > 7 then Exit;        // '::' doit compresser au moins un groupe
    for i := 0 to nl - 1 do w[i] := wl[i];
    for i := 0 to nr - 1 do w[8 - nr + i] := wr[i];
  end
  else
  begin
    if (not ParseGroups(s, wl, nl)) or (nl <> 8) then Exit;
    w := wl;
  end;
  for i := 0 to 7 do
  begin
    A[i * 2] := w[i] shr 8;
    A[i * 2 + 1] := w[i] and $FF;
  end;
  Result := True;
end;

// RFC 5952 : plus longue suite de zeros >= 2 compressee, la plus a gauche
function FormatIPv6(const A: TIPv6): string;
var
  w: TWords8;
  i, runStart, runLen, bestStart, bestLen: Integer;
begin
  for i := 0 to 7 do
    w[i] := (A[i * 2] shl 8) or A[i * 2 + 1];
  bestStart := -1; bestLen := 0; runStart := -1; runLen := 0;
  for i := 0 to 7 do
    if w[i] = 0 then
    begin
      if runStart < 0 then begin runStart := i; runLen := 0; end;
      Inc(runLen);
      if runLen > bestLen then begin bestLen := runLen; bestStart := runStart; end;
    end
    else
      runStart := -1;
  if bestLen < 2 then bestStart := -1;
  Result := '';
  i := 0;
  while i <= 7 do
  begin
    if i = bestStart then
    begin
      Result := Result + '::';
      Inc(i, bestLen);
      Continue;
    end;
    if (Result <> '') and (Result[Length(Result)] <> ':') then
      Result := Result + ':';
    Result := Result + LowerCase(IntToHex(w[i], 1));
    Inc(i);
  end;
  if Result = '' then Result := '::';
end;

procedure MaskV6(const A: TIPv6; APrefix: Integer; out ANet, ALast: TIPv6);
var
  i, full, rem: Integer;
  mb: Byte;
begin
  full := APrefix div 8;
  rem := APrefix mod 8;
  for i := 0 to 15 do
    if i < full then
    begin
      ANet[i] := A[i];
      ALast[i] := A[i];
    end
    else if (i = full) and (rem > 0) then
    begin
      mb := Byte($FF shl (8 - rem));
      ANet[i] := A[i] and mb;
      ALast[i] := A[i] or (not mb);
    end
    else
    begin
      ANet[i] := 0;
      ALast[i] := $FF;
    end;
end;

function AddrTypeV6(const A: TIPv6): string;
var
  i: Integer;
  z: Boolean;
begin
  z := True;
  for i := 0 to 15 do if A[i] <> 0 then begin z := False; Break; end;
  if z then Exit('unspecified');
  z := True;
  for i := 0 to 14 do if A[i] <> 0 then begin z := False; Break; end;
  if z and (A[15] = 1) then Exit('loopback');
  if A[0] = $FF then Exit('multicast');
  if (A[0] = $FE) and ((A[1] and $C0) = $80) then Exit('link-local');
  if (A[0] and $FE) = $FC then Exit('unique local (ULA)');
  if (A[0] = $20) and (A[1] = $01) and (A[2] = $0D) and (A[3] = $B8) then
    Exit('documentation');
  z := True;   // ::ffff:0:0/96 = IPv4-mapped
  for i := 0 to 9 do if A[i] <> 0 then begin z := False; Break; end;
  if z and (A[10] = $FF) and (A[11] = $FF) then Exit('IPv4-mapped');
  if (A[0] and $E0) = $20 then Exit('global unicast');
  Result := 'reserved';
end;

function CidrReportV6(const AInput: string): string;
var
  s, ipPart, pfxPart, cnt, exp_: string;
  slash, prefix, i: Integer;
  a, net, last: TIPv6;
  sb: TStringList;
begin
  s := Trim(AInput);
  if s = '' then raise ENetError.Create('Empty input');
  slash := Pos('/', s);
  if slash > 0 then
  begin
    ipPart := Trim(Copy(s, 1, slash - 1));
    pfxPart := Trim(Copy(s, slash + 1, MaxInt));
    prefix := StrToIntDef(pfxPart, -1);
    if (pfxPart = '') or (prefix < 0) or (prefix > 128) then
      raise ENetError.Create('Prefix must be 0..128');
  end
  else
  begin
    ipPart := s;
    prefix := 128;
  end;
  if not ParseIPv6(ipPart, a) then
    raise ENetError.Create('Invalid IPv6 address');
  MaskV6(a, prefix, net, last);
  exp_ := '';
  for i := 0 to 7 do
  begin
    if exp_ <> '' then exp_ := exp_ + ':';
    exp_ := exp_ + LowerCase(IntToHex((a[i * 2] shl 8) or a[i * 2 + 1], 4));
  end;
  if prefix = 128 then cnt := '1'
  else if 128 - prefix <= 63 then
    cnt := Format('%s (2^%d)', [IntToStr(QWord(1) shl (128 - prefix)), 128 - prefix])
  else
    cnt := Format('2^%d', [128 - prefix]);
  sb := TStringList.Create;
  try
    sb.Add(Format('Address:    %s/%d', [FormatIPv6(a), prefix]));
    sb.Add(Format('Expanded:   %s', [exp_]));
    sb.Add(Format('Network:    %s/%d', [FormatIPv6(net), prefix]));
    sb.Add(Format('Last addr:  %s', [FormatIPv6(last)]));
    sb.Add(Format('Addresses:  %s', [cnt]));
    sb.Add(Format('Type:       %s', [AddrTypeV6(a)]));
    Result := sb.Text;
  finally
    sb.Free;
  end;
end;

function CidrReport(const AInput: string): string;
begin
  if Pos(':', AInput) > 0 then Result := CidrReportV6(AInput)
  else Result := CidrReportV4(AInput);
end;

end.
