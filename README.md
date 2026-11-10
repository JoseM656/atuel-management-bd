# Bodegas del Atuel — Sistema de Gestión y Distribución Vitivinícola

> **Trabajo Práctico Integrador · Bases de Datos · Ingeniería en Sistemas · UTN Facultad Regional San Rafael · Ciclo 2026**

Sistema integral para la empresa vitivinícola ficticia **«Bodegas del Atuel»**, que abarca la producción primaria de uva en fincas y parcelas, controles de calidad de cosecha, elaboración de vinos en bodegas del grupo, logística de abastecimiento hacia un depósito central, redistribución a una red de salas de venta regionales y facturación comercial a socios, distribuidores y exportadores.

---

## 1. Objetivos y Principio de Diseño (*Regla de Oro*)

La arquitectura está diseñada en tres capas (**PostgreSQL 16** + **API REST en Go** + **Frontend en Alpine.js**) donde **la capa de datos es el corazón del sistema**:

- **Esquema Relacional Normalizado (3FN):** 31 tablas y 37 claves foráneas con acciones referenciales justificadas (`RESTRICT` en movimientos/catálogos y `CASCADE` únicamente en dependientes débiles), tipos enumerados (`ENUM`) y dominio propio (`DOMAIN cuit`).
- **Lógica e Integridad en la Base de Datos:** Todas las reglas de negocio explícitas (**RN-01 a RN-15**) e implícitas (**RI-01 a RI-07**) viven dentro de PostgreSQL mediante `CHECK`, `UNIQUE`, índices únicos de expresión, funciones (`fn_*`), procedimientos transaccionales (`sp_*`) y triggers (`BEFORE`, `AFTER` y `CONSTRAINT TRIGGER DEFERRABLE INITIALLY DEFERRED`).
- **Sin ORM ni Cálculo fuera de la Base:** La API Go (`chi` + `pgxpool`) y el Frontend Alpine.js **no recalculan** precios, descuentos, subtotales, totales ni saldos de stock; invocan directamente el SQL parametrizado, las funciones y los procedimientos de la base, y traducen los errores `SQLSTATE` a respuestas HTTP claras en castellano.
- **Seguridad por Privilegios Mínimos:** La API se conecta exclusivamente con el rol restringido `app_rw` (sin permisos de DDL ni de superusuario).

---

## 2. Estructura del Repositorio

```text
/
├── README.md                          # Guía principal reproducible del proyecto
├── docker-compose.yml                 # Orquestación de Base (PostgreSQL 16), API (Go) y Front (Nginx)
├── .env.example                       # Plantilla de variables de entorno (sin secretos reales)
├── db/
│   ├── docker/
│   │   └── init.sh                    # Script de inicialización automática del contenedor PostgreSQL
│   ├── migrations/
│   │   ├── 001_esquema.sql            # Dominios, tipos ENUM, 31 tablas, PKs y 37 FKs
│   │   ├── 002_constraints.sql        # Restricciones UNIQUE, CHECK y DEFAULT
│   │   ├── 003_funciones.sql          # 4 funciones SQL/PLpgSQL (stock, totales, descuento, antigüedad)
│   │   ├── 004_procedimientos.sql     # Procedimientos transaccionales de ingresos y transferencias
│   │   ├── 005_triggers.sql           # 16 funciones de trigger y 21 triggers (incl. diferidos)
│   │   ├── 006_vistas.sql             # 4 vistas (stock total, ventas mensuales materializada, pendientes, clientes)
│   │   ├── 007_roles.sql              # Roles propietario, app_rw y reportes_ro con privilegios mínimos
│   │   └── 008_indices.sql            # 5 índices de optimización justificados con EXPLAIN (ANALYZE, BUFFERS)
│   ├── seed/
│   │   ├── *.csv                      # Catálogos reales de Mendoza (departamentos, localidades, cepas, maridajes, etc.)
│   │   ├── seed.py                    # Generador determinista (seed=42) de 729.551 filas vía COPY
│   │   ├── consultas_control.sql      # 14 controles de integridad post-carga (C01..C14)
│   │   └── README.md                  # Documentación detallada de la carga masiva y generación del dump
│   └── tests/
│       ├── db_tests.sql               # 43 pruebas automáticas de reglas RN-01..15 y RI-01..07
│       └── db_tests_roles.sql         # Pruebas de permisos de los roles app_rw y reportes_ro
├── consultas/
│   ├── update.sql                     # Operaciones de modificación (U1–U6) en transacción con ROLLBACK
│   ├── insert.sql                     # Operaciones de inserción (I1–I6) en transacción con ROLLBACK
│   ├── delete.sql                     # Operaciones de borrado (D1–D6) en transacción con ROLLBACK
│   └── select.sql                     # Consultas básicas (S1–S8) y avanzadas (S9–S12)
├── api/                               # API REST en Go 1.26 (chi + pgx/v5) sin ORM
│   ├── Dockerfile                     # Construcción multi-stage (golang:1.26 → alpine:3 con binario estático)
│   ├── cmd/api/main.go                # Punto de entrada del servidor HTTP
│   ├── internal/                      # Paquetes config, db, httpapi y httperr (traducción SQLSTATE→HTTP)
│   └── docs/                          # Documentación de la API (api.md, openapi.yaml, curl.md)
├── front/                             # Interfaz web en HTML5 + CSS + Alpine.js (5 pantallas)
│   ├── nginx.conf                     # Configuración Nginx (sirve estáticos y proxya /api/ → api:3333)
│   ├── index.html                     # SPA con pestañas de las 5 pantallas requeridas
│   └── js/                            # Módulos por pantalla (api.js, catalogo.js, vino.js, venta.js, transferencias.js, tablero.js)
└── docs/
    ├── informe_final.md               # Informe final integrador (Sección 10.2, capítulos 1 a 9)
    └── entregables/                   # Entregables detallados por etapa (DER, diccionario, informes Etapas 1 a 8)
```

---

## 3. Requisitos Previos

- **Ejecución completa con contenedores (recomendado):**
  - [Docker](https://docs.docker.com/get-docker/) y **Docker Compose v2** (`docker compose`).
- **Herramientas opcionales en la máquina anfitriona** (solo si se desea correr el generador `seed.py` o `go test` fuera de Docker):
  - **Python 3.10+** con `psycopg[binary]` y `Faker` (`pip install "psycopg[binary]" Faker`).
  - **Go 1.26+** y cliente **`psql`** (o usar directamente `docker compose exec db psql ...`).

---

## 4. Cómo Levantar Todo en Local con Docker Compose

En una máquina limpia, **un solo comando** levanta la base de datos con las migraciones `001`–`008` aplicadas, la API Go conectada con el rol `app_rw` y el Frontend servido por Nginx:

```bash
# 1. Crear el archivo .env a partir de la plantilla
cp .env.example .env

# 2. Construir y levantar los 3 servicios (db, api, front)
docker compose up --build -d
```

### Servicios expuestos en local

| Servicio | Contenedor | URL / Puerto en Host | Descripción |
| :--- | :--- | :--- | :--- |
| **Frontend Web** | `front` (`nginx:1.27-alpine`) | [`http://localhost:8080`](http://localhost:8080) | Interfaz de usuario con las 5 pantallas y proxy inverso `/api/*` |
| **API REST** | `api` (`Go 1.26 alpine:3`) | [`http://localhost:3333`](http://localhost:3333) | Backend HTTP JSON (ver [`http://localhost:3333/salud`](http://localhost:3333/salud)) |
| **PostgreSQL 16** | `db` (`postgres:16`) | `localhost:5433` (BD: `atuel`) | Motor relacional (mapeado al puerto `5433` del host para no colisionar con instancias locales en `5432`) |

Para verificar que los tres contenedores están saludables y que la API responde desde la base:

```bash
docker compose ps
curl http://localhost:3333/salud
# Respuesta esperada: {"estado":"ok"}
```

---

## 5. Ejecución de Migraciones, Carga Masiva (`seed.py`) y Pruebas

### 5.1. Aplicar migraciones manualmente (opcional)
Al iniciar el contenedor `db` por primera vez, el script [`db/docker/init.sh`](db/docker/init.sh) ejecuta automáticamente todas las migraciones `db/migrations/001_esquema.sql` a `008_indices.sql` en orden alfabético y asigna la contraseña de `app_rw`. Si se desea aplicarlas sobre una base PostgreSQL externa:

```bash
for f in db/migrations/*.sql; do
  psql "postgresql://postgres:postgres@127.0.0.1:5433/atuel" -v ON_ERROR_STOP=1 -f "$f"
done
```

### 5.2. Ejecutar la carga masiva reproducible (Etapa 3 — 729.551 filas)
Con el contenedor `db` corriendo en el puerto `5433`, instalar las dependencias en un entorno virtual y ejecutar [`db/seed/seed.py`](db/seed/seed.py):

```bash
python -m venv .venv
# En Linux/macOS: source .venv/bin/activate
# En Windows PowerShell: .\.venv\Scripts\Activate.ps1
pip install "psycopg[binary]>=3.1" "Faker>=24.0"

python db/seed/seed.py \
  --dsn "postgresql://postgres:postgres@127.0.0.1:5433/atuel" \
  --seed 42
```

- **Resultado:** Carga determinista de **729.551 registros en las 31 tablas** (incluyendo `500.000` renglones de comprobante, `150.000` comprobantes y `20.000` clientes) en ~11–35 segundos usando `COPY ... FROM STDIN`, refrescando la vista materializada `v_ventas_mensuales_sala` y ejecutando `ANALYZE`.
- **Verificar la integridad post-carga (`C01` a `C14`):**
  ```bash
  docker compose exec -T db psql -U postgres -d atuel -v ON_ERROR_STOP=1 < db/seed/consultas_control.sql
  ```

### 5.3. Ejecutar las pruebas SQL de reglas de negocio y roles (Etapa 2)
El banco de pruebas [`db/tests/db_tests.sql`](db/tests/db_tests.sql) ejecuta **43 casos de prueba** (positivos y negativos) cubriendo `RN-01` a `RN-15` y `RI-01` a `RI-07` dentro de una transacción con `ROLLBACK` (requiere una base recién migrada o vacía):

```bash
# Prueba de las 22 reglas RN/RI
docker compose exec -T db psql -U postgres -d atuel < db/tests/db_tests.sql

# Prueba de privilegios mínimos de los roles app_rw y reportes_ro
docker compose exec -T db psql -U postgres -d atuel < db/tests/db_tests_roles.sql
```

### 5.4. Ejecutar las consultas SQL requeridas (Etapa 5)
Todas las operaciones de modificación (`U1`–`U6`, `I1`–`I6`, `D1`–`D6`) corren dentro de bloques `BEGIN; ... SET CONSTRAINTS ALL IMMEDIATE; ROLLBACK;` para mostrar el estado previo y posterior sin alterar los datos cargados (`update.sql` y `delete.sql` reciben por `-v` los parámetros de bodega y localidades exigidos por sus consignas):

```bash
docker compose exec -T db psql -U postgres -d atuel -v ON_ERROR_STOP=1 < consultas/insert.sql
docker compose exec -T db psql -U postgres -d atuel -v ON_ERROR_STOP=1 -v bodega="Bodega Atuel del Sur S.A." < consultas/update.sql
docker compose exec -T db psql -U postgres -d atuel -v ON_ERROR_STOP=1 -v localidad_d3="Chacras de Coria" -v localidad_d6="General Alvear" < consultas/delete.sql
docker compose exec -T db psql -U postgres -d atuel -v ON_ERROR_STOP=1 < consultas/select.sql
```

### 5.5. Ejecutar las pruebas automáticas de la API REST (Etapa 6)
La suite [`api/internal/httpapi/api_test.go`](api/internal/httpapi/api_test.go) incluye **23 tests de integración** contra la base real (incluyendo violaciones deliberadas de `RN-01`, `RN-05`, `RN-09`, `RN-11`, `RN-12`, `RN-14` y la prueba de **inyección SQL fallida** `TestInyeccionSQL`):

```bash
cd api
export DATABASE_URL="postgresql://app_rw:ContraseñaSuperSercreta1234@127.0.0.1:5433/atuel"
go test -v ./...
```

---

## 6. Reglas de Negocio, Consultas, API y Frontend

- **Documentación del Informe Final Integrador:** [`docs/informe_final.md`](docs/informe_final.md) (incluye modelo de datos, normalización 3FN, tabla completa de trazabilidad `Regla → Mecanismo → Prueba`, carga masiva, estudio de índices con `EXPLAIN`, consultas SQL, API/Front y arquitectura en la nube).
- **Documentación de la API REST:** [`api/docs/api.md`](api/docs/api.md), especificación OpenAPI 3.0 en [`api/docs/openapi.yaml`](api/docs/openapi.yaml) y ejemplos `curl` en [`api/docs/curl.md`](api/docs/curl.md).
- **Pantallas del Frontend (`http://localhost:8080`):**
  1. **Catálogo de vinos:** Listado paginado con búsqueda por nombre y filtros por tipo, cepa, bodega y añada; modal de ficha técnica (`S9`) con cepas, porcentajes, maridajes y stock total.
  2. **Alta y edición de vino:** Formulario dinámico de composición varietal y maridajes; exhibe sin intermediación el error de la base (`RN-05` / `RI-02`) si los porcentajes no suman 100 %.
  3. **Nueva venta:** Selección de cliente y sala, simulación en tiempo real mediante `POST /comprobantes/simular` (calculada por los triggers en transacción revertida) y confirmación atómica (`POST /comprobantes`), mostrando el rechazo por stock insuficiente (`RN-09`, `HTTP 409`).
  4. **Transferencias:** Creación de solicitud, alta y baja de renglones en estado `'en_confeccion'` (`RN-12`) y transición de estados (`terminar` $\rightarrow$ `procesar` invocando `sp_procesar_transferencia`, `RN-11`).
  5. **Tablero de control:** Top 10 de vinos más vendidos (`S1`), gráfico de ventas por sala en el último trimestre (`S8`), vinos sin stock en una sala con disponibilidad en depósito (`S6`) y transportista más activo del último mes (`S7`).

---

## 7. Despliegue en la Nube (Etapa 8)

El diseño de la arquitectura cloud, la comparativa de proveedores (`Neon PostgreSQL 16` + `Render` vs. `Supabase`/`Fly.io` y `VPS Docker`), la configuración de seguridad (`sslmode=require`, rol `app_rw`, secretos en variables de entorno, aislamiento de red) y el procedimiento de backup/restauración (`pg_dump` / `pg_restore`) se encuentran detallados en:

- [`docs/entregables/etapa 8/informe_etapa8_nube.md`](docs/entregables/etapa%208/informe_etapa8_nube.md)
- Capítulo 8 de [`docs/informe_final.md`](docs/informe_final.md)

### Enlaces del Entorno Cloud
- **URL Pública del Sistema (Frontend HTTPS):** `https://bodegas-del-atuel.onrender.com` *(configurar según instancia activa en la defensa)*
- **URL Pública de la API (`GET /salud`):** `https://bodegas-del-atuel-api.onrender.com/salud`
- **Conexión de la API a PostgreSQL:** Cifrada vía TLS (`?sslmode=require`) autenticando con el rol de privilegios mínimos `app_rw`.
