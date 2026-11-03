#!/usr/bin/env python3
"""Open facts about films and series from Wikidata (CC0) for the recommender's data pack.

Writes build/datapack/wikidata.tsv with one line per IMDb id:
    imdb  kp  year  ru_title  rt  mc
  imdb      IMDb id without «tt» (int)
  kp        Kinopoisk film id (int), empty when unknown
  year      first publication year, empty when unknown
  ru_title  the Russian label, empty when there is none
  rt        Rotten Tomatoes critics score (the Tomatometer), 0–100, empty when unknown
  mc        Metacritic metascore, 0–100, empty when unknown

Usage: scripts/datapack/wikidata.py [--out build/datapack/wikidata.tsv]
Three queries to QLever's Wikidata endpoint (qlever.dev, University of Freiburg): the public query service at
query.wikidata.org times out on queries this size. Each answer is streamed to a file as TSV (a few minutes in all).
"""

import argparse
import csv
import os
import re
import sys
import urllib.parse
import urllib.request

ENDPOINT = "https://qlever.dev/api/wikidata"
AGENT = "KinoPohuy-datapack/1.0 (https://github.com/SashaEee/kinopohuy-macos)"
PREFIXES = """PREFIX wd: <http://www.wikidata.org/entity/>
PREFIX wdt: <http://www.wikidata.org/prop/direct/>
PREFIX p: <http://www.wikidata.org/prop/>
PREFIX ps: <http://www.wikidata.org/prop/statement/>
PREFIX pq: <http://www.wikidata.org/prop/qualifier/>
PREFIX rdfs: <http://www.w3.org/2000/01/rdf-schema#>
"""
KINOPOISK = """SELECT ?imdb ?kp ?ru ?date WHERE {
  ?item wdt:P2603 ?kp ; wdt:P345 ?imdb .
  OPTIONAL { ?item rdfs:label ?ru FILTER(LANG(?ru) = "ru") }
  OPTIONAL { ?item wdt:P577 ?date }
}"""
SCORES = """SELECT ?imdb ?score ?method WHERE {
  ?item p:P444 ?statement ; wdt:P345 ?imdb .
  ?statement ps:P444 ?score ; pq:P447 wd:%s .
  OPTIONAL { ?statement pq:P459 ?method }
}"""
ROTTEN_TOMATOES, TOMATOMETER = "Q105584", "Q108403393"
METACRITIC, METASCORE = "Q150248", "Q106515043"


def fetch(query, path):
    """Streams the query's answer to `path` as TSV."""
    url = ENDPOINT + "?" + urllib.parse.urlencode({"query": PREFIXES + query})
    request = urllib.request.Request(url, headers={"User-Agent": AGENT, "Accept": "text/tab-separated-values"})
    with urllib.request.urlopen(request, timeout=600) as response, open(path, "wb") as out:
        while chunk := response.read(1 << 20):
            out.write(chunk)


def rows(path):
    with open(path, encoding="utf-8", newline="") as source:
        reader = csv.reader(source, delimiter="\t", quoting=csv.QUOTE_NONE)
        next(reader, None)
        for row in reader:
            yield [unquote(cell) for cell in row]


def unquote(cell):
    """«"Начало"@ru» → «Начало», «"447301"» → «447301», «<…/Q108403393>» → «Q108403393»."""
    cell = cell.strip()
    if cell.startswith("<") and cell.endswith(">"):
        return cell.rsplit("/", 1)[-1][:-1]
    match = re.match(r'^"(.*)"(?:@[\w-]+|\^\^<[^>]+>)?$', cell)
    return match.group(1).replace('\\"', '"') if match else cell


def imdb_number(value):
    match = re.fullmatch(r"tt(\d+)", value or "")
    return int(match.group(1)) if match else None


def percent(text):
    match = re.match(r"\s*(\d+(?:\.\d+)?)\s*(%|/\s*100)?\s*$", text or "")
    if not match or not match.group(2):
        return None
    value = float(match.group(1))
    return int(round(value)) if 0 <= value <= 100 else None


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", default="build/datapack/wikidata.tsv")
    args = parser.parse_args()
    folder = os.path.dirname(args.out) or "."
    os.makedirs(folder, exist_ok=True)

    titles = {}

    def row(imdb):
        return titles.setdefault(imdb, {"kp": None, "year": None, "ru": "", "rt": None, "mc": None})

    print("Kinopoisk ids, Russian titles, dates…", file=sys.stderr)
    path = os.path.join(folder, "wd-kp.tsv")
    fetch(KINOPOISK, path)
    for imdb, kp, ru, date in ((r + [""] * 4)[:4] for r in rows(path)):
        number = imdb_number(imdb)
        kp = re.sub(r"\D", "", kp)
        if number is None or not kp:
            continue
        r = row(number)
        r["kp"] = r["kp"] or int(kp)
        if ru and not r["ru"]:
            r["ru"] = ru.replace("\t", " ").strip()
        year = re.match(r"(\d{4})", date or "")
        if year:
            r["year"] = int(year.group(1)) if r["year"] is None else min(r["year"], int(year.group(1)))

    for key, source, method_wanted in (("rt", ROTTEN_TOMATOES, TOMATOMETER), ("mc", METACRITIC, METASCORE)):
        print(f"{key} scores…", file=sys.stderr)
        path = os.path.join(folder, f"wd-{key}.tsv")
        fetch(SCORES % source, path)
        for imdb, score, method in ((r + [""] * 3)[:3] for r in rows(path)):
            number = imdb_number(imdb)
            if number is None or (method and method != method_wanted):
                continue  # the audience's average, not the critics' score
            value = percent(score)
            if value is not None and row(number)[key] is None:
                row(number)[key] = value

    with open(args.out, "w", encoding="utf-8") as out:
        for imdb in sorted(titles):
            r = titles[imdb]
            out.write("\t".join("" if x is None else str(x) for x in (imdb, r["kp"], r["year"], r["ru"], r["rt"], r["mc"])) + "\n")
    count = lambda key: sum(1 for r in titles.values() if r[key])
    print(f"{len(titles)} titles: {count('kp')} with a Kinopoisk id, {count('ru')} with a Russian title, "
          f"{count('rt')} with RT, {count('mc')} with Metacritic → {args.out}", file=sys.stderr)


if __name__ == "__main__":
    main()
