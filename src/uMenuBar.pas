unit uMenuBar;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Controls, Graphics, Menus, LCLType, LCLProc, Types, Forms,
  uActions, uTheme, uHighlight, uEditorView, uEncoding, uRecent, uThemeLoad;

type
  TRTMenuBar = class(TCustomControl)
  private
    FActions: TAppActions;
    FMenus: array of TPopupMenu;
    FTitles: array of string;
    FRects: array of TRect;
    FHover: Integer;
    FOpen: Integer;
    FRecentSub: TMenuItem;
    FFileMenu: TPopupMenu;
    {$IFDEF DARWIN}
    FNativeRoots: array of TMenuItem;
    {$ENDIF}
    procedure BuildLabels;
    procedure BuildMenus;
    procedure FileMenuPopup(Sender: TObject);
    function AddMenu(const ATitle: string): TPopupMenu;
    function AddItem(AParent: TMenuItem; AMenu: TPopupMenu; const ACaption: string;
      AHandler: TNotifyEvent; AShortCut: TShortCut = 0): TMenuItem;
    procedure AddSep(AParent: TMenuItem; AMenu: TPopupMenu);
    procedure DrawMenuItem(Sender: TObject; ACanvas: TCanvas; ARect: TRect; AState: TOwnerDrawState);
    procedure MeasureMenuItem(Sender: TObject; ACanvas: TCanvas; var AWidth, AHeight: Integer);
    procedure OpenAt(AIndex: Integer);
    procedure PopupClosed(Sender: TObject);
  protected
    procedure Paint; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseLeave; override;
  public
    constructor Create(AOwner: TComponent); override;
    procedure Attach(AActions: TAppActions);
    {$IFDEF DARWIN}
    // les items sont DEPLACES dans un TMainMenu natif (barre globale macOS),
    // donc rendus par Cocoa: l'owner-draw et ses couleurs sont perdus.
    procedure AttachNative(AForm: TCustomForm);
    {$ENDIF}
    function MenuCount: Integer;
    function MenuTitle(AIndex: Integer): string;
    function MenuRoot(AIndex: Integer): TMenuItem;
    procedure RefreshRecent;
  end;

implementation

const
  LBL_PAD = 9;
  ITEM_H  = 24;
  SEP_H   = 9;
  WRAP_COLS: array[0..10] of Integer = (40, 70, 72, 74, 76, 78, 80, 90, 100, 110, 120);

constructor TRTMenuBar.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FHover := -1;
  FOpen := -1;
  Font.Name := RTFontName;
  Font.Size := 10;
  Font.Quality := fqCleartype;
end;

procedure TRTMenuBar.Attach(AActions: TAppActions);
begin
  FActions := AActions;
  BuildMenus;
  Invalidate;
end;

function TRTMenuBar.AddMenu(const ATitle: string): TPopupMenu;
begin
  Result := TPopupMenu.Create(Self);
  Result.OwnerDraw := True;
  Result.OnClose := @PopupClosed;
  SetLength(FMenus, Length(FMenus) + 1);
  SetLength(FTitles, Length(FTitles) + 1);
  FMenus[High(FMenus)] := Result;
  FTitles[High(FTitles)] := ATitle;
end;

function TRTMenuBar.AddItem(AParent: TMenuItem; AMenu: TPopupMenu; const ACaption: string;
  AHandler: TNotifyEvent; AShortCut: TShortCut): TMenuItem;
begin
  Result := TMenuItem.Create(AMenu);
  Result.Caption := ACaption;
  Result.OnClick := AHandler;
  Result.ShortCut := AShortCut;
  Result.OnDrawItem := @DrawMenuItem;
  Result.OnMeasureItem := @MeasureMenuItem;
  if AParent <> nil then
    AParent.Add(Result)
  else
    AMenu.Items.Add(Result);
end;

procedure TRTMenuBar.AddSep(AParent: TMenuItem; AMenu: TPopupMenu);
var
  mi: TMenuItem;
begin
  mi := TMenuItem.Create(AMenu);
  mi.Caption := '-';
  mi.OnDrawItem := @DrawMenuItem;
  mi.OnMeasureItem := @MeasureMenuItem;
  if AParent <> nil then AParent.Add(mi) else AMenu.Items.Add(mi);
end;

procedure TRTMenuBar.BuildMenus;
var
  m: TPopupMenu;
  sub, sub2, sub3, mi: TMenuItem;
  A: TAppActions;
  i: Integer;

  procedure AddEncodings(AParent: TMenuItem; AMenu: TPopupMenu;
    AHandler, AHexHandler: TNotifyEvent);
  var
    e: Integer;
    mi: TMenuItem; // LOCAL: sinon ecrase le 'mi' de BuildMenus -> FSaveItem faux
  begin
    for e := 0 to High(Encodings) do
    begin
      mi := AddItem(AParent, AMenu, Encodings[e].Caption, AHandler);
      mi.Tag := e;
      if e = ENC_UNICODE_LAST then AddSep(AParent, AMenu);
    end;
    AddSep(AParent, AMenu);
    AddItem(AParent, AMenu, 'Hexadecimal', AHexHandler);
  end;

begin
  A := FActions;

  // File
  m := AddMenu('File');
  AddItem(nil, m, 'New File', @A.FileNew, ShortCut(Word('N'), [ssModifier]));
  AddItem(nil, m, 'Open File...', @A.FileOpen, ShortCut(Word('O'), [ssModifier]));
  AddItem(nil, m, 'Open Folder...', @A.FileOpenFolder);
  FRecentSub := AddItem(nil, m, 'Open Recent', nil);
  FFileMenu := m;
  m.OnPopup := @FileMenuPopup;
  sub := AddItem(nil, m, 'Reopen with Encoding', nil);
  AddEncodings(sub, m, @A.FileReopenWithEncoding, @A.FileReopenHex);
  AddSep(nil, m);
  mi := AddItem(nil, m, 'Split View', @A.ViewSplit);
  A.SetSplitItem(mi);
  AddSep(nil, m);
  mi := AddItem(nil, m, 'Save', @A.FileSave, ShortCut(Word('S'), [ssModifier]));
  sub := AddItem(nil, m, 'Save with Encoding', nil);
  AddEncodings(sub, m, @A.FileSaveWithEncoding, @A.FileSaveHex);
  A.SetFileItems(mi, sub);
  AddItem(nil, m, 'Save As...', @A.FileSaveAs, ShortCut(Word('S'), [ssModifier, ssShift]));
  AddItem(nil, m, 'Save All', @A.FileSaveAll);
  AddSep(nil, m);
  AddItem(nil, m, 'Print...', @A.FilePrint);
  AddSep(nil, m);
  AddItem(nil, m, 'New Window', @A.FileNewWindow, ShortCut(Word('N'), [ssModifier, ssShift]));
  AddItem(nil, m, 'Close Window', @A.FileCloseWindow, ShortCut(Word('W'), [ssModifier, ssShift]));
  AddItem(nil, m, 'Close File', @A.FileClose, ShortCut(Word('W'), [ssModifier]));
  AddItem(nil, m, 'Revert File', @A.FileRevert);
  AddItem(nil, m, 'Close All Files', @A.FileCloseAll);
  {$IFNDEF DARWIN}
  // macOS: le Quit du menu app natif suffit
  AddSep(nil, m);
  AddItem(nil, m, 'Quit', @A.FileQuit); // pas de raccourci, Ctrl+Q = Record Macro
  {$ENDIF}

  // Edit
  m := AddMenu('Edit');
  AddItem(nil, m, 'Undo', @A.EditUndo, ShortCut(Word('Z'), [ssModifier]));
  AddItem(nil, m, 'Redo', @A.EditRedo, ShortCut(Word('Y'), [ssModifier]));
  AddSep(nil, m);
  AddItem(nil, m, 'Cut', @A.EditCut, ShortCut(Word('X'), [ssModifier]));
  AddItem(nil, m, 'Copy', @A.EditCopy, ShortCut(Word('C'), [ssModifier]));
  AddItem(nil, m, 'Paste', @A.EditPaste, ShortCut(Word('V'), [ssModifier]));
  AddItem(nil, m, 'Paste and Indent', @A.EditPasteIndent, ShortCut(Word('V'), [ssModifier, ssShift]));
  AddSep(nil, m);
  sub := AddItem(nil, m, 'Line', nil);
  AddItem(sub, m, 'Indent', @A.EditIndent, ShortCut(VK_OEM_6, [ssModifier]));
  AddItem(sub, m, 'Unindent', @A.EditUnindent, ShortCut(VK_OEM_4, [ssModifier]));
  AddItem(sub, m, 'Delete Line', @A.EditDeleteLine, ShortCut(Word('K'), [ssModifier, ssShift]));
  sub := AddItem(nil, m, 'Comment', nil);
  AddItem(sub, m, 'Toggle Comment', @A.EditToggleComment, ShortCut(VK_OEM_2, [ssModifier]));
  sub := AddItem(nil, m, 'Convert Case', nil);
  AddItem(sub, m, 'Upper Case', @A.EditUpperCase);
  AddItem(sub, m, 'Lower Case', @A.EditLowerCase);
  AddItem(sub, m, 'Title Case', @A.EditTitleCase);
  AddItem(sub, m, 'Swap Case', @A.EditSwapCase);
  AddItem(nil, m, 'Convert Tabs to Spaces', @A.EditExpandTabs);
  AddSep(nil, m);
  AddItem(nil, m, 'Sort Lines', @A.EditSortLines, ShortCut(VK_F9, []));

  // Selection
  m := AddMenu('Selection');
  AddItem(nil, m, 'Split into Lines', @A.SelSplitLines, ShortCut(Word('L'), [ssModifier, ssShift]));
  AddItem(nil, m, 'Single Selection', @A.SelSingle, ShortCut(VK_ESCAPE, []));
  AddSep(nil, m);
  AddItem(nil, m, 'Select All', @A.SelSelectAll, ShortCut(Word('A'), [ssModifier]));
  AddItem(nil, m, 'Expand Selection to Line', @A.SelExpandLine, ShortCut(Word('L'), [ssModifier]));
  AddItem(nil, m, 'Expand Selection to Word', @A.SelExpandWord, ShortCut(Word('D'), [ssModifier]));
  AddItem(nil, m, 'Expand Selection to Brackets', @A.SelExpandBrackets, ShortCut(Word('M'), [ssModifier, ssShift]));
  AddSep(nil, m);
  AddItem(nil, m, 'Add Previous Line', @A.SelAddPrevLine, ShortCut(VK_UP, [ssModifier, ssAlt]));
  AddItem(nil, m, 'Add Next Line', @A.SelAddNextLine, ShortCut(VK_DOWN, [ssModifier, ssAlt]));
  AddSep(nil, m);
  AddItem(nil, m, 'Fill with Lorem Ipsum', @A.SelFillLorem);

  // Find
  m := AddMenu('Find');
  AddItem(nil, m, 'Find...', @A.FindShow, ShortCut(Word('F'), [ssModifier]));
  AddItem(nil, m, 'Find Next', @A.FindNext, ShortCut(VK_F3, []));
  AddItem(nil, m, 'Find Previous', @A.FindPrev, ShortCut(VK_F3, [ssShift]));
  AddSep(nil, m);
  AddItem(nil, m, 'Replace...', @A.ReplaceShow, ShortCut(Word('H'), [ssModifier]));
  AddItem(nil, m, 'Replace Next', @A.ReplaceNext);
  AddItem(nil, m, 'Replace All', @A.ReplaceAll);
  AddSep(nil, m);
  // vue hex seulement (no-op sur un doc texte)
  AddItem(nil, m, 'Goto Offset...', @A.FindGotoOffset, ShortCut(Word('G'), [ssModifier]));

  // View
  m := AddMenu('View');
  mi := AddItem(nil, m, 'Side Bar', @A.ViewSideBar);
  A.SetSideBarItem(mi);
  AddSep(nil, m);
  if ThemeCount > 0 then
  begin
    sub := AddItem(nil, m, 'Theme', nil);
    for i := 0 to ThemeCount - 1 do
    begin
      mi := AddItem(sub, m, ThemeName(i), @A.ViewTheme);
      mi.Tag := i;
      mi.RadioItem := True;
      mi.GroupIndex := 3;
      mi.Checked := (i = CurrentTheme);
    end;
  end;
  sub := AddItem(nil, m, 'Syntax', nil);
  mi := AddItem(sub, m, 'Plain Text', @A.SetSyntax); mi.Tag := 0;
  AddSep(sub, m);
  for i := 0 to SyntaxCount - 1 do
  begin
    mi := AddItem(sub, m, SyntaxDisplayName(i), @A.SetSyntax);
    mi.Tag := i + 1;
  end;
  sub := AddItem(nil, m, 'Tab Width', nil);
  for i := 1 to 8 do
  begin
    mi := AddItem(sub, m, IntToStr(i), @A.ViewTabWidth);
    mi.Tag := i;
    mi.RadioItem := True;
    mi.GroupIndex := 1;
    mi.Checked := (i = RTTabWidth);
  end;
  AddSep(nil, m);
  mi := AddItem(nil, m, 'Word Wrap', @A.ViewWordWrap);
  mi.Checked := RTWordWrap;
  sub := AddItem(nil, m, 'Word Wrap Column', nil);
  mi := AddItem(sub, m, 'Automatic', @A.ViewWrapColumn);
  mi.Tag := 0;
  mi.RadioItem := True;
  mi.GroupIndex := 2;
  mi.Checked := (RTWrapColumn = 0);
  AddSep(sub, m);
  for i := 0 to High(WRAP_COLS) do
  begin
    mi := AddItem(sub, m, IntToStr(WRAP_COLS[i]), @A.ViewWrapColumn);
    mi.Tag := WRAP_COLS[i];
    mi.RadioItem := True;
    mi.GroupIndex := 2;
    mi.Checked := (RTWrapColumn = WRAP_COLS[i]);
  end;
  mi := AddItem(nil, m, 'Show Invisibles', @A.ViewShowInvisibles);
  mi.Checked := RTShowInvisibles;
  mi := AddItem(nil, m, 'Map Tab to Space', @A.ViewMapTabToSpace);
  mi.Checked := RTMapTabToSpace;

  // Macro
  m := AddMenu('Macro');
  mi := AddItem(nil, m, 'Record Macro', @A.MacroToggleRecord, ShortCut(Word('Q'), [ssModifier]));
  sub := AddItem(nil, m, 'Playback Macro', @A.MacroPlayback, ShortCut(Word('Q'), [ssModifier, ssShift]));
  A.SetMacroItems(mi, sub);

  // Tools: le Tag de chaque item porte la variante (handlers ToolsXxx d'uActions)
  m := AddMenu('Tools');
  AddItem(nil, m, 'Command Palette...', @A.ViewCommandPalette,
    ShortCut(Word('P'), [ssModifier, ssShift]));
  AddSep(nil, m);
  sub := AddItem(nil, m, 'Hash Selection', nil);
  mi := AddItem(sub, m, 'MD5', @A.ToolsTransform); mi.Tag := 10;
  mi := AddItem(sub, m, 'SHA-1', @A.ToolsTransform); mi.Tag := 11;
  mi := AddItem(sub, m, 'SHA-256', @A.ToolsTransform); mi.Tag := 12;
  mi := AddItem(sub, m, 'SHA-512', @A.ToolsTransform); mi.Tag := 13;
  sub := AddItem(nil, m, 'Checksum of File...', nil);
  mi := AddItem(sub, m, 'SHA-256', @A.ToolsHashFile); mi.Tag := 2;
  mi := AddItem(sub, m, 'SHA-1', @A.ToolsHashFile); mi.Tag := 1;
  mi := AddItem(sub, m, 'MD5', @A.ToolsHashFile); mi.Tag := 0;
  AddItem(nil, m, 'Insert Checksum Comment', @A.ToolsChecksumComment);
  sub := AddItem(nil, m, 'HMAC of Selection...', nil);
  mi := AddItem(sub, m, 'SHA-256', @A.ToolsHMAC); mi.Tag := 2;
  mi := AddItem(sub, m, 'SHA-1', @A.ToolsHMAC); mi.Tag := 1;
  mi := AddItem(sub, m, 'SHA-512', @A.ToolsHMAC); mi.Tag := 3;
  mi := AddItem(sub, m, 'MD5', @A.ToolsHMAC); mi.Tag := 0;
  AddSep(nil, m);
  sub := AddItem(nil, m, 'Encode / Decode', nil);
  mi := AddItem(sub, m, 'Base64 Encode', @A.ToolsTransform); mi.Tag := 20;
  mi := AddItem(sub, m, 'Base64 Decode', @A.ToolsTransform); mi.Tag := 21;
  mi := AddItem(sub, m, 'Base64 URL Encode', @A.ToolsTransform); mi.Tag := 22;
  mi := AddItem(sub, m, 'Base64 URL Decode', @A.ToolsTransform); mi.Tag := 23;
  AddSep(sub, m);
  mi := AddItem(sub, m, 'URL Encode', @A.ToolsTransform); mi.Tag := 24;
  mi := AddItem(sub, m, 'URL Decode', @A.ToolsTransform); mi.Tag := 25;
  AddSep(sub, m);
  mi := AddItem(sub, m, 'HTML Encode', @A.ToolsTransform); mi.Tag := 26;
  mi := AddItem(sub, m, 'HTML Decode', @A.ToolsTransform); mi.Tag := 27;
  AddSep(sub, m);
  mi := AddItem(sub, m, 'Hex Encode', @A.ToolsTransform); mi.Tag := 28;
  mi := AddItem(sub, m, 'Hex Decode', @A.ToolsTransform); mi.Tag := 29;
  sub := AddItem(nil, m, 'Escape Selection For', nil);
  mi := AddItem(sub, m, 'Bash', @A.ToolsTransform); mi.Tag := 30;
  mi := AddItem(sub, m, 'PowerShell', @A.ToolsTransform); mi.Tag := 31;
  mi := AddItem(sub, m, 'JSON', @A.ToolsTransform); mi.Tag := 32;
  mi := AddItem(sub, m, 'YAML', @A.ToolsTransform); mi.Tag := 33;
  mi := AddItem(sub, m, 'SQL', @A.ToolsTransform); mi.Tag := 34;
  AddSep(sub, m);
  mi := AddItem(sub, m, 'sed (pattern)', @A.ToolsTransform); mi.Tag := 35;
  mi := AddItem(sub, m, 'sed (replacement)', @A.ToolsTransform); mi.Tag := 36;
  mi := AddItem(sub, m, 'Regex (literal)', @A.ToolsTransform); mi.Tag := 37;
  mi := AddItem(sub, m, 'systemd Exec line', @A.ToolsTransform); mi.Tag := 38;
  mi := AddItem(sub, m, 'nginx / Apache string', @A.ToolsTransform); mi.Tag := 39;
  sub := AddItem(nil, m, 'Permissions', nil);
  mi := AddItem(sub, m, 'Convert Mode (rwx / octal)...', @A.ToolsPerms); mi.Tag := 0;
  mi := AddItem(sub, m, 'umask Calculator...', @A.ToolsPerms); mi.Tag := 1;
  sub := AddItem(nil, m, 'Line Endings', nil);
  mi := AddItem(sub, m, 'To LF (Unix)', @A.ToolsEol); mi.Tag := 0;
  mi := AddItem(sub, m, 'To CRLF (Windows)', @A.ToolsEol); mi.Tag := 1;
  mi := AddItem(sub, m, 'To CR (legacy Mac)', @A.ToolsEol); mi.Tag := 2;
  AddSep(nil, m);
  sub := AddItem(nil, m, 'Generate', nil);
  mi := AddItem(sub, m, 'Password to Clipboard...', @A.ToolsGenPassword); mi.Tag := 0;
  mi := AddItem(sub, m, 'Insert Password...', @A.ToolsGenPassword); mi.Tag := 1;
  AddSep(sub, m);
  mi := AddItem(sub, m, 'UUID', @A.ToolsInsert); mi.Tag := 40;
  mi := AddItem(sub, m, 'Unix Timestamp', @A.ToolsInsert); mi.Tag := 41;
  mi := AddItem(sub, m, 'ISO 8601 (Local)', @A.ToolsInsert); mi.Tag := 42;
  mi := AddItem(sub, m, 'ISO 8601 (UTC)', @A.ToolsInsert); mi.Tag := 43;
  AddSep(sub, m);
  mi := AddItem(sub, m, 'Token (Hex, 32 bytes)', @A.ToolsInsert); mi.Tag := 50;
  mi := AddItem(sub, m, 'Token (Base64, 32 bytes)', @A.ToolsInsert); mi.Tag := 51;
  mi := AddItem(sub, m, 'Token (base64url, 32 bytes)', @A.ToolsInsert); mi.Tag := 52;
  mi := AddItem(sub, m, 'API Key...', @A.ToolsInsert); mi.Tag := 53;
  AddSep(sub, m);
  sub2 := AddItem(sub, m, '.htpasswd Entry...', nil);
  mi := AddItem(sub2, m, 'bcrypt (recommended)', @A.ToolsHtpasswd); mi.Tag := 0;
  mi := AddItem(sub2, m, 'MD5 (apr1)', @A.ToolsHtpasswd); mi.Tag := 1;
  mi := AddItem(sub2, m, 'SHA-1 (compatibility)', @A.ToolsHtpasswd); mi.Tag := 2;
  sub2 := AddItem(sub, m, 'LDAP', nil);
  // Tag = TLdapPwScheme (uLdap); SASL = une identite, pas un hash
  sub3 := AddItem(sub2, m, 'userPassword...', nil);
  mi := AddItem(sub3, m, 'SSHA (recommended)', @A.ToolsLdapPassword); mi.Tag := 0;
  mi := AddItem(sub3, m, 'SSHA-256', @A.ToolsLdapPassword); mi.Tag := 1;
  mi := AddItem(sub3, m, 'SSHA-512', @A.ToolsLdapPassword); mi.Tag := 2;
  AddSep(sub3, m);
  mi := AddItem(sub3, m, 'CRYPT (bcrypt)', @A.ToolsLdapPassword); mi.Tag := 6;
  mi := AddItem(sub3, m, 'SHA (unsalted)', @A.ToolsLdapPassword); mi.Tag := 3;
  mi := AddItem(sub3, m, 'SMD5', @A.ToolsLdapPassword); mi.Tag := 4;
  mi := AddItem(sub3, m, 'MD5 (unsalted)', @A.ToolsLdapPassword); mi.Tag := 5;
  AddSep(sub3, m);
  mi := AddItem(sub3, m, 'SASL (passthrough)', @A.ToolsLdapPassword); mi.Tag := 7;
  AddSep(sub2, m);
  AddItem(sub2, m, 'LDIF: Root (domain)...', @A.ToolsLdifRoot);
  AddItem(sub2, m, 'LDIF: Organizational Unit...', @A.ToolsLdifOU);
  AddItem(sub2, m, 'LDIF: Person / Account...', @A.ToolsLdifEntry);
  AddItem(sub2, m, 'LDIF: Group (posixGroup)...', @A.ToolsLdifGroup);
  AddItem(sub2, m, 'LDIF: Group (groupOfNames)...', @A.ToolsLdifGroupOfNames);
  AddItem(sub2, m, 'LDIF: Service / Bind Account...', @A.ToolsLdifService);
  // Tag = TProtoKind (uProto)
  sub2 := AddItem(sub, m, 'Protocol', nil);
  mi := AddItem(sub2, m, 'HTTP...', @A.ToolsHttp); mi.Tag := 0;
  mi := AddItem(sub2, m, 'HTTPS...', @A.ToolsHttp); mi.Tag := 1;
  AddSep(sub2, m);
  mi := AddItem(sub2, m, 'SMTP', @A.ToolsProtocol); mi.Tag := 2;
  mi := AddItem(sub2, m, 'SMTP (STARTTLS)', @A.ToolsProtocol); mi.Tag := 3;
  mi := AddItem(sub2, m, 'SMTPS (TLS)', @A.ToolsProtocol); mi.Tag := 4;
  AddSep(sub2, m);
  mi := AddItem(sub2, m, 'POP3', @A.ToolsProtocol); mi.Tag := 5;
  mi := AddItem(sub2, m, 'POP3S (TLS)', @A.ToolsProtocol); mi.Tag := 6;
  mi := AddItem(sub2, m, 'IMAP', @A.ToolsProtocol); mi.Tag := 7;
  mi := AddItem(sub2, m, 'IMAPS (TLS)', @A.ToolsProtocol); mi.Tag := 8;
  AddSep(sub2, m);
  mi := AddItem(sub2, m, 'FTP', @A.ToolsProtocol); mi.Tag := 9;
  mi := AddItem(sub2, m, 'FTPS (AUTH TLS)', @A.ToolsProtocol); mi.Tag := 10;
  mi := AddItem(sub2, m, 'Redis', @A.ToolsProtocol); mi.Tag := 11;
  AddSep(sub2, m);
  mi := AddItem(sub2, m, 'NNTP', @A.ToolsProtocol); mi.Tag := 18;
  mi := AddItem(sub2, m, 'WHOIS', @A.ToolsProtocol); mi.Tag := 19;
  mi := AddItem(sub2, m, 'IRC', @A.ToolsProtocol); mi.Tag := 20;
  mi := AddItem(sub2, m, 'Memcached', @A.ToolsProtocol); mi.Tag := 21;
  mi := AddItem(sub2, m, 'SIP (OPTIONS ping)', @A.ToolsProtocol); mi.Tag := 22;
  mi := AddItem(sub2, m, 'Graphite / Carbon', @A.ToolsProtocol); mi.Tag := 23;
  mi := AddItem(sub2, m, 'Beanstalkd', @A.ToolsProtocol); mi.Tag := 24;
  AddSep(sub2, m);
  mi := AddItem(sub2, m, 'LDAP (ldapsearch)', @A.ToolsProtocol); mi.Tag := 12;
  mi := AddItem(sub2, m, 'MySQL (mysql client)', @A.ToolsProtocol); mi.Tag := 13;
  mi := AddItem(sub2, m, 'PostgreSQL (psql)', @A.ToolsProtocol); mi.Tag := 14;
  AddSep(sub2, m);
  mi := AddItem(sub2, m, 'PHP-FPM (FastCGI)', @A.ToolsProtocol); mi.Tag := 15;
  mi := AddItem(sub2, m, 'Traefik API (curl)', @A.ToolsProtocol); mi.Tag := 16;
  mi := AddItem(sub2, m, 'Docker Engine API (curl)', @A.ToolsProtocol); mi.Tag := 17;
  mi := AddItem(sub2, m, 'Kubernetes API (curl)', @A.ToolsProtocol); mi.Tag := 25;
  sub := AddItem(nil, m, 'JSON', nil);
  mi := AddItem(sub, m, 'Validate', @A.ToolsJson); mi.Tag := 0;
  mi := AddItem(sub, m, 'Format', @A.ToolsJson); mi.Tag := 1;
  mi := AddItem(sub, m, 'Minify', @A.ToolsJson); mi.Tag := 2;
  mi := AddItem(sub, m, 'Sort Keys', @A.ToolsJson); mi.Tag := 3;
  sub := AddItem(nil, m, 'XML', nil);
  mi := AddItem(sub, m, 'Validate', @A.ToolsXml); mi.Tag := 0;
  mi := AddItem(sub, m, 'Format', @A.ToolsXml); mi.Tag := 1;
  sub := AddItem(nil, m, 'YAML', nil);
  mi := AddItem(sub, m, 'Validate', @A.ToolsYaml); mi.Tag := 0;
  mi := AddItem(sub, m, 'Flatten to Dotted Paths', @A.ToolsYaml); mi.Tag := 1;
  mi := AddItem(sub, m, 'Sort Keys...', @A.ToolsYaml); mi.Tag := 2;
  AddItem(sub, m, 'Values Diff vs File...', @A.ToolsYamlDiff);
  sub := AddItem(nil, m, 'INI', nil);
  mi := AddItem(sub, m, 'Validate', @A.ToolsIni); mi.Tag := 0;
  mi := AddItem(sub, m, 'Sort Keys', @A.ToolsIni); mi.Tag := 1;
  mi := AddItem(sub, m, 'Find Duplicate Keys', @A.ToolsIni); mi.Tag := 2;
  sub := AddItem(nil, m, 'TOML', nil);
  mi := AddItem(sub, m, 'Validate', @A.ToolsToml); mi.Tag := 0;
  mi := AddItem(sub, m, 'Sort Keys', @A.ToolsToml); mi.Tag := 1;
  mi := AddItem(sub, m, 'Find Duplicate Keys', @A.ToolsToml); mi.Tag := 2;
  sub := AddItem(nil, m, 'Kubernetes', nil);
  mi := AddItem(sub, m, 'Secret from key=value...', @A.ToolsKube); mi.Tag := 0;
  mi := AddItem(sub, m, 'Decode Secret', @A.ToolsKube); mi.Tag := 1;
  mi := AddItem(sub, m, 'ConfigMap from key=value...', @A.ToolsKube); mi.Tag := 2;
  mi := AddItem(sub, m, 'Decode ConfigMap', @A.ToolsKube); mi.Tag := 3;
  sub := AddItem(nil, m, '.env', nil);
  mi := AddItem(sub, m, 'Sort Keys', @A.ToolsEnv); mi.Tag := 0;
  mi := AddItem(sub, m, 'Find Duplicate Keys', @A.ToolsEnv); mi.Tag := 1;
  mi := AddItem(sub, m, 'Redact Secrets', @A.ToolsEnv); mi.Tag := 2;
  mi := AddItem(sub, m, 'Quote Values', @A.ToolsEnv); mi.Tag := 5;
  mi := AddItem(sub, m, 'Unquote Values', @A.ToolsEnv); mi.Tag := 6;
  AddSep(sub, m);
  mi := AddItem(sub, m, 'To JSON', @A.ToolsEnv); mi.Tag := 3;
  mi := AddItem(sub, m, 'From JSON', @A.ToolsEnv); mi.Tag := 4;
  mi := AddItem(sub, m, 'To YAML', @A.ToolsEnv); mi.Tag := 7;
  mi := AddItem(sub, m, 'From YAML', @A.ToolsEnv); mi.Tag := 8;
  sub := AddItem(nil, m, 'Docker / Compose', nil);
  mi := AddItem(sub, m, 'List Images', @A.ToolsCompose); mi.Tag := 0;
  mi := AddItem(sub, m, 'Environment to .env', @A.ToolsCompose); mi.Tag := 1;
  mi := AddItem(sub, m, 'Set Image Tag...', @A.ToolsCompose); mi.Tag := 2;
  sub := AddItem(nil, m, 'Podman Quadlet', nil);
  mi := AddItem(sub, m, 'List Image', @A.ToolsQuadlet); mi.Tag := 0;
  mi := AddItem(sub, m, 'Environment to .env', @A.ToolsQuadlet); mi.Tag := 1;
  mi := AddItem(sub, m, 'Set Image Tag...', @A.ToolsQuadlet); mi.Tag := 2;
  sub := AddItem(nil, m, 'Terraform', nil);
  mi := AddItem(sub, m, 'List Variables', @A.ToolsTerraform); mi.Tag := 0;
  mi := AddItem(sub, m, 'tfvars Skeleton', @A.ToolsTerraform); mi.Tag := 1;
  mi := AddItem(sub, m, 'Find Duplicate Variables', @A.ToolsTerraform); mi.Tag := 2;
  sub := AddItem(nil, m, 'Helm', nil);
  mi := AddItem(sub, m, 'Values Skeleton from Template', @A.ToolsHelm); mi.Tag := 0;
  mi := AddItem(sub, m, 'Values Skeleton from Folder...', @A.ToolsHelmFolder); mi.Tag := 0;
  mi := AddItem(sub, m, 'Values Path at Cursor', @A.ToolsHelm); mi.Tag := 1;
  AddItem(sub, m, 'Find Missing / Unused Values...', @A.ToolsHelmIssues);
  mi := AddItem(sub, m, 'Find Missing / Unused (Folder)...', @A.ToolsHelmFolder); mi.Tag := 1;
  AddItem(sub, m, 'Wrap Value in quote', @A.ToolsHelmQuote);
  AddItem(sub, m, 'Value to toYaml | nindent...', @A.ToolsHelmToYaml);
  sub2 := AddItem(sub, m, 'Insert Snippet', nil);
  mi := AddItem(sub2, m, 'If .Values.enabled', @A.ToolsHelmSnippet); mi.Tag := 0;
  mi := AddItem(sub2, m, 'With .Values.section', @A.ToolsHelmSnippet); mi.Tag := 1;
  mi := AddItem(sub2, m, 'Range .Values.items', @A.ToolsHelmSnippet); mi.Tag := 2;
  mi := AddItem(sub2, m, 'Include (fullname)', @A.ToolsHelmSnippet); mi.Tag := 3;
  mi := AddItem(sub2, m, 'Common Labels', @A.ToolsHelmSnippet); mi.Tag := 4;
  mi := AddItem(sub2, m, 'Selector Labels', @A.ToolsHelmSnippet); mi.Tag := 5;
  mi := AddItem(sub2, m, 'Resources (toYaml)', @A.ToolsHelmSnippet); mi.Tag := 6;
  AddSep(nil, m);
  AddItem(nil, m, 'IP / CIDR Calculator...', @A.ToolsIpCalc);
  AddItem(nil, m, 'nmap Command Builder...', @A.ToolsNmap);
  AddItem(nil, m, 'Timestamp Converter...', @A.ToolsTimestamp);
  AddItem(nil, m, 'Cron / Timer Explainer...', @A.ToolsCron);
  AddItem(nil, m, 'JWT Inspector...', @A.ToolsJwt);
  AddItem(nil, m, 'Mail Trace', @A.ToolsMailTrace);
  sub := AddItem(nil, m, 'X.509 Certificate', nil);
  mi := AddItem(sub, m, 'Inspect Buffer / Selection', @A.ToolsX509); mi.Tag := 0;
  mi := AddItem(sub, m, 'Inspect File...', @A.ToolsX509); mi.Tag := 1;
  sub := AddItem(nil, m, 'Extract / Count', nil);
  mi := AddItem(sub, m, 'IPv4 Addresses', @A.ToolsExtract); mi.Tag := 0;
  mi := AddItem(sub, m, 'URLs', @A.ToolsExtract); mi.Tag := 1;
  mi := AddItem(sub, m, 'Email Addresses', @A.ToolsExtract); mi.Tag := 2;
  mi := AddItem(sub, m, 'UUIDs', @A.ToolsExtract); mi.Tag := 3;
  mi := AddItem(sub, m, 'Hashes (hex)', @A.ToolsExtract); mi.Tag := 4;
  mi := AddItem(sub, m, 'Hostnames', @A.ToolsExtract); mi.Tag := 5;
  AddSep(sub, m);
  mi := AddItem(sub, m, 'All of the Above', @A.ToolsExtract); mi.Tag := 9;
  sub := AddItem(nil, m, 'Log', nil);
  mi := AddItem(sub, m, 'Normalize Timestamps', @A.ToolsLog); mi.Tag := 0;
  mi := AddItem(sub, m, 'Sort by Timestamp', @A.ToolsLog); mi.Tag := 1;
  mi := AddItem(sub, m, 'Merge with File...', @A.ToolsLog); mi.Tag := 2;
  mi := AddItem(sub, m, 'Deltas Between Timestamps', @A.ToolsLog); mi.Tag := 3;
  mi := AddItem(sub, m, 'Summary (Top Errors / IPs / Status)', @A.ToolsLog); mi.Tag := 4;
  AddItem(nil, m, 'Diff vs File...', @A.ToolsDiff);

  // Help
  m := AddMenu('Help');
  AddItem(nil, m, 'About RottenText', @A.HelpAbout);
end;

// MRU relue du disque a chaque popup: les autres fenetres sont des process
// separes.
procedure TRTMenuBar.RefreshRecent;
var
  i: Integer;
  mi: TMenuItem;
begin
  if (FRecentSub = nil) or (FFileMenu = nil) then Exit;
  FRecentSub.Clear;
  RecentReload;
  for i := 0 to RecentCount - 1 do
  begin
    // libelle assaini; l'ouverture repart du chemin brut
    mi := AddItem(FRecentSub, FFileMenu, RecentDisplay(i), @FActions.FileOpenRecent);
    mi.Tag := i;
  end;
  if RecentCount > 0 then AddSep(FRecentSub, FFileMenu);
  mi := AddItem(FRecentSub, FFileMenu, 'Clear Items', @FActions.FileClearRecent);
  mi.Enabled := RecentCount > 0;
end;

procedure TRTMenuBar.FileMenuPopup(Sender: TObject);
begin
  RefreshRecent;
end;

{$IFDEF DARWIN}
// Le menu natif consomme ses equivalents clavier AVANT le KeyDown LCL: Esc
// grabberait la fermeture de la find bar, et Cmd+Q / Cmd+H appartiennent a
// macOS (Quit / Hide).
procedure DarwinFixShortcuts(AItem: TMenuItem);
var
  i: Integer;
begin
  for i := 0 to AItem.Count - 1 do
    DarwinFixShortcuts(AItem.Items[i]);
  if AItem.ShortCut = ShortCut(VK_ESCAPE, []) then
    AItem.ShortCut := 0
  else if AItem.ShortCut = ShortCut(Word('Q'), [ssModifier]) then
    AItem.ShortCut := ShortCut(Word('Q'), [ssCtrl])
  else if AItem.ShortCut = ShortCut(Word('Q'), [ssModifier, ssShift]) then
    AItem.ShortCut := ShortCut(Word('Q'), [ssCtrl, ssShift])
  else if AItem.ShortCut = ShortCut(Word('H'), [ssModifier]) then
    AItem.ShortCut := ShortCut(Word('F'), [ssModifier, ssAlt]);
end;

procedure TRTMenuBar.AttachNative(AForm: TCustomForm);
var
  mm: TMainMenu;
  root, child: TMenuItem;
  i: Integer;
begin
  mm := TMainMenu.Create(AForm);
  SetLength(FNativeRoots, Length(FMenus));
  for i := 0 to High(FMenus) do
  begin
    root := TMenuItem.Create(mm);
    root.Caption := FTitles[i];
    mm.Items.Add(root);
    // deplacer, pas cloner: la palette et uActions pointent sur CES objets
    while FMenus[i].Items.Count > 0 do
    begin
      child := FMenus[i].Items[0];
      FMenus[i].Items.Delete(0);
      root.Add(child);
    end;
    DarwinFixShortcuts(root);
    FNativeRoots[i] := root;
  end;
  // pas de OnPopup en natif (Cocoa fire le OnClick du parent), et un parent SANS
  // enfant n'a pas de NSMenu: il faut le peupler une premiere fois ici.
  if FRecentSub <> nil then
  begin
    FRecentSub.OnClick := @FileMenuPopup;
    RefreshRecent;
  end;
  AForm.Menu := mm;
end;
{$ENDIF}

function TRTMenuBar.MenuCount: Integer;
begin
  Result := Length(FMenus);
end;

function TRTMenuBar.MenuTitle(AIndex: Integer): string;
begin
  Result := FTitles[AIndex];
end;

function TRTMenuBar.MenuRoot(AIndex: Integer): TMenuItem;
begin
  {$IFDEF DARWIN}
  if (AIndex <= High(FNativeRoots)) and (FNativeRoots[AIndex] <> nil) then
    Exit(FNativeRoots[AIndex]);
  {$ENDIF}
  Result := FMenus[AIndex].Items;
end;

procedure TRTMenuBar.BuildLabels;
var
  i, x, w: Integer;
begin
  Canvas.Font := Font;
  SetLength(FRects, Length(FTitles));
  x := 6;
  for i := 0 to High(FTitles) do
  begin
    w := Canvas.TextWidth(FTitles[i]) + LBL_PAD * 2;
    FRects[i] := Rect(x, 0, x + w, ClientHeight);
    Inc(x, w);
  end;
end;

procedure TRTMenuBar.Paint;
var
  i, ty: Integer;
begin
  BuildLabels;
  Canvas.Brush.Color := clMenuBg;
  Canvas.FillRect(ClientRect);
  Canvas.Brush.Style := bsClear;
  ty := (ClientHeight - Canvas.TextHeight('Ag')) div 2;
  for i := 0 to High(FTitles) do
  begin
    if (i = FHover) or (i = FOpen) then
    begin
      Canvas.Brush.Style := bsSolid;
      Canvas.Brush.Color := clMenuHover;
      Canvas.FillRect(FRects[i]);
      Canvas.Brush.Style := bsClear;
    end;
    Canvas.Font.Color := clMenuText;
    Canvas.TextOut(FRects[i].Left + LBL_PAD, ty, FTitles[i]);
  end;
  Canvas.Brush.Style := bsSolid;
end;

procedure TRTMenuBar.OpenAt(AIndex: Integer);
var
  p: TPoint;
begin
  if (AIndex < 0) or (AIndex > High(FMenus)) then Exit;
  FOpen := AIndex;
  Invalidate;
  p := ClientToScreen(Point(FRects[AIndex].Left, ClientHeight));
  FMenus[AIndex].PopUp(p.X, p.Y);
end;

procedure TRTMenuBar.PopupClosed(Sender: TObject);
begin
  FOpen := -1;
  Invalidate;
end;

procedure TRTMenuBar.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  i: Integer;
begin
  inherited MouseDown(Button, Shift, X, Y);
  for i := 0 to High(FRects) do
    if (X >= FRects[i].Left) and (X < FRects[i].Right) then
    begin
      OpenAt(i);
      Exit;
    end;
end;

procedure TRTMenuBar.MouseMove(Shift: TShiftState; X, Y: Integer);
var
  i, old: Integer;
begin
  inherited MouseMove(Shift, X, Y);
  old := FHover;
  FHover := -1;
  for i := 0 to High(FRects) do
    if (X >= FRects[i].Left) and (X < FRects[i].Right) then
    begin
      FHover := i;
      Break;
    end;
  if old <> FHover then Invalidate;
end;

procedure TRTMenuBar.MouseLeave;
begin
  inherited MouseLeave;
  if FHover <> -1 then
  begin
    FHover := -1;
    Invalidate;
  end;
end;

procedure TRTMenuBar.MeasureMenuItem(Sender: TObject; ACanvas: TCanvas; var AWidth, AHeight: Integer);
var
  mi: TMenuItem;
  scw: Integer;
begin
  mi := TMenuItem(Sender);
  ACanvas.Font := Font;
  if mi.Caption = '-' then
  begin
    AHeight := SEP_H;
    Exit;
  end;
  scw := 0;
  if mi.ShortCut <> 0 then
    scw := ACanvas.TextWidth(ShortCutToText(mi.ShortCut)) + 24;
  AWidth := 28 + ACanvas.TextWidth(mi.Caption) + 30 + scw + 16;
  AHeight := ITEM_H;
end;

procedure TRTMenuBar.DrawMenuItem(Sender: TObject; ACanvas: TCanvas; ARect: TRect; AState: TOwnerDrawState);
var
  mi: TMenuItem;
  ty: Integer;
  sc: string;
begin
  mi := TMenuItem(Sender);
  ACanvas.Font := Font;

  if mi.Caption = '-' then
  begin
    ACanvas.Brush.Color := clMenuPopupBg;
    ACanvas.FillRect(ARect);
    ACanvas.Pen.Color := RGBToColor($D7, $D7, $D7);
    ACanvas.Line(ARect.Left + 8, (ARect.Top + ARect.Bottom) div 2,
      ARect.Right - 8, (ARect.Top + ARect.Bottom) div 2);
    Exit;
  end;

  if odSelected in AState then
    ACanvas.Brush.Color := clMenuHover
  else
    ACanvas.Brush.Color := clMenuPopupBg;
  ACanvas.FillRect(ARect);

  ty := ARect.Top + (ARect.Bottom - ARect.Top - ACanvas.TextHeight('Ag')) div 2;
  ACanvas.Brush.Style := bsClear;
  if odDisabled in AState then
    ACanvas.Font.Color := clMenuDisabled
  else
    ACanvas.Font.Color := clMenuText;

  if mi.Checked then
    ACanvas.TextOut(ARect.Left + 10, ty, #$E2#$9C#$93); // check mark
  ACanvas.TextOut(ARect.Left + 28, ty, mi.Caption);

  if mi.ShortCut <> 0 then
  begin
    sc := ShortCutToText(mi.ShortCut);
    ACanvas.Font.Color := clMenuDisabled;
    ACanvas.TextOut(ARect.Right - ACanvas.TextWidth(sc) - 16, ty, sc);
  end;
  ACanvas.Brush.Style := bsSolid;
end;

end.
