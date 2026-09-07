#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Cuts data/osm/mexico.json (roads) and data/osm/mexico-rail.json (rails and
the Cablebús gondolas) out of the Geofabrik mexico-latest.osm.pbf — the same
JSON shape Overpass returns ('elements': ways with tags, node ids and
geometry), so build.mjs cannot tell the difference. Written 7.09.2026 when
every public Overpass mirror sat on the 54 × 50 km road query for an hour;
the boxes are the ones download.sh queries.
"""
import json, os, re, sys
import osmium

ROOT = os.path.join(os.path.dirname(__file__), '..')
PBF = os.path.join(ROOT, 'data', 'mexico-latest.osm.pbf')
ROAD_BOX = (19.08, -99.42, 19.62, -98.92)   # S, W, N, E — as download.sh
RAIL_BOX = (19.15, -99.80, 19.72, -98.90)
HW = re.compile(r'^(motorway|trunk|primary|secondary|tertiary|unclassified|residential|living_street|service|busway|construction|motorway_link|trunk_link|primary_link|secondary_link|tertiary_link)$')
RAIL = re.compile(r'^(subway|light_rail|rail|tram|construction)$')
AERIAL = re.compile(r'^(gondola|cable_car)$')

road_file = os.path.join(ROOT, 'data/osm/mexico.json')
rail_file = os.path.join(ROOT, 'data/osm/mexico-rail.json')
need_road, need_rail = not os.path.exists(road_file), not os.path.exists(rail_file)
print('roads:', need_road, '| rails:', need_rail, flush=True)
if not need_road and not need_rail:
    sys.exit(0)
if not os.path.exists(PBF):
    sys.exit(f'brak {PBF}')
os.makedirs(os.path.join(ROOT, 'data/osm'), exist_ok=True)
FS = min(ROAD_BOX[0], RAIL_BOX[0]); FW = min(ROAD_BOX[1], RAIL_BOX[1])
FN = max(ROAD_BOX[2], RAIL_BOX[2]); FE = max(ROAD_BOX[3], RAIL_BOX[3])
out_road, out_rail = [], []


class H(osmium.SimpleHandler):
    def way(self, w):
        tags = w.tags
        hw, rw, aw = tags.get('highway'), tags.get('railway'), tags.get('aerialway')
        is_road = need_road and hw is not None and HW.match(hw)
        is_rail = need_rail and ((rw is not None and RAIL.match(rw)) or (aw is not None and AERIAL.match(aw)))
        if not is_road and not is_rail:
            return
        geom, ids = [], []
        la0, la1, lo0, lo1 = 90.0, -90.0, 180.0, -180.0
        for n in w.nodes:
            try:
                lo, la = n.lon, n.lat
            except osmium.InvalidLocationError:
                continue
            ids.append(n.ref)
            geom.append({'lat': la, 'lon': lo})
            if la < la0: la0 = la
            if la > la1: la1 = la
            if lo < lo0: lo0 = lo
            if lo > lo1: lo1 = lo
        if len(geom) < 2 or la1 < FS or la0 > FN or lo1 < FW or lo0 > FE:
            return
        el = {'type': 'way', 'id': w.id, 'nodes': ids, 'tags': {t.k: t.v for t in tags}, 'geometry': geom}
        if is_road and la1 >= ROAD_BOX[0] and la0 <= ROAD_BOX[2] and lo1 >= ROAD_BOX[1] and lo0 <= ROAD_BOX[3]:
            out_road.append(el)
        if is_rail and la1 >= RAIL_BOX[0] and la0 <= RAIL_BOX[2] and lo1 >= RAIL_BOX[1] and lo0 <= RAIL_BOX[3]:
            out_rail.append(el)


print('czytam', os.path.basename(PBF), flush=True)
H().apply_file(PBF, locations=True, idx='flex_mem')
GEN = 'pbf-cut.py (Geofabrik mexico-latest)'
if need_road:
    json.dump({'version': 0.6, 'generator': GEN, 'elements': out_road}, open(road_file, 'w'))
    print(f'drogi: {len(out_road)}', flush=True)
if need_rail:
    json.dump({'version': 0.6, 'generator': GEN, 'elements': out_rail}, open(rail_file, 'w'))
    print(f'szyny + gondole: {len(out_rail)}', flush=True)
print('gotowe', flush=True)
