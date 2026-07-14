unit uHighlight;

{$mode objfpc}{$H+}

// Coloration via grammaires TextMate (.tmLanguage JSON, TSynTextMateSyn).
// Une grammaire est une entree NON FIABLE (regex arbitraires = ReDoS, JSON
// malforme = crash): on ne charge que celles de syntax/, sous try/except et
// sous plafond de taille. Des grammaires utilisateur seraient a traiter comme
// hostiles.

interface

uses
  Classes, SysUtils, SynEditHighlighter;

function SyntaxCount: Integer;
function SyntaxDisplayName(AIndex: Integer): string;
function HighlighterByIndex(AIndex: Integer): TSynCustomHighlighter;
function HighlighterForFile(const AFileName: string): TSynCustomHighlighter;
function IndexForFile(const AFileName: string): Integer; // -1 si aucune
function IndexForName(const AName: string): Integer;    // -1 si nom inconnu
function LanguageLabel(AHl: TSynCustomHighlighter): string; // 'Plain Text' si nil
// False si le langage n'a pas de commentaires (Diff, Log, Plain Text)
function CommentTokensFor(AHl: TSynCustomHighlighter; out ALine, AOpen, AClose: string): Boolean;
// changement de theme a chaud
procedure ReapplyScopeTheme;

implementation

uses
  Graphics, SynTextMateSyn, uTheme;

const
  MAX_GRAMMAR_BYTES = 2 * 1024 * 1024; // plafond anti-bombe JSON

type
  TSynDef = record
    Display: string;
    Grammar: string; // nom de fichier dans syntax/
    Exts: string;    // ';.pas;.pp;' (bornes par ; pour matcher tout entier)
    Names: string;   // fichiers sans extension (';makefile;'), en minuscules
    LineC: string;   // commentaire de ligne ('' = aucun)
    BlockO, BlockC: string;
    Hl: TSynCustomHighlighter;
    Tried: Boolean;  // charge une seule fois, succes ou echec
  end;

var
  Defs: array of TSynDef;
  SyntaxDir: string;

procedure AddDef(const ADisplay, AGrammar, AExts: string; const ANames: string = '';
  const ALineC: string = ''; const ABlockO: string = ''; const ABlockC: string = '');
begin
  SetLength(Defs, Length(Defs) + 1);
  Defs[High(Defs)].Display := ADisplay;
  Defs[High(Defs)].Grammar := AGrammar;
  Defs[High(Defs)].Exts := ';' + LowerCase(AExts) + ';';
  if ANames <> '' then
    Defs[High(Defs)].Names := ';' + LowerCase(ANames) + ';';
  Defs[High(Defs)].LineC := ALineC;
  Defs[High(Defs)].BlockO := ABlockO;
  Defs[High(Defs)].BlockC := ABlockC;
  Defs[High(Defs)].Hl := nil;
  Defs[High(Defs)].Tried := False;
end;

function ReadCapped(const AFull: string; out AData: string): Boolean;
var
  fs: TFileStream;
begin
  Result := False;
  AData := '';
  try
    fs := TFileStream.Create(AFull, fmOpenRead or fmShareDenyWrite);
    try
      if (fs.Size <= 0) or (fs.Size > MAX_GRAMMAR_BYTES) then Exit;
      SetLength(AData, fs.Size);
      fs.ReadBuffer(AData[1], fs.Size);
      Result := True;
    finally
      fs.Free;
    end;
  except
    Result := False;
    AData := '';
  end;
end;

// callback d'IO du highlighter, "include" compris: ExtractFileName neutralise
// le path traversal, tout est cherche dans syntax/
procedure GuardedLoadGrammarFile(AGrammarFile, AGrammarPath: String; out AGrammarDef: String);
begin
  AGrammarDef := '';
  if (AGrammarFile = '') or (Pos('..', AGrammarFile) > 0) then Exit;
  ReadCapped(SyntaxDir + ExtractFileName(AGrammarFile), AGrammarDef);
end;

// scope TextMate: le plus specifique gagne, d'ou l'ordre du ladder plus bas
function ScopeIs(const AScope, APrefix: string): Boolean;
begin
  Result := (AScope = APrefix) or
    ((Length(AScope) > Length(APrefix)) and
     (Copy(AScope, 1, Length(APrefix) + 1) = APrefix + '.'));
end;

procedure StyleForScope(const AScope: string; out AFg: TColor; out AItalic, AHas: Boolean);
begin
  AFg := clNone;
  AItalic := False;
  AHas := True;
  if ScopeIs(AScope, 'comment') then begin AFg := clCodeComment; AItalic := True; end
  else if ScopeIs(AScope, 'string') then AFg := clCodeString
  else if ScopeIs(AScope, 'constant.numeric') then AFg := clCodeNumber
  else if ScopeIs(AScope, 'constant') then AFg := clCodeConstant
  else if ScopeIs(AScope, 'keyword.operator') then AFg := clCodeOperator
  else if ScopeIs(AScope, 'keyword') then AFg := clCodeKeyword
  else if ScopeIs(AScope, 'storage.type') then AFg := clCodeType
  else if ScopeIs(AScope, 'storage') then AFg := clCodeKeyword
  else if ScopeIs(AScope, 'entity.name.function') or ScopeIs(AScope, 'support.function') then AFg := clCodeFunction
  else if ScopeIs(AScope, 'entity.name.type') or ScopeIs(AScope, 'entity.name.class')
       or ScopeIs(AScope, 'support.type') or ScopeIs(AScope, 'support.class') then AFg := clCodeType
  else if ScopeIs(AScope, 'entity.name.tag') then AFg := clCodeKeyword
  else if ScopeIs(AScope, 'variable') then AFg := clCodeVariable
  else if ScopeIs(AScope, 'invalid') then AFg := clCodeInvalid
  else AHas := False;
end;

procedure ApplyScopeTheme(AHl: TSynCustomHighlighter);
var
  i: Integer;
  attr: TSynHighlighterAttributes;
  fg: TColor;
  ital, has: Boolean;
begin
  for i := 0 to AHl.AttrCount - 1 do
  begin
    attr := AHl.Attribute[i];
    if attr = nil then Continue;
    StyleForScope(attr.StoredName, fg, ital, has);
    if has then
    begin
      attr.Foreground := fg;
      if ital then attr.Style := attr.Style + [fsItalic];
    end;
  end;
end;

function SafeLoad(const AGrammar: string): TSynCustomHighlighter;
var
  hl: TSynTextMateSyn;
begin
  Result := nil;
  // le nom vient de nous, le contenu non
  if (AGrammar = '') or (Pos('..', AGrammar) > 0) or (Pos('/', AGrammar) > 0)
     or (Pos('\', AGrammar) > 0) then Exit;
  if not FileExists(SyntaxDir + AGrammar) then Exit;
  hl := TSynTextMateSyn.Create(nil);
  try
    hl.OnLoadGrammarFile := @GuardedLoadGrammarFile;
    hl.LoadGrammar(AGrammar, SyntaxDir); // IO routee via le callback garde
    if hl.ParserError <> '' then
      raise Exception.Create('grammar parse error: ' + hl.ParserError);
    ApplyScopeTheme(hl);
    Result := hl;
  except
    // grammaire cassee: repli en Plain Text, jamais de crash
    FreeAndNil(hl);
    Result := nil;
  end;
end;

function SyntaxCount: Integer;
begin
  Result := Length(Defs);
end;

function SyntaxDisplayName(AIndex: Integer): string;
begin
  if (AIndex >= 0) and (AIndex < Length(Defs)) then
    Result := Defs[AIndex].Display
  else
    Result := '';
end;

function HighlighterByIndex(AIndex: Integer): TSynCustomHighlighter;
begin
  Result := nil;
  if (AIndex < 0) or (AIndex >= Length(Defs)) then Exit;
  if not Defs[AIndex].Tried then
  begin
    Defs[AIndex].Hl := SafeLoad(Defs[AIndex].Grammar);
    Defs[AIndex].Tried := True;
  end;
  Result := Defs[AIndex].Hl;
end;

function IndexForFile(const AFileName: string): Integer;
var
  i: Integer;
  e, n: string;
begin
  Result := -1;
  // nom complet d'abord: sans-extension (Makefile) et noms a points que
  // l'extension ne discrimine pas (Makefile.in, configure.in)
  n := LowerCase(ExtractFileName(AFileName));
  if n <> '' then
    for i := 0 to High(Defs) do
      if (Defs[i].Names <> '') and (Pos(';' + n + ';', Defs[i].Names) > 0) then
        Exit(i);
  e := LowerCase(ExtractFileExt(AFileName));
  // dotfile: ExtractFileExt rend '' (le point est en tete), le nom entier fait
  // donc office d'extension
  if (e = '') and (n <> '') and (n[1] = '.') then e := n;
  if e = '' then Exit;
  for i := 0 to High(Defs) do
    if Pos(';' + e + ';', Defs[i].Exts) > 0 then
      Exit(i);
end;

function HighlighterForFile(const AFileName: string): TSynCustomHighlighter;
var
  idx: Integer;
begin
  idx := IndexForFile(AFileName);
  if idx < 0 then Result := nil
  else Result := HighlighterByIndex(idx);
end;

function IndexForName(const AName: string): Integer;
var
  i: Integer;
begin
  Result := -1;
  for i := 0 to High(Defs) do
    if SameText(Defs[i].Display, AName) then Exit(i);
end;

function LanguageLabel(AHl: TSynCustomHighlighter): string;
var
  i: Integer;
begin
  Result := 'Plain Text';
  if AHl = nil then Exit;
  for i := 0 to High(Defs) do
    if Defs[i].Hl = AHl then
      Exit(Defs[i].Display);
end;

function CommentTokensFor(AHl: TSynCustomHighlighter; out ALine, AOpen, AClose: string): Boolean;
var
  i: Integer;
begin
  ALine := '';
  AOpen := '';
  AClose := '';
  Result := False;
  if AHl = nil then Exit;
  for i := 0 to High(Defs) do
    if Defs[i].Hl = AHl then
    begin
      ALine := Defs[i].LineC;
      AOpen := Defs[i].BlockO;
      AClose := Defs[i].BlockC;
      Exit((ALine <> '') or (AOpen <> ''));
    end;
end;

procedure ReapplyScopeTheme;
var
  i: Integer;
begin
  for i := 0 to High(Defs) do
    if Defs[i].Hl <> nil then
      ApplyScopeTheme(Defs[i].Hl);
end;

procedure FreeDefs;
var
  i: Integer;
begin
  for i := 0 to High(Defs) do
    Defs[i].Hl.Free;
end;

initialization
  SyntaxDir := IncludeTrailingPathDelimiter(
    IncludeTrailingPathDelimiter(ExtractFilePath(ParamStr(0))) + 'syntax');
  // ordre = menu View > Syntax et priorite de detection (1er match d'extension)
  AddDef('Assembly (6502)', 'asm-6502.tmLanguage.json', '.a65;.s65;.asm65', '', ';');
  AddDef('Assembly (68000)', 'asm-m68k.tmLanguage.json', '.x68;.s68;.68k', '', ';');
  AddDef('Assembly (ARM64)', 'asm-arm64.tmLanguage.json', '.s', '', '//');
  AddDef('Assembly (x86-64)', 'asm-x86_64.tmLanguage.json', '.asm;.nasm', '', ';');
  AddDef('BASIC', 'basic.tmLanguage.json', '.bas;.bi;.bm', '', '''');
  AddDef('Autoconf', 'autoconf.tmLanguage.json', '.ac;.m4', 'configure.ac;configure.in;aclocal.m4', '#');
  AddDef('Bash', 'bash.tmLanguage.json', '.sh;.bash;.zsh;.bashrc;.zshrc;.profile', 'profile;configure;config.status', '#');
  AddDef('Batch', 'batch.tmLanguage.json', '.bat;.cmd', '', 'REM');
  AddDef('C', 'c.tmLanguage.json', '.c;.h', '', '//', '/*', '*/');
  AddDef('C#', 'csharp.tmLanguage.json', '.cs', '', '//', '/*', '*/');
  AddDef('C++', 'cpp.tmLanguage.json', '.cpp;.hpp;.cc;.cxx;.hh;.hxx', '', '//', '/*', '*/');
  AddDef('Cisco IOS', 'cisco.tmLanguage.json', '.ios;.cisco', '', '!');
  AddDef('Conf', 'conf.tmLanguage.json', '.conf;.cnf;.cf;.htaccess;.properties', '', '#');
  AddDef('CSS', 'css.tmLanguage.json', '.css', '', '', '/*', '*/');
  AddDef('Diff', 'diff.tmLanguage.json', '.diff;.patch');
  AddDef('Dockerfile', 'dockerfile.tmLanguage.json', '.dockerfile', 'dockerfile;containerfile', '#');
  AddDef('Go', 'go.tmLanguage.json', '.go', '', '//', '/*', '*/');
  AddDef('HTML', 'html.tmLanguage.json', '.html;.htm', '', '', '<!--', '-->');
  AddDef('INI', 'ini.tmLanguage.json', '.ini;.cfg;.inf;.reg;.editorconfig;.gitconfig', '', ';');
  AddDef('JavaScript', 'javascript.tmLanguage.json', '.js;.mjs;.cjs', '', '//', '/*', '*/');
  AddDef('JSON', 'json.tmLanguage.json', '.json', '', '//', '/*', '*/');
  AddDef('Juniper Junos', 'junos.tmLanguage.json', '.junos', '', '#', '/*', '*/');
  AddDef('LaTeX', 'latex.tmLanguage.json', '.tex;.sty;.cls;.bib', '', '%');
  AddDef('LDIF', 'ldif.tmLanguage.json', '.ldif', '', '#');
  AddDef('Log', 'log.tmLanguage.json', '.log', 'syslog;messages');
  AddDef('Logo', 'logo.tmLanguage.json', '.logo;.glg', '', ';');
  AddDef('Makefile', 'makefile.tmLanguage.json', '.mk;.mak;.make;.am', 'makefile;gnumakefile;makefile.am;makefile.in;gnumakefile.am;makefile.inc', '#');
  AddDef('Markdown', 'markdown.tmLanguage.json', '.md;.markdown', '', '', '<!--', '-->');
  AddDef('Pascal', 'pascal.tmLanguage.json', '.pas;.pp;.lpr;.dpr;.inc;.lfm;.dfm', '', '//', '{', '}');
  AddDef('Perl', 'perl.tmLanguage.json', '.pl;.pm;.t', '', '#');
  AddDef('PHP', 'php.tmLanguage.json', '.php;.php3;.php4;.php5;.phtml', '', '//', '/*', '*/');
  AddDef('PowerShell', 'powershell.tmLanguage.json', '.ps1;.psm1;.psd1', '', '#', '<#', '#>');
  AddDef('Python', 'python.tmLanguage.json', '.py;.pyw;.pyi', '', '#');
  AddDef('Ruby', 'ruby.tmLanguage.json', '.rb;.rake;.gemspec;.ru',
    'vagrantfile;rakefile;gemfile;guardfile;berksfile', '#');
  AddDef('Rust', 'rust.tmLanguage.json', '.rs', '', '//', '/*', '*/');
  AddDef('SQL', 'sql.tmLanguage.json', '.sql', '', '--', '/*', '*/');
  AddDef('TOML', 'toml.tmLanguage.json', '.toml', '', '#');
  AddDef('TypeScript', 'typescript.tmLanguage.json', '.ts;.tsx;.mts;.cts', '', '//', '/*', '*/');
  AddDef('XML', 'xml.tmLanguage.json', '.xml;.xsd;.xsl;.xslt;.svg;.plist;.lpi;.lpk;.csproj;.wsdl;.rss;.atom',
    '', '', '<!--', '-->');
  AddDef('YAML', 'yaml.tmLanguage.json', '.yml;.yaml', '', '#');

finalization
  FreeDefs; // highlighters crees avec Owner=nil

end.
