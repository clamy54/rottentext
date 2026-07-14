unit uProto;

{$mode objfpc}{$H+}

// Templates de dialogues de protocole ; 1re ligne = commentaire '#' de connexion.

interface

type
  TProtoKind = (pkHTTP, pkHTTPS, pkSMTP, pkSMTPStartTLS, pkSMTPS,
    pkPOP3, pkPOP3S, pkIMAP, pkIMAPS, pkFTP, pkFTPS, pkRedis,
    pkLDAP, pkMySQL, pkPostgres, pkPHPFPM, pkTraefik, pkDocker,
    pkNNTP, pkWHOIS, pkIRC, pkMemcached, pkSIP, pkCarbon, pkBeanstalkd,
    pkK8s);

function ProtoLabel(AKind: TProtoKind): string;
function ProtoScript(AKind: TProtoKind): string;
function ProtoScriptByTag(ATag: Integer): string;

implementation

uses
  SysUtils;

function ProtoLabel(AKind: TProtoKind): string;
begin
  case AKind of
    pkHTTP:         Result := 'HTTP';
    pkHTTPS:        Result := 'HTTPS (TLS)';
    pkSMTP:         Result := 'SMTP';
    pkSMTPStartTLS: Result := 'SMTP (STARTTLS)';
    pkSMTPS:        Result := 'SMTPS (TLS)';
    pkPOP3:         Result := 'POP3';
    pkPOP3S:        Result := 'POP3S (TLS)';
    pkIMAP:         Result := 'IMAP';
    pkIMAPS:        Result := 'IMAPS (TLS)';
    pkFTP:          Result := 'FTP';
    pkFTPS:         Result := 'FTPS (AUTH TLS)';
    pkRedis:        Result := 'Redis';
    pkLDAP:         Result := 'LDAP (ldapsearch)';
    pkMySQL:        Result := 'MySQL (mysql client)';
    pkPostgres:     Result := 'PostgreSQL (psql)';
    pkPHPFPM:       Result := 'PHP-FPM (FastCGI)';
    pkTraefik:      Result := 'Traefik API (curl)';
    pkDocker:       Result := 'Docker Engine API (curl)';
    pkNNTP:         Result := 'NNTP';
    pkWHOIS:        Result := 'WHOIS';
    pkIRC:          Result := 'IRC';
    pkMemcached:    Result := 'Memcached';
    pkSIP:          Result := 'SIP (OPTIONS ping)';
    pkCarbon:       Result := 'Graphite / Carbon';
    pkBeanstalkd:   Result := 'Beanstalkd';
    pkK8s:          Result := 'Kubernetes API (curl)';
    else            Result := '';
  end;
end;

function J(const A: array of string): string;
var
  i: Integer;
begin
  Result := '';
  for i := 0 to High(A) do
    Result := Result + A[i] + LineEnding;
end;

const
  HTTP_BODY: array[0..3] of string = (
    'GET / HTTP/1.1',
    'Host: HOST',
    'Connection: close',
    '');

  SMTP_BODY: array[0..10] of string = (
    'EHLO localhost',
    'MAIL FROM: <sender@domain.com>',
    'RCPT TO: <recipient@domain.com>',
    'DATA',
    'From: sender@domain.com',
    'To: recipient@domain.com',
    'Subject: This is a test',
    '',
    'Test message body.',
    '.',
    'QUIT');

  POP3_BODY: array[0..5] of string = (
    'USER username',
    'PASS password',
    'STAT',
    'LIST',
    'RETR 1',
    'QUIT');

  IMAP_BODY: array[0..4] of string = (
    'a1 LOGIN username password',
    'a2 LIST "" "*"',
    'a3 SELECT INBOX',
    'a4 FETCH 1 BODY[]',
    'a5 LOGOUT');

  FTP_BODY: array[0..4] of string = (
    'USER anonymous',
    'PASS anonymous@',
    'SYST',
    'PWD',
    'QUIT');

function ProtoScript(AKind: TProtoKind): string;
begin
  case AKind of
    pkHTTP:
      Result := '# connect: nc HOST 80   (or: telnet HOST 80)' + LineEnding +
        J(HTTP_BODY);
    pkHTTPS:
      Result := '# connect: openssl s_client -connect HOST:443 -crlf -quiet' +
        LineEnding + J(HTTP_BODY);
    pkSMTP:
      Result := '# connect: telnet HOST 25   (or: nc HOST 25)' + LineEnding +
        J(SMTP_BODY);
    pkSMTPStartTLS:
      Result := '# connect: openssl s_client -starttls smtp -connect HOST:587 -crlf' +
        LineEnding + J(SMTP_BODY);
    pkSMTPS:
      Result := '# connect: openssl s_client -connect HOST:465 -crlf' +
        LineEnding + J(SMTP_BODY);
    pkPOP3:
      Result := '# connect: telnet HOST 110   (or: nc HOST 110)' + LineEnding +
        J(POP3_BODY);
    pkPOP3S:
      Result := '# connect: openssl s_client -connect HOST:995 -crlf' +
        LineEnding + J(POP3_BODY);
    pkIMAP:
      Result := '# connect: telnet HOST 143   (or: nc HOST 143)' + LineEnding +
        J(IMAP_BODY);
    pkIMAPS:
      Result := '# connect: openssl s_client -connect HOST:993 -crlf' +
        LineEnding + J(IMAP_BODY);
    pkFTP:
      Result := '# connect: telnet HOST 21   (or: nc HOST 21)' + LineEnding +
        J(FTP_BODY);
    pkFTPS:
      Result := '# connect: openssl s_client -starttls ftp -connect HOST:21 -crlf' +
        LineEnding + J(FTP_BODY);
    pkRedis:
      Result := '# connect: nc HOST 6379   (or: redis-cli -h HOST)' + LineEnding +
        J(['PING',
           'INFO server',
           'CONFIG GET maxmemory',
           'DBSIZE',
           'QUIT']);
    pkLDAP:
      Result := '# LDAP is a binary protocol (BER) - use ldapsearch, not telnet/nc' +
        LineEnding +
        J(['ldapsearch -x -H ldap://HOST -b "dc=example,dc=org" -D "cn=admin,dc=example,dc=org" -W "(uid=jdoe)"',
           '# who am I (test a bind):',
           'ldapwhoami -x -H ldap://HOST -D "cn=admin,dc=example,dc=org" -W',
           '# anonymous root DSE (server info, no bind):',
           'ldapsearch -x -H ldap://HOST -s base -b "" "+"',
           '# over TLS:',
           'ldapsearch -x -H ldaps://HOST -b "dc=example,dc=org"']);
    pkMySQL:
      Result := '# MySQL is a binary protocol - use the mysql client, not telnet/nc' +
        LineEnding +
        J(['mysql -h HOST -P 3306 -u root -p',
           '# one-shot query (prompts for the password):',
           'mysql -h HOST -u root -p -e "SELECT VERSION(); SHOW DATABASES;"',
           '# connectivity check only:',
           'mysqladmin -h HOST -u root -p ping',
           '# require TLS:',
           'mysql -h HOST -u root -p --ssl-mode=REQUIRED']);
    pkPostgres:
      Result := '# PostgreSQL is a binary protocol - use psql, not telnet/nc' +
        LineEnding +
        J(['psql -h HOST -p 5432 -U postgres -c "SELECT version();"',
           '# connectivity check (no query):',
           'pg_isready -h HOST -p 5432',
           '# list databases:',
           'psql -h HOST -U postgres -l',
           '# require TLS:',
           'psql "host=HOST user=postgres sslmode=require"']);
    pkPHPFPM:
      Result := '# PHP-FPM speaks FastCGI (binary) - use cgi-fcgi, not telnet/nc' +
        LineEnding +
        J(['SCRIPT_NAME=/status SCRIPT_FILENAME=/status REQUEST_METHOD=GET cgi-fcgi -bind -connect HOST:9000',
           '# pool ping (ping.path, usually /ping):',
           'SCRIPT_NAME=/ping SCRIPT_FILENAME=/ping REQUEST_METHOD=GET cgi-fcgi -bind -connect HOST:9000',
           '# via a unix socket instead of HOST:9000:',
           'SCRIPT_NAME=/status SCRIPT_FILENAME=/status REQUEST_METHOD=GET cgi-fcgi -bind -connect /run/php/php-fpm.sock']);
    pkTraefik:
      Result := '# Traefik API / dashboard is HTTP - use curl' + LineEnding +
        J(['curl -s http://HOST:8080/ping',
           'curl -s http://HOST:8080/api/overview',
           'curl -s http://HOST:8080/api/http/routers',
           'curl -s http://HOST:8080/api/http/services']);
    pkDocker:
      Result := '# Docker Engine API - curl over the unix socket (or TCP+TLS)' +
        LineEnding +
        J(['curl -s --unix-socket /var/run/docker.sock http://localhost/version',
           'curl -s --unix-socket /var/run/docker.sock http://localhost/info',
           'curl -s --unix-socket /var/run/docker.sock http://localhost/containers/json',
           '# remote daemon over TLS:',
           'curl -s https://HOST:2376/version --cert cert.pem --key key.pem --cacert ca.pem']);
    pkNNTP:
      Result := '# connect: telnet HOST 119   (or: nc HOST 119)' + LineEnding +
        J(['MODE READER',
           'LIST',
           'GROUP comp.lang.pascal',
           'ARTICLE 1',
           'QUIT']);
    pkWHOIS:
      Result := '# connect: nc HOST 43   (whois server; type the query below, then Enter)' +
        LineEnding + J(['example.com']);
    pkIRC:
      Result := '# connect: nc HOST 6667   (or: telnet HOST 6667)' + LineEnding +
        J(['NICK testuser',
           'USER testuser 0 * :Test User',
           'JOIN #test',
           'PRIVMSG #test :hello',
           'QUIT :bye']);
    pkMemcached:
      Result := '# connect: nc HOST 11211   (or: telnet HOST 11211)' + LineEnding +
        J(['version',
           'stats',
           'set foo 0 60 3',
           'bar',
           'get foo',
           'quit']);
    pkSIP:
      Result := '# connect: nc -u HOST 5060   (SIP is usually UDP; OPTIONS ping)' +
        LineEnding +
        J(['OPTIONS sip:HOST SIP/2.0',
           'Via: SIP/2.0/UDP localhost:5060;branch=z9hG4bK-test',
           'From: <sip:test@localhost>;tag=1',
           'To: <sip:HOST>',
           'Call-ID: test-call-id@localhost',
           'CSeq: 1 OPTIONS',
           'Max-Forwards: 70',
           'Content-Length: 0',
           '']);
    pkCarbon:
      Result := '# connect: nc HOST 2003   (Carbon plaintext: "path value timestamp")' +
        LineEnding + J(['servers.web01.load 1.5 UNIXTIME']);
    pkBeanstalkd:
      Result := '# connect: nc HOST 11300   (or: telnet HOST 11300)' + LineEnding +
        J(['list-tubes',
           'stats',
           'use default',
           'put 0 0 60 5',
           'hello',
           'quit']);
    pkK8s:
      Result := '# Kubernetes API is HTTPS/REST - use curl with a token (or: kubectl)' +
        LineEnding +
        J(['# unauthenticated health / version:',
           'curl -sk https://HOST:6443/version',
           'curl -sk https://HOST:6443/healthz',
           '# from inside a pod (service account token):',
           'TOKEN=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)',
           'curl -s --cacert /var/run/secrets/kubernetes.io/serviceaccount/ca.crt \',
           '  -H "Authorization: Bearer $TOKEN" https://HOST:6443/api/v1/namespaces/default/pods',
           '# via kubectl proxy (no auth juggling):',
           'kubectl proxy --port=8001 &   # then:',
           'curl -s http://localhost:8001/api/v1/nodes']);
    else
      Result := '';
  end;
end;

function ProtoScriptByTag(ATag: Integer): string;
begin
  if (ATag < 0) or (ATag > Ord(High(TProtoKind))) then
    Result := ''
  else
    Result := ProtoScript(TProtoKind(ATag));
end;

end.
