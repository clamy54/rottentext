unit uSession;

{$mode objfpc}{$H+}

// Session: session.json + un tampon session/uN.txt par untitled non sauvegarde
// (leur contenu EST la session, ils ne sont pas promptes au quit). Fichier
// semi-fiable: plafonds, chemins assainis, noms de tampons sans traversal.

interface

uses
  Classes, SysUtils, uDocumentManager;

type
  TSessEntry = record
    Path: string;   // '' = untitled (Buf rempli)
    Buf: string;    // nom du tampon dans session/ (untitled seulement)
    Group: Integer;
    CaretX, CaretY, TopLine: Integer;
    Enc: Integer;   // encodage au dernier quit (-1 = laisser la detection)
    Syntax: string; // nom du langage choisi ('' / 'Plain Text' = aucun)
    Hex: Boolean;   // fichier TEXTE force en vue hex a la main (Reopen > Hex)
  end;
  TSession = record
    Entries: array of TSessEntry;
    Split: Boolean;
    ActiveGroup: Integer;
    Shown: array[0..1] of Integer; // entree montree par groupe (-1 = aucune)
  end;

function SessionLoad(out S: TSession): Boolean;
// False = un untitled non vierge n'est pas garanti restaurable: la fermeture
// doit repasser par les prompts au lieu de perdre les notes en silence
function SessionSaveFrom(AMgr: TDocumentManager): Boolean;
procedure SessionRestoreInto(AMgr: TDocumentManager; const S: TSession);

implementation

uses
  fpjson, jsonparser, uSafeSave, uDocument, uEncoding, uRecent, uHighlight;

const
  PROBE_BUDGET_MS   = 2000;             // budget TOTAL des sondes lentes
  // meme borne a l'ecriture et a la relecture: un untitled ne doit jamais etre
  // ecrit puis refuse au chargement
  MAX_SESSION_BYTES = 2 * 1024 * 1024;
  MAX_SESSION_FILES = 64;
  MAX_BUF_BYTES     = 64 * 1024 * 1024;
  MAX_PATH_LEN      = 4096;

function ConfigDir: string;
begin
  Result := IncludeTrailingPathDelimiter(GetAppConfigDir(False));
end;

function SessionFile: string;
begin
  Result := ConfigDir + 'session.json';
end;

function SessionDir: string;
begin
  Result := ConfigDir + 'session' + PathDelim;
end;

// ---------- sonde d'accessibilite

{$IFDEF WINDOWS}
function GetDriveTypeW(lpRootPathName: PWideChar): LongWord; stdcall;
  external 'kernel32.dll' name 'GetDriveTypeW';

const
  DRIVE_FIXED = 3;
{$ENDIF}

// FileExists sur un partage mort bloque des dizaines de secondes: hors disque
// fixe local, on sonde en thread
function SlowPath(const APath: string): Boolean;
{$IFDEF WINDOWS}
var
  w: UnicodeString;
begin
  Result := True;
  if (Length(APath) >= 3) and (APath[2] = ':') and (APath[3] = '\') then
  begin
    w := UnicodeString(Copy(APath, 1, 3)); // 'C:\'
    Result := GetDriveTypeW(PWideChar(w)) <> DRIVE_FIXED;
  end;
end;
{$ELSE}
begin
  // pas de classification portable (NFS et cie): tout passe par un thread
  Result := True;
end;
{$ENDIF}

type
  TProbeThread = class(TThread)
  private
    FIndex: Integer;
  protected
    procedure Execute; override;
  public
    constructor Create(AIndex: Integer);
  end;

var
  // globales jamais liberees: un thread encore bloque apres le budget ecrit
  // dans de la memoire toujours vivante
  ProbePaths: array of string;
  // 0 en cours, 1 accessible, 2 inaccessible. UNE variable en InterLockedExchange
  // (barriere pleine): avec un couple ok/done, ARM64 verrait 'done' avant 'ok'
  ProbeState: array of LongInt;

constructor TProbeThread.Create(AIndex: Integer);
begin
  FIndex := AIndex;
  FreeOnTerminate := True;
  inherited Create(False);
end;

procedure TProbeThread.Execute;
begin
  if FileExists(ProbePaths[FIndex]) then
    InterLockedExchange(ProbeState[FIndex], 1)
  else
    InterLockedExchange(ProbeState[FIndex], 2);
end;

// pas de reponse dans le budget = entree sautee, le lancement reste rapide
procedure RunProbes;
var
  i: Integer;
  deadline: QWord;
  alldone: Boolean;
begin
  SetLength(ProbeState, Length(ProbePaths));
  for i := 0 to High(ProbePaths) do
    ProbeState[i] := 0;
  for i := 0 to High(ProbePaths) do
    TProbeThread.Create(i);
  deadline := GetTickCount64 + PROBE_BUDGET_MS;
  repeat
    alldone := True;
    for i := 0 to High(ProbePaths) do
      if ProbeState[i] = 0 then
      begin
        alldone := False;
        Break;
      end;
    if alldone then Exit;
    Sleep(15);
  until GetTickCount64 >= deadline;
end;

// ---------- lecture

function JInt(AObj: TJSONObject; const AKey: string; ADef: Integer): Integer;
var
  jd: TJSONData;
begin
  Result := ADef;
  jd := AObj.Find(AKey);
  if (jd <> nil) and (jd.JSONType = jtNumber) then
    try
      Result := jd.AsInteger;
    except
      Result := ADef;
    end;
end;

function JStr(AObj: TJSONObject; const AKey: string): string;
var
  jd: TJSONData;
begin
  Result := '';
  jd := AObj.Find(AKey);
  if (jd <> nil) and (jd.JSONType = jtString) then
    Result := jd.AsString;
end;

function PathOK(const S: string): Boolean;
var
  i: Integer;
begin
  Result := False;
  if (S = '') or (Length(S) > MAX_PATH_LEN) then Exit;
  for i := 1 to Length(S) do
    if S[i] < ' ' then Exit;
  Result := True;
end;

// nom simple, pas de chemin: anti-traversal
function BufOK(const S: string): Boolean;
begin
  Result := (S <> '') and (Length(S) <= 64) and (ExtractFileName(S) = S);
end;

// GetJSON refuse un BOM UTF-8
procedure StripBom(var S: string);
begin
  if (Length(S) >= 3) and (S[1] = #$EF) and (S[2] = #$BB) and (S[3] = #$BF) then
    Delete(S, 1, 3);
end;

function SessionLoad(out S: TSession): Boolean;
var
  fs: TFileStream;
  data: string;
  root: TJSONData;
  obj, e: TJSONObject;
  arr: TJSONArray;
  i, n: Integer;
  raw: array of TSessEntry;
  cur: TSessEntry;
  keepMap: array of Integer; // index brut -> index filtre (-1 = saute)
  slow: array of Integer;    // index brut des chemins a sonder en thread
  rawShown: array[0..1] of Integer; // index brut du doc montre par groupe
begin
  Result := False;
  S.Entries := nil;
  S.Split := False;
  S.ActiveGroup := 0;
  S.Shown[0] := -1;
  S.Shown[1] := -1;
  // rattrapage des sessions nees avant le durcissement (0644/0755); les
  // tampons u*.txt repasseront en 0600 au prochain save, le 0700 du dossier
  // les couvre des maintenant
  MakePrivateDir(SessionDir);
  MakePrivateFile(SessionFile);
  root := nil;
  try
    try
      if not FileExists(SessionFile) then Exit;
      fs := TFileStream.Create(SessionFile, fmOpenRead or fmShareDenyNone);
      try
        if (fs.Size <= 0) or (fs.Size > MAX_SESSION_BYTES) then Exit;
        SetLength(data, fs.Size);
        fs.ReadBuffer(data[1], fs.Size);
      finally
        fs.Free;
      end;
      StripBom(data);
      root := GetJSON(data);
      if (root = nil) or (root.JSONType <> jtObject) then Exit;
      obj := TJSONObject(root);
      S.Split := JInt(obj, 'split', 0) <> 0;
      S.ActiveGroup := JInt(obj, 'activeGroup', 0);
      if (S.ActiveGroup < 0) or (S.ActiveGroup > 1) then S.ActiveGroup := 0;
      S.Shown[0] := JInt(obj, 'shown0', -1);
      S.Shown[1] := JInt(obj, 'shown1', -1);
      if (obj.Find('files') = nil) or
         (obj.Find('files').JSONType <> jtArray) then Exit;
      arr := TJSONArray(obj.Find('files'));
      SetLength(raw, 0);
      rawShown[0] := -1;
      rawShown[1] := -1;
      for i := 0 to arr.Count - 1 do
      begin
        if Length(raw) >= MAX_SESSION_FILES then Break;
        if arr[i].JSONType <> jtObject then Continue;
        e := TJSONObject(arr[i]);
        cur.Path := JStr(e, 'path');
        cur.Buf := JStr(e, 'buf');
        cur.Group := JInt(e, 'group', 0);
        if (cur.Group < 0) or (cur.Group > 1) then cur.Group := 0;
        cur.CaretX := JInt(e, 'caretX', 1);
        cur.CaretY := JInt(e, 'caretY', 1);
        cur.TopLine := JInt(e, 'top', 1);
        cur.Enc := JInt(e, 'enc', -1);
        cur.Syntax := JStr(e, 'syntax');
        cur.Hex := JInt(e, 'hex', 0) <> 0;
        // exactement UNE source: un chemin valide OU un tampon valide
        if cur.Path <> '' then
        begin
          cur.Buf := '';
          if not PathOK(cur.Path) then Continue;
        end
        else if not BufOK(cur.Buf) then
          Continue;
        SetLength(raw, Length(raw) + 1);
        raw[High(raw)] := cur;
        if i = S.Shown[0] then rawShown[0] := High(raw);
        if i = S.Shown[1] then rawShown[1] := High(raw);
      end;
    except
      Exit; // JSON malforme: pas de session
    end;
  finally
    root.Free;
  end;

  // sonde d'accessibilite: fixes en direct, le reste en threads a budget
  SetLength(keepMap, Length(raw));
  SetLength(slow, 0);
  SetLength(ProbePaths, 0);
  for i := 0 to High(raw) do
  begin
    keepMap[i] := -2; // a decider
    if raw[i].Path = '' then
    begin
      if not FileExists(SessionDir + raw[i].Buf) then keepMap[i] := -1;
    end
    else if not SlowPath(raw[i].Path) then
    begin
      if not FileExists(raw[i].Path) then keepMap[i] := -1;
    end
    else
    begin
      SetLength(slow, Length(slow) + 1);
      slow[High(slow)] := i;
      SetLength(ProbePaths, Length(ProbePaths) + 1);
      ProbePaths[High(ProbePaths)] := raw[i].Path;
    end;
  end;
  if Length(ProbePaths) > 0 then
  begin
    RunProbes;
    for i := 0 to High(slow) do
      if ProbeState[i] <> 1 then
        keepMap[slow[i]] := -1; // inaccessible ou pas repondu a temps: saute
  end;

  // filtrage + remap des index "shown"
  n := 0;
  for i := 0 to High(raw) do
    if keepMap[i] <> -1 then
    begin
      keepMap[i] := n;
      SetLength(S.Entries, n + 1);
      S.Entries[n] := raw[i];
      Inc(n);
    end;
  // une entree ecartee au parse decale les index de 'files': on repasse par
  // l'index BRUT memorise a l'acceptation
  for i := 0 to 1 do
    if (rawShown[i] >= 0) and (keepMap[rawShown[i]] >= 0) then
      S.Shown[i] := keepMap[rawShown[i]]
    else
      S.Shown[i] := -1;
  Result := Length(S.Entries) > 0;
end;

// ---------- ecriture

// untitled jamais touche: sans ce filtre les vierges s'accumulent a chaque cycle
function DocIsBlank(D: TDocument): Boolean;
begin
  Result := D.Untitled and not D.Modified and not D.IsHex and
    (D.View.Syn.Lines.Count <= 1) and
    ((D.View.Syn.Lines.Count = 0) or (D.View.Syn.Lines[0] = ''));
end;

function WriteBuffer(const AName: string; ALines: TStrings): Boolean;
var
  st: TStream;
  tmp, data: string;
begin
  Result := False;
  tmp := '';
  try
    data := ALines.Text;
    // le loader refuserait ce tampon: l'ecrire serait pretendre que la note
    // est sauvee alors qu'elle ne reviendra pas
    if Length(data) > MAX_BUF_BYTES then Exit;
    st := CreateTempIn(SessionDir + AName, tmp);
    try
      if data <> '' then
        st.WriteBuffer(data[1], Length(data));
    finally
      st.Free;
    end;
    Result := ReplaceByRenamePrivate(tmp, SessionDir + AName);
    if not Result then
      DeleteFile(tmp);
  except
    Result := False;
    // pas de fragment de note laisse trainer dans un .tmp
    if tmp <> '' then DeleteFile(tmp);
  end;
end;

// generation d'un nom de tampon ('u3_1.txt' -> 3, legacy 'u2.txt' -> 2)
function BufGenOf(const AName: string): Integer;
var
  i, v: Integer;
begin
  Result := -1;
  if (Length(AName) < 2) or (AName[1] <> 'u') or
     not (AName[2] in ['0'..'9']) then Exit;
  v := 0;
  i := 2;
  while (i <= Length(AName)) and (AName[i] in ['0'..'9']) do
  begin
    v := v * 10 + Ord(AName[i]) - Ord('0');
    if v > 100000000 then Exit; // dechet
    Inc(i);
  end;
  Result := v;
end;

function ReadBuffer(const AName: string; out AContent: string): Boolean;
var
  fs: TFileStream;
begin
  Result := False;
  AContent := '';
  try
    fs := TFileStream.Create(SessionDir + AName, fmOpenRead or fmShareDenyNone);
    try
      if (fs.Size < 0) or (fs.Size > MAX_BUF_BYTES) then Exit;
      SetLength(AContent, fs.Size);
      if fs.Size > 0 then
        fs.ReadBuffer(AContent[1], fs.Size);
      Result := True;
    finally
      fs.Free;
    end;
    // un tampon retouche a la main ne doit pas polluer la 1re ligne (= nom d'onglet)
    StripBom(AContent);
  except
    Result := False;
    AContent := '';
  end;
end;

// Generationnel: tampons ecrits sous des noms NEUFS, json commite seulement si
// tous ont reussi, ancienne generation purgee APRES le commit. Sinon une
// sauvegarde ratee detruirait le dernier backup valide (et l'autosave repasse).
function SessionSaveFrom(AMgr: TDocumentManager): Boolean;
var
  rootObj, e: TJSONObject;
  arr: TJSONArray;
  kept: TStringList;
  st: TStream;
  d: TDocument;
  i, g, gen, bufN, pos: Integer;
  bufName, data, tmp: string;
  sr: TSearchRec;
  committed: Boolean;
begin
  Result := True; // toute perte possible d'untitled le passe a False
  kept := nil;
  tmp := '';
  committed := False;
  try
    ForceDirectories(SessionDir);
    MakePrivateDir(ConfigDir);
    MakePrivateDir(SessionDir);
    gen := 0;
    if FindFirst(SessionDir + 'u*.txt', faAnyFile, sr) = 0 then
    begin
      repeat
        g := BufGenOf(sr.Name);
        if g >= gen then gen := g + 1;
      until FindNext(sr) <> 0;
      SysUtils.FindClose(sr);
    end;
    kept := TStringList.Create;
    rootObj := TJSONObject.Create;
    try
      arr := TJSONArray.Create;
      rootObj.Add('files', arr);
      rootObj.Add('split', Ord(AMgr.Split));
      rootObj.Add('activeGroup', AMgr.ActiveGroup);
      rootObj.Add('shown0', -1);
      rootObj.Add('shown1', -1);
      bufN := 0;
      for i := 0 to AMgr.Count - 1 do
      begin
        d := AMgr.Docs[i];
        e := nil;
        // le loader tronque a ce plafond: un untitled dans la coupe serait perdu
        if arr.Count >= MAX_SESSION_FILES then
        begin
          if d.Untitled and not DocIsBlank(d) then Result := False;
          Continue;
        end;
        if not d.Untitled then
        begin
          e := TJSONObject.Create;
          e.Add('path', d.FileName);
          e.Add('enc', d.Encoding);
        end
        else if not DocIsBlank(d) then
        begin
          bufName := Format('u%d_%d.txt', [gen, bufN]);
          if WriteBuffer(bufName, d.View.Syn.Lines) then
          begin
            // le tampon existe deja sur disque: l'enregistrer dans kept AVANT
            // toute allocation, sinon l'except ne saurait pas le retirer
            try
              kept.Add(bufName);
            except
              DeleteFile(SessionDir + bufName);
              raise;
            end;
            e := TJSONObject.Create;
            e.Add('buf', bufName);
            Inc(bufN);
          end
          else
            Result := False; // note pas ecrite (disque plein, trop grosse)
        end;
        if e = nil then Continue;
        e.Add('group', d.Group);
        e.Add('hex', Ord(d.IsHex));
        if not d.IsHex then
        begin
          e.Add('caretX', d.View.Syn.CaretX);
          e.Add('caretY', d.View.Syn.CaretY);
          e.Add('top', d.View.Syn.TopLine);
          // un untitled n'a pas d'extension a auto-detecter au restore
          e.Add('syntax', LanguageLabel(d.View.Syn.Highlighter));
        end;
        arr.Add(e);
        pos := arr.Count - 1;
        if d = AMgr.GroupDoc(0) then rootObj.Integers['shown0'] := pos;
        if d = AMgr.GroupDoc(1) then rootObj.Integers['shown1'] := pos;
      end;
      data := rootObj.FormatJSON;
    finally
      rootObj.Free;
    end;
    // meme borne que le loader: un json qu'il refuserait = session perdue
    if Length(data) > MAX_SESSION_BYTES then Result := False;
    if Result then
    begin
      st := CreateTempIn(SessionFile, tmp);
      try
        if data <> '' then
          st.WriteBuffer(data[1], Length(data));
      finally
        st.Free;
      end;
      if ReplaceByRenamePrivate(tmp, SessionFile) then
      begin
        tmp := '';
        committed := True; // a partir d'ici les tampons neufs SONT la session
      end
      else
      begin
        DeleteFile(tmp);
        tmp := '';
        Result := False;
      end;
    end;
    if Result then
    begin
      // commit fait: purger les generations precedentes et les strays
      if FindFirst(SessionDir + 'u*.txt', faAnyFile, sr) = 0 then
      begin
        repeat
          if kept.IndexOf(sr.Name) < 0 then
            DeleteFile(SessionDir + sr.Name);
        until FindNext(sr) <> 0;
        SysUtils.FindClose(sr);
      end;
    end
    else
      // abort: l'ancien json et ses tampons restent le backup valide
      for i := 0 to kept.Count - 1 do
        DeleteFile(SessionDir + kept[i]);
  except
    Result := False;
    if tmp <> '' then DeleteFile(tmp);
    // apres commit les tampons neufs SONT la session: une exception pendant la
    // purge des vieilles generations ne doit pas la detruire
    if (kept <> nil) and not committed then
      for i := 0 to kept.Count - 1 do
        DeleteFile(SessionDir + kept[i]);
  end;
  kept.Free;
end;

// ---------- restauration

function MgrIndexOf(AMgr: TDocumentManager; ADoc: TDocument): Integer;
var
  i: Integer;
begin
  Result := -1;
  for i := 0 to AMgr.Count - 1 do
    if AMgr.Docs[i] = ADoc then Exit(i);
end;

procedure RestoreCaret(D: TDocument; const E: TSessEntry);
var
  cx, cy, top: Integer;
begin
  if D.IsHex then Exit;
  cy := E.CaretY;
  if cy < 1 then cy := 1;
  if cy > D.View.Syn.Lines.Count then cy := D.View.Syn.Lines.Count;
  cx := E.CaretX;
  if cx < 1 then cx := 1;
  top := E.TopLine;
  if top < 1 then top := 1;
  if top > D.View.Syn.Lines.Count then top := D.View.Syn.Lines.Count;
  D.View.Syn.CaretXY := Classes.Point(cx, cy); // SynEdit borne X lui-meme
  D.View.Syn.TopLine := top;
end;

procedure SessionRestoreInto(AMgr: TDocumentManager; const S: TSession);
var
  pre, docs: array of TDocument;
  gotGroup: array[0..1] of Boolean;
  i, g, idx, ag, si: Integer;
  d: TDocument;
  content: string;

  procedure ShowEntry(AEntry: Integer);
  var
    mi: Integer;
  begin
    if (AEntry < 0) or (AEntry > High(docs)) or (docs[AEntry] = nil) then Exit;
    mi := MgrIndexOf(AMgr, docs[AEntry]);
    if mi >= 0 then AMgr.Activate(mi);
  end;

begin
  if Length(S.Entries) = 0 then Exit;
  SetLength(pre, AMgr.Count);
  for i := 0 to AMgr.Count - 1 do
    pre[i] := AMgr.Docs[i];
  SetLength(docs, Length(S.Entries));
  gotGroup[0] := False;
  gotGroup[1] := False;
  // restaurer une session ne doit pas reordonner la MRU Open Recent
  RecentSuspended := True;
  try
    for i := 0 to High(S.Entries) do
    begin
      docs[i] := nil;
      g := S.Entries[i].Group;
      if (g = 1) and not AMgr.Split then g := 0;
      AMgr.ActivateGroup(g);
      if S.Entries[i].Path <> '' then
        d := AMgr.OpenFile(S.Entries[i].Path) // disparu depuis la sonde: nil
      else
      begin
        if not ReadBuffer(S.Entries[i].Buf, content) then Continue;
        d := AMgr.NewFile(g);
        d.View.Syn.Lines.Text := content;
        d.Modified := True; // tampon = contenu jamais sauve par definition
      end;
      if d = nil then Continue;
      docs[i] := d;
      gotGroup[d.Group] := True;
      // OpenFile a auto-detecte du texte: rejouer les choix manuels du dernier
      // quit (hex, encodage, coloration). Doc pas encore modifie = pas de prompt.
      if S.Entries[i].Hex and not d.IsHex then
        AMgr.ReopenActiveHex;
      if (S.Entries[i].Path <> '') and not d.IsHex and
         (S.Entries[i].Enc >= 0) and (S.Entries[i].Enc <= High(Encodings)) and
         (d.Encoding <> S.Entries[i].Enc) then
        AMgr.ReopenActiveWithEncoding(S.Entries[i].Enc);
      RestoreCaret(d, S.Entries[i]);
      if not d.IsHex and (S.Entries[i].Syntax <> '') then
      begin
        si := IndexForName(S.Entries[i].Syntax);
        if si >= 0 then
          d.View.Syn.Highlighter := HighlighterByIndex(si)
        else if SameText(S.Entries[i].Syntax, 'Plain Text') then
          d.View.Syn.Highlighter := nil;
      end;
    end;
  finally
    RecentSuspended := False;
  end;
  // vierges du boot et du split: a jeter si leur groupe a recu des onglets
  for i := 0 to High(pre) do
  begin
    idx := MgrIndexOf(AMgr, pre[i]); // -1 si deja recycle/ferme
    if idx < 0 then Continue;
    d := AMgr.Docs[idx];
    if gotGroup[d.Group] and DocIsBlank(d) then
      AMgr.CloseDoc(idx);
  end;
  // le groupe actif reprend le focus en dernier
  ag := S.ActiveGroup;
  if (ag < 0) or (ag > 1) then ag := 0;
  if AMgr.Split then
    ShowEntry(S.Shown[1 - ag]);
  ShowEntry(S.Shown[ag]);
end;

end.
