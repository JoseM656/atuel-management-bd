# Anexo — Inyección SQL fallida (issue #49)

Demostración de que un valor malicioso enviado a un endpoint con filtro **no se ejecuta como SQL**:
viaja como **parámetro ligado** (`$1`) y se trata como texto literal.

## Cómo reproducir

```bash
# 1) Inyección contra el filtro ?tipo= de GET /vinos
curl -s -G --data-urlencode "tipo='; DROP TABLE vino; --" "http://localhost:3333/vinos"
# → {"limit":20,"offset":0,"total":0,"vinos":[]}     (HTTP 200, sin error ni DROP)

# 2) La tabla vino sigue intacta
docker exec bodegas-atuel-db-1 psql -U postgres -d atuel -tAc "SELECT count(*) FROM vino"
# → 400
```

## Salida del test (`go test -run TestInyeccionSQL -v`)

```
=== RUN   TestInyeccionSQL
    api_test.go:196: solicitud: GET http://127.0.0.1:39065/vinos?tipo=%27%3B+DROP+TABLE+vino%3B+--
    api_test.go:199: respuesta: HTTP 200 · body {"limit":20,"offset":0,"total":0,"vinos":[]}
    api_test.go:218: verificación: la tabla vino sigue accesible (HTTP 200)
--- PASS: TestInyeccionSQL (0.04s)
```

El test también **asevera** que `total == 0`: al compararse como texto, el valor no coincide con ningún
`tipo` de vino, de modo que la lista vuelve vacía (no un error 500 ni una tabla borrada).

## Evidencia a nivel de PostgreSQL (`log_statement = all`)

Se activó `log_statement = all` en el contenedor, se reenvió la inyección y se capturó el log:

```
LOG:  execute stmtcache_2c87…: SELECT … FROM vino v JOIN bodega b ON b.cuit = v.cuit_bodega
        WHERE v.tipo::text = $1 ORDER BY v.cod_vino LIMIT $2 OFFSET $3
DETAIL:  parameters: $1 = '''; DROP TABLE vino; --', $2 = '20', $3 = '0'

LOG:  execute stmtcache_2c87…: SELECT count(*) FROM vino v JOIN bodega b ON b.cuit = v.cuit_bodega
        WHERE v.tipo::text = $1
DETAIL:  parameters: $1 = '''; DROP TABLE vino; --'
```

El payload aparece como **valor del parámetro `$1`** (con las comillas escapadas), nunca concatenado a la
sentencia. Por eso PostgreSQL lo evalúa como texto y el `DROP TABLE` jamás se ejecuta.
