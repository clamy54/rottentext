; Installeur Windows pour RottenText (Inno Setup 6).
; Prerequis : avoir compile l'executable avec scripts\build.ps1 -Release
; (l'exe attendu est RottenText.exe a la racine du depot).
; Compilation de l'installeur : ISCC.exe rottentext.iss  (ou via l'IDE Inno Setup).
;
; AppVersion est extrait de RT_VERSION (src\uMain.pas) a la compilation :
; make-version.ps1 genere version.iss (meme mecanisme que make-notices.ps1).
; RT_VERSION introuvable = erreur de compilation, jamais de version par defaut.

#define AppName "RottenText"
#define AppPublisher "Cyril Lamy"
#define AppExe "RottenText.exe"

#define VerRC Exec("powershell.exe", "-NoProfile -ExecutionPolicy Bypass -File """ + SourcePath + "\make-version.ps1""", SourcePath, 1, 0)
#if VerRC != 0
  #error make-version.ps1 a echoue: version non extraite de src\uMain.pas
#endif
#include "version.iss"

; third-party.txt = LICENSE_THIRD_PARTIES.md rendu en texte lisible (Inno
; afficherait le markdown tel quel: #, ** et | des tableaux). Regenere ICI, a
; chaque compilation, pour qu'il ne puisse pas deriver de sa source.
#define NoticesRC Exec("powershell.exe", "-NoProfile -ExecutionPolicy Bypass -File """ + SourcePath + "\make-notices.ps1""", SourcePath, 1, 0)
#if NoticesRC != 0
  #error make-notices.ps1 a echoue: page des licences tierces non regeneree
#endif

[Setup]
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher={#AppPublisher}
AppSupportURL=https://github.com/clamy54/rottentext
DefaultDirName={autopf}\RottenText
DefaultGroupName=RottenText
DisableProgramGroupPage=yes
; install machine (admin) ou utilisateur : l'utilisateur choisit. Permet aussi
; une install sans elevation (ISCC ... /CURRENTUSER), ce qui sert aux tests.
PrivilegesRequired=admin
PrivilegesRequiredOverridesAllowed=dialog commandline
UninstallDisplayIcon={app}\{#AppExe}
; page d'acceptation = la GPL-2, la licence de RottenText lui-meme
LicenseFile=..\..\LICENSE
; page d'info juste apres: l'inventaire des oeuvres tierces embarquees (polices
; Monaspace compilees DANS l'exe, LCL/FPC, SynEdit). L'afficher n'est pas une
; obligation -- les licences doivent ACCOMPAGNER la distribution, ce que fait
; [Files] -- mais autant que l'utilisateur voie ce qu'il installe.
InfoBeforeFile=third-party.txt
OutputDir=output
OutputBaseFilename=RottenText-Setup-{#AppVersion}
SetupIconFile=..\..\RottenText.ico
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ArchitecturesInstallIn64BitMode=x64compatible

[Languages]
Name: "fr"; MessagesFile: "compiler:Languages\French.isl"
Name: "en"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"
Name: "contextmenu"; Description: "Add to Explorer context menu"; GroupDescription: "Shell integration:"

[Files]
Source: "..\..\RottenText.exe"; DestDir: "{app}"; Flags: ignoreversion
; donnees runtime : les loaders les cherchent A COTE de l'exe
; (ExtractFilePath(ParamStr(0)) + 'syntax' / 'themes'), pas ailleurs.
Source: "..\..\syntax\*"; DestDir: "{app}\syntax"; Flags: recursesubdirs createallsubdirs
Source: "..\..\themes\*"; DestDir: "{app}\themes"; Flags: recursesubdirs createallsubdirs
Source: "..\..\RottenText.ico"; DestDir: "{app}"
; licences : les polices Monaspace sont COMPILEES DANS l'exe (ressources RCDATA),
; donc l'OFL impose que son texte accompagne la distribution, binaire compris.
Source: "..\..\LICENSE"; DestDir: "{app}"; DestName: "LICENSE.txt"
Source: "..\..\LICENSE_THIRD_PARTIES.md"; DestDir: "{app}"
Source: "..\..\licenses\*"; DestDir: "{app}\licenses"

[Icons]
Name: "{group}\RottenText"; Filename: "{app}\{#AppExe}"; IconFilename: "{app}\RottenText.ico"
Name: "{group}\{cm:UninstallProgram,RottenText}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\RottenText"; Filename: "{app}\{#AppExe}"; IconFilename: "{app}\RottenText.ico"; Tasks: desktopicon

[Registry]
; "Open with RottenText" (clic droit sur un fichier), avec l'icone de l'app a
; gauche. Une instance deja lancee recupere le fichier en nouvel onglet
; (mono-instance IPC), sinon une fenetre s'ouvre.
; HKA = HKLM en install machine, HKCU en install utilisateur.
;
; PORTEE : ce mecanisme registre marche PARTOUT -- Windows 10, Windows Server
; 2019/2022, et Windows 11.
;
; LIMITE ASSUMEE (Windows 11) : l'entree y apparait sous "Afficher plus
; d'options" (Shift+F10), pas dans le menu principal. Ce n'est pas un oubli :
; le menu principal de Win11 n'accepte QUE les extensions implementant
; IExplorerCommand et fournies par une app a IDENTITE DE PACKAGE (MSIX ou
; sparse package) -- une cle de registre y est ignoree par construction (doc
; Microsoft: "Windows application development - Best practices", section
; Context menus). Y aller demanderait une DLL COM + un package MSIX signe par
; un certificat approuve par la machine cible. Choix produit: on s'en tient au
; registre, qui marche partout sans certificat ni friction a l'installation.
Root: HKA; Subkey: "Software\Classes\*\shell\RottenText"; ValueType: string; ValueName: ""; ValueData: "Open with RottenText"; Flags: uninsdeletekey; Tasks: contextmenu
Root: HKA; Subkey: "Software\Classes\*\shell\RottenText"; ValueType: string; ValueName: "Icon"; ValueData: """{app}\{#AppExe}"",0"; Tasks: contextmenu
Root: HKA; Subkey: "Software\Classes\*\shell\RottenText\command"; ValueType: string; ValueName: ""; ValueData: """{app}\{#AppExe}"" ""%1"""; Flags: uninsdeletekey; Tasks: contextmenu

[Run]
Filename: "{app}\{#AppExe}"; Description: "{cm:LaunchProgram,RottenText}"; Flags: nowait postinstall skipifsilent
