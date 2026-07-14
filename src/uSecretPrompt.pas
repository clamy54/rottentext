unit uSecretPrompt;

{$mode objfpc}{$H+}

// Saisie masquee d'un secret. Le clair n'est jamais affiche, insere, loggue ni
// copie. WipeSecret est best effort: les AnsiString FPC sont refcountees.

interface

function AskSecret(const ATitle, APrompt: string; out AValue: string;
  AConfirm: Boolean = False): Boolean;

procedure WipeSecret(var AValue: string);

implementation

uses
  Classes, SysUtils, Controls, StdCtrls, Forms, Dialogs;

type
  TSecretForm = class(TForm)
  public
    Ed1, Ed2: TEdit;
    NeedConfirm: Boolean;
    procedure DoOK(Sender: TObject);
  end;

procedure TSecretForm.DoOK(Sender: TObject);
begin
  if NeedConfirm and (Ed1.Text <> Ed2.Text) then
  begin
    MessageDlg('RottenText', 'The two entries do not match.', mtWarning, [mbOK], 0);
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
  bOk, bCancel: TButton;
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

    f.Ed1 := TEdit.Create(f);
    f.Ed1.Parent := f;
    f.Ed1.SetBounds(12, y, 336, 26);
    f.Ed1.EchoMode := emPassword;
    f.Ed1.PasswordChar := '*';
    Inc(y, 32);

    if AConfirm then
    begin
      lbl2 := TLabel.Create(f);
      lbl2.Parent := f;
      lbl2.SetBounds(12, y, 336, 18);
      lbl2.Caption := 'Confirm:';
      Inc(y, 20);

      f.Ed2 := TEdit.Create(f);
      f.Ed2.Parent := f;
      f.Ed2.SetBounds(12, y, 336, 26);
      f.Ed2.EchoMode := emPassword;
      f.Ed2.PasswordChar := '*';
      Inc(y, 32);
    end;

    Inc(y, 6);
    bOk := TButton.Create(f);
    bOk.Parent := f;
    bOk.SetBounds(180, y, 80, 28);
    bOk.Caption := 'OK';
    bOk.Default := True;
    bOk.OnClick := @f.DoOK;

    bCancel := TButton.Create(f);
    bCancel.Parent := f;
    bCancel.SetBounds(268, y, 80, 28);
    bCancel.Caption := 'Cancel';
    bCancel.Cancel := True;
    bCancel.ModalResult := mrCancel;

    f.ClientHeight := y + 40;
    f.ActiveControl := f.Ed1;

    if f.ShowModal = mrOk then
    begin
      AValue := f.Ed1.Text;
      Result := True;
    end;
    // efface le clair des champs
    f.Ed1.Clear;
    if AConfirm and (f.Ed2 <> nil) then f.Ed2.Clear;
  finally
    f.Free;
  end;
end;

end.
