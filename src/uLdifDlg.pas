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
  Classes, SysUtils, Math, Controls, StdCtrls, Forms, Dialogs,
  uTheme, uThemedControls, uRtMessage;

const
  // index combo (1..10) -> schema ; index 0 = aucun mot de passe
  SchemeMap: array[1..10] of TLdapPwScheme =
    (lpsSSHA, lpsSSHA256, lpsSSHA512, lpsCrypt, lpsArgon2LibArgon2,
     lpsArgon2LibSodium, lpsSHA, lpsSMD5, lpsMD5, lpsSASL);

// colonne a la largeur du plus long texte: la police de l'interface est plus
// large que celle du systeme
function ColWidth(const ATexts: array of string; AMin, APad: Integer): Integer;
var
  i: Integer;
begin
  Result := AMin;
  for i := 0 to High(ATexts) do
    Result := Max(Result, DialogTextWidth(ATexts[i]) + APad);
end;

type
  TLdifForm = class(TForm)
  public
    LblW: Integer;
    edDn, edCn, edSn, edGiven, edDisplay, edUid, edMail, edTel, edTitle,
      edO, edOu, edDesc: TEdit;
    cbPosix: TThemedCheck;
    edUidN, edGidN, edHome, edShell, edGecos: TEdit;
    cbScheme: TThemedCombo;
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
  Invalidate; // cadres des champs
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
    RtMessageDlg('RottenText', err, mtWarning, [mbOK], 0);
    Exit;   // formulaire reste ouvert
  end;
  ModalResult := mrOk;
end;

function AddEd(f: TLdifForm; const cap: string; x, y, ew: Integer): TEdit;
var
  l: TLabel;
begin
  l := TLabel.Create(f); l.Parent := f; l.SetBounds(x, y + 4, f.LblW, 18);
  l.Caption := cap;
  Result := TEdit.Create(f); Result.Parent := f;
  Result.SetBounds(x + f.LblW + 4, y, ew, 24); Result.AutoSize := False;
end;

function AskLdifPerson(out P: TLdifPerson; out AWantPw: Boolean;
  out AScheme: TLdapPwScheme): Boolean;
var
  f: TLdifForm;
  bOk, bCancel: TThemedButton;
  lblS: TLabel;
  colA, colB, y: Integer;
begin
  Result := False;
  AWantPw := False;
  AScheme := lpsSSHA;
  f := TLdifForm.CreateNew(nil);
  try
    f.Caption := 'LDIF Entry';
    f.BorderStyle := bsDialog;
    f.Position := poScreenCenter;
    f.LblW := ColWidth(['displayName', 'homeDirectory', 'userPassword',
      'description', 'telephone'], 92, 8);
    colA := 12; colB := colA + f.LblW + 4 + 200 + 16;
    f.ClientWidth := colB + f.LblW + 4 + 200 + 12;

    y := 12;
    f.edDn := AddEd(f, 'dn', colA, y, f.ClientWidth - 12 - (colA + f.LblW + 4));
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

    f.cbPosix := TThemedCheck.Create(f); f.cbPosix.Parent := f;
    f.cbPosix.Caption := 'Include posixAccount (Unix account)';
    f.cbPosix.SetBounds(colA, y, ColWidth([f.cbPosix.Caption], 300, 34), 20);
    f.cbPosix.OnChange := @f.PosixToggle; Inc(y, 28);

    f.edUidN := AddEd(f, 'uidNumber', colA, y, 200);
    f.edGidN := AddEd(f, 'gidNumber', colB, y, 200); Inc(y, 30);
    f.edHome := AddEd(f, 'homeDirectory', colA, y, 200);
    f.edHome.TextHint := '/home/jdoe';
    f.edShell := AddEd(f, 'loginShell', colB, y, 200);
    f.edShell.Text := '/bin/bash'; Inc(y, 30);
    f.edGecos := AddEd(f, 'gecos', colA, y, 200); Inc(y, 34);

    lblS := TLabel.Create(f); lblS.Parent := f;
    lblS.SetBounds(colA, y + 4, f.LblW, 18); lblS.Caption := 'userPassword';
    f.cbScheme := TThemedCombo.Create(f); f.cbScheme.Parent := f;
    f.cbScheme.SetBounds(colA + f.LblW + 4, y, 200, 24);
    f.cbScheme.Style := csDropDownList;
    // pas de CommaText : il coupe AUSSI sur les espaces, un libelle a espace ferait 2 items
    f.cbScheme.Items.Add('(none)');
    f.cbScheme.Items.Add('SSHA');
    f.cbScheme.Items.Add('SSHA-256');
    f.cbScheme.Items.Add('SSHA-512');
    f.cbScheme.Items.Add('CRYPT');
    f.cbScheme.Items.Add('ARGON2 (libargon2)');
    f.cbScheme.Items.Add('ARGON2 (libsodium)');
    f.cbScheme.Items.Add('SHA');
    f.cbScheme.Items.Add('SMD5');
    f.cbScheme.Items.Add('MD5');
    f.cbScheme.Items.Add('SASL');
    f.cbScheme.ItemIndex := 0;
    Inc(y, 40);

    bOk := TThemedButton.Create(f); bOk.Parent := f;
    bOk.SetBounds(f.ClientWidth - 178, y, 80, 28);
    bOk.Caption := 'OK'; bOk.Default := True; bOk.OnClick := @f.DoOK;
    bCancel := TThemedButton.Create(f); bCancel.Parent := f;
    bCancel.SetBounds(f.ClientWidth - 90, y, 80, 28);
    bCancel.Caption := 'Cancel'; bCancel.Cancel := True;
    bCancel.ModalResult := mrCancel;

    f.ClientHeight := y + 40;
    f.PosixToggle(nil);
    f.ActiveControl := f.edDn;
    ThemeDialog(f);

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
  bOk, bCancel: TThemedButton;
  i, y, lw, ew: Integer;
begin
  Result := False;
  SetLength(AValues, Length(ALabels));
  SetLength(eds, Length(ALabels));
  f := TForm.CreateNew(nil);
  try
    f.Caption := ATitle;
    f.BorderStyle := bsDialog;
    f.Position := poScreenCenter;
    lw := ColWidth(ALabels, 140, 8);
    // le defaut le plus long tient dans son champ
    ew := Min(ColWidth(ADefaults, 300, 32), 560);
    f.ClientWidth := 12 + lw + 4 + ew + 14;
    y := 12;
    for i := 0 to High(ALabels) do
    begin
      lbl := TLabel.Create(f); lbl.Parent := f;
      lbl.SetBounds(12, y + 4, lw, 18); lbl.Caption := ALabels[i];
      eds[i] := TEdit.Create(f); eds[i].Parent := f;
      eds[i].SetBounds(12 + lw + 4, y, ew, 24); eds[i].AutoSize := False;
      if i <= High(ADefaults) then eds[i].Text := ADefaults[i];
      Inc(y, 30);
    end;
    Inc(y, 8);
    bOk := TThemedButton.Create(f); bOk.Parent := f;
    bOk.SetBounds(f.ClientWidth - 178, y, 80, 28);
    bOk.Caption := 'OK'; bOk.Default := True; bOk.ModalResult := mrOk;
    bCancel := TThemedButton.Create(f); bCancel.Parent := f;
    bCancel.SetBounds(f.ClientWidth - 90, y, 80, 28);
    bCancel.Caption := 'Cancel'; bCancel.Cancel := True; bCancel.ModalResult := mrCancel;
    f.ClientHeight := y + 40;
    if Length(eds) > 0 then f.ActiveControl := eds[0];
    ThemeDialog(f);
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
const
  PORTS_HINT = '22,80,443  |  1-1000  |  -  (all)  |  top:1000';
var
  f: TForm;
  edTarget, edPorts: TEdit;
  cbScan, cbTiming: TThemedCombo;
  ckSV, ckO, ckSC, ckA, ckPn, ckOpen, ckV: TThemedCheck;
  bOk, bCancel: TThemedButton;
  y, lw, x0, ew, col2: Integer;

  function Lbl(const c: string; x, yy, w: Integer): TLabel;
  begin
    Result := TLabel.Create(f); Result.Parent := f;
    Result.SetBounds(x, yy + 4, w, 18); Result.Caption := c;
  end;
  function Chk(const c: string; x, yy: Integer): TThemedCheck;
  begin
    Result := TThemedCheck.Create(f); Result.Parent := f;
    Result.SetBounds(x, yy, ColWidth([c], 0, 34), 20); Result.Caption := c;
  end;

begin
  Result := False;
  FillChar(AOpts, SizeOf(AOpts), 0);
  f := TForm.CreateNew(nil);
  try
    f.Caption := 'nmap Command Builder';
    f.BorderStyle := bsDialog;
    f.Position := poScreenCenter;
    lw := ColWidth(['Target', 'Scan type', 'Ports', 'Timing'], 90, 8);
    x0 := 12 + lw + 6;
    ew := ColWidth([PORTS_HINT], 348, 32);
    // seconde colonne de cases: apres la plus longue de la premiere
    col2 := 12 + ColWidth(['Service / version (-sV)', 'OS detection (-O)',
      'Default scripts (-sC)'], 220, 34) + 8;
    f.ClientWidth := Max(x0 + ew + 14, col2 + ColWidth(
      ['Skip host discovery (-Pn)', 'Only open ports (--open)'], 0, 34) + 12);
    ew := f.ClientWidth - 14 - x0;

    y := 12;
    Lbl('Target', 12, y, lw);
    edTarget := TEdit.Create(f); edTarget.Parent := f;
    edTarget.SetBounds(x0, y, ew, 24); edTarget.AutoSize := False;
    edTarget.Text := '192.168.1.0/24';
    Inc(y, 32);

    Lbl('Scan type', 12, y, lw);
    cbScan := TThemedCombo.Create(f); cbScan.Parent := f;
    cbScan.SetBounds(x0, y, ew, 24); cbScan.Style := csDropDownList;
    cbScan.Items.Add('TCP SYN (-sS, needs root)');
    cbScan.Items.Add('TCP connect (-sT)');
    cbScan.Items.Add('UDP (-sU)');
    cbScan.Items.Add('Ping sweep, no port scan (-sn)');
    cbScan.Items.Add('List targets only (-sL)');
    cbScan.ItemIndex := 0;
    Inc(y, 32);

    Lbl('Ports', 12, y, lw);
    edPorts := TEdit.Create(f); edPorts.Parent := f;
    edPorts.SetBounds(x0, y, ew, 24); edPorts.AutoSize := False;
    edPorts.TextHint := PORTS_HINT;
    Inc(y, 32);

    Lbl('Timing', 12, y, lw);
    cbTiming := TThemedCombo.Create(f); cbTiming.Parent := f;
    cbTiming.SetBounds(x0, y, ew, 24); cbTiming.Style := csDropDownList;
    cbTiming.Items.Add('-T0 (paranoid)');
    cbTiming.Items.Add('-T1 (sneaky)');
    cbTiming.Items.Add('-T2 (polite)');
    cbTiming.Items.Add('-T3 (normal)');
    cbTiming.Items.Add('-T4 (aggressive)');
    cbTiming.Items.Add('-T5 (insane)');
    cbTiming.ItemIndex := 4;
    Inc(y, 36);

    ckSV := Chk('Service / version (-sV)', 12, y);
    ckPn := Chk('Skip host discovery (-Pn)', col2, y); Inc(y, 24);
    ckO := Chk('OS detection (-O)', 12, y);
    ckOpen := Chk('Only open ports (--open)', col2, y); Inc(y, 24);
    ckSC := Chk('Default scripts (-sC)', 12, y);
    ckV := Chk('Verbose (-v)', col2, y); Inc(y, 24);
    ckA := Chk('Aggressive (-A = -sV -O -sC)', 12, y); Inc(y, 32);

    bOk := TThemedButton.Create(f); bOk.Parent := f;
    bOk.SetBounds(f.ClientWidth - 178, y, 80, 28);
    bOk.Caption := 'OK'; bOk.Default := True; bOk.ModalResult := mrOk;
    bCancel := TThemedButton.Create(f); bCancel.Parent := f;
    bCancel.SetBounds(f.ClientWidth - 90, y, 80, 28);
    bCancel.Caption := 'Cancel'; bCancel.Cancel := True; bCancel.ModalResult := mrCancel;
    f.ClientHeight := y + 40;
    f.ActiveControl := edTarget;
    ThemeDialog(f);

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
const
  CONNECT_HINT = 'IP/host if different from vhost (else = Host)';
  TLS_CAPTION = 'TLS (openssl s_client)';
  CT_HINT = 'Content-Type (body)';
var
  f: TForm;
  cbMethod: TThemedCombo;
  edHost, edConnect, edPort, edPath, edCT: TEdit;
  ckTLS: TThemedCheck;
  meHeaders, meBody: TMemo;
  bOk, bCancel: TThemedButton;
  y, lw, x0, ew: Integer;

  function Lbl(const c: string; yy: Integer): TLabel;
  begin
    Result := TLabel.Create(f); Result.Parent := f;
    Result.SetBounds(12, yy + 4, lw, 18); Result.Caption := c;
  end;
  function Ed(yy, w: Integer): TEdit;
  begin
    Result := TEdit.Create(f); Result.Parent := f;
    Result.SetBounds(x0, yy, w, 24); Result.AutoSize := False;
  end;

begin
  Result := False;
  FillChar(AReq, SizeOf(AReq), 0);
  f := TForm.CreateNew(nil);
  try
    f.Caption := 'HTTP Request Builder';
    f.BorderStyle := bsDialog;
    f.Position := poScreenCenter;
    lw := ColWidth(['Method', 'Host (vhost)', 'Connect to', 'Headers'], 96, 8);
    x0 := 12 + lw + 4;
    ew := Max(ColWidth([CONNECT_HINT], 344, 32),
      168 + ColWidth([TLS_CAPTION, CT_HINT], 176, 34));
    f.ClientWidth := x0 + ew + 14;

    y := 12;
    Lbl('Method', y);
    cbMethod := TThemedCombo.Create(f); cbMethod.Parent := f;
    cbMethod.SetBounds(x0, y, 150, 24); cbMethod.Style := csDropDownList;
    cbMethod.Items.CommaText := 'GET,POST,HEAD,PUT,DELETE,OPTIONS,PATCH';
    cbMethod.ItemIndex := 0;
    ckTLS := TThemedCheck.Create(f); ckTLS.Parent := f;
    ckTLS.SetBounds(x0 + 168, y + 2, ew - 168, 20); ckTLS.Caption := TLS_CAPTION;
    ckTLS.Checked := ADefaultTLS;
    Inc(y, 32);
    Lbl('Host (vhost)', y);
    edHost := Ed(y, ew); edHost.Text := 'www.example.com';
    Inc(y, 30);
    Lbl('Connect to', y);
    edConnect := Ed(y, ew); edConnect.TextHint := CONNECT_HINT;
    Inc(y, 30);
    Lbl('Port', y);
    edPort := Ed(y, 150); edPort.TextHint := '80 / 443';
    Lbl('', y);
    edCT := TEdit.Create(f); edCT.Parent := f; edCT.AutoSize := False;
    edCT.SetBounds(x0 + 168, y, ew - 168, 24);
    edCT.TextHint := CT_HINT;
    Inc(y, 30);
    Lbl('Path', y);
    edPath := Ed(y, ew); edPath.Text := '/';
    Inc(y, 32);
    Lbl('Headers', y);
    meHeaders := TMemo.Create(f); meHeaders.Parent := f;
    meHeaders.SetBounds(x0, y, ew, 52);
    meHeaders.ScrollBars := ssVertical;
    meHeaders.Lines.Text := '';
    Inc(y, 60);
    Lbl('Body', y);
    meBody := TMemo.Create(f); meBody.Parent := f;
    meBody.SetBounds(x0, y, ew, 64);
    meBody.ScrollBars := ssVertical;
    Inc(y, 74);

    bOk := TThemedButton.Create(f); bOk.Parent := f;
    bOk.SetBounds(f.ClientWidth - 178, y, 80, 28);
    bOk.Caption := 'OK'; bOk.Default := True; bOk.ModalResult := mrOk;
    bCancel := TThemedButton.Create(f); bCancel.Parent := f;
    bCancel.SetBounds(f.ClientWidth - 90, y, 80, 28);
    bCancel.Caption := 'Cancel'; bCancel.Cancel := True; bCancel.ModalResult := mrCancel;
    f.ClientHeight := y + 40;
    f.ActiveControl := edHost;
    ThemeDialog(f);

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
