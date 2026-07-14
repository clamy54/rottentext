unit uPrint;

{$mode objfpc}{$H+}

// Impression coloree sur papier BLANC: les couleurs de scope du theme, pensees
// pour un fond sombre, sont assombries (PrintFg).

interface

uses
  Classes, SysUtils, Graphics, Printers, LazUTF8, SynEditHighlighter, uTheme;

procedure PrintDocument(const ATitle: string; ALines: TStrings;
  AHighlighter: TSynCustomHighlighter; ATabWidth: Integer);

implementation

function DarkenForPrint(c: TColor): TColor;
var
  r, g, b, lum: Integer;
begin
  c := ColorToRGB(c);
  r := Red(c); g := Green(c); b := Blue(c);
  lum := (r * 299 + g * 587 + b * 114) div 1000;
  if lum <= 140 then Exit(c);
  r := r * 120 div lum; g := g * 120 div lum; b := b * 120 div lum;
  Result := RGBToColor(r, g, b);
end;

function PrintFg(fg: TColor): TColor;
begin
  if fg = clNone then Exit(clBlack);
  if fg = clCodeComment then Exit(RGBToColor($6A, $73, $7D));
  if fg = clCodeString then Exit(RGBToColor($1E, $7A, $34));
  if fg = clCodeNumber then Exit(RGBToColor($9A, $52, $00));
  if fg = clCodeKeyword then Exit(RGBToColor($7A, $3E, $9D));
  if fg = clCodeType then Exit(RGBToColor($8A, $62, $00));
  if fg = clCodeFunction then Exit(RGBToColor($15, $4E, $9E));
  if fg = clCodeOperator then Exit(RGBToColor($0E, $70, $70));
  if fg = clCodeVariable then Exit(RGBToColor($C0, $1C, $28));
  Result := DarkenForPrint(fg);
end;

procedure PrintDocument(const ATitle: string; ALines: TStrings;
  AHighlighter: TSynCustomHighlighter; ATabWidth: Integer);
var
  mx, my, w, h, lineH, charW, y, maxChars, page, col, i: Integer;
  tabRun: string;
  attr: TSynHighlighterAttributes;
  c: TColor;
  ital: Boolean;

  procedure Header;
  var
    ps: string;
  begin
    Printer.Canvas.Font.Color := clBlack;
    Printer.Canvas.Font.Style := [fsBold];
    Printer.Canvas.TextOut(mx, my, ATitle);
    ps := IntToStr(page);
    Printer.Canvas.TextOut(mx + w - Printer.Canvas.TextWidth(ps), my, ps);
    Printer.Canvas.Font.Style := [];
    y := my + lineH * 2;
    col := 0;
  end;

  procedure EnsureRow;
  begin
    if y + lineH > my + h then
    begin
      Printer.NewPage;
      Inc(page);
      Header;
    end;
  end;

  procedure EmitSeg(const S: string; AColor: TColor; AItalic: Boolean);
  var
    n, p, take: Integer;
  begin
    if S = '' then Exit;
    if AItalic then Printer.Canvas.Font.Style := [fsItalic]
    else Printer.Canvas.Font.Style := [];
    Printer.Canvas.Font.Color := AColor;
    n := UTF8Length(S);
    p := 1;
    while p <= n do
    begin
      if col >= maxChars then
      begin
        Inc(y, lineH);
        col := 0;
        EnsureRow;
      end;
      take := maxChars - col;
      if take > n - p + 1 then take := n - p + 1;
      // UTF8Copy: ne pas couper un caractere multi-octets en deux
      Printer.Canvas.TextOut(mx + col * charW, y, UTF8Copy(S, p, take));
      Inc(col, take);
      Inc(p, take);
    end;
  end;

  function ExpandTabs(const S: string): string;
  begin
    Result := StringReplace(S, #9, tabRun, [rfReplaceAll]);
  end;

begin
  Printer.BeginDoc;
  try
    Printer.Canvas.Font.Name := RTFontName;
    Printer.Canvas.Font.Size := 10;
    mx := Printer.XDPI div 2;
    my := Printer.YDPI div 2;
    w := Printer.PageWidth - 2 * mx;
    h := Printer.PageHeight - 2 * my;
    lineH := Printer.Canvas.TextHeight('Ag');
    charW := Printer.Canvas.TextWidth('M');
    // metriques nulles: division par zero, et un lineH <= 0 boucle dans EmitSeg
    if (lineH <= 0) or (charW <= 0) then
      raise Exception.Create('Printer reports invalid font metrics');
    maxChars := w div charW;
    if maxChars < 20 then maxChars := 20;
    tabRun := StringOfChar(' ', ATabWidth);
    page := 1;
    Header;

    // ResetRange une fois puis SetLine dans l'ordre: l'etat multi-ligne se propage
    if AHighlighter <> nil then AHighlighter.ResetRange;
    for i := 0 to ALines.Count - 1 do
    begin
      EnsureRow;
      if AHighlighter <> nil then
      begin
        AHighlighter.SetLine(ALines[i], i);
        while not AHighlighter.GetEol do
        begin
          attr := AHighlighter.GetTokenAttribute;
          if attr <> nil then
          begin
            c := PrintFg(attr.Foreground);
            ital := fsItalic in attr.Style;
          end
          else
          begin
            c := clBlack;
            ital := False;
          end;
          EmitSeg(ExpandTabs(AHighlighter.GetToken), c, ital);
          AHighlighter.Next;
        end;
      end
      else
        EmitSeg(ExpandTabs(ALines[i]), clBlack, False);
      Inc(y, lineH);
      col := 0;
    end;

    Printer.EndDoc;
  except
    Printer.Abort;
    raise;
  end;
end;

end.
