unit uActions;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types, Controls, Forms, Menus, Dialogs, Process, PrintersDlgs,
  Clipbrd, LazUTF8, SynEdit, SynEditKeyCmds, SynMacroRecorder,
  uDocumentManager, uDocument, uEditorView, uHighlight, uFindBar, uPrint,
  uHexView, uTextOps, uRecent, uThemeLoad, uSettings, uOps, uSecretPrompt, uLdap,
  uLdif, uLdifDlg, uNet, uJwt, uExtract, uTimeConv, uProto, uNmap, uHttp,
  uDiffView, uYaml, uKube, uHelm, uEnv, uX509, uCompose, uQuadlet, uTf, uIni,
  uToml, uEol, uCron, uLogTools, uMailTrace, DateUtils;

type
  TAppActions = class
  private
    FMgr: TDocumentManager;
    FFindBar: TFindBar;
    FRec: TSynMacroRecorder;
    FMacroRecordItem: TMenuItem;
    FMacroPlayItem: TMenuItem;
    FSaveItem: TMenuItem;
    FSaveEncItem: TMenuItem;
    FSideBarItem: TMenuItem;
    FSplitItem: TMenuItem;
    FOnMacroStateChange: TNotifyEvent;
    FOnToggleSideBar: TNotifyEvent;
    FOnToggleSplit: TNotifyEvent;
    FOnThemeChanged: TNotifyEvent;
    FOnCommandPalette: TNotifyEvent;
    function Ed: TSynEdit;
    // False = l'utilisateur a annule
    function ConfirmLargeText(AOnSel: Boolean): Boolean;
    function ConfirmLargeFile(const APath: string): Boolean;
    procedure Cmd(ACmd: TSynEditorCommand);
    procedure SpawnWindow(const AArg: string);
    procedure ApplyViewSettingsToAll;
    procedure MacroStateChanged(Sender: TObject);
    procedure ApplyCase(AMode: Integer);
    procedure ToggleLineComment(AEd: TSynEdit; const ALc: string; AL1, AL2: Integer);
    procedure ToggleBlockComment(AEd: TSynEdit; const ABo, ABc: string);
  public
    constructor Create(AMgr: TDocumentManager; ARecOwner: TComponent);
    destructor Destroy; override;
    procedure AttachFindBar(ABar: TFindBar);
    procedure SetMacroItems(ARecordItem, APlayItem: TMenuItem);
    procedure SyncMacroEditors;
    function MacroRecordingIndex: Integer; // -1 si aucun enregistrement
    property OnMacroStateChange: TNotifyEvent read FOnMacroStateChange write FOnMacroStateChange;
    property OnToggleSideBar: TNotifyEvent read FOnToggleSideBar write FOnToggleSideBar;
    property OnToggleSplit: TNotifyEvent read FOnToggleSplit write FOnToggleSplit;
    property OnThemeChanged: TNotifyEvent read FOnThemeChanged write FOnThemeChanged;
    property OnCommandPalette: TNotifyEvent read FOnCommandPalette write FOnCommandPalette;
    property Mgr: TDocumentManager read FMgr;
    // File
    procedure FileNew(Sender: TObject);
    procedure FileOpen(Sender: TObject);
    procedure FileOpenFolder(Sender: TObject);
    procedure FileSave(Sender: TObject);
    procedure FileSaveAs(Sender: TObject);
    procedure FileSaveAll(Sender: TObject);
    procedure FileClose(Sender: TObject);
    procedure FileCloseAll(Sender: TObject);
    procedure FileRevert(Sender: TObject);
    procedure FilePrint(Sender: TObject);
    procedure FileNewWindow(Sender: TObject);   // fenetre = process
    procedure FileCloseWindow(Sender: TObject);
    procedure FileQuit(Sender: TObject);
    // Tag = index dans uEncoding.Encodings
    procedure FileSaveWithEncoding(Sender: TObject);
    procedure FileReopenWithEncoding(Sender: TObject);
    procedure FileReopenHex(Sender: TObject);
    procedure FileSaveHex(Sender: TObject);
    procedure SetFileItems(ASaveItem, ASaveEncItem: TMenuItem);
    procedure UpdateFileItems;
    // Edit
    procedure EditUndo(Sender: TObject);
    procedure EditRedo(Sender: TObject);
    procedure EditCut(Sender: TObject);
    procedure EditCopy(Sender: TObject);
    procedure EditPaste(Sender: TObject);
    procedure EditPasteIndent(Sender: TObject);
    procedure EditIndent(Sender: TObject);
    procedure EditUnindent(Sender: TObject);
    procedure EditDeleteLine(Sender: TObject);
    procedure EditToggleComment(Sender: TObject);
    procedure EditUpperCase(Sender: TObject);
    procedure EditLowerCase(Sender: TObject);
    procedure EditTitleCase(Sender: TObject);
    procedure EditSwapCase(Sender: TObject);
    procedure EditSortLines(Sender: TObject);
    procedure EditExpandTabs(Sender: TObject);
    // Tag = index dans la MRU
    procedure FileOpenRecent(Sender: TObject);
    procedure FileClearRecent(Sender: TObject);
    // View
    procedure ViewSideBar(Sender: TObject);
    procedure SetSideBarItem(AItem: TMenuItem);
    procedure SetSideBarChecked(AVisible: Boolean);
    procedure ViewSplit(Sender: TObject);
    procedure SetSplitItem(AItem: TMenuItem);
    procedure SetSplitChecked(AOn: Boolean);
    procedure ViewTheme(Sender: TObject); // Tag = index dans uThemeLoad
    procedure SetSyntax(Sender: TObject); // Tag: 0 = Plain Text, N = syntaxe N-1
    procedure ViewTabWidth(Sender: TObject);   // Tag = 1..8
    procedure ViewWordWrap(Sender: TObject);
    procedure ViewWrapColumn(Sender: TObject); // Tag = 0 (Automatic) ou colonne
    procedure ViewShowInvisibles(Sender: TObject);
    procedure ViewMapTabToSpace(Sender: TObject);
    procedure ViewCommandPalette(Sender: TObject);
    // Help
    procedure HelpAbout(Sender: TObject);
    // Find
    procedure FindShow(Sender: TObject);
    procedure FindNext(Sender: TObject);
    procedure FindPrev(Sender: TObject);
    procedure ReplaceShow(Sender: TObject);
    procedure ReplaceNext(Sender: TObject);
    procedure ReplaceAll(Sender: TObject);
    procedure FindGotoOffset(Sender: TObject); // vue hex seulement
    // Selection
    procedure SelSelectAll(Sender: TObject);
    procedure SelSplitLines(Sender: TObject);
    procedure SelSingle(Sender: TObject);
    procedure SelExpandLine(Sender: TObject);
    procedure SelExpandWord(Sender: TObject);
    procedure SelAddPrevLine(Sender: TObject);
    procedure SelAddNextLine(Sender: TObject);
    procedure SelExpandBrackets(Sender: TObject);
    procedure SelFillLorem(Sender: TObject);
    // Macro
    procedure MacroToggleRecord(Sender: TObject);
    procedure MacroPlayback(Sender: TObject);
    // Tools: le Tag de l'item de menu porte la variante
    procedure ToolsTransform(Sender: TObject);
    procedure ToolsHashFile(Sender: TObject);
    procedure ToolsHMAC(Sender: TObject);
    procedure ToolsChecksumComment(Sender: TObject);
    procedure ToolsInsert(Sender: TObject);
    procedure ToolsGenPassword(Sender: TObject);
    procedure ToolsHtpasswd(Sender: TObject);
    procedure ToolsLdapPassword(Sender: TObject);
    procedure ToolsLdifEntry(Sender: TObject);
    procedure ToolsLdifRoot(Sender: TObject);
    procedure ToolsLdifOU(Sender: TObject);
    procedure ToolsLdifGroup(Sender: TObject);
    procedure ToolsLdifGroupOfNames(Sender: TObject);
    procedure ToolsLdifService(Sender: TObject);
    procedure ToolsJson(Sender: TObject);
    procedure ToolsXml(Sender: TObject);
    procedure ToolsYaml(Sender: TObject);
    procedure ToolsYamlDiff(Sender: TObject);
    procedure ToolsKube(Sender: TObject);
    procedure ToolsEnv(Sender: TObject);
    procedure ToolsCompose(Sender: TObject);
    procedure ToolsQuadlet(Sender: TObject);
    procedure ToolsTerraform(Sender: TObject);
    procedure ToolsIni(Sender: TObject);
    procedure ToolsToml(Sender: TObject);
    procedure ToolsEol(Sender: TObject);
    procedure ToolsCron(Sender: TObject);
    procedure ToolsLog(Sender: TObject);
    procedure ToolsHelm(Sender: TObject);
    procedure ToolsHelmIssues(Sender: TObject);
    procedure ToolsHelmFolder(Sender: TObject);
    procedure ToolsHelmSnippet(Sender: TObject);
    procedure ToolsHelmQuote(Sender: TObject);
    procedure ToolsHelmToYaml(Sender: TObject);
    procedure ToolsIpCalc(Sender: TObject);
    procedure ToolsTimestamp(Sender: TObject);
    procedure ToolsJwt(Sender: TObject);
    procedure ToolsMailTrace(Sender: TObject);
    procedure ToolsX509(Sender: TObject);
    procedure ToolsPerms(Sender: TObject);
    procedure ToolsExtract(Sender: TObject);
    procedure ToolsProtocol(Sender: TObject);
    procedure ToolsNmap(Sender: TObject);
    procedure ToolsHttp(Sender: TObject);
    procedure ToolsDiff(Sender: TObject);
  end;

// Un dialogue NATIF n'incremente pas Application.ModalLevel: pendant ce trou le
// timer IPC, le check de modif externe ou un drop peuvent fermer le document que
// l'action tient. uMain les suspend tant que le verrou est pose. Compteur, pas
// booleen: une action imbriquee ne relache pas le verrou de l'englobante.
procedure BeginActionModal;
procedure EndActionModal;
function ActionModalActive: Boolean;

implementation

uses
  uAbout, uMain; // implementation seulement: uMain nous use en interface

var
  FActionModal: Integer = 0;

procedure BeginActionModal;
begin
  Inc(FActionModal);
end;

procedure EndActionModal;
begin
  if FActionModal > 0 then Dec(FActionModal);
end;

function ActionModalActive: Boolean;
begin
  Result := FActionModal > 0;
end;

procedure TAppActions.HelpAbout(Sender: TObject);
begin
  ShowAbout(RT_VERSION);
end;

constructor TAppActions.Create(AMgr: TDocumentManager; ARecOwner: TComponent);
begin
  FMgr := AMgr;
  // owner OBLIGATOIRE: avec Owner=nil SynEdit croit le plugin "owned by editor"
  // et le Free quand le dernier editeur ferme -> ref pendouillante
  FRec := TSynMacroRecorder.Create(ARecOwner);
  FRec.RecordShortCut := 0;
  FRec.PlaybackShortCut := 0;
  FRec.OnStateChange := @MacroStateChanged;
end;

destructor TAppActions.Destroy;
begin
  FRec.Free;
  inherited Destroy;
end;

procedure TAppActions.AttachFindBar(ABar: TFindBar);
begin
  FFindBar := ABar;
end;

procedure TAppActions.FindShow(Sender: TObject);    begin if FFindBar <> nil then FFindBar.ShowFind; end;
procedure TAppActions.FindNext(Sender: TObject);    begin if FFindBar <> nil then FFindBar.FindNext; end;
procedure TAppActions.FindPrev(Sender: TObject);    begin if FFindBar <> nil then FFindBar.FindPrev; end;
procedure TAppActions.ReplaceShow(Sender: TObject); begin if FFindBar <> nil then FFindBar.ShowReplace; end;
procedure TAppActions.ReplaceNext(Sender: TObject); begin if FFindBar <> nil then FFindBar.ReplaceNext; end;
procedure TAppActions.ReplaceAll(Sender: TObject);  begin if FFindBar <> nil then FFindBar.ReplaceAll; end;

function TAppActions.Ed: TSynEdit;
begin
  // doc hex: le SynEdit existe mais est cache et vide, une action texte qui le
  // viserait marquerait le doc modifie pour rien
  if (FMgr.ActiveDoc <> nil) and not FMgr.ActiveDoc.IsHex then
    Result := FMgr.ActiveDoc.View.Syn
  else
    Result := nil;
end;

function TAppActions.ConfirmLargeText(AOnSel: Boolean): Boolean;
const
  BIG_LINES = 50000; // au-dela, materialiser/parser sur l'UI thread coince
var
  e: TSynEdit;
  big: Boolean;
begin
  Result := True;
  e := Ed;
  if (e = nil) or (FMgr.ActiveDoc = nil) or not FMgr.ActiveDoc.LargeFile then Exit;
  // taille estimee par les coords de lignes, AVANT toute copie du texte
  if AOnSel then big := (e.BlockEnd.Y - e.BlockBegin.Y + 1) > BIG_LINES
  else big := True;
  if big then
    Result := MessageDlg('RottenText',
      'Process this large amount of text? This can take a while.',
      mtConfirmation, [mbYes, mbCancel], 0) = mrYes;
end;

function TAppActions.ConfirmLargeFile(const APath: string): Boolean;
const
  BIG_FILE = 16 * 1024 * 1024;
var
  sr: TSearchRec;
  sz: Int64;
begin
  Result := True;
  sz := 0;
  if SysUtils.FindFirst(APath, faAnyFile, sr) = 0 then
  begin
    sz := sr.Size;
    SysUtils.FindClose(sr);
  end;
  if sz > BIG_FILE then
    Result := MessageDlg('RottenText',
      Format('That file is %d MB. Load and parse it anyway?', [sz div (1024 * 1024)]),
      mtConfirmation, [mbYes, mbCancel], 0) = mrYes;
end;

procedure TAppActions.Cmd(ACmd: TSynEditorCommand);
begin
  if Ed <> nil then
  begin
    if Ed.CanFocus then Ed.SetFocus;
    Ed.CommandProcessor(ACmd, '', nil);
  end;
end;

procedure TAppActions.FileNew(Sender: TObject);   begin FMgr.NewFile; end;
procedure TAppActions.FileOpen(Sender: TObject);  begin FMgr.OpenDialog; end;

// le dossier s'ouvre dans une NOUVELLE fenetre, via l'argument CLI <dossier>
procedure TAppActions.FileOpenFolder(Sender: TObject);
var
  dlg: TSelectDirectoryDialog;
begin
  dlg := TSelectDirectoryDialog.Create(nil);
  BeginActionModal; // dialogue natif
  try
    if dlg.Execute then
      SpawnWindow(dlg.FileName);
  finally
    EndActionModal;
    dlg.Free;
  end;
end;

// une fenetre = un process
procedure TAppActions.SpawnWindow(const AArg: string);
var
  p: TProcess;
begin
  try
    p := TProcess.Create(nil);
    try
      p.Executable := ParamStr(0);
      if AArg <> '' then
        p.Parameters.Add(AArg);
      p.Execute;
    finally
      p.Free;
    end;
  except
    on E: Exception do
      MessageDlg('RottenText', 'Cannot open new window: ' + E.Message,
        mtError, [mbOK], 0);
  end;
end;

procedure TAppActions.ViewSideBar(Sender: TObject);
begin
  if Assigned(FOnToggleSideBar) then
    FOnToggleSideBar(Self);
end;

procedure TAppActions.SetSideBarItem(AItem: TMenuItem);
begin
  FSideBarItem := AItem;
end;

procedure TAppActions.SetSideBarChecked(AVisible: Boolean);
begin
  if FSideBarItem <> nil then
    FSideBarItem.Checked := AVisible;
end;

procedure TAppActions.ViewSplit(Sender: TObject);
begin
  if Assigned(FOnToggleSplit) then
    FOnToggleSplit(Self);
end;

procedure TAppActions.SetSplitItem(AItem: TMenuItem);
begin
  FSplitItem := AItem;
end;

procedure TAppActions.SetSplitChecked(AOn: Boolean);
begin
  if FSplitItem <> nil then
    FSplitItem.Checked := AOn;
end;
procedure TAppActions.FileSave(Sender: TObject);  begin FMgr.SaveActive; end;
procedure TAppActions.FileSaveAs(Sender: TObject);begin FMgr.SaveActiveAs; end;

procedure TAppActions.FileSaveAll(Sender: TObject);
begin
  FMgr.SaveAll;
end;

procedure TAppActions.FileClose(Sender: TObject);    begin FMgr.CloseDoc(FMgr.ActiveIndex); end;
procedure TAppActions.FileCloseAll(Sender: TObject); begin FMgr.CloseAll; end;
procedure TAppActions.FileRevert(Sender: TObject);
begin
  FMgr.RevertActive;
end;

procedure TAppActions.FilePrint(Sender: TObject);
var
  dlg: TPrintDialog;
  doc: TDocument;
begin
  doc := FMgr.ActiveDoc;
  if (doc = nil) or doc.IsHex then Exit;
  // doc capture dans un local puis tenu en travers du dialogue natif: relire
  // ActiveDoc apres le dialogue peut viser un AUTRE onglet
  BeginActionModal;
  try
    dlg := TPrintDialog.Create(nil);
    try
      if not dlg.Execute then Exit;
    finally
      dlg.Free;
    end;
    try
      PrintDocument(doc.DisplayName, doc.View.Syn.Lines,
        doc.View.Syn.Highlighter, RTTabWidth);
    except
      on E: Exception do
        MessageDlg('RottenText', 'Print failed: ' + E.Message, mtError, [mbOK], 0);
    end;
  finally
    EndActionModal;
  end;
end;

// --blank: sans lui la nouvelle fenetre rejouerait la session et dupliquerait
// ses onglets
procedure TAppActions.FileNewWindow(Sender: TObject);
begin
  SpawnWindow('--blank');
end;

// Close via la form: Application.Terminate court-circuite OnCloseQuery, donc le
// prompt de sauvegarde, et perd les docs modifies
procedure TAppActions.FileCloseWindow(Sender: TObject);
begin
  if Application.MainForm <> nil then
    Application.MainForm.Close;
end;

procedure TAppActions.FileQuit(Sender: TObject);
begin
  FileCloseWindow(Sender); // un process par fenetre
end;

procedure TAppActions.FileSaveWithEncoding(Sender: TObject);
begin
  FMgr.SaveActiveWithEncoding((Sender as TMenuItem).Tag);
end;

procedure TAppActions.FileReopenWithEncoding(Sender: TObject);
begin
  FMgr.ReopenActiveWithEncoding((Sender as TMenuItem).Tag);
end;

procedure TAppActions.FileReopenHex(Sender: TObject);
begin
  FMgr.ReopenActiveHex;
end;

procedure TAppActions.FileSaveHex(Sender: TObject);
begin
  if (FMgr.ActiveDoc <> nil) and FMgr.ActiveDoc.IsHex then
    FMgr.SaveActive;
end;

// '1A2B', '0x1A2B' ou '$1A2B'; toujours lu en HEXA
function ParseHexOffset(S: string; out AOfs: Int64): Boolean;
begin
  S := Trim(S);
  if (Length(S) >= 2) and (S[1] = '0') and (UpCase(S[2]) = 'X') then
    Delete(S, 1, 2)
  else if (S <> '') and (S[1] = '$') then
    Delete(S, 1, 1);
  Result := (S <> '') and TryStrToInt64('$' + S, AOfs) and (AOfs >= 0);
end;

procedure TAppActions.FindGotoOffset(Sender: TObject);
var
  s: string;
  ofs: Int64;
begin
  if (FMgr.ActiveDoc = nil) or not FMgr.ActiveDoc.IsHex then Exit;
  // InputQuery et pas InputBox: InputBox rend le DEFAUT a l'annulation
  s := IntToHex(FMgr.ActiveDoc.HexView.CaretOfs, 1);
  if not InputQuery('RottenText', 'Go to offset (hex):', s) then Exit;
  if Trim(s) = '' then Exit;
  if not ParseHexOffset(s, ofs) then
  begin
    MessageDlg('RottenText', Format('Invalid offset: %s', [s]),
      mtWarning, [mbOK], 0);
    Exit;
  end;
  FMgr.ActiveDoc.HexView.GotoOffset(ofs);
  FMgr.ActiveDoc.FocusDoc;
end;

procedure TAppActions.SetFileItems(ASaveItem, ASaveEncItem: TMenuItem);
begin
  FSaveItem := ASaveItem;
  FSaveEncItem := ASaveEncItem;
end;

procedure TAppActions.UpdateFileItems;
var
  ena: Boolean;
begin
  ena := (FMgr.ActiveDoc = nil) or not FMgr.ActiveDoc.ReadOnly;
  if FSaveItem <> nil then FSaveItem.Enabled := ena;
  if FSaveEncItem <> nil then FSaveEncItem.Enabled := ena;
end;

procedure TAppActions.EditUndo(Sender: TObject);   begin Cmd(ecUndo); end;
procedure TAppActions.EditRedo(Sender: TObject);   begin Cmd(ecRedo); end;
procedure TAppActions.EditCut(Sender: TObject);    begin Cmd(ecCut); end;
procedure TAppActions.EditCopy(Sender: TObject);   begin Cmd(ecCopy); end;
procedure TAppActions.EditPaste(Sender: TObject);  begin Cmd(ecPaste); end;
procedure TAppActions.EditIndent(Sender: TObject); begin Cmd(ecBlockIndent); end;
procedure TAppActions.EditUnindent(Sender: TObject);begin Cmd(ecBlockUnindent); end;
procedure TAppActions.EditDeleteLine(Sender: TObject);begin Cmd(ecDeleteLine); end;

procedure TAppActions.EditPasteIndent(Sender: TObject);
var
  e: TSynEdit;
  clip, txt: string;
begin
  e := Ed;
  if e = nil then Exit;
  clip := Clipboard.AsText;
  if clip = '' then Exit;
  if (Pos(#10, clip) = 0) and (Pos(#13, clip) = 0) then
  begin
    Cmd(ecPaste);
    Exit;
  end;
  txt := ReindentForPaste(clip, LeadingWS(e.Lines[e.CaretY - 1]));
  if e.CanFocus then e.SetFocus;
  if e.SelAvail then
    e.SelText := txt
  else
    e.InsertTextAtCaret(txt);
end;

// une selection qui s'arrete en colonne 1 n'inclut pas cette derniere ligne
procedure LineRange(AEd: TSynEdit; out AL1, AL2: Integer);
begin
  if AEd.SelAvail then
  begin
    AL1 := AEd.BlockBegin.Y;
    AL2 := AEd.BlockEnd.Y;
    if (AEd.BlockEnd.X = 1) and (AL2 > AL1) then Dec(AL2);
  end
  else
  begin
    AL1 := AEd.CaretY;
    AL2 := AL1;
  end;
end;

procedure TAppActions.ToggleLineComment(AEd: TSynEdit; const ALc: string;
  AL1, AL2: Integer);
var
  i, n, minInd: Integer;
  s, ws: string;
  all, any, alpha: Boolean;

  // token alphabetique ('REM'): casse ignoree + frontiere exigee, sinon 'REMARK'
  // passerait pour un commentaire
  function Commented(const ALine, ALead: string): Boolean;
  var
    p, after: Integer;
  begin
    p := Length(ALead) + 1;
    if alpha then
    begin
      if not SameText(Copy(ALine, p, Length(ALc)), ALc) then Exit(False);
      after := p + Length(ALc);
      Result := (after > Length(ALine)) or (ALine[after] in [' ', #9]);
    end
    else
      Result := Copy(ALine, p, Length(ALc)) = ALc;
  end;

begin
  alpha := (ALc <> '') and (ALc[1] in ['A'..'Z', 'a'..'z']);
  all := True;
  any := False;
  for i := AL1 to AL2 do
  begin
    s := AEd.Lines[i - 1];
    if Trim(s) = '' then Continue;
    any := True;
    ws := LeadingWS(s);
    if not Commented(s, ws) then all := False;
  end;
  if not any then Exit;
  AEd.BeginUndoBlock;
  try
    if all then
    begin
      for i := AL1 to AL2 do
      begin
        s := AEd.Lines[i - 1];
        if Trim(s) = '' then Continue;
        ws := LeadingWS(s);
        n := Length(ALc);
        if Copy(s, Length(ws) + 1 + n, 1) = ' ' then Inc(n);
        AEd.SetTextBetweenPoints(Point(Length(ws) + 1, i),
          Point(Length(ws) + 1 + n, i), '');
      end;
    end
    else
    begin
      minInd := MaxInt;
      for i := AL1 to AL2 do
      begin
        s := AEd.Lines[i - 1];
        if Trim(s) = '' then Continue;
        if Length(LeadingWS(s)) < minInd then minInd := Length(LeadingWS(s));
      end;
      for i := AL1 to AL2 do
      begin
        s := AEd.Lines[i - 1];
        if Trim(s) = '' then Continue;
        AEd.SetTextBetweenPoints(Point(minInd + 1, i), Point(minInd + 1, i),
          ALc + ' ');
      end;
    end;
  finally
    AEd.EndUndoBlock;
  end;
end;

// pour les langages sans commentaire de ligne (HTML/CSS/XML/Markdown)
procedure TAppActions.ToggleBlockComment(AEd: TSynEdit; const ABo, ABc: string);
var
  bb, be: TPoint;
  s, t, ws: string;
  i, m, k, te: Integer;
begin
  if AEd.SelAvail then
  begin
    bb := AEd.BlockBegin;
    be := AEd.BlockEnd;
    s := AEd.SelText;
    AEd.BeginUndoBlock;
    try
      if (Length(s) >= Length(ABo) + Length(ABc)) and
         (Copy(s, 1, Length(ABo)) = ABo) and
         (Copy(s, Length(s) - Length(ABc) + 1, Length(ABc)) = ABc) then
      begin
        // la fin d'abord: retirer le debut decalerait ses coordonnees
        AEd.SetTextBetweenPoints(Point(be.X - Length(ABc), be.Y), be, '');
        AEd.SetTextBetweenPoints(bb, Point(bb.X + Length(ABo), bb.Y), '');
      end
      else
      begin
        AEd.SetTextBetweenPoints(be, be, ABc);
        AEd.SetTextBetweenPoints(bb, bb, ABo);
      end;
    finally
      AEd.EndUndoBlock;
    end;
    Exit;
  end;
  i := AEd.CaretY;
  s := AEd.Lines[i - 1];
  ws := LeadingWS(s);
  t := Trim(s);
  if t = '' then Exit;
  AEd.BeginUndoBlock;
  try
    if (Length(t) >= Length(ABo) + Length(ABc)) and
       (Copy(t, 1, Length(ABo)) = ABo) and
       (Copy(t, Length(t) - Length(ABc) + 1, Length(ABc)) = ABc) then
    begin
      // position de ABc calculee en IGNORANT le blanc de fin: le test "deja
      // commente" porte sur Trim(s), un espace final decalerait la coupe
      te := Length(s);
      while (te > 0) and ((s[te] = ' ') or (s[te] = #9)) do Dec(te);
      m := te - Length(ABc) + 1;
      if (m > 1) and (s[m - 1] = ' ') then Dec(m);
      AEd.SetTextBetweenPoints(Point(m, i), Point(Length(s) + 1, i), '');
      k := Length(ws) + Length(ABo);
      if Copy(s, k + 1, 1) = ' ' then Inc(k);
      AEd.SetTextBetweenPoints(Point(Length(ws) + 1, i), Point(k + 1, i), '');
    end
    else
    begin
      AEd.SetTextBetweenPoints(Point(Length(s) + 1, i), Point(Length(s) + 1, i),
        ' ' + ABc);
      AEd.SetTextBetweenPoints(Point(Length(ws) + 1, i), Point(Length(ws) + 1, i),
        ABo + ' ');
    end;
  finally
    AEd.EndUndoBlock;
  end;
end;

procedure TAppActions.EditToggleComment(Sender: TObject);
var
  e: TSynEdit;
  lc, bo, bc: string;
  l1, l2: Integer;
begin
  e := Ed;
  if e = nil then Exit;
  if not CommentTokensFor(e.Highlighter, lc, bo, bc) then Exit;
  // un SetTextBetweenPoints par ligne dans un seul undo block: Ctrl+A sur un
  // gros fichier tiendrait des millions de lignes
  if e.SelAvail and not ConfirmLargeText(True) then Exit;
  if e.CanFocus then e.SetFocus;
  if lc <> '' then
  begin
    LineRange(e, l1, l2);
    ToggleLineComment(e, lc, l1, l2);
  end
  else
    ToggleBlockComment(e, bo, bc);
end;

// 0 = upper, 1 = lower, 2 = title, 3 = swap. Sans selection: mot courant.
procedure TAppActions.ApplyCase(AMode: Integer);
var
  e: TSynEdit;
  s, r: string;
begin
  e := Ed;
  if e = nil then Exit;
  if e.SelAvail and not ConfirmLargeText(True) then Exit;
  if e.CanFocus then e.SetFocus;
  if not e.SelAvail then e.SelectWord;
  if not e.SelAvail then Exit;
  s := e.SelText;
  case AMode of
    0: r := UTF8UpperCase(s);
    1: r := UTF8LowerCase(s);
    2: r := UTF8TitleCase(s);
    else r := UTF8SwapCase(s);
  end;
  if r = s then Exit;
  // setSelect: garde la selection, pour enchainer les conversions
  e.SetTextBetweenPoints(e.BlockBegin, e.BlockEnd, r, [setSelect], scamEnd);
end;

procedure TAppActions.EditUpperCase(Sender: TObject); begin ApplyCase(0); end;
procedure TAppActions.EditLowerCase(Sender: TObject); begin ApplyCase(1); end;
procedure TAppActions.EditTitleCase(Sender: TObject); begin ApplyCase(2); end;
procedure TAppActions.EditSwapCase(Sender: TObject);  begin ApplyCase(3); end;

procedure TAppActions.EditSortLines(Sender: TObject);
const
  BIG_SORT_LINES = 50000;
var
  e: TSynEdit;
  l1, l2, i: Integer;
  sl: TStringList;
  txt: string;
begin
  e := Ed;
  if e = nil then Exit;
  if e.SelAvail then
    LineRange(e, l1, l2)
  else
  begin
    l1 := 1;
    l2 := e.Lines.Count;
  end;
  if l2 - l1 < 1 then Exit;
  if (FMgr.ActiveDoc <> nil) and FMgr.ActiveDoc.LargeFile and
     (l2 - l1 + 1 > BIG_SORT_LINES) then
    if MessageDlg('RottenText',
        Format('Sort %d lines? This can take a while.', [l2 - l1 + 1]),
        mtConfirmation, [mbYes, mbCancel], 0) <> mrYes then Exit;
  if e.CanFocus then e.SetFocus;
  sl := TStringList.Create;
  try
    for i := l1 to l2 do
      sl.Add(e.Lines[i - 1]);
    SortLinesCI(sl);
    txt := sl.Text;
    SetLength(txt, Length(txt) - Length(LineEnding)); // saut final en trop
    e.SetTextBetweenPoints(Point(1, l1),
      Point(Length(e.Lines[l2 - 1]) + 1, l2), txt);
  finally
    sl.Free;
  end;
end;

// le NOM du fichier en second: forcer le doc en Plain Text ne doit pas faire
// sauter l'avertissement
function IsMakefile(const ALang, AFileName: string): Boolean;
var
  i: Integer;
begin
  Result := ALang = 'Makefile';
  if Result or (AFileName = '') then Exit;
  i := IndexForFile(AFileName);
  Result := (i >= 0) and (SyntaxDisplayName(i) = 'Makefile');
end;

// un Makefile EXIGE de vraies tabulations en tete de recette: convertir le
// casserait en silence, d'ou la confirmation
procedure TAppActions.EditExpandTabs(Sender: TObject);
var
  e: TSynEdit;
  b, en: TPoint;
  src, res, fn: string;
begin
  e := Ed;
  if e = nil then Exit;
  if not ConfirmLargeText(e.SelAvail) then Exit;
  fn := '';
  if FMgr.ActiveDoc <> nil then fn := FMgr.ActiveDoc.FileName;
  if IsMakefile(LanguageLabel(e.Highlighter), fn) then
    if MessageDlg('RottenText',
        'A Makefile needs real tabs to start a recipe line.' + LineEnding +
        'Converting them to spaces will break it. Continue?',
        mtWarning, [mbYes, mbCancel], 0) <> mrYes then Exit;
  if e.CanFocus then e.SetFocus;
  if e.SelAvail then
  begin
    src := e.SelText;
    // colonne PHYSIQUE: une selection qui demarre en colonne 20 doit viser les
    // taquets REELS
    res := ExpandTabs(src, RTTabWidth,
      e.LogicalToPhysicalPos(e.BlockBegin).X - 1);
    if res = src then
    begin
      MessageDlg('RottenText', 'No tabs in the selection.',
        mtInformation, [mbOK], 0);
      Exit;
    end;
    e.SelText := res;
  end
  else
  begin
    src := e.Lines.Text;
    res := ExpandTabs(src, RTTabWidth);
    if res = src then
    begin
      MessageDlg('RottenText', 'No tabs in this document.',
        mtInformation, [mbOK], 0);
      Exit;
    end;
    // un seul SetTextBetweenPoints = un seul undo (jamais Lines.Text :=)
    b := Point(1, 1);
    en := Point(Length(e.Lines[e.Lines.Count - 1]) + 1, e.Lines.Count);
    // retirer UNIQUEMENT le saut final synthetique de TStrings.Text: un fichier
    // qui finit sur des lignes vides volontaires les perdrait
    if Copy(res, Length(res) - Length(LineEnding) + 1, Length(LineEnding))
       = LineEnding then
      SetLength(res, Length(res) - Length(LineEnding));
    e.SetTextBetweenPoints(b, en, res);
  end;
end;

procedure TAppActions.ViewMapTabToSpace(Sender: TObject);
begin
  RTMapTabToSpace := not RTMapTabToSpace;
  if Sender is TMenuItem then
    TMenuItem(Sender).Checked := RTMapTabToSpace;
  ApplyViewSettingsToAll;
  SettingsSave;
end;

procedure TAppActions.FileOpenRecent(Sender: TObject);
var
  i: Integer;
begin
  if not (Sender is TMenuItem) then Exit;
  i := TMenuItem(Sender).Tag;
  if (i >= 0) and (i < RecentCount) then
    FMgr.OpenFile(RecentPath(i));
end;

procedure TAppActions.FileClearRecent(Sender: TObject);
begin
  RecentClear;
end;

// matching NAIF: chaines et commentaires ne sont pas distingues
procedure TAppActions.SelExpandBrackets(Sender: TObject);
const
  BR_O = '([{';
  BR_C = ')]}';
  MAX_SCAN = 2000000; // borne anti-gel, par sens
var
  e: TSynEdit;
  sp, opn, cp, p1, p2: TPoint;
  stack, s: string;
  x, y, k, depth, scan: Integer;
  oc, cc: Char;
  found: Boolean;
begin
  e := Ed;
  if e = nil then Exit;
  if e.SelAvail then sp := e.BlockBegin else sp := e.LogicalCaretXY;
  // remonter: premier ouvrant non apparie = crochet englobant
  oc := #0; cc := #0;
  stack := '';
  found := False;
  scan := 0;
  y := sp.Y;
  while (y >= 1) and not found and (scan < MAX_SCAN) do
  begin
    s := e.Lines[y - 1];
    if y = sp.Y then x := sp.X - 1 else x := Length(s);
    if x > Length(s) then x := Length(s);
    while (x >= 1) and not found and (scan < MAX_SCAN) do
    begin
      Inc(scan);
      k := Pos(s[x], BR_C);
      if k > 0 then
        stack := stack + BR_O[k]
      else
      begin
        k := Pos(s[x], BR_O);
        if k > 0 then
        begin
          if (stack <> '') and (stack[Length(stack)] = s[x]) then
            SetLength(stack, Length(stack) - 1)
          else
          begin
            opn := Point(x, y);
            oc := s[x];
            cc := BR_C[k];
            found := True;
          end;
        end;
      end;
      Dec(x);
    end;
    Dec(y);
  end;
  if not found then Exit;
  depth := 0;
  found := False;
  scan := 0;
  y := opn.Y;
  while (y <= e.Lines.Count) and not found and (scan < MAX_SCAN) do
  begin
    s := e.Lines[y - 1];
    if y = opn.Y then x := opn.X else x := 1;
    while (x <= Length(s)) and not found and (scan < MAX_SCAN) do
    begin
      Inc(scan);
      if s[x] = oc then Inc(depth)
      else if s[x] = cc then
      begin
        Dec(depth);
        if depth = 0 then
        begin
          cp := Point(x, y);
          found := True;
        end;
      end;
      Inc(x);
    end;
    Inc(y);
  end;
  if not found then Exit;
  p1 := Point(opn.X + 1, opn.Y); // interieur, crochets exclus
  p2 := cp;
  if e.SelAvail and (e.BlockBegin.X = p1.X) and (e.BlockBegin.Y = p1.Y) and
     (e.BlockEnd.X = p2.X) and (e.BlockEnd.Y = p2.Y) then
  begin
    p1 := opn;
    p2 := Point(cp.X + 1, cp.Y);
  end;
  if e.CanFocus then e.SetFocus;
  // caret d'abord: le poser efface la selection
  e.LogicalCaretXY := p2;
  e.BlockBegin := p1;
  e.BlockEnd := p2;
end;

procedure TAppActions.ViewTheme(Sender: TObject);
begin
  if not (Sender is TMenuItem) then Exit;
  if not ApplyTheme(TMenuItem(Sender).Tag) then
  begin
    MessageDlg('RottenText', 'Cannot load this theme (missing or malformed file).',
      mtWarning, [mbOK], 0);
    Exit;
  end;
  TMenuItem(Sender).Checked := True;
  if Assigned(FOnThemeChanged) then
    FOnThemeChanged(Self);
  SettingsSave;
end;

procedure TAppActions.SetSyntax(Sender: TObject);
var
  t: Integer;
begin
  if not (Sender is TMenuItem) then Exit;
  t := TMenuItem(Sender).Tag;
  if t <= 0 then
    FMgr.SetActiveHighlighter(nil)
  else
    FMgr.SetActiveHighlighter(HighlighterByIndex(t - 1));
end;

procedure TAppActions.ApplyViewSettingsToAll;
var
  i: Integer;
begin
  for i := 0 to FMgr.Count - 1 do
    FMgr.Docs[i].View.ApplyViewSettings;
  FMgr.NotifyViewChanged;
end;

procedure TAppActions.ViewTabWidth(Sender: TObject);
begin
  if not (Sender is TMenuItem) then Exit;
  RTTabWidth := TMenuItem(Sender).Tag;
  TMenuItem(Sender).Checked := True;
  ApplyViewSettingsToAll;
  SettingsSave;
end;

procedure TAppActions.ViewWordWrap(Sender: TObject);
begin
  RTWordWrap := not RTWordWrap;
  if Sender is TMenuItem then
    TMenuItem(Sender).Checked := RTWordWrap;
  ApplyViewSettingsToAll;
  SettingsSave;
end;

procedure TAppActions.ViewWrapColumn(Sender: TObject);
begin
  if not (Sender is TMenuItem) then Exit;
  RTWrapColumn := TMenuItem(Sender).Tag;
  TMenuItem(Sender).Checked := True;
  ApplyViewSettingsToAll;
  SettingsSave;
end;

procedure TAppActions.ViewShowInvisibles(Sender: TObject);
begin
  RTShowInvisibles := not RTShowInvisibles;
  if Sender is TMenuItem then
    TMenuItem(Sender).Checked := RTShowInvisibles;
  ApplyViewSettingsToAll;
  SettingsSave;
end;

procedure TAppActions.ViewCommandPalette(Sender: TObject);
begin
  if Assigned(FOnCommandPalette) then
    FOnCommandPalette(Self);
end;

procedure TAppActions.SelSelectAll(Sender: TObject); begin Cmd(ecSelectAll); end;

// Ed = nil sur un doc hex: les actions Selection y sont sans objet

procedure TAppActions.SelSplitLines(Sender: TObject);
begin
  if Ed <> nil then FMgr.ActiveDoc.View.MultiSplitLines;
end;

procedure TAppActions.SelSingle(Sender: TObject);
begin
  if Ed <> nil then FMgr.ActiveDoc.View.MultiClear;
end;

procedure TAppActions.SelExpandLine(Sender: TObject);
begin
  if Ed <> nil then FMgr.ActiveDoc.View.ExpandToLine;
end;

procedure TAppActions.SelExpandWord(Sender: TObject);
begin
  if Ed <> nil then FMgr.ActiveDoc.View.ExpandToWord;
end;

procedure TAppActions.SelAddPrevLine(Sender: TObject);
begin
  if Ed <> nil then FMgr.ActiveDoc.View.MultiAddLine(-1);
end;

procedure TAppActions.SelAddNextLine(Sender: TObject);
begin
  if Ed <> nil then FMgr.ActiveDoc.View.MultiAddLine(1);
end;

procedure TAppActions.SelFillLorem(Sender: TObject);
var
  e: TSynEdit;
begin
  e := Ed;
  if e = nil then Exit;
  if not e.SelAvail then
  begin
    MessageDlg('RottenText', 'Select the area to fill first.',
      mtInformation, [mbOK], 0);
    Exit;
  end;
  if not ConfirmLargeText(True) then Exit;
  e.SelText := LoremFill(e.SelText);
end;

procedure TAppActions.SetMacroItems(ARecordItem, APlayItem: TMenuItem);
begin
  FMacroRecordItem := ARecordItem;
  FMacroPlayItem := APlayItem;
  MacroStateChanged(nil);
end;

// AddEditor ignore les doublons; stop propre si l'onglet en cours
// d'enregistrement vient d'etre ferme
procedure TAppActions.SyncMacroEditors;
var
  i: Integer;
  alive: Boolean;
begin
  for i := 0 to FMgr.Count - 1 do
    FRec.AddEditor(FMgr.Docs[i].View.Syn);
  if FRec.State in [msRecording, msPaused] then
  begin
    alive := False;
    for i := 0 to FMgr.Count - 1 do
      if FMgr.Docs[i].View.Syn = FRec.CurrentEditor then alive := True;
    if not alive then FRec.Stop;
  end;
end;

function TAppActions.MacroRecordingIndex: Integer;
var
  i: Integer;
begin
  Result := -1;
  if not (FRec.State in [msRecording, msPaused]) then Exit;
  for i := 0 to FMgr.Count - 1 do
    if FMgr.Docs[i].View.Syn = FRec.CurrentEditor then Exit(i);
end;

procedure TAppActions.MacroStateChanged(Sender: TObject);
begin
  if FMacroRecordItem <> nil then
  begin
    if FRec.State in [msRecording, msPaused] then
      FMacroRecordItem.Caption := 'Stop Recording Macro'
    else
      FMacroRecordItem.Caption := 'Record Macro';
  end;
  if FMacroPlayItem <> nil then
    FMacroPlayItem.Enabled := (FRec.State = msStopped) and not FRec.IsEmpty;
  if Assigned(FOnMacroStateChange) then
    FOnMacroStateChange(Self);
end;

procedure TAppActions.MacroToggleRecord(Sender: TObject);
begin
  case FRec.State of
    msRecording, msPaused: FRec.Stop;
    msStopped:
      if Ed <> nil then
      begin
        SyncMacroEditors;
        if Ed.CanFocus then Ed.SetFocus;
        FRec.RecordMacro(Ed);
      end;
    msPlaying: ;
  end;
end;

procedure TAppActions.MacroPlayback(Sender: TObject);
begin
  if (FRec.State = msStopped) and (not FRec.IsEmpty) and (Ed <> nil) then
  begin
    if Ed.CanFocus then Ed.SetFocus;
    FRec.PlaybackMacro(Ed);
  end;
end;

{ ---- Tools ---- }

function HashKindFromTag(ATag: Integer): TOpsHash;
begin
  case ATag mod 10 of
    0: Result := ohMD5;
    1: Result := ohSHA1;
    3: Result := ohSHA512;
    else Result := ohSHA256;
  end;
end;

function ToolTransformByTag(ATag: Integer; const S: string): string;
begin
  case ATag of
    10: Result := HashText(ohMD5, S);
    11: Result := HashText(ohSHA1, S);
    12: Result := HashText(ohSHA256, S);
    13: Result := HashText(ohSHA512, S);
    20: Result := B64Encode(S);
    21: Result := B64Decode(S);
    22: Result := B64UrlEncode(S);
    23: Result := B64UrlDecode(S);
    24: Result := UrlEncode(S);
    25: Result := UrlDecode(S);
    26: Result := HtmlEncode(S);
    27: Result := HtmlDecode(S);
    28: Result := HexEncode(S);
    29: Result := HexDecode(S);
    30: Result := EscapeBash(S);
    31: Result := EscapePowerShell(S);
    32: Result := EscapeJSON(S);
    33: Result := EscapeYAML(S);
    34: Result := EscapeSQL(S);
    35: Result := EscapeSedPattern(S);
    36: Result := EscapeSedReplacement(S);
    37: Result := EscapeRegex(S);
    38: Result := EscapeSystemdExec(S);
    39: Result := EscapeNginxQuoted(S);
    else Result := S;
  end;
end;

procedure TAppActions.ToolsTransform(Sender: TObject);
var
  e: TSynEdit;
  src, res: string;
  tag, y: Integer;
  onLine: Boolean;
begin
  e := Ed;
  if (e = nil) or not (Sender is TMenuItem) then Exit;
  tag := TMenuItem(Sender).Tag;
  if e.SelAvail and not ConfirmLargeText(True) then Exit;
  if e.CanFocus then e.SetFocus;
  if e.SelAvail then
  begin
    src := e.SelText;
    onLine := False;
    y := 0;
  end
  else
  begin
    y := e.CaretY;
    src := e.Lines[y - 1];
    onLine := True;
  end;
  try
    res := ToolTransformByTag(tag, src);
  except
    on ex: Exception do
    begin
      MessageDlg('RottenText', ex.Message, mtError, [mbOK], 0);
      Exit;
    end;
  end;
  if onLine then
    e.SetTextBetweenPoints(Point(1, y), Point(Length(e.Lines[y - 1]) + 1, y), res,
      [setSelect], scamEnd)
  else
    e.SelText := res;
end;

// sortie "<hash>  <nom>", au format de sha256sum -c
procedure TAppActions.ToolsHashFile(Sender: TObject);
var
  e: TSynEdit;
  dlg: TOpenDialog;
  line: string;
begin
  e := Ed;
  if (e = nil) or not (Sender is TMenuItem) then Exit;
  // e tenu en travers du dialogue natif: sans le verrou, le check de modif
  // externe pourrait fermer le doc et l'insertion viserait un editeur libere
  BeginActionModal;
  try
    dlg := TOpenDialog.Create(nil);
    try
      dlg.Options := dlg.Options + [ofFileMustExist];
      if not dlg.Execute then Exit;
      try
        line := HashFile(HashKindFromTag(TMenuItem(Sender).Tag), dlg.FileName) +
          '  ' + ExtractFileName(dlg.FileName);
      except
        on ex: Exception do
        begin
          MessageDlg('RottenText', ex.Message, mtError, [mbOK], 0);
          Exit;
        end;
      end;
    finally
      dlg.Free;
    end;
    if e.CanFocus then e.SetFocus;
    if e.SelAvail then e.SelText := line else e.InsertTextAtCaret(line);
  finally
    EndActionModal;
  end;
end;

// cle saisie masquee, jamais affichee ni inseree
procedure TAppActions.ToolsHMAC(Sender: TObject);
var
  e: TSynEdit;
  key, src, res: string;
  y: Integer;
  onLine: Boolean;
begin
  e := Ed;
  if (e = nil) or not (Sender is TMenuItem) then Exit;
  if e.SelAvail and not ConfirmLargeText(True) then Exit;
  if e.SelAvail then
  begin
    src := e.SelText;
    onLine := False;
    y := 0;
  end
  else
  begin
    y := e.CaretY;
    src := e.Lines[y - 1];
    onLine := True;
  end;
  key := '';
  if not AskSecret('HMAC key', 'Secret key:', key) then Exit;
  try
    res := HMACHex(HashKindFromTag(TMenuItem(Sender).Tag), key, src);
  finally
    WipeSecret(key);
  end;
  if e.CanFocus then e.SetFocus;
  if onLine then
    e.SetTextBetweenPoints(Point(1, y), Point(Length(e.Lines[y - 1]) + 1, y), res,
      [setSelect], scamEnd)
  else
    e.SelText := res;
end;

// jamais le buffer entier: un fichier ne peut pas contenir son propre hash, le
// commentaire le rendrait faux des l'insertion
procedure TAppActions.ToolsChecksumComment(Sender: TObject);
var
  e: TSynEdit;
  lc, bo, bc, h, comment, src, what: string;
  y: Integer;
begin
  e := Ed;
  if e = nil then Exit;
  if e.SelAvail and not ConfirmLargeText(True) then Exit;
  if e.SelAvail then
  begin
    src := e.SelText;
    what := 'selection';
  end
  else
  begin
    src := e.Lines[e.CaretY - 1];
    what := 'line';
  end;
  h := HashText(ohSHA256, src);
  lc := ''; bo := ''; bc := '';
  CommentTokensFor(e.Highlighter, lc, bo, bc);
  if lc <> '' then
    comment := lc + ' sha256 (' + what + '): ' + h
  else if bo <> '' then
    comment := bo + ' sha256 (' + what + '): ' + h + ' ' + bc
  else
    comment := '# sha256 (' + what + '): ' + h;
  if e.CanFocus then e.SetFocus;
  y := e.CaretY;
  e.SetTextBetweenPoints(Point(1, y), Point(1, y), comment + LineEnding);
end;

procedure TAppActions.ToolsInsert(Sender: TObject);
var
  e: TSynEdit;
  res, pfx: string;
begin
  e := Ed;
  if (e = nil) or not (Sender is TMenuItem) then Exit;
  try
    case TMenuItem(Sender).Tag of
      40: res := GenUUIDv4;
      41: res := IntToStr(NowUnixSeconds);
      42: res := NowISO8601(False);
      50: res := GenTokenHex(32);
      51: res := GenTokenB64(32);
      52: res := GenTokenB64Url(32);
      53:
        begin
          pfx := 'rt';
          if not InputQuery('API Key', 'Prefix (e.g. rt, sk):', pfx) then Exit;
          if Trim(pfx) = '' then Exit;
          res := GenApiKey(pfx, 18);
        end;
      else res := NowISO8601(True);
    end;
  except
    on ex: Exception do
    begin
      MessageDlg('RottenText', ex.Message, mtError, [mbOK], 0);
      Exit;
    end;
  end;
  if e.CanFocus then e.SetFocus;
  if e.SelAvail then e.SelText := res else e.InsertTextAtCaret(res);
end;

procedure TAppActions.ToolsGenPassword(Sender: TObject);
var
  e: TSynEdit;
  sLen, res: string;
  n: Integer;
begin
  if not (Sender is TMenuItem) then Exit;
  // InputQuery et pas InputBox: InputBox rend le DEFAUT a l'annulation, donc
  // Cancel generait un mot de passe et ecraserait le presse-papiers
  sLen := '20';
  if not InputQuery('RottenText', 'Password length:', sLen) then Exit;
  if Trim(sLen) = '' then Exit;
  n := StrToIntDef(Trim(sLen), 0);
  if (n < 1) or (n > 4096) then
  begin
    MessageDlg('RottenText', 'Length must be between 1 and 4096.', mtError, [mbOK], 0);
    Exit;
  end;
  try
    res := GenPassword(n);
  except
    on ex: Exception do
    begin
      MessageDlg('RottenText', ex.Message, mtError, [mbOK], 0);
      Exit;
    end;
  end;
  if TMenuItem(Sender).Tag = 1 then
  begin
    e := Ed;
    if e <> nil then
    begin
      if e.CanFocus then e.SetFocus;
      if e.SelAvail then e.SelText := res else e.InsertTextAtCaret(res);
    end;
  end
  else
  begin
    Clipboard.AsText := res;
    MessageDlg('RottenText',
      Format('A %d-character password was copied to the clipboard.', [n]),
      mtInformation, [mbOK], 0);
  end;
  WipeSecret(res);
end;

procedure TAppActions.ToolsHtpasswd(Sender: TObject);
var
  e: TSynEdit;
  user, pw, entry: string;
begin
  e := Ed;
  if (e = nil) or not (Sender is TMenuItem) then Exit;
  user := Trim(InputBox('htpasswd', 'Username:', ''));
  if user = '' then Exit;
  if Pos(':', user) > 0 then
  begin
    MessageDlg('RottenText', 'Username cannot contain '':''.', mtError, [mbOK], 0);
    Exit;
  end;
  pw := '';
  if not AskSecret('htpasswd', 'Password for ' + user + ':', pw, True) then Exit;
  try
    case TMenuItem(Sender).Tag of
      1: entry := HtpasswdApr1(user, pw);
      2: entry := HtpasswdSha(user, pw);
      else entry := HtpasswdBcrypt(user, pw, 10);
    end;
  except
    on ex: Exception do
    begin
      WipeSecret(pw);
      MessageDlg('RottenText', ex.Message, mtError, [mbOK], 0);
      Exit;
    end;
  end;
  WipeSecret(pw);
  if e.CanFocus then e.SetFocus;
  if e.SelAvail then e.SelText := entry else e.InsertTextAtCaret(entry);
end;

// saisie masquee pour un hash, NON masquee pour SASL (identite uid@REALM, pas
// un secret). Le clair est zeroise apres usage.
function BuildSchemeValue(AScheme: TLdapPwScheme; out AValue: string): Boolean;
var
  pw, id: string;
begin
  Result := False;
  AValue := '';
  if AScheme = lpsSASL then
  begin
    id := InputBox('LDAP userPassword (SASL)', 'SASL identity (uid@REALM or DN):', '');
    if Trim(id) = '' then Exit;
    AValue := LdapUserPassword(lpsSASL, id);
    Result := True;
    Exit;
  end;
  pw := '';
  if not AskSecret('LDAP userPassword', 'Password:', pw, True) then Exit;
  try
    AValue := LdapUserPassword(AScheme, pw);
    Result := True;
  except
    on ex: Exception do
      MessageDlg('RottenText', ex.Message, mtError, [mbOK], 0);
  end;
  WipeSecret(pw);
end;

// seule la valeur hashee est inseree, jamais le mot de passe
procedure TAppActions.ToolsLdapPassword(Sender: TObject);
var
  e: TSynEdit;
  entry: string;
begin
  e := Ed;
  if (e = nil) or not (Sender is TMenuItem) then Exit;
  if not BuildSchemeValue(TLdapPwScheme(TMenuItem(Sender).Tag), entry) then Exit;
  if e.CanFocus then e.SetFocus;
  if e.SelAvail then e.SelText := entry else e.InsertTextAtCaret(entry);
end;

// le userPassword est saisi masque APRES le formulaire et hashe: pas de clair
// dans le form
procedure TAppActions.ToolsLdifEntry(Sender: TObject);
var
  e: TSynEdit;
  p: TLdifPerson;
  wantPw: Boolean;
  scheme: TLdapPwScheme;
  entry: string;
begin
  e := Ed;
  if e = nil then Exit;
  if not AskLdifPerson(p, wantPw, scheme) then Exit;
  if wantPw then
    if not BuildSchemeValue(scheme, p.UserPassword) then Exit;
  entry := BuildLdif(p);
  if e.CanFocus then e.SetFocus;
  if e.SelAvail then e.SelText := entry else e.InsertTextAtCaret(entry);
end;

procedure TAppActions.ToolsLdifRoot(Sender: TObject);
var
  e: TSynEdit;
  v: TStrArray;
begin
  e := Ed;
  if e = nil then Exit;
  if not AskFields('LDIF Root (domain)',
    ['Base DN', 'Organization (o)', 'Description'],
    ['dc=example,dc=org', '', ''], v) then Exit;
  if v[0] = '' then begin MessageDlg('RottenText', 'DN is required', mtWarning, [mbOK], 0); Exit; end;
  if e.CanFocus then e.SetFocus;
  e.InsertTextAtCaret(BuildLdifRoot(v[0], v[1], v[2]));
end;

procedure TAppActions.ToolsLdifOU(Sender: TObject);
var
  e: TSynEdit;
  v: TStrArray;
begin
  e := Ed;
  if e = nil then Exit;
  if not AskFields('LDIF Organizational Unit',
    ['DN', 'Description'],
    ['ou=people,dc=example,dc=org', ''], v) then Exit;
  if v[0] = '' then begin MessageDlg('RottenText', 'DN is required', mtWarning, [mbOK], 0); Exit; end;
  if e.CanFocus then e.SetFocus;
  e.InsertTextAtCaret(BuildLdifOU(v[0], v[1]));
end;

procedure TAppActions.ToolsLdifGroup(Sender: TObject);
var
  e: TSynEdit;
  v: TStrArray;
begin
  e := Ed;
  if e = nil then Exit;
  if not AskFields('LDIF Group (posixGroup)',
    ['DN', 'gidNumber', 'Members (uid, space-sep)', 'Description'],
    ['cn=admins,ou=groups,dc=example,dc=org', '10000', '', ''], v) then Exit;
  if v[0] = '' then begin MessageDlg('RottenText', 'DN is required', mtWarning, [mbOK], 0); Exit; end;
  if e.CanFocus then e.SetFocus;
  e.InsertTextAtCaret(BuildLdifGroup(v[0], v[1], v[2], v[3]));
end;

procedure TAppActions.ToolsLdifGroupOfNames(Sender: TObject);
var
  e: TSynEdit;
  v: TStrArray;
begin
  e := Ed;
  if e = nil then Exit;
  if not AskFields('LDIF Group (groupOfNames)',
    ['DN', 'Members (DN, ;-separated)', 'Description'],
    ['cn=app-admins,ou=groups,dc=example,dc=org', '', ''], v) then Exit;
  if v[0] = '' then begin MessageDlg('RottenText', 'DN is required', mtWarning, [mbOK], 0); Exit; end;
  if v[1] = '' then begin MessageDlg('RottenText', 'groupOfNames requires at least one member (DN)', mtWarning, [mbOK], 0); Exit; end;
  if e.CanFocus then e.SetFocus;
  e.InsertTextAtCaret(BuildLdifGroupOfNames(v[0], v[1], v[2]));
end;

procedure TAppActions.ToolsLdifService(Sender: TObject);
var
  e: TSynEdit;
  v: TStrArray;
  pw, hashed: string;
begin
  e := Ed;
  if e = nil then Exit;
  if not AskFields('LDIF Service / Bind Account',
    ['DN', 'Description'],
    ['uid=readonly,ou=services,dc=example,dc=org', 'bind account'], v) then Exit;
  if v[0] = '' then begin MessageDlg('RottenText', 'DN is required', mtWarning, [mbOK], 0); Exit; end;
  hashed := '';
  pw := '';
  // OK avec un champ vide = compte account sans mot de passe, c'est valide
  if not AskSecret('Service account password (SSHA)', 'Password (blank = none):', pw, True) then Exit;
  // pas de Trim(pw): ca creerait une COPIE du secret sur le tas, jamais wipee
  if pw <> '' then
    try
      hashed := LdapUserPassword(lpsSSHA, pw);
    except
      on ex: Exception do
      begin
        WipeSecret(pw);
        MessageDlg('RottenText', ex.Message, mtError, [mbOK], 0);
        Exit;
      end;
    end;
  WipeSecret(pw);
  if e.CanFocus then e.SetFocus;
  e.InsertTextAtCaret(BuildLdifService(v[0], hashed, v[1]));
end;

procedure TAppActions.ToolsJson(Sender: TObject);
const
  BIG_JSON_LINES = 50000;
var
  e: TSynEdit;
  src, res, err: string;
  onSel, big: Boolean;
begin
  e := Ed;
  if (e = nil) or not (Sender is TMenuItem) then Exit;
  onSel := e.SelAvail;
  // taille estimee par les coords de lignes AVANT toute copie: on ne materialise
  // Lines.Text/SelText qu'au feu vert
  big := False;
  if (FMgr.ActiveDoc <> nil) and FMgr.ActiveDoc.LargeFile then
    if onSel then
      big := (e.BlockEnd.Y - e.BlockBegin.Y + 1) > BIG_JSON_LINES
    else
      big := True;
  if big then
    if MessageDlg('RottenText',
        'Process this large amount of text? This can take a while.',
        mtConfirmation, [mbYes, mbCancel], 0) <> mrYes then Exit;
  if onSel then src := e.SelText else src := e.Lines.Text;
  case TMenuItem(Sender).Tag of
    0:
      begin
        if JsonValidate(src, err) then
          MessageDlg('RottenText', 'Valid JSON.', mtInformation, [mbOK], 0)
        else
          MessageDlg('RottenText', 'Invalid JSON:'#10 + err, mtError, [mbOK], 0);
        Exit;
      end;
    1: if not JsonFormat(src, res, err) then
       begin
         MessageDlg('RottenText', 'Invalid JSON:'#10 + err, mtError, [mbOK], 0);
         Exit;
       end;
    2: if not JsonMinify(src, res, err) then
       begin
         MessageDlg('RottenText', 'Invalid JSON:'#10 + err, mtError, [mbOK], 0);
         Exit;
       end;
    else if not JsonSortKeys(src, res, err) then
       begin
         MessageDlg('RottenText', 'Invalid JSON:'#10 + err, mtError, [mbOK], 0);
         Exit;
       end;
  end;
  if e.CanFocus then e.SetFocus;
  if onSel then
    e.SelText := res
  else
  begin
    e.SelectAll;
    e.SelText := res;
  end;
end;

procedure TAppActions.ToolsXml(Sender: TObject);
const
  BIG_XML_LINES = 50000;
var
  e: TSynEdit;
  src, res, err: string;
  onSel, big: Boolean;
begin
  e := Ed;
  if (e = nil) or not (Sender is TMenuItem) then Exit;
  onSel := e.SelAvail;
  big := False;
  if (FMgr.ActiveDoc <> nil) and FMgr.ActiveDoc.LargeFile then
    if onSel then big := (e.BlockEnd.Y - e.BlockBegin.Y + 1) > BIG_XML_LINES
    else big := True;
  if big then
    if MessageDlg('RottenText',
        'Process this large amount of text? This can take a while.',
        mtConfirmation, [mbYes, mbCancel], 0) <> mrYes then Exit;
  if onSel then src := e.SelText else src := e.Lines.Text;
  case TMenuItem(Sender).Tag of
    0:
      begin
        if XmlValidate(src, err) then
          MessageDlg('RottenText', 'Well-formed XML.', mtInformation, [mbOK], 0)
        else
          MessageDlg('RottenText', 'Invalid XML:'#10 + err, mtError, [mbOK], 0);
        Exit;
      end;
    else if not XmlFormat(src, res, err) then
      begin
        MessageDlg('RottenText', 'Invalid XML:'#10 + err, mtError, [mbOK], 0);
        Exit;
      end;
  end;
  if e.CanFocus then e.SetFocus;
  if onSel then
    e.SelText := res
  else
  begin
    e.SelectAll;
    e.SelText := res;
  end;
end;

procedure TAppActions.ToolsYaml(Sender: TObject);
const
  BIG_YAML_LINES = 50000;
var
  e: TSynEdit;
  src, err: string;
  onSel, big: Boolean;
  node: TYamlNode;
  d: TDocument;
  sl: TStringList;
begin
  e := Ed;
  if (e = nil) or not (Sender is TMenuItem) then Exit;
  onSel := e.SelAvail;
  big := False;
  if (FMgr.ActiveDoc <> nil) and FMgr.ActiveDoc.LargeFile then
    if onSel then big := (e.BlockEnd.Y - e.BlockBegin.Y + 1) > BIG_YAML_LINES
    else big := True;
  if big then
    if MessageDlg('RottenText',
        'Process this large amount of text? This can take a while.',
        mtConfirmation, [mbYes, mbCancel], 0) <> mrYes then Exit;
  if onSel then src := e.SelText else src := e.Lines.Text;

  // le tri passe par l'emetteur: commentaires et mise en forme d'origine perdus
  if TMenuItem(Sender).Tag = 2 then
    if MessageDlg('RottenText',
        'Sort keys rewrites the document: comments and original formatting are lost (undo available). Continue?',
        mtConfirmation, [mbYes, mbCancel], 0) <> mrYes then Exit;

  node := YamlParse(src, err);
  if node = nil then
  begin
    MessageDlg('RottenText', 'Invalid YAML:'#10 + err, mtError, [mbOK], 0);
    Exit;
  end;
  try
    case TMenuItem(Sender).Tag of
      0:
        begin
          MessageDlg('RottenText', 'Well-formed YAML (block subset).', mtInformation, [mbOK], 0);
          Exit;
        end;
      1:
        begin
          sl := TStringList.Create;
          try
            YamlFlatten(node, sl);
            d := FMgr.NewFile;
            if d = nil then Exit;
            d.View.Syn.Lines.Assign(sl);
            d.Modified := True;
          finally
            sl.Free;
          end;
        end;
      else
        begin
          YamlSortKeys(node);
          src := YamlEmit(node);
          if e.CanFocus then e.SetFocus;
          if onSel then e.SelText := src
          else begin e.SelectAll; e.SelText := src; end;
        end;
    end;
  finally
    node.Free;
  end;
end;

procedure TAppActions.ToolsYamlDiff(Sender: TObject);
var
  e: TSynEdit;
  dlg: TOpenDialog;
  a, b: TYamlNode;
  err, report: string;
  d: TDocument;
  fs: TStringList;
begin
  e := Ed;
  if e = nil then Exit;
  if not ConfirmLargeText(False) then Exit;
  a := YamlParse(e.Lines.Text, err);
  if a = nil then
  begin
    MessageDlg('RottenText', 'Current buffer is not valid YAML:'#10 + err, mtError, [mbOK], 0);
    Exit;
  end;
  b := nil;
  BeginActionModal; // dialogue natif
  try
    dlg := TOpenDialog.Create(nil);
    try
      dlg.Options := dlg.Options + [ofFileMustExist];
      if not dlg.Execute then Exit;
      if not ConfirmLargeFile(dlg.FileName) then Exit;
      fs := TStringList.Create;
      try
        try
          fs.LoadFromFile(dlg.FileName);
        except
          on ex: Exception do
          begin
            MessageDlg('RottenText', ex.Message, mtError, [mbOK], 0);
            Exit;
          end;
        end;
        b := YamlParse(fs.Text, err);
      finally
        fs.Free;
      end;
      if b = nil then
      begin
        MessageDlg('RottenText', 'Chosen file is not valid YAML:'#10 + err, mtError, [mbOK], 0);
        Exit;
      end;
      report := YamlValuesDiff(a, b, '(current buffer)', ExtractFileName(dlg.FileName));
      d := FMgr.NewFile;
      if d = nil then Exit;
      d.View.Syn.Lines.Text := report;
      d.Modified := True;
    finally
      dlg.Free;
    end;
  finally
    EndActionModal;
    b.Free;
    a.Free;
  end;
end;

procedure TAppActions.ToolsKube(Sender: TObject);
var
  e: TSynEdit;
  src, name, res, err: string;
  d: TDocument;
  env: TStringList;
  di: Integer;
begin
  e := Ed;
  if (e = nil) or not (Sender is TMenuItem) then Exit;
  if not ConfirmLargeText(e.SelAvail) then Exit;
  if e.SelAvail then src := e.SelText else src := e.Lines.Text;

  case TMenuItem(Sender).Tag of
    0, 2:
      begin
        if TMenuItem(Sender).Tag = 0 then
        begin
          name := 'my-secret';
          if not InputQuery('Kubernetes Secret', 'Secret name:', name) then Exit;
        end
        else
        begin
          name := 'my-configmap';
          if not InputQuery('Kubernetes ConfigMap', 'ConfigMap name:', name) then Exit;
        end;
        if Trim(name) = '' then Exit;
        // un nom hors RFC 1123 casserait le YAML ou serait refuse par k8s
        if not ValidK8sName(Trim(name)) then
        begin
          MessageDlg('RottenText', '"' + Trim(name) + '" is not a valid'
            + ' Kubernetes name (lowercase letters, digits, "-" and ".",'
            + ' must start and end alphanumeric).', mtError, [mbOK], 0);
          Exit;
        end;
        env := TStringList.Create;
        try
          env.Text := src;
          if TMenuItem(Sender).Tag = 0 then
            res := SecretEncode(name, '', env)
          else
            res := ConfigMapEncode(name, '', env);
        finally
          env.Free;
        end;
      end;
    1:
      begin
        res := SecretDecode(src, err);
        if err <> '' then
        begin
          MessageDlg('RottenText', 'Cannot decode Secret:'#10 + err, mtError, [mbOK], 0);
          Exit;
        end;
      end;
  else
    begin
      res := ConfigMapDecode(src, err);
      if err <> '' then
      begin
        MessageDlg('RottenText', 'Cannot decode ConfigMap:'#10 + err, mtError, [mbOK], 0);
        Exit;
      end;
    end;
  end;

  d := FMgr.NewFile;
  if d = nil then Exit;
  d.View.Syn.Lines.Text := res;
  // comparaisons explicites: un `in [..]` sur un Tag PtrInt leve le hint FPC
  // "left operand should be byte sized"
  if (TMenuItem(Sender).Tag = 0) or (TMenuItem(Sender).Tag = 2) then
  begin
    di := IndexForName('YAML');
    if di >= 0 then d.View.Syn.Highlighter := HighlighterByIndex(di);
  end;
  d.Modified := True;
end;

procedure TAppActions.ToolsEnv(Sender: TObject);
var
  e: TSynEdit;
  src, res, err: string;
  tag, di: Integer;
  onSel: Boolean;
  d: TDocument;
begin
  e := Ed;
  if (e = nil) or not (Sender is TMenuItem) then Exit;
  tag := TMenuItem(Sender).Tag;
  onSel := e.SelAvail;
  if not ConfirmLargeText(onSel) then Exit;
  if onSel then src := e.SelText else src := e.Lines.Text;

  err := '';
  case tag of
    0: res := EnvSortKeys(src);
    1: res := EnvFindDuplicates(src);
    2: res := EnvRedact(src);
    3: res := EnvToJson(src);
    4: res := EnvFromJson(src, err);
    5: res := EnvQuoteValues(src);
    6: res := EnvUnquoteValues(src);
    7: res := EnvToYaml(src);
  else res := EnvFromYaml(src, err);
  end;
  if err <> '' then
  begin
    if tag = 4 then
      MessageDlg('RottenText', 'Invalid JSON:'#10 + err, mtError, [mbOK], 0)
    else
      MessageDlg('RottenText', 'Invalid YAML:'#10 + err, mtError, [mbOK], 0);
    Exit;
  end;

  if tag in [0, 5, 6] then
  begin
    if e.CanFocus then e.SetFocus;
    if onSel then e.SelText := res
    else begin e.SelectAll; e.SelText := res; end;
    Exit;
  end;

  d := FMgr.NewFile;
  if d = nil then Exit;
  d.View.Syn.Lines.Text := res;
  if tag in [3, 7] then
  begin
    if tag = 3 then di := IndexForName('JSON') else di := IndexForName('YAML');
    if di >= 0 then d.View.Syn.Highlighter := HighlighterByIndex(di);
  end;
  d.Modified := True;
end;

procedure TAppActions.ToolsCompose(Sender: TObject);
var
  e: TSynEdit;
  src, res, err, ln, curTag, newTag: string;
  y: Integer;
  d: TDocument;
begin
  e := Ed;
  if (e = nil) or not (Sender is TMenuItem) then Exit;

  if TMenuItem(Sender).Tag = 2 then
  begin
    y := e.CaretY;
    ln := e.Lines[y - 1];
    curTag := ImageTagOnLine(ln);
    if (curTag = '') and (ComposeRetagLine(ln, 'x') = ln) then
    begin
      MessageDlg('RottenText',
        'Put the cursor on an "image:" line first.', mtInformation, [mbOK], 0);
      Exit;
    end;
    newTag := curTag;
    if not InputQuery('Set Image Tag', 'New tag:', newTag) then Exit;
    newTag := Trim(newTag);
    if newTag = '' then Exit;
    res := ComposeRetagLine(ln, newTag);
    if res = ln then Exit;
    if e.CanFocus then e.SetFocus;
    e.SetTextBetweenPoints(Point(1, y), Point(Length(ln) + 1, y), res, [setSelect], scamEnd);
    Exit;
  end;

  if not ConfirmLargeText(False) then Exit;
  src := e.Lines.Text;
  if TMenuItem(Sender).Tag = 0 then
    res := ComposeListImages(src, err)
  else
    res := ComposeEnvDotenv(src, err);
  if err <> '' then
  begin
    MessageDlg('RottenText', err, mtError, [mbOK], 0);
    Exit;
  end;
  d := FMgr.NewFile;
  if d = nil then Exit;
  d.View.Syn.Lines.Text := res;
  d.Modified := True;
end;

procedure TAppActions.ToolsQuadlet(Sender: TObject);
var
  e: TSynEdit;
  src, res, err, ln, curTag, newTag: string;
  y: Integer;
  d: TDocument;
begin
  e := Ed;
  if (e = nil) or not (Sender is TMenuItem) then Exit;

  if TMenuItem(Sender).Tag = 2 then
  begin
    y := e.CaretY;
    ln := e.Lines[y - 1];
    curTag := QuadletTagOnLine(ln);
    // curTag <> '' prouve deja que c'est une ligne image, meme si son tag vaut
    // le sentinel 'x' du test de retag
    if (curTag = '') and (QuadletRetagLine(ln, 'x') = ln) then
    begin
      MessageDlg('RottenText',
        'Put the cursor on an "Image=" line first.', mtInformation, [mbOK], 0);
      Exit;
    end;
    newTag := curTag;
    if not InputQuery('Set Image Tag', 'New tag:', newTag) then Exit;
    newTag := Trim(newTag);
    if newTag = '' then Exit;
    res := QuadletRetagLine(ln, newTag);
    if res = ln then Exit;
    if e.CanFocus then e.SetFocus;
    e.SetTextBetweenPoints(Point(1, y), Point(Length(ln) + 1, y), res, [setSelect], scamEnd);
    Exit;
  end;

  if not ConfirmLargeText(False) then Exit;
  src := e.Lines.Text;
  if TMenuItem(Sender).Tag = 0 then
    res := QuadletListImage(src, err)
  else
    res := QuadletEnvDotenv(src, err);
  if err <> '' then
  begin
    MessageDlg('RottenText', err, mtError, [mbOK], 0);
    Exit;
  end;
  d := FMgr.NewFile;
  if d = nil then Exit;
  d.View.Syn.Lines.Text := res;
  d.Modified := True;
end;

procedure TAppActions.ToolsIni(Sender: TObject);
var
  e: TSynEdit;
  src, res: string;
  onSel: Boolean;
  d: TDocument;
begin
  e := Ed;
  if (e = nil) or not (Sender is TMenuItem) then Exit;
  onSel := e.SelAvail;
  if not ConfirmLargeText(onSel) then Exit;
  if onSel then src := e.SelText else src := e.Lines.Text;

  case TMenuItem(Sender).Tag of
    0:
      begin
        res := IniValidate(src);
        if Copy(res, 1, 6) = 'INI OK' then
          MessageDlg('RottenText', res, mtInformation, [mbOK], 0)
        else
          MessageDlg('RottenText', res, mtWarning, [mbOK], 0);
      end;
    1:
      begin
        res := IniSortKeys(src);
        if e.CanFocus then e.SetFocus;
        if onSel then e.SelText := res
        else begin e.SelectAll; e.SelText := res; end;
      end;
  else
    begin
      res := IniFindDuplicates(src);
      d := FMgr.NewFile;
      if d = nil then Exit;
      d.View.Syn.Lines.Text := res;
      d.Modified := True;
    end;
  end;
end;

procedure TAppActions.ToolsToml(Sender: TObject);
var
  e: TSynEdit;
  src, res: string;
  onSel: Boolean;
  d: TDocument;
begin
  e := Ed;
  if (e = nil) or not (Sender is TMenuItem) then Exit;
  onSel := e.SelAvail;
  if not ConfirmLargeText(onSel) then Exit;
  if onSel then src := e.SelText else src := e.Lines.Text;

  case TMenuItem(Sender).Tag of
    0:
      begin
        res := TomlValidate(src);
        if Copy(res, 1, 7) = 'TOML OK' then
          MessageDlg('RottenText', res, mtInformation, [mbOK], 0)
        else
          MessageDlg('RottenText', res, mtWarning, [mbOK], 0);
      end;
    1:
      begin
        res := TomlSortKeys(src);
        if e.CanFocus then e.SetFocus;
        if onSel then e.SelText := res
        else begin e.SelectAll; e.SelText := res; end;
      end;
  else
    begin
      res := TomlFindDuplicates(src);
      d := FMgr.NewFile;
      if d = nil then Exit;
      d.View.Syn.Lines.Text := res;
      d.Modified := True;
    end;
  end;
end;

// le buffer SynEdit ne stocke pas de fins de ligne: on change le modele EOL du
// doc, applique au prochain save. Comme un encodage force, pas d'undo.
procedure TAppActions.ToolsEol(Sender: TObject);
var
  d: TDocument;
  k: TEolKind;
begin
  d := FMgr.ActiveDoc;
  if (d = nil) or d.IsHex or not (Sender is TMenuItem) then Exit;
  case TMenuItem(Sender).Tag of
    0: k := eolLF;
    1: k := eolCRLF;
  else
    k := eolCR;
  end;
  if d.Eol = k then
  begin
    MessageDlg('RottenText', 'Line endings are already ' + EolName(k) + '.',
      mtInformation, [mbOK], 0);
    Exit;
  end;
  d.Eol := k;
  d.Modified := True; // la representation disque changera au save
end;

procedure TAppActions.ToolsCron(Sender: TObject);
var
  e: TSynEdit;
  src, res, err: string;
  d: TDocument;
begin
  e := Ed;
  if e = nil then Exit;
  if e.SelAvail then
    src := Trim(e.SelText)
  else if (e.CaretY >= 1) and (e.CaretY <= e.Lines.Count) then
    src := Trim(e.Lines[e.CaretY - 1])
  else
    src := '';
  if src = '' then
  begin
    src := Trim(InputBox('RottenText',
      'Cron expression, crontab line or OnCalendar= value:', ''));
    if src = '' then Exit;
  end;
  res := ScheduleReport(src, Now, 10, err);
  if res = '' then
  begin
    MessageDlg('RottenText', err, mtError, [mbOK], 0);
    Exit;
  end;
  d := FMgr.NewFile;
  if d = nil then Exit;
  d.View.Syn.Lines.Text := res;
  d.Modified := True;
end;

procedure TAppActions.ToolsLog(Sender: TObject);
var
  e: TSynEdit;
  src, res: string;
  d: TDocument;
  dlg: TOpenDialog;
  fs: TStringList;
begin
  e := Ed;
  if (e = nil) or not (Sender is TMenuItem) then Exit;
  if not ConfirmLargeText(e.SelAvail) then Exit;
  if e.SelAvail then src := e.SelText else src := e.Lines.Text;
  case TMenuItem(Sender).Tag of
    0: res := LogNormalize(src);
    1: res := LogSort(src);
    2:
      begin
        dlg := TOpenDialog.Create(nil);
        BeginActionModal; // dialogue natif
        try
          dlg.Title := 'Merge with log file';
          dlg.Options := dlg.Options + [ofFileMustExist];
          if not dlg.Execute then Exit;
          if not ConfirmLargeFile(dlg.FileName) then Exit;
          fs := TStringList.Create;
          try
            try
              fs.LoadFromFile(dlg.FileName);
            except
              on ex: Exception do
              begin
                MessageDlg('RottenText', ex.Message, mtError, [mbOK], 0);
                Exit;
              end;
            end;
            res := LogMerge(src, fs.Text);
          finally
            fs.Free;
          end;
        finally
          EndActionModal;
          dlg.Free;
        end;
      end;
    3: res := LogDeltas(src);
  else
    res := LogSummary(src);
  end;
  d := FMgr.NewFile;
  if d = nil then Exit;
  d.View.Syn.Lines.Text := res;
  d.Modified := True;
end;

procedure TAppActions.ToolsTerraform(Sender: TObject);
var
  e: TSynEdit;
  src, res, err: string;
  d: TDocument;
begin
  e := Ed;
  if (e = nil) or not (Sender is TMenuItem) then Exit;
  if not ConfirmLargeText(e.SelAvail) then Exit;
  if e.SelAvail then src := e.SelText else src := e.Lines.Text;
  err := '';
  case TMenuItem(Sender).Tag of
    0: res := TfListVariables(src, err);
    1: res := TfVarsSkeleton(src, err);
  else res := TfFindDuplicates(src, err);
  end;
  if err <> '' then
  begin
    MessageDlg('RottenText', err, mtError, [mbOK], 0);
    Exit;
  end;
  d := FMgr.NewFile;
  if d = nil then Exit;
  d.View.Syn.Lines.Text := res;
  d.Modified := True;
end;

procedure TAppActions.ToolsHelm(Sender: TObject);
var
  e: TSynEdit;
  src, res, path: string;
  d: TDocument;
  di: Integer;
begin
  e := Ed;
  if (e = nil) or not (Sender is TMenuItem) then Exit;

  if TMenuItem(Sender).Tag = 1 then
  begin
    path := RenderValuesPath(e.Lines, e.CaretY - 1);
    if (path = '') or (path = '.Values.') then
    begin
      MessageDlg('RottenText', 'Place the cursor on a key line first.',
        mtInformation, [mbOK], 0);
      Exit;
    end;
    Clipboard.AsText := path;
    MessageDlg('RottenText', 'Copied to clipboard:'#10 + path, mtInformation, [mbOK], 0);
    Exit;
  end;

  if not ConfirmLargeText(e.SelAvail) then Exit;
  if e.SelAvail then src := e.SelText else src := e.Lines.Text;
  res := ValuesSkeleton(src);
  d := FMgr.NewFile;
  if d = nil then Exit;
  d.View.Syn.Lines.Text := res;
  di := IndexForName('YAML');
  if di >= 0 then d.View.Syn.Highlighter := HighlighterByIndex(di);
  d.Modified := True;
end;

procedure TAppActions.ToolsHelmIssues(Sender: TObject);
var
  e: TSynEdit;
  dlg: TOpenDialog;
  vals: TYamlNode;
  fs: TStringList;
  src, err, report: string;
  d: TDocument;
begin
  e := Ed;
  if e = nil then Exit;
  if not ConfirmLargeText(e.SelAvail) then Exit;
  if e.SelAvail then src := e.SelText else src := e.Lines.Text;
  vals := nil;
  dlg := TOpenDialog.Create(nil);
  BeginActionModal; // dialogue natif
  try
    dlg.Title := 'Choose values.yaml';
    dlg.Options := dlg.Options + [ofFileMustExist];
    if not dlg.Execute then Exit;
    if not ConfirmLargeFile(dlg.FileName) then Exit;
    fs := TStringList.Create;
    try
      try
        fs.LoadFromFile(dlg.FileName);
      except
        on ex: Exception do
        begin
          MessageDlg('RottenText', ex.Message, mtError, [mbOK], 0);
          Exit;
        end;
      end;
      vals := YamlParse(fs.Text, err);
    finally
      fs.Free;
    end;
    if vals = nil then
    begin
      MessageDlg('RottenText', 'Chosen values file is not valid YAML:'#10 + err,
        mtError, [mbOK], 0);
      Exit;
    end;
    try
      report := FindValuesIssues(src, vals);
    finally
      vals.Free;
    end;
    d := FMgr.NewFile;
    if d = nil then Exit;
    d.View.Syn.Lines.Text := report;
    d.Modified := True;
  finally
    EndActionModal;
    dlg.Free;
  end;
end;

procedure TAppActions.ToolsHelmFolder(Sender: TObject);
var
  dirDlg: TSelectDirectoryDialog;
  valDlg: TOpenDialog;
  refs: TStringList;
  vals: TYamlNode;
  fs: TStringList;
  fileCount, skipped, tag, di: Integer;
  res, err, note: string;
  d: TDocument;
begin
  if not (Sender is TMenuItem) then Exit;
  tag := TMenuItem(Sender).Tag;
  res := '';
  vals := nil;
  dirDlg := TSelectDirectoryDialog.Create(nil);
  BeginActionModal; // dialogues natifs
  try
    dirDlg.Title := 'Choose the chart templates/ folder';
    if not dirDlg.Execute then Exit;
    refs := ScanValuesRefsInDir(dirDlg.FileName, fileCount, skipped);
    try
      if fileCount = 0 then
      begin
        MessageDlg('RottenText',
          'No template files (.yaml/.yml/.tpl/.txt) found in that folder.',
          mtInformation, [mbOK], 0);
        Exit;
      end;
      note := Format('# scanned %d template file(s)', [fileCount]);
      if skipped > 0 then
        note := note + Format(', %d skipped (too large / unreadable)', [skipped]);

      if tag = 0 then
        res := note + #10 + ValuesSkeletonFromRefs(refs)
      else
      begin
        valDlg := TOpenDialog.Create(nil);
        try
          valDlg.Title := 'Choose values.yaml';
          valDlg.Options := valDlg.Options + [ofFileMustExist];
          if not valDlg.Execute then Exit;
          if not ConfirmLargeFile(valDlg.FileName) then Exit;
          fs := TStringList.Create;
          try
            try
              fs.LoadFromFile(valDlg.FileName);
            except
              on ex: Exception do
              begin
                MessageDlg('RottenText', ex.Message, mtError, [mbOK], 0);
                Exit;
              end;
            end;
            vals := YamlParse(fs.Text, err);
          finally
            fs.Free;
          end;
          if vals = nil then
          begin
            MessageDlg('RottenText', 'Chosen values file is not valid YAML:'#10 + err,
              mtError, [mbOK], 0);
            Exit;
          end;
          res := note + #10 + FindValuesIssuesFromRefs(refs, vals);
        finally
          valDlg.Free;
        end;
      end;
    finally
      refs.Free;
      vals.Free;
    end;
  finally
    EndActionModal;
    dirDlg.Free;
  end;

  if res = '' then Exit;
  d := FMgr.NewFile;
  if d = nil then Exit;
  d.View.Syn.Lines.Text := res;
  if tag = 0 then
  begin
    di := IndexForName('YAML');
    if di >= 0 then d.View.Syn.Highlighter := HighlighterByIndex(di);
  end;
  d.Modified := True;
end;

procedure TAppActions.ToolsHelmSnippet(Sender: TObject);
var
  e: TSynEdit;
  s: string;
begin
  e := Ed;
  if (e = nil) or not (Sender is TMenuItem) then Exit;
  s := HelmSnippet(TMenuItem(Sender).Tag);
  if s = '' then Exit;
  if e.CanFocus then e.SetFocus;
  if e.SelAvail then e.SelText := s else e.InsertTextAtCaret(s);
end;

procedure TAppActions.ToolsHelmQuote(Sender: TObject);
var
  e: TSynEdit;
  y: Integer;
  ln, res: string;
begin
  e := Ed;
  if e = nil then Exit;
  y := e.CaretY;
  ln := e.Lines[y - 1];
  res := HelmQuoteLine(ln);
  if res = ln then
  begin
    MessageDlg('RottenText', 'No {{ ... }} expression to quote on this line.',
      mtInformation, [mbOK], 0);
    Exit;
  end;
  if e.CanFocus then e.SetFocus;
  e.SetTextBetweenPoints(Point(1, y), Point(Length(ln) + 1, y), res, [setSelect], scamEnd);
end;

// remplace la cle seule: un bloc enfant existant est a retirer a la main
procedure TAppActions.ToolsHelmToYaml(Sender: TObject);
var
  e: TSynEdit;
  y: Integer;
  ln, path, block: string;
begin
  e := Ed;
  if e = nil then Exit;
  y := e.CaretY;
  ln := e.Lines[y - 1];
  path := DefaultValuesPath(ln);
  if path = '' then
  begin
    MessageDlg('RottenText', 'Place the cursor on a key line first.',
      mtInformation, [mbOK], 0);
    Exit;
  end;
  if not InputQuery('Value to toYaml | nindent', '.Values path:', path) then Exit;
  path := Trim(path);
  if path = '' then Exit;
  block := HelmToYamlLine(ln, path);
  if block = '' then Exit;
  if e.CanFocus then e.SetFocus;
  e.SetTextBetweenPoints(Point(1, y), Point(Length(ln) + 1, y), block, [setSelect], scamEnd);
end;

procedure TAppActions.ToolsIpCalc(Sender: TObject);
var
  e: TSynEdit;
  src, report: string;
  hadSel: Boolean;
begin
  e := Ed;
  if e = nil then Exit;
  hadSel := e.SelAvail;
  if hadSel then
  begin
    src := e.SelText;
    // LogicalCaretXY et pas CaretXY: CaretXY est PHYSIQUE, un tab ou de l'UTF-8
    // dans la selection posait le caret DANS celle-ci
    e.LogicalCaretXY := e.BlockEnd;
  end
  else
    src := InputBox('IP / CIDR Calculator', 'Address (a.b.c.d/n or IPv6/n):', '');
  if Trim(src) = '' then Exit;
  try
    report := CidrReport(src);   // ':' dans l'entree = IPv6
  except
    on ex: Exception do
    begin
      MessageDlg('RottenText', ex.Message, mtError, [mbOK], 0);
      Exit;
    end;
  end;
  if e.CanFocus then e.SetFocus;
  if hadSel then e.InsertTextAtCaret(LineEnding + report)
  else e.InsertTextAtCaret(report);
end;

procedure TAppActions.ToolsTimestamp(Sender: TObject);
var
  e: TSynEdit;
  src, report: string;
  hadSel: Boolean;
begin
  e := Ed;
  if e = nil then Exit;
  hadSel := e.SelAvail;
  if hadSel then
  begin
    src := e.SelText;
    // LogicalCaretXY: CaretXY est PHYSIQUE et poserait le caret DANS la selection
    e.LogicalCaretXY := e.BlockEnd;
  end
  else
    src := InputBox('Timestamp Converter',
      'Timestamp (unix / ISO 8601 / Apache / syslog):', '');
  if Trim(src) = '' then Exit;
  report := TimestampReport(src);
  if report = '' then
  begin
    MessageDlg('RottenText', 'No timestamp recognized.', mtInformation, [mbOK], 0);
    Exit;
  end;
  if e.CanFocus then e.SetFocus;
  if hadSel then e.InsertTextAtCaret(LineEnding + report)
  else e.InsertTextAtCaret(report);
end;

// la signature n'est jamais verifiee (bandeau dans le rapport)
procedure TAppActions.ToolsJwt(Sender: TObject);
var
  e: TSynEdit;
  src, report: string;
  d: TDocument;
begin
  e := Ed;
  if e = nil then Exit;
  if e.SelAvail then src := e.SelText
  else src := InputBox('JWT Inspector', 'Token:', '');
  if Trim(src) = '' then Exit;
  try
    report := JwtDecode(src);
  except
    on ex: Exception do
    begin
      MessageDlg('RottenText', ex.Message, mtError, [mbOK], 0);
      Exit;
    end;
  end;
  d := FMgr.NewFile;
  if d = nil then Exit;
  d.View.Syn.Lines.Text := report;
  d.Modified := True;
end;

procedure TAppActions.ToolsMailTrace(Sender: TObject);
var
  e: TSynEdit;
  src, report: string;
  d: TDocument;
begin
  e := Ed;
  if e = nil then Exit;
  if not ConfirmLargeText(e.SelAvail) then Exit;
  if e.SelAvail then src := e.SelText else src := e.Lines.Text;
  if Trim(src) = '' then Exit;
  report := MailTraceReport(src);
  if report = '' then
  begin
    MessageDlg('RottenText',
      'No Received headers found. Paste raw mail headers or a full .eml.',
      mtInformation, [mbOK], 0);
    Exit;
  end;
  d := FMgr.NewFile;
  if d = nil then Exit;
  d.View.Syn.Lines.Text := report;
  d.Modified := True;
end;

// la signature n'est jamais verifiee (bandeau dans le rapport)
procedure TAppActions.ToolsX509(Sender: TObject);
var
  e: TSynEdit;
  dlg: TOpenDialog;
  src, report, err: string;
  d: TDocument;
  nowUtc: TDateTime;
begin
  if not (Sender is TMenuItem) then Exit;
  nowUtc := LocalTimeToUniversal(Now);
  if TMenuItem(Sender).Tag = 0 then
  begin
    e := Ed;
    if e = nil then Exit;
    if not ConfirmLargeText(e.SelAvail) then Exit;
    if e.SelAvail then src := e.SelText else src := e.Lines.Text;
    report := X509ReportFromText(src, nowUtc, err);
  end
  else
  begin
    dlg := TOpenDialog.Create(nil);
    BeginActionModal; // dialogue natif
    try
      dlg.Title := 'Choose a certificate file (PEM or DER)';
      dlg.Options := dlg.Options + [ofFileMustExist];
      if not dlg.Execute then Exit;
      report := X509ReportFromFile(dlg.FileName, nowUtc, err);
    finally
      EndActionModal;
      dlg.Free;
    end;
  end;
  if err <> '' then
  begin
    MessageDlg('RottenText', 'Cannot inspect certificate:'#10 + err,
      mtError, [mbOK], 0);
    Exit;
  end;
  d := FMgr.NewFile;
  if d = nil then Exit;
  d.View.Syn.Lines.Text := report;
  d.Modified := True;
end;

procedure TAppActions.ToolsPerms(Sender: TObject);
var
  e: TSynEdit;
  src, res: string;
  hadSel: Boolean;
begin
  e := Ed;
  if (e = nil) or not (Sender is TMenuItem) then Exit;
  if TMenuItem(Sender).Tag = 1 then
  begin
    src := '022';
    if not InputQuery('umask Calculator', 'umask (octal, e.g. 022):', src) then Exit;
    if Trim(src) = '' then Exit;
    try
      res := UmaskReport(src);
    except
      on ex: Exception do
      begin
        MessageDlg('RottenText', ex.Message, mtError, [mbOK], 0);
        Exit;
      end;
    end;
    if e.CanFocus then e.SetFocus;
    e.InsertTextAtCaret(res);
    Exit;
  end;
  hadSel := e.SelAvail;
  if hadSel then src := e.SelText
  else src := InputBox('Convert chmod Mode', 'Mode (750 or rwxr-x---):', '');
  if Trim(src) = '' then Exit;
  try
    res := ChmodConvert(src);
  except
    on ex: Exception do
    begin
      MessageDlg('RottenText', ex.Message, mtError, [mbOK], 0);
      Exit;
    end;
  end;
  if e.CanFocus then e.SetFocus;
  if hadSel then e.SelText := res else e.InsertTextAtCaret(res);
end;

procedure TAppActions.ToolsExtract(Sender: TObject);
const
  BIG_EXTRACT_LINES = 200000;
var
  e: TSynEdit;
  src: string;
  kinds: TExtractKinds;
  onSel, big: Boolean;
  d: TDocument;
begin
  e := Ed;
  if (e = nil) or not (Sender is TMenuItem) then Exit;
  case TMenuItem(Sender).Tag of
    0: kinds := [ekIPv4];
    1: kinds := [ekURL];
    2: kinds := [ekEmail];
    3: kinds := [ekUUID];
    4: kinds := [ekHash];
    5: kinds := [ekHost];
    else kinds := [ekIPv4, ekURL, ekEmail, ekUUID, ekHash, ekHost];
  end;
  onSel := e.SelAvail;
  big := False;
  if (FMgr.ActiveDoc <> nil) and FMgr.ActiveDoc.LargeFile then
    if onSel then big := (e.BlockEnd.Y - e.BlockBegin.Y + 1) > BIG_EXTRACT_LINES
    else big := True;
  if big then
    if MessageDlg('RottenText',
        'Scan this large amount of text? This can take a while.',
        mtConfirmation, [mbYes, mbCancel], 0) <> mrYes then Exit;
  if onSel then src := e.SelText else src := e.Lines.Text;
  d := FMgr.NewFile;
  if d = nil then Exit;
  d.View.Syn.Lines.Text := ExtractReport(src, kinds);
  d.Modified := True;
end;

procedure TAppActions.ToolsProtocol(Sender: TObject);
var
  e: TSynEdit;
  s: string;
begin
  e := Ed;
  if (e = nil) or not (Sender is TMenuItem) then Exit;
  s := ProtoScriptByTag(TMenuItem(Sender).Tag);
  if s = '' then Exit;
  if e.CanFocus then e.SetFocus;
  if e.SelAvail then e.SelText := s else e.InsertTextAtCaret(s);
end;

procedure TAppActions.ToolsNmap(Sender: TObject);
var
  e: TSynEdit;
  opts: TNmapOpts;
  line: string;
begin
  e := Ed;
  if e = nil then Exit;
  if not AskNmap(opts) then Exit;
  line := BuildNmap(opts);
  if e.CanFocus then e.SetFocus;
  if e.SelAvail then e.SelText := line else e.InsertTextAtCaret(line);
end;

procedure TAppActions.ToolsHttp(Sender: TObject);
var
  e: TSynEdit;
  req: THttpReq;
  s: string;
begin
  e := Ed;
  if (e = nil) or not (Sender is TMenuItem) then Exit;
  if not AskHttp(TMenuItem(Sender).Tag = 1, req) then Exit;
  s := BuildHttpRequest(req);
  if e.CanFocus then e.SetFocus;
  if e.SelAvail then e.SelText := s else e.InsertTextAtCaret(s);
end;

procedure TAppActions.ToolsDiff(Sender: TObject);
var
  e: TSynEdit;
  dlg: TOpenDialog;
  a, b, res: TStringList;
  leftName, merged, orig, cur: string;
  wasSel: Boolean;
  selB, selE: TPoint;

  // le doc source peut etre FERME pendant un dialogue: comparaison de POINTEURS
  // seulement, e ne doit pas etre dereference tant qu'on ignore s'il vit
  function SourceAlive: Boolean;
  var
    i: Integer;
  begin
    Result := False;
    for i := 0 to FMgr.Count - 1 do
      if (FMgr.Docs[i].View <> nil) and (FMgr.Docs[i].View.Syn = e) then
        Exit(True);
  end;

  procedure SourceGone;
  begin
    MessageDlg('RottenText',
      'The source document was closed while the diff was open.' + LineEnding +
      'Nothing was integrated.', mtWarning, [mbOK], 0);
  end;

begin
  e := Ed;
  if e = nil then Exit;
  wasSel := e.SelAvail;
  // garde AVANT toute copie: un Cancel ne doit pas payer la materialisation
  if not ConfirmLargeText(wasSel) then Exit;
  // e est tenu en travers d'un dialogue natif puis d'une modale. try IMMEDIAT:
  // une exception d'allocation ne doit pas laisser le verrou pose
  a := nil; b := nil; res := nil;
  BeginActionModal;
  try
    a := TStringList.Create;
    b := TStringList.Create;
    res := TStringList.Create;
    // bornes sauvees AVANT la modale: au retour la selection a pu changer, et la
    // reinjection doit viser la plage d'origine, jamais tout le buffer
    selB := e.BlockBegin;
    selE := e.BlockEnd;
    // texte source garde: un reload externe peut arriver PENDANT la modale, on
    // le recompare avant de reinjecter
    if wasSel then
    begin
      orig := e.SelText;
      leftName := '(selection)';
    end
    else
    begin
      orig := e.Lines.Text;
      leftName := '(current buffer)';
    end;
    a.Text := orig;
    dlg := TOpenDialog.Create(nil);
    try
      dlg.Options := dlg.Options + [ofFileMustExist];
      if not dlg.Execute then Exit;
      // le TOpenDialog natif n'incremente pas forcement ModalLevel: le garde
      // d'uMain ne couvre pas ce trou
      if not SourceAlive then begin SourceGone; Exit; end;
      if not ConfirmLargeFile(dlg.FileName) then Exit;
      try
        b.LoadFromFile(dlg.FileName);
      except
        on ex: Exception do
        begin
          MessageDlg('RottenText', ex.Message, mtError, [mbOK], 0);
          Exit;
        end;
      end;
      // meme grammaire que le doc source: coloration gardee sous la teinte de diff
      if not ShowDiffView(a, b, leftName, ExtractFileName(dlg.FileName),
        e.Highlighter, res) then Exit;
    finally
      dlg.Free;
    end;
    if not SourceAlive then begin SourceGone; Exit; end;

    // SkipLastLineBreak: pas de saut de ligne final parasite
    res.SkipLastLineBreak := True;
    merged := res.Text;
    // clamp: le buffer a pu changer sous la modale
    if wasSel then
    begin
      if selE.Y > e.Lines.Count then
      begin
        selE.Y := e.Lines.Count;
        if selE.Y < 1 then selE.Y := 1;
        selE.X := Length(e.Lines[selE.Y - 1]) + 1;
      end;
      if selB.Y > selE.Y then selB := selE;
      cur := e.TextBetweenPoints[selB, selE];
    end
    else
      cur := e.Lines.Text;
    // texte source perime: le merge a ete calcule contre un texte qui n'existe
    // plus, on ne l'applique pas en silence
    if cur <> orig then
      if MessageDlg('RottenText',
        'The document changed while the diff was open (external reload?).' +
        LineEnding + 'Overwrite the current text with the merged result anyway?',
        mtWarning, [mbYes, mbCancel], 0) <> mrYes then Exit;
    if wasSel then
      e.SetTextBetweenPoints(selB, selE, merged, [setSelect], scamEnd)
    else
    begin
      e.SelectAll;
      e.SelText := merged;
    end;
  finally
    EndActionModal;
    res.Free;
    b.Free;
    a.Free;
  end;
end;

end.
