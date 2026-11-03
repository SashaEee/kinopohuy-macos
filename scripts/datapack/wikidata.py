#!/usr/bin/env python3
"""Open facts about films and series from Wikidata (CC0) for the recommender's data pack.

Writes build/datapack/wikidata.tsv with one line per IMDb id:
    imdb  kp  year  ru_title  rt  mc
  imdb      IMDb id without «tt» (int)
  kp        Kinopoisk film id (int), empty when unknown
  year      first publication year, empty when unknown
  ru_title  the Russian label, empty when there is none
  rt        Rotten Tomatoes critics score, 0–100 (the Tomatometer), empty when unknown
  mc        Metacritic metascore, 0–100, empty when unknown

Usage: scripts/datapack/wikidata.py [--out build/datapack/wikidata.tsv]
Only the public query service is asked (query.wikidata.org), about 120 requests, a pause between them (~10 min).
"""

import argparse
import json
import os
import re
import sys
import time
import urllib.parse
import urllib.request

ENDPOINT = "https://query.wikidata.org/sparql"
AGENT = "KinoPohuy-datapack/1.0 (https://github.com/SashaEee/kinopohuy-macos)"
ROTTEN_TOMATOES = "Q105584"
METACRITIC = "Q150248"
TOMATOMETER = "Q108403393"


def ask(query, attempts=4):
    data = urllib.parse.urlencode({"query": query, "format": "json"}).encode()
    for attempt in range(attempts):
        request = urllib.request.Request(ENDPOINT, data=data, headers={
            "User-Agent": AGENT, "Accept": "application/sparql-results+json",
            "Content-Type": "application/x-www-form-urlencoded",
        })
        try:
            with urllib.request.urlopen(request, timeout=120) as response:
                return json.load(response)["results"]["bindings"]
        except Exception as error:  # timeouts and 429s: wait and try again
            wait = 10 * (attempt + 1)
            print(f"  retry in {wait} s ({error})", file=sys.stderr)
            time.sleep(wait)
    raise SystemExit("Wikidata didn't answer")


def imdb_number(value):
    match = re.fullmatch(r"tt(\d+)", value or "")
    return int(match.group(1)) if match else None


def percent(text):
    match = re.match(r"\s*(\d+(?:\.\d+)?)\s*(%|/\s*100)?", text or "")
    if not match:
        return None
    value = float(match.group(1))
    return int(round(value)) if 0 <= value <= 100 else None


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", default="build/datapack/wikidata.tsv")
    args = parser.parse_args()
    os.makedirs(os.path.dirname(args.out), exist_ok=True)

    rows = {}  # imdb → dict

    def row(imdb):
        return rows.setdefault(imdb, {"kp": None, "year": None, "ru": "", "rt": None, "mc": None})

    def absorb(b, r):
        if "ru" in b and not r["ru"]:
            r["ru"] = b["ru"]["value"].replace("\t", " ").strip()
        if "date" in b:
            match = re.match(r"-?(\d{4})", b["date"]["value"])
            if match:
                year = int(match.group(1))
                r["year"] = year if r["year"] is None else min(r["year"], year)

    # 1. Kinopoisk ids with IMDb ids, Russian titles and dates, split by the id's last two digits (each part a few
    #    seconds; one query for all of them runs past the service's minute). No GROUP BY: rows are folded here.
    for suffix in (f"{n:02d}" for n in range(100)):
        print(f"Kinopoisk ids ending in {suffix}…", file=sys.stderr)
        bindings = ask(f"""
            SELECT ?imdb ?kp ?ru ?date WHERE {{
              ?item wdt:P2603 ?kp ; wdt:P345 ?imdb .
              FILTER(STRENDS(?kp, "{suffix}"))
              OPTIONAL {{ ?item rdfs:label ?ru FILTER(LANG(?ru) = "ru") }}
              OPTIONAL {{ ?item wdt:P577 ?date }}
            }}""")
        for b in bindings:
            imdb = imdb_number(b["imdb"]["value"])
            kp = re.sub(r"\D", "", b["kp"]["value"])
            if imdb is None or not kp:
                continue
            r = row(imdb)
            r["kp"] = r["kp"] or int(kp)
            absorb(b, r)
        time.sleep(1)

    # 2. Critics: the Tomatometer (when a statement says which score it is, only that one) and the Metascore.
    for source, key in ((ROTTEN_TOMATOES, "rt"), (METACRITIC, "mc")):
        for digit in "0123456789":
            print(f"{key} scores, IMDb ids ending in {digit}…", file=sys.stderr)
            bindings = ask(f"""
                SELECT ?imdb ?score ?method ?ru ?date WHERE {{
                  ?item p:P444 ?statement ; wdt:P345 ?imdb .
                  FILTER(STRENDS(?imdb, "{digit}"))
                  ?statement ps:P444 ?score ; pq:P447 wd:{source} .
                  OPTIONAL {{ ?statement pq:P459 ?method }}
                  OPTIONAL {{ ?item rdfs:label ?ru FILTER(LANG(?ru) = "ru") }}
                  OPTIONAL {{ ?item wdt:P577 ?date }}
                }}""")
            for b in bindings:
                imdb = imdb_number(b["imdb"]["value"])
                if imdb is None:
                    continue
                method = b.get("method", {}).get("value", "")
                if key == "rt" and method and not method.endswith(TOMATOMETER):
                    continue  # the audience score, not the critics'
                value = percent(b["score"]["value"])
                if value is None:
                    continue
                r = row(imdb)
                r[key] = value if r[key] is None else r[key]
                absorb(b, r)
            time.sleep(1)

    with open(args.out, "w", encoding="utf-8") as out:
        for imdb in sorted(rows):
            r = rows[imdb]
            out.write("\t".join(str(x) if x is not None else "" for x in (imdb, r["kp"], r["year"], r["ru"], r["rt"], r["mc"])) + "\n")
    with_kp = sum(1 for r in rows.values() if r["kp"])
    with_rt = sum(1 for r in rows.values() if r["rt"] is not None)
    with_mc = sum(1 for r in rows.values() if r["mc"] is not None)
    print(f"{len(rows)} titles: {with_kp} with a Kinopoisk id, {with_rt} with RT, {with_mc} with Metacritic → {args.out}", file=sys.stderr)


if __name__ == "__main__":
    main()
