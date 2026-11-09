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
| GET | `/clientes` | Lista de clientes con su subtipo (filtro `?tipo=`, búsqueda `?q=` por ID, documento o nombre, paginación) |
| POST | `/clientes` | Alta de un cliente (socio/distribuidor/exportador); el descuento lo asigna la base |
| GET | `/clientes/{id}` | Cliente con su subtipo |
| PUT | `/clientes/{id}` | Reemplaza campos comunes y del subtipo |
| DELETE | `/clientes/{id}` | Baja de un cliente (RN-14 lo rechaza si tiene comprobantes) |
| POST | `/comprobantes` | Venta transaccional: cabecera + renglones; precios/totales los calcula la base |
| POST | `/comprobantes/simular` | Calcula importes con los triggers y hace ROLLBACK (no guarda) |
| GET | `/comprobantes/{nro}` | Detalle de un comprobante con sus renglones |
| GET | `/salas` | Catálogo de salas de venta (para desplegables) |
| GET | `/cepas` | Catálogo de cepas |
| GET | `/bodegas` | Catálogo de bodegas |
| GET | `/maridajes` | Catálogo de maridajes |
| GET | `/transferencias` | Lista paginada con filtros `estado` e `id_sala` |
| POST | `/transferencias` | Alta de una transferencia (en confección) |
| GET | `/transferencias/{nro}` | Detalle con estado actual y renglones |
| POST | `/transferencias/{nro}/renglones` | Carga renglones (solo en confección, RN-12) |
| DELETE | `/transferencias/{nro}/renglones/{cod}` | Quita el renglón de un vino (solo en confección, RN-12) |
| POST | `/transferencias/{nro}/terminar` | Pasa a terminado (`sp_terminar_transferencia`) |
| POST | `/transferencias/{nro}/procesar` | Procesa y mueve stock (`sp_procesar_transferencia`) |
| POST | `/ingresos` | Alta de un ingreso (en confección) |
| POST | `/ingresos/{cod}/renglones` | Carga renglones (solo en confección, RN-12) |
| POST | `/ingresos/{cod}/terminar` | Pasa a terminado (`sp_terminar_ingreso`) |
| POST | `/ingresos/{cod}/procesar` | Procesa e impacta el depósito (`sp_procesar_ingreso`) |
| GET | `/reportes/s1` … `/reportes/s12b` | Consultas S1–S12 (solo lectura) |
| GET | `/reportes/top-vinos` | Tablero: top 10 vinos (lógica de S1, con añada y volumen) |
| GET | `/reportes/ventas-por-sala` | Tablero: ventas por sala del último trimestre (lógica de S8, con localidad y período) |
| GET | `/reportes/transportista-activo` | Tablero: transportista más activo del último mes (lógica de S7, con CUIT y período) |
| GET | `/reportes/vinos-sin-stock?sala=` | Tablero: vinos sin stock en la sala (lógica de S6, con tipo y bodega) |

## Errores

Los errores se devuelven como JSON `{"error": "...", "codigo": "<SQLSTATE>", "restriccion": "<nombre>"}` con el
código HTTP correspondiente al `SQLSTATE`:
`23505`/`23503` → 409 · `23514`/`23502` → 422 · `22P02` → 400 · `40001`/`40P01` → 503 · `RAISE EXCEPTION` (reglas RN/RI) → 409.

El mensaje está en castellano (#88): para `P0001` es el texto del `RAISE EXCEPTION`; para los CHECK, UNIQUE y FK que
el front puede provocar sale de [`internal/httperr/mensajes.go`](../internal/httperr/mensajes.go); el resto recibe un
texto genérico con el nombre de la restricción. La regla vive solo en la base: la API traduce el texto, y
`TestMensajesRestriccionesExisten` verifica contra `pg_constraint` que cada restricción de la tabla siga existiendo.

## Tests

Los tests de integración están en `api/internal/httpapi/api_test.go` (paquete `httpapi`). Levantan el router real con
`httptest` contra una base migrada y seedeada, leída de `TEST_DATABASE_URL`/`DATABASE_URL`; si no hay base, se
**omiten** (`t.Skip`) para no romper `go test ./...` en una máquina sin datos.

```bash
export DATABASE_URL=postgresql://app_rw:…@127.0.0.1:5433/atuel
go test ./...
```

Son **23 pruebas de integración** (el enunciado pide al menos 8). Las que **provocan una violación de regla de la
base y verifican el código HTTP** son:

| Test | Regla | Respuesta |
| --- | --- | --- |
| `TestVentaSinStock` | RN-09 · stock insuficiente | 409 |
| `TestPrecioNegativo` | RN-01 · precio > 0 | 422 |
| `TestCambioEstadoInvalido` | RN-11 · salto de estado | 409 |
| `TestEditarVinoComposicion` | RN-05 · el corte suma 100 | 409 |
| `TestQuitarRenglonTransferencia` | RN-12 · renglones solo en confección | 409 |
| `TestMensajeAnada` | `ck_vino_anada` · mensaje en castellano | 422 |
| `TestMensajeVinoDuplicado` | `uq_vino_nombre_anada_volumen` | 409 |
| `TestMensajeBorradoRN14` | RN-14 · vino con movimientos | 409 |
| `TestMensajeP0001SinEnvoltorio` | RN-11 · texto del trigger sin envoltorio | 409 |

Además, `api/internal/httperr/httperr_test.go` prueba la traducción de errores sin base (corre siempre), y
`TestMensajesRestriccionesExisten` verifica contra `pg_constraint` que cada restricción con mensaje propio exista.

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