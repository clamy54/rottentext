unit uAbout;

{$mode objfpc}{$H+}

// Logo pris dans la ressource PNG APPICON_PNG, pas dans MAINICON: sous gtk2 la
// conversion TIcon->bitmap sort des pixels stries au-dela de la 16x16.

interface

procedure ShowAbout(const AVersion: string);

implementation

uses
  Classes, SysUtils, Types, Forms, Controls, StdCtrls, ExtCtrls, Graphics,
  LCLIntf, uTheme;

type
  TAboutForm = class(TForm)
  public
    procedure LinkClick(Sender: TObject);
  end;

procedure TAboutForm.LinkClick(Sender: TObject);
begin
  OpenURL(TLabel(Sender).Caption);
end;

function AddLabel(AForm: TAboutForm; ATop: Integer; const AText: string;
  ALink: Boolean; ASize: Integer = 0; ABold: Boolean = False): TLabel;
begin
  Result := TLabel.Create(AForm);
  Result.Parent := AForm;
  Result.Caption := AText;
  Result.AutoSize := True;
  Result.Font.Color := clEditorFg;
  if ASize > 0 then Result.Font.Size := ASize;
  if ABold then Result.Font.Style := Result.Font.Style + [fsBold];
  if ALink then
  begin
    Result.Font.Color := clCaret;
    Result.Font.Style := Result.Font.Style + [fsUnderline];
    Result.Cursor := crHandPoint;
    Result.OnClick := @AForm.LinkClick;
  end;
  Result.Anchors := [akTop];
  Result.AnchorHorizontalCenterTo(AForm);
  Result.Top := ATop;
end;

function LoadLogo(AImg: TImage): Boolean;
var
  rs: TResourceStream;
  png: TPortableNetworkGraphic;
begin
  Result := False;
  try
    rs := TResourceStream.Create(HInstance, 'APPICON_PNG', RT_RCDATA);
    try
      png := TPortableNetworkGraphic.Create;
      try
        png.LoadFromStream(rs);
        AImg.Picture.Assign(png);
        Result := True;
      finally
        png.Free;
      end;
    finally
      rs.Free;
    end;
  except
    // ressource absente: repli sur MAINICON
  end;
end;

procedure ShowAbout(const AVersion: string);
var
  f: TAboutForm;
  img: TImage;
  ico: TIcon;
  b: TButton;
  y: Integer;
begin
  f := TAboutForm.CreateNew(nil);
  try
    f.Caption := 'About RottenText';
    f.BorderStyle := bsDialog;
    f.Position := poMainFormCenter;
    f.Color := clEditorBg;
    f.Width := 440;
    f.Height := 420;

    img := TImage.Create(f);
    img.Parent := f;
    img.SetBounds((f.ClientWidth - 96) div 2, 16, 96, 96);
    img.Stretch := True;
    img.Proportional := True;
    img.Center := True;
    if not LoadLogo(img) then
      try
        ico := TIcon.Create;
        try
          ico.LoadFromResourceName(HInstance, 'MAINICON');
          ico.Current := ico.GetBestIndexForSize(Size(128, 128));
          img.Picture.Assign(ico);
        finally
          ico.Free;
        end;
      except
        // pas d'icone liee: boite sans logo
      end;

    y := 124;
    AddLabel(f, y, 'RottenText ' + AVersion, False, 15, True);
    Inc(y, 38);
    AddLabel(f, y, 'A rotten editor for rotten files and rotten days.', False);
    Inc(y, 30);
    AddLabel(f, y, 'Developed by Cyril LAMY', False);
    Inc(y, 24);
    AddLabel(f, y, 'Released under the GPL-V2 license', False);
    Inc(y, 30);
    AddLabel(f, y, 'https://github.com/clamy54/rottentext', True);
    Inc(y, 34);
    AddLabel(f, y, 'RottenText uses the Monaspace font family:', False);
    Inc(y, 22);
    AddLabel(f, y, 'https://monaspace.githubnext.com/', True);

    b := TButton.Create(f);
    b.Parent := f;
    b.Caption := 'Close';
    b.ModalResult := mrOk;
    b.Default := True;
    b.Cancel := True;
    b.SetBounds((f.ClientWidth - 90) div 2, f.ClientHeight - 44, 90, 30);

    f.ShowModal;
  finally
    f.Free;
  end;
end;

end.
