unit uJwt;

{$mode objfpc}{$H+}

// Decodeur JWT. La signature n'est JAMAIS verifiee (il faudrait la cle),
// bandeau explicite dans le rapport.

interface

uses
  SysUtils;

type
  EJwtError = class(Exception);

function JwtDecode(const AToken: string): string;

implementation

uses
  Classes, StrUtils, DateUtils, base64, fpjson, jsonparser;

function B64UrlDecode(const S: string): string;
var
  t: string;
  pad: Integer;
begin
  t := StringReplace(S, '-', '+', [rfReplaceAll]);
  t := StringReplace(t, '_', '/', [rfReplaceAll]);
  pad := Length(t) mod 4;
  if pad > 0 then t := t + StringOfChar('=', 4 - pad);
  Result := DecodeStringBase64(t);
end;

function PrettyJson(const ARaw: string): string;
var
  d: TJSONData;
begin
  d := nil;
  try
    d := GetJSON(ARaw);
    if d = nil then Exit(ARaw);
    Result := d.FormatJSON;
  except
    Result := ARaw;
  end;
  d.Free;
end;

function EpochLine(AObj: TJSONObject; const AClaim, ALabel: string): string;
const
  // hors plage, UnixToDateTime + FormatDateTime levent une AV (exp = Int64 max)
  EPOCH_MIN = Int64(-62135596800); // 0001-01-01
  EPOCH_MAX = Int64(253402214400); // 9999-12-31
var
  idx: Integer;
  v: Int64;
  fv: Double;
  dtUtc: TDateTime;
begin
  Result := '';
  idx := AObj.IndexOfName(AClaim);
  if idx < 0 then Exit;
  if not (AObj.Items[idx].JSONType in [jtNumber]) then Exit;
  // AsInt64 leve sur un float hors plage (exp:1e100) : borner sur AsFloat avant
  fv := AObj.Items[idx].AsFloat;
  if (fv < EPOCH_MIN) or (fv > EPOCH_MAX) then
  begin
    Result := Format('%-4s (%s): %s = (out of range)',
      [AClaim, ALabel, AObj.Items[idx].AsString]);
    Exit;
  end;
  v := AObj.Items[idx].AsInt64;
  dtUtc := UnixToDateTime(v);
  Result := Format('%-4s (%s): %d = %s UTC / %s local',
    [AClaim, ALabel, v,
     FormatDateTime('yyyy-mm-dd hh:nn:ss', dtUtc),
     FormatDateTime('yyyy-mm-dd hh:nn:ss', UniversalTimeToLocal(dtUtc))]);
end;

function JwtDecode(const AToken: string): string;
var
  tok, hdr, pl, times: string;
  p1, p2: Integer;
  payload: TJSONData;
  obj: TJSONObject;
  sb: TStringList;
  nowU: Int64;
  idx: Integer;
begin
  tok := Trim(AToken);
  if (Length(tok) >= 7) and (LowerCase(Copy(tok, 1, 7)) = 'bearer ') then
    tok := Trim(Copy(tok, 8, MaxInt));
  p1 := Pos('.', tok);
  if p1 = 0 then raise EJwtError.Create('Not a JWT (expected header.payload.signature)');
  p2 := PosEx('.', tok, p1 + 1);
  if p2 = 0 then raise EJwtError.Create('Not a JWT (missing payload/signature separator)');
  hdr := Copy(tok, 1, p1 - 1);
  pl := Copy(tok, p1 + 1, p2 - p1 - 1);
  if (hdr = '') or (pl = '') then raise EJwtError.Create('Empty header or payload');

  sb := TStringList.Create;
  try
    sb.Add('=== JWT  (signature NOT verified) ===');
    sb.Add('');
    sb.Add('--- Header ---');
    sb.Add(PrettyJson(B64UrlDecode(hdr)));
    sb.Add('');
    sb.Add('--- Payload ---');
    sb.Add(PrettyJson(B64UrlDecode(pl)));

    payload := nil;
    try payload := GetJSON(B64UrlDecode(pl)); except end;
    try
    if payload is TJSONObject then
    begin
      obj := TJSONObject(payload);
      times := '';
      times := times + EpochLine(obj, 'iat', 'issued at');
      if times <> '' then times := times + LineEnding;
      times := times + EpochLine(obj, 'nbf', 'not before');
      if (times <> '') and (times[Length(times)] <> #10) then times := times + LineEnding;
      times := times + EpochLine(obj, 'exp', 'expires');
      if Trim(times) <> '' then
      begin
        sb.Add('');
        sb.Add('--- Times ---');
        sb.Add(Trim(times));
      end;
      idx := obj.IndexOfName('exp');
      if (idx >= 0) and (obj.Items[idx].JSONType = jtNumber) then
      begin
        nowU := DateTimeToUnix(LocalTimeToUniversal(Now));
        // AsFloat, pas AsInt64 : un exp:1e100 leverait
        if obj.Items[idx].AsFloat < nowU then sb.Add('Status:  EXPIRED')
        else sb.Add('Status:  not expired');
      end;
    end;
    finally
      payload.Free; // Free(nil) est sur
    end;
    Result := sb.Text;
  finally
    sb.Free;
  end;
end;

end.
