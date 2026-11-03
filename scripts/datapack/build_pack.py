#!/usr/bin/env python3
"""Packs the recommender's open data into one SQLite file the app reads as is.

  scripts/datapack/build_pack.py [--wikidata build/datapack/wikidata.tsv] [--neighbours build/datapack/neighbours.tsv]
                                 [--out build/datapack/recs-pack.sqlite]

Tables:
  title(imdb, kp, year, ru, ru_key, en, en_key, rt, mc, likes, mean)  one row per IMDb id; en is MovieLens's English title
                                                           (to search the site for films without a Russian one);
                                                           ru_key is the Russian title folded
                                                           (lower case, ё→е, letters and digits only) for matching
                                                           the site's cards by name and year
  neighbour(imdb, other, score)                            «those who liked imdb also liked other»
  meta(key, value)                                         version, build date, sources
No ratings, users or tags are stored: only the neighbour lists derived from them.
"""

import argparse
import csv
import datetime
import os
import re
import sqlite3
import sys

VERSION = 1


def fold(text):
    text = (text or "").lower().replace("ё", "е")
    return re.sub(r"[^0-9a-zа-я]+", "", text)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--wikidata", default="build/datapack/wikidata.tsv")
    parser.add_argument("--neighbours", default="build/datapack/neighbours.tsv")
    parser.add_argument("--movies", default="movielens/movies.csv")
    parser.add_argument("--links", default="movielens/links.csv")
    parser.add_argument("--out", default="build/datapack/recs-pack.sqlite")
    args = parser.parse_args()

    titles = {}
    with open(args.wikidata, encoding="utf-8") as source:
        for line in source:
            imdb, kp, year, ru, rt, mc = (line.rstrip("\n").split("\t") + [""] * 6)[:6]
            titles[int(imdb)] = {
                "kp": int(kp) if kp else None, "year": int(year) if year else None, "ru": ru or None,
                "rt": int(rt) if rt else None, "mc": int(mc) if mc else None, "likes": None, "mean": None,
            }

    neighbours = []
    with open(args.neighbours, encoding="utf-8") as source:
        for line in source:
            imdb, likes, mean, others = (line.rstrip("\n").split("\t") + [""] * 4)[:4]
            imdb = int(imdb)
            row = titles.setdefault(imdb, {"kp": None, "year": None, "ru": None, "rt": None, "mc": None})
            row["likes"] = int(likes)
            row["mean"] = float(mean)
            for pair in filter(None, others.split(",")):
                other, score = pair.split(":")
                neighbours.append((imdb, int(other), round(float(score), 4)))

    # MovieLens's English titles: «Matrix, The (1999)» → «The Matrix», 1999.
    imdb_of = {}
    with open(args.links, encoding="utf-8", newline="") as source:
        for row in csv.DictReader(source):
            if row["imdbId"]:
                imdb_of[row["movieId"]] = int(row["imdbId"])
    with open(args.movies, encoding="utf-8", newline="") as source:
        for row in csv.DictReader(source):
            imdb = imdb_of.get(row["movieId"])
            if imdb is None or imdb not in titles:
                continue
            match = re.match(r"^(.*?)\s*\((\d{4})\)\s*$", row["title"].strip())
            name, year = (match.group(1), int(match.group(2))) if match else (row["title"].strip(), None)
            name = re.sub(r"^(.*), (The|A|An|Les|La|Le|Il|Der|Die|Das|El)$", r"\2 \1", name)
            name = re.sub(r"\s*\(a\.k\.a\..*\)$", "", name)
            titles[imdb]["en"] = name
            titles[imdb]["year"] = titles[imdb]["year"] or year

    if os.path.exists(args.out):
        os.remove(args.out)
    db = sqlite3.connect(args.out)
    db.executescript("""
        CREATE TABLE title (
            imdb INTEGER PRIMARY KEY, kp INTEGER, year INTEGER, ru TEXT, ru_key TEXT, en TEXT, en_key TEXT, rt INTEGER,
            mc INTEGER, likes INTEGER, mean REAL
        );
        CREATE TABLE neighbour (imdb INTEGER NOT NULL, other INTEGER NOT NULL, score REAL NOT NULL,
            PRIMARY KEY (imdb, other)) WITHOUT ROWID;
        CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT NOT NULL);
    """)
    # Only titles that carry something the app uses: critics' scores or viewer neighbours (a bare id mapping is
    # nothing the title page doesn't already say).
    useful = {imdb: r for imdb, r in titles.items() if r["rt"] is not None or r["mc"] is not None or r.get("likes")}
    db.executemany(
        "INSERT INTO title VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
        ((imdb, r["kp"], r["year"], r["ru"], fold(r["ru"]) or None, r.get("en"), fold(r.get("en")) or None, r["rt"], r["mc"],
          r.get("likes"), r.get("mean"))
         for imdb, r in useful.items()),
    )
    titles = useful
    db.executemany("INSERT OR IGNORE INTO neighbour VALUES (?, ?, ?)", neighbours)
    db.executescript("""
        CREATE INDEX title_kp ON title(kp) WHERE kp IS NOT NULL;
        CREATE INDEX title_ru ON title(ru_key, year) WHERE ru_key IS NOT NULL;
        CREATE INDEX title_en ON title(en_key, year) WHERE en_key IS NOT NULL;
    """)
    db.executemany("INSERT INTO meta VALUES (?, ?)", [
        ("version", str(VERSION)),
        ("built", datetime.date.today().isoformat()),
        ("sources", "Wikidata (CC0); viewer neighbours derived from MovieLens 32M with GroupLens's permission"),
    ])
    db.commit()
    db.execute("VACUUM")
    db.close()
    print(f"{len(titles)} titles, {len(neighbours)} neighbour pairs → {args.out} "
          f"({os.path.getsize(args.out) / 1e6:.1f} MB)", file=sys.stderr)


if __name__ == "__main__":
    main()
