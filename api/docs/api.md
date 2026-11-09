# API en Go

API REST en Go (`chi` + `pgx`) que expone la capa de datos. La API **no recalcula** totales, descuentos ni stock: delega en las funciones, procedimientos y triggers de la base.

## Requisitos

- PostgreSQL 14+ con las migraciones `001`–`008` aplicadas.
- Rol `app_rw` con contraseña configurada (ver `.env.example`).

## Ejecución

```bash
# docker compose (levanta base + API)
docker compose up --build

# o en local, con una base ya levantada
export $(grep -v '^#' .env | xargs)
go run ./cmd/api
```

## Endpoints

| Método | Ruta | Descripción |
| --- | --- | --- |
| GET | `/salud` | Verifica que la API llega a la base |
| GET | `/vinos` | Lista de vinos con su bodega, con filtros (`?tipo=`, `?cepa=`, `?bodega=`, `?anada=`) y paginación (`?limit=`, `?offset=`) |
| GET | `/vinos/{cod}` | Ficha de un vino: cepas+porcentajes, bodega, maridajes y stock total (S9) |
| POST | `/vinos` | Alta de un vino con composición de cepas y maridajes |
| PUT | `/vinos/{cod}` | Reemplaza los campos de un vino (el cambio de precio se audita, RN-13) |
| DELETE | `/vinos/{cod}` | Baja de un vino (RN-14 lo rechaza si tiene movimientos) |
| GET | `/clientes` | Lista de clientes con su subtipo (filtro `?tipo=`, paginación) |
| POST | `/clientes` | Alta de un cliente (socio/distribuidor/exportador); el descuento lo asigna la base |
| GET | `/clientes/{id}` | Cliente con su subtipo |
| PUT | `/clientes/{id}` | Reemplaza campos comunes y del subtipo |
| DELETE | `/clientes/{id}` | Baja de un cliente (RN-14 lo rechaza si tiene comprobantes) |
| POST | `/comprobantes` | Venta transaccional: cabecera + renglones; precios/totales los calcula la base |
| GET | `/comprobantes/{nro}` | Detalle de un comprobante con sus renglones |
| GET | `/transferencias` | Lista paginada con filtros `estado` e `id_sala` |
| POST | `/transferencias` | Alta de una transferencia (en confección) |
| GET | `/transferencias/{nro}` | Detalle con estado actual y renglones |
| POST | `/transferencias/{nro}/renglones` | Carga renglones (solo en confección, RN-12) |
| POST | `/transferencias/{nro}/terminar` | Pasa a terminado (`sp_terminar_transferencia`) |
| POST | `/transferencias/{nro}/procesar` | Procesa y mueve stock (`sp_procesar_transferencia`) |
| POST | `/ingresos` | Alta de un ingreso (en confección) |
| POST | `/ingresos/{cod}/renglones` | Carga renglones (solo en confección, RN-12) |
| POST | `/ingresos/{cod}/terminar` | Pasa a terminado (`sp_terminar_ingreso`) |
| POST | `/ingresos/{cod}/procesar` | Procesa e impacta el depósito (`sp_procesar_ingreso`) |
| GET | `/reportes/s1` … `/reportes/s12b` | Consultas S1–S12 (solo lectura) |

## Errores

Los errores se devuelven como JSON `{"error": "..."}` con el código HTTP correspondiente al `SQLSTATE`:
`23505`/`23503` → 409 · `23514`/`23502` → 422 · `22P02` → 400 · `40001`/`40P01` → 503 · `RAISE EXCEPTION` (reglas RN/RI) → 409.

## Tests

Los tests de integración están en `api/internal/httpapi/api_test.go` (paquete `httpapi`). Levantan el router real con
`httptest` contra una base migrada y seedeada, leída de `TEST_DATABASE_URL`/`DATABASE_URL`; si no hay base, se
**omiten** (`t.Skip`) para no romper `go test ./...` en una máquina sin datos.

```bash
export DATABASE_URL=postgresql://app_rw:…@127.0.0.1:5433/atuel
go test ./...
```

Son **8 pruebas automáticas**; **3 provocan una violación de regla de la base y verifican el código HTTP**:

| Test | Regla | Respuesta |
| --- | --- | --- |
| `TestVentaSinStock` | RN-09 · stock insuficiente | 409 |
| `TestPrecioNegativo` | RN-01 · precio > 0 | 422 |
| `TestCambioEstadoInvalido` | RN-11 · salto de estado | 409 |

`TestInyeccionSQL` envía `'; DROP TABLE vino; --` al filtro `?tipo=` y verifica que responde 200 con `total == 0`
(tratado como texto, por estar la consulta parametrizada) y que la tabla `vino` sigue accesible.

**Para el informe final** (Etapa 6 / Milestone 9): la captura de la inyección fallida que pide la aceptación de la
issue #49 **ya está generada** en
[`docs/entregables/etapa 6/anexo_inyeccion_sql.md`](../../docs/entregables/etapa%206/anexo_inyeccion_sql.md), con la
salida del test y el log de PostgreSQL (`log_statement=all`) que muestra el payload viajando como parámetro `$1`.
Referenciarla desde el informe; no hace falta regenerarla.

## Documentación

- Especificación OpenAPI: [`openapi.yaml`](openapi.yaml).
- Comandos de prueba `curl`: [`curl.md`](curl.md).
- Anexo de inyección SQL (informe): [`docs/entregables/etapa 6/anexo_inyeccion_sql.md`](../../docs/entregables/etapa%206/anexo_inyeccion_sql.md).