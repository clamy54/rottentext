unit uStatusBar;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Controls, Graphics, LazUTF8, SynEdit, SynEditTypes, uTheme;

type
  TRTStatusBar = class(TCustomControl)
  private
    FSyn: TSynEdit;
    FFileType: string;
    FEncName: string;
    FEolName: string;
    FLeftOverride: string; // texte de gauche sans editeur lie (vue hex)
    FFindInfo: string;
    FLeftText: string;     // cache: Paint ne doit pas re-materialiser la
                           // selection (Ctrl+A sur gros fichier)
    procedure SynStatusChange(Sender: TObject; Changes: TSynStatusChanges);
    function ComputeLeftText: string;
    procedure RefreshLeft;
    function TabText: string;
    procedure DrawRight(var ARight: Integer; ATop: Integer; const AText: string);
  protected
    procedure Paint; override;
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
  public
    constructor Create(AOwner: TComponent); override;
    procedure Bind(ASyn: TSynEdit);
    procedure SetFileType(const AType: string);
    procedure SetEncoding(const AName: string);
    procedure SetEol(const AName: string);
    procedure SetLeftOverride(const AText: string);
    procedure SetFindInfo(const AInfo: string);
  end;

implementation

constructor TRTStatusBar.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FFileType := 'Plain Text';
  Font.Name := RTFontName;
  Font.Size := 9;
  Font.Quality := fqCleartype;
end;

procedure TRTStatusBar.Bind(ASyn: TSynEdit);
begin
  if FSyn = ASyn then
  begin
    RefreshLeft;
    Exit;
  end;
  if FSyn <> nil then
  begin
    FSyn.RemoveFreeNotification(Self);
    FSyn.UnRegisterStatusChangedHandler(@SynStatusChange);
  end;
  FSyn := ASyn;
  if FSyn <> nil then
  begin
    FSyn.FreeNotification(Self);
    FSyn.RegisterStatusChangedHandler(@SynStatusChange,
      [scCaretX, scCaretY, scSelection]);
  end;
  RefreshLeft;
end;

procedure TRTStatusBar.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited Notification(AComponent, Operation);
  if (Operation = opRemove) and (AComponent = FSyn) then
  begin
    FSyn := nil;
    FLeftText := FLeftOverride;
  end;
end;

procedure TRTStatusBar.SetFileType(const AType: string);
begin
  if FFileType = AType then Exit;
  FFileType := AType;
  Invalidate;
end;

procedure TRTStatusBar.SetEncoding(const AName: string);
begin
  if FEncName = AName then Exit;
  FEncName := AName;
  Invalidate;
end;

procedure TRTStatusBar.SetEol(const AName: string);
begin
  if FEolName = AName then Exit;
  FEolName := AName;
  Invalidate;
end;

procedure TRTStatusBar.SetLeftOverride(const AText: string);
begin
  if FLeftOverride = AText then Exit;
  FLeftOverride := AText;
  RefreshLeft;
end;

procedure TRTStatusBar.SetFindInfo(const AInfo: string);
begin
  if FFindInfo = AInfo then Exit;
  FFindInfo := AInfo;
  Invalidate;
end;

procedure TRTStatusBar.SynStatusChange(Sender: TObject; Changes: TSynStatusChanges);
begin
  if Changes * [scCaretX, scCaretY, scSelection] <> [] then
    RefreshLeft;
end;

function TRTStatusBar.ComputeLeftText: string;
var
  bb, be: TPoint;
  lines, chars: Integer;
begin
  if FSyn = nil then
    Exit(FLeftOverride);
  if FSyn.SelAvail then
  begin
    bb := FSyn.BlockBegin;
    be := FSyn.BlockEnd;
    lines := be.Y - bb.Y + 1;
    // saut de ligne compte pour un caractere
    chars := UTF8Length(StringReplace(FSyn.SelText, #13#10, #10, [rfReplaceAll]));
    if lines > 1 then
      Result := Format('%d lines, %d characters', [lines, chars])
    else
      Result := Format('%d characters', [chars]);
  end
  else
    Result := Format('Line %d, Column %d', [FSyn.CaretY, FSyn.CaretX]);
end;

procedure TRTStatusBar.RefreshLeft;
var
  newText: string;
begin
  newText := ComputeLeftText;
  if newText <> FLeftText then
  begin
    FLeftText := newText;
    Invalidate;
  end;
end;

function TRTStatusBar.TabText: string;
begin
  if FSyn = nil then
    Result := ''
  else
    Result := Format('Tab Size: %d', [FSyn.TabWidth]);
end;

procedure TRTStatusBar.DrawRight(var ARight: Integer; ATop: Integer; const AText: string);
begin
  if AText = '' then Exit;
  Dec(ARight, Canvas.TextWidth(AText));
  Canvas.TextOut(ARight, ATop, AText);
  Dec(ARight, 28);
end;

procedure TRTStatusBar.Paint;
var
  ty, rx: Integer;
begin
  Canvas.Brush.Color := clStatusBg;
  Canvas.FillRect(ClientRect);
  Canvas.Font := Font;
  Canvas.Font.Color := clStatusText;
  Canvas.Brush.Style := bsClear;

  ty := (ClientHeight - Canvas.TextHeight('Ag')) div 2;
  Canvas.TextOut(12, ty, FLeftText);

  rx := ClientWidth - 14;
  DrawRight(rx, ty, FFileType);
  DrawRight(rx, ty, TabText);
  DrawRight(rx, ty, FEncName);
  DrawRight(rx, ty, FEolName);
  DrawRight(rx, ty, FFindInfo);

  Canvas.Brush.Style := bsSolid;
end;

end.
