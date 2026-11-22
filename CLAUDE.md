# Scout (addon WoW Forever)

Addon pour **WoW Forever** : client moderne (`## Interface: 16001`, API `C_AuctionHouse`, `C_Item`, `C_TradeSkillUI`)
sur du contenu Classic (objets, recettes, butin). Une fenêtre `/scout` à trois onglets (Équipement, Métiers, Farm),
collée à l'HdV, et **un seul scan de l'HdV** partagé par les trois. L'historique des prix est étudié hors jeu
par l'outil Rust compagnon `../scout-rs` (voir son `CLAUDE.md`).

## Façon de travailler
- Claude écrit le code ; l'utilisateur relit et teste en jeu. Réponses en français, tutoiement.
- Claude ne peut pas lancer le jeu : vérifier ce qui est vérifiable hors jeu (`luac -p`, scripts `tools/` sur le
  vrai SavedVariables, lecture du journal), et dire clairement ce qui reste à tester en jeu.
- Si Claude se trompe, il le dit franchement.
- Rester dans ce qu'autorise l'API des addons : lecture seule de l'HdV, chaque scan lancé par un clic, respect de
  la limite de requêtes (`IsThrottledMessageSystemReady`), aucune action automatique (achat, vente, fabrication).

## Installation et fichiers du jeu
- Ce dossier est **lié** dans le jeu : `…/_forever_/Interface/AddOns/Scout -> ~/dev/outils-jeux/wow/Scout`.
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
| `Equip/` | Poids de stats, gain vs équipé, analyse des objets du scan. |
| `Craft/` | Recettes (fenêtre de métier), sources d'apprentissage, rentabilité. |
| `Farm/` | Valeur par kill : `Loot.lua` **généré** (`tools/build_loot.py`, ne pas éditer), butin observé. |
| `UI/` | Fenêtre à onglets, listes, bouton de minimap ; boutons « Scanner l'HdV » / « Rapide » orange pendant un scan, verts si le dernier date de moins de 20 min. |
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
- `names[itemID]` : nom de **tout** objet vu ; `class[itemID] = classID * 100 + subClassID` et
  `classNames` / `subclassNames` (libellés du client). Mêmes numéros d'objet qu'Auctionator et Forever Guide.
- `t, n` / `tq, nq` : heure et nombre d'objets du dernier scan complet / rapide (bouton vert < 20 min).
- `tools/export.lua` est le contrat avec `scout-rs` : colonnes `item_id,name,timestamp,datetime,price,quantity`
  (et `item_id,name,class_id,subclass_id,class,subclass` avec `--names`). Changer ce format = changer
  `scout-rs/scout-sources/src/import.rs` en même temps.

### Marchands (`Prices.lua`)
- À chaque ouverture d'un marchand (`MERCHANT_SHOW`) : `vendor[itemID]` = prix unitaire (remise comprise) et
  `merchants[npcID] = { name, zone, x, y, t, items = { [itemID] = { p, l = stock limité } } }` (npcID tiré de
  `UnitGUID("npc")`, position via `C_Map`). Objets payés en jetons ignorés. Exporté vers `scout-rs` par son
  `scout-sources/lua/vendor_export.lua`.

## Pièges connus
- **`a and b or c` en Lua** : si `b` peut être `nil`/`false`, l'expression renvoie `c`. C'est ce qui a fait comparer
  le premier scan rapide au scan complet. Écrire un `if` explicite.
- `C_Item.GetItemInfo` peut renvoyer `nil` (objet pas en cache) : `RequestLoadItemDataByID` puis
  `GET_ITEM_INFO_RECEIVED`. `GetItemInfoInstant` (classe, sous-classe) ne dépend pas du cache.
- Autres addons de l'utilisateur à ménager : Auctionator, Forever Guide (scans HdV), QuestieDB (données monstres).

## Style
- Code, commentaires et textes affichés en **français** ; fichiers courts.
- Commits : sujet en français, phrase courte avec majuscule (ex. « Historique HdV horodaté, export CSV et scan
  protégé »), corps qui explique le pourquoi. Dépôt privé `github.com/Darkrizen7/Scout`, branche `master`.
