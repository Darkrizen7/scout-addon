# Scout (addon WoW Forever)

Addon pour **WoW Forever** : client moderne (`## Interface: 16001`, API `C_AuctionHouse`, `C_Item`, `C_TradeSkillUI`)
sur du contenu Classic (objets, recettes, butin). Une fenêtre `/scout` à onglets (Équipement, Métiers),
collée à l'HdV, et **un seul scan de l'HdV** partagé par tous. L'historique des prix est étudié hors jeu
par l'outil Rust compagnon `../scout-rs` (voir son `CLAUDE.md`).

## Façon de travailler
- Claude écrit le code ; l'utilisateur relit et teste en jeu. Réponses en français, tutoiement.
- Claude ne peut pas lancer le jeu : vérifier ce qui est vérifiable hors jeu (`luac -p`, scripts `tools/` sur le
  vrai SavedVariables, lecture du journal), et dire clairement ce qui reste à tester en jeu.
- Si Claude se trompe, il le dit franchement.
- Rester dans ce qu'autorise l'API des addons : lecture seule de l'HdV, chaque scan lancé par un clic, respect de
  la limite de requêtes (`IsThrottledMessageSystemReady`), aucune action automatique (achat, vente, fabrication).

## Installation et fichiers du jeu
- Ce dossier est **lié** dans le jeu : `…/_forever_/Interface/AddOns/Scout -> ~/dev/outils-jeux/wow/scout-addon`.
  Ne rien y mettre de lourd (pas de build, pas de `target/`) : le projet Rust vit à côté, dans `../scout-rs`.
- Jeu sous Wine : `~/Games/battlenet/drive_c/Program Files (x86)/World of Warcraft/_forever_/`.
  SavedVariables : `WTF/Account/<compte>/SavedVariables/Scout.lua` (variable `ScoutDB`).
- Après un changement de code : `/reload` en jeu (un fichier ajouté au `.toc` demande de relancer le jeu).
- **Le jeu n'écrit `Scout.lua` qu'au `/reload` ou à la déconnexion**, et l'écrase avec ce qu'il a en mémoire.
  Pour corriger ce fichier à la main : l'utilisateur se déconnecte (écran de sélection des personnages),
  sauvegarde du fichier, modification, puis reconnexion.
- `ScoutDB.log` : journal de la session (`ns.Log`), lisible sur disque après `/reload` — premier réflexe pour
  diagnostiquer un problème signalé en jeu.

## Vérifier hors jeu
- Syntaxe : `luac -p Core.lua Scan.lua …` (Lua 5.4 installé ; le jeu tourne en Lua 5.1 : pas de `//`, `&`, `goto`
  dans le code de l'addon — les scripts de `tools/` tournent, eux, en 5.4).
- Données réelles : `lua tools/export.lua "<…>/SavedVariables/Scout.lua"` (historique) et `… --names` (noms et
  catégories) ; `lua -e 'local e={} loadfile(…,"t",e)() …'` pour inspecter `ScoutDB`.

## Architecture
Ordre de chargement : celui du `.toc`. Namespace partagé `ns` (`local _, ns = ...`).

| Fichier | Rôle |
|---|---|
| `Core.lua` | `ns`, `ScoutDB` (défauts, schéma documenté en tête), `ns.On` (plusieurs gestionnaires par événement), `ns.OnInit`, `ns.Log`, commandes `/scout`. |
| `Prices.lua` | Prix partagés : scan Scout (persisté), Auctionator en secours, prix marchands ; relevé des marchands ouverts (PNJ, position, objets). |
| `Scan.lua` | Scan de l'HdV : complet ou rapide (artisanat), enregistrement des prix / historique / noms / catégories, garde-fous. |
| `Equip/` | Poids de stats, gain vs équipé (rien n'est proposé pour un emplacement dont l'objet porté a des stats inconnues, ni pour un objet déjà porté ; doublon d'anneau/bijou/arme seulement s'il n'est pas « Unique »), analyse des objets du scan. |
| `Craft/` | Recettes (fenêtre de métier), sources d'apprentissage, rentabilité. |
| `Farm/` | Pas d'onglet : `Loot.lua` **généré** (`tools/build_loot.py`, ne pas éditer ; objets de butin suivis au scan, prix marchand), butin observé exporté vers scout-rs. |
| `UI/` | Fenêtre à onglets (texte d'aide : champ `help` de `UI.RegisterTab`), listes, bouton de minimap ; boutons « Scanner l'HdV » / « Rapide » affichés seulement HdV ouvert, orange pendant un scan, verts si le dernier date de moins de 20 min. |
| `tools/` | `export.lua` (CSV pour l'outil Rust), `migrate.lua` (anciens addons), `build_loot.py`. |

### Scan de l'HdV (`Scan.lua`)
- Lecture par `C_AuctionHouse.SendBrowseQuery` (recherche vide) puis `RequestMoreBrowseResults` jusqu'à
  `HasFullBrowseResults`. Le serveur Forever **respecte `itemClassFilters`** : le scan rapide ne demande que
  Artisanat, Recettes, Consommables, Réactifs, Gemmes (≈ 1 900 objets contre ≈ 7 000).
- **Les résultats de recherche de l'HdV sont partagés** avec tout le reste : barre de recherche, favoris, boutons de
  scan de Forever Guide ou d'Auctionator. Une autre recherche pendant la lecture remplace nos résultats : le scan
  est alors **annulé** (crochet `hooksecurefunc` sur `SendBrowseQuery` / `SearchForFavorites`, et contrôle dans
  `BROWSE_RESULTS_UPDATED`). Ne jamais enregistrer un scan incomplet : il mettrait tous les objets suivis à
  « 0 en vente ».
- Garde-fou : un scan qui voit moins de la moitié des objets du scan précédent **du même type** (`market.n` /
  `market.nq`) n'est pas enregistré.
- Scan rapide : ne touche qu'aux objets des classes d'artisanat (prix, historique, « 0 en vente ») ; le reste garde
  les prix du dernier scan complet, et l'analyse d'équipement n'est pas lancée.

### Données de marché (`ScoutDB.market`)
- `hist[itemID]` : relevés `{ t, p, q }` de **chaque scan** (plusieurs par jour), gardés 21 jours (`HISTORY_DAYS`).
  Les anciens relevés journaliers `{ d = "AAAA-MM-JJ" }` sont convertis à midi quand on y touche.
- `houses[i] = { realm, faction }` : HdV scannés (dédupliqués) ; chaque relevé porte `a = i`. `faction` ∈
  `Alliance | Horde | Neutral` ; HdV neutre détecté par la carte du joueur (`NEUTRAL_MAPS`, Scan.lua, IDs à
  vérifier en jeu). Anciens relevés sans `a` : inchangés. `MIN_RATIO` et `prices` restent communs à tous les HdV.
- `names[itemID]` : nom de **tout** objet vu ; `class[itemID] = classID * 100 + subClassID` et
  `classNames` / `subclassNames` (libellés du client). Mêmes numéros d'objet qu'Auctionator et Forever Guide.
- `t, n` / `tq, nq` : heure et nombre d'objets du dernier scan complet / rapide (bouton vert < 20 min).
- `tools/export.lua` est le contrat avec `scout-rs` : colonnes `item_id,name,timestamp,datetime,price,quantity,realm,faction`
  (et `item_id,name,class_id,subclass_id,class,subclass` avec `--names` ; butin avec `--loot`, voir plus bas).
  Changer ce format = changer `scout-rs/scout-sources/src/import.rs` en même temps.

### Marchands (`Prices.lua`)
- À chaque ouverture d'un marchand (`MERCHANT_SHOW`) : `vendor[itemID]` = prix unitaire (remise comprise) et
  `merchants[npcID] = { name, zone, x, y, t, items = { [itemID] = { p, l = stock limité } } }` (npcID tiré de
  `UnitGUID("npc")`, position via `C_Map`). Objets payés en jetons ignorés. Exporté vers `scout-rs` par son
  `scout-sources/lua/vendor_export.lua`.

### Butin observé (`Farm/Observed.lua`, `ScoutDB.farm`)
- `obs[npcID] = { name, zone, kills, money, items = { [itemID] = { n, q } }, skins, skin = { [itemID] = { n, q } } }` :
  `n` = corps où l'objet est tombé (→ chance réelle `n / kills`), `q` = quantité totale. Anciennes entrées
  `items[id] = quantité` converties à la lecture.
- Fouille ou récolte : une fenêtre de butin ouverte moins de 5 s après un sort de Dépeçage / Minage /
  Herboristerie (`UNIT_SPELLCAST_SUCCEEDED`, ids Classic + noms) va dans `skins` / `skin`.
- `seen.set[GUID] = { l, s, sk }` (300 derniers corps) : objets déjà comptés par corps, pour qu'une fenêtre
  rouverte ne recompte rien. Nom du monstre : mémorisé en cible / au survol (`guid → nom`).
- Exporté vers `scout-rs` par `tools/export.lua --loot` : colonnes
  `npc_id,name,zone,kills,skins,kind,item_id,drops,quantity` (`kind` ∈ `loot | skin` ; ligne sans objet pour un
  monstre sans butin). **Contrat** : le changer = changer `scout-rs/scout-sources/src/import.rs`.
- Test hors jeu : simuler les événements avec de fausses fonctions WoW (`GetLootSourceInfo`, `GetMoney`…) puis
  charger `Farm/Observed.lua` avec `loadfile(…)("Scout", ns)`.

### Point sur la carte (`Core.lua`, `/way`)
- `/way #<UiMap> <x> <y> [nom]` (syntaxe TomTom, coordonnées en %, virgule acceptée), texte copié depuis scout-rs :
  `C_Map.SetUserWaypoint` puis `C_SuperTrack.SetSuperTrackedUserWaypoint` (pin natif suivi). En combat, posé à
  `PLAYER_REGEN_ENABLED`. Enregistrée à `PLAYER_LOGIN` **seulement si TomTom n'a pas déjà `/way`** (TomTom se charge
  après Scout). Action tapée par le joueur, rien d'automatique.

### Prix des 30 derniers jours (`History.lua`, `ScoutHistory`)
- Fichier **écrit par scout-rs** (une fois par jour, gitignoré), chargé en premier par le `.toc` ; absent si l'outil
  n'a rien écrit : `ScoutHistory` peut être `nil`. Lecture seule, aucun code ne l'utilise encore.
- Contrat (format 1) : `{ format = 1, generated = <Unix>, first_day = <jours depuis 1970-01-01>, prices = { [itemId] = "120,,118,121" } }`
  (prix en cuivre par unité, un par jour depuis `first_day`, champ vide = pas de relevé). Aujourd'hui :
  `local t = date("*t"); local today = math.floor(time{year=t.year, month=t.month, day=t.day, hour=12} / 86400)`.
- Détail : `docs/sources.md` de scout-rs (« Prix envoyés à l'addon »).

## Pièges connus
- **`a and b or c` en Lua** : si `b` peut être `nil`/`false`, l'expression renvoie `c`. C'est ce qui a fait comparer
  le premier scan rapide au scan complet. Écrire un `if` explicite.
- **`tonumber(select(n, strsplit(…)))`** : `select` renvoie aussi les champs suivants, que `tonumber` prend pour
  la base → « bad argument #2 ». Entourer de parenthèses `tonumber((select(…)))` ou passer par des variables locales.
- **Ramassage rapide** (Leatrix Plus « Faster auto loot », installé chez l'utilisateur) : tout est ramassé à
  `LOOT_READY`, avant `LOOT_OPENED`. Lire le butin dès `LOOT_READY` (Farm/Observed.lua), sinon la fenêtre est déjà vide.
- **Valeurs secrètes** (en donjon notamment) : `UnitGUID`, `UnitName`, des liens de butin peuvent être « secrets » ;
  les découper (`strsplit`), les convertir ou s'en servir de clé déclenche une erreur à chaque événement. Toujours
  passer par `ns.NpcID(guid)` et tester `ns.IsSecret(v)` (Core.lua, via `issecretvalue`). Conséquence : en donjon,
  le butin des monstres à GUID secret n'est pas enregistré.
- `C_Item.GetItemInfo` peut renvoyer `nil` (objet pas en cache) : `RequestLoadItemDataByID` puis
  `GET_ITEM_INFO_RECEIVED`. `GetItemInfoInstant` (classe, sous-classe) ne dépend pas du cache.
- Autres addons de l'utilisateur à ménager : Auctionator, Forever Guide (scans HdV), QuestieDB (données monstres).

## Style
- Code, commentaires et textes affichés en **français** ; fichiers courts.
- Commits : sujet en français, phrase courte avec majuscule (ex. « Historique HdV horodaté, export CSV et scan
  protégé »), corps qui explique le pourquoi. Dépôt public `github.com/Darkrizen7/scout-addon`, branche `master`.
- Versions : tag `vX.Y.Z` posé à la demande de l'utilisateur, identique à `## Version` de `Scout.toc` (à monter
  avant, commit à part). Licence MIT, sauf `Farm/Loot.lua` (données cmangos) : GPL-3.0-or-later.

## Tickets (pman)

<!-- pman init: début (bloc géré par `pman init`) -->
- Workspace pman : `wow` (`PMAN_WORKSPACE`, posé par `.claude/settings.json`) ; serveur http://127.0.0.1:8090.
- Projets : `ADDON`.
- Lien d'un ticket : http://127.0.0.1:8090/wow/projects/ADDON/issues/ADDON-42
- Workflow : skill `/pman` (`.claude/skills/pman/`) et agent `dev` (`.claude/agents/dev.md`), installés par `pman init` ; CLI : `pman --help`.
<!-- pman init: fin -->
- Propre à l'addon (hors du bloc géré) :
  - Comptes : Claude agit uniquement avec le bot `claude` ; l'utilisateur est `arthur`. Label **Feature** ou **Fix**
    posé à la création. Une branche par ticket depuis `master` (`ADDON-42-description-courte`), clé en tête du
    sujet des commits (`ADDON-42 : …`), PR vers `master` (corps : résumé, comment tester, `pman : ADDON-42 (<lien>)`),
    relecture tracée en `gh pr comment`, fusion par Claude (`git merge --no-ff` en local, message
    `Fusion de la PR #N : <titre>`, puis `git push origin master` et suppression de la branche). Jamais de `--force`.
  - Dates des commits : jamais en semaine 9h–12h ni 14h–18h (heure de Paris) ; sinon `--date` et
    `GIT_COMMITTER_DATE` juste après la plage.
  - Vérifications (relecture et agent `dev`) : `luac -p` sur chaque fichier `.lua` modifié, aucune syntaxe Lua 5.2+
    dans l'addon (voir « Vérifier hors jeu »), et `tools/export.lua` sur le vrai SavedVariables si l'export change.
  - Claude ne lance pas le jeu : un ticket qui change le comportement en jeu finit en `agent request-validation`
    (étapes précises : `/reload`, quoi cliquer, résultat attendu), pas en Done.
  - Le format des CSV exportés est un contrat avec `../scout-rs` : un changement = un ticket `ADDON` et un ticket
    `APP` liés par une relation, livrés ensemble.
  - Dépôt **public** : rien de personnel dans les tickets cités, les PR ni les commits (pas de SavedVariables,
    pas de nom de compte ni de personnage).
