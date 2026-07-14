unit uLdifDlg;

{$mode objfpc}{$H+}

// Dialogues Tools. Aucun mot de passe en clair ne transite par ces formulaires :
// l'appelant le saisit masque et le hashe.

interface

uses
  uLdif, uLdap, uNmap, uHttp;

type
  TStrArray = array of string;

// AWantPw = un schema userPassword a ete choisi (clair demande APRES, par l'appelant)
function AskLdifPerson(out P: TLdifPerson; out AWantPw: Boolean;
  out AScheme: TLdapPwScheme): Boolean;

function AskFields(const ATitle: string; const ALabels, ADefaults: array of string;
  out AValues: TStrArray): Boolean;

function AskNmap(out AOpts: TNmapOpts): Boolean;

function AskHttp(ADefaultTLS: Boolean; out AReq: THttpReq): Boolean;

implementation

uses
  Classes, SysUtils, Controls, StdCtrls, Forms, Dialogs;

const
  // index combo (1..8) -> schema ; index 0 = aucun mot de passe
  SchemeMap: array[1..8] of TLdapPwScheme =
    (lpsSSHA, lpsSSHA256, lpsSSHA512, lpsCrypt, lpsSHA, lpsSMD5, lpsMD5, lpsSASL);

type
  TLdifForm = class(TForm)
  public
    edDn, edCn, edSn, edGiven, edDisplay, edUid, edMail, edTel, edTitle,
      edO, edOu, edDesc: TEdit;
    cbPosix: TCheckBox;
    edUidN, edGidN, edHome, edShell, edGecos: TEdit;
    cbScheme: TComboBox;
    Res: TLdifPerson;
    procedure DoOK(Sender: TObject);
    procedure PosixToggle(Sender: TObject);
  end;

procedure TLdifForm.PosixToggle(Sender: TObject);
var
  on_: Boolean;
begin
  on_ := cbPosix.Checked;
  edUidN.Enabled := on_;  edGidN.Enabled := on_;  edHome.Enabled := on_;
  edShell.Enabled := on_;  edGecos.Enabled := on_;
end;

procedure TLdifForm.DoOK(Sender: TObject);
var
  err: string;
begin
  Res.Dn := Trim(edDn.Text);
  Res.Cn := Trim(edCn.Text);          Res.Sn := Trim(edSn.Text);
  Res.GivenName := Trim(edGiven.Text); Res.DisplayName := Trim(edDisplay.Text);
  Res.Uid := Trim(edUid.Text);        Res.Mail := Trim(edMail.Text);
  Res.Telephone := Trim(edTel.Text);  Res.Title := Trim(edTitle.Text);
  Res.O := Trim(edO.Text);            Res.Ou := Trim(edOu.Text);
  Res.Description := Trim(edDesc.Text);
  Res.IncPosix := cbPosix.Checked;
  Res.UidNumber := Trim(edUidN.Text); Res.GidNumber := Trim(edGidN.Text);
  Res.HomeDir := Trim(edHome.Text);   Res.LoginShell := Trim(edShell.Text);
  Res.Gecos := Trim(edGecos.Text);
  err := ValidateLdif(Res);
  if err <> '' then
  begin
    MessageDlg('RottenText', err, mtWarning, [mbOK], 0);
    Exit;   // formulaire reste ouvert
  end;
  ModalResult := mrOk;
end;

function AddEd(f: TLdifForm; const cap: string; x, y, ew: Integer): TEdit;
var
  l: TLabel;
begin
  l := TLabel.Create(f); l.Parent := f; l.SetBounds(x, y + 4, 92, 18);
  l.Caption := cap;
  Result := TEdit.Create(f); Result.Parent := f;
  Result.SetBounds(x + 96, y, ew, 24); Result.AutoSize := False;
end;

function AskLdifPerson(out P: TLdifPerson; out AWantPw: Boolean;
  out AScheme: TLdapPwScheme): Boolean;
var
  f: TLdifForm;
  bOk, bCancel: TButton;
  lblS: TLabel;
  colA, colB, y: Integer;
begin
  Result := False;
  AWantPw := False;
  AScheme := lpsSSHA;
  colA := 12; colB := 324;
  f := TLdifForm.CreateNew(nil);
  try
    f.Caption := 'LDIF Entry';
    f.BorderStyle := bsDialog;
    f.Position := poScreenCenter;
    f.ClientWidth := 632;

    y := 12;
    f.edDn := AddEd(f, 'dn', colA, y, 512);
    f.edDn.TextHint := 'uid=jdoe,ou=people,dc=example,dc=org';
    Inc(y, 30);
    f.edCn := AddEd(f, 'cn *', colA, y, 200);
    f.edTel := AddEd(f, 'telephone', colB, y, 200); Inc(y, 30);
    f.edSn := AddEd(f, 'sn *', colA, y, 200);
    f.edTitle := AddEd(f, 'title', colB, y, 200); Inc(y, 30);
    f.edGiven := AddEd(f, 'givenName', colA, y, 200);
    f.edO := AddEd(f, 'o', colB, y, 200); Inc(y, 30);
    f.edDisplay := AddEd(f, 'displayName', colA, y, 200);
    f.edOu := AddEd(f, 'ou', colB, y, 200); Inc(y, 30);
    f.edUid := AddEd(f, 'uid', colA, y, 200);
    f.edDesc := AddEd(f, 'description', colB, y, 200); Inc(y, 30);
    f.edMail := AddEd(f, 'mail', colA, y, 200); Inc(y, 34);

    f.cbPosix := TCheckBox.Create(f); f.cbPosix.Parent := f;
    f.cbPosix.SetBounds(colA, y, 300, 20);
    f.cbPosix.Caption := 'Include posixAccount (Unix account)';
    f.cbPosix.OnClick := @f.PosixToggle; Inc(y, 28);

    f.edUidN := AddEd(f, 'uidNumber', colA, y, 200);
    f.edGidN := AddEd(f, 'gidNumber', colB, y, 200); Inc(y, 30);
    f.edHome := AddEd(f, 'homeDirectory', colA, y, 200);
    f.edHome.TextHint := '/home/jdoe';
    f.edShell := AddEd(f, 'loginShell', colB, y, 200);
    f.edShell.Text := '/bin/bash'; Inc(y, 30);
    f.edGecos := AddEd(f, 'gecos', colA, y, 200); Inc(y, 34);

    lblS := TLabel.Create(f); lblS.Parent := f;
    lblS.SetBounds(colA, y + 4, 92, 18); lblS.Caption := 'userPassword';
    f.cbScheme := TComboBox.Create(f); f.cbScheme.Parent := f;
    f.cbScheme.SetBounds(colA + 96, y, 200, 24);
    f.cbScheme.Style := csDropDownList;
    // pas de CommaText : il coupe AUSSI sur les espaces, un libelle a espace ferait 2 items
    f.cbScheme.Items.Add('(none)');
    f.cbScheme.Items.Add('SSHA');
    f.cbScheme.Items.Add('SSHA-256');
    f.cbScheme.Items.Add('SSHA-512');
    f.cbScheme.Items.Add('CRYPT');
    f.cbScheme.Items.Add('SHA');
    f.cbScheme.Items.Add('SMD5');
    f.cbScheme.Items.Add('MD5');
    f.cbScheme.Items.Add('SASL');
    f.cbScheme.ItemIndex := 0;
    Inc(y, 40);

    bOk := TButton.Create(f); bOk.Parent := f;
    bOk.SetBounds(f.ClientWidth - 178, y, 80, 28);
    bOk.Caption := 'OK'; bOk.Default := True; bOk.OnClick := @f.DoOK;
    bCancel := TButton.Create(f); bCancel.Parent := f;
    bCancel.SetBounds(f.ClientWidth - 90, y, 80, 28);
    bCancel.Caption := 'Cancel'; bCancel.Cancel := True;
    bCancel.ModalResult := mrCancel;

    f.ClientHeight := y + 40;
    f.PosixToggle(nil);
    f.ActiveControl := f.edDn;

    if f.ShowModal = mrOk then
    begin
      P := f.Res;
      if f.cbScheme.ItemIndex > 0 then
      begin
        AWantPw := True;
        AScheme := SchemeMap[f.cbScheme.ItemIndex];
      end;
      Result := True;
    end;
  finally
    f.Free;
  end;
end;

function AskFields(const ATitle: string; const ALabels, ADefaults: array of string;
  out AValues: TStrArray): Boolean;
var
  f: TForm;
  eds: array of TEdit;
  lbl: TLabel;
  bOk, bCancel: TButton;
  i, y: Integer;
begin
  Result := False;
  SetLength(AValues, Length(ALabels));
  SetLength(eds, Length(ALabels));
  f := TForm.CreateNew(nil);
  try
    f.Caption := ATitle;
    f.BorderStyle := bsDialog;
    f.Position := poScreenCenter;
    f.ClientWidth := 470;
    y := 12;
    for i := 0 to High(ALabels) do
    begin
      lbl := TLabel.Create(f); lbl.Parent := f;
      lbl.SetBounds(12, y + 4, 140, 18); lbl.Caption := ALabels[i];
      eds[i] := TEdit.Create(f); eds[i].Parent := f;
      eds[i].SetBounds(156, y, 300, 24); eds[i].AutoSize := False;
      if i <= High(ADefaults) then eds[i].Text := ADefaults[i];
      Inc(y, 30);
    end;
    Inc(y, 8);
    bOk := TButton.Create(f); bOk.Parent := f;
    bOk.SetBounds(f.ClientWidth - 178, y, 80, 28);
    bOk.Caption := 'OK'; bOk.Default := True; bOk.ModalResult := mrOk;
    bCancel := TButton.Create(f); bCancel.Parent := f;
    bCancel.SetBounds(f.ClientWidth - 90, y, 80, 28);
    bCancel.Caption := 'Cancel'; bCancel.Cancel := True; bCancel.ModalResult := mrCancel;
    f.ClientHeight := y + 40;
    if Length(eds) > 0 then f.ActiveControl := eds[0];
    if f.ShowModal = mrOk then
    begin
      for i := 0 to High(eds) do AValues[i] := Trim(eds[i].Text);
      Result := True;
    end;
  finally
    f.Free;
  end;
end;

function AskNmap(out AOpts: TNmapOpts): Boolean;
var
  f: TForm;
  edTarget, edPorts: TEdit;
  cbScan, cbTiming: TComboBox;
  ckSV, ckO, ckSC, ckA, ckPn, ckOpen, ckV: TCheckBox;
  bOk, bCancel: TButton;
  y: Integer;

  function Lbl(const c: string; x, yy, w: Integer): TLabel;
  begin
    Result := TLabel.Create(f); Result.Parent := f;
    Result.SetBounds(x, yy + 4, w, 18); Result.Caption := c;
  end;
  function Chk(const c: string; x, yy: Integer): TCheckBox;
  begin
    Result := TCheckBox.Create(f); Result.Parent := f;
    Result.SetBounds(x, yy, 220, 20); Result.Caption := c;
  end;

begin
  Result := False;
  FillChar(AOpts, SizeOf(AOpts), 0);
  f := TForm.CreateNew(nil);
  try
    f.Caption := 'nmap Command Builder';
    f.BorderStyle := bsDialog;
    f.Position := poScreenCenter;
    f.ClientWidth := 470;

    y := 12;
    Lbl('Target', 12, y, 90);
    edTarget := TEdit.Create(f); edTarget.Parent := f;
    edTarget.SetBounds(108, y, 348, 24); edTarget.AutoSize := False;
    edTarget.Text := '192.168.1.0/24';
    Inc(y, 32);

    Lbl('Scan type', 12, y, 90);
    cbScan := TComboBox.Create(f); cbScan.Parent := f;
    cbScan.SetBounds(108, y, 348, 24); cbScan.Style := csDropDownList;
    cbScan.Items.Add('TCP SYN (-sS, needs root)');
    cbScan.Items.Add('TCP connect (-sT)');
    cbScan.Items.Add('UDP (-sU)');
    cbScan.Items.Add('Ping sweep, no port scan (-sn)');
    cbScan.Items.Add('List targets only (-sL)');
    cbScan.ItemIndex := 0;
    Inc(y, 32);

    Lbl('Ports', 12, y, 90);
    edPorts := TEdit.Create(f); edPorts.Parent := f;
    edPorts.SetBounds(108, y, 348, 24); edPorts.AutoSize := False;
    edPorts.TextHint := '22,80,443  |  1-1000  |  -  (all)  |  top:1000';
    Inc(y, 32);

    Lbl('Timing', 12, y, 90);
    cbTiming := TComboBox.Create(f); cbTiming.Parent := f;
    cbTiming.SetBounds(108, y, 348, 24); cbTiming.Style := csDropDownList;
    cbTiming.Items.Add('-T0 (paranoid)');
    cbTiming.Items.Add('-T1 (sneaky)');
    cbTiming.Items.Add('-T2 (polite)');
    cbTiming.Items.Add('-T3 (normal)');
    cbTiming.Items.Add('-T4 (aggressive)');
    cbTiming.Items.Add('-T5 (insane)');
    cbTiming.ItemIndex := 4;
    Inc(y, 36);

    ckSV := Chk('Service / version (-sV)', 12, y);
    ckPn := Chk('Skip host discovery (-Pn)', 240, y); Inc(y, 24);
    ckO := Chk('OS detection (-O)', 12, y);
    ckOpen := Chk('Only open ports (--open)', 240, y); Inc(y, 24);
    ckSC := Chk('Default scripts (-sC)', 12, y);
    ckV := Chk('Verbose (-v)', 240, y); Inc(y, 24);
    ckA := Chk('Aggressive (-A = -sV -O -sC)', 12, y); Inc(y, 32);

    bOk := TButton.Create(f); bOk.Parent := f;
    bOk.SetBounds(f.ClientWidth - 178, y, 80, 28);
    bOk.Caption := 'OK'; bOk.Default := True; bOk.ModalResult := mrOk;
    bCancel := TButton.Create(f); bCancel.Parent := f;
    bCancel.SetBounds(f.ClientWidth - 90, y, 80, 28);
    bCancel.Caption := 'Cancel'; bCancel.Cancel := True; bCancel.ModalResult := mrCancel;
    f.ClientHeight := y + 40;
    f.ActiveControl := edTarget;

    if f.ShowModal = mrOk then
    begin
      if Trim(edTarget.Text) = '' then Exit;
      AOpts.Target := Trim(edTarget.Text);
      AOpts.Scan := TNmapScan(cbScan.ItemIndex);
      AOpts.Ports := Trim(edPorts.Text);
      AOpts.Timing := cbTiming.ItemIndex;
      AOpts.SvcVersion := ckSV.Checked;
      AOpts.OsDetect := ckO.Checked;
      AOpts.DefScripts := ckSC.Checked;
      AOpts.Aggressive := ckA.Checked;
      AOpts.NoPing := ckPn.Checked;
      AOpts.OnlyOpen := ckOpen.Checked;
      AOpts.Verbose := ckV.Checked;
      Result := True;
    end;
  finally
    f.Free;
  end;
end;

function AskHttp(ADefaultTLS: Boolean; out AReq: THttpReq): Boolean;
var
  f: TForm;
  cbMethod: TComboBox;
  edHost, edConnect, edPort, edPath, edCT: TEdit;
  ckTLS: TCheckBox;
  meHeaders, meBody: TMemo;
  bOk, bCancel: TButton;
  y: Integer;

  function Lbl(const c: string; yy: Integer): TLabel;
  begin
    Result := TLabel.Create(f); Result.Parent := f;
    Result.SetBounds(12, yy + 4, 96, 18); Result.Caption := c;
  end;
  function Ed(yy, w: Integer): TEdit;
  begin
    Result := TEdit.Create(f); Result.Parent := f;
    Result.SetBounds(112, yy, w, 24); Result.AutoSize := False;
  end;

begin
  Result := False;
  FillChar(AReq, SizeOf(AReq), 0);
  f := TForm.CreateNew(nil);
  try
    f.Caption := 'HTTP Request Builder';
    f.BorderStyle := bsDialog;
    f.Position := poScreenCenter;
    f.ClientWidth := 470;

    y := 12;
    Lbl('Method', y);
    cbMethod := TComboBox.Create(f); cbMethod.Parent := f;
    cbMethod.SetBounds(112, y, 150, 24); cbMethod.Style := csDropDownList;
    cbMethod.Items.CommaText := 'GET,POST,HEAD,PUT,DELETE,OPTIONS,PATCH';
    cbMethod.ItemIndex := 0;
    ckTLS := TCheckBox.Create(f); ckTLS.Parent := f;
    ckTLS.SetBounds(280, y + 2, 170, 20); ckTLS.Caption := 'TLS (openssl s_client)';
    ckTLS.Checked := ADefaultTLS;
    Inc(y, 32);
    Lbl('Host (vhost)', y);
    edHost := Ed(y, 344); edHost.Text := 'www.example.com';
    Inc(y, 30);
    Lbl('Connect to', y);
    edConnect := Ed(y, 344); edConnect.TextHint := 'IP/host if different from vhost (else = Host)';
    Inc(y, 30);
    Lbl('Port', y);
    edPort := Ed(y, 150); edPort.TextHint := '80 / 443';
    Lbl('', y);
    edCT := TEdit.Create(f); edCT.Parent := f; edCT.AutoSize := False;
    edCT.SetBounds(280, y, 176, 24);
    edCT.TextHint := 'Content-Type (body)';
    Inc(y, 30);
    Lbl('Path', y);
    edPath := Ed(y, 344); edPath.Text := '/';
    Inc(y, 32);
    Lbl('Headers', y);
    meHeaders := TMemo.Create(f); meHeaders.Parent := f;
    meHeaders.SetBounds(112, y, 344, 52);
    meHeaders.ScrollBars := ssVertical;
    meHeaders.Lines.Text := '';
    Inc(y, 60);
    Lbl('Body', y);
    meBody := TMemo.Create(f); meBody.Parent := f;
    meBody.SetBounds(112, y, 344, 64);
    meBody.ScrollBars := ssVertical;
    Inc(y, 74);

    bOk := TButton.Create(f); bOk.Parent := f;
    bOk.SetBounds(f.ClientWidth - 178, y, 80, 28);
    bOk.Caption := 'OK'; bOk.Default := True; bOk.ModalResult := mrOk;
    bCancel := TButton.Create(f); bCancel.Parent := f;
    bCancel.SetBounds(f.ClientWidth - 90, y, 80, 28);
    bCancel.Caption := 'Cancel'; bCancel.Cancel := True; bCancel.ModalResult := mrCancel;
    f.ClientHeight := y + 40;
    f.ActiveControl := edHost;

    if f.ShowModal = mrOk then
    begin
      AReq.Method := cbMethod.Text;
      AReq.Host := Trim(edHost.Text);
      AReq.ConnectHost := Trim(edConnect.Text);
      AReq.Port := StrToIntDef(Trim(edPort.Text), 0);
      AReq.Path := Trim(edPath.Text);
      AReq.TLS := ckTLS.Checked;
      AReq.ExtraHeaders := meHeaders.Lines.Text;
      AReq.ContentType := Trim(edCT.Text);
      AReq.Body := meBody.Lines.Text;
      Result := True;
    end;
  finally
    f.Free;
  end;
end;

end.
