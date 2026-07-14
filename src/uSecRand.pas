unit uSecRand;

{$mode objfpc}{$H+}

// Aleatoire cryptographique de l'OS (RtlGenRandom / /dev/urandom).
// FAIL-CLOSED : source indisponible = False, jamais de repli sur un PRNG faible.

interface

function SecureRandomBytes(out ABuf; ACount: Integer): Boolean;

implementation

{$IFDEF WINDOWS}
function RtlGenRandom(RandomBuffer: Pointer; RandomBufferLength: DWord): ByteBool;
  stdcall; external 'advapi32.dll' name 'SystemFunction036';

function SecureRandomBytes(out ABuf; ACount: Integer): Boolean;
begin
  if ACount <= 0 then Exit(True);
  Result := RtlGenRandom(@ABuf, DWord(ACount));
end;
{$ELSE}
uses
  BaseUnix;

function SecureRandomBytes(out ABuf; ACount: Integer): Boolean;
var
  fd: cint;
  n, got: TSsize;
  p: PByte;
begin
  Result := False;
  if ACount <= 0 then Exit(True);
  fd := FpOpen('/dev/urandom', O_RDONLY);
  if fd < 0 then Exit;
  try
    p := @ABuf;
    got := 0;
    while got < ACount do
    begin
      n := FpRead(fd, p[got], ACount - got);
      if n <= 0 then Exit;
      Inc(got, n);
    end;
    Result := True;
  finally
    FpClose(fd);
  end;
end;
{$ENDIF}

end.
