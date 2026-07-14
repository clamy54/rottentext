program RottenText;

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}cthreads,{$ENDIF}
  SysUtils, {$IFDEF LINUX}Classes, Graphics,{$ENDIF} Interfaces, Forms,
  uMain, uTheme, uFontEmbed, uSettings, uInstance;

{$R *.res}

{$IFDEF LINUX}
// L'icone du .ico (MAINICON) ressort CORROMPUE de la conversion icone->pixbuf
// de gtk2 (bouillie de pixels des qu'on depasse la 16x16), et le shell affiche
// alors son icone generique. Le meme dessin en PNG passe intact: on remplace
// l'icone d'application par la ressource PNG. Windows (small+big) et macOS
// (.icns du bundle) ne sont pas concernes.
procedure LoadLinuxAppIcon;
var
  rs: TResourceStream;
  png: TPortableNetworkGraphic;
begin
  try
    rs := TResourceStream.Create(HInstance, 'APPICON_PNG', RT_RCDATA);
    try
      png := TPortableNetworkGraphic.Create;
      try
        png.LoadFromStream(rs);
        Application.Icon.Assign(png);
      finally
        png.Free;
      end;
    finally
      rs.Free;
    end;
  except
    // ressource absente ou illisible: on garde l'icone du .ico, pas de quoi
    // empecher l'editeur de demarrer
  end;
end;
{$ENDIF}

begin
  // M-mono-instance: un fichier passe en argument est d'abord propose a
  // l'instance session deja ouverte (nouvel onglet la-bas); accuse recu =
  // rien a faire ici. Pas de reponse sous budget = demarrage normal.
  // Avant toute init LCL: le forward reussi ne paie ni polices ni fenetre.
  if (ParamCount = 1) and not DirectoryExists(ParamStr(1)) and
     FileExists(ParamStr(1)) then
    if ForwardToRunningInstance(ParamStr(1)) then Exit;
  Application.Scaled := True;
  Application.Initialize;
  LoadEmbeddedFonts;
  SettingsLoad; // reglages + theme persistes (apres les polices, avant la
                // fenetre: les controles lisent les bonnes valeurs a la
                // creation); theme disparu ou 1er lancement = theme par defaut
  {$IFDEF LINUX}
  LoadLinuxAppIcon;
  {$ENDIF}
  Application.CreateForm(TfrmMain, frmMain);
  frmMain.Show;
  Application.Run;
end.
