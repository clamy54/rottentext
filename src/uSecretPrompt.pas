unit uSecretPrompt;

{$mode objfpc}{$H+}

// Saisie masquee d'un secret. Le clair n'est jamais affiche, insere, loggue ni
// copie. WipeSecret est best effort: les AnsiString FPC sont refcountees.
// Le masquage (sans EchoMode/PasswordChar) vit dans TRtSecretEdit, cote RottenUI.

interface

function AskSecret(const ATitle, APrompt: string; out AValue: string;
  AConfirm: Boolean = False): Boolean;

procedure WipeSecret(var AValue: string);

implementation

uses
  Classes, SysUtils, Controls, StdCtrls, Forms, Dialogs,
  uThemedControls, uRtMessage, uRtSecretEdit;

type
  TSecretForm = class(TForm)
  public
    Ed1, Ed2: TRtSecretEdit;
    NeedConfirm: Boolean;
    procedure DoOK(Sender: TObject);
  end;

procedure TSecretForm.DoOK(Sender: TObject);
begin
  if NeedConfirm and not Ed1.SameAs(Ed2) then
  begin
    RtMessageDlg('RottenText', 'The two entries do not match.', mtWarning, [mbOK], 0);
    Ed2.SetFocus;
    Exit;
  end;
  ModalResult := mrOk;
end;

procedure WipeSecret(var AValue: string);
begin
  if AValue <> '' then
  begin
    UniqueString(AValue);
    FillChar(AValue[1], Length(AValue), 0);
  end;
  AValue := '';
end;

function AskSecret(const ATitle, APrompt: string; out AValue: string;
  AConfirm: Boolean): Boolean;
var
  f: TSecretForm;
  lbl, lbl2: TLabel;
  bOk, bCancel: TThemedButton;
  y: Integer;
begin
  Result := False;
  AValue := '';
  f := TSecretForm.CreateNew(nil);
  try
    f.Caption := ATitle;
    f.BorderStyle := bsDialog;
    f.Position := poScreenCenter;
    f.ClientWidth := 360;
    f.NeedConfirm := AConfirm;

    y := 12;
    lbl := TLabel.Create(f);
    lbl.Parent := f;
    lbl.SetBounds(12, y, 336, 18);
    lbl.Caption := APrompt;
    Inc(y, 22);

    f.Ed1 := TRtSecretEdit.Create(f);
    f.Ed1.Parent := f;
    f.Ed1.SetBounds(12, y, 336, 26);
    Inc(y, 32);

    if AConfirm then
    begin
      lbl2 := TLabel.Create(f);
      lbl2.Parent := f;
      lbl2.SetBounds(12, y, 336, 18);
      lbl2.Caption := 'Confirm:';
      Inc(y, 20);

      f.Ed2 := TRtSecretEdit.Create(f);
      f.Ed2.Parent := f;
      f.Ed2.SetBounds(12, y, 336, 26);
      Inc(y, 32);
    end;

    Inc(y, 6);
    bOk := TThemedButton.Create(f);
    bOk.Parent := f;
    bOk.SetBounds(180, y, 80, 28);
    bOk.Caption := 'OK';
    bOk.Default := True;
    bOk.OnClick := @f.DoOK;

    bCancel := TThemedButton.Create(f);
    bCancel.Parent := f;
    bCancel.SetBounds(268, y, 80, 28);
    bCancel.Caption := 'Cancel';
    bCancel.Cancel := True;
    bCancel.ModalResult := mrCancel;

    f.ClientHeight := y + 40;
    f.ActiveControl := f.Ed1;
    ThemeDialog(f);

    if f.ShowModal = mrOk then
    begin
      f.Ed1.GetSecret(AValue);
      Result := True;
    end;
    // efface le clair des buffers
    f.Ed1.Wipe;
    if AConfirm and (f.Ed2 <> nil) then f.Ed2.Wipe;
  finally
    f.Free;
  end;
end;

end.
