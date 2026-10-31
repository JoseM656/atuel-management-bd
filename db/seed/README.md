# Carga Masiva y Reproducible (`db/seed/`) — Bodegas del Atuel

Este directorio contiene los catálogos reales en CSV (Anexo B), el generador determinista de carga masiva en Python (`seed.py`) y la batería de consultas de control (`consultas_control.sql`) correspondientes a la **Etapa 3**.

---

## 1. Contenido del directorio

| Archivo | Propósito | Filas |
| :--- | :--- | :---: |
| `departamentos.csv` | Los 18 departamentos oficiales de Mendoza (Anexo B.3). | 18 |
| `cepas.csv` | 12 cepas activas del Anexo B.1 + 3 cepas sin uso (`Petit Verdot`, `Cabernet Franc`, `Viognier`) para probar `D2`. | 15 |
| `maridajes.csv` | 8 maridajes del Anexo B.2 + 4 adicionales con temperatura de servicio (°C). No incluye `'cordero al disco'` (`I2`). | 12 |
| `localidades.csv` | 24 localidades reales de Mendoza con su código postal (`San Rafael`, `General Alvear`, etc.). | 24 |
| `bodegas.csv` | 20 bodegas elaboradoras con CUIT de 11 dígitos válido y domicilio en Mendoza. | 20 |
| `transportistas.csv` | 15 empresas de transporte con CUIT único y email válido. | 15 |
| `tipos_vino_presentaciones.csv` | Combinaciones de los 4 `tipo_vino` y las 5 presentaciones (`187` a `3000` ml) con precio base sugerido múltiplo de `100.00`. | 20 |
| `requirements.txt` | Dependencias fijadas: `psycopg[binary]==3.2.3` y `Faker==30.8.2` (sin ORM). | — |
| `seed.py` | Script CLI reproducible con semilla fija, algoritmo *bottom-up* de stock/fechas, manejo transaccional de triggers y carga vía `COPY`. | — |
| `consultas_control.sql` | Conteo de las 31 tablas (Bloque A) y batería de 14 controles de integridad y coherencia `C01..C14` (Bloque B). | — |

---

## 2. Contrato de conexión de `seed.py`

Antes de ejecutar `seed.py`, tené en cuenta cómo resuelve la conexión y qué permisos requiere en la base de datos:

1. **Orden de resolución del DSN (cadena de conexión):**
   1. Argumento explícito por CLI: `--dsn "postgresql://..."`
   2. Variable de entorno: `DATABASE_URL`
   3. Valor por defecto local: `postgresql://postgres:postgres@127.0.0.1:5433/atuel`
   *(Se utiliza `127.0.0.1` en lugar de `localhost` para evitar fallos de resolución dual-stack IPv6 `::1` contra el port-forwarding IPv4 de Docker).*
2. **Prerrequisito obligatorio de migraciones (`001` a `007`):**
   La base de datos destino **debe tener aplicadas previamente las migraciones `001_esquema.sql` a `007_roles.sql` en orden**.
3. **Rol de ejecución (`postgres` $\rightarrow$ `SET ROLE propietario;`):**
   La migración `007_roles.sql` transfiere el ownership de las 31 tablas y vistas al rol `propietario` y revoca privilegios administrativos a `app_rw`. Como `ALTER TABLE ... DISABLE/ENABLE TRIGGER USER` y `REFRESH MATERIALIZED VIEW` exigen ser dueño de las tablas, `seed.py` se conecta con el superusuario (`postgres`) y ejecuta internamente `SET ROLE propietario;` al abrir la transacción de carga.

---

## 3. Requisitos previos y levantado del entorno

### Opción A — Linux / macOS (`bash`)

```bash
# 1. Levantar contenedor PostgreSQL 16 desechable en el puerto 5433
docker rm -f atuel_seed_db 2>/dev/null || true
docker run -d --name atuel_seed_db \
  -e POSTGRES_USER=postgres \
  -e POSTGRES_PASSWORD=postgres \
  -e POSTGRES_DB=atuel \
  -p 127.0.0.1:5433:5432 \
  -v "$PWD/db/migrations:/migrations:ro" \
  postgres:16

# 2. Esperar a que el proceso definitivo acepte conexiones TCP (-h 127.0.0.1 evita el falso positivo del socket Unix durante initdb)
until docker exec atuel_seed_db pg_isready -h 127.0.0.1 -U postgres -d atuel >/dev/null 2>&1; do sleep 1; done

# 3. Aplicar migraciones 001 a 007 en orden
docker exec atuel_seed_db sh -c 'for f in /migrations/*.sql; do echo "==> $f"; psql -U postgres -d atuel -v ON_ERROR_STOP=1 -q -f "$f" || exit 1; done'

# 4. Crear entorno virtual e instalar dependencias
python3 -m venv .venv
.venv/bin/pip install -r db/seed/requirements.txt
```

### Opción B — Windows (`PowerShell`)

```powershell
# 1. Levantar contenedor PostgreSQL 16 desechable en el puerto 5433
$repo = (Resolve-Path ".").Path
docker rm -f atuel_seed_db 2>$null
docker run -d --name atuel_seed_db `
  -e POSTGRES_USER=postgres `
  -e POSTGRES_PASSWORD=postgres `
  -e POSTGRES_DB=atuel `
  -p 127.0.0.1:5433:5432 `
  -v "${repo}\db\migrations:/migrations:ro" `
  postgres:16

# 2. Esperar a que el proceso definitivo acepte conexiones TCP
do {
  Start-Sleep -Seconds 1
  $ready = docker exec atuel_seed_db pg_isready -h 127.0.0.1 -U postgres -d atuel
} while ($ready -notmatch "accepting connections")

# 3. Aplicar migraciones 001 a 007 en orden
Get-ChildItem "$repo\db\migrations\*.sql" | Sort-Object Name | ForEach-Object {
  Write-Host "==> $($_.Name)"
  docker exec atuel_seed_db psql -v ON_ERROR_STOP=1 -U postgres -d atuel -q -f "/migrations/$($_.Name)"
}

# 4. Crear entorno virtual e instalar dependencias
python -m venv .venv
.\.venv\Scripts\pip install -r db\seed\requirements.txt
```

---

## 4. Ejecución del script de carga (`seed.py`)

### Linux / macOS (`bash`)
```bash
# Carga estándar (usa 127.0.0.1:5433, semilla 42 y fecha_ref 2026-10-30 por defecto)
.venv/bin/python -u db/seed/seed.py

# Carga completa con benchmark (fila a fila vs executemany vs COPY) y verificación C01..C14
.venv/bin/python -u db/seed/seed.py \
  --dsn "postgresql://postgres:postgres@127.0.0.1:5433/atuel" \
  --seed 42 \
  --fecha-ref 2026-10-30 \
  --benchmark \
  --verificar
```

### Windows (`PowerShell`)
```powershell
# Carga estándar (usa 127.0.0.1:5433, semilla 42 y fecha_ref 2026-10-30 por defecto)
.\.venv\Scripts\python.exe -u db\seed\seed.py

# Carga completa con benchmark (fila a fila vs executemany vs COPY) y verificación C01..C14
.\.venv\Scripts\python.exe -u db\seed\seed.py `
  --dsn "postgresql://postgres:postgres@127.0.0.1:5433/atuel" `
  --seed 42 `
  --fecha-ref 2026-10-30 `
  --benchmark `
  --verificar
```

### Parámetros soportados por CLI
- `--dsn`: cadena de conexión PostgreSQL (default: `DATABASE_URL` o `postgresql://postgres:postgres@127.0.0.1:5433/atuel`).
- `--seed`: semilla entera para `random.Random` y `Faker` (default: `42`).
- `--fecha-ref`: fecha de referencia `YYYY-MM-DD` para todas las ventanas temporales (default: `2026-10-30`).
- `--benchmark`: ejecuta antes de la carga una comparativa controlada sobre 10.000 filas en tabla temporal midiendo `cur.execute` fila por fila, `cur.executemany` (lotes de 1.000) y `cur.copy` (`COPY ... FROM STDIN`).
- `--verificar`: ejecuta al finalizar todas las validaciones de `db/seed/consultas_control.sql` y termina con código `1` si alguna detecta inconsistencias.

---

## 5. Ejecución manual de las consultas de control

### Linux / macOS (`bash`)
```bash
docker cp db/seed/consultas_control.sql atuel_seed_db:/tmp/consultas_control.sql
docker exec atuel_seed_db psql -v ON_ERROR_STOP=1 -U postgres -d atuel -f /tmp/consultas_control.sql
```

### Windows (`PowerShell`)
```powershell
docker cp db\seed\consultas_control.sql atuel_seed_db:/tmp/consultas_control.sql
docker exec atuel_seed_db psql -v ON_ERROR_STOP=1 -U postgres -d atuel -f /tmp/consultas_control.sql
```

---

## 6. Generación y restauración del volcado (`dump_completo.sql.gz`)

> **Nota para Windows PowerShell 5.1:** No redirigir la salida binaria con `>` desde PowerShell porque recodifica el flujo a UTF-16LE y corrompe el archivo `.gz`. Ejecutar `gzip` dentro del contenedor y copiar con `docker cp`.

### Linux / macOS (`bash`)
```bash
# Generar volcado portable (--no-owner --no-acl)
docker exec atuel_seed_db sh -c "pg_dump -U postgres -d atuel --no-owner --no-acl | gzip -9 > /tmp/dump_completo.sql.gz"
docker cp atuel_seed_db:/tmp/dump_completo.sql.gz ./dump_completo.sql.gz

# Probar restauración en una base limpia y validar con consultas_control.sql
docker exec atuel_seed_db psql -U postgres -c "DROP DATABASE IF EXISTS atuel_restore_test;"
docker exec atuel_seed_db psql -U postgres -c "CREATE DATABASE atuel_restore_test;"
docker exec atuel_seed_db sh -c "gunzip -c /tmp/dump_completo.sql.gz | psql -v ON_ERROR_STOP=1 -U postgres -d atuel_restore_test -q"
docker exec atuel_seed_db psql -v ON_ERROR_STOP=1 -U postgres -d atuel_restore_test -f /tmp/consultas_control.sql
docker exec atuel_seed_db psql -U postgres -c "DROP DATABASE atuel_restore_test;"
```

### Windows (`PowerShell`)
```powershell
# Generar volcado portable (--no-owner --no-acl)
docker exec atuel_seed_db sh -c "pg_dump -U postgres -d atuel --no-owner --no-acl | gzip -9 > /tmp/dump_completo.sql.gz"
docker cp atuel_seed_db:/tmp/dump_completo.sql.gz .\dump_completo.sql.gz

# Probar restauración en una base limpia y validar con consultas_control.sql
docker exec atuel_seed_db psql -U postgres -c "DROP DATABASE IF EXISTS atuel_restore_test;"
docker exec atuel_seed_db psql -U postgres -c "CREATE DATABASE atuel_restore_test;"
docker exec atuel_seed_db sh -c "gunzip -c /tmp/dump_completo.sql.gz | psql -v ON_ERROR_STOP=1 -U postgres -d atuel_restore_test -q"
docker exec atuel_seed_db psql -v ON_ERROR_STOP=1 -U postgres -d atuel_restore_test -f /tmp/consultas_control.sql
docker exec atuel_seed_db psql -U postgres -c "DROP DATABASE atuel_restore_test;"
```
