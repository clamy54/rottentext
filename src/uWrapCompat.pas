unit uWrapCompat;

{$mode objfpc}{$H+}

// Retour a la ligne a colonne fixe, quelle que soit la version de SynEdit.
// Lazarus 4.x: GetWrapColumn est prive et non virtuel, d'ou le fork uWrapView.
// Depuis Lazarus 5: MinWrapWidth/MaxWrapWidth font le travail, le fork (cale
// sur les internes de la 4.8) ne compile plus et n'est plus lie.

interface

uses
  Classes, LCLVersion, SynEdit;

function CreateWrapPlugin(AEditor: TSynEdit): TComponent;
// 0 = automatique (largeur de la fenetre), sinon colonne fixe
procedure SetWrapColumn(APlugin: TComponent; AColumn: Integer);

implementation

uses
  {$IF lcl_fullversion >= 4990000}SynEditWrappedView{$ELSE}uWrapView{$ENDIF};

function CreateWrapPlugin(AEditor: TSynEdit): TComponent;
begin
  Result := TLazSynEditLineWrapPlugin.Create(AEditor);
end;

procedure SetWrapColumn(APlugin: TComponent; AColumn: Integer);
var
  p: TLazSynEditLineWrapPlugin;
begin
  p := TLazSynEditLineWrapPlugin(APlugin);
  {$IF lcl_fullversion >= 4990000}
  if AColumn > 0 then
  begin
    p.MinWrapWidth := AColumn;
    p.MaxWrapWidth := AColumn;
  end
  else
  begin
    p.MinWrapWidth := 1;
    p.MaxWrapWidth := 0;
  end;
  {$ELSE}
  p.FixedWrapColumn := AColumn;
  {$ENDIF}
end;

end.
