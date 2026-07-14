unit uDocumentManager;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Controls, Dialogs, SynEditHighlighter,
  uDocument, uEditorView, uHighlight, uRecent;

type
  TPathEvent = procedure(const APath: string) of object;

  // Deux groupes d'onglets au plus (0 = gauche, 1 = droite en split view).
  TDocumentManager = class
  private
    FDocs: TFPList;
    FHosts: array[0..1] of TWinControl;
    FGroupActive: array[0..1] of TDocument; // doc montre par groupe (nil = vide)
    FActiveGroup: Integer;
    FSplit: Boolean;
    FShowLock: Integer; // ShowGroupDoc donne le focus: ignorer ces OnEnter
    FCheckingExternal: Boolean;
    FOnListChanged: TNotifyEvent;
    FOnActiveChanged: TNotifyEvent;
    FOnDocChanged: TNotifyEvent;
    FOnOpenFolder: TPathEvent;
    function GetCount: Integer;
    function GetDoc(AIndex: Integer): TDocument;
    function GetActiveIndex: Integer;
    procedure DocChangedHandler(Sender: TObject);
    procedure DocFocusedHandler(Sender: TObject);
    procedure Notify(AEvent: TNotifyEvent);
    function AddDocIn(AGroup: Integer; ALargeFile: Boolean = False): TDocument;
    procedure RemoveAt(AIndex: Integer);
    procedure AfterListChange;
    procedure ShowGroupDoc(AGroup: Integer);
    procedure ShowGroups;
    function FirstDocInGroup(AGroup: Integer): TDocument;
    function GroupDocCount(AGroup: Integer): Integer;
    function ReplacementFor(ADoc: TDocument): TDocument;
    procedure ReparentDoc(ADoc: TDocument; AHost: TWinControl);
    function SaveDoc(AIndex: Integer): Boolean;
    function SaveDocAs(AIndex: Integer): Boolean;
    function ConfirmCanClose(AIndex: Integer): Boolean;
    function SoleBlankDoc: TDocument;
    procedure ReloadPreservingCaret(ADoc: TDocument);
    function SafeReload(ADoc: TDocument): Boolean;
    procedure DiskActionFailed(ADoc: TDocument; E: Exception);
  public
    constructor Create(AHost: TWinControl);
    destructor Destroy; override;
    function NewFile(AGroup: Integer = -1): TDocument; // -1 = groupe actif
    function OpenFile(const AFileName: string): TDocument;
    procedure OpenDialog;
    procedure Activate(AIndex: Integer);
    procedure ActivateNext;
    procedure ActivatePrev;
    function CloseDoc(AIndex: Integer): Boolean; // False = fermeture annulee
    procedure CloseOthers(AIndex: Integer);   // scope: le groupe de l'onglet
    procedure CloseToRight(AIndex: Integer);
    procedure CloseUnmodified(AGroup: Integer = -1); // -1 = tous les groupes
    function CloseAll: Boolean; // False = annule dans un prompt de save
    function CanCloseAll(ASkipUntitled: Boolean = False): Boolean;
    function CanCloseUntitled: Boolean;
    procedure SaveActive;
    procedure SaveActiveAs;
    procedure SaveActiveWithEncoding(AEnc: Integer);
    procedure ReopenActiveWithEncoding(AEnc: Integer);
    procedure ReopenActiveHex;
    function SaveAll: Boolean; // False si un Save As a ete annule
    procedure RevertActive;
    procedure CheckExternalChanges;
    procedure SetActiveHighlighter(AHl: TSynCustomHighlighter);
    procedure NotifyViewChanged;
    function ActiveDoc: TDocument;
    function IndexOfFile(const AFileName: string): Integer;
    procedure SetGroupHost(AGroup: Integer; AHost: TWinControl);
    procedure SetSplit(AOn: Boolean); // off = les docs du groupe 1 rejoignent le 0
    procedure ActivateGroup(AGroup: Integer);
    procedure MoveToOtherGroup(AIndex: Integer);
    procedure MoveActiveToGroup(AGroup: Integer);
    procedure MoveDocInGroup(AIndex, ANewVisualPos: Integer);
    function GroupDoc(AGroup: Integer): TDocument;
    function GroupActiveIndex(AGroup: Integer): Integer;
    property Count: Integer read GetCount;
    property Docs[AIndex: Integer]: TDocument read GetDoc;
    property ActiveIndex: Integer read GetActiveIndex;
    property ActiveGroup: Integer read FActiveGroup;
    property Split: Boolean read FSplit;
    property OnListChanged: TNotifyEvent read FOnListChanged write FOnListChanged;
    property OnActiveChanged: TNotifyEvent read FOnActiveChanged write FOnActiveChanged;
    property OnDocChanged: TNotifyEvent read FOnDocChanged write FOnDocChanged;
    property OnOpenFolder: TPathEvent read FOnOpenFolder write FOnOpenFolder;
  end;

implementation

uses
  // verrou d'action: un dialogue natif n'incremente pas forcement ModalLevel
  uActions;

constructor TDocumentManager.Create(AHost: TWinControl);
begin
  FHosts[0] := AHost;
  FDocs := TFPList.Create;
  FActiveGroup := 0;
end;

destructor TDocumentManager.Destroy;
var
  i: Integer;
begin
  // Free d'un doc focuse relocalise le focus -> OnEnter -> Activate sur des liberes
  Inc(FShowLock);
  for i := 0 to FDocs.Count - 1 do
    TDocument(FDocs[i]).Free;
  FDocs.Free;
  inherited Destroy;
end;

function TDocumentManager.GetCount: Integer;
begin
  Result := FDocs.Count;
end;

function TDocumentManager.GetDoc(AIndex: Integer): TDocument;
begin
  Result := TDocument(FDocs[AIndex]);
end;

function TDocumentManager.GetActiveIndex: Integer;
begin
  if FGroupActive[FActiveGroup] = nil then
    Result := -1
  else
    Result := FDocs.IndexOf(FGroupActive[FActiveGroup]);
end;

procedure TDocumentManager.Notify(AEvent: TNotifyEvent);
begin
  if Assigned(AEvent) then
    AEvent(Self);
end;

procedure TDocumentManager.DocChangedHandler(Sender: TObject);
begin
  Notify(FOnDocChanged);
end;

procedure TDocumentManager.DocFocusedHandler(Sender: TObject);
var
  idx: Integer;
begin
  if FShowLock > 0 then Exit; // focus donne par ShowGroupDoc, pas par l'utilisateur
  if Sender = ActiveDoc then Exit;
  idx := FDocs.IndexOf(Sender);
  if idx >= 0 then Activate(idx);
end;

function TDocumentManager.GroupDocCount(AGroup: Integer): Integer;
var
  i: Integer;
begin
  Result := 0;
  for i := 0 to FDocs.Count - 1 do
    if TDocument(FDocs[i]).Group = AGroup then Inc(Result);
end;

function TDocumentManager.FirstDocInGroup(AGroup: Integer): TDocument;
var
  i: Integer;
begin
  Result := nil;
  for i := 0 to FDocs.Count - 1 do
    if TDocument(FDocs[i]).Group = AGroup then
      Exit(TDocument(FDocs[i]));
end;

function TDocumentManager.ReplacementFor(ADoc: TDocument): TDocument;
var
  i, from: Integer;
begin
  Result := nil;
  from := FDocs.IndexOf(ADoc);
  if from < 0 then Exit;
  for i := from + 1 to FDocs.Count - 1 do
    if TDocument(FDocs[i]).Group = ADoc.Group then
      Exit(TDocument(FDocs[i]));
  for i := from - 1 downto 0 do
    if TDocument(FDocs[i]).Group = ADoc.Group then
      Exit(TDocument(FDocs[i]));
end;

function TDocumentManager.GroupDoc(AGroup: Integer): TDocument;
begin
  Result := FGroupActive[AGroup];
end;

function TDocumentManager.GroupActiveIndex(AGroup: Integer): Integer;
begin
  if FGroupActive[AGroup] = nil then
    Result := -1
  else
    Result := FDocs.IndexOf(FGroupActive[AGroup]);
end;

function TDocumentManager.AddDocIn(AGroup: Integer; ALargeFile: Boolean): TDocument;
var
  view: TEditorView;
begin
  view := TEditorView.Create(FHosts[AGroup], ALargeFile);
  Result := TDocument.Create(view);
  Result.Group := AGroup;
  Result.OnChange := @DocChangedHandler;
  Result.OnFocus := @DocFocusedHandler;
  FDocs.Add(Result);
end;

function TDocumentManager.NewFile(AGroup: Integer): TDocument;
begin
  if (AGroup < 0) or (AGroup > 1) or ((AGroup = 1) and not FSplit) then
    AGroup := FActiveGroup;
  Result := AddDocIn(AGroup);
  Notify(FOnListChanged);
  Activate(FDocs.Count - 1);
end;

function TDocumentManager.IndexOfFile(const AFileName: string): Integer;
var
  i: Integer;
begin
  // pas SameText: sur un FS sensible a la casse, Makefile <> makefile
  for i := 0 to FDocs.Count - 1 do
    if SameFileName(TDocument(FDocs[i]).FileName, AFileName) then
      Exit(i);
  Result := -1;
end;

function IsBlankDoc(ADoc: TDocument): Boolean;
begin
  Result := ADoc.Untitled and not ADoc.Modified and not ADoc.IsHex and
     (ADoc.View.Syn.Lines.Count <= 1) and
     ((ADoc.View.Syn.Lines.Count = 0) or (ADoc.View.Syn.Lines[0] = ''));
end;

function TDocumentManager.SoleBlankDoc: TDocument;
var
  doc: TDocument;
begin
  Result := nil;
  if GroupDocCount(FActiveGroup) <> 1 then Exit;
  doc := FirstDocInGroup(FActiveGroup);
  if IsBlankDoc(doc) then
    Result := doc;
end;

// pas sur un gros fichier: l'attache scanne tout le buffer, SYNCHRONE (~6,5 s / 1M lignes)
procedure ApplyAutoSyntax(ADoc: TDocument; const AFileName: string);
begin
  if ADoc.IsHex or ADoc.LargeFile then Exit;
  ADoc.View.Syn.Highlighter := HighlighterForFile(AFileName);
end;

function TDocumentManager.OpenFile(const AFileName: string): TDocument;
var
  idx: Integer;
  large, created: Boolean;
  blank: TDocument;
  sr: TSearchRec;
begin
  // macOS: le panneau Open laisse choisir un .app/.bundle, qui est un DOSSIER
  if DirectoryExists(AFileName) then
  begin
    if Assigned(FOnOpenFolder) then
      FOnOpenFolder(AFileName)
    else
      MessageDlg('RottenText',
        Format('%s is a folder, not a file.', [AFileName]),
        mtInformation, [mbOK], 0);
    Exit(nil);
  end;
  idx := IndexOfFile(AFileName);
  if idx >= 0 then
  begin
    Activate(idx);
    Exit(TDocument(FDocs[idx]));
  end;
  // taille connue AVANT la vue: une vue "large" ne recoit jamais le plugin wrap
  large := False;
  if SysUtils.FindFirst(AFileName, faAnyFile, sr) = 0 then
  begin
    large := sr.Size >= LargeFileBytes;
    SysUtils.FindClose(sr);
  end;
  // onglet vierge reutilise, sauf gros fichier: sa vue a deja le plugin wrap
  blank := SoleBlankDoc;
  Result := nil;
  if not large then
    Result := blank;
  created := Result = nil;
  if created then
    Result := AddDocIn(FActiveGroup, large);
  try
    Result.LoadFromFile(AFileName);
  except
    // sans ce menage, le doc fraichement cree resterait fantome dans la liste
    on E: Exception do
    begin
      if created then
      begin
        idx := FDocs.IndexOf(Result);
        if idx >= 0 then RemoveAt(idx);
      end;
      MessageDlg('RottenText',
        Format('Cannot open %s.' + LineEnding + '%s', [AFileName, E.Message]),
        mtError, [mbOK], 0);
      Exit(nil);
    end;
  end;
  if large and (blank <> nil) then
  begin
    idx := FDocs.IndexOf(blank);
    if idx >= 0 then RemoveAt(idx);
  end;
  // avant Activate: la minimap lit le highlighter au bind
  ApplyAutoSyntax(Result, AFileName);
  RecentAdd(AFileName);
  Notify(FOnListChanged);
  Activate(FDocs.IndexOf(Result));
end;

procedure TDocumentManager.OpenDialog;
var
  dlg: TOpenDialog;
  i: Integer;
begin
  dlg := TOpenDialog.Create(nil);
  BeginActionModal;
  try
    dlg.Options := dlg.Options + [ofAllowMultiSelect, ofFileMustExist];
    if dlg.Execute then
      for i := 0 to dlg.Files.Count - 1 do
        OpenFile(dlg.Files[i]);
  finally
    EndActionModal;
    dlg.Free;
  end;
end;

function TDocumentManager.ActiveDoc: TDocument;
begin
  Result := FGroupActive[FActiveGroup];
end;

procedure TDocumentManager.ShowGroupDoc(AGroup: Integer);
var
  i: Integer;
  d: TDocument;
begin
  // ShowDoc donne le focus: DocFocusedHandler n'y verrait un clic utilisateur
  Inc(FShowLock);
  try
    for i := 0 to FDocs.Count - 1 do
    begin
      d := TDocument(FDocs[i]);
      if (d.Group = AGroup) and (d <> FGroupActive[AGroup]) then
        d.HideDoc;
    end;
    if FGroupActive[AGroup] <> nil then
      FGroupActive[AGroup].ShowDoc;
  finally
    Dec(FShowLock);
  end;
end;

procedure TDocumentManager.ShowGroups;
begin
  // l'actif en dernier: son ShowDoc reprend le focus clavier
  ShowGroupDoc(1 - FActiveGroup);
  ShowGroupDoc(FActiveGroup);
end;

procedure TDocumentManager.Activate(AIndex: Integer);
var
  doc: TDocument;
begin
  if (AIndex < 0) or (AIndex >= FDocs.Count) then Exit;
  doc := TDocument(FDocs[AIndex]);
  FGroupActive[doc.Group] := doc;
  FActiveGroup := doc.Group;
  ShowGroupDoc(doc.Group);
  Notify(FOnActiveChanged);
end;

procedure TDocumentManager.ActivateGroup(AGroup: Integer);
begin
  if (AGroup < 0) or (AGroup > 1) then Exit;
  if (AGroup = 1) and not FSplit then Exit;
  if AGroup = FActiveGroup then Exit;
  FActiveGroup := AGroup;
  if FGroupActive[AGroup] <> nil then
    FGroupActive[AGroup].FocusDoc;
  Notify(FOnActiveChanged);
end;

procedure TDocumentManager.ActivateNext;
var
  i, cur: Integer;
begin
  cur := GetActiveIndex;
  if cur < 0 then Exit;
  i := cur;
  repeat
    i := (i + 1) mod FDocs.Count;
  until TDocument(FDocs[i]).Group = FActiveGroup;
  Activate(i);
end;

procedure TDocumentManager.ActivatePrev;
var
  i, cur: Integer;
begin
  cur := GetActiveIndex;
  if cur < 0 then Exit;
  i := cur;
  repeat
    i := (i - 1 + FDocs.Count) mod FDocs.Count;
  until TDocument(FDocs[i]).Group = FActiveGroup;
  Activate(i);
end;

procedure TDocumentManager.RemoveAt(AIndex: Integer);
var
  doc: TDocument;
  g: Integer;
begin
  doc := TDocument(FDocs[AIndex]);
  for g := 0 to 1 do
    if FGroupActive[g] = doc then FGroupActive[g] := nil;
  // liberer une vue focusee -> OnEnter d'un autre editeur -> Activate reentrant (AV)
  Inc(FShowLock);
  try
    doc.Free;
  finally
    Dec(FShowLock);
  end;
  FDocs.Delete(AIndex);
end;

procedure TDocumentManager.AfterListChange;
var
  g: Integer;
begin
  for g := 0 to 1 do
    if FGroupActive[g] = nil then
      FGroupActive[g] := FirstDocInGroup(g);
  if (FGroupActive[FActiveGroup] = nil) and
     (FGroupActive[1 - FActiveGroup] <> nil) then
    FActiveGroup := 1 - FActiveGroup;
  Notify(FOnListChanged);
  ShowGroups;
  Notify(FOnActiveChanged);
end;

function TDocumentManager.ConfirmCanClose(AIndex: Integer): Boolean;
var
  doc: TDocument;
begin
  doc := TDocument(FDocs[AIndex]);
  if not doc.Modified then Exit(True);
  Activate(AIndex);
  // fige la liste: sinon AIndex et les index des boucles appelantes glissent
  BeginActionModal;
  try
    case MessageDlg('RottenText',
        Format('Save changes to %s before closing?', [doc.DisplayName]),
        mtConfirmation, [mbYes, mbNo, mbCancel], 0) of
      mrYes: Result := SaveDoc(AIndex);
      mrNo:  Result := True;
    else
      Result := False;
    end;
  finally
    EndActionModal;
  end;
end;

// False = annule, le doc reste a AIndex (CheckExternalChanges ne doit pas boucler)
function TDocumentManager.CloseDoc(AIndex: Integer): Boolean;
var
  doc: TDocument;
begin
  Result := False;
  if (AIndex < 0) or (AIndex >= FDocs.Count) then Exit;
  if not ConfirmCanClose(AIndex) then Exit;
  doc := TDocument(FDocs[AIndex]);
  if FGroupActive[doc.Group] = doc then
    FGroupActive[doc.Group] := ReplacementFor(doc);
  RemoveAt(AIndex);
  AfterListChange;
  Result := True;
end;

procedure TDocumentManager.CloseOthers(AIndex: Integer);
var
  keep: TDocument;
  i: Integer;
begin
  if (AIndex < 0) or (AIndex >= FDocs.Count) then Exit;
  keep := TDocument(FDocs[AIndex]);
  for i := 0 to FDocs.Count - 1 do
    if (TDocument(FDocs[i]) <> keep) and (TDocument(FDocs[i]).Group = keep.Group)
       and not ConfirmCanClose(i) then Exit;
  for i := FDocs.Count - 1 downto 0 do
    if (TDocument(FDocs[i]) <> keep) and (TDocument(FDocs[i]).Group = keep.Group) then
      RemoveAt(i);
  FGroupActive[keep.Group] := keep;
  FActiveGroup := keep.Group;
  AfterListChange;
end;

procedure TDocumentManager.CloseToRight(AIndex: Integer);
var
  i, g: Integer;
begin
  if (AIndex < 0) or (AIndex >= FDocs.Count) then Exit;
  g := TDocument(FDocs[AIndex]).Group;
  for i := AIndex + 1 to FDocs.Count - 1 do
    if (TDocument(FDocs[i]).Group = g) and not ConfirmCanClose(i) then Exit;
  for i := FDocs.Count - 1 downto AIndex + 1 do
    if TDocument(FDocs[i]).Group = g then
      RemoveAt(i);
  AfterListChange;
end;

procedure TDocumentManager.CloseUnmodified(AGroup: Integer);
var
  i: Integer;
begin
  for i := FDocs.Count - 1 downto 0 do
    if not TDocument(FDocs[i]).Modified and
       ((AGroup < 0) or (TDocument(FDocs[i]).Group = AGroup)) then
      RemoveAt(i);
  AfterListChange;
end;

function TDocumentManager.CloseAll: Boolean;
var
  i: Integer;
begin
  Result := CanCloseAll;
  if not Result then Exit;
  for i := FDocs.Count - 1 downto 0 do
    RemoveAt(i);
  AfterListChange;
end;

function TDocumentManager.CanCloseAll(ASkipUntitled: Boolean): Boolean;
var
  i: Integer;
begin
  for i := 0 to FDocs.Count - 1 do
  begin
    if ASkipUntitled and TDocument(FDocs[i]).Untitled then Continue;
    if not ConfirmCanClose(i) then Exit(False);
  end;
  Result := True;
end;

function TDocumentManager.CanCloseUntitled: Boolean;
var
  i: Integer;
begin
  for i := 0 to FDocs.Count - 1 do
    if TDocument(FDocs[i]).Untitled and not ConfirmCanClose(i) then
      Exit(False);
  Result := True;
end;

function TDocumentManager.SaveDocAs(AIndex: Integer): Boolean;
var
  doc: TDocument;
  dlg: TSaveDialog;
begin
  Result := False;
  doc := TDocument(FDocs[AIndex]);
  dlg := TSaveDialog.Create(nil);
  // doc tenu en travers du dialogue natif: un reload externe pourrait le liberer
  BeginActionModal;
  try
    if not doc.Untitled then
      dlg.FileName := doc.FileName;
    while dlg.Execute do
    begin
      // chemin d'origine re-valide tel quel sur un read-only: fmCreate planterait
      if doc.ReadOnly and SameFileName(dlg.FileName, doc.FileName) then
      begin
        MessageDlg('RottenText',
          Format('%s is read-only. Choose another name.', [doc.DisplayName]),
          mtWarning, [mbOK], 0);
        Continue;
      end;
      try
        doc.SaveToFile(dlg.FileName);
      except
        on E: Exception do
        begin
          MessageDlg('RottenText',
            Format('Cannot save %s.' + LineEnding + '%s', [dlg.FileName, E.Message]),
            mtError, [mbOK], 0);
          Continue;
        end;
      end;
      ApplyAutoSyntax(doc, dlg.FileName);
      RecentAdd(dlg.FileName);
      if AIndex = GetActiveIndex then
        Notify(FOnActiveChanged);
      Exit(True);
    end;
  finally
    EndActionModal;
    dlg.Free;
  end;
end;

function TDocumentManager.SaveDoc(AIndex: Integer): Boolean;
var
  doc: TDocument;
begin
  doc := TDocument(FDocs[AIndex]);
  if doc.Untitled or doc.ReadOnly then
    Result := SaveDocAs(AIndex)
  else
  begin
    // doc tenu en travers des dialogues natifs ci-dessous: cf. SaveDocAs
    BeginActionModal;
    try
      // disque change et jamais recharge: ecrire ecraserait la version externe
      case doc.CheckDiskChange of
        dcModified:
          if MessageDlg('RottenText',
              Format('%s has changed on disk since it was loaded.' + LineEnding +
                'Overwrite the version on disk?', [doc.DisplayName]),
              mtWarning, [mbYes, mbCancel], 0) <> mrYes then
            Exit(False);
        dcDeleted:
          if MessageDlg('RottenText',
              Format('%s no longer exists on disk.' + LineEnding +
                'Save will recreate it. Continue?', [doc.DisplayName]),
              mtWarning, [mbYes, mbCancel], 0) <> mrYes then
            Exit(False);
      end;
      try
        doc.SaveToFile(doc.FileName);
        Result := True;
      except
        on E: Exception do
        begin
          MessageDlg('RottenText',
            Format('Cannot save %s.' + LineEnding + '%s', [doc.DisplayName, E.Message]),
            mtError, [mbOK], 0);
          Result := False;
        end;
      end;
    finally
      EndActionModal;
    end;
  end;
end;

procedure TDocumentManager.SaveActive;
begin
  if ActiveDoc <> nil then SaveDoc(GetActiveIndex);
end;

procedure TDocumentManager.SetActiveHighlighter(AHl: TSynCustomHighlighter);
begin
  if ActiveDoc = nil then Exit;
  ActiveDoc.View.Syn.Highlighter := AHl;
  Notify(FOnActiveChanged);
end;

procedure TDocumentManager.NotifyViewChanged;
begin
  Notify(FOnActiveChanged);
end;

procedure TDocumentManager.SaveActiveAs;
begin
  if ActiveDoc <> nil then SaveDocAs(GetActiveIndex);
end;

procedure TDocumentManager.SaveActiveWithEncoding(AEnc: Integer);
var
  old: Integer;
  doc: TDocument;
begin
  // capture: SaveDoc dialogue, relire ActiveDoc apres viserait un autre onglet
  doc := ActiveDoc;
  if (doc = nil) or doc.IsHex or doc.ReadOnly then Exit;
  old := doc.Encoding;
  doc.Encoding := AEnc;
  if SaveDoc(FDocs.IndexOf(doc)) then
    Notify(FOnActiveChanged)
  else
    doc.Encoding := old; // save annule: ne pas garder le nouvel encodage
end;

// stamp NON recapture: il masquerait une modif externe qu'un save ecraserait
procedure TDocumentManager.DiskActionFailed(ADoc: TDocument; E: Exception);
begin
  ADoc.DeferredReload := True;
  MessageDlg('RottenText',
    Format('Could not reload %s from disk:' + LineEnding + '%s',
      [ADoc.DisplayName, E.Message]), mtWarning, [mbOK], 0);
end;

procedure TDocumentManager.RevertActive;
begin
  if ActiveDoc = nil then Exit;
  try
    ActiveDoc.Revert;
  except
    on E: Exception do begin DiskActionFailed(ActiveDoc, E); Exit; end;
  end;
  // Revert peut changer LargeFile/highlighter/encodage: re-caler les bindings
  Activate(GetActiveIndex);
end;

procedure TDocumentManager.ReloadPreservingCaret(ADoc: TDocument);
var
  cx, cy, top: Integer;
begin
  if ADoc.IsHex then
  begin
    ADoc.Revert;
    Exit;
  end;
  cx := ADoc.View.Syn.CaretX;
  cy := ADoc.View.Syn.CaretY;
  top := ADoc.View.Syn.TopLine;
  ADoc.Revert;
  if cy > ADoc.View.Syn.Lines.Count then cy := ADoc.View.Syn.Lines.Count;
  if cy < 1 then cy := 1;
  ADoc.View.Syn.CaretXY := Point(cx, cy);
  ADoc.View.Syn.TopLine := top;
end;

// message a la PREMIERE panne seulement, les focus suivants re-tentent en silence
function TDocumentManager.SafeReload(ADoc: TDocument): Boolean;
begin
  Result := True;
  try
    ReloadPreservingCaret(ADoc);
  except
    on E: Exception do
    begin
      Result := False;
      if not ADoc.DeferredReload then
      begin
        ADoc.DeferredReload := True;
        MessageDlg('RottenText',
          Format('Could not reload %s:' + LineEnding + '%s' + LineEnding +
            'Use File > Revert File to retry.', [ADoc.DisplayName, E.Message]),
          mtWarning, [mbOK], 0);
      end;
    end;
  end;
end;

procedure TDocumentManager.CheckExternalChanges;
var
  i: Integer;
  d: TDocument;
  changed: Boolean;
begin
  if FCheckingExternal then Exit; // les dialogs ci-dessous re-declenchent OnActivate
  FCheckingExternal := True;
  // dialogues natifs: sans verrou, un open IPC/drop mute FDocs et decale i
  BeginActionModal;
  changed := False;
  try
    i := 0;
    while i < FDocs.Count do
    begin
      d := TDocument(FDocs[i]);
      case d.CheckDiskChange of
        dcModified:
          begin
            if not d.Modified then
            begin
              if SafeReload(d) then changed := True;
            end
            else if d.DeferredReload then
              // deja en echec et buffer modifie: ne pas re-demander en boucle
            else
            begin
              Activate(i);
              if MessageDlg('RottenText',
                  Format('%s has been changed by another program.' + LineEnding +
                    'Reload it and lose your unsaved changes?', [d.DisplayName]),
                  mtWarning, [mbYes, mbNo], 0) = mrYes then
              begin
                if SafeReload(d) then changed := True;
              end
              else
                d.CaptureDiskState; // garder ses modifs: ne plus re-demander
            end;
            Inc(i);
          end;
        dcDeleted:
          begin
            Activate(i);
            if MessageDlg('RottenText',
                Format('%s no longer exists on disk.' + LineEnding +
                  'Keep it in the editor?', [d.DisplayName]),
                mtWarning, [mbYes, mbNo], 0) = mrYes then
            begin
              d.MarkOrphan;
              Inc(i);
            end
            else if not CloseDoc(i) then
            begin
              // fermeture annulee: sans ca on re-boucle sur les memes dialogs
              d.MarkOrphan;
              Inc(i);
            end;
            // fermeture reussie: la liste a glisse, i pointe deja le suivant
          end;
      else
        Inc(i);
      end;
    end;
  finally
    EndActionModal;
    FCheckingExternal := False;
  end;
  if changed then
  begin
    // un reload peut changer la VUE (texte devenu binaire -> hex): re-montrer
    ShowGroups;
    Notify(FOnListChanged);
    Notify(FOnActiveChanged);
  end;
end;

procedure TDocumentManager.ReopenActiveWithEncoding(AEnc: Integer);
var
  wasHex: Boolean;
  doc: TDocument;
begin
  doc := ActiveDoc;
  if (doc = nil) or doc.Untitled or not FileExists(doc.FileName) then Exit;
  // doc capture: sous cocoa les timers IPC/drop tournent pendant le MessageDlg
  BeginActionModal;
  try
    if doc.Modified then
      if MessageDlg('RottenText',
          Format('Reopening %s will discard unsaved changes. Continue?',
            [doc.DisplayName]),
          mtConfirmation, [mbYes, mbCancel], 0) <> mrYes then Exit;
    wasHex := doc.IsHex;
    // le load libere la vue hex FOCUSEE -> Activate reentrant sans ce verrou
    Inc(FShowLock);
    try
      try
        doc.LoadFromFileEnc(doc.FileName, AEnc);
      except
        on E: Exception do begin DiskActionFailed(doc, E); Exit; end;
      end;
    finally
      Dec(FShowLock);
    end;
    // hors de ce cas, un choix manuel View > Syntax doit survivre
    if wasHex then
      ApplyAutoSyntax(doc, doc.FileName);
    Activate(FDocs.IndexOf(doc));
  finally
    EndActionModal;
  end;
end;

procedure TDocumentManager.ReopenActiveHex;
var
  doc: TDocument;
begin
  doc := ActiveDoc;
  if (doc = nil) or doc.Untitled or not FileExists(doc.FileName) then Exit;
  if doc.IsHex then Exit;
  // meme verrou que ReopenActiveWithEncoding: MessageDlg natif, doc tenu
  BeginActionModal;
  try
    if doc.Modified then
      if MessageDlg('RottenText',
          Format('Reopening %s will discard unsaved changes. Continue?',
            [doc.DisplayName]),
          mtConfirmation, [mbYes, mbCancel], 0) <> mrYes then Exit;
    try
      doc.OpenHex(doc.FileName);
    except
      on E: Exception do begin DiskActionFailed(doc, E); Exit; end;
    end;
    Activate(FDocs.IndexOf(doc));
  finally
    EndActionModal;
  end;
end;

function TDocumentManager.SaveAll: Boolean;
var
  i: Integer;
begin
  Result := True;
  // read-only modifies sautes: pas de rafale de dialogues Save As
  for i := 0 to FDocs.Count - 1 do
    if TDocument(FDocs[i]).Modified and not TDocument(FDocs[i]).ReadOnly then
    begin
      if TDocument(FDocs[i]).Untitled then
        Activate(i);
      if not SaveDoc(i) then
        Exit(False);
    end;
end;

procedure TDocumentManager.SetGroupHost(AGroup: Integer; AHost: TWinControl);
begin
  if (AGroup >= 0) and (AGroup <= 1) then
    FHosts[AGroup] := AHost;
end;

// parent ET owner: le host d'origine ne doit pas liberer une vue partie ailleurs
procedure TDocumentManager.ReparentDoc(ADoc: TDocument; AHost: TWinControl);
begin
  ADoc.View.Syn.Owner.RemoveComponent(ADoc.View.Syn);
  AHost.InsertComponent(ADoc.View.Syn);
  ADoc.View.Syn.Parent := AHost;
  if ADoc.HexView <> nil then
  begin
    ADoc.HexView.Owner.RemoveComponent(ADoc.HexView);
    AHost.InsertComponent(ADoc.HexView);
    ADoc.HexView.Parent := AHost;
  end;
end;

procedure TDocumentManager.SetSplit(AOn: Boolean);
var
  i: Integer;
  d, act: TDocument;
begin
  if AOn = FSplit then Exit;
  if AOn then
  begin
    if FHosts[1] = nil then Exit; // uMain fournit le host avant
    FSplit := True;
    NewFile(1);
    Exit;
  end;
  // verrou: Free et re-parentage bougent le focus (voir RemoveAt)
  Inc(FShowLock);
  try
    for i := FDocs.Count - 1 downto 0 do
      if (TDocument(FDocs[i]).Group = 1) and IsBlankDoc(TDocument(FDocs[i])) then
        RemoveAt(i);
    act := ActiveDoc; // apres le menage: l'actif a pu etre un vierge jete
    for i := 0 to FDocs.Count - 1 do
    begin
      d := TDocument(FDocs[i]);
      if d.Group = 1 then
      begin
        ReparentDoc(d, FHosts[0]);
        d.Group := 0;
      end;
    end;
    FGroupActive[1] := nil;
    FActiveGroup := 0;
    if act <> nil then FGroupActive[0] := act;
    FSplit := False;
  finally
    Dec(FShowLock);
  end;
  AfterListChange;
end;

procedure TDocumentManager.MoveToOtherGroup(AIndex: Integer);
var
  doc: TDocument;
  dst: Integer;
begin
  if not FSplit then Exit;
  if (AIndex < 0) or (AIndex >= FDocs.Count) then Exit;
  doc := TDocument(FDocs[AIndex]);
  dst := 1 - doc.Group;
  if FHosts[dst] = nil then Exit;
  // meme verrou que RemoveAt: re-parenter une vue focusee bouge le focus
  Inc(FShowLock);
  try
    if FGroupActive[doc.Group] = doc then
      FGroupActive[doc.Group] := ReplacementFor(doc);
    ReparentDoc(doc, FHosts[dst]);
    doc.Group := dst;
    FGroupActive[dst] := doc;
    FActiveGroup := dst; // le focus suit le fichier deplace
  finally
    Dec(FShowLock);
  end;
  Notify(FOnListChanged);
  ShowGroups;
  Notify(FOnActiveChanged);
end;

procedure TDocumentManager.MoveActiveToGroup(AGroup: Integer);
begin
  if (ActiveDoc = nil) or not FSplit then Exit;
  if (AGroup < 0) or (AGroup > 1) or (ActiveDoc.Group = AGroup) then Exit;
  MoveToOtherGroup(GetActiveIndex);
end;

// l'ordre des onglets d'un groupe = l'ordre de ses docs dans FDocs
procedure TDocumentManager.MoveDocInGroup(AIndex, ANewVisualPos: Integer);
var
  doc: TDocument;
  g, i, cnt, curPos, target: Integer;
  groupIdx: array of Integer;
begin
  if (AIndex < 0) or (AIndex >= FDocs.Count) then Exit;
  doc := TDocument(FDocs[AIndex]);
  g := doc.Group;
  SetLength(groupIdx, 0);
  for i := 0 to FDocs.Count - 1 do
    if TDocument(FDocs[i]).Group = g then
    begin
      SetLength(groupIdx, Length(groupIdx) + 1);
      groupIdx[High(groupIdx)] := i;
    end;
  cnt := Length(groupIdx);
  curPos := -1;
  for i := 0 to cnt - 1 do
    if groupIdx[i] = AIndex then curPos := i;
  if curPos < 0 then Exit;
  if ANewVisualPos < 0 then ANewVisualPos := 0;
  if ANewVisualPos > cnt - 1 then ANewVisualPos := cnt - 1;
  if ANewVisualPos = curPos then Exit;
  target := groupIdx[ANewVisualPos]; // TFPList.Move place l'element a cet index
  FDocs.Move(AIndex, target);
  Notify(FOnListChanged);
end;

end.
