unit uMailTrace;

{$mode objfpc}{$H+}

// Trajet d'un mail depuis ses en-tetes Received, qui sont des DECLARATIONS
// forgeables sous le premier hop de confiance (bandeau dans le rapport). Le
// groupement des hops par serveur est une HEURISTIQUE. Entree hostile :
// plafonds MT_MAX_*, scanners lineaires (pas de regex), profondeur bornee.

interface

// '' si aucun en-tete Received exploitable
function MailTraceReport(const S: string): string;

implementation

uses
  Classes, SysUtils, DateUtils;

const
  MT_MAX_BYTES = 8 * 1024 * 1024;
  MAX_HEADERS  = 2000;
  MAX_HDR_LEN  = 65536;
  MAX_HOPS     = 64;
  MAX_RULES    = 80;
  MAX_UNPARSED = 3;
  MONTHS: array[1..12] of string =
    ('jan', 'feb', 'mar', 'apr', 'may', 'jun',
     'jul', 'aug', 'sep', 'oct', 'nov', 'dec');

type
  THeader = record
    Name, Value: string;
  end;

  THop = record
    FromName, FromRdns, FromIP: string;
    ByName, ByAlias, ByIP: string;   // ByAlias = nom reel du commentaire: 'by localhost (mx1 [127.0.0.1])'
    Proto, QueueId, ForAddr, Software: string;
    Port: Integer;
    HasDate: Boolean;
    UTC: TDateTime;
    Parsed: Boolean;
    Raw: string;
  end;

  TRule = record
    Name: string;
    Score: Double;
    HasScore: Boolean;
  end;

  TBox = record
    NormName, DispName, IP: string;
    FirstHop, LastHop: Integer;
  end;

function IsDig(c: Char): Boolean; inline;
begin
  Result := c in ['0'..'9'];
end;

function IsAlphaC(c: Char): Boolean; inline;
begin
  Result := c in ['A'..'Z', 'a'..'z'];
end;

function IsAlnumC(c: Char): Boolean; inline;
begin
  Result := c in ['A'..'Z', 'a'..'z', '0'..'9'];
end;

function CleanCtl(const S: string): string;
var
  i: Integer;
begin
  Result := S;
  for i := 1 to Length(Result) do
    if (Result[i] < #32) or (Result[i] = #127) then Result[i] := ' ';
end;

function CapStr(const S: string; N: Integer): string;
begin
  if Length(S) <= N then Result := S
  else Result := Copy(S, 1, N - 3) + '...';
end;

function TidyStr(const S: string; N: Integer): string;
begin
  Result := CapStr(Trim(CleanCtl(S)), N);
end;

function MonthOf3(const S3: string): Integer;
var
  i: Integer;
  l: string;
begin
  Result := 0;
  l := LowerCase(S3);
  for i := 1 to 12 do
    if l = MONTHS[i] then Exit(i);
end;

{ ---- decode des encoded-words RFC 2047 (Subject/From/To affiches) ---- }

function B64d(const S: string): string;
var
  i, v, bits, n: Integer;
begin
  Result := '';
  v := 0;
  bits := 0;
  for i := 1 to Length(S) do
  begin
    case S[i] of
      'A'..'Z': n := Ord(S[i]) - 65;
      'a'..'z': n := Ord(S[i]) - 71;
      '0'..'9': n := Ord(S[i]) + 4;
      '+': n := 62;
      '/': n := 63;
      '=': Break;
      else Continue;
    end;
    v := (v shl 6) or n;
    Inc(bits, 6);
    if bits >= 8 then
    begin
      Dec(bits, 8);
      Result := Result + Chr((v shr bits) and $FF);
    end;
  end;
end;

function QPd(const S: string): string;
var
  i, hi, lo: Integer;

  function HexV(c: Char): Integer;
  begin
    case c of
      '0'..'9': Result := Ord(c) - 48;
      'a'..'f': Result := Ord(c) - 87;
      'A'..'F': Result := Ord(c) - 55;
      else Result := -1;
    end;
  end;

begin
  Result := '';
  i := 1;
  while i <= Length(S) do
  begin
    if S[i] = '_' then Result := Result + ' '
    else if (S[i] = '=') and (i + 2 <= Length(S)) then
    begin
      hi := HexV(S[i + 1]);
      lo := HexV(S[i + 2]);
      if (hi >= 0) and (lo >= 0) then
      begin
        Result := Result + Chr(hi * 16 + lo);
        Inc(i, 2);
      end
      else
        Result := Result + S[i];
    end
    else
      Result := Result + S[i];
    Inc(i);
  end;
end;

function Latin1ToUtf8(const S: string): string;
var
  i: Integer;
  b: Byte;
begin
  Result := '';
  for i := 1 to Length(S) do
  begin
    b := Ord(S[i]);
    if b < 128 then Result := Result + S[i]
    else Result := Result + Chr($C0 or (b shr 6)) + Chr($80 or (b and $3F));
  end;
end;

function DecodeMimeWords(const V: string): string;
var
  i, q1, q2, q3, q4: Integer;
  cs, enc, data, dec: string;
  ok: Boolean;
begin
  Result := '';
  i := 1;
  while i <= Length(V) do
  begin
    ok := False;
    if (V[i] = '=') and (i + 1 <= Length(V)) and (V[i + 1] = '?') then
    begin
      // =?charset?B|Q?data?=   (RFC 2047)
      q1 := i + 2;
      q2 := q1;
      while (q2 <= Length(V)) and (V[q2] <> '?') and (q2 - q1 < 40) do Inc(q2);
      if (q2 <= Length(V)) and (V[q2] = '?') and (q2 + 1 <= Length(V)) then
      begin
        q3 := q2 + 2;
        if (q3 <= Length(V)) and (V[q3] = '?') then
        begin
          q4 := q3 + 1;
          while (q4 + 1 <= Length(V)) and
                not ((V[q4] = '?') and (V[q4 + 1] = '=')) and
                (q4 - q3 < 4096) do
            Inc(q4);
          if (q4 + 1 <= Length(V)) and (V[q4] = '?') and (V[q4 + 1] = '=') then
          begin
            cs := LowerCase(Copy(V, q1, q2 - q1));
            enc := LowerCase(V[q2 + 1]);
            data := Copy(V, q3 + 1, q4 - q3 - 1);
            if enc = 'b' then dec := B64d(data)
            else if enc = 'q' then dec := QPd(data)
            else dec := '';
            if dec <> '' then
            begin
              if (Pos('8859', cs) > 0) or (Pos('1252', cs) > 0) then
                dec := Latin1ToUtf8(dec);
              Result := Result + dec;
              i := q4 + 2;
              // l'espace entre deux encoded-words consecutifs se jette (RFC 2047)
              q1 := i;
              while (q1 <= Length(V)) and (V[q1] = ' ') do Inc(q1);
              if (q1 + 1 <= Length(V)) and (V[q1] = '=') and (V[q1 + 1] = '?') then
                i := q1;
              ok := True;
            end;
          end;
        end;
      end;
    end;
    if not ok then
    begin
      Result := Result + V[i];
      Inc(i);
    end;
  end;
  Result := CleanCtl(Result);
end;

{ ---- decoupage de la zone d'en-tetes ---- }

procedure SplitHeaders(const S: string; var H: array of THeader; out N: Integer);
var
  i, L, ls, le, p: Integer;
  line: string;
  started: Boolean;
begin
  N := 0;
  L := Length(S);
  if L > MT_MAX_BYTES then L := MT_MAX_BYTES;
  i := 1;
  started := False;
  while i <= L do
  begin
    ls := i;
    while (i <= L) and (S[i] <> #10) and (S[i] <> #13) do Inc(i);
    le := i;
    if (i <= L) and (S[i] = #13) then Inc(i);
    if (i <= L) and (S[i] = #10) then Inc(i);
    line := Copy(S, ls, le - ls);
    if Trim(line) = '' then
    begin
      if started then Break;   // un Received forge dans le CORPS n'est jamais lu
      Continue;
    end;
    started := True;
    if (line[1] in [' ', #9]) then
    begin
      // re-capper APRES l'ajout : une ligne repliee peut etre enorme
      if (N > 0) and (Length(H[N - 1].Value) < MAX_HDR_LEN) then
      begin
        H[N - 1].Value := H[N - 1].Value + ' ' + Trim(CleanCtl(line));
        if Length(H[N - 1].Value) > MAX_HDR_LEN then
          SetLength(H[N - 1].Value, MAX_HDR_LEN);
      end;
      Continue;
    end;
    p := Pos(':', line);
    if p <= 1 then Continue;   // separateur mbox 'From ...' et bruit
    if N >= MAX_HEADERS then Break;
    H[N].Name := LowerCase(Trim(Copy(line, 1, p - 1)));
    H[N].Value := Trim(CleanCtl(Copy(line, p + 1, MaxInt)));
    if Length(H[N].Value) > MAX_HDR_LEN then
      SetLength(H[N].Value, MAX_HDR_LEN);
    Inc(N);
  end;
end;

{ ---- date RFC 5322 (+ variante asctime), zones usuelles ---- }

function ZoneMin(const W: string): Integer;
var
  u: string;
begin
  u := UpperCase(W);
  Result := 0;
  if (u = 'GMT') or (u = 'UT') or (u = 'UTC') then Exit;
  if u = 'EST' then Exit(-300);
  if u = 'EDT' then Exit(-240);
  if u = 'CST' then Exit(-360);
  if u = 'CDT' then Exit(-300);
  if u = 'MST' then Exit(-420);
  if u = 'MDT' then Exit(-360);
  if u = 'PST' then Exit(-480);
  if u = 'PDT' then Exit(-420);
  if u = 'CET' then Exit(60);
  if u = 'CEST' then Exit(120);
end;

function ParseDate822(const DS: string; out UTC: TDateTime): Boolean;
var
  i, L, day, mon, yr, hh, nn, ss, zmin, sgn: Integer;
  dt: TDateTime;
  w: string;

  procedure SkipSp;
  begin
    while (i <= L) and (DS[i] in [' ', #9]) do Inc(i);
  end;

  function ReadNum: Integer;
  var
    v, n: Integer;
  begin
    v := 0;
    n := 0;
    while (i <= L) and IsDig(DS[i]) and (n < 6) do
    begin
      v := v * 10 + Ord(DS[i]) - Ord('0');
      Inc(i);
      Inc(n);
    end;
    if n = 0 then Result := -1 else Result := v;
  end;

  function ReadAlpha: string;
  var
    st: Integer;
  begin
    st := i;
    while (i <= L) and IsAlphaC(DS[i]) and (i - st < 12) do Inc(i);
    Result := Copy(DS, st, i - st);
  end;

  function ReadTime: Boolean;
  begin
    Result := False;
    hh := ReadNum;
    if (hh < 0) or (i > L) or (DS[i] <> ':') then Exit;
    Inc(i);
    nn := ReadNum;
    if nn < 0 then Exit;
    ss := 0;
    if (i <= L) and (DS[i] = ':') then
    begin
      Inc(i);
      ss := ReadNum;
      if ss < 0 then Exit;
    end;
    Result := True;
  end;

begin
  Result := False;
  UTC := 0;
  i := 1;
  L := Length(DS);
  SkipSp;
  if (i <= L) and IsAlphaC(DS[i]) then
  begin
    w := ReadAlpha;
    SkipSp;
    if (i <= L) and (DS[i] = ',') then Inc(i);
    SkipSp;
  end;
  zmin := 0;
  sgn := 1;
  if (i <= L) and IsAlphaC(DS[i]) then
  begin
    // asctime 'Mmm d hh:mm:ss yyyy' : pas de zone, UTC suppose
    mon := MonthOf3(ReadAlpha);
    SkipSp;
    day := ReadNum;
    SkipSp;
    if not ReadTime then Exit;
    SkipSp;
    yr := ReadNum;
  end
  else
  begin
    day := ReadNum;
    SkipSp;
    mon := MonthOf3(ReadAlpha);
    SkipSp;
    yr := ReadNum;
    SkipSp;
    if not ReadTime then Exit;
    SkipSp;
    if (i <= L) and (DS[i] in ['+', '-']) then
    begin
      if DS[i] = '-' then sgn := -1;
      Inc(i);
      zmin := ReadNum;
      if zmin < 0 then zmin := 0
      else zmin := (zmin div 100) * 60 + (zmin mod 100);
    end
    else if (i <= L) and IsAlphaC(DS[i]) then
    begin
      zmin := ZoneMin(ReadAlpha);
      if zmin < 0 then
      begin
        sgn := -1;
        zmin := -zmin;
      end;
    end;
  end;
  if yr < 0 then Exit;
  if yr < 100 then
    if yr < 50 then Inc(yr, 2000) else Inc(yr, 1900);
  if (yr < 1970) or (yr > 2200) or (mon < 1) or (day < 1) then Exit;
  if not TryEncodeDateTime(yr, mon, day, hh, nn, ss, 0, dt) then Exit;
  UTC := dt - sgn * zmin / (24 * 60);
  Result := True;
end;

{ ---- parse d'un Received ---- }

function IPish(const T: string): Boolean;
var
  i, d, c: Integer;
begin
  Result := False;
  if (T = '') or (Length(T) > 45) then Exit;
  d := 0;
  c := 0;
  for i := 1 to Length(T) do
    case T[i] of
      '0'..'9', 'a'..'f', 'A'..'F': ;
      '.': Inc(d);
      ':': Inc(c);
      '%': ;
      else Exit;
    end;
  Result := (d = 3) or (c >= 2);
end;

function ExtractBrIP(const C: string): string;
var
  i, j: Integer;
  t: string;
begin
  Result := '';
  i := 1;
  while i <= Length(C) do
  begin
    if C[i] = '[' then
    begin
      j := i + 1;
      while (j <= Length(C)) and (C[j] <> ']') and (j - i <= 48) do Inc(j);
      if (j <= Length(C)) and (C[j] = ']') then
      begin
        t := Copy(C, i + 1, j - i - 1);
        if LowerCase(Copy(t, 1, 5)) = 'ipv6:' then Delete(t, 1, 5);
        if IPish(t) then Exit(t);
        i := j;
      end;
    end;
    Inc(i);
  end;
end;

function HostChars(const T: string): Boolean;
var
  i: Integer;
begin
  Result := False;
  if T = '' then Exit;
  for i := 1 to Length(T) do
    if not (T[i] in ['A'..'Z', 'a'..'z', '0'..'9', '.', '-', '_']) then Exit;
  Result := True;
end;

function FirstHostAtom(const C: string): string;
var
  i, j: Integer;
  t: string;
begin
  Result := '';
  i := 1;
  while i <= Length(C) do
  begin
    if not (C[i] in [' ', ',', '(', ')', '[', ']']) then
    begin
      j := i;
      while (j <= Length(C)) and not (C[j] in [' ', ',', '(', ')', '[', ']']) do
        Inc(j);
      t := Copy(C, i, j - i);
      while (t <> '') and (t[Length(t)] = '.') do
        SetLength(t, Length(t) - 1);   // rdns Postfix a point final
      if (Pos('.', t) > 1) and HostChars(t) and not IPish(t) then
        Exit(CapStr(t, 80));           // une IP n'est pas un rdns
      i := j;
    end
    else
      Inc(i);
  end;
end;

// IP sans crochets dans un commentaire (Exchange, Zimbra LHLO, Received forge)
function FirstIPAtom(const C: string): string;
var
  i, j: Integer;
  t: string;
begin
  Result := '';
  i := 1;
  while i <= Length(C) do
  begin
    if not (C[i] in [' ', ',', '(', ')', '[', ']']) then
    begin
      j := i;
      while (j <= Length(C)) and not (C[j] in [' ', ',', '(', ')', '[', ']']) do
        Inc(j);
      t := Copy(C, i, j - i);
      if IPish(t) then Exit(t);
      i := j;
    end
    else
      Inc(i);
  end;
end;

function ScanPort(const C: string): Integer;
var
  i, j, v: Integer;
begin
  Result := 0;
  i := 1;
  while i + 3 <= Length(C) do
  begin
    if ((i = 1) or not IsAlnumC(C[i - 1])) and
       (LowerCase(Copy(C, i, 4)) = 'port') and
       ((i + 4 > Length(C)) or not IsAlphaC(C[i + 4])) then
    begin
      j := i + 4;
      while (j <= Length(C)) and (C[j] in [' ', '=', ':']) do Inc(j);
      v := 0;
      while (j <= Length(C)) and IsDig(C[j]) and (v <= 65535) do
      begin
        v := v * 10 + Ord(C[j]) - Ord('0');
        Inc(j);
      end;
      if (v > 0) and (v <= 65535) then Exit(v);
      i := j;
    end
    else
      Inc(i);
  end;
end;

function TidyHost(const S: string): string;
var
  t: string;
begin
  t := Trim(CleanCtl(S));
  while (t <> '') and (t[Length(t)] in ['.', ';', ',']) do
    SetLength(t, Length(t) - 1);
  Result := CapStr(t, 80);
end;

function TidyAddr(const S: string): string;
var
  t: string;
begin
  t := Trim(CleanCtl(S));
  if (t <> '') and (t[1] = '<') then Delete(t, 1, 1);
  while (t <> '') and (t[Length(t)] in ['>', ';', ',']) do
    SetLength(t, Length(t) - 1);
  Result := CapStr(t, 80);
end;

function ParseReceived(const V: string; out H: THop): Boolean;
var
  i, L, protoWords: Integer;
  key, atom, cmt, la, ip, datestr: string;

  procedure SkipWS;
  begin
    while (i <= L) and (V[i] = ' ') do Inc(i);
  end;

  function ReadComment: string;
  var
    st, depth: Integer;
  begin
    st := i + 1;
    depth := 0;
    while i <= L do
    begin
      if V[i] = '(' then
      begin
        Inc(depth);
        if depth > 32 then Break;   // parentheses hostiles
      end
      else if V[i] = ')' then
      begin
        Dec(depth);
        if depth = 0 then
        begin
          Result := Copy(V, st, i - st);
          Inc(i);
          Exit;
        end;
      end;
      Inc(i);
    end;
    Result := Copy(V, st, L - st + 1);
    i := L + 1;
  end;

  function ReadAtom: string;
  var
    st: Integer;
  begin
    st := i;
    while (i <= L) and not (V[i] in [' ', '(', ';']) do Inc(i);
    Result := Copy(V, st, i - st);
  end;

begin
  H := Default(THop);
  H.Raw := TidyStr(V, 120);
  i := 1;
  L := Length(V);
  key := '';
  protoWords := 0;
  while i <= L do
  begin
    SkipWS;
    if i > L then Break;
    if V[i] = '(' then
    begin
      cmt := ReadComment;
      if H.Port = 0 then H.Port := ScanPort(cmt);
      if key = 'from' then
      begin
        if H.FromIP = '' then H.FromIP := ExtractBrIP(cmt);
        if H.FromIP = '' then H.FromIP := FirstIPAtom(cmt);
        if H.FromRdns = '' then H.FromRdns := FirstHostAtom(cmt);
        if H.FromName = '' then H.FromName := H.FromRdns;
      end
      else if key = 'by' then
      begin
        ip := ExtractBrIP(cmt);
        if ip = '' then ip := FirstIPAtom(cmt);
        if ip <> '' then
        begin
          if H.ByIP = '' then H.ByIP := ip;
          if H.ByAlias = '' then
          begin
            la := FirstHostAtom(cmt);
            if la <> ip then H.ByAlias := la;
          end;
        end
        else if H.Software = '' then
          H.Software := TidyStr(cmt, 48);
      end
      else if (key = 'with') and (H.Software = '') then
        H.Software := TidyStr(cmt, 48);
    end
    else if V[i] = ';' then
    begin
      Inc(i);
      datestr := '';
      while (i <= L) and (Length(datestr) < 128) do
        if V[i] = '(' then ReadComment
        else
        begin
          datestr := datestr + V[i];
          Inc(i);
        end;
      H.HasDate := ParseDate822(Trim(datestr), H.UTC);
      Break;
    end
    else
    begin
      atom := ReadAtom;
      if atom = '' then
      begin
        Inc(i);
        Continue;
      end;
      la := LowerCase(atom);
      if (la = 'from') or (la = 'by') or (la = 'with') or (la = 'id') or
         (la = 'for') or (la = 'via') then
        key := la
      else if (key = 'from') and (H.FromName = '') and (H.FromIP = '') then
      begin
        if atom[1] = '[' then H.FromIP := ExtractBrIP(atom)
        else H.FromName := TidyHost(atom);
      end
      else if (key = 'by') and (H.ByName = '') then
        H.ByName := TidyHost(atom)
      else if (key = 'with') and (H.Proto = '') then
      begin
        H.Proto := TidyStr(atom, 24);
        protoWords := 1;
      end
      else if (key = 'with') and (protoWords > 0) and (protoWords < 4) and
              (Length(H.Proto) < 30) then
      begin
        // proto multi-mots : 'with Microsoft SMTP Server'
        H.Proto := H.Proto + ' ' + TidyStr(atom, 24);
        Inc(protoWords);
      end
      else if (key = 'id') and (H.QueueId = '') then
        H.QueueId := TidyStr(atom, 40)
      else if (key = 'for') and (H.ForAddr = '') then
        H.ForAddr := TidyAddr(atom);
    end;
  end;
  H.Parsed := (H.ByName <> '') or (H.ByAlias <> '') or
              (H.FromName <> '') or (H.FromIP <> '');
  Result := H.Parsed;
end;

{ ---- dictionnaire des regles antispam courantes ---- }

type
  TRuleDesc = record
    N, D: string;
  end;

const
  RX: array[0..58] of TRuleDesc = (
    (N: 'ALL_TRUSTED'; D: 'only crossed hops configured as trusted (strong ham sign)'),
    (N: 'ASN'; D: 'origin AS number recorded (info only)'),
    (N: 'BAYES_00'; D: 'Bayes: 0-1% spam probability (learned as ham)'),
    (N: 'BAYES_50'; D: 'Bayes: 40-60%, the classifier has no opinion'),
    (N: 'BAYES_99'; D: 'Bayes: 99-100% spam probability (learned as spam)'),
    (N: 'BAYES_999'; D: 'Bayes: >99.9% spam probability, stacks on BAYES_99'),
    (N: 'DCC_CHECK'; D: 'DCC says this body was seen in bulk'),
    (N: 'DKIM_INVALID'; D: 'DKIM signature present but fails verification'),
    (N: 'DKIM_SIGNED'; D: 'has a DKIM signature (says nothing about validity)'),
    (N: 'DKIM_VALID'; D: 'DKIM signature verifies'),
    (N: 'DKIM_VALID_AU'; D: 'DKIM valid and d= matches the From domain'),
    (N: 'DKIM_VALID_EF'; D: 'DKIM valid and d= matches the envelope-from'),
    (N: 'FREEMAIL_FROM'; D: 'From uses a free mail provider'),
    (N: 'FREEMAIL_REPLYTO'; D: 'Reply-To is a freemail and From is not (scam shape)'),
    (N: 'GREYLIST'; D: 'greylisting was applied'),
    (N: 'HEADER_FROM_DIFFERENT_DOMAINS'; D: 'From: domain differs from envelope sender (mailing lists do this, so do spoofers)'),
    (N: 'HTML_FONT_LOW_CONTRAST'; D: 'text color blends into the background (hidden text trick)'),
    (N: 'HTML_MESSAGE'; D: 'contains an HTML part (nearly all mail does)'),
    (N: 'INVALID_MSGID'; D: 'Message-ID is malformed'),
    (N: 'LOTS_OF_MONEY'; D: 'mentions a large sum of money (419 flavor)'),
    (N: 'MANY_INVISIBLE_PARTS'; D: 'lots of invisible content in the body'),
    (N: 'MID_RHS_MATCH_FROM'; D: 'Message-ID domain matches From domain (normal)'),
    (N: 'MIME_GOOD'; D: 'MIME structure looks normal (lowers score)'),
    (N: 'MIME_HTML_ONLY'; D: 'HTML with no plain-text alternative'),
    (N: 'MISSING_DATE'; D: 'no Date header'),
    (N: 'MISSING_HEADERS'; D: 'missing standard headers (usually To:)'),
    (N: 'MISSING_MID'; D: 'no Message-ID header'),
    (N: 'MISSING_SUBJECT'; D: 'no Subject header'),
    (N: 'MPART_ALT_DIFF'; D: 'text and HTML parts tell different stories'),
    (N: 'NEURAL_HAM'; D: 'rspamd neural network says ham'),
    (N: 'NEURAL_SPAM'; D: 'rspamd neural network says spam'),
    (N: 'NO_RELAYS'; D: 'never crossed a network (local injection)'),
    (N: 'ONCE_RECEIVED'; D: 'single Received, direct-to-MX delivery (bot pattern)'),
    (N: 'PREVIOUSLY_DELIVERED'; D: 'recipient already got mail from this sender'),
    (N: 'PYZOR_CHECK'; D: 'body fingerprint listed in Pyzor (collaborative db)'),
    (N: 'RAZOR2_CHECK'; D: 'body fingerprint listed in Razor2 (collaborative db)'),
    (N: 'RCVD_IN_BL_SPAMCOP_NET'; D: 'sender IP listed at SpamCop'),
    (N: 'RCVD_IN_DNSWL_HI'; D: 'sender IP strongly allowlisted at dnswl.org'),
    (N: 'RCVD_IN_DNSWL_LOW'; D: 'sender IP allowlisted at dnswl.org (low trust)'),
    (N: 'RCVD_IN_DNSWL_MED'; D: 'sender IP allowlisted at dnswl.org (medium trust)'),
    (N: 'RCVD_IN_DNSWL_NONE'; D: 'sender IP known to dnswl.org, neutral'),
    (N: 'RCVD_IN_MSPIKE_BL'; D: 'sender IP blocklisted at Mailspike'),
    (N: 'RCVD_IN_PBL'; D: 'sender IP in Spamhaus PBL (residential pool, should not send direct)'),
    (N: 'RCVD_IN_SBL'; D: 'sender IP in Spamhaus SBL (known spam source)'),
    (N: 'RCVD_IN_XBL'; D: 'sender IP in Spamhaus XBL (exploited/infected host)'),
    (N: 'RCVD_TLS_ALL'; D: 'every hop used TLS'),
    (N: 'RCVD_TLS_LAST'; D: 'last hop used TLS'),
    (N: 'RDNS_DYNAMIC'; D: 'reverse DNS looks like a dynamic/residential pool'),
    (N: 'RDNS_NONE'; D: 'sender IP has no reverse DNS'),
    (N: 'REPLY'; D: 'looks like a reply to mail you sent (lowers score)'),
    (N: 'SIGNED_PGP'; D: 'PGP signed'),
    (N: 'SPF_FAIL'; D: 'sender IP rejected by the domain SPF record'),
    (N: 'SPF_NEUTRAL'; D: 'SPF neutral (?all), record says nothing useful'),
    (N: 'SPF_NONE'; D: 'domain publishes no SPF record'),
    (N: 'SPF_PASS'; D: 'sender IP allowed by the domain SPF record'),
    (N: 'SPF_SOFTFAIL'; D: 'SPF soft fail (~all), suspicious but not rejected'),
    (N: 'SUBJ_ALL_CAPS'; D: 'subject is all capitals'),
    (N: 'UNPARSEABLE_RELAY'; D: 'a Received header could not be parsed (broken or forged MTA)'),
    (N: 'ZERO_FONT'; D: 'zero-size or invisible text in the body')
  );

  // prefixes, matche le plus long
  PX: array[0..30] of TRuleDesc = (
    (N: 'ADVANCE_FEE_'; D: 'advance-fee fraud wording pattern'),
    (N: 'ARC_'; D: 'ARC chain evaluation (forwarded-mail authentication)'),
    (N: 'BAYES_'; D: 'Bayes classifier probability bucket (suffix = % spam)'),
    (N: 'CHARSET_'; D: 'unusual character set for your locale'),
    (N: 'DATE_IN_FUTURE'; D: 'Date header is in the future vs receive time'),
    (N: 'DATE_IN_PAST'; D: 'Date header is far in the past vs receive time'),
    (N: 'DKIM_'; D: 'DKIM signature check (suffix = result)'),
    (N: 'DMARC_'; D: 'DMARC policy evaluation (suffix = result)'),
    (N: 'FORGED_'; D: 'a header looks forged (suffix says which)'),
    (N: 'FREEMAIL_'; D: 'free mail provider heuristic'),
    (N: 'FROM_'; D: 'From header shape heuristic'),
    (N: 'HELO_'; D: 'HELO name looks wrong (dynamic, bare IP, mismatch)'),
    (N: 'HFILTER_'; D: 'rspamd host/HELO/URL hygiene check'),
    (N: 'HTML_IMAGE_'; D: 'mostly images with little or no text'),
    (N: 'HTML_'; D: 'HTML body pattern (suffix says which)'),
    (N: 'KAM_'; D: 'KAM third-party ruleset (policy patterns)'),
    (N: 'MIME_'; D: 'MIME structure pattern (suffix says which)'),
    (N: 'MONEY_'; D: 'money-related wording pattern'),
    (N: 'RAZOR2_'; D: 'Razor2 collaborative filter signal'),
    (N: 'RCVD_COUNT_'; D: 'number of relay hops bucket'),
    (N: 'RCVD_IN_MSPIKE_H'; D: 'sender IP has good reputation at Mailspike'),
    (N: 'RCVD_IN_VALIDITY_'; D: 'Validity/Return Path reputation data'),
    (N: 'RCVD_IN_'; D: 'sender IP found in a DNS block/allow list (suffix = which)'),
    (N: 'R_DKIM_'; D: 'rspamd DKIM result (suffix = result)'),
    (N: 'R_SPF_'; D: 'rspamd SPF result (suffix = result)'),
    (N: 'SPF_HELO_'; D: 'SPF check on the HELO name (suffix = result)'),
    (N: 'SPOOF_'; D: 'sender identity looks spoofed'),
    (N: 'SUBJECT_'; D: 'subject shape heuristic'),
    (N: 'SUBJ_'; D: 'subject shape heuristic'),
    (N: 'TVD_'; D: 'TVD pattern family (often phishing/image spam shapes)'),
    (N: 'URIBL_'; D: 'a URL in the body is in a URI blocklist (suffix = which)')
  );

function RuleDesc(const AName: string): string;
var
  u: string;
  i, best, bl: Integer;
begin
  u := UpperCase(AName);
  if u = 'URIBL_BLOCKED' then
    Exit('URIBL query refused (resolver over quota), rule gave NO signal; use a local resolver');
  for i := Low(RX) to High(RX) do
    if RX[i].N = u then Exit(RX[i].D);
  best := -1;
  bl := 0;
  for i := Low(PX) to High(PX) do
    if (Length(PX[i].N) > bl) and (Copy(u, 1, Length(PX[i].N)) = PX[i].N) then
    begin
      best := i;
      bl := Length(PX[i].N);
    end;
  if best >= 0 then Exit(PX[best].D);
  if Copy(u, 1, 2) = 'T_' then
  begin
    Result := RuleDesc(Copy(u, 3, MaxInt));
    if Result = '' then Result := 'test-phase rule, negligible score'
    else Result := Result + ' (test-phase rule)';
    Exit;
  end;
  Result := '';
end;

{ ---- en-tetes antispam ---- }

function ScanFloat(const V: string; var idx: Integer; out Num: Double): Boolean;
var
  L: Integer;
  neg: Boolean;
  frac, fd: Double;
begin
  Result := False;
  Num := 0;
  L := Length(V);
  while (idx <= L) and (V[idx] = ' ') do Inc(idx);
  neg := False;
  if (idx <= L) and (V[idx] in ['-', '+']) then
  begin
    neg := V[idx] = '-';
    Inc(idx);
  end;
  if (idx > L) or not IsDig(V[idx]) then Exit;
  while (idx <= L) and IsDig(V[idx]) do
  begin
    Num := Num * 10 + (Ord(V[idx]) - Ord('0'));
    Inc(idx);
  end;
  frac := 0;
  fd := 1;
  if (idx <= L) and (V[idx] = '.') then
  begin
    Inc(idx);
    while (idx <= L) and IsDig(V[idx]) do
    begin
      fd := fd / 10;
      frac := frac + (Ord(V[idx]) - Ord('0')) * fd;
      Inc(idx);
    end;
  end;
  Num := Num + frac;
  if neg then Num := -Num;
  Result := True;
end;

function FindKeyNum(const V, AKey: string; out Num: Double): Boolean;
var
  i: Integer;
begin
  Result := False;
  Num := 0;
  i := Pos(LowerCase(AKey) + '=', LowerCase(V));
  if i = 0 then Exit;
  i := i + Length(AKey) + 1;
  Result := ScanFloat(V, i, Num);
end;

procedure AddRule(var R: array of TRule; var N: Integer; const AName: string;
  AScore: Double; AHas: Boolean);
begin
  if (N >= MAX_RULES) or (AName = '') or (Length(AName) > 60) then Exit;
  R[N].Name := UpperCase(AName);
  R[N].Score := AScore;
  R[N].HasScore := AHas;
  Inc(N);
end;

// 'No, score=2.1 required=5.0 tests=A,B=1.2' ; amavis: 'tests=[A=1.2, B=0.5]'
procedure ParseSpamStatus(const V: string; out IsSpam: Boolean;
  out Score, Req: Double; out HasScore: Boolean;
  var R: array of TRule; var NR: Integer);
var
  i, j, L: Integer;
  lst, item, nm: string;
  sc: Double;
  hs: Boolean;
  p: Integer;
begin
  IsSpam := LowerCase(Copy(Trim(V), 1, 3)) = 'yes';
  HasScore := FindKeyNum(V, 'score', Score);
  if not FindKeyNum(V, 'required', Req) then Req := 0;
  L := Length(V);
  i := Pos('tests=', LowerCase(V));
  if i = 0 then Exit;
  i := i + 6;
  lst := '';
  if (i <= L) and (V[i] = '[') then
  begin
    Inc(i);
    while (i <= L) and (V[i] <> ']') and (Length(lst) < 8192) do
    begin
      lst := lst + V[i];
      Inc(i);
    end;
  end
  else
  begin
    // liste nue, l'espace ne termine que s'il ne suit pas une virgule
    while (i <= L) and (Length(lst) < 8192) do
    begin
      if V[i] = ' ' then
      begin
        if (lst = '') or (lst[Length(lst)] <> ',') then Break;
      end
      else
        lst := lst + V[i];
      Inc(i);
    end;
  end;
  i := 1;
  while i <= Length(lst) do
  begin
    j := i;
    while (j <= Length(lst)) and (lst[j] <> ',') do Inc(j);
    item := Trim(Copy(lst, i, j - i));
    i := j + 1;
    if item = '' then Continue;
    p := Pos('=', item);
    hs := False;
    sc := 0;
    if p > 1 then
    begin
      nm := Copy(item, 1, p - 1);
      Inc(p);
      hs := ScanFloat(item, p, sc);
    end
    else
      nm := item;
    AddRule(R, NR, TidyStr(nm, 60), sc, hs);
  end;
end;



// X-Spamd-Result: 'default: False [2.10 / 15.00]; SYM(1.20)[detail]; ...'
procedure ParseSpamdResult(const V: string; out IsSpam: Boolean;
  out Score, Req: Double; out HasScore: Boolean;
  var R: array of TRule; var NR: Integer);
var
  i, j, L: Integer;
  seg, nm, head: string;
  sc: Double;
  hs: Boolean;
begin
  HasScore := False;
  Score := 0;
  Req := 0;
  L := Length(V);
  i := Pos('[', V);
  if i > 0 then head := Copy(V, 1, i) else head := V;
  IsSpam := Pos('true', LowerCase(head)) > 0;
  if i > 0 then
  begin
    Inc(i);
    if ScanFloat(V, i, Score) then
    begin
      HasScore := True;
      while (i <= L) and (V[i] in [' ', '/']) do Inc(i);
      ScanFloat(V, i, Req);
    end;
  end;
  // symboles apres le 1er ';'
  i := Pos(';', V);
  if i = 0 then Exit;
  Inc(i);
  while i <= L do
  begin
    j := i;
    while (j <= L) and (V[j] <> ';') do Inc(j);
    seg := Trim(Copy(V, i, j - i));
    i := j + 1;
    if seg = '' then Continue;
    j := 1;
    while (j <= Length(seg)) and
          (seg[j] in ['A'..'Z', 'a'..'z', '0'..'9', '_']) do
      Inc(j);
    nm := Copy(seg, 1, j - 1);
    hs := False;
    sc := 0;
    if (j <= Length(seg)) and (seg[j] = '(') then
    begin
      Inc(j);
      hs := ScanFloat(seg, j, sc);
    end;
    if nm <> '' then AddRule(R, NR, TidyStr(nm, 60), sc, hs);
  end;
end;

// sinon le detail forwarde 'arc=pass (... dmarc=pass ...)' masque le vrai verdict
function StripComments(const S: string): string;
var
  i, depth: Integer;
begin
  Result := '';
  depth := 0;
  for i := 1 to Length(S) do
    if S[i] = '(' then Inc(depth)
    else if S[i] = ')' then
    begin
      if depth > 0 then Dec(depth);
    end
    else if depth = 0 then
      Result := Result + S[i];
end;

function AuthSummary(const AV: string): string;
var
  V, lv, w: string;
  i, j: Integer;

  function GrabAfter(const AKey: string): string;
  var
    p, q: Integer;
  begin
    Result := '';
    p := Pos(AKey, lv);
    if p = 0 then Exit;
    if (p > 1) and IsAlnumC(lv[p - 1]) then Exit;
    q := p + Length(AKey);
    while (q <= Length(V)) and
          (V[q] in ['A'..'Z', 'a'..'z', '0'..'9', '.', '-', '_']) do
      Inc(q);
    Result := Copy(V, p + Length(AKey), q - p - Length(AKey));
  end;

begin
  Result := '';
  V := StripComments(Copy(AV, 1, 8192));
  lv := LowerCase(V);
  w := GrabAfter('spf=');
  if w <> '' then Result := Result + 'spf=' + w + '  ';
  w := GrabAfter('dkim=');
  if w <> '' then
  begin
    Result := Result + 'dkim=' + w;
    w := GrabAfter('header.d=');
    if w <> '' then Result := Result + ' (d=' + w + ')';
    Result := Result + '  ';
  end;
  w := GrabAfter('dmarc=');
  if w <> '' then Result := Result + 'dmarc=' + w + '  ';
  w := GrabAfter('arc=');
  if w <> '' then Result := Result + 'arc=' + w + '  ';
  Result := TidyStr(Result, 120);
  if Result <> '' then
  begin
    // authserv-id = 1er token avant ';'
    i := Pos(';', V);
    if i > 1 then
    begin
      w := Trim(Copy(V, 1, i - 1));
      j := Pos(' ', w);
      if j > 0 then w := Copy(w, 1, j - 1);
      if HostChars(w) and (w <> '') then
        Result := Result + '  (as claimed by ' + CapStr(w, 60) + ')';
    end;
  end;
end;

{ ---- groupement en boxes + rendu ---- }

function NormHost(const S: string): string;
var
  t: string;
begin
  t := LowerCase(Trim(S));
  while (t <> '') and (t[Length(t)] = '.') do SetLength(t, Length(t) - 1);
  Result := t;
end;

function IsLoopIP(const S: string): Boolean;
begin
  Result := (Copy(S, 1, 4) = '127.') or (S = '::1');
end;

function ZoneStrip(const S: string): string;
var
  p: Integer;
begin
  p := Pos('%', S);
  if p > 0 then Result := Copy(S, 1, p - 1)
  else Result := S;
end;

function IsLocalName(const S: string): Boolean;
var
  n: string;
begin
  n := NormHost(S);
  Result := (n = 'localhost') or (n = 'localhost.localdomain');
end;

function FmtDelta(secs: Int64): string;
var
  a: Int64;
  sign: string;
begin
  if secs < 0 then
  begin
    sign := '-';
    a := -secs;
  end
  else
  begin
    sign := '+';
    a := secs;
  end;
  if a < 60 then Result := Format('%s%ds', [sign, a])
  else if a < 3600 then Result := Format('%s%dm%.2ds', [sign, a div 60, a mod 60])
  else if a < 86400 then
    Result := Format('%s%dh%.2dm', [sign, a div 3600, (a mod 3600) div 60])
  else
    Result := Format('%s%dd%.2dh', [sign, a div 86400, (a mod 86400) div 3600]);
  if secs < 0 then Result := Result + ' (clock skew?)';
end;

function HopDelta(const A, B: THop): string;
var
  secs: Int64;
begin
  Result := '';
  if not (A.HasDate and B.HasDate) then Exit;
  secs := Round((B.UTC - A.UTC) * 86400.0);
  Result := FmtDelta(secs);
end;

procedure StepLines(const H: THop; SB: TStringList);
var
  parts: array[0..4] of string;
  np, i: Integer;
  line, tok: string;
begin
  np := 0;
  if H.Port > 0 then
  begin
    parts[np] := ':' + IntToStr(H.Port);
    Inc(np);
  end;
  if H.Proto <> '' then
  begin
    parts[np] := LowerCase(H.Proto);
    Inc(np);
  end;
  if H.QueueId <> '' then
  begin
    parts[np] := 'id ' + H.QueueId;
    Inc(np);
  end;
  if H.Software <> '' then
  begin
    parts[np] := '(' + H.Software + ')';
    Inc(np);
  end;
  if H.ForAddr <> '' then
  begin
    parts[np] := 'for ' + H.ForAddr;
    Inc(np);
  end;
  if np = 0 then
  begin
    SB.Add('  (no detail)');
    Exit;
  end;
  line := ' ';
  for i := 0 to np - 1 do
  begin
    tok := parts[i];
    if (Length(line) + Length(tok) + 2 > 62) and (line <> ' ') then
    begin
      SB.Add(line);
      line := '     ';
    end;
    line := line + ' ' + tok;
  end;
  if Trim(line) <> '' then SB.Add(line);
end;

function MailTraceReport(const S: string): string;
var
  hdrs: array[0..MAX_HEADERS - 1] of THeader;
  nhd: Integer;
  hops: array of THop;
  nhops, skippedHops, unparsed, i, j, k, nb, nbb, w: Integer;
  bx: array of TBox;
  content: array of TStringList;
  bdel: array of string;
  fp: array[0..2] of string;
  nfp: Integer;
  mergeOrigin: Boolean;
  rules: array[0..MAX_RULES - 1] of TRule;
  nr: Integer;
  rep: TStringList;
  h: THop;
  eff, t, d, auth, virus, vName, vSrc: string;
  isSpam, hasScore, haveVerdict: Boolean;
  score, req: Double;
  tmpR: TRule;
  totSecs: Int64;
  firstDated, lastDated: Integer;

  function HeaderVal(const AName: string): string;
  var
    x: Integer;
  begin
    Result := '';
    for x := 0 to nhd - 1 do
      if hdrs[x].Name = AName then Exit(hdrs[x].Value);
  end;

  procedure InfoLine(const ALabel, AVal: string; ADecode: Boolean);
  var
    v: string;
  begin
    if AVal = '' then Exit;
    if ADecode then v := DecodeMimeWords(Copy(AVal, 1, 2048)) else v := AVal;
    rep.Add(Format('%-12s %s', [ALabel + ':', CapStr(v, 100)]));
  end;

  function EffName(const AH: THop): string;
  begin
    if IsLocalName(AH.ByName) and (AH.ByAlias <> '') then Result := AH.ByAlias
    else if AH.ByName <> '' then Result := AH.ByName
    else Result := AH.ByAlias;
  end;

begin
  Result := '';
  try
    SplitHeaders(S, hdrs, nhd);
    if nhd = 0 then Exit;

    // dans le fichier, les Received vont du plus recent au plus ancien
    SetLength(hops, MAX_HOPS);
    nhops := 0;
    skippedHops := 0;
    unparsed := 0;
    for i := 0 to nhd - 1 do
      if hdrs[i].Name = 'received' then
      begin
        if nhops >= MAX_HOPS then
        begin
          Inc(skippedHops);
          Continue;
        end;
        if ParseReceived(hdrs[i].Value, h) then
        begin
          hops[nhops] := h;
          Inc(nhops);
        end
        else
          Inc(unparsed);
      end;
    if nhops = 0 then Exit;

    for i := 0 to nhops div 2 - 1 do
    begin
      h := hops[i];
      hops[i] := hops[nhops - 1 - i];
      hops[nhops - 1 - i] := h;
    end;

    SetLength(bx, nhops);
    nb := 0;
    for i := 0 to nhops - 1 do
    begin
      eff := NormHost(EffName(hops[i]));
      if (nb > 0) and
         (((eff <> '') and (eff = bx[nb - 1].NormName)) or
          IsLoopIP(hops[i].FromIP) or IsLocalName(hops[i].FromName) or
          ((hops[i].ByIP <> '') and not IsLoopIP(hops[i].ByIP) and
           (hops[i].ByIP = bx[nb - 1].IP))) then
      begin
        bx[nb - 1].LastHop := i;
        if (bx[nb - 1].NormName = '') or IsLocalName(bx[nb - 1].DispName) then
          if (eff <> '') and not IsLocalName(eff) then
          begin
            bx[nb - 1].NormName := eff;
            bx[nb - 1].DispName := EffName(hops[i]);
          end;
        if (bx[nb - 1].IP = '') and (hops[i].ByIP <> '') and
           not IsLoopIP(hops[i].ByIP) then
          bx[nb - 1].IP := hops[i].ByIP;
      end
      else
      begin
        bx[nb].NormName := eff;
        bx[nb].DispName := EffName(hops[i]);
        if bx[nb].DispName = '' then bx[nb].DispName := '(unknown server)';
        if not IsLoopIP(hops[i].ByIP) then bx[nb].IP := hops[i].ByIP
        else bx[nb].IP := '';
        bx[nb].FirstHop := i;
        bx[nb].LastHop := i;
        Inc(nb);
      end;
    end;

    // ip reprise du hop suivant SEULEMENT si le nom colle: sinon on prendrait
    // l'ip d'une autre machine du pool de MX
    for k := 0 to nb - 1 do
      if (bx[k].IP = '') and (bx[k].LastHop + 1 < nhops) then
      begin
        i := bx[k].LastHop + 1;
        t := hops[i].FromIP;
        if (t <> '') and not IsLoopIP(t) and
           (NormHost(hops[i].FromName) <> '') and
           (NormHost(hops[i].FromName) = bx[k].NormName) then
          bx[k].IP := t;
      end;

    rep := TStringList.Create;
    try
      rep.Add(Format('=== Mail Trace: %d hop(s) through %d server(s) ===',
        [nhops, nb]));
      rep.Add('Received headers are self-reported: anything below your first');
      rep.Add('trusted hop can be forged. Server grouping is heuristic.');
      rep.Add('');
      InfoLine('From', HeaderVal('from'), True);
      InfoLine('To', HeaderVal('to'), True);
      InfoLine('Subject', HeaderVal('subject'), True);
      InfoLine('Date', HeaderVal('date'), False);
      InfoLine('Message-ID', HeaderVal('message-id'), False);
      InfoLine('Return-Path', HeaderVal('return-path'), False);
      InfoLine('Delivered-To', HeaderVal('delivered-to'), False);
      rep.Add('');
      if skippedHops > 0 then
      begin
        rep.Add(Format('(%d earlier hop(s) beyond the %d cap not shown)',
          [skippedHops, MAX_HOPS]));
        rep.Add('');
      end;

      // auto-soumission (MAPI Exchange, ESMTPA) : origine fusionnee dans la 1re box
      mergeOrigin := (NormHost(hops[0].FromName) <> '') and
                     (NormHost(hops[0].FromName) = bx[0].NormName);

      SetLength(content, nb + 1);
      SetLength(bdel, nb + 1);
      nbb := 0;
      if not mergeOrigin then
      begin
        content[0] := TStringList.Create;
        t := hops[0].FromName;
        if (hops[0].FromRdns <> '') and
           (NormHost(hops[0].FromRdns) <> NormHost(hops[0].FromName)) then
          t := t + ' (rdns ' + hops[0].FromRdns + ')';
        if hops[0].FromIP <> '' then
        begin
          if t <> '' then t := t + ' ';
          t := t + '[' + hops[0].FromIP + ']';
        end;
        if t = '' then t := '(unknown or local injection)';
        if Length(t) + 19 > 70 then
        begin
          content[0].Add(t);
          content[0].Add('   (claimed origin)');
        end
        else
          content[0].Add(t + '   (claimed origin)');
        bdel[0] := '';
        nbb := 1;
      end;
      try
        for k := 0 to nb - 1 do
        begin
          content[nbb] := TStringList.Create;
          t := bx[k].DispName;
          if bx[k].IP <> '' then t := t + ' [' + bx[k].IP + ']';
          if mergeOrigin and (k = 0) then
          begin
            if Length(t) + 11 > 70 then
            begin
              content[nbb].Add(t);
              t := '   (origin)';
            end
            else
              t := t + '   (origin)';
          end;
          content[nbb].Add(t);
          if mergeOrigin and (k = 0) and (hops[0].FromIP <> '') and
             (ZoneStrip(hops[0].FromIP) <> ZoneStrip(bx[0].IP)) then
            content[nbb].Add('  submitted from [' + hops[0].FromIP + ']');
          // from qui ne colle pas a la box precedente = chaine cassee (Received
          // forge) ou pool de MX : montrer qui s'est VRAIMENT connecte
          if k > 0 then
          begin
            i := bx[k].FirstHop;
            d := NormHost(hops[i].FromName);
            if (((d <> '') and (d <> bx[k - 1].NormName)) or
                ((d = '') and (hops[i].FromIP <> ''))) and
               not ((hops[i].FromIP <> '') and (bx[k - 1].IP <> '') and
                    (ZoneStrip(hops[i].FromIP) = ZoneStrip(bx[k - 1].IP))) then
            begin
              nfp := 0;
              if hops[i].FromName <> '' then
              begin
                fp[nfp] := hops[i].FromName;
                Inc(nfp);
              end;
              if (hops[i].FromRdns <> '') and
                 (NormHost(hops[i].FromRdns) <> NormHost(hops[i].FromName)) then
              begin
                fp[nfp] := '(rdns ' + hops[i].FromRdns + ')';
                Inc(nfp);
              end;
              if hops[i].FromIP <> '' then
              begin
                fp[nfp] := '[' + hops[i].FromIP + ']';
                Inc(nfp);
              end;
              if nfp > 0 then
              begin
                d := '  from';
                for j := 0 to nfp - 1 do
                begin
                  if (Length(d) + Length(fp[j]) + 1 > 68) and
                     (d <> '  from') and (d <> '      ') then
                  begin
                    content[nbb].Add(d);
                    d := '      ';
                  end;
                  d := d + ' ' + fp[j];
                end;
                content[nbb].Add(d);
              end;
            end;
          end;
          for i := bx[k].FirstHop to bx[k].LastHop do
          begin
            if i > bx[k].FirstHop then
            begin
              content[nbb].Add('   |');
              d := HopDelta(hops[i - 1], hops[i]);
              if d <> '' then content[nbb].Add('   v  ' + d)
              else content[nbb].Add('   v');
            end;
            StepLines(hops[i], content[nbb]);
          end;
          if k = 0 then bdel[nbb] := ''
          else bdel[nbb] := HopDelta(hops[bx[k - 1].LastHop], hops[bx[k].FirstHop]);
          Inc(nbb);
        end;

        w := 24;
        for k := 0 to nbb - 1 do
          for i := 0 to content[k].Count - 1 do
            if Length(content[k][i]) > w then w := Length(content[k][i]);
        if w > 70 then w := 70;

        for k := 0 to nbb - 1 do
        begin
          if k > 0 then
          begin
            rep.Add('      |');
            if bdel[k] <> '' then rep.Add('      v  ' + bdel[k])
            else rep.Add('      v');
          end;
          rep.Add('+' + StringOfChar('-', w + 2) + '+');
          for i := 0 to content[k].Count - 1 do
          begin
            t := CapStr(content[k][i], w);
            rep.Add('| ' + t + StringOfChar(' ', w - Length(t)) + ' |');
          end;
          rep.Add('+' + StringOfChar('-', w + 2) + '+');
        end;
      finally
        for i := 0 to nbb - 1 do content[i].Free;
      end;

      firstDated := -1;
      lastDated := -1;
      for i := 0 to nhops - 1 do
        if hops[i].HasDate then
        begin
          if firstDated < 0 then firstDated := i;
          lastDated := i;
        end;
      if (firstDated >= 0) and (lastDated > firstDated) then
      begin
        totSecs := Round((hops[lastDated].UTC - hops[firstDated].UTC) * 86400.0);
        rep.Add('');
        rep.Add('Total transit: ' + FmtDelta(totSecs) +
          '  (first to last Received)');
      end;

      if unparsed > 0 then
      begin
        rep.Add('');
        rep.Add(Format('! %d Received header(s) could not be parsed:', [unparsed]));
        j := 0;
        for i := 0 to nhd - 1 do
          if (hdrs[i].Name = 'received') and (j < MAX_UNPARSED) then
            if not ParseReceived(hdrs[i].Value, h) then
            begin
              rep.Add('  ' + CapStr(hdrs[i].Value, 90));
              Inc(j);
            end;
      end;

      auth := '';
      t := HeaderVal('authentication-results');
      if t <> '' then auth := AuthSummary(t);
      virus := TidyStr(HeaderVal('x-virus-scanned'), 100);
      if (auth <> '') or (virus <> '') then rep.Add('');
      if auth <> '' then rep.Add('Authentication: ' + auth);
      if virus <> '' then rep.Add('Virus scan:     ' + virus);

      nr := 0;
      haveVerdict := False;
      isSpam := False;
      score := 0;
      req := 0;
      hasScore := False;
      vSrc := '';
      t := HeaderVal('x-spam-status');
      if t <> '' then
      begin
        ParseSpamStatus(t, isSpam, score, req, hasScore, rules, nr);
        haveVerdict := True;
        vSrc := 'X-Spam-Status';
      end
      else
      begin
        t := HeaderVal('x-spamd-result');
        if t <> '' then
        begin
          ParseSpamdResult(t, isSpam, score, req, hasScore, rules, nr);
          haveVerdict := True;
          vSrc := 'X-Spamd-Result';
        end
        else
        begin
          t := HeaderVal('x-spam-flag');
          if t <> '' then
          begin
            isSpam := Pos('yes', LowerCase(t)) > 0;
            haveVerdict := True;
            vSrc := 'X-Spam-Flag';
          end;
        end;
      end;

      if haveVerdict then
      begin
        rep.Add('');
        if isSpam then vName := 'SPAM' else vName := 'HAM';
        t := 'Verdict: ' + vName;
        if hasScore then
        begin
          t := t + Format('  (score %.2f', [score]);
          if req > 0 then t := t + Format(' / required %.2f', [req]);
          t := t + ')';
        end;
        rep.Add(t + '  [' + vSrc + ']');
        if nr > 0 then
        begin
          for i := 1 to nr - 1 do
          begin
            tmpR := rules[i];
            j := i - 1;
            while (j >= 0) and (rules[j].Score < tmpR.Score) do
            begin
              rules[j + 1] := rules[j];
              Dec(j);
            end;
            rules[j + 1] := tmpR;
          end;
          for i := 0 to nr - 1 do
          begin
            if rules[i].HasScore then t := Format('%7.2f', [rules[i].Score])
            else t := '       ';
            d := RuleDesc(rules[i].Name);
            if d <> '' then
              rep.Add(Format('%s  %-26s %s', [t, rules[i].Name, d]))
            else
              rep.Add(Format('%s  %s', [t, rules[i].Name]));
          end;
        end;
      end;

      Result := rep.Text;
    finally
      rep.Free;
    end;
  except
    Result := '';   // entree hostile : refus propre, jamais de crash
  end;
end;

end.
