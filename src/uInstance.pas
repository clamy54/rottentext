unit uInstance;

{$mode objfpc}{$H+}

// Mono-instance: un fichier ouvert depuis le shell arrive en onglet dans
// l'instance vivante. TSimpleIPC (fenetre de message Windows, FIFO 0600 POSIX),
// protocole une passe + accuse horodate. Le message est une entree non fiable.

interface

// True = accuse recu, l'appelant quitte sans ouvrir
function ForwardToRunningInstance(const APath: string): Boolean;

// False = une autre instance sert deja le canal: chacun sa fenetre
function InstanceServerStart: Boolean;
// non bloquant, un chemin par appel. Rappeler jusqu'a False.
function InstanceServerPoll(out APath: string): Boolean;
// instance occupee: vider le canal SANS acquitter ni ouvrir, sinon le fichier
// serait ouvert deux fois (le client expire et ouvre sa propre fenetre)
procedure InstanceServerDrain;

implementation

uses
  Classes, SysUtils, simpleipc{$IFDEF UNIX}, BaseUnix, Unix{$ENDIF};

{$IFDEF WINDOWS}
const
  ERR_ALREADY_EXISTS = 183;
// declares a la main: l'unite Windows entre en conflit de types avec la LCL
function CreateMutexW(lpAttr: Pointer; bInitialOwner: LongBool;
  lpName: PWideChar): THandle; stdcall; external 'kernel32.dll' name 'CreateMutexW';
function CloseHandle(hObject: THandle): LongBool; stdcall;
  external 'kernel32.dll' name 'CloseHandle';
{$ENDIF}

const
  ACK_BUDGET_MS = 1500; // au-dela, le serveur est repute mort/occupe
  // marge sous le budget: passe ce delai le client abandonne, l'accuse
  // arriverait trop tard et le fichier finirait ouvert des deux cotes
  STALE_MS = ACK_BUDGET_MS - 250;
  MAX_MSG = 8192;
  MAX_DRAIN = 32;       // un flood local ne monopolise pas le tick du timer UI

var
  FSrv: TSimpleIPCServer = nil;
  {$IFDEF WINDOWS}
  FSlot: THandle = 0;   // mutex nomme: notre droit a servir le canal
  {$ELSE}
  FSlot: cint = -1;     // fd du verrou de fichier, idem
  {$ENDIF}

function ConfigDir: string;
begin
  Result := IncludeTrailingPathDelimiter(GetAppConfigDir(False));
end;

// primitive d'exclusion de l'OS, pas un simple "un serveur tourne-t-il ?": N
// process lances d'un coup verraient tous le canal libre et le serviraient tous
function ClaimServerSlot: Boolean;
begin
  {$IFDEF WINDOWS}
  if FSlot <> 0 then Exit(True);
  FSlot := CreateMutexW(nil, False, 'Local\RottenText.server');
  if FSlot = 0 then Exit(False);
  // le mutex existait deja: une autre instance sert
  Result := GetLastOSError <> ERR_ALREADY_EXISTS;
  if not Result then
  begin
    CloseHandle(FSlot);
    FSlot := 0;
  end;
  {$ELSE}
  if FSlot >= 0 then Exit(True);
  FSlot := FpOpen(ConfigDir + 'instance.lock', O_CREAT or O_RDWR, &600);
  if FSlot < 0 then Exit(False);
  Result := fpFlock(FSlot, LOCK_EX or LOCK_NB) = 0;
  if not Result then
  begin
    FpClose(FSlot);
    FSlot := -1;
  end;
  {$ENDIF}
end;

// rendre la place: une prochaine instance pourra servir
procedure ReleaseServerSlot;
begin
  {$IFDEF WINDOWS}
  if FSlot <> 0 then CloseHandle(FSlot);
  FSlot := 0;
  {$ELSE}
  if FSlot >= 0 then FpClose(FSlot); // le flock tombe avec le fd
  FSlot := -1;
  {$ENDIF}
end;

procedure DropServer;
begin
  FreeAndNil(FSrv);
  ReleaseServerSlot;
end;

// POSIX: chemin ABSOLU, un ServerID relatif atterrirait dans /tmp world-writable
function InstanceChannel: string;
begin
  {$IFDEF WINDOWS}
  Result := 'rottentext';
  {$ELSE}
  Result := ConfigDir + 'instance.ipc';
  {$ENDIF}
end;

function AckChannel(APid: SizeUInt): string;
begin
  {$IFDEF WINDOWS}
  Result := 'rottentext_ack_' + IntToStr(APid);
  {$ELSE}
  Result := ConfigDir + 'ack_' + IntToStr(APid) + '.ipc';
  {$ENDIF}
end;

// l'id d'ack vient du message: n'ecrire que vers un canal a notre forme exacte,
// jamais vers un chemin arbitraire fourni par le pair
function AckChannelOK(const AId: string): Boolean;
var
  pre, digits: string;
  i: Integer;
begin
  Result := False;
  {$IFDEF WINDOWS}
  pre := 'rottentext_ack_';
  {$ELSE}
  pre := ConfigDir + 'ack_';
  {$ENDIF}
  if (Length(AId) <= Length(pre)) or (Length(AId) > Length(pre) + 24) then Exit;
  if Copy(AId, 1, Length(pre)) <> pre then Exit;
  digits := Copy(AId, Length(pre) + 1, MaxInt);
  {$IFNDEF WINDOWS}
  if (Length(digits) <= 4) or (Copy(digits, Length(digits) - 3, 4) <> '.ipc') then Exit;
  SetLength(digits, Length(digits) - 4);
  {$ENDIF}
  if digits = '' then Exit;
  for i := 1 to Length(digits) do
    if not (digits[i] in ['0'..'9']) then Exit;
  Result := True;
end;

{$IFDEF UNIX}
// ecrire vers un pair mort entre le test et le write tuerait le process
procedure IgnoreSigPipe;
begin
  FpSignal(SIGPIPE, SignalHandler(SIG_IGN));
end;
{$ENDIF}

function ForwardToRunningInstance(const APath: string): Boolean;
var
  cli: TSimpleIPCClient;
  ack: TSimpleIPCServer;
  full: string;
  t0: QWord;
begin
  Result := False;
  if APath = '' then Exit;
  {$IFDEF UNIX}IgnoreSigPipe;{$ENDIF}
  try
    full := ExpandFileName(APath);
    if Length(full) > 4096 then Exit;
    cli := TSimpleIPCClient.Create(nil);
    try
      cli.ServerID := InstanceChannel;
      if not cli.ServerRunning then Exit; // purge aussi un FIFO orphelin
      ack := TSimpleIPCServer.Create(nil);
      try
        ack.Global := True; // nom SANS suffixe pid: le serveur doit le retrouver
        ack.ServerID := AckChannel(GetProcessID);
        ack.StartServer;
        {$IFDEF UNIX}FpChmod(ack.ServerID, &600);{$ENDIF}
        cli.Active := True;
        // horodatage pose au plus pres de l'envoi: le serveur mesure l'age
        cli.SendStringMessage('OPEN'#1 + ack.ServerID + #1 +
          IntToStr(GetTickCount64) + #1 + full);
        cli.Active := False;
        t0 := GetTickCount64;
        while GetTickCount64 - t0 < ACK_BUDGET_MS do
          if ack.PeekMessage(50, True) then
          begin
            Result := ack.StringMessage = 'OK';
            Break;
          end;
      finally
        ack.Free; // StopServer + suppression du FIFO d'ack
      end;
    finally
      cli.Free;
    end;
  except
    Result := False; // canal cabosse = ouverture normale, jamais bloquant
  end;
end;

function InstanceServerStart: Boolean;
begin
  Result := False;
  if FSrv <> nil then Exit(True);
  {$IFDEF UNIX}IgnoreSigPipe;{$ENDIF}
  try
    ForceDirectories(GetAppConfigDir(False));
    if not ClaimServerSlot then Exit;
    FSrv := TSimpleIPCServer.Create(nil);
    FSrv.Global := True; // nom fixe, decouvrable par les clients
    FSrv.ServerID := InstanceChannel;
    FSrv.StartServer; // reutilise un FIFO orphelin laisse par un crash
    {$IFDEF UNIX}FpChmod(FSrv.ServerID, &600);{$ENDIF}
    Result := True;
  except
    DropServer; // pas de canal, pas fatal
  end;
end;

procedure SendAck(const AId: string);
var
  cli: TSimpleIPCClient;
begin
  if not AckChannelOK(AId) then Exit;
  try
    cli := TSimpleIPCClient.Create(nil);
    try
      cli.ServerID := AId;
      if cli.ServerRunning then
      begin
        cli.Active := True;
        cli.SendStringMessage('OK');
      end;
    finally
      cli.Free;
    end;
  except
    // client deja reparti: il ouvrira sa propre fenetre, pas grave
  end;
end;

// GetTickCount64 est la meme horloge pour tous les process de la machine.
// Horloge reculee (NTP) = on sert: un doublon vaut mieux qu'un clic perdu.
function MsgFresh(const ATick: string): Boolean;
var
  sent, tnow: QWord;
begin
  Result := False;
  if (ATick = '') or (Length(ATick) > 20) then Exit;
  if not TryStrToQWord(ATick, sent) then Exit;
  tnow := GetTickCount64;
  if tnow <= sent then Exit(True);
  Result := (tnow - sent) <= STALE_MS;
end;

procedure InstanceServerDrain;
var
  n: Integer;
begin
  if FSrv = nil then Exit;
  n := 0;
  try
    while (n < MAX_DRAIN) and FSrv.PeekMessage(0, True) do
      Inc(n);
  except
    DropServer;
  end;
end;

function InstanceServerPoll(out APath: string): Boolean;
var
  s, ackid, tick, p: string;
  sep, drained: Integer;
begin
  Result := False;
  APath := '';
  if FSrv = nil then Exit;
  drained := 0;
  try
    while (drained < MAX_DRAIN) and FSrv.PeekMessage(0, True) do
    begin
      Inc(drained);
      s := FSrv.StringMessage;
      if (Length(s) > MAX_MSG) or (Copy(s, 1, 5) <> 'OPEN'#1) then Continue;
      Delete(s, 1, 5);
      sep := Pos(#1, s);
      if sep <= 1 then Continue;
      ackid := Copy(s, 1, sep - 1);
      Delete(s, 1, sep);
      sep := Pos(#1, s);
      if sep <= 1 then Continue;
      tick := Copy(s, 1, sep - 1);
      // chemin en DERNIER champ: un chemin POSIX peut contenir n'importe quoi
      p := Copy(s, sep + 1, MaxInt);
      // perime = le client a renonce et ouvert sa fenetre: le servir ouvrirait
      // le fichier une deuxieme fois
      if not MsgFresh(tick) then Continue;
      // valider PUIS acquitter: l'accuse signifie "je l'ouvre"
      if (p <> '') and (Length(p) <= 4096) and FileExists(p) and
         not DirectoryExists(p) then
      begin
        // le stat a pu durer (volume reseau malade): re-verifier l'age avant
        // d'acquitter, sinon l'accuse part vers un client deja parti
        if not MsgFresh(tick) then Continue;
        SendAck(ackid);
        APath := p;
        Exit(True); // un chemin par poll, le timer repassera
      end;
    end;
  except
    // canal HS: on cesse de servir, l'editeur continue
    DropServer;
  end;
end;

finalization
  DropServer; // StopServer: le FIFO/la fenetre de message disparait

end.
