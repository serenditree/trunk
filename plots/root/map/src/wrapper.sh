#!/bin/bash

if [[ ! -f data/osm.mbtiles ]]; then
    echo "Database osm.mbtiles does not exist. Aborting..."
    exit 1
fi

exec ./tileserver-gl osm.mbtiles --config config.json --silent --bind 0.0.0.0 --port "$TILESERVER_PORT"
