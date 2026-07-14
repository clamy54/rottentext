unit uHttp;

{$mode objfpc}{$H+}

// Requete HTTP brute a coller dans nc/telnet/openssl s_client. Content-Length =
// octets du corps tel quel : buffer en LF et service en CRLF = longueur fausse.

interface

type
  THttpReq = record
    Method: string;
    Host: string;         // en-tete Host (le vhost)
    ConnectHost: string;  // hote/IP de connexion ('' = Host)
    Port: Integer;
    Path: string;
    TLS: Boolean;
    ExtraHeaders: string; // une par ligne 'Name: value'
    ContentType: string;
    Body: string;
  end;

function BuildHttpRequest(const R: THttpReq): string;

implementation

uses
  Classes, SysUtils;

function BuildHttpRequest(const R: THttpReq): string;
var
  sb, hdrs: TStringList;
  method, path, host, chost, ct: string;
  port, i: Integer;
  hasBody: Boolean;
begin
  method := UpperCase(Trim(R.Method));
  if method = '' then method := 'GET';
  path := Trim(R.Path);
  if path = '' then path := '/';
  if path[1] <> '/' then path := '/' + path;
  host := Trim(R.Host);
  chost := Trim(R.ConnectHost);
  if chost = '' then chost := host;
  if chost = '' then chost := 'HOST';
  port := R.Port;
  if port <= 0 then
    if R.TLS then port := 443 else port := 80;
  hasBody := (R.Body <> '') and (method <> 'GET') and (method <> 'HEAD');

  sb := TStringList.Create;
  hdrs := TStringList.Create;
  try
    if R.TLS then
      sb.Add(Format('# connect: openssl s_client -connect %s:%d -crlf -quiet',
        [chost, port]))
    else
      sb.Add(Format('# connect: nc %s %d   (or: telnet %s %d)',
        [chost, port, chost, port]));
    sb.Add(Format('%s %s HTTP/1.1', [method, path]));
    if host <> '' then sb.Add('Host: ' + host)
    else sb.Add('Host: HOST');
    sb.Add('User-Agent: rottentext/1.0');
    sb.Add('Accept: */*');
    hdrs.Text := R.ExtraHeaders;
    for i := 0 to hdrs.Count - 1 do
      if Trim(hdrs[i]) <> '' then sb.Add(Trim(hdrs[i]));
    if hasBody then
    begin
      ct := Trim(R.ContentType);
      if ct = '' then ct := 'application/x-www-form-urlencoded';
      sb.Add('Content-Type: ' + ct);
      sb.Add('Content-Length: ' + IntToStr(Length(R.Body)));
    end;
    sb.Add('Connection: close');
    sb.Add('');
    if hasBody then sb.Add(R.Body);
    Result := sb.Text;
  finally
    hdrs.Free;
    sb.Free;
  end;
end;

end.
