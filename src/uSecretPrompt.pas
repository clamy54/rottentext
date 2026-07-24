unit uSecretPrompt;

{$mode objfpc}{$H+}

// Saisie masquee d'un secret. Le clair n'est jamais affiche, insere, loggue ni
// copie. WipeSecret est best effort: les AnsiString FPC sont refcountees.
//
// macOS: on n'utilise PAS EchoMode/PasswordChar. Le widgetset Cocoa transforme
// alors le champ en NSSecureTextField, qui active le "secure event input" du
// WindowServer; l'etat se desequilibre au fil d'une session (plusieurs
// dialogues) et finit par bloquer l'app (roue coloree, quit force) au passage
// de focus entre deux champs securises. On masque nous-memes: le champ affiche
// des '*', le clair vit dans un buffer fantome cote LCL, jamais dans le widget.

interface

function AskSecret(const ATitle, APrompt: string; out AValue: string;
  AConfirm: Boolean = False): Boolean;

procedure WipeSecret(var AValue: string);

implementation

uses
  Classes, SysUtils, Math, Controls, StdCtrls, Forms, Dialogs, LazUTF8;

type
  // Champ masque sans secure input: le Text visible est '*' x N, le clair est
  // FValue. Toute mutation (frappe, souris, coller/couper menu) est interceptee
  // pour reconstruire FValue a partir de la selection AVANT edition.
  TSecretEdit = class(TEdit)
  private
    FValue: string;
    FGuard: Boolean;
    FSelStart, FSelLen: Integer; // selection pre-edition, en caracteres visibles
    procedure Capture;
  protected
    procedure Change; override;
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
  public
    procedure SelectAll; override;
    procedure PasteFromClipboard; override;
    procedure CopyToClipboard; override; // bloque: pas de clair au presse-papier
    procedure CutToClipboard; override;  // bloque de meme
    procedure Undo; override;            // l'historique du widget garderait du clair
    procedure ClearValue;
    property Value: string read FValue;
  end;

  TSecretForm = class(TForm)
  public
    Ed1, Ed2: TSecretEdit;
    NeedConfirm: Boolean;
    procedure DoOK(Sender: TObject);
  end;

procedure TSecretEdit.Capture;
begin
  FSelStart := SelStart;
  FSelLen := SelLength;
end;

procedure TSecretEdit.KeyDown(var Key: Word; Shift: TShiftState);
begin
  // avant que la frappe (ou un raccourci d'edition) ne modifie le texte
  Capture;
  inherited KeyDown(Key, Shift);
end;

procedure TSecretEdit.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseUp(Button, Shift, X, Y);
  Capture; // le clic vient de (re)poser caret/selection
end;

procedure TSecretEdit.SelectAll;
begin
  inherited SelectAll;
  Capture;
end;

procedure TSecretEdit.PasteFromClipboard;
begin
  Capture; // le collage remplace la selection courante
  inherited PasteFromClipboard;
end;

procedure TSecretEdit.CopyToClipboard;
begin
  // volontairement vide: ne jamais exposer le clair (ni les '*') au presse-papier
end;

procedure TSecretEdit.CutToClipboard;
begin
  // pas de copie; on supprime la selection comme un effacement simple
  Capture;
  if FSelLen > 0 then
  begin
    FGuard := True;
    SelText := '';
    FGuard := False;
    FValue := UTF8Copy(FValue, 1, FSelStart) +
              UTF8Copy(FValue, FSelStart + FSelLen + 1, MaxInt);
    FGuard := True;
    Text := StringOfChar('*', UTF8Length(FValue));
    SelStart := FSelStart;
    SelLength := 0;
    FGuard := False;
    FSelLen := 0;
  end;
end;

procedure TSecretEdit.Undo;
begin
  // no-op: rejouer l'undo du widget reafficherait des caracteres reels
end;

procedure TSecretEdit.Change;
var
  newText, inserted: string;
  newLen, oldLen, insLen, newCaret: Integer;
begin
  if FGuard then
  begin
    inherited Change;
    Exit;
  end;
  newText := Text;
  newLen := UTF8Length(newText);
  oldLen := UTF8Length(FValue);
  // insLen = caracteres inseres a la place de la selection [FSelStart, +FSelLen)
  insLen := newLen - oldLen + FSelLen;
  if (insLen >= 0) and (FSelStart >= 0) and (FSelStart + FSelLen <= oldLen) then
  begin
    // frappe, collage, ou remplacement d'une selection
    inserted := UTF8Copy(newText, FSelStart + 1, insLen);
    FValue := UTF8Copy(FValue, 1, FSelStart) + inserted +
              UTF8Copy(FValue, FSelStart + FSelLen + 1, MaxInt);
    newCaret := FSelStart + insLen;
  end
  else
  begin
    // suppression sans selection (backspace / forward-delete): le caret
    // post-edition marque le DEBUT de la plage supprimee dans les deux cas
    newCaret := SelStart;
    if newCaret < 0 then newCaret := 0;
    if newCaret > oldLen then newCaret := oldLen;
    FValue := UTF8Copy(FValue, 1, newCaret) +
              UTF8Copy(FValue, newCaret - insLen + 1, MaxInt);
  end;
  FGuard := True;
  Text := StringOfChar('*', UTF8Length(FValue));
  newCaret := EnsureRange(newCaret, 0, UTF8Length(FValue));
  SelStart := newCaret;
  SelLength := 0;
  FGuard := False;
  // le caret devient le point d'insertion de la prochaine edition
  FSelStart := newCaret;
  FSelLen := 0;
  inherited Change;
end;

procedure TSecretEdit.ClearValue;
begin
  WipeSecret(FValue);
  FGuard := True;
  Text := '';
  FGuard := False;
  FSelStart := 0;
  FSelLen := 0;
end;

procedure TSecretForm.DoOK(Sender: TObject);
begin
  if NeedConfirm and (Ed1.Value <> Ed2.Value) then
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

    f.Ed1 := TSecretEdit.Create(f);
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

      f.Ed2 := TSecretEdit.Create(f);
      f.Ed2.Parent := f;
      f.Ed2.SetBounds(12, y, 336, 26);
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
      AValue := f.Ed1.Value;
      Result := True;
    end;
    // efface le clair des buffers
    f.Ed1.ClearValue;
    if AConfirm and (f.Ed2 <> nil) then f.Ed2.ClearValue;
  finally
    f.Free;
  end;
end;

end.
