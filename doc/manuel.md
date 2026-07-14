# RottenText

> Un éditeur pourri pour des fichiers pourris et des journées pourries.

## À lire d'abord

Si tu écris du code pour gagner ta vie, tu n'as rien à faire ici. RottenText est un
éditeur pourri. Pas de marketplace de plugins, pas de copilote IA qui te supplie
d'autocompléter ta lettre de démission, pas 400 Mo d'Electron déguisés en éditeur
de texte. Va trouver le bonheur ailleurs. Quelque part avec un thème sombre appelé
"Cobalt2" et un serveur Discord.

Si tu es un sysadmin pressé, reste. RottenText va peut-être te faire gagner dix
secondes de temps en temps, plusieurs fois par jour. C'est toute la proposition de
valeur. Dix secondes, plusieurs fois par jour, jusqu'à la fin de ta carrière
d'astreinte. Fais le calcul. Puis ne le fais pas, parce qu'il est 3 h du matin et
que le téléphone sonne encore.

RottenText est un éditeur de texte simple et rapide, avec une boîte à outils
boulonnée sur le côté. La partie éditeur ouvre des fichiers et ne se met pas en
travers de ton chemin. La partie boîte à outils est la raison pour laquelle ce truc
existe : elle fait les petites conversions pénibles et casse-gueule que tu ferais
sinon en collant les secrets de ta boîte dans un site qui s'appelle
`base64-decode-online-free.ru`.

Tout tourne en local, dans le process. Rien de ce que tu tapes ne quitte la
machine. Pas de télémétrie, pas de "statistiques d'usage anonymes", pas d'appel à
la maison. La seule chose qui te regarde taper le mot de passe root de la prod dans
le générateur htpasswd, c'est toi, ta conscience, et éventuellement ton voisin d'en face qui t'espionne avec ses jumelles,
mais ça, c'est entre vous trois.

## Systèmes supportés

Windows, Linux et macOS. Même éditeur, même boîte à outils, mêmes regrets, trois
noyaux.

## Comment l'obtenir

### La méthode des feignasses

Il y a des paquets précompilés sur la page des releases, pour les systèmes
ci-dessus. Télécharge celui de ta plateforme, décompresse, lance. Si tu es le genre
de sysadmin qui recompile tout depuis les sources "pour la sécurité", on sait tous
les deux que tu n'as pas lu les sources, alors prends juste le paquet.

Releases : https://github.com/clamy54/rottentext/releases

### Compiler depuis les sources

Pour les trois personnes qui insistent. Il te faut :

- **Lazarus** (testé avec la 4.8) et **FPC 3.2.2**.
- Les paquets Lazarus : `SynEdit`, `LCL`, `Printer4Lazarus` (`lazbuild` tire les
  dépendances transitives tout seul).
- Les polices **Monaspace Frozen** dans `fonts/` : 5 familles fois 4 styles, 20
  fichiers TTF au total. Le build les compile dans le binaire sous forme de
  ressources, donc le programme final embarque ses propres polices et se moque de
  ce qui traîne d'installé sur l'hôte. Récupère-les depuis l'archive de release de
  Monaspace. Oui, les vingt. Non, tu ne peux pas sauter les italiques.

Ensuite :

- **Windows :** `powershell -File scripts\build.ps1` (ajoute `-Release` pour un
  build allégé, sans symboles de debug).
- **Linux et macOS :** `scripts/build.sh` (ajoute `--release` pour la même chose).

Les scripts de build trouvent `lazbuild` tout seuls, utilisent des chemins
relatifs, et tuent l'instance en cours avant de relinker, donc ils marchent depuis
n'importe quelle machine et n'importe quel dossier. Si ce n'est pas le cas, la
machine est hantée et c'est un problème matériel.

Le kill est brutal et ne demande rien : ferme tes documents non enregistrés avant
de recompiler, sinon ils partent avec le process.

**macOS, une étape en plus.** Compiler produit un binaire nu, que macOS traite avec
la méfiance qu'il mérite. Lance `scripts/make-app.sh` (qui prend aussi `--release`)
pour le pipeline complet : build, emballage dans un bundle `RottenText.app` avec les
données de thèmes et de syntaxe à l'intérieur, génération de l'icône, écriture de
l'`Info.plist`, et signature ad-hoc pour qu'Apple Silicon accepte de le lancer tout
court. La signature est ad-hoc, pas notarisée, donc si tu copies le `.app` sur un
autre Mac, Gatekeeper va hurler. Sur la machine qui l'a compilé, ça se lance sans
histoires.

## L'éditeur

La partie qui ouvre des fichiers. Volontairement ennuyeuse. Les grandes lignes :

- **Onglets** pour les documents ouverts, avec un glisser-déposer pour les
  réordonner et les boutons de fermeture habituels. Un point à la place de la croix
  = modifications non enregistrées. Un cadenas = fichier en lecture seule et ton
  `sudo` est resté ailleurs.
- **Vue scindée** en deux colonnes, parce que tu as toujours besoin de regarder la
  config cassée et la config qui marche en même temps pour repérer l'unique espace
  qui diffère.
- **Minimap** à droite, pour l'illusion d'une vue d'ensemble sur un log de 40 000
  lignes que tu ne liras jamais.
- **Rechercher / Remplacer** avec sensibilité à la casse, mot entier, dans la
  sélection, et un compteur d'occurrences en direct dans la barre d'état
  ("3/8 matches"), pour savoir exactement combien d'endroits tu es sur le point de
  casser d'un coup. Pas d'expressions régulières. Si tu veux du chercher-remplacer
  en regex sur tout un fichier, tu veux un autre outil, et probablement un ticket de
  change.
- **Gestion des encodages** : des dizaines d'encodages, détectés à l'ouverture, avec
  "Reopen with Encoding" pour quand le détecteur se trompe sur ce fichier venu de la
  machine Windows 2003 que personne ne te laisse décommissionner.
- **Fins de ligne** suivies par document et préservées à l'enregistrement, pour
  qu'ouvrir un fichier Unix sous Windows ne transforme pas silencieusement chaque
  fin de ligne en CRLF et ne produise pas un diff de 12 000 changements pour zéro
  changement réel.
- **Tabulations** : *View › Map Tab to Space* (coché par défaut, et retenu d'une
  session à l'autre) fait que la touche Tab insère des espaces jusqu'au prochain
  taquet, pas une tabulation. *Edit › Convert Tabs to Spaces* fait le ménage dans
  un fichier existant, sélection ou document entier. Dans les deux cas, on avance
  jusqu'au prochain taquet plutôt que de poser bêtement quatre espaces : une
  tabulation en milieu de ligne garde donc son alignement, tes colonnes ne se
  décalent pas. Et si tu fais ça sur un Makefile, il te demandera confirmation,
  parce qu'une recette de Makefile exige une vraie tabulation et que la convertir
  la casserait en silence. C'est le genre de détail qu'on n'apprend qu'une fois.
- **Vue hexadécimale** pour les fichiers binaires, ouverte automatiquement quand un
  fichier a l'air binaire, ou à la demande. Rechercher et remplacer des octets,
  sauter à un offset, écraser sur place.
- **Coloration syntaxique** pour une quarantaine de langages, chargée depuis des
  grammaires écrites à la main. Les gros fichiers sautent la coloration automatique
  exprès, parce que tokeniser un log de 156 Mo pour le rendre joli n'est pas une
  fonctionnalité, c'est un déni de service contre toi-même.
- **Thèmes** : une douzaine, changeables à chaud. La barre de menu reste claire dans
  tous les thèmes, exprès. Si ça jure avec ton thème sombre, c'est un choix assumé,
  pas un bug à signaler.
- **Barre latérale** avec une liste des fichiers ouverts et une arborescence de
  dossier ("Open Folder"). L'arbre surveille le disque sous Windows et se rafraîchit
  quand un build ou un log remue le dossier sous tes pieds.
- **Macros** : enregistre une séquence d'édition, rejoue-la. Pour le jour où tu dois
  faire la même modif sur 300 lignes et où le copier-coller t'a lâché
  spirituellement.
- **Fill with Lorem Ipsum** (menu Selection) : remplit la sélection avec du lorem
  ipsum, en respectant la forme des lignes et sans jamais tronquer un mot. Une
  sélection de lignes vides est remplie à 78 colonnes, prête pour la réunion.
  Officiellement, c'est pour faire du texte de remplissage : maquettes, tests de
  rendu, ce genre de choses. Officieusement, c'est pour faire croire que tu as pris
  énormément de notes pendant la réunion. De loin, ça fait parfaitement illusion
  auprès des autres personnes conviées, d'autant qu'aucune d'entre elles ne sait
  qui a organisé cette réunion ni dans quel but. Et pourtant, toi, tu as pris
  énormément de notes. En latin.
- **Palette de commandes** (Ctrl+Shift+P) : recherche floue sur toutes les commandes
  de tous les menus, parce que ta souris est peut-être en panne pour aller chercher dans le menu et que tu n'as pas assez de RAM dans ta tête pour te souvenir des raccourcis clavier.
- **Sessions** : la fenêtre se souvient de ce que tu avais d'ouvert et le rouvre, y
  compris les notes de brouillon non enregistrées, pour que l'onglet sans titre où
  tu rédigeais la chronologie de l'incident survive à un crash et, surtout, survive
  à toi fermant la fenêtre par réflexe à la fin d'une garde de 14 heures.
  C'est un peu comme ton bureau. Si tu pars en laissant le merdier sur ton bureau, pas de raison qu'il soit rangé quand tu reviens.
- **Instance unique** : ouvrir un fichier depuis l'explorateur ou le shell alors que
  RottenText tourne déjà l'envoie dans la fenêtre existante, en nouvel onglet, au
  lieu d'empiler une énième fenêtre. Pas d'instance en vie, ou instance occupée à te
  poser une question dans un dialogue ? Le fichier s'ouvre normalement, dans sa
  propre fenêtre. Ton clic ne part jamais dans le vide.
- **Impression** avec les couleurs de syntaxe, sur papier blanc, pour l'auditeur qui
  veut "une copie papier des règles de firewall" et qui ne plaisante pas.

Voilà pour l'éditeur. Maintenant, la partie pour laquelle tu es venu.

## Le menu Tools

C'est là tout l'intérêt de RottenText. L'éditeur est le truc qui tient le menu Tools
ouvert.

Chaque outil tourne en local. Aucun outil n'envoie quoi que ce soit où que ce soit.
Ça compte, parce que la moitié de ces opérations sont des choses que les gens font
d'habitude en collant des données sensibles dans un formulaire web au hasard, avant
de s'étonner au post-mortem de la prochaine fuite.

### Comment les outils décident sur quoi travailler

Avant la liste, les deux conventions qui régissent chaque outil. Apprends-les une
fois et tu sauras comment chacun se comporte sans lire son paragraphe.

- **Les transformations** (hachage, encodage, échappement, et compagnie) travaillent
  sur ta **sélection si tu en as une, sinon la ligne courante**. Elles n'avalent
  jamais silencieusement tout le fichier. Le résultat remplace la sélection, ou
  remplace la ligne. C'est délibéré : un outil qui hacherait ton buffer de 2 Go
  parce que tu as oublié de sélectionner quelque chose n'est pas un outil, c'est un
  malware.
- **Les validateurs et rapports** (JSON validate, cron explain, log summary, et
  ainsi de suite) travaillent sur ta **sélection si tu en as une, sinon tout le
  buffer**. Les rapports s'ouvrent généralement dans un **nouvel onglet** pour ne pas
  écraser ta source. Certains insèrent au curseur, d'autres copient dans le
  presse-papiers, d'autres se contentent d'une boîte de message. Chaque entrée
  ci-dessous précise laquelle.

Les gros buffers déclenchent une confirmation avant que quoi que ce soit de coûteux
ne parte, pour te laisser une chance de te raviser avant de lui demander de parser
un "petit fichier de config" de 900 Mo.

### Palette de commandes

**Command Palette...** (aussi Ctrl+Shift+P). Liste avec recherche de toutes les
commandes de tous les menus, collectée à neuf à chaque ouverture, fichiers récents
compris. Tape quelques lettres, appuie sur Entrée. Pour quand tu sais que l'outil
existe mais que le sous-menu où il vit a déménagé trois fois depuis la dernière fois
que tu en as eu besoin. On avait déjà vu cette fonction dans la partie éditeur mais je la remets ici car je sais très bien que tu as directement sauté à la partie tools.

### Hachage et HMAC

- **Hash Selection** (MD5, SHA-1, SHA-256, SHA-512). Hache la sélection, ou la ligne
  courante, et la remplace par le condensat en hexadécimal. SHA-2 est écrit à la
  main, pas emprunté, et vérifié contre les vecteurs NIST, donc c'est correct même
  si tu ne vérifieras jamais cette affirmation.
- **Checksum of File...** (SHA-256, SHA-1, MD5). Choisis un fichier, obtiens une
  ligne `<hash>  <nom>` insérée au curseur, au format exact que `sha256sum -c`
  attend. Pour le rituel du "confirme que l'ISO s'est bien téléchargée" ...
- **Insert Checksum Comment**. Hache la **sélection, ou la ligne courante**, et
  insère un SHA-256 en commentaire dans le fichier. Il ne hache
  délibérément jamais tout le buffer, parce qu'un fichier ne peut pas contenir son
  propre hash : à l'instant où tu insères le commentaire, le hash serait déjà faux. Faut vraiment être con pour tenter ça.
  Le libellé dit exactement ce qui a été haché, pour que personne ne le prenne pour
  un condensat vérifié du fichier entier six mois plus tard pendant l'audit.
- **HMAC of Selection...** (SHA-256, SHA-1, SHA-512, MD5). Demande la clé secrète
  dans un champ masqué, calcule le HMAC de la sélection ou de la ligne. La clé n'est
  jamais affichée, jamais insérée, jamais loggée, et est effacée de la mémoire après
  usage. La signature de webhook que tu débogues reste ton problème et pas celui
  d'internet.

### Encoder / Décoder

**Encode / Decode** : Base64, Base64 URL, URL percent, entités HTML, Hex, dans les
deux sens. Travaille sur la sélection ou la ligne courante, la remplace par le
résultat. Hex Decode refuse de jeter silencieusement les caractères non-hexa au
lieu de supprimer tranquillement la moitié de ton texte pour te le faire découvrir
en prod. C'est le sous-menu que tu utiliseras quarante fois par jour sans jamais y
penser, ce qui est le plus grand compliment qu'un éditeur de texte pourri puisse mériter.

### Échapper pour

**Escape Selection For** : Bash, PowerShell, JSON, YAML, SQL, sed (pattern), sed
(replacement), Regex (literal), systemd Exec line, nginx / Apache string. Prend la
sélection ou la ligne et l'échappe correctement pour le contexte cible. Parce que la
raison pour laquelle le déploiement a planté, c'était une apostrophe dans un mot de
passe, dans une chaîne YAML, dans un heredoc Bash, dans une tâche Ansible, et tu
n'allais jamais réussir les quatre couches à la main à minuit.

### Permissions

- **Convert Mode (rwx / octal)...** : transforme `rwxr-x---` en `750` et
  réciproquement, bits setuid, setgid et sticky compris, en tolérant le `-` de tête
  d'un copier-coller d'`ls -l`. Pour quand tu fixes une chaîne de permissions en
  essayant de te rappeler si `750` était la version sûre ou celle qui ouvre la
  porte.
- **umask Calculator...** : montre ce qu'un umask donné produit réellement pour les
  nouveaux fichiers et dossiers, écrit noir sur blanc. Parce que le umask est une
  soustraction qui n'en est pas une, et que tout le monde a besoin d'être rassuré.

### Fins de ligne

**To LF (Unix)**, **To CRLF (Windows)**, **To CR (legacy Mac)**. Change le style de
fin de ligne de tout le document, appliqué au prochain enregistrement. L'option
legacy Mac est là pour l'unique fichier, sur l'unique système, qui nous survivra à tous. Très utile également pour emmerder volontairement la personne à qui tu vas transférer ton fichier.

### Générer

L'usine à aléatoire ... Les secrets sont générés depuis une vraie
source aléatoire de l'OS qui échoue en mode fermé : si le système ne peut pas
produire d'aléa cryptographique, il refuse plutôt que de te refiler un "mot de
passe" prévisible.

- **Password to Clipboard...** / **Insert Password...** : un mot de passe généré,
  soit copié (par défaut, pour qu'il n'atterrisse pas dans le fichier que tu édites),
  soit inséré au curseur.
- **UUID**, **Unix Timestamp**, **ISO 8601 (Local)**, **ISO 8601 (UTC)** : insérés au
  curseur. Les quatre trucs que tu colles dans un ticket, un nom de fichier ou une
  ligne de log douze fois par jour.
- **Token (Hex / Base64 / base64url)** et **API Key...** : insérés au curseur. De la
  vraie entropie, le bon format, pas de surprise de padding.
- **.htpasswd Entry...** (bcrypt, MD5 apr1, SHA-1) : demande le mot de passe dans un
  champ masqué, n'insère que la ligne finie `user:hash`. Par défaut bcrypt, parce
  qu'on n'est toujours pas en 2009 et que l'option "SHA-1 pour compatibilité" est un
  piège dans lequel tu choisis de marcher.
- **LDAP** : tout le fourre-tout LDAP sous un seul sous-menu. Des valeurs
  `userPassword...` aux formats slappasswd d'OpenLDAP (SSHA et ses amies, salées,
  plus bcrypt via `{CRYPT}`, plus le passthrough SASL), et des générateurs d'entrées
  **LDIF** complets pour un domaine Root, une Organizational Unit, une Person ou
  Account, un posixGroup, un groupOfNames, et un compte de Service ou de Bind. Les
  mots de passe sont saisis masqués, hachés, et seul le hash arrive dans le LDIF.
  Pour quand le serveur d'annuaire est à terre et, qu'en bon sysadmin, t'as pas une seule sauvegarde correcte sous la main.
- **Protocol** : des modèles à coller dans un terminal pour tâter un service à la
  main. Les protocoles texte (HTTP, SMTP avec et sans STARTTLS, POP3, IMAP, FTP,
  Redis, NNTP, WHOIS, IRC, Memcached, SIP, Graphite, Beanstalkd, et leurs variantes
  TLS) rendent un dialogue prêt à coller dans `telnet`, `nc` ou `openssl s_client`,
  la première ligne étant un commentaire qui te dit comment te connecter. Les
  protocoles binaires et les API HTTP (LDAP, MySQL, PostgreSQL, PHP-FPM, Traefik,
  Docker, Kubernetes) rendent plutôt la bonne commande client, parce que tu ne vas
  pas parler le protocole MySQL à la pogne dans `nc` et on le sait tous les
  deux. HTTP et HTTPS ouvrent un petit dialogue de construction de requête (méthode,
  hôte, vhost, port, chemin, en-têtes, corps, avec le Content-Length rempli pour
  toi), pour tester un hôte virtuel sur une IP précise sans éditer ton fichier hosts
  et oublier de le remettre.

### Texte structuré : JSON, XML, YAML, INI, TOML

La famille du "pourquoi cette config ne se charge pas". Les outils valident, ils ne jugent pas, sauf quand ils
jugent.

- **JSON** : **Validate** (boîte de message, te dit où ça a cassé), **Format**,
  **Minify**, **Sort Keys**. Format/Minify/Sort travaillent sur la sélection ou tout
  le buffer, sur place. Sort Keys sert à rendre deux configs comparables quand une
  équipe a décidé que l'ordre des clés était une personnalité.
- **XML** : **Validate** (bonne formation, avec ligne et position) et **Format**. Les
  déclarations DOCTYPE et ENTITY sont rejetées avant le parsing, exprès, pour qu'une
  petite bombe d'entités faite main ne puisse pas geler l'éditeur. Non, il ne fait
  pas des chichis, il refuse d'être ton vecteur de déni de service.
- **YAML** : **Validate** (message), **Flatten to Dotted Paths** (nouvel onglet,
  transforme un arbre imbriqué en lignes `a.b.c: valeur` que tu peux grep),
  **Sort Keys...** (sur place, te prévient d'abord parce qu'il perd les commentaires
  et la mise en forme d'origine), et **Values Diff vs File...** (nouvel onglet,
  compare deux fichiers YAML clé par clé : uniquement dans A, uniquement dans B,
  changé). Le dernier sert au "le values.yaml de staging et celui de prod sont
  forcément identiques" (ils ne le sont pas).
- **INI** et **TOML** : **Validate** (message), **Sort Keys** (sur place, dans chaque
  section ou table, l'ordre préservé là où il compte), **Find Duplicate Keys**
  (nouvel onglet, avec numéros de ligne, parce que la clé en double qui a
  silencieusement gagné, c'est la raison pour laquelle le réglage que tu as changé
  n'a rien fait).

### Kubernetes

- **Secret from key=value...** et **ConfigMap from key=value...** : lisent le buffer,
  ou la sélection, comme des lignes `KEY=value` (un `.env`, en gros) et émettent un
  vrai manifest Secret ou ConfigMap dans un nouvel onglet, base64 pour les Secrets,
  en clair pour les ConfigMaps. Les noms sont validés comme de vraies étiquettes
  DNS, donc une faute de frappe devient un refus avec message au lieu d'un manifest
  que `kubectl` rejettera après que tu as déjà annoncé à tout le monde qu'il est
  déployé.
- **Decode Secret** et **Decode ConfigMap** : l'autre sens, dans un nouvel onglet,
  décodé du base64, pour lire ce qu'il y a vraiment dans ce Secret sans
  l'incantation en quatre temps `kubectl get -o jsonpath | base64 -d` que tu
  recherches à chaque fois.

### Fichiers .env

Le couteau suisse du .env, pour le format de fichier qui n'a pas de spec et trente
implémentations.

- **Sort Keys**, **Quote Values**, **Unquote Values** : sur place, compatibles undo.
- **Find Duplicate Keys** : nouvel onglet, avec numéros de ligne. En dotenv, le
  dernier gagne, et ce n'est jamais celui que tu voulais.
- **Redact Secrets** : nouvel onglet, masque les valeurs qui ont l'air secrètes et
  gomme les mots de passe de toute URL `scheme://user:pass@host`, y compris dans les
  commentaires, avant que tu ne colles le fichier dans un ticket pour "que le vendor
  y jette un œil". Heuristique best-effort, donc relis-le avant de le partager, mais
  ça rattrape le couteau évident que tu étais sur le point de tendre à quelqu'un.
- **To JSON / From JSON**, **To YAML / From YAML** : convertissent le tout, dans un
  nouvel onglet. Chaque producteur passe par un unique émetteur sûr, pour qu'une
  valeur contenant un saut de ligne ou un signe égal ne puisse pas injecter une
  seconde fausse ligne.

### Docker, Compose, Podman

- **Docker / Compose** : **List Images** (nouvel onglet, tous les
  `services.*.image` plus un résumé des repo/tag uniques), **Environment to .env**
  (nouvel onglet, agrège le bloc environment de chaque service), **Set Image Tag...**
  (re-tague la ligne `image:` sous le curseur, en préservant l'indentation, les
  guillemets, le digest et le commentaire de fin, parce que le re-tag qui bouffe ton
  commentaire `# pinned by security`, c'est comme ça que le pin meurt en silence).
- **Podman Quadlet** : les trois mêmes, pour le format d'unité systemd `.container`,
  en lisant `Image=` et `Environment=` avec un vrai parsing façon systemd.

### Terraform et Helm

- **Terraform** : **List Variables** (nouvel onglet), **tfvars Skeleton** (nouvel
  onglet, les variables obligatoires d'abord avec des placeholders typés, les
  optionnelles commentées), **Find Duplicate Variables** (nouvel onglet). Les
  valeurs par défaut des variables `sensitive` sont caviardées à la fois dans le
  rapport et dans le squelette, pour que le secret ne fuie pas dans le tfvars que tu
  es sur le point de committer. Oui, dans le dépôt. Oui, le public.
- **Helm** : le kit de regrets de l'auteur de chart. **Values Skeleton from
  Template** et **from Folder...** (scanne les références `.Values.x.y`, émet un
  values.yaml minimal dans un nouvel onglet, la version dossier parcourt tout le
  répertoire `templates/`), **Values Path at Cursor** (copie le `.Values.a.b.c` de la
  ligne où tu es dans le presse-papiers), **Find Missing / Unused Values...** et la
  version dossier (croise les références du template avec un values.yaml : ce qui est
  utilisé mais absent, ce qui est défini mais jamais référencé), **Wrap Value in
  quote** et **Value to toYaml | nindent...** (corrigent une ligne existante sur
  place), et **Insert Snippet** (sept blocs de boilerplate que tu retapes de mémoire
  en te trompant d'indentation). Tout ça est un scan naïf qui ne résout pas le
  scoping `with` et `range` de Helm, et il le dit, donc traite-le comme un indice
  fort, pas comme parole d'évangile.

### Réseau et temps

- **IP / CIDR Calculator...** : IPv4 et IPv6. Réseau, broadcast, masque, wildcard,
  plage d'hôtes, nombre, et type d'adresse, rapport inséré au curseur. La source est
  la sélection, sinon il demande. Pour régler la dispute du "est-ce que `.31` est
  dans ce sous-réseau ou pas" avant que quelqu'un ne firewalle le mauvais hôte ... 
- **nmap Command Builder...** : construit une ligne de commande `nmap` depuis un
  dialogue (type de scan, ports, timing, les flags habituels) et l'insère. Il
  construit la commande. Il ne la lance pas. Que tu aies l'autorisation de la lancer,
  ça, c'est entre toi et le propriétaire de la machine cible.
- **Timestamp Converter...** : scanne la sélection (ou demande) à la recherche de
  timestamps Unix, ISO 8601, temps de log Apache et temps syslog, et rapporte chacun
  en Unix plus UTC plus local, avec le delta entre le premier et le dernier.
  Sélectionne deux lignes de log, apprends combien de temps la panne a vraiment duré,
  pleure en conséquence.
- **Cron / Timer Explainer...** : explique une expression cron ou une ligne systemd
  `OnCalendar=` en langage clair et calcule les prochaines exécutions. La source est
  la sélection, sinon la ligne courante, sinon il demande. Pour le `*/15 8-18 * * 1-5`
  que tu as copié quelque part et dont tu n'as jamais été tout à fait sûr.
- **JWT Inspector...** : décode le header et le payload d'un JWT dans un nouvel
  onglet, avec `exp`, `iat`, `nbf` en UTC et local et un verdict d'expiration. Il ne
  vérifie pas la signature, ne peut pas la vérifier sans la clé, et le dit haut et
  fort tout en haut, pour que personne ne le cite comme preuve que le token était
  valide.

### Trajet d'un mail

**Mail Trace**. Colle un `.eml` complet (ou juste ses en-têtes) dans un onglet,
lance l'outil, et obtiens le trajet du mail reconstruit depuis ses `Received:`
dans un nouvel onglet : une boîte ASCII par serveur traversé, les étapes internes
d'une même machine empilées dedans, des flèches avec le **délai
entre chaque saut**, et le transit total. C'est la réponse aux deux questions
qui comptent : "où est-ce que ce mail a dormi quatre heures" et "par où a transité ce spam".


**Inspect Buffer / Selection** (lit les blocs PEM du texte) et **Inspect File...**
(PEM ou DER brut). Rapport dans un nouvel onglet : sujet, émetteur, numéro de série,
validité avec verdict d'expiration, type et taille de clé, algorithme de signature
avec les faibles signalés, contraintes de base, usage de clé, SAN, empreintes. La plupart du temps, tu l'utiliseras pour
répondre à "il expire quand ça" trois jours après qu'il l'a déjà fait.

### Extract, Log, Diff

- **Extract / Count** : extrait les adresses IPv4, URL, emails, UUID, hashes hexa ou
  hostnames (ou tout à la fois) de la sélection ou de tout le buffer, dédupliqués et
  comptés, dans un nouvel onglet. Des scanners linéaires écrits à la main, pas de
  regex, donc il ne s'écroule pas sur un fichier de 100 Mo. Pour transformer un mur
  de log en "voici les 12 IP distinctes qui comptaient vraiment".
- **Log** : la boîte à outils du fichier que tu es réellement en train de fixer
  pendant l'incident. **Normalize Timestamps** (réécrit chaque timestamp dans un
  format ISO local uniforme), **Sort by Timestamp** (même à travers des formats
  mélangés, les lignes sans date collant à la ligne datée au-dessus pour qu'une stack
  trace suive son erreur), **Merge with File...** (entrelace deux logs par le temps,
  même non triés), **Deltas Between Timestamps** (préfixe chaque ligne par l'écart
  depuis la précédente datée, négatif si le log a reculé, ce qu'il fera), et
  **Summary** (compteurs de lignes, plage de temps, tri par sévérité, top des codes
  HTTP, top des IP, top des erreurs répétées). Le tout dans un nouvel onglet. C'est
  l'outil du "corrèle le log applicatif et le log du proxy et trouve les huit
  secondes où tout est parti en vrille".
- **Diff vs File...** : ouvre un diff coloré en direct à deux panneaux, le buffer
  courant contre un fichier que tu choisis, aligné ligne à ligne, lignes identiques
  en sombre et lignes changées éclairées. Le panneau de gauche est éditable, celui de
  droite est la référence. Édite une ligne de gauche jusqu'à ce qu'elle corresponde
  et sa teinte s'éteint aussitôt ; insère ou supprime des lignes et le diff se
  recalcule en direct, l'alignement suit (seul prix : l'historique d'annulation
  repart de zéro à ce moment-là). À la fermeture, si tu as changé le côté gauche, il
  propose de réintégrer ces modifications dans ton document. Pour réconcilier la
  config qui marche avec la config qui ne marche pas, ce qui est l'essentiel du
  boulot.

## Une note sur la confiance

Chaque outil ci-dessus qui touche à un mot de passe, une clé ou un certificat le
fait en mémoire, sur ta machine, et l'oublie quand il a fini. Rien n'est uploadé.
Rien n'est mis en cache dans un cloud que tu n'as pas choisi. Les outils à saisie
masquée n'affichent, n'insèrent, ne loggent, ni ne copient jamais le secret que tu
as tapé. Ce n'est pas une feature marketing, c'est le minimum, et le fait qu'il
faille le préciser en dit long sur les outils que tu utilisais avant celui-ci.

## Licence et crédits

RottenText est publié sous licence GPL-V2.

Développé par Cyril LAMY.

Il utilise la famille de polices Monaspace : https://monaspace.githubnext.com/

Sources et releases : https://github.com/clamy54/rottentext
