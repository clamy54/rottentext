unit uEditorTheme;

{$mode objfpc}{$H+}

// Pose les couleurs et la police du theme sur un SynEdit. Ici et pas dans
// RottenUI: le kit ne depend pas de SynEdit.

interface

uses
  SynEdit;

procedure ApplyEditorTheme(ASyn: TSynEdit);

implementation

uses
  Graphics, SynEditTypes, SynGutter, SynGutterLineNumber, SynEditMiscClasses, uTheme;

procedure ApplyEditorTheme(ASyn: TSynEdit);
var
  i: Integer;
  ln: TSynGutterLineNumber;
begin
  ASyn.Font.Name := RSEditorFontName;
  ASyn.Font.Size := RSEditorFontSize;
  ASyn.Color := clEditorBg;
  ASyn.Font.Color := clEditorFg;

  ASyn.SelectedColor.Background := clSelectionBg;
  ASyn.SelectedColor.Foreground := clSelectionFg; // clNone garderait la couleur du token

  ASyn.HighlightAllColor.Background := clNone;
  ASyn.HighlightAllColor.Foreground := clNone;
  ASyn.HighlightAllColor.FrameColor := clFindOutline;

  // RightEdge 0 s'ancre juste apres le gutter: seule l'option masque la regle
  ASyn.Options := ASyn.Options + [eoHideRightMargin];

  ASyn.Gutter.Color := clGutterBg;
  ASyn.Gutter.LeftOffset := 8;
  ASyn.Gutter.RightOffset := 0;
  for i := 0 to ASyn.Gutter.Parts.Count - 1 do
    if ASyn.Gutter.Parts[i] is TSynGutterLineNumber then
    begin
      ln := TSynGutterLineNumber(ASyn.Gutter.Parts[i]);
      ln.MarkupInfo.Background := clGutterBg;
      ln.MarkupInfo.Foreground := clGutterFg;
      ln.MarkupInfoCurrentLine.Background := clGutterCurBg;
      ln.MarkupInfoCurrentLine.Foreground := clGutterFgCur;
    end
    else
      ASyn.Gutter.Parts[i].Visible := False;
end;

end.
