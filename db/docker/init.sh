#!/bin/bash
# Lo ejecuta la imagen de postgres la primera vez que arranca (volumen vacío).
# Aplica las migraciones en orden y después los datos de prueba.
set -e

for f in /migrations/*.sql; do
    echo "==> migración $(basename "$f")"
    psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" -q -f "$f"
done

for f in /dev-data/*.sql; do
    echo "==> datos de prueba $(basename "$f")"
    psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" -q -f "$f"
done
