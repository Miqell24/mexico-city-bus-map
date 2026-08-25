#!/usr/bin/env bash
# Downloads input data: the SEMOVI GTFS, OSM networks (Overpass), MapLibre GL.
# Everything is cached — re-running only fetches what is missing.
#
# Mexico City: ONE bundle from SEMOVI carrying every public operator in the
# city — the concessioned corridors and RTP buses, the STE trolleybuses, the
# Metrobús BRT, the Metro, the Tren Ligero, the Cablebús gondolas, the
# Ferrocarril Suburbano, the Tren El Insurgente and the UNAM's Pumabús — each
# under its own agency_id, which is what separates the modes at build time.
#
# The producer, datos.cdmx.gob.mx, is unreachable from outside Mexico: every
# request times out, and the Mobility Database says the same in its own words
# ("temporarily redirecting to old, expired feed version because the new feed
# version is geo-fenced"), as does transit.land, whose fetcher logs
# "dial tcp 189.240.234.183:443: i/o timeout". So this takes the last complete
# copy the Mobility Database managed to mirror: feed mdb-1830, a snapshot of
# the 16.02.2026 file taken on 09.03.2026. If datos.cdmx.gob.mx becomes
# reachable again, DIRECT below is the producer URL to go back to.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p data/gtfs data/osm web/vendor

DIRECT="https://datos.cdmx.gob.mx/dataset/75538d96-3ade-4bc5-ae7d-d85595e4522d/resource/32ed1b6b-41cd-49b3-b7f0-b57acb0eb819/download/gtfs-2.zip"
MIRROR="https://files.mobilitydatabase.org/mdb-1830/mdb-1830-202603090024/mdb-1830-202603090024.zip"

ok_json () { # $1=file  $2=minimum element count
  python3 - "$1" "$2" <<'PYEOF' 2>/dev/null
import json, sys
try:
    sys.exit(0 if len(json.load(open(sys.argv[1])).get("elements", [])) >= int(sys.argv[2]) else 1)
except Exception:
    sys.exit(1)
PYEOF
}

overpass () { # $1=outfile  $2=query  $3=minimum element count
  local out="$1" q="$2" floor="$3" round wait
  for round in 1 2 3 4 5 6 7 8; do
    for EP in "https://overpass-api.de/api/interpreter" \
              "https://maps.mail.ru/osm/tools/overpass/api/interpreter" \
              "https://overpass.kumi.systems/api/interpreter" \
              "https://overpass.private.coffee/api/interpreter"; do
      echo "-- round $round: $EP"
      if curl -fsS --max-time 1800 -o "$out" --data-urlencode "data=$q" "$EP" && ok_json "$out" "$floor"; then
        return 0
      fi
      rm -f "$out"
    done
    wait=$((round * 45))
    echo "-- all mirrors busy, waiting ${wait}s"
    sleep "$wait"
  done
  echo "Overpass: all mirrors failed for $out" >&2
  return 1
}

# 1) GTFS — the producer first (it answers only from inside Mexico), the
#    Mobility Database mirror when it does not
if [ ! -f data/gtfs/routes.txt ]; then
  echo "== GTFS → data/gtfs =="
  if curl -fL --retry 1 --max-time 120 -o data/gtfs.zip "$DIRECT"; then
    echo "   (from datos.cdmx.gob.mx)"
  else
    echo "   producer unreachable — falling back to the Mobility Database mirror"
    curl -fL --retry 3 --max-time 600 -o data/gtfs.zip "$MIRROR"
  fi
  unzip -o data/gtfs.zip -d data/gtfs
fi

# 2) OSM — roadways over the city and its southern boroughs (feed stops
#    19.13–19.58 N, 99.34–98.95 W; RTP reaches Milpa Alta in the south)
if [ ! -f data/osm/mexico.json ]; then
  echo "== Overpass (roads) =="
  overpass data/osm/mexico.json \
    '[out:json][timeout:1800][maxsize:2000000000];way(19.08,-99.42,19.62,-98.92)["highway"~"^(motorway|trunk|primary|secondary|tertiary|unclassified|residential|living_street|service|busway|construction|motorway_link|trunk_link|primary_link|secondary_link|tertiary_link)$"];out geom;' 2000
fi

# 2b) OSM — the fixed-track world: Metro tunnels and viaducts (railway=subway),
#     the Tren Ligero (light_rail), the Suburbano and the Tren El Insurgente
#     (rail — the latter runs 60 km west to Zinacantepec, hence the wide box)
#     and the Cablebús gondolas, which are aerialway=gondola, not railway at
#     all; build.mjs admits them through cfg.railExtra.
if [ ! -f data/osm/mexico-rail.json ]; then
  echo "== Overpass (rails + gondolas) =="
  overpass data/osm/mexico-rail.json \
    '[out:json][timeout:900][maxsize:1000000000];(way(19.15,-99.80,19.72,-98.90)["railway"~"^(subway|light_rail|rail|tram|construction)$"];way(19.15,-99.80,19.72,-98.90)["aerialway"~"^(gondola|cable_car)$"];);out geom;' 200
fi

# 3) MapLibre GL (vendored, no CDN at runtime)
if [ ! -f web/vendor/maplibre-gl.js ]; then
  echo "== MapLibre GL =="
  curl -fL --retry 3 -o web/vendor/maplibre-gl.js  https://unpkg.com/maplibre-gl@5.6.1/dist/maplibre-gl.js
  curl -fL --retry 3 -o web/vendor/maplibre-gl.css https://unpkg.com/maplibre-gl@5.6.1/dist/maplibre-gl.css
fi

echo "OK — data ready:"
du -sh data/gtfs data/osm/*.json 2>/dev/null || true
