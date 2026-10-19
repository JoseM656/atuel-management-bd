# Bodegas del Atuel

TPI de Bases de Datos (UTN FRSR, 2026): sistema de gestión y distribución de una empresa vitivinícola sobre PostgreSQL.

## Base de desarrollo con Docker

Levanta un PostgreSQL 16 con todas las migraciones aplicadas y un set chico de datos falsos para ir probando los `.sql`.

### Qué incluye

- `docker-compose.yml`: levanta el contenedor `atuel_db`, aplica todas las migraciones de `db/migrations/` en orden y carga los datos falsos. Una migración nueva (por ejemplo `006_vistas.sql`) se aplica sola.
- `db/docker/init.sh`: script que corre dentro del contenedor la primera vez y aplica migraciones y datos.
- `db/dev/datos_prueba.sql`: datos falsos (2 salas, 3 vinos, un cliente de cada tipo, ingresos y transferencias en distintos estados).
- `db/tests/pruebas_reglas.sql`: un caso por regla de negocio (RN-01…RN-15 y RI) que muestra `OK` / `FALLA` por cada uno.
- `.env.example`: plantilla de configuración. El `.env` real queda en `.gitignore` y no se sube.

### Primera vez

Cada integrante copia `.env.example` a `.env` y pone una contraseña en `POSTGRES_PASSWORD`:

```bash
cp .env.example .env
docker compose up -d
```

### Conectarse

- Consola: `docker exec -it atuel_db psql -U postgres -d atuel`
- DBeaver / pgAdmin: `localhost`, puerto `5433`, base `atuel`, usuario `postgres`.

Se usa el puerto `5433` (configurable con `POSTGRES_PORT`) para no chocar con un PostgreSQL instalado localmente, que suele ocupar el `5432`.

### Recrear la base

Las migraciones solo se aplican cuando la base arranca vacía. Después de agregar o cambiar un archivo en `db/migrations/` o `db/dev/`, hay que recrearla:

```bash
docker compose down -v && docker compose up -d
```

### Pruebas de reglas de negocio

Corren sobre los datos de prueba y terminan en `ROLLBACK`, así que no modifican nada:

```bash
docker exec -i atuel_db psql -U postgres -d atuel < db/tests/pruebas_reglas.sql
```
