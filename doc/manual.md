# RottenText

> A rotten editor for rotten files and rotten days.

## Read this first

If you write code for a living, there is nothing for you here. RottenText is a
rotten editor. It has no plugin marketplace, no AI copilot begging to autocomplete
your resignation letter, no 400 MB of Electron pretending to be a text editor. Go
find happiness elsewhere. Somewhere with a dark theme called "Cobalt2" and a
Discord server.

If you are a sysadmin in a hurry, stay. RottenText might save you ten seconds now
and then, several times a day. That is the entire value proposition. Ten seconds,
several times a day, for the rest of your on-call career. Do the math. Then don't,
because it's 3 AM and the phone is ringing again.

RottenText is a plain, fast text editor with a toolbox bolted to the side. The
editor part opens files and does not get in your way. The toolbox part is the
reason the thing exists: it does the small, annoying, error-prone conversions you
would otherwise do by pasting company secrets into a website called
`base64-decode-online-free.ru`.

Everything runs in-process. Nothing you type leaves the machine. No telemetry, no
"anonymous usage statistics", no phone-home. The only thing watching you type your
production root password into the htpasswd generator is you, and your conscience,
and possibly the neighbor across the street watching you through binoculars, but
that is between the three of you.

## Supported systems

Windows, Linux, and macOS. Same editor, same toolbox, same regrets, three
kernels.

## Getting it

### The lazy way

There are prebuilt packages on the releases page for the operating systems above.
Download the one for your platform, unpack it, run it. If you are the kind of
sysadmin who compiles everything from source "for security", we both know you
haven't read the source, so just grab the package.

Releases: https://github.com/clamy54/rottentext/releases

### Building from source

For the three people who insist. You need:

- **Lazarus** (tested with 4.8) and **FPC 3.2.2**.
- Lazarus packages: `SynEdit`, `LCL`, `Printer4Lazarus` (`lazbuild` pulls the
  transitive dependencies on its own).
- The **Monaspace Frozen** fonts in `fonts/`: 5 families times 4 styles, 20 TTF
  files total. The build compiles them into the binary as resources, so the final
  program carries its own fonts and does not care what garbage is installed on the
  host. Get them from the Monaspace release archive. Yes, all twenty. No, you
  cannot skip the italics.

Then:

- **Windows:** `powershell -File scripts\build.ps1` (add `-Release` for a lean
  build without debug symbols).
- **Linux and macOS:** `scripts/build.sh` (add `--release` for the same).

The build scripts find `lazbuild` on their own, use relative paths, and kill any
running instance before relinking, so they work from any machine and any
directory. If they don't, the machine is haunted and that is a hardware problem.

That kill is blunt and asks nothing: close your unsaved documents before you
rebuild, or they leave with the process.

**macOS, one extra step.** Compiling produces a bare binary, which macOS treats
with the suspicion it deserves. Run `scripts/make-app.sh` (also takes `--release`)
to get the full pipeline: build, wrap it in a `RottenText.app` bundle with the
theme and syntax data inside, generate the icon, write the `Info.plist`, and
ad-hoc sign it so Apple Silicon lets it run at all. The signature is ad-hoc, not
notarized, so if you copy the `.app` to another Mac, Gatekeeper will scream. On the
machine that built it, it just runs.

## The editor

The part that opens files. Kept deliberately boring. Highlights:

- **Tabs** for open documents, with a drag-to-reorder gesture and the usual close
  buttons. A dot instead of a cross means unsaved changes. A padlock means the
  file is read-only and your `sudo` is somewhere else.
- **Split view** into two columns, because you always need to look at the broken
  config and the working config at the same time to notice the one space that is
  different.
- **Minimap** on the right, for the illusion of an overview of a 40,000 line log
  you will never read.
- **Find and Replace** with case sensitivity, whole word, in-selection, and a live
  match counter in the status bar ("3/8 matches"), so you know exactly how many
  places you are about to break at once. No regular expressions. If you want regex
  find-and-replace across a whole file, you want a different tool and probably a
  change ticket.
- **Encoding support**: dozens of encodings, autodetected on open, with "Reopen
  with Encoding" for when the autodetector guesses wrong on that one file from the
  Windows 2003 box nobody will let you decommission.
- **Line endings** tracked per document and preserved on save, so opening a Unix
  file on Windows does not silently turn every line ending into CRLF and produce a
  diff with 12,000 changes and zero actual changes.
- **Tabs**: *View › Map Tab to Space* (on by default, and remembered across
  sessions) makes the Tab key insert spaces up to the next tab stop rather than a
  tab character. *Edit › Convert Tabs to Spaces* cleans up an existing file,
  selection or whole document. Both advance to the next tab stop instead of
  blindly dropping four spaces, so a tab in the middle of a line keeps its
  alignment and your columns do not drift. And if you do this to a Makefile it
  will ask for confirmation, because a Makefile recipe requires a real tab and
  converting it would break the file silently. That is the sort of detail you
  only learn once.
- **Hex view** for binary files, opened automatically when a file looks binary, or
  on demand. Find and replace bytes, jump to an offset, overwrite in place.
- **Syntax highlighting** for 40-odd languages, loaded from hand-written grammars.
  Big files skip automatic highlighting on purpose, because tokenizing a 156 MB
  log to make it pretty is not a feature, it is a denial of service against
  yourself.
- **Themes**: a dozen of them, switchable live. The menu bar stays light on every
  theme, on purpose. If it clashes with your dark theme, that's a deliberate
  choice, not a bug to file.
- **Sidebar** with an open-files list and a folder tree ("Open Folder"). The tree
  watches the disk on Windows and refreshes itself when a build or a log churns the
  directory under you.
- **Macros**: record a sequence of edits, play it back. For the day you have to
  make the same edit on 300 lines and copy-paste has failed you spiritually.
- **Fill with Lorem Ipsum** (Selection menu): fills the selection with lorem
  ipsum, preserving the line shape and never truncating a word. A selection of
  empty lines gets filled at 78 columns, meeting-ready. Officially it's
  for filler text: mockups, rendering tests, that kind of thing. Unofficially
  it's for looking like you took a great deal of notes during the meeting. From
  a distance it's perfectly convincing to the other attendees, especially since
  none of them knows who called this meeting or why. And yet you, you took an
  enormous amount of notes. In Latin.
- **Command Palette** (Ctrl+Shift+P): fuzzy search over every menu command,
  because your mouse might be dead for digging through the menus and you don't
  have enough RAM in your head to remember the keyboard shortcuts.
- **Sessions**: the window remembers what you had open and reopens it, including
  unsaved scratch notes, so the untitled tab where you were drafting the incident
  timeline survives a crash and, more importantly, survives you closing the window
  by reflex at the end of a 14 hour shift. It is a bit like your desk: if you leave
  the mess on it when you go, no reason it should be tidy when you come back.
- **Single instance**: opening a file from the file manager or the shell while
  RottenText is already running sends it to the existing window as a new tab,
  instead of stacking yet another window. No instance alive, or the instance busy
  asking you something in a dialog? The file opens normally, in its own window.
  Your click never goes nowhere.
- **Printing** with syntax colors, on white paper, for the auditor who wants "a
  hard copy of the firewall rules" and means it.

That's the editor. Now the part you came for.

## The Tools menu

This is the point of RottenText. The editor is the thing that holds the Tools
menu open.

Every tool runs locally. No tool sends anything anywhere. This matters, because
half of these operations are things people habitually do by pasting sensitive data
into a random web form, and then act surprised at the next breach post-mortem.

### How the tools decide what to work on

Before the list, the two conventions that govern every tool. Learn these once and
you will know how each one behaves without reading its paragraph.

- **Transforms** (hashing, encoding, escaping, and friends) work on your
  **selection if you have one, otherwise the current line**. They never silently
  eat the whole file. The result replaces the selection, or replaces the line.
  This is deliberate: a tool that hashed your entire 2 GB buffer because you forgot
  to select something is not a tool, it is malware.
- **Validators and reports** (JSON validate, cron explain, log summary, and so on)
  work on your **selection if you have one, otherwise the whole buffer**. Reports
  usually open in a **new tab** so they don't clobber your source. Some insert at
  the cursor, some copy to the clipboard, some just pop a message box. Each entry
  below says which.

Big buffers trip a confirmation prompt before anything expensive runs, so you get
one chance to reconsider before you ask it to parse a 900 MB "small config file".

### Command Palette

**Command Palette...** (also Ctrl+Shift+P). Searchable list of every command in
every menu, collected fresh each time it opens, recent files included. Type a few
letters, hit Enter. For when you know the tool exists but the submenu it lives in
has moved three times since you last needed it. We already saw this one in the
editor section, but I am putting it here again because I know full well you jumped
straight to the Tools part.

### Hashing and HMAC

- **Hash Selection** (MD5, SHA-1, SHA-256, SHA-512). Hashes the selection, or the
  current line, and replaces it with the hex digest. SHA-2 is hand-written, not
  borrowed, and checked against the NIST vectors, so it is correct even though you
  will never verify that claim.
- **Checksum of File...** (SHA-256, SHA-1, MD5). Pick a file, get a
  `<hash>  <filename>` line inserted at the cursor, in the exact format
  `sha256sum -c` expects. For the "please confirm the ISO downloaded intact"
  ritual ...
- **Insert Checksum Comment**. Hashes the **selection, or the current line**, and
  inserts a SHA-256 as a comment in the file. It deliberately never hashes the
  whole buffer, because a file cannot contain its own hash: the moment you inserted
  the comment, the hash would be wrong. You would have to be a real idiot to try
  that. The label tells you exactly what got hashed so nobody mistakes it for a
  verified whole-file digest six months later during the audit.
- **HMAC of Selection...** (SHA-256, SHA-1, SHA-512, MD5). Prompts for the secret
  key with a masked field, computes the HMAC of the selection or line. The key is
  never shown, never inserted, never logged, and is wiped from memory after use.
  The webhook signature you are debugging stays your problem and not the internet's.

### Encode / Decode

**Encode / Decode**: Base64, Base64 URL, URL percent, HTML entities, Hex, each way.
Works on the selection or the current line, replaces it with the result. Hex Decode
refuses to silently drop non-hex garbage instead of quietly deleting half your text
and letting you find out in production. This is the submenu you will use forty
times a day and never think about, which is the highest praise a rotten text
editor can earn.

### Escape For

**Escape Selection For**: Bash, PowerShell, JSON, YAML, SQL, sed (pattern), sed
(replacement), Regex (literal), systemd Exec line, nginx / Apache string. Takes the
selection or line and escapes it correctly for the target context. Because the
reason the deploy failed was one apostrophe in a password, inside a YAML string,
inside a Bash heredoc, inside an Ansible task, and you were never going to get all
four layers right by hand at midnight.

### Permissions

- **Convert Mode (rwx / octal)...**: turns `rwxr-x---` into `750` and back,
  setuid, setgid, and sticky bits included, tolerating the leading `-` from an
  `ls -l` paste. For when you are staring at a permission string trying to remember
  if `750` was the safe one or the one that opens the door.
- **umask Calculator...**: shows what a given umask actually produces for new files
  and directories, spelled out. Because umask is subtraction that isn't subtraction
  and everyone needs reassurance.

### Line Endings

**To LF (Unix)**, **To CRLF (Windows)**, **To CR (legacy Mac)**. Changes the whole
document's line-ending style, applied on the next save. The legacy Mac option is
there for the one file, on the one system, that will outlive us all. Also very
handy for deliberately annoying whoever you are about to send the file to.

### Generate

The randomness factory ... Secrets are generated with a real OS random source that
fails closed: if the system can't produce cryptographic randomness, it refuses
rather than handing you a predictable "password".

- **Password to Clipboard...** / **Insert Password...**: a generated password,
  either copied (default, so it doesn't land in the file you are editing) or
  inserted at the cursor.
- **UUID**, **Unix Timestamp**, **ISO 8601 (Local)**, **ISO 8601 (UTC)**: inserted
  at the cursor. The four things you paste into a ticket, a filename, or a log line
  twelve times a day.
- **Token (Hex / Base64 / base64url)** and **API Key...**: inserted at the cursor.
  Real entropy, right format, no padding surprises.
- **.htpasswd Entry...** (bcrypt, MD5 apr1, SHA-1): prompts for the password with a
  masked field, inserts only the finished `user:hash` line. Defaults to bcrypt,
  because it is still not 2009 and the "SHA-1 for compatibility" option is a trap
  you are choosing to walk into.
- **LDAP**: the whole LDAP grab-bag under one submenu. `userPassword...` values in
  the OpenLDAP slappasswd formats (SSHA and friends, salted, plus bcrypt via
  `{CRYPT}`, plus SASL passthrough), and full **LDIF** entry generators for a Root
  domain, an Organizational Unit, a Person or Account, a posixGroup, a
  groupOfNames, and a Service or Bind account. Passwords are entered masked, hashed,
  and only the hash reaches the LDIF. For when the directory server is down and,
  like a good sysadmin, you don't have a single decent backup on hand.
- **Protocol**: templates you paste into a terminal to poke a service by hand.
  Text protocols (HTTP, SMTP with and without STARTTLS, POP3, IMAP, FTP, Redis,
  NNTP, WHOIS, IRC, Memcached, SIP, Graphite, Beanstalkd, and their TLS variants)
  render as a ready-to-paste `telnet`, `nc`, or `openssl s_client` dialogue, first
  line a comment telling you how to connect. Binary protocols and HTTP APIs (LDAP,
  MySQL, PostgreSQL, PHP-FPM, Traefik, Docker, Kubernetes) render as the right
  client command instead, because you are not going to hand-speak the MySQL
  protocol into `nc` and we both know it. HTTP and HTTPS open a small request
  builder dialog (method, host, vhost, port, path, headers, body, with
  Content-Length filled in for you), so you can test a virtual host on a specific
  IP without editing your hosts file and forgetting to change it back.

### Structured text: JSON, XML, YAML, INI, TOML

The "why is this config not loading" family. They validate, they do not judge,
except when they judge.

- **JSON**: **Validate** (message box, tells you where it broke), **Format**,
  **Minify**, **Sort Keys**. Format/Minify/Sort work on the selection or the whole
  buffer, in place. Sort Keys is for making two configs diffable when one team
  decided key order was a personality.
- **XML**: **Validate** (well-formedness, with line and position) and **Format**.
  DOCTYPE and ENTITY declarations are rejected before parsing, on purpose, so a
  tiny hand-crafted entity bomb cannot freeze the editor. No, it is not being
  difficult, it is refusing to be your denial-of-service vector.
- **YAML**: **Validate** (message), **Flatten to Dotted Paths** (new tab, turns a
  nested tree into `a.b.c: value` lines you can grep), **Sort Keys...** (in place,
  warns you first because it drops comments and original formatting), and **Values
  Diff vs File...** (new tab, compares two YAML files key by key: only-in-A,
  only-in-B, changed). The last one is for "the values.yaml on staging and the one
  on prod are definitely identical" (they are not).
- **INI** and **TOML**: **Validate** (message), **Sort Keys** (in place, within
  each section or table, order preserved where it matters), **Find Duplicate Keys**
  (new tab, with line numbers, because the duplicate key that silently won is why
  the setting you changed did nothing).

### Kubernetes

- **Secret from key=value...** and **ConfigMap from key=value...**: reads the
  buffer, or the selection, as `KEY=value` lines (a `.env`, basically) and emits a
  proper Secret or ConfigMap manifest in a new tab, base64 for Secrets, plain for
  ConfigMaps. Names are validated as real DNS labels, so a typo becomes a rejection
  with a message instead of a manifest `kubectl` will reject after you have already
  told everyone it is deployed.
- **Decode Secret** and **Decode ConfigMap**: the other direction, into a new tab,
  base64 decoded, for reading what is actually in that Secret without the four-step
  `kubectl get -o jsonpath | base64 -d` incantation you look up every single time.

### .env files

The .env Swiss army knife, for the file format that has no spec and thirty
implementations.

- **Sort Keys**, **Quote Values**, **Unquote Values**: in place, undo-friendly.
- **Find Duplicate Keys**: new tab, with line numbers. Last one wins in dotenv, and
  that is never the one you meant.
- **Redact Secrets**: new tab, masks values that look secret and scrubs passwords
  out of any `scheme://user:pass@host` URL, including inside comments, before you
  paste the file into a ticket for "the vendor to look at". Best-effort heuristic,
  so read it before you share it, but it catches the obvious knife you were about
  to hand someone.
- **To JSON / From JSON**, **To YAML / From YAML**: convert the whole thing, into a
  new tab. Every producer routes through one safe emitter, so a value with a
  newline or an equals sign in it cannot inject a second fake line.

### Docker, Compose, Podman

- **Docker / Compose**: **List Images** (new tab, every `services.*.image` plus a
  unique repo/tag summary), **Environment to .env** (new tab, aggregates every
  service's environment block), **Set Image Tag...** (retags the `image:` line under
  the cursor, preserving indentation, quotes, digest, and trailing comment, because
  the retag that eats your `# pinned by security` comment is how the pin quietly
  dies).
- **Podman Quadlet**: the same three, for the systemd-unit `.container` format,
  reading `Image=` and `Environment=` with proper systemd-style parsing.

### Terraform and Helm

- **Terraform**: **List Variables** (new tab), **tfvars Skeleton** (new tab,
  required variables first with typed placeholders, optionals commented out), **Find
  Duplicate Variables** (new tab). Defaults on `sensitive` variables are redacted in
  both the report and the skeleton, so the secret does not leak into the tfvars you
  are about to commit. Yes, into the repo. Yes, that public one.
- **Helm**: the chart-author's regret kit. **Values Skeleton from Template** and
  **from Folder...** (scan `.Values.x.y` references, emit a minimal values.yaml in a
  new tab, folder version walks the whole `templates/` directory), **Values Path at
  Cursor** (copies the `.Values.a.b.c` for the line you are on to the clipboard),
  **Find Missing / Unused Values...** and the folder version (cross-check template
  references against a values.yaml: what is used but missing, what is defined but
  never referenced), **Wrap Value in quote** and **Value to toYaml | nindent...**
  (fix an existing line in place), and **Insert Snippet** (seven boilerplate blocks
  you retype from memory and get the indentation wrong on). All of this is a naive
  scan that does not resolve Helm's `with` and `range` scoping, and it says so, so
  treat it as a strong hint, not gospel.

### Network and time

- **IP / CIDR Calculator...**: IPv4 and IPv6. Network, broadcast, netmask,
  wildcard, host range, count, and address type, report inserted at the cursor.
  Source is the selection, otherwise it asks. For settling the "is `.31` in that
  subnet or not" argument before someone firewalls the wrong host ...
- **nmap Command Builder...**: builds an `nmap` command line from a dialog (scan
  type, ports, timing, the usual flags) and inserts it. It builds the command. It
  does not run it. Whether you have authorization to run it is between you and the
  owner of the target machine.
- **Timestamp Converter...**: scans the selection (or asks) for Unix timestamps,
  ISO 8601, Apache log time, and syslog time, and reports each one as Unix plus UTC
  plus local, with the delta between the first and last. Select two log lines, learn
  how long the outage actually was, cry accordingly.
- **Cron / Timer Explainer...**: explains a cron expression or a systemd
  `OnCalendar=` line in plain English and computes the next few run times. Source is
  the selection, otherwise the current line, otherwise it asks. For the `*/15 8-18 *
  * 1-5` you copied from somewhere and have never once been fully sure about.
- **JWT Inspector...**: decodes a JWT's header and payload into a new tab, with
  `exp`, `iat`, `nbf` in UTC and local and an expiry verdict. It does not verify the
  signature, cannot verify the signature without the key, and says so loudly at the
  top, so nobody quotes it as proof the token was valid.

### Mail routing

**Mail Trace**. Paste a full `.eml` (or just its headers) into a tab, run the
tool, and get the mail's journey rebuilt from its `Received:` headers in a new
tab: one ASCII box per server it crossed, the internal steps of a single machine
stacked inside it, arrows with the **delay between each hop**, and the total
transit time. It answers the two questions that matter: "where did this mail
sleep for four hours" and "which route did this spam take".


**Inspect Buffer / Selection** (reads PEM blocks from the text) and **Inspect
File...** (PEM or raw DER). Report into a new tab: subject, issuer, serial,
validity with an expiry verdict, key type and size, signature algorithm with weak
ones flagged, basic constraints, key usage, SANs, fingerprints. Mostly you will
use it to answer "when does this expire" three days after it already did.

### Extract, Log, Diff

- **Extract / Count**: pulls IPv4 addresses, URLs, emails, UUIDs, hex hashes, or
  hostnames (or all of them) out of the selection or the whole buffer, deduplicated
  and counted, into a new tab. Linear hand-written scanners, no regex, so it does
  not fall over on a 100 MB file. For turning a wall of log into "here are the 12
  distinct IPs that actually mattered".
- **Log**: the toolkit for the file you are actually staring at during the
  incident. **Normalize Timestamps** (rewrite every timestamp to one uniform local
  ISO format), **Sort by Timestamp** (even across mixed formats, with unstamped
  lines sticking to the stamped line above them so a stack trace follows its error),
  **Merge with File...** (interleave two logs by time, even unsorted), **Deltas
  Between Timestamps** (prefix each line with the gap since the previous stamped
  one, negative if the log went backwards, which it will), and **Summary** (line
  counts, time span, severity tally, top HTTP statuses, top IPs, top repeated
  errors). All into a new tab. This is the "correlate the app log and the proxy log
  and find the eight seconds where everything went wrong" tool.
- **Diff vs File...**: opens a live two-pane colored diff of the current buffer
  against a file you pick, aligned line by line, same-lines dark and changed-lines
  lit up. The left pane is editable, the right is the reference. Edit a left line
  until it matches and its highlight goes out immediately; insert or delete lines
  and the diff recomputes live, the alignment follows (the only price: the undo
  history restarts at that point). On close, if you changed the left side, it
  offers to integrate those edits back into your document. For reconciling the
  config that works with the config that doesn't, which is most of the job.

## A note on trust

Every tool above that touches a password, a key, or a certificate does it in
memory, on your machine, and forgets it when it is done. Nothing is uploaded.
Nothing is cached in a cloud you did not choose. The masked-entry tools never show,
insert, log, or copy the secret you typed. This is not a marketing feature, it is
the minimum bar, and the fact that it needs stating tells you everything about the
tools you were using before this one.

## License and credits

RottenText is released under the GPL-V2 license.

Developed by Cyril LAMY.

It uses the Monaspace font family: https://monaspace.githubnext.com/

Source and releases: https://github.com/clamy54/rottentext
