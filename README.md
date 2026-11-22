# Scout

Addon WoW Forever (client 16001), fusion d'UpgradeScout, CraftScout et FarmScout. Une fenêtre `/scout`
à trois onglets, collée à l'HdV quand il s'ouvre, et un seul scan de l'HdV pour les trois :

- **Équipement** : meilleures améliorations par slot dans ton budget (poids de stats par classe/rôle).
- **Métiers** : recettes à apprendre (maître, marchand, patrons HdV) avec bénéfice, remboursement et offre.
- **Farm** : valeur moyenne par kill des monstres de ton niveau (butin cmangos × prix), corrigée par ton butin réel.

Données : `Farm/Loot.lua` est généré par `python3 -I tools/build_loot.py ClassicDB.sql.gz Farm/Loot.lua`
depuis [cmangos classic-db](https://github.com/cmangos/classic-db). Monstres via l'API publique de QuestieDB,
prix de secours via Auctionator. `tools/migrate.lua` reprend les sauvegardes des trois anciens addons.
`lua tools/export.lua <SavedVariables/Scout.lua> historique.csv` exporte l'historique HdV en CSV
(`item_id,name,timestamp,datetime,price,quantity`, un relevé par scan, prix en cuivre).

Licence : GPL-3.0-or-later.
