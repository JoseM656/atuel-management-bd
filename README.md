# Bodegas del Atuel

TPI de Bases de Datos (UTN FRSR, 2026): sistema de gestión y distribución de una empresa vitivinícola sobre PostgreSQL.

## Base de desarrollo con Docker

Levanta un PostgreSQL 16 con todas las migraciones de `db/migrations/` aplicadas en orden y un set chico de datos falsos (`db/dev/datos_prueba.sql`) para ir probando los `.sql`.

```bash
cp .env.example .env          # y poner una contraseña en POSTGRES_PASSWORD
docker compose up -d
docker exec -it atuel_db psql -U postgres -d atuel
```

Desde DBeaver/pgAdmin: `localhost`, puerto `5433` (o el de `POSTGRES_PORT`), base `atuel`.

Las migraciones solo se aplican cuando el volumen está vacío. Después de agregar o cambiar un archivo en `db/migrations/` o `db/dev/`, recrear la base:

```bash
docker compose down -v && docker compose up -d
```

### Pruebas de reglas de negocio

`db/tests/pruebas_reglas.sql` corre un caso por regla (RN-01…RN-15 y RI) sobre los datos de prueba y muestra `OK` / `FALLA` por cada uno. Termina en `ROLLBACK`, así que no modifica los datos.

```bash
docker exec -i atuel_db psql -U postgres -d atuel < db/tests/pruebas_reglas.sql
```
