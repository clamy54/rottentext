unit uDarwinQuit;

{$mode objfpc}{$H+}
{$modeswitch objectivec1}

// Lazarus 4.8: CocoaConfigApplication.events.onQuitApp a disparu et l'item
// Quit du menu app appelle MainForm.CloseQuery en direct, donc la branche
// bouton rouge (cacher) au lieu de quitter. On re-cible l'item Quit (Cmd+Q)
// vers un handler local qui reproduit la mecanique 4.4: QueueAsyncCall du
// callback applicatif, hors de la boucle de tracking du menu.

interface

uses
  Forms, CocoaAll;

// re-cible l'item Quit du menu app; False si le menu n'est pas encore pose
function DarwinQuitHookInstall(const AProc: TDataEvent): Boolean;

implementation

type
  TRTQuitTarget = objcclass(NSObject)
  public
    procedure rtQuitApp(sender: id); message 'rtQuitApp:';
  end;

var
  QuitProc: TDataEvent = nil;
  QuitTarget: TRTQuitTarget = nil;

procedure TRTQuitTarget.rtQuitApp(sender: id);
begin
  if Assigned(QuitProc) then
    Application.QueueAsyncCall(QuitProc, 0);
end;

function DarwinQuitHookInstall(const AProc: TDataEvent): Boolean;
var
  appMenu: NSMenu;
  item: NSMenuItem;
  i: Integer;
begin
  Result := False;
  if (NSApp = nil) or (NSApp.mainMenu = nil) or
     (NSApp.mainMenu.numberOfItems = 0) then Exit;
  appMenu := NSApp.mainMenu.itemAtIndex(0).submenu;
  if appMenu = nil then Exit;
  for i := 0 to appMenu.numberOfItems - 1 do
  begin
    item := appMenu.itemAtIndex(i);
    // seul l'item Quit pose par la LCL porte Cmd+Q dans le menu app
    // (DarwinFixShortcuts remappe les Cmd+Q applicatifs en Ctrl+Q)
    if (AnsiString(item.keyEquivalent.UTF8String) = 'q') and
       ((item.keyEquivalentModifierMask and NSCommandKeyMask) <> 0) then
    begin
      QuitProc := AProc;
      if QuitTarget = nil then
        QuitTarget := TRTQuitTarget.alloc.init;
      item.setTarget(QuitTarget);
      item.setAction(objcselector('rtQuitApp:'));
      Exit(True);
    end;
  end;
end;

end.
