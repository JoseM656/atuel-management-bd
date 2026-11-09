# Comandos curl — API Bodegas del Atuel

Base: `http://localhost:3333` (con el servidor levantado: `docker compose up` o `go run ./cmd/api`).

Para formatear el JSON usá `jq` o `python3 -m json.tool`.

> Esta documentación es para hacer pruebas en local.

## Salud

```bash
# ¿La API llega a la base?
curl -i http://localhost:3333/salud
# → 200 {"estado":"ok"}
```

## Vinos — listado (`GET /vinos`)

```bash
# Todos (página por defecto: limit=20)
curl http://localhost:3333/vinos

# Paginación: 5 por página, salteando 10
curl 'http://localhost:3333/vinos?limit=5&offset=10'

# Filtro por tipo (tinto | blanco | rosado | espumante)
curl 'http://localhost:3333/vinos?tipo=tinto'

# Filtro por cepa (busca la cepa del corte, no el nombre del vino)
curl 'http://localhost:3333/vinos?cepa=Malbec'

# Filtro por bodega (razón social, URL-encoded)
curl 'http://localhost:3333/vinos?bodega=Bodega%20Atuel%20del%20Sur%20S.A.'

# Filtro por añada
curl 'http://localhost:3333/vinos?anada=2020'

# Combinados
curl 'http://localhost:3333/vinos?tipo=tinto&anada=2020&limit=10'
```

Respuesta del listado: `{"total": N, "limit": L, "offset": O, "vinos": [...]}`.

## Vinos — ficha (`GET /vinos/{cod}`)

```bash
# Ficha completa: cabecera + bodega + stock_total + cepas + maridajes
curl http://localhost:3333/vinos/1

# No existe → 404
curl -i http://localhost:3333/vinos/9999

# Código inválido → 400
curl -i http://localhost:3333/vinos/abc
```

## Vinos — alta (`POST /vinos`)

```bash
# Alta con composición (suma 100) y al menos un maridaje
curl -i -X POST http://localhost:3333/vinos \
  -H 'Content-Type: application/json' \
  -d '{
    "nombre": "Vino de Prueba",
    "tipo": "tinto",
    "anada": 2022,
    "volumen_ml": 750,
    "graduacion": 13.5,
    "precio": 8000,
    "cuit_bodega": "30700000019",
    "cepas": [{"id_cepa": 1, "porcentaje": 60}, {"id_cepa": 2, "porcentaje": 40}],
    "maridajes": [1]
  }'
# → 201 {"cod_vino": N}

# Cortes que no suman 100 → 409
# Maridajes vacíos → 409
```

## Vinos — modificación (`PUT /vinos/{cod}`)

```bash
# Reemplaza los campos; el cambio de precio lo audita RN-13
curl -i -X PUT http://localhost:3333/vinos/1 \
  -H 'Content-Type: application/json' \
  -d '{"nombre":"Malbec Reserva B1","tipo":"tinto","anada":2020,"volumen_ml":750,"graduacion":14.5,"precio":9000,"cuit_bodega":"30700000019"}'
# → 204 (sin cuerpo)
```

## Vinos — baja (`DELETE /vinos/{cod}`)

```bash
# RN-14: rechaza si el vino tiene movimientos/auditoría → 409
curl -i -X DELETE http://localhost:3333/vinos/1

# Un vino recién creado (sin movimientos) → 204
curl -i -X DELETE http://localhost:3333/vinos/401
```

## Errores (SQLSTATE → HTTP)

| SQLSTATE | Significado | HTTP |
| --- | --- | --- |
| `23505` / `23503` | unique / foreign_key_violation | 409 |
| `23514` / `23502` | check / not_null | 422 |
| `22P02` | invalid_text_representation | 400 |
| `40001` / `40P01` | serialization / deadlock | 503 |
| `P0001` | RAISE EXCEPTION (reglas RN/RI) | 409 |
