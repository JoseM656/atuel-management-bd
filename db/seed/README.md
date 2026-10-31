# Carga Masiva y Reproducible (`db/seed/`) — Bodegas del Atuel

Este directorio contiene los catálogos reales en CSV (Anexo B), el generador determinista de carga masiva en Python (`seed.py`) y la batería de consultas de control (`consultas_control.sql`) correspondientes a la **Etapa 3 (Issues #26, #27, #28, #29 y #30)**.

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

## 2. Requisitos previos y configuración del entorno

1. **Base de datos PostgreSQL 14+ con las migraciones `001` a `007` aplicadas en orden:**
   ```powershell
   $repo = (Resolve-Path ".").Path
   docker run -d --name atuel_seed_db `
     -e POSTGRES_USER=postgres `
     -e POSTGRES_PASSWORD=postgres `
     -e POSTGRES_DB=atuel `
     -p 5433:5432 `
     -v "${repo}\db\migrations:/migrations:ro" `
     postgres:16

   Get-ChildItem "$repo\db\migrations\*.sql" | Sort-Object Name | ForEach-Object {
     docker exec atuel_seed_db psql -v ON_ERROR_STOP=1 -U postgres -d atuel -q -f "/migrations/$($_.Name)"
   }
   ```

2. **Entorno virtual de Python 3.11+:**
   ```powershell
   python -m venv .venv
   .\.venv\Scripts\pip install -r db\seed\requirements.txt
   ```

3. **Rol de conexión:**
   Como `007_roles.sql` transfiere el ownership de las 31 tablas al rol `propietario` y revoca permisos administrativos a `app_rw`, `seed.py` se conecta con el superusuario (`postgres`) y ejecuta internamente `SET ROLE propietario;` dentro de la transacción de carga.

---

## 3. Ejecución del script de carga (`seed.py`)

### Carga estándar (semilla `42`, fecha de referencia `2026-10-30`)
```powershell
.\.venv\Scripts\python.exe -u db\seed\seed.py
```

### Carga con benchmark (`fila a fila` vs `executemany` vs `COPY`) y verificación automática (`C01..C14`)
```powershell
.\.venv\Scripts\python.exe -u db\seed\seed.py --dsn "postgresql://postgres:postgres@localhost:5433/atuel" --seed 42 --fecha-ref 2026-10-30 --benchmark --verificar
```

### Parámetros soportados por CLI
- `--dsn`: cadena de conexión PostgreSQL (por defecto lee `DATABASE_URL` o usa `postgresql://postgres:postgres@localhost:5433/atuel`).
- `--seed`: semilla entera para `random.Random` y `Faker` (default: `42`).
- `--fecha-ref`: fecha de referencia `YYYY-MM-DD` para todas las ventanas temporales (default: `2026-10-30`).
- `--benchmark`: ejecuta antes de la carga una comparativa controlada sobre 10.000 filas en tabla temporal midiendo `cur.execute` fila por fila, `cur.executemany` (lotes de 1.000) y `cur.copy` (`COPY ... FROM STDIN`).
- `--verificar`: ejecuta al finalizar todas las validaciones de `db/seed/consultas_control.sql` y termina con código `1` si alguna detecta inconsistencias.

---

## 4. Ejecución manual de las consultas de control

```powershell
docker cp db\seed\consultas_control.sql atuel_seed_db:/tmp/consultas_control.sql
docker exec atuel_seed_db psql -v ON_ERROR_STOP=1 -U postgres -d atuel -f /tmp/consultas_control.sql
```

---

## 5. Generación y restauración del volcado (`dump_completo.sql.gz`)

> **Nota para Windows PowerShell 5.1:** No redirigir la salida binaria con `>` desde PowerShell porque recodifica el flujo a UTF-16LE y corrompe el archivo `.gz`. Ejecutar `gzip` dentro del contenedor y copiar con `docker cp`.

### Opción A — Volcado portable (`--no-owner --no-acl`, recomendado para restaurar en cualquier servidor o nube sin requerir superusuario)
```powershell
docker exec atuel_seed_db sh -c "pg_dump -U postgres -d atuel --no-owner --no-acl | gzip -9 > /tmp/dump_completo.sql.gz"
docker cp atuel_seed_db:/tmp/dump_completo.sql.gz .\dump_completo.sql.gz
```

### Opción B — Volcado completo con roles (`propietario`, `app_rw`, `reportes_ro` ya creados en el servidor destino)
```powershell
docker exec atuel_seed_db sh -c "pg_dump -U postgres -d atuel | gzip -9 > /tmp/dump_completo_con_roles.sql.gz"
```

### Restauración y verificación en una base limpia
```powershell
docker exec atuel_seed_db psql -U postgres -c "DROP DATABASE IF EXISTS atuel_restore_test; CREATE DATABASE atuel_restore_test;"
docker exec atuel_seed_db sh -c "gunzip -c /tmp/dump_completo.sql.gz | psql -v ON_ERROR_STOP=1 -U postgres -d atuel_restore_test -q"
docker exec atuel_seed_db psql -v ON_ERROR_STOP=1 -U postgres -d atuel_restore_test -f /tmp/consultas_control.sql
docker exec atuel_seed_db psql -U postgres -c "DROP DATABASE atuel_restore_test;"
```
