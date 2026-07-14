unit uDocument;

{$mode objfpc}{$H+}

interface

uses
  {$IFDEF UNIX}BaseUnix,{$ENDIF}
  Classes, SysUtils, Controls, LazUTF8, uEditorView, uEncoding, uHexView,
  uSafeSave, uEol;

const
  // au-dela: mode gros fichier (ni coloration auto ni wrap a l'ouverture)
  LargeFileBytes = 10 * 1024 * 1024;
  // ReadBuffer prend un Count Longint: au-dela de 4 Gio il reboucle POSITIF,
  // lecture partielle silencieuse puis Ctrl+S ecrit le garbage sur le fichier
  TextLoadMaxBytes = Int64(MaxInt); // 2 Gio - 1

type
  TDiskChange = (dcNone, dcModified, dcDeleted);

  TDocument = class
  private
    FView: TEditorView;
    FHex: THexView; // nil = doc texte
    FFileName: string;
    FModified: Boolean;
    FUntitled: Boolean;
    FReadOnly: Boolean;
    FLargeFile: Boolean;
    FLoading: Boolean;
    FTornLoad: Boolean;  // reload interrompu en pleine mutation du buffer
    FEncoding: Integer;  // index dans uEncoding.Encodings, garde pour Save
    FEol: TEolKind;      // fins de ligne du fichier, re-appliquees au save
    // TStrings.Text ajoute TOUJOURS un saut final: sans ce flag, Ctrl+S en
    // ajouterait un a un fichier qui n'en avait pas
    FTrailingEol: Boolean;
    FGroup: Integer;
    FDiskTime: Int64;   // instantane du fichier (mtime + taille + id) a la
    FDiskSize: Int64;   // derniere lecture/ecriture (modif externe)
    FDiskId: Int64;     // inode POSIX (0 sous Windows)
    FHasStamp: Boolean;
    // reload en echec: le stamp n'est PAS recapture (ca masquerait la modif
    // externe et un save ulterieur l'ecraserait sans bruit)
    FDeferredReload: Boolean;
    FOnChange: TNotifyEvent;
    FOnFocus: TNotifyEvent;
    procedure SynChanged(Sender: TObject);
    procedure HexEdited(Sender: TObject);
    procedure ViewEntered(Sender: TObject);
    procedure SetModified(AValue: Boolean);
    procedure SetEol(AValue: TEolKind);
    procedure Changed;
  public
    constructor Create(AView: TEditorView);
    destructor Destroy; override;
    function DisplayName: string;
    procedure LoadFromFile(const AFileName: string);
    // AEnc = -1: auto-detection
    procedure LoadFromFileEnc(const AFileName: string; AEnc: Integer);
    procedure OpenHex(const AFileName: string);
    procedure SaveToFile(const AFileName: string);
    procedure Revert;
    procedure CaptureDiskState;
    function CheckDiskChange: TDiskChange;
    procedure MarkOrphan; // fichier disparu, gardé en editeur: stop surveillance
    function IsHex: Boolean;
    procedure ShowDoc;
    procedure HideDoc;
    procedure FocusDoc;
    property View: TEditorView read FView;
    property HexView: THexView read FHex;
    property FileName: string read FFileName;
    property Untitled: Boolean read FUntitled;
    property ReadOnly: Boolean read FReadOnly;
    property LargeFile: Boolean read FLargeFile;
    property Modified: Boolean read FModified write SetModified;
    property Encoding: Integer read FEncoding write FEncoding;
    property Eol: TEolKind read FEol write SetEol;
    property Group: Integer read FGroup write FGroup;
    property DeferredReload: Boolean read FDeferredReload write FDeferredReload;
    property OnChange: TNotifyEvent read FOnChange write FOnChange;
    property OnFocus: TNotifyEvent read FOnFocus write FOnFocus;
  end;

implementation

{$IFDEF WINDOWS}
// declares a la main: l'unite Windows entre en conflit de types avec la LCL
type
  TRTFileTime = record
    dwLowDateTime: DWord;
    dwHighDateTime: DWord;
  end;
  TRTFileAttrData = record
    dwFileAttributes: DWord;
    ftCreationTime: TRTFileTime;
    ftLastAccessTime: TRTFileTime;
    ftLastWriteTime: TRTFileTime;
    nFileSizeHigh: DWord;
    nFileSizeLow: DWord;
  end;

function GetFileAttributesExW(lpFileName: PWideChar; fInfoLevelId: Integer;
  lpFileInformation: Pointer): LongBool; stdcall;
  external 'kernel32.dll' name 'GetFileAttributesExW';
{$ENDIF}

// mtime haute resolution + taille + inode (POSIX): une reecriture externe de
// meme taille dans la meme seconde, ou un fichier remplace par mv, se voient
function FileStamp(const AName: string; out ATime, ASize, AId: Int64): Boolean;
{$IFDEF WINDOWS}
var
  fad: TRTFileAttrData;
  w: UnicodeString;
  resolved: string;
begin
  Result := False;
  AId := 0;
  // GetFileAttributesExW ne suit PAS les reparse points: sans ResolveLink, un
  // doc ouvert via lien rendrait le mtime du LIEN, qui ne change jamais
  try
    resolved := ResolveLink(AName);
  except
    Exit; // lien pendouillant/inaccessible: pas de stamp fiable
  end;
  w := UTF8ToUTF16(resolved);
  if not GetFileAttributesExW(PWideChar(w), 0, @fad) then Exit; // 0 = standard
  ATime := (Int64(fad.ftLastWriteTime.dwHighDateTime) shl 32)
           or Int64(fad.ftLastWriteTime.dwLowDateTime);
  ASize := (Int64(fad.nFileSizeHigh) shl 32) or Int64(fad.nFileSizeLow);
  Result := True;
end;
{$ELSE}
var
  st: Stat;
begin
  Result := False;
  if fpStat(AName, st) <> 0 then Exit; // suit les symlinks (on sauve la cible)
  ATime := Int64(st.st_mtime) * 1000000000;
  {$IFDEF LINUX}
  ATime := ATime + st.st_mtime_nsec;
  {$ENDIF}
  ASize := st.st_size;
  AId := Int64(st.st_ino);
  Result := True;
end;
{$ENDIF}

// sonde reelle: seule une ouverture en ecriture couvre attribut RO ET ACL
function FileWritable(const AFileName: string): Boolean;
var
  fs: TFileStream;
begin
  try
    fs := TFileStream.Create(AFileName, fmOpenWrite or fmShareDenyNone);
    fs.Free;
    Result := True;
  except
    Result := False;
  end;
end;

constructor TDocument.Create(AView: TEditorView);
begin
  FView := AView;
  FUntitled := True;
  FModified := False;
  FEncoding := ENC_UTF8;
  FEol := PlatformEol;
  FTrailingEol := True; // untitled: newline final a la sauvegarde (usage POSIX)
  FView.OnChange := @SynChanged;
  FView.Syn.OnEnter := @ViewEntered;
end;

destructor TDocument.Destroy;
begin
  FHex.Free;
  FView.Free;
  inherited Destroy;
end;

procedure TDocument.Changed;
begin
  if Assigned(FOnChange) then
    FOnChange(Self);
end;

procedure TDocument.SetModified(AValue: Boolean);
begin
  if FModified = AValue then Exit;
  FModified := AValue;
  FView.Syn.Modified := AValue;
  Changed;
end;

// le buffer ne stocke pas de fins de ligne: l'EOL ne prend effet qu'au save
procedure TDocument.SetEol(AValue: TEolKind);
begin
  if FEol = AValue then Exit;
  FEol := AValue;
  Changed;
end;

procedure TDocument.SynChanged(Sender: TObject);
begin
  if FLoading then Exit;
  if not FModified then
    SetModified(True) // fait deja un Changed
  else
    Changed;
end;

function TDocument.DisplayName: string;
var
  s: string;
begin
  if not FUntitled then
    Exit(ExtractFileName(FFileName));
  // untitled: l'onglet prend la 1re ligne. Borner AVANT de manipuler (appele a
  // chaque repaint, un blob colle en une ligne serait recopie en entier); 256
  // octets couvrent toujours 50 chars UTF-8.
  s := '';
  if (not IsHex) and (FView.Syn.Lines.Count > 0) then
    s := Trim(Copy(FView.Syn.Lines[0], 1, 256));
  if s = '' then
    Result := 'untitled'
  else
    Result := UTF8Copy(s, 1, 50);
end;

procedure TDocument.LoadFromFile(const AFileName: string);
var
  fs: TFileStream;
  head: string;
  n: Integer;
  det: Integer;
begin
  // detection binaire sur la tete: un gros binaire ne doit pas etre charge en
  // memoire pour etre reconnu
  fs := TFileStream.Create(AFileName, fmOpenRead or fmShareDenyNone);
  try
    n := 8192;
    if fs.Size < n then n := fs.Size;
    SetLength(head, n);
    if n > 0 then
      fs.ReadBuffer(head[1], n);
  finally
    fs.Free;
  end;
  det := DetectEncoding(head);
  // les octets nuls d'un UTF-16 (a BOM ou non) ne font pas un binaire
  if LooksBinary(head) and (det <> ENC_UTF16LE_BOM) and (det <> ENC_UTF16BE_BOM) then
  begin
    det := DetectUTF16NoBom(head);
    if det >= 0 then
      LoadFromFileEnc(AFileName, det)
    else
      OpenHex(AFileName);
  end
  else
    LoadFromFileEnc(AFileName, -1);
end;

procedure TDocument.OpenHex(const AFileName: string);
var
  host: TWinControl;
  created: Boolean;
begin
  created := FHex = nil;
  if created then
  begin
    // configurer avant Parent: anti-flicker
    host := FView.Syn.Parent;
    FHex := THexView.Create(host);
    FHex.Visible := False;
    FHex.Align := alClient;
    FHex.Parent := host;
    FHex.OnEdited := @HexEdited;
    FHex.OnEnter := @ViewEntered;
  end;
  // sur echec, ne pas laisser le doc marque IsHex avec une vue a moitie montee
  try
    FHex.LoadFile(AFileName);
  except
    if created then FreeAndNil(FHex);
    raise;
  end;
  // le doc est porte par la vue hex: vider l'editeur texte
  FLoading := True;
  try
    FView.Syn.ClearAll;
    if FView.Syn.Lines.Count = 0 then
      FView.Syn.Lines.Add('');
  finally
    FLoading := False;
  end;
  FFileName := AFileName;
  FUntitled := False;
  FReadOnly := not FileWritable(AFileName);
  FModified := False;
  FView.Syn.Modified := False;
  CaptureDiskState;
  Changed;
end;

function TDocument.IsHex: Boolean;
begin
  Result := FHex <> nil;
end;

procedure TDocument.HexEdited(Sender: TObject);
begin
  if FHex.EditCount > 0 then
  begin
    if not FModified then
      SetModified(True)
    else
      Changed;
  end
  else
    SetModified(False); // tous les octets sont revenus a l'origine
end;

procedure TDocument.ShowDoc;
begin
  if IsHex then
  begin
    FView.HideView;
    FHex.ShowView;
  end
  else
  begin
    if FHex <> nil then FHex.HideView;
    FView.ShowView;
  end;
end;

procedure TDocument.HideDoc;
begin
  FView.HideView;
  if FHex <> nil then FHex.HideView;
end;

procedure TDocument.FocusDoc;
begin
  if IsHex then
  begin
    if FHex.CanFocus then FHex.SetFocus;
  end
  else if FView.Syn.CanFocus then
    FView.Syn.SetFocus;
end;

procedure TDocument.ViewEntered(Sender: TObject);
begin
  if Assigned(FOnFocus) then FOnFocus(Self);
end;

procedure TDocument.LoadFromFileEnc(const AFileName: string; AEnc: Integer);
var
  fs: TFileStream;
  raw, txt: string;
  smpLen: Integer;
begin
  fs := TFileStream.Create(AFileName, fmOpenRead or fmShareDenyNone);
  try
    if fs.Size > TextLoadMaxBytes then
      raise EStreamError.CreateFmt(
        '%s is %d bytes -- too large to open as text (max %d bytes / 2 GB).',
        [ExtractFileName(AFileName), fs.Size, TextLoadMaxBytes]);
    SetLength(raw, fs.Size);
    if raw <> '' then
      fs.ReadBuffer(raw[1], Length(raw));
  finally
    fs.Free;
  end;
  FLargeFile := Length(raw) >= LargeFileBytes;
  if FLargeFile and not FView.LargeFile then
  begin
    // devenu gros (Revert / Reopen with Encoding): couper wrap et coloration
    // AVANT de charger, sinon chacun rescanne tout le buffer en synchrone
    FView.LargeFile := True;
    FView.ApplyViewSettings;
    FView.Syn.Highlighter := nil;
  end;
  if AEnc < 0 then
  begin
    // gros fichier: detection sur echantillon (le scan UTF-8 est lineaire).
    // Des octets non-UTF-8 au-dela de 4 Mo passent inapercus, Reopen corrige.
    if FLargeFile then
    begin
      smpLen := 4 * 1024 * 1024;
      if smpLen > Length(raw) then smpLen := Length(raw);
      // couper au milieu d'une sequence UTF-8 ferait passer le fichier pour du
      // Windows-1252 (mojibake, puis reencode 1252 au save): reculer sur la
      // frontiere si l'octet suivant est une continuation
      while (smpLen > 0) and (smpLen < Length(raw)) and
            (Ord(raw[smpLen + 1]) >= $80) and (Ord(raw[smpLen + 1]) <= $BF) do
        Dec(smpLen);
      AEnc := DetectEncoding(Copy(raw, 1, smpLen));
    end
    else
      AEnc := DetectEncoding(raw);
  end;
  FEncoding := AEnc;
  txt := DecodeToUTF8(raw, AEnc);
  // EOL detecte sur le texte DECODE: en UTF-16 brut les CR/LF sont noyes dans
  // des paires avec 00
  if FLargeFile then
    FEol := DetectEol(txt, PlatformEol, 4 * 1024 * 1024)
  else
    FEol := DetectEol(txt, PlatformEol);
  // fichier vide = pas de saut final non plus (sinon Ctrl+S ecrirait 1 EOL)
  FTrailingEol := (txt <> '') and (txt[Length(txt)] in [#10, #13]);
  // une exception ici (OOM pres du cap 2 Gio) laisse un buffer PARTIEL avec
  // Modified=False et le stamp intact: le flag bloque le save jusqu'au Revert
  FTornLoad := True;
  FLoading := True;
  try
    FView.Syn.Lines.Text := txt;
  finally
    FLoading := False;
  end;
  FTornLoad := False;
  // redevenu petit: recreer le plugin wrap APRES le chargement, le creer sur
  // l'ancien buffer encore gros paierait sa validation
  if FView.LargeFile and not FLargeFile then
  begin
    FView.LargeFile := False;
    FView.ApplyViewSettings;
  end;
  FreeAndNil(FHex); // Reopen with Encoding sur un doc hex: retour au texte
  FFileName := AFileName;
  FUntitled := False;
  FReadOnly := not FileWritable(AFileName);
  FModified := False;
  FView.Syn.Modified := False;
  CaptureDiskState;
  Changed;
end;

procedure TDocument.SaveToFile(const AFileName: string);
var
  st: TOwnedHandleStream;
  raw, tmp, target, txt: string;
  n: Integer;
begin
  if IsHex then
  begin
    FHex.SaveCopyAs(AFileName);
    FFileName := AFileName;
    FUntitled := False;
    FReadOnly := False; // on vient d'y ecrire
    Modified := False;
    CaptureDiskState;
    Changed;
    Exit;
  end;
  // buffer partiel d'un reload interrompu: sauver ecraserait le fichier intact
  // par un fragment, et rien ne le signalerait (Modified=False, stamp inchange)
  if FTornLoad then
    raise EStreamError.CreateFmt(
      'The last reload of %s was interrupted; the buffer may be incomplete.' +
      LineEnding + 'Use File > Revert File before saving.', [DisplayName]);
  // Lines.Text sort en EOL plateforme: re-imposer celui du doc AVANT l'encodage
  txt := FView.Syn.Lines.Text;
  if not FTrailingEol then
  begin
    // saut final synthetique de Lines.Text: en retirer UN seul, jamais les
    // lignes vides volontaires de la fin du buffer
    n := Length(txt);
    if (n > 0) and (txt[n] = #10) then Dec(n);
    if (n > 0) and (txt[n] = #13) then Dec(n);
    SetLength(txt, n);
  end;
  raw := EncodeFromUTF8(ForceEol(txt, FEol), FEncoding);
  // sauver la CIBLE du lien: l'entree du lien n'est pas touchee, il survit
  target := ResolveLink(AFileName);
  if HasHardLinks(target) then
    // un rename casserait le groupe de liens
    WriteInPlaceKeepLinks(target, raw)
  else
  begin
    // temp exclusif + remplacement atomique: un fmCreate direct tronquerait la
    // cible avant d'ecrire (disque plein / reseau / antivirus = fichier perdu)
    st := CreateTempIn(target, tmp);
    try
      try
        if raw <> '' then
          WriteAllBuf(st, raw);
      finally
        st.Free;
      end;
    except
      DeleteFile(tmp);
      raise;
    end;
    if not ReplaceByRename(tmp, target) then
    begin
      DeleteFile(tmp);
      raise EStreamError.CreateFmt('Cannot replace %s', [target]);
    end;
  end;
  // le doc garde le chemin du LIEN, pas celui de la cible
  FFileName := AFileName;
  FUntitled := False;
  FReadOnly := False; // on vient d'y ecrire
  Modified := False;
  CaptureDiskState;
  Changed;
end;

procedure TDocument.Revert;
begin
  if FUntitled or not FileExists(FFileName) then Exit;
  if IsHex then
  begin
    FHex.LoadFile(FFileName); // jette l'overlay d'edits
    FReadOnly := not FileWritable(FFileName); // les droits ont pu changer
    Modified := False;
    CaptureDiskState;
    Changed;
  end
  else
    LoadFromFile(FFileName);
end;

procedure TDocument.CaptureDiskState;
var
  t, s, id: Int64;
begin
  FHasStamp := False;
  FDeferredReload := False;
  if FUntitled then Exit;
  if FileStamp(FFileName, t, s, id) then
  begin
    FDiskTime := t;
    FDiskSize := s;
    FDiskId := id;
    FHasStamp := True;
  end;
end;

function TDocument.CheckDiskChange: TDiskChange;
var
  t, s, id: Int64;
begin
  Result := dcNone;
  if FUntitled or not FHasStamp then Exit;
  if not FileStamp(FFileName, t, s, id) then
    Exit(dcDeleted); // le fichier a disparu du disque
  if (t <> FDiskTime) or (s <> FDiskSize) or (id <> FDiskId) then
    Result := dcModified;
end;

procedure TDocument.MarkOrphan;
begin
  FHasStamp := False; // ne plus surveiller (le disque n'a plus ce fichier)
  Modified := True;   // le buffer est la seule copie: le signaler
end;

end.
