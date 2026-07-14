unit uTheme;

{$mode objfpc}{$H+}

interface

uses
  Graphics, SynEdit, SynEditTypes, SynGutter, SynGutterLineNumber, SynEditMiscClasses;

// Des variables, pas des constantes: uThemeLoad les remplace a chaud.
var
  clEditorBg, clEditorFg, clCurrentLine, clSelectionBg, clSelectionInactive,
  clSelectionFg,
  clCaret, clGutterBg, clGutterFg, clGutterFgCur, clGutterCurBg, clRightEdge,
  clTabStrip, clTabActive, clTabInactive, clTabHover, clTabActiveText, clTabInactiveText,
  clTabActiveDim, clTabActiveTextDim,
  clModifiedDot, clTabIcon, clTabIconHi, clTabGlyph, clMacroRec,
  clTabLock, clTabLockMod,
  clMenuBg, clMenuText, clMenuHover, clMenuPopupBg, clMenuDisabled,
  clStatusBg, clStatusText, clMinimapViewport, clBorder,
  clFindOutline, clFindBtn, clFindBtnText,
  clFindToggleOn, clFindToggleOnText, clFindToggleOff, clFindToggleOffText: TColor;

var
  clSideBg, clSideHeader, clSideText, clSideTextHi, clSideHover, clSideSel: TColor;

var
  clCodeComment, clCodeString, clCodeNumber, clCodeConstant, clCodeKeyword,
  clCodeType, clCodeFunction, clCodeOperator, clCodeVariable, clCodeInvalid: TColor;

var
  RTFontName: string = 'Consolas';

// Le gutter suit la police de l'editeur: un seul TextDrawer par SynEdit, pas de
// police de numeros de ligne independante.
var
  RTEditorFont: string = 'Consolas';  RTEditorSize: Integer = 11;
  RTTabFont: string = 'Consolas';     RTTabSize: Integer = 10;
  RTSideFont: string = 'Consolas';    RTSideSize: Integer = 9;

const
  RT_EDITOR_SIZE_DEF = 11;
  RT_TAB_SIZE_DEF = 10;
  RT_SIDE_SIZE_DEF = 9;

// a appeler avant d'appliquer un theme: une cle absente ne doit pas heriter du
// theme precedent.
procedure ApplyDefaultFonts;

procedure ApplyEditorTheme(ASyn: TSynEdit);

implementation

procedure ApplyDefaultFonts;
begin
  RTEditorFont := RTFontName;  RTEditorSize := RT_EDITOR_SIZE_DEF;
  RTTabFont := RTFontName;     RTTabSize := RT_TAB_SIZE_DEF;
  RTSideFont := RTFontName;    RTSideSize := RT_SIDE_SIZE_DEF;
end;

procedure ApplyEditorTheme(ASyn: TSynEdit);
var
  i: Integer;
  ln: TSynGutterLineNumber;
begin
  ASyn.Font.Name := RTEditorFont;
  ASyn.Font.Size := RTEditorSize;
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

initialization
  clEditorBg         := RGBToColor($30, $38, $41);
  clEditorFg         := RGBToColor($D8, $DE, $E9);
  clCurrentLine      := RGBToColor($30, $38, $41);
  clSelectionBg      := RGBToColor($4C, $58, $63);
  clSelectionInactive:= RGBToColor($4C, $58, $63);
  clSelectionFg      := clWhite;
  clCaret            := RGBToColor($F9, $AE, $58);
  clGutterBg         := RGBToColor($30, $38, $41);
  clGutterFg         := RGBToColor($BF, $C5, $D0);
  clGutterFgCur      := RGBToColor($BF, $C5, $D0);
  clGutterCurBg      := RGBToColor($4C, $58, $63);
  clRightEdge        := RGBToColor($4C, $58, $63);
  clTabStrip         := RGBToColor($72, $78, $7E);
  clTabInactive      := RGBToColor($72, $78, $7E);
  clTabHover         := RGBToColor($4F, $57, $5E);
  clTabActive        := RGBToColor($30, $38, $41);
  clTabActiveText    := RGBToColor($FF, $FF, $FF);
  clTabInactiveText  := RGBToColor($DA, $DC, $DD);
  // onglet actif du pane qui n'a PAS le focus (split view)
  clTabActiveDim     := RGBToColor($3E, $46, $4F);
  clTabActiveTextDim := RGBToColor($B8, $BD, $C4);
  clModifiedDot      := RGBToColor($85, $9F, $89);
  clTabIcon          := RGBToColor($85, $9F, $89);
  clTabIconHi        := RGBToColor($84, $AA, $83);
  clTabGlyph         := RGBToColor($C6, $C9, $CB);
  clMacroRec         := RGBToColor($EC, $5F, $67);
  clTabLock          := RGBToColor($EC, $5F, $67);
  clTabLockMod       := RGBToColor($F9, $AE, $58);
  clMenuBg           := RGBToColor($FF, $FF, $FF);
  clMenuText         := RGBToColor($00, $00, $00);
  clMenuHover        := RGBToColor($91, $C9, $F7);
  clMenuPopupBg      := RGBToColor($F2, $F2, $F2);
  clMenuDisabled     := RGBToColor($6D, $6D, $6D);
  clStatusBg         := RGBToColor($2B, $31, $38);
  clStatusText       := RGBToColor($9A, $A4, $B0);
  clMinimapViewport  := RGBToColor($3F, $4A, $56);
  clBorder           := RGBToColor($23, $27, $2D);
  clFindOutline      := RGBToColor($64, $73, $82);
  clFindBtn          := RGBToColor($3F, $4A, $56);
  clFindBtnText      := RGBToColor($D8, $DE, $E9);
  clFindToggleOn     := RGBToColor($4C, $58, $63);
  clFindToggleOnText := RGBToColor($F9, $AE, $58);
  clFindToggleOff    := RGBToColor($3F, $4A, $56);
  clFindToggleOffText:= RGBToColor($9A, $A4, $B0);
  clSideBg           := RGBToColor($2B, $31, $38);
  clSideHeader       := RGBToColor($6F, $79, $84);
  clSideText         := RGBToColor($9A, $A4, $B0);
  clSideTextHi       := RGBToColor($D8, $DE, $E9);
  clSideHover        := RGBToColor($33, $3B, $44);
  clSideSel          := RGBToColor($3F, $4A, $56);
  clCodeComment      := RGBToColor($65, $73, $7E);
  clCodeString       := RGBToColor($99, $C7, $94);
  clCodeNumber       := RGBToColor($F9, $AE, $58);
  clCodeConstant     := RGBToColor($F9, $AE, $58);
  clCodeKeyword      := RGBToColor($C5, $94, $C5);
  clCodeType         := RGBToColor($FA, $C8, $63);
  clCodeFunction     := RGBToColor($66, $99, $CC);
  clCodeOperator     := RGBToColor($5F, $B3, $B3);
  clCodeVariable     := RGBToColor($EC, $5F, $67);
  clCodeInvalid      := RGBToColor($EC, $5F, $67);
end.
