#!/usr/bin/env python3
"""Génère Data/Loot.lua à partir de la base libre cmangos classic-db (GPL-3.0).

Usage : python3 -I tools/build_loot.py <ClassicDB.sql ou .sql.gz> <sortie.lua>

Pour chaque monstre apparaissant dans le monde, on calcule le butin attendu par kill
(espérance du nombre de chaque objet), l'or moyen et la table de dépeçage. Les tables de
référence (butin « mondial » partagé, ex. objets verts) restent séparées pour garder un
fichier compact : la valeur d'une référence est calculée une seule fois en jeu.

Règles de butin cmangos :
- chance < 0 : objet de quête (seulement si la quête est en cours) -> ignoré ;
- mincountOrRef < 0 : référence -(mincountOrRef), tirée maxcount fois avec la chance donnée ;
- groupid 0 : chaque ligne est tirée indépendamment ;
- groupid > 0 : au plus un objet par groupe ; les objets à chance explicite sont tirés d'abord,
  les objets à chance 0 se partagent à parts égales la probabilité restante.
"""
import gzip
import sys
from collections import defaultdict

TABLES = {
    "creature", "creature_template", "creature_loot_template",
    "reference_loot_template", "skinning_loot_template", "item_template",
}
MIN_EXPECTED = 1e-5   # en dessous, l'objet est négligeable


def parse_values(text, start):
    """Lit les tuples SQL `(a,'b',NULL),(...)` à partir de `start`. Renvoie une liste de listes."""
    rows, row, i, n = [], None, start, len(text)
    while i < n:
        c = text[i]
        if c == "(":
            row, i = [], i + 1
            token = []
            while True:
                c = text[i]
                if c == "'":
                    i += 1
                    s = []
                    while True:
                        c = text[i]
                        if c == "\\":
                            s.append(text[i + 1])
                            i += 2
                        elif c == "'" and text[i + 1] == "'":
                            s.append("'")
                            i += 2
                        elif c == "'":
                            i += 1
                            break
                        else:
                            s.append(c)
                            i += 1
                    token = s
                    row.append("".join(token))
                    token = None
                elif c in ",)":
                    if token is not None:
                        raw = "".join(token).strip()
                        row.append(None if raw == "NULL" else raw)
                    token = []
                    i += 1
                    if c == ")":
                        rows.append(row)
                        break
                else:
                    token.append(c)
                    i += 1
        elif c == ";":
            break
        else:
            i += 1
    return rows


def load(path):
    opener = gzip.open if path.endswith(".gz") else open
    columns, data, current_create = {}, defaultdict(list), None
    with opener(path, "rt", encoding="utf-8", errors="replace") as f:
        for line in f:
            if line.startswith("CREATE TABLE `"):
                name = line.split("`")[1]
                current_create = name if name in TABLES else None
                if current_create:
                    columns[name] = []
            elif current_create and line.startswith("  `"):
                columns[current_create].append(line.split("`")[1])
            elif current_create and line.startswith(")"):
                current_create = None
            elif line.startswith("INSERT INTO `"):
                name = line.split("`")[1]
                if name in TABLES:
                    data[name].extend(parse_values(line, line.index("VALUES") + 6))
    tables = {}
    for name, rows in data.items():
        cols = columns[name]
        tables[name] = [dict(zip(cols, r)) for r in rows]
    return tables


def group_loot(rows):
    by_entry = defaultdict(list)
    for r in rows:
        by_entry[int(r["entry"])].append(r)
    return by_entry


class Loot:
    """Espérance de butin d'une table, références incluses ou laissées séparées."""

    def __init__(self, refs):
        self.refs = refs
        self.memo = {}

    def expand(self, rows, flatten_refs):
        items, refs = defaultdict(float), defaultdict(float)

        def add_ref(ref_id, mult):
            if flatten_refs:
                for item, exp in self.reference(ref_id).items():
                    items[item] += exp * mult
            else:
                refs[ref_id] += mult

        groups = defaultdict(list)
        for r in rows:
            chance = float(r["ChanceOrQuestChance"])
            if chance < 0:
                continue
            mincount, maxcount = int(r["mincountOrRef"]), int(r["maxcount"])
            group = int(r["groupid"])
            if mincount < 0:
                add_ref(-mincount, (chance or 100) / 100 * max(maxcount, 1))
            elif group == 0:
                items[int(r["item"])] += chance / 100 * (mincount + maxcount) / 2
            else:
                groups[group].append((int(r["item"]), chance, (mincount + maxcount) / 2))
        for entries in groups.values():
            explicit = sum(c for _, c, _ in entries if c > 0)
            equal = [e for e in entries if e[1] == 0]
            share = max(0.0, 100 - explicit) / len(equal) if equal else 0
            for item, chance, count in entries:
                items[item] += (chance if chance > 0 else share) / 100 * count
        return items, refs

    def reference(self, ref_id):
        if ref_id not in self.memo:
            self.memo[ref_id] = {}   # garde contre les cycles
            items, _ = self.expand(self.refs.get(ref_id, []), flatten_refs=True)
            self.memo[ref_id] = items
        return self.memo[ref_id]


def fmt(x):
    return ("%.5f" % x).rstrip("0").rstrip(".")


def flat(d):
    return "{" + ",".join("%d,%s" % (k, fmt(v)) for k, v in sorted(d.items()) if v >= MIN_EXPECTED) + "}"


def main(src, dst):
    t = load(src)
    spawned = {int(r["id"]) for r in t["creature"]}
    loot = Loot(group_loot(t["reference_loot_template"]))
    creature_loot = group_loot(t["creature_loot_template"])
    skin_loot = group_loot(t["skinning_loot_template"])

    creatures, used_refs, used_skins, used_items = [], set(), set(), set()
    for c in t["creature_template"]:
        cid = int(c["Entry"])
        if cid not in spawned or int(c["MinLevel"]) > 63:
            continue
        gold = (int(c["MinLootGold"]) + int(c["MaxLootGold"])) / 2
        lid, sid = int(c["LootId"]), int(c["SkinningLootId"])
        items, refs = loot.expand(creature_loot.get(lid, []), flatten_refs=False) if lid else ({}, {})
        skin = sid if sid and sid in skin_loot else 0
        if not (items or refs or gold or skin):
            continue
        used_refs.update(refs)
        if skin:
            used_skins.add(skin)
        used_items.update(items)
        creatures.append((cid, gold, items, refs, skin))

    skins = {}
    for sid in used_skins:
        skins[sid], _ = loot.expand(skin_loot[sid], flatten_refs=True)
        used_items.update(skins[sid])
    refs = {rid: loot.reference(rid) for rid in used_refs}
    for items in refs.values():
        used_items.update(items)

    item_rows = {int(r["entry"]): r for r in t["item_template"]}
    with open(dst, "w", encoding="utf-8") as out:
        out.write("-- SPDX-License-Identifier: GPL-3.0-or-later\n")
        out.write("-- GÉNÉRÉ par tools/build_loot.py depuis cmangos classic-db (GPL-3.0). Ne pas éditer.\n")
        out.write("-- C[npcID] = { or moyen (cuivre), {objet, espérance, ...}, {référence, multiplicateur, ...}, table de dépeçage }\n")
        out.write("local _, ns = ...\nlocal D = {}\nns.LootData = D\n")
        out.write("D.C = {\n")
        for cid, gold, items, rrefs, skin in sorted(creatures):
            out.write("[%d]={%d,%s,%s,%d},\n" % (cid, gold, flat(items), flat(rrefs), skin))
        out.write("}\nD.R = {\n")
        for rid, items in sorted(refs.items()):
            out.write("[%d]=%s,\n" % (rid, flat(items)))
        out.write("}\nD.S = {\n")
        for sid, items in sorted(skins.items()):
            out.write("[%d]=%s,\n" % (sid, flat(items)))
        # Prix marchand ; négatif = objet lié quand ramassé (invendable à l'HdV).
        out.write("}\nD.V = {\n")
        for iid in sorted(used_items):
            r = item_rows.get(iid)
            if r:
                price = int(r["SellPrice"])
                if int(r["bonding"]) == 1:
                    price = -price
                out.write("[%d]=%d,\n" % (iid, price))
        out.write("}\n")
    print("monstres %d, références %d, dépeçage %d, objets %d" % (
        len(creatures), len(refs), len(skins), len(used_items)))


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
