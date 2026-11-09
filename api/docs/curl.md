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

# Búsqueda por nombre: parcial y sin distinguir mayúsculas
curl -i 'http://localhost:3333/vinos?nombre=reserva'

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

## Clientes — listado y detalle

```bash
# Lista (con filtro ?tipo= y paginación)
curl 'http://localhost:3333/clientes?tipo=socio&limit=5'

# Búsqueda ?q=: ID exacto (primero), documento que empieza con (ignora guiones) o nombre
curl 'http://localhost:3333/clientes?q=18500&limit=20'
curl 'http://localhost:3333/clientes?q=30-8001&tipo=exportador&limit=20'

# Detalle con subtipo
curl http://localhost:3333/clientes/1
```

## Clientes — alta (`POST /clientes`)

```bash
# Socio (sin campos de subtipo)
curl -i -X POST http://localhost:3333/clientes \
  -H 'Content-Type: application/json' \
  -d '{"nombre_razon_social":"Socio Test","tipo_doc":"DNI","nro_doc":"39999999","direccion":"Calle 1","id_localidad":1,"tipo":"socio"}'

# Distribuidor
curl -i -X POST http://localhost:3333/clientes \
  -H 'Content-Type: application/json' \
  -d '{"nombre_razon_social":"Distri Test","tipo_doc":"CUIT","nro_doc":"30999999991","direccion":"Calle 2","id_localidad":1,"tipo":"distribuidor","zona_cobertura":"Sur","nro_habilitacion":"HAB-TEST"}'

# Exportador (con permisos; >3 permisos -> descuento 35 %)
curl -i -X POST http://localhost:3333/clientes \
  -H 'Content-Type: application/json' \
  -d '{"nombre_razon_social":"Export Test","tipo_doc":"CUIT","nro_doc":"30999999992","direccion":"Calle 3","id_localidad":1,"tipo":"exportador","pais_destino":"Chile","permisos":[{"codigo":"P-1","fecha_emision":"2025-01-01","fecha_vencimiento":"2026-01-01"}]}'
```

El `descuento` NO se envía: lo asigna la base (socio 10, distribuidor 20, exportador 30/35).

## Clientes — modificación y baja

```bash
curl -i -X PUT http://localhost:3333/clientes/20002 \
  -H 'Content-Type: application/json' \
  -d '{"nombre_razon_social":"Distri Test","tipo_doc":"CUIT","nro_doc":"30999999991","direccion":"Calle 2 bis","id_localidad":1,"zona_cobertura":"Norte","nro_habilitacion":"HAB-TEST"}'

# RN-14: rechaza si tiene comprobantes → 409
curl -i -X DELETE http://localhost:3333/clientes/366
```

## Comprobantes — venta (`POST /comprobantes`)

```bash
# Venta transaccional: cabecera + renglones en una sola operación.
# La API NO envía precios; la base calcula descuento, precios y totales,
# valida el stock (RN-09) y lo descuenta.
curl -i -X POST http://localhost:3333/comprobantes \
  -H 'Content-Type: application/json' \
  -d '{
    "id_cliente": 1,
    "id_sala": 1,
    "renglones": [
      {"cod_vino": 1, "cantidad": 2},
      {"cod_vino": 2, "cantidad": 1}
    ]
  }'
# → 201 {"nro": N}

# Venta sin stock → 409 (no deja datos a medias)
curl -i -X POST http://localhost:3333/comprobantes \
  -H 'Content-Type: application/json' \
  -d '{"id_cliente": 1, "id_sala": 1, "renglones": [{"cod_vino": 1, "cantidad": 999999}]}'
```

## Comprobantes — simulación (`POST /comprobantes/simular`)

```bash
# Mismo cuerpo que una venta. La base calcula precio, descuento y total con sus
# triggers y la transacción termina en ROLLBACK: no guarda nada ni toca stock.
curl -i -X POST http://localhost:3333/comprobantes/simular \
  -H 'Content-Type: application/json' \
  -d '{"id_cliente": 2, "id_sala": 1, "renglones": [{"cod_vino": 1, "cantidad": 6}]}'
# → 200 {"nro":0, "subtotal":..., "porcentaje_descuento":..., "total":..., "renglones":[...]}

# Sin stock → 409 con el mismo mensaje que una venta real (RN-09)
```

## Comprobantes — detalle (`GET /comprobantes/{nro}`)

```bash
# Cabecera (cliente, sala, subtotal, descuento, total) + renglones
curl http://localhost:3333/comprobantes/1

# No existe → 404
curl -i http://localhost:3333/comprobantes/99999999

# Número inválido → 400
curl -i http://localhost:3333/comprobantes/abc
```

## Transferencias (`POST /transferencias` y sub-recursos)

```bash
# 1. Alta (nace en_confeccion; la fecha la pone la base)
curl -i -X POST http://localhost:3333/transferencias \
  -H 'Content-Type: application/json' \
  -d '{"id_sala": 1}'
# → 201 {"nro": N}

# 2. Cargar renglones mientras está en_confeccion
curl -i -X POST http://localhost:3333/transferencias/N/renglones \
  -H 'Content-Type: application/json' \
  -d '[{"cod_vino": 1, "cantidad": 5}]'
# → 204

# 3. Terminar (en_confeccion -> terminado)
curl -i -X POST http://localhost:3333/transferencias/N/terminar
# → 204

# 4. Procesar (descuenta depósito, suma a la sala, -> procesado)
curl -i -X POST http://localhost:3333/transferencias/N/procesar
# → 204

# Renglón sobre una transferencia ya terminada → 409 (RN-12)
# Procesar sin stock suficiente → 409 (RN-11)
```

## Transferencias — consulta (`GET /transferencias` y `GET /transferencias/{nro}`)

```bash
# Detalle: cabecera con el estado actual (RN-11) + renglones
curl -i http://localhost:3333/transferencias/1
# → 200 {"nro":1,"id_sala":1,"sala":"...","fecha_confeccion":"...","estado":"procesado","renglones":[...]}

# No existe → 404 · Número inválido → 400
curl -i http://localhost:3333/transferencias/99999999
curl -i http://localhost:3333/transferencias/abc

# Listado, de la más reciente a la más antigua (limit=20 por defecto)
curl -i 'http://localhost:3333/transferencias?limit=5'

# Filtros: estado (en_confeccion | terminado | procesado) y sala
curl -i 'http://localhost:3333/transferencias?estado=terminado&id_sala=1'

# Estado inexistente → 400 (lo rechaza el ENUM de la base, SQLSTATE 22P02)
curl -i 'http://localhost:3333/transferencias?estado=anulado'
```

## Ingresos (`POST /ingresos` y sub-recursos)

```bash
# 1. Alta (nace en_confeccion; transportista debe cubrir el depósito, RI-05)
curl -i -X POST http://localhost:3333/ingresos \
  -H 'Content-Type: application/json' \
  -d '{"cod_transportista": 1, "cuit_bodega": "30700000019"}'
# → 201 {"cod_ingreso": N}

# 2. Cargar renglones (vinos de la bodega de origen, RI-04)
curl -i -X POST http://localhost:3333/ingresos/N/renglones \
  -H 'Content-Type: application/json' \
  -d '[{"cod_vino": 1, "cantidad": 120}]'
# → 204

# 3. Terminar (en_confeccion -> terminado)
curl -i -X POST http://localhost:3333/ingresos/N/terminar
# → 204

# 4. Procesar (suma al depósito, -> procesado)
curl -i -X POST http://localhost:3333/ingresos/N/procesar
# → 204

# Procesar un ingreso que no está terminado → 409 (RN-10)
# Vino ajeno a la bodega → 409 (RI-04)
```

## Catálogos — desplegables del front (solo lectura)

```bash
# Listas completas, sin paginar, ordenadas por nombre
curl -i http://localhost:3333/salas       # → [{"id_sala":7,"descripcion":"Av. Principal 70 715, Agrelo","localidad":"Agrelo"}, ...]
curl -i http://localhost:3333/cepas       # → [{"id_cepa":5,"nombre":"Bonarda","tipo":"tinta"}, ...]
curl -i http://localhost:3333/bodegas     # → [{"cuit":"30700000085","razon_social":"Bodega Altos del Diamante S.A."}, ...]
curl -i http://localhost:3333/maridajes   # → [{"id_maridaje":4,"nombre":"Carnes blancas","temperatura_servicio":12}, ...]
```

## Reportes — consultas S1–S12 (solo lectura)

```bash
# S1: top 10 vinos por botellas vendidas
curl http://localhost:3333/reportes/s1

# S2: vinos vendidos en todas las salas
curl http://localhost:3333/reportes/s2

# S3: clientes por tipo que compraron en la sala 12 (última semana)
curl 'http://localhost:3333/reportes/s3?sala=12'

# S4: top 5 salas que pidieron el vino 1 por transferencia (15 días)
curl 'http://localhost:3333/reportes/s4?vino=1'

# S5: salas con menos transferencias pendientes
curl http://localhost:3333/reportes/s5

# S6: vinos sin stock en la sala 12 pero con stock en depósito
curl 'http://localhost:3333/reportes/s6?sala=12'

# S7: transportista más activo del último mes
curl http://localhost:3333/reportes/s7

# S8: monto de ventas por sala (último trimestre)
curl http://localhost:3333/reportes/s8

# S9: ficha del vino 1 (cepas, bodega, maridajes, stock total)
curl 'http://localhost:3333/reportes/s9?vino=1'

# S10: rendimiento kg/ha por parcela/campaña
curl http://localhost:3333/reportes/s10

# S11: ranking de vinos por sala + acumulado mensual
curl http://localhost:3333/reportes/s11

# S12a: clientes que compraron todos los vinos de una bodega
curl 'http://localhost:3333/reportes/s12a?bodega=30700000019'

# S12b: clientes que nunca compraron vino tinto
curl http://localhost:3333/reportes/s12b
```

## Errores (SQLSTATE → HTTP)

| SQLSTATE | Significado | HTTP |
| --- | --- | --- |
| `23505` / `23503` | unique / foreign_key_violation | 409 |
| `23514` / `23502` | check / not_null | 422 |
| `22P02` | invalid_text_representation | 400 |
| `40001` / `40P01` | serialization / deadlock | 503 |
| `P0001` | RAISE EXCEPTION (reglas RN/RI) | 409 |
