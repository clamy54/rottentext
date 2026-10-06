unit uAppMenu;

{$mode objfpc}{$H+}

// Arbre des menus de l'appli, dans UN TMainMenu. macOS: il part au menu global
// natif. Ailleurs: la barre du kit (uMenuBar) l'adopte et DEPLACE les enfants
// de chaque racine dans ses popups.

interface

uses
  Classes, SysUtils, Controls, Menus, LCLType, Forms,
  uActions, uHighlight, uEditorView, uEncoding, uRecent, uThemeLoad, uMenuBar;

type
  TAppMenu = class(TComponent)
  private
    FActions: TAppActions;
    FMenu: TMainMenu;
    FBar: TRSMenuBar;
    FFileRoot: TMenuItem;
    FRecentSub: TMenuItem;
    procedure BuildMenus;
    procedure FileMenuPopup(Sender: TObject);
    function AddMenu(const ATitle: string): TMenuItem;
    function AddItem(AParent: TMenuItem; const ACaption: string;
      AHandler: TNotifyEvent; AShortCut: TShortCut = 0): TMenuItem;
    procedure AddSep(AParent: TMenuItem);
  public
    constructor Create(AOwner: TComponent; AActions: TAppActions); reintroduce;
    // barre dessinee du kit: les items partent dans ses popups
    procedure AttachBar(ABar: TRSMenuBar);
    {$IFDEF DARWIN}
    // barre globale macOS: items rendus par Cocoa, pas d'owner-draw
    procedure AttachNative(AForm: TCustomForm);
    {$ENDIF}
    function MenuCount: Integer;
    function MenuTitle(AIndex: Integer): string;
    function MenuRoot(AIndex: Integer): TMenuItem;
    procedure RefreshRecent;
  end;

implementation

const
  WRAP_COLS: array[0..10] of Integer = (40, 70, 72, 74, 76, 78, 80, 90, 100, 110, 120);

constructor TAppMenu.Create(AOwner: TComponent; AActions: TAppActions);
begin
  inherited Create(AOwner);
  FActions := AActions;
  // proprietaire = Self, pas le form: la LCL auto-assignerait Form.Menu et
  // poserait un menu natif EN PLUS de la barre dessinee
  FMenu := TMainMenu.Create(Self);
  BuildMenus;
end;

function TAppMenu.AddMenu(const ATitle: string): TMenuItem;
begin
  Result := TMenuItem.Create(FMenu);
  Result.Caption := ATitle;
  FMenu.Items.Add(Result);
end;

function TAppMenu.AddItem(AParent: TMenuItem; const ACaption: string;
  AHandler: TNotifyEvent; AShortCut: TShortCut): TMenuItem;
begin
  Result := TMenuItem.Create(FMenu);
  Result.Caption := ACaption;
  Result.OnClick := AHandler;
  Result.ShortCut := AShortCut;
  AParent.Add(Result);
end;

procedure TAppMenu.AddSep(AParent: TMenuItem);
var
  mi: TMenuItem;
begin
  mi := TMenuItem.Create(FMenu);
  mi.Caption := '-';
  AParent.Add(mi);
end;

procedure TAppMenu.BuildMenus;
var
  m, sub, sub2, sub3, mi: TMenuItem;
  A: TAppActions;
  i: Integer;

  procedure AddEncodings(AParent: TMenuItem;
    AHandler, AHexHandler: TNotifyEvent);
  var
    e: Integer;
    mi: TMenuItem; // LOCAL: sinon ecrase le 'mi' de BuildMenus -> FSaveItem faux
  begin
    for e := 0 to High(Encodings) do
    begin
      mi := AddItem(AParent, Encodings[e].Caption, AHandler);
      mi.Tag := e;
      if e = ENC_UNICODE_LAST then AddSep(AParent);
    end;
    AddSep(AParent);
    AddItem(AParent, 'Hexadecimal', AHexHandler);
  end;

begin
  A := FActions;

  // File
  m := AddMenu('File');
  AddItem(m, 'New File', @A.FileNew, ShortCut(Word('N'), [ssModifier]));
  AddItem(m, 'Open File...', @A.FileOpen, ShortCut(Word('O'), [ssModifier]));
  AddItem(m, 'Open Folder...', @A.FileOpenFolder);
  FRecentSub := AddItem(m, 'Open Recent', nil);
  FFileRoot := m;
  sub := AddItem(m, 'Reopen with Encoding', nil);
  AddEncodings(sub, @A.FileReopenWithEncoding, @A.FileReopenHex);
  AddSep(m);
  mi := AddItem(m, 'Split View', @A.ViewSplit);
  A.SetSplitItem(mi);
  AddSep(m);
  mi := AddItem(m, 'Save', @A.FileSave, ShortCut(Word('S'), [ssModifier]));
  sub := AddItem(m, 'Save with Encoding', nil);
  AddEncodings(sub, @A.FileSaveWithEncoding, @A.FileSaveHex);
  A.SetFileItems(mi, sub);
  AddItem(m, 'Save As...', @A.FileSaveAs, ShortCut(Word('S'), [ssModifier, ssShift]));
  AddItem(m, 'Save All', @A.FileSaveAll);
  AddSep(m);
  AddItem(m, 'Print...', @A.FilePrint);
  AddSep(m);
  AddItem(m, 'New Window', @A.FileNewWindow, ShortCut(Word('N'), [ssModifier, ssShift]));
  AddItem(m, 'Close Window', @A.FileCloseWindow, ShortCut(Word('W'), [ssModifier, ssShift]));
  AddItem(m, 'Close File', @A.FileClose, ShortCut(Word('W'), [ssModifier]));
  AddItem(m, 'Revert File', @A.FileRevert);
  AddItem(m, 'Close All Files', @A.FileCloseAll);
  {$IFNDEF DARWIN}
  // macOS: le Quit du menu app natif suffit
  AddSep(m);
  AddItem(m, 'Quit', @A.FileQuit, ShortCut(Word('Q'), [ssModifier]));
  {$ENDIF}

  // Edit
  m := AddMenu('Edit');
  AddItem(m, 'Undo', @A.EditUndo, ShortCut(Word('Z'), [ssModifier]));
  AddItem(m, 'Redo', @A.EditRedo, ShortCut(Word('Y'), [ssModifier]));
  AddSep(m);
  AddItem(m, 'Cut', @A.EditCut, ShortCut(Word('X'), [ssModifier]));
  AddItem(m, 'Copy', @A.EditCopy, ShortCut(Word('C'), [ssModifier]));
  AddItem(m, 'Paste', @A.EditPaste, ShortCut(Word('V'), [ssModifier]));
  AddItem(m, 'Paste and Indent', @A.EditPasteIndent, ShortCut(Word('V'), [ssModifier, ssShift]));
  mi := AddItem(m, 'Copy on Select', @A.EditCopyOnSelect);
  mi.Checked := RTCopyOnSelect;
  AddSep(m);
  sub := AddItem(m, 'Line', nil);
  AddItem(sub, 'Indent', @A.EditIndent, ShortCut(VK_OEM_6, [ssModifier]));
  AddItem(sub, 'Unindent', @A.EditUnindent, ShortCut(VK_OEM_4, [ssModifier]));
  AddItem(sub, 'Delete Line', @A.EditDeleteLine, ShortCut(Word('K'), [ssModifier, ssShift]));
  sub := AddItem(m, 'Comment', nil);
  AddItem(sub, 'Toggle Comment', @A.EditToggleComment, ShortCut(VK_OEM_2, [ssModifier]));
  sub := AddItem(m, 'Convert Case', nil);
  AddItem(sub, 'Upper Case', @A.EditUpperCase);
  AddItem(sub, 'Lower Case', @A.EditLowerCase);
  AddItem(sub, 'Title Case', @A.EditTitleCase);
  AddItem(sub, 'Swap Case', @A.EditSwapCase);
  AddItem(m, 'Convert Tabs to Spaces', @A.EditExpandTabs);
  AddSep(m);
  AddItem(m, 'Sort Lines', @A.EditSortLines, ShortCut(VK_F9, []));

  // Selection
  m := AddMenu('Selection');
  AddItem(m, 'Split into Lines', @A.SelSplitLines, ShortCut(Word('L'), [ssModifier, ssShift]));
  AddItem(m, 'Single Selection', @A.SelSingle, ShortCut(VK_ESCAPE, []));
  AddSep(m);
  AddItem(m, 'Select All', @A.SelSelectAll, ShortCut(Word('A'), [ssModifier]));
  AddItem(m, 'Expand Selection to Line', @A.SelExpandLine, ShortCut(Word('L'), [ssModifier]));
  AddItem(m, 'Expand Selection to Word', @A.SelExpandWord, ShortCut(Word('D'), [ssModifier]));
  AddItem(m, 'Expand Selection to Brackets', @A.SelExpandBrackets, ShortCut(Word('B'), [ssModifier, ssShift]));
  AddSep(m);
  AddItem(m, 'Add Previous Line', @A.SelAddPrevLine, ShortCut(VK_UP, [ssModifier, ssAlt]));
  AddItem(m, 'Add Next Line', @A.SelAddNextLine, ShortCut(VK_DOWN, [ssModifier, ssAlt]));
  AddSep(m);
  AddItem(m, 'Fill with Lorem Ipsum', @A.SelFillLorem);

  // Find
  m := AddMenu('Find');
  AddItem(m, 'Find...', @A.FindShow, ShortCut(Word('F'), [ssModifier]));
  AddItem(m, 'Find Next', @A.FindNext, ShortCut(VK_F3, []));
  AddItem(m, 'Find Previous', @A.FindPrev, ShortCut(VK_F3, [ssShift]));
  AddSep(m);
  AddItem(m, 'Replace...', @A.ReplaceShow, ShortCut(Word('H'), [ssModifier]));
  AddItem(m, 'Replace Next', @A.ReplaceNext);
  AddItem(m, 'Replace All', @A.ReplaceAll);
  AddSep(m);
  // vue hex seulement (no-op sur un doc texte)
  AddItem(m, 'Goto Offset...', @A.FindGotoOffset, ShortCut(Word('G'), [ssModifier]));

  // View
  m := AddMenu('View');
  mi := AddItem(m, 'Side Bar', @A.ViewSideBar);
  A.SetSideBarItem(mi);
  AddSep(m);
  if ThemeCount > 0 then
  begin
    sub := AddItem(m, 'Theme', nil);
    for i := 0 to ThemeCount - 1 do
    begin
      mi := AddItem(sub, ThemeName(i), @A.ViewTheme);
      mi.Tag := i;
      mi.RadioItem := True;
      mi.GroupIndex := 3;
      mi.Checked := (i = CurrentThemeIndex);
    end;
  end;
  AddItem(m, 'Font...', @A.ViewFont);
  sub := AddItem(m, 'Syntax', nil);
  mi := AddItem(sub, 'Plain Text', @A.SetSyntax); mi.Tag := 0;
  AddSep(sub);
  for i := 0 to SyntaxCount - 1 do
  begin
    mi := AddItem(sub, SyntaxDisplayName(i), @A.SetSyntax);
    mi.Tag := i + 1;
  end;
  sub := AddItem(m, 'Tab Width', nil);
  for i := 1 to 8 do
  begin
    mi := AddItem(sub, IntToStr(i), @A.ViewTabWidth);
    mi.Tag := i;
    mi.RadioItem := True;
    mi.GroupIndex := 1;
    mi.Checked := (i = RTTabWidth);
  end;
  AddSep(m);
  mi := AddItem(m, 'Word Wrap', @A.ViewWordWrap);
  mi.Checked := RTWordWrap;
  sub := AddItem(m, 'Word Wrap Column', nil);
  mi := AddItem(sub, 'Automatic', @A.ViewWrapColumn);
  mi.Tag := 0;
  mi.RadioItem := True;
  mi.GroupIndex := 2;
  mi.Checked := (RTWrapColumn = 0);
  AddSep(sub);
  for i := 0 to High(WRAP_COLS) do
  begin
    mi := AddItem(sub, IntToStr(WRAP_COLS[i]), @A.ViewWrapColumn);
    mi.Tag := WRAP_COLS[i];
    mi.RadioItem := True;
    mi.GroupIndex := 2;
    mi.Checked := (RTWrapColumn = WRAP_COLS[i]);
  end;
  mi := AddItem(m, 'Show Invisibles', @A.ViewShowInvisibles);
  mi.Checked := RTShowInvisibles;
  mi := AddItem(m, 'Map Tab to Space', @A.ViewMapTabToSpace);
  mi.Checked := RTMapTabToSpace;

  // Macro
  m := AddMenu('Macro');
  mi := AddItem(m, 'Record Macro', @A.MacroToggleRecord, ShortCut(Word('M'), [ssModifier]));
  sub := AddItem(m, 'Playback Macro', @A.MacroPlayback, ShortCut(Word('M'), [ssModifier, ssShift]));
  A.SetMacroItems(mi, sub);

  // Tools: le Tag de chaque item porte la variante (handlers ToolsXxx d'uActions)
  m := AddMenu('Tools');
  AddItem(m, 'Command Palette...', @A.ViewCommandPalette,
    ShortCut(Word('P'), [ssModifier, ssShift]));
  AddSep(m);
  sub := AddItem(m, 'Hash Selection', nil);
  mi := AddItem(sub, 'MD5', @A.ToolsTransform); mi.Tag := 10;
  mi := AddItem(sub, 'SHA-1', @A.ToolsTransform); mi.Tag := 11;
  mi := AddItem(sub, 'SHA-256', @A.ToolsTransform); mi.Tag := 12;
  mi := AddItem(sub, 'SHA-512', @A.ToolsTransform); mi.Tag := 13;
  sub := AddItem(m, 'Checksum of File...', nil);
  mi := AddItem(sub, 'SHA-256', @A.ToolsHashFile); mi.Tag := 2;
  mi := AddItem(sub, 'SHA-1', @A.ToolsHashFile); mi.Tag := 1;
  mi := AddItem(sub, 'MD5', @A.ToolsHashFile); mi.Tag := 0;
  AddItem(m, 'Insert Checksum Comment', @A.ToolsChecksumComment);
  sub := AddItem(m, 'HMAC of Selection...', nil);
  mi := AddItem(sub, 'SHA-256', @A.ToolsHMAC); mi.Tag := 2;
  mi := AddItem(sub, 'SHA-1', @A.ToolsHMAC); mi.Tag := 1;
  mi := AddItem(sub, 'SHA-512', @A.ToolsHMAC); mi.Tag := 3;
  mi := AddItem(sub, 'MD5', @A.ToolsHMAC); mi.Tag := 0;
  AddSep(m);
  sub := AddItem(m, 'Encode / Decode', nil);
  mi := AddItem(sub, 'Base64 Encode', @A.ToolsTransform); mi.Tag := 20;
  mi := AddItem(sub, 'Base64 Decode', @A.ToolsTransform); mi.Tag := 21;
  mi := AddItem(sub, 'Base64 URL Encode', @A.ToolsTransform); mi.Tag := 22;
  mi := AddItem(sub, 'Base64 URL Decode', @A.ToolsTransform); mi.Tag := 23;
  AddSep(sub);
  mi := AddItem(sub, 'URL Encode', @A.ToolsTransform); mi.Tag := 24;
  mi := AddItem(sub, 'URL Decode', @A.ToolsTransform); mi.Tag := 25;
  AddSep(sub);
  mi := AddItem(sub, 'HTML Encode', @A.ToolsTransform); mi.Tag := 26;
  mi := AddItem(sub, 'HTML Decode', @A.ToolsTransform); mi.Tag := 27;
  AddSep(sub);
  mi := AddItem(sub, 'Hex Encode', @A.ToolsTransform); mi.Tag := 28;
  mi := AddItem(sub, 'Hex Decode', @A.ToolsTransform); mi.Tag := 29;
  sub := AddItem(m, 'Escape Selection For', nil);
  mi := AddItem(sub, 'Bash', @A.ToolsTransform); mi.Tag := 30;
  mi := AddItem(sub, 'PowerShell', @A.ToolsTransform); mi.Tag := 31;
  mi := AddItem(sub, 'JSON', @A.ToolsTransform); mi.Tag := 32;
  mi := AddItem(sub, 'YAML', @A.ToolsTransform); mi.Tag := 33;
  // ANSI seulement : sur MySQL backslash-escapes le doublage de quote ne suffit pas
  mi := AddItem(sub, 'SQL (ANSI quotes)', @A.ToolsTransform); mi.Tag := 34;
  AddSep(sub);
  mi := AddItem(sub, 'sed (pattern)', @A.ToolsTransform); mi.Tag := 35;
  mi := AddItem(sub, 'sed (replacement)', @A.ToolsTransform); mi.Tag := 36;
  mi := AddItem(sub, 'Regex (literal)', @A.ToolsTransform); mi.Tag := 37;
  mi := AddItem(sub, 'systemd Exec line', @A.ToolsTransform); mi.Tag := 38;
  mi := AddItem(sub, 'nginx / Apache string', @A.ToolsTransform); mi.Tag := 39;
  sub := AddItem(m, 'Permissions', nil);
  mi := AddItem(sub, 'Convert Mode (rwx / octal)...', @A.ToolsPerms); mi.Tag := 0;
  mi := AddItem(sub, 'umask Calculator...', @A.ToolsPerms); mi.Tag := 1;
  sub := AddItem(m, 'Line Endings', nil);
  mi := AddItem(sub, 'To LF (Unix)', @A.ToolsEol); mi.Tag := 0;
  mi := AddItem(sub, 'To CRLF (Windows)', @A.ToolsEol); mi.Tag := 1;
  mi := AddItem(sub, 'To CR (legacy Mac)', @A.ToolsEol); mi.Tag := 2;
  AddSep(m);
  sub := AddItem(m, 'Generate', nil);
  mi := AddItem(sub, 'Password to Clipboard...', @A.ToolsGenPassword); mi.Tag := 0;
  mi := AddItem(sub, 'Insert Password...', @A.ToolsGenPassword); mi.Tag := 1;
  AddSep(sub);
  mi := AddItem(sub, 'UUID', @A.ToolsInsert); mi.Tag := 40;
  mi := AddItem(sub, 'Unix Timestamp', @A.ToolsInsert); mi.Tag := 41;
  mi := AddItem(sub, 'ISO 8601 (Local)', @A.ToolsInsert); mi.Tag := 42;
  mi := AddItem(sub, 'ISO 8601 (UTC)', @A.ToolsInsert); mi.Tag := 43;
  AddSep(sub);
  mi := AddItem(sub, 'Token (Hex, 32 bytes)', @A.ToolsInsert); mi.Tag := 50;
  mi := AddItem(sub, 'Token (Base64, 32 bytes)', @A.ToolsInsert); mi.Tag := 51;
  mi := AddItem(sub, 'Token (base64url, 32 bytes)', @A.ToolsInsert); mi.Tag := 52;
  mi := AddItem(sub, 'API Key...', @A.ToolsInsert); mi.Tag := 53;
  AddSep(sub);
  sub2 := AddItem(sub, '.htpasswd Entry...', nil);
  mi := AddItem(sub2, 'bcrypt (recommended)', @A.ToolsHtpasswd); mi.Tag := 0;
  mi := AddItem(sub2, 'MD5 (apr1)', @A.ToolsHtpasswd); mi.Tag := 1;
  mi := AddItem(sub2, 'SHA-1 (compatibility)', @A.ToolsHtpasswd); mi.Tag := 2;
  sub2 := AddItem(sub, 'LDAP', nil);
  // Tag = TLdapPwScheme (uLdap); SASL = une identite, pas un hash
  sub3 := AddItem(sub2, 'userPassword...', nil);
  mi := AddItem(sub3, 'SSHA (recommended)', @A.ToolsLdapPassword); mi.Tag := 0;
  mi := AddItem(sub3, 'SSHA-256', @A.ToolsLdapPassword); mi.Tag := 1;
  mi := AddItem(sub3, 'SSHA-512', @A.ToolsLdapPassword); mi.Tag := 2;
  AddSep(sub3);
  mi := AddItem(sub3, 'CRYPT (bcrypt)', @A.ToolsLdapPassword); mi.Tag := 6;
  // pw-argon2 : le cout suit la bibliotheque avec laquelle slapd est compile
  mi := AddItem(sub3, 'ARGON2 (slapd + libargon2: t=5, m=7168 KiB)', @A.ToolsLdapPassword); mi.Tag := 8;
  mi := AddItem(sub3, 'ARGON2 (slapd + libsodium: t=2, m=64 MiB)', @A.ToolsLdapPassword); mi.Tag := 9;
  mi := AddItem(sub3, 'SHA (unsalted)', @A.ToolsLdapPassword); mi.Tag := 3;
  mi := AddItem(sub3, 'SMD5', @A.ToolsLdapPassword); mi.Tag := 4;
  mi := AddItem(sub3, 'MD5 (unsalted)', @A.ToolsLdapPassword); mi.Tag := 5;
  AddSep(sub3);
  mi := AddItem(sub3, 'SASL (passthrough)', @A.ToolsLdapPassword); mi.Tag := 7;
  AddSep(sub2);
  AddItem(sub2, 'LDIF: Root (domain)...', @A.ToolsLdifRoot);
  AddItem(sub2, 'LDIF: Organizational Unit...', @A.ToolsLdifOU);
  AddItem(sub2, 'LDIF: Person / Account...', @A.ToolsLdifEntry);
  AddItem(sub2, 'LDIF: Group (posixGroup)...', @A.ToolsLdifGroup);
  AddItem(sub2, 'LDIF: Group (groupOfNames)...', @A.ToolsLdifGroupOfNames);
  AddItem(sub2, 'LDIF: Service / Bind Account...', @A.ToolsLdifService);
  // Tag = TProtoKind (uProto)
  sub2 := AddItem(sub, 'Protocol', nil);
  mi := AddItem(sub2, 'HTTP...', @A.ToolsHttp); mi.Tag := 0;
  mi := AddItem(sub2, 'HTTPS...', @A.ToolsHttp); mi.Tag := 1;
  AddSep(sub2);
  mi := AddItem(sub2, 'SMTP', @A.ToolsProtocol); mi.Tag := 2;
  mi := AddItem(sub2, 'SMTP (STARTTLS)', @A.ToolsProtocol); mi.Tag := 3;
  mi := AddItem(sub2, 'SMTPS (TLS)', @A.ToolsProtocol); mi.Tag := 4;
  AddSep(sub2);
  mi := AddItem(sub2, 'POP3', @A.ToolsProtocol); mi.Tag := 5;
  mi := AddItem(sub2, 'POP3S (TLS)', @A.ToolsProtocol); mi.Tag := 6;
  mi := AddItem(sub2, 'IMAP', @A.ToolsProtocol); mi.Tag := 7;
  mi := AddItem(sub2, 'IMAPS (TLS)', @A.ToolsProtocol); mi.Tag := 8;
  AddSep(sub2);
  mi := AddItem(sub2, 'FTP', @A.ToolsProtocol); mi.Tag := 9;
  mi := AddItem(sub2, 'FTPS (AUTH TLS)', @A.ToolsProtocol); mi.Tag := 10;
  mi := AddItem(sub2, 'Redis', @A.ToolsProtocol); mi.Tag := 11;
  AddSep(sub2);
  mi := AddItem(sub2, 'NNTP', @A.ToolsProtocol); mi.Tag := 18;
  mi := AddItem(sub2, 'WHOIS', @A.ToolsProtocol); mi.Tag := 19;
  mi := AddItem(sub2, 'IRC', @A.ToolsProtocol); mi.Tag := 20;
  mi := AddItem(sub2, 'Memcached', @A.ToolsProtocol); mi.Tag := 21;
  mi := AddItem(sub2, 'SIP (OPTIONS ping)', @A.ToolsProtocol); mi.Tag := 22;
  mi := AddItem(sub2, 'Graphite / Carbon', @A.ToolsProtocol); mi.Tag := 23;
  mi := AddItem(sub2, 'Beanstalkd', @A.ToolsProtocol); mi.Tag := 24;
  AddSep(sub2);
  mi := AddItem(sub2, 'LDAP (ldapsearch)', @A.ToolsProtocol); mi.Tag := 12;
  mi := AddItem(sub2, 'MySQL (mysql client)', @A.ToolsProtocol); mi.Tag := 13;
  mi := AddItem(sub2, 'PostgreSQL (psql)', @A.ToolsProtocol); mi.Tag := 14;
  AddSep(sub2);
  mi := AddItem(sub2, 'PHP-FPM (FastCGI)', @A.ToolsProtocol); mi.Tag := 15;
  mi := AddItem(sub2, 'Traefik API (curl)', @A.ToolsProtocol); mi.Tag := 16;
  mi := AddItem(sub2, 'Docker Engine API (curl)', @A.ToolsProtocol); mi.Tag := 17;
  mi := AddItem(sub2, 'Kubernetes API (curl)', @A.ToolsProtocol); mi.Tag := 25;
  sub := AddItem(m, 'JSON', nil);
  mi := AddItem(sub, 'Validate', @A.ToolsJson); mi.Tag := 0;
  mi := AddItem(sub, 'Format', @A.ToolsJson); mi.Tag := 1;
  mi := AddItem(sub, 'Minify', @A.ToolsJson); mi.Tag := 2;
  mi := AddItem(sub, 'Sort Keys', @A.ToolsJson); mi.Tag := 3;
  sub := AddItem(m, 'XML', nil);
  mi := AddItem(sub, 'Validate', @A.ToolsXml); mi.Tag := 0;
  mi := AddItem(sub, 'Format', @A.ToolsXml); mi.Tag := 1;
  sub := AddItem(m, 'YAML', nil);
  mi := AddItem(sub, 'Validate', @A.ToolsYaml); mi.Tag := 0;
  mi := AddItem(sub, 'Flatten to Dotted Paths', @A.ToolsYaml); mi.Tag := 1;
  mi := AddItem(sub, 'Sort Keys...', @A.ToolsYaml); mi.Tag := 2;
  AddItem(sub, 'Values Diff vs File...', @A.ToolsYamlDiff);
  sub := AddItem(m, 'INI', nil);
  mi := AddItem(sub, 'Validate', @A.ToolsIni); mi.Tag := 0;
  mi := AddItem(sub, 'Sort Keys', @A.ToolsIni); mi.Tag := 1;
  mi := AddItem(sub, 'Find Duplicate Keys', @A.ToolsIni); mi.Tag := 2;
  sub := AddItem(m, 'TOML', nil);
  mi := AddItem(sub, 'Validate', @A.ToolsToml); mi.Tag := 0;
  mi := AddItem(sub, 'Sort Keys', @A.ToolsToml); mi.Tag := 1;
  mi := AddItem(sub, 'Find Duplicate Keys', @A.ToolsToml); mi.Tag := 2;
  sub := AddItem(m, 'Kubernetes', nil);
  mi := AddItem(sub, 'Secret from key=value...', @A.ToolsKube); mi.Tag := 0;
  mi := AddItem(sub, 'Decode Secret', @A.ToolsKube); mi.Tag := 1;
  mi := AddItem(sub, 'ConfigMap from key=value...', @A.ToolsKube); mi.Tag := 2;
  mi := AddItem(sub, 'Decode ConfigMap', @A.ToolsKube); mi.Tag := 3;
  sub := AddItem(m, '.env', nil);
  mi := AddItem(sub, 'Sort Keys', @A.ToolsEnv); mi.Tag := 0;
  mi := AddItem(sub, 'Find Duplicate Keys', @A.ToolsEnv); mi.Tag := 1;
  mi := AddItem(sub, 'Redact Secrets', @A.ToolsEnv); mi.Tag := 2;
  mi := AddItem(sub, 'Quote Values', @A.ToolsEnv); mi.Tag := 5;
  mi := AddItem(sub, 'Unquote Values', @A.ToolsEnv); mi.Tag := 6;
  AddSep(sub);
  mi := AddItem(sub, 'To JSON', @A.ToolsEnv); mi.Tag := 3;
  mi := AddItem(sub, 'From JSON', @A.ToolsEnv); mi.Tag := 4;
  mi := AddItem(sub, 'To YAML', @A.ToolsEnv); mi.Tag := 7;
  mi := AddItem(sub, 'From YAML', @A.ToolsEnv); mi.Tag := 8;
  sub := AddItem(m, 'Docker / Compose', nil);
  mi := AddItem(sub, 'List Images', @A.ToolsCompose); mi.Tag := 0;
  mi := AddItem(sub, 'Environment to .env', @A.ToolsCompose); mi.Tag := 1;
  mi := AddItem(sub, 'Set Image Tag...', @A.ToolsCompose); mi.Tag := 2;
  sub := AddItem(m, 'Podman Quadlet', nil);
  mi := AddItem(sub, 'List Image', @A.ToolsQuadlet); mi.Tag := 0;
  mi := AddItem(sub, 'Environment to .env', @A.ToolsQuadlet); mi.Tag := 1;
  mi := AddItem(sub, 'Set Image Tag...', @A.ToolsQuadlet); mi.Tag := 2;
  sub := AddItem(m, 'Terraform', nil);
  mi := AddItem(sub, 'List Variables', @A.ToolsTerraform); mi.Tag := 0;
  mi := AddItem(sub, 'tfvars Skeleton', @A.ToolsTerraform); mi.Tag := 1;
  mi := AddItem(sub, 'Find Duplicate Variables', @A.ToolsTerraform); mi.Tag := 2;
  sub := AddItem(m, 'Helm', nil);
  mi := AddItem(sub, 'Values Skeleton from Template', @A.ToolsHelm); mi.Tag := 0;
  mi := AddItem(sub, 'Values Skeleton from Folder...', @A.ToolsHelmFolder); mi.Tag := 0;
  mi := AddItem(sub, 'Values Path at Cursor', @A.ToolsHelm); mi.Tag := 1;
  AddItem(sub, 'Find Missing / Unused Values...', @A.ToolsHelmIssues);
  mi := AddItem(sub, 'Find Missing / Unused (Folder)...', @A.ToolsHelmFolder); mi.Tag := 1;
  AddItem(sub, 'Wrap Value in quote', @A.ToolsHelmQuote);
  AddItem(sub, 'Value to toYaml | nindent...', @A.ToolsHelmToYaml);
  sub2 := AddItem(sub, 'Insert Snippet', nil);
  mi := AddItem(sub2, 'If .Values.enabled', @A.ToolsHelmSnippet); mi.Tag := 0;
  mi := AddItem(sub2, 'With .Values.section', @A.ToolsHelmSnippet); mi.Tag := 1;
  mi := AddItem(sub2, 'Range .Values.items', @A.ToolsHelmSnippet); mi.Tag := 2;
  mi := AddItem(sub2, 'Include (fullname)', @A.ToolsHelmSnippet); mi.Tag := 3;
  mi := AddItem(sub2, 'Common Labels', @A.ToolsHelmSnippet); mi.Tag := 4;
  mi := AddItem(sub2, 'Selector Labels', @A.ToolsHelmSnippet); mi.Tag := 5;
  mi := AddItem(sub2, 'Resources (toYaml)', @A.ToolsHelmSnippet); mi.Tag := 6;
  AddSep(m);
  AddItem(m, 'IP / CIDR Calculator...', @A.ToolsIpCalc);
  AddItem(m, 'nmap Command Builder...', @A.ToolsNmap);
  AddItem(m, 'Timestamp Converter...', @A.ToolsTimestamp);
  AddItem(m, 'Cron / Timer Explainer...', @A.ToolsCron);
  AddItem(m, 'JWT Inspector...', @A.ToolsJwt);
  AddItem(m, 'Mail Trace', @A.ToolsMailTrace);
  sub := AddItem(m, 'X.509 Certificate', nil);
  mi := AddItem(sub, 'Inspect Buffer / Selection', @A.ToolsX509); mi.Tag := 0;
  mi := AddItem(sub, 'Inspect File...', @A.ToolsX509); mi.Tag := 1;
  sub := AddItem(m, 'Extract / Count', nil);
  mi := AddItem(sub, 'IPv4 Addresses', @A.ToolsExtract); mi.Tag := 0;
  mi := AddItem(sub, 'URLs', @A.ToolsExtract); mi.Tag := 1;
  mi := AddItem(sub, 'Email Addresses', @A.ToolsExtract); mi.Tag := 2;
  mi := AddItem(sub, 'UUIDs', @A.ToolsExtract); mi.Tag := 3;
  mi := AddItem(sub, 'Hashes (hex)', @A.ToolsExtract); mi.Tag := 4;
  mi := AddItem(sub, 'Hostnames', @A.ToolsExtract); mi.Tag := 5;
  AddSep(sub);
  mi := AddItem(sub, 'All of the Above', @A.ToolsExtract); mi.Tag := 9;
  sub := AddItem(m, 'Log', nil);
  mi := AddItem(sub, 'Normalize Timestamps', @A.ToolsLog); mi.Tag := 0;
  mi := AddItem(sub, 'Sort by Timestamp', @A.ToolsLog); mi.Tag := 1;
  mi := AddItem(sub, 'Merge with File...', @A.ToolsLog); mi.Tag := 2;
  mi := AddItem(sub, 'Deltas Between Timestamps', @A.ToolsLog); mi.Tag := 3;
  mi := AddItem(sub, 'Summary (Top Errors / IPs / Status)', @A.ToolsLog); mi.Tag := 4;
  AddItem(m, 'Diff vs File...', @A.ToolsDiff);

  // Help
  m := AddMenu('Help');
  AddItem(m, 'About RottenText', @A.HelpAbout);
end;

// MRU relue du disque a chaque popup: les autres fenetres sont des process
// separes.
procedure TAppMenu.RefreshRecent;
var
  i: Integer;
  mi: TMenuItem;
begin
  if FRecentSub = nil then Exit;
  FRecentSub.Clear;
  RecentReload;
  for i := 0 to RecentCount - 1 do
  begin
    // libelle assaini; l'ouverture repart du chemin brut
    mi := AddItem(FRecentSub, RecentDisplay(i), @FActions.FileOpenRecent);
    mi.Tag := i;
  end;
  if RecentCount > 0 then AddSep(FRecentSub);
  mi := AddItem(FRecentSub, 'Clear Items', @FActions.FileClearRecent);
  mi.Enabled := RecentCount > 0;
  // items neufs = sans handler de dessin (la palette passe ici hors popup)
  if FBar <> nil then ThemeMenuItems(FRecentSub);
end;

procedure TAppMenu.FileMenuPopup(Sender: TObject);
begin
  RefreshRecent;
end;

procedure TAppMenu.AttachBar(ABar: TRSMenuBar);
begin
  // la barre rejoue le OnClick de la racine a chaque ouverture de son popup
  FFileRoot.OnClick := @FileMenuPopup;
  ABar.AdoptMainMenu(FMenu);
  FBar := ABar;
end;

{$IFDEF DARWIN}
// Esc grabberait la fermeture de la find bar, et Cmd+H appartient a macOS
// (Hide): le remplacer passe par Cmd+Alt+F. Jusqu'a Lazarus 4.4 le menu natif
// consomme ses equivalents clavier AVANT le KeyDown LCL; en 4.8 l'ordre
// s'inverse, uMain exclut donc aussi Cmd+H de son KeyDown sur mac.
procedure DarwinFixShortcuts(AItem: TMenuItem);
var
  i: Integer;
begin
  for i := 0 to AItem.Count - 1 do
    DarwinFixShortcuts(AItem.Items[i]);
  if AItem.ShortCut = ShortCut(VK_ESCAPE, []) then
    AItem.ShortCut := 0
  else if AItem.ShortCut = ShortCut(Word('H'), [ssModifier]) then
    AItem.ShortCut := ShortCut(Word('F'), [ssModifier, ssAlt]);
end;

procedure TAppMenu.AttachNative(AForm: TCustomForm);
begin
  DarwinFixShortcuts(FMenu.Items);
  // pas de OnPopup en natif (Cocoa fire le OnClick du parent), et un parent SANS
  // enfant n'a pas de NSMenu: il faut le peupler une premiere fois ici.
  FRecentSub.OnClick := @FileMenuPopup;
  RefreshRecent;
  AForm.Menu := FMenu;
end;
{$ENDIF}

function TAppMenu.MenuCount: Integer;
begin
  Result := FMenu.Items.Count;
end;

function TAppMenu.MenuTitle(AIndex: Integer): string;
begin
  Result := FMenu.Items[AIndex].Caption;
end;

function TAppMenu.MenuRoot(AIndex: Integer): TMenuItem;
begin
  // adopte: la racine du TMainMenu est vide, ses items sont dans la barre
  if FBar <> nil then
    Result := FBar.MenuRoot(AIndex)
  else
    Result := FMenu.Items[AIndex];
end;

end.
