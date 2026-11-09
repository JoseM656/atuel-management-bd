# Bodegas del Atuel

Sistema de gestión y distribución para la empresa vitivinícola ficticia «Bodegas del Atuel»: producción de uva y vino, distribución a través de un depósito central y venta en una red de salas. TPI Bases de Datos · UTN FRSR · 2026.

## Objetivos

<!-- pendiente -->

## Reglas y consultas

<!-- pendiente -->

## API

API REST en Go (`chi` + `pgx`) que expone la capa de datos. La API **no recalcula** totales, descuentos ni stock: delega en las funciones, procedimientos y triggers de la base.

### Requisitos

- PostgreSQL 14+ con las migraciones `001`–`008` aplicadas.
- Rol `app_rw` con contraseña configurada (ver `.env.example`).

### Ejecución

```bash
# docker compose (levanta base + API)
docker compose up --build

# o en local, con una base ya levantada
export $(grep -v '^#' .env | xargs)
go run ./cmd/api
```

### Endpoints

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

### Errores

Los errores se devuelven como JSON `{"error": "..."}` con el código HTTP correspondiente al `SQLSTATE`:
`23505`/`23503` → 409 · `23514`/`23502` → 422 · `22P02` → 400 · `40001`/`40P01` → 503 · `RAISE EXCEPTION` (reglas RN/RI) → 409.

### Documentación

Especificación OpenAPI: [`api/docs/openapi.yaml`](api/docs/openapi.yaml).

## Front

<!-- pendiente -->

## Nube

<!-- pendiente -->
