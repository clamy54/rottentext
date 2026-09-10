unit uFontDlg;

{$mode objfpc}{$H+}

// View > Font...: police du contenu de l'editeur, polices embarquees seulement

interface

// True = choix pose dans uTheme; l'appelant rafraichit les vues et sauve
function ShowEditorFontDialog: Boolean;

implementation

uses
  Classes, SysUtils, Forms, Controls, StdCtrls, Graphics, Dialogs,
  uFontEmbed, uTheme, uThemeLoad;

const
  SIZE_MIN = 6;
  SIZE_MAX = 40;

type
  TFontForm = class(TForm)
  private
    FFamily: TComboBox;
    FKeys: TStringList; // cle par ligne du combo
    FSize: TComboBox;
    FPreview: TLabel;
    procedure ChoiceChanged(Sender: TObject);
    procedure UpdatePreview;
    function SelectedKey: string;
    function SelectedSize: Integer;
  end;

function TFontForm.SelectedKey: string;
begin
  Result := '';
  if (FFamily.ItemIndex >= 0) and (FFamily.ItemIndex < FKeys.Count) then
    Result := FKeys[FFamily.ItemIndex];
end;

function TFontForm.SelectedSize: Integer;
begin
  Result := StrToIntDef(FSize.Text, RT_EDITOR_SIZE_DEF);
  if Result < SIZE_MIN then Result := SIZE_MIN;
  if Result > SIZE_MAX then Result := SIZE_MAX;
end;

procedure TFontForm.UpdatePreview;
var
  fam: string;
begin
  fam := ResolveMonaspace(SelectedKey);
  if fam = '' then fam := RTEditorFont;
  FPreview.Font.Name := fam;
  FPreview.Font.Size := SelectedSize;
end;

procedure TFontForm.ChoiceChanged(Sender: TObject);
begin
  UpdatePreview;
end;

function ShowEditorFontDialog: Boolean;
var
  f: TFontForm;
  lbl: TLabel;
  btn: TButton;
  i, sz: Integer;
  key: string;
begin
  Result := False;
  if not MonaspaceAvailable then
  begin
    MessageDlg('RottenText', 'The embedded fonts are not available in this ' +
      'binary: the system default font is used.', mtInformation, [mbOK], 0);
    Exit;
  end;

  f := TFontForm.CreateNew(nil);
  try
    f.FKeys := TStringList.Create;
    f.Caption := 'Editor Font';
    f.BorderStyle := bsDialog;
    f.Position := poMainFormCenter;
    f.Color := clEditorBg;
    f.ClientWidth := 440;
    f.ClientHeight := 230;

    lbl := TLabel.Create(f);
    lbl.Parent := f;
    lbl.SetBounds(16, 20, 90, 18);
    lbl.Caption := 'Family:';
    lbl.Font.Color := clEditorFg;

    f.FFamily := TComboBox.Create(f);
    f.FFamily.Parent := f;
    f.FFamily.SetBounds(112, 16, 300, 26);
    f.FFamily.Style := csDropDownList;
    for i := 0 to MonaspaceFamilyCount - 1 do
    begin
      key := MonaspaceFamilyKey(i);
      if ResolveMonaspace(key) = '' then Continue; // famille non chargee
      f.FKeys.Add(key);
      f.FFamily.Items.Add(MonaspaceFamilyLabel(i));
      if SameText(ResolveMonaspace(key), RTEditorFont) then
        f.FFamily.ItemIndex := f.FFamily.Items.Count - 1;
    end;
    if f.FFamily.ItemIndex < 0 then f.FFamily.ItemIndex := 0;

    lbl := TLabel.Create(f);
    lbl.Parent := f;
    lbl.SetBounds(16, 58, 90, 18);
    lbl.Caption := 'Size:';
    lbl.Font.Color := clEditorFg;

    f.FSize := TComboBox.Create(f);
    f.FSize.Parent := f;
    f.FSize.SetBounds(112, 54, 80, 26);
    f.FSize.Style := csDropDownList;
    for sz := SIZE_MIN to SIZE_MAX do
    begin
      f.FSize.Items.Add(IntToStr(sz));
      if sz = RTEditorSize then f.FSize.ItemIndex := f.FSize.Items.Count - 1;
    end;
    if f.FSize.ItemIndex < 0 then
      f.FSize.ItemIndex := f.FSize.Items.IndexOf(IntToStr(RT_EDITOR_SIZE_DEF));

    f.FPreview := TLabel.Create(f);
    f.FPreview.Parent := f;
    f.FPreview.AutoSize := False;
    f.FPreview.SetBounds(16, 96, 408, 70);
    f.FPreview.WordWrap := True;
    f.FPreview.Font.Color := clEditorFg;
    f.FPreview.Caption := 'if (x != 0) { return a->b[i]; }  0O1lI  |{}[]()<>#$&@' +
      LineEnding + 'drwxr-xr-x  1.234 KiB  2026-07-17  # comment';

    f.FFamily.OnChange := @f.ChoiceChanged;
    f.FSize.OnChange := @f.ChoiceChanged;
    f.UpdatePreview;

    // mrIgnore = retour a la police du theme
    btn := TButton.Create(f);
    btn.Parent := f;
    btn.SetBounds(16, 184, 120, 30);
    btn.Caption := 'Theme Default';
    btn.ModalResult := mrIgnore;

    btn := TButton.Create(f);
    btn.Parent := f;
    btn.SetBounds(244, 184, 88, 30);
    btn.Caption := 'OK';
    btn.ModalResult := mrOK;
    btn.Default := True;

    btn := TButton.Create(f);
    btn.Parent := f;
    btn.SetBounds(336, 184, 88, 30);
    btn.Caption := 'Cancel';
    btn.ModalResult := mrCancel;
    btn.Cancel := True;

    case f.ShowModal of
      mrOK:
        begin
          if f.SelectedKey = '' then Exit;
          PrefEditorFontKey := f.SelectedKey;
          PrefEditorFontSize := f.SelectedSize;
        end;
      mrIgnore:
        begin
          PrefEditorFontKey := '';
          PrefEditorFontSize := 0;
        end;
    else
      Exit;
    end;
    ReapplyEditorFont;
    Result := True;
  finally
    f.FKeys.Free;
    f.Free;
  end;
end;

end.
