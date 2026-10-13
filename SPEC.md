# Spec: Bodegas del Atuel — Sistema de gestión y distribución vitivinícola

> Trabajo Práctico Integrador · Bases de Datos · Ingeniería en Sistemas · UTN Facultad Regional San Rafael · Ciclo 2026.
> Fuente de requisitos: `docs/TPI_Bodegas_del_Atuel.md` (el enunciado del cliente/cátedra) y `docs/resumen.md` (resumen del modelo y decisiones ya tomadas). Este documento es la síntesis ejecutable del proyecto y el índice de qué se construye, por qué y cómo se valida.

---

## 1. Objetivo

Construir un sistema de gestión para la empresa vitivinícola ficticia **«Bodegas del Atuel»**: producción de uva y vino, distribución (depósito central, ingresos y transferencias), y venta a través de una red de salas. La **capa de datos es el corazón del sistema** y representa el 70 % de la nota: el modelo, las constraints, la lógica en PL/pgSQL, la carga masiva, los índices y las consultas SQL.

La **API (Go)** y el **front (Alpine.js)** son el *medio* para demostrar que la base funciona como parte de un sistema real: exponen la base sin ocultar el SQL y sin duplicar las reglas que ya viven en ella.

**Éxito** = cumplir la rúbrica (100 pts) y que cualquier persona pueda levantar el sistema con `docker compose up` y usarlo desde una URL pública.

### Regla de oro (no negociable)

> La API **no recalcula** totales, descuentos ni stock. Llama a las funciones y procedimientos de la base y deja que los triggers protejan las reglas. Así las reglas siguen valiendo aunque alguien acceda a la base directamente.

---

## 2. Decisiones de diseño y supuestos

| Decisión | Elección (recomendada) | Alternativas |
|---|---|---|
| Motor de BD | PostgreSQL 14+ | — |
| Lenguaje API | Go 1.22+ | — |
| Router API | `chi` (confirmado) | `net/http` stdlib, `gin`, `echo` |
| Driver PostgreSQL | `pgx` v5 (`pgxpool`) | `lib/pq` |
| Acceso a datos | Capa propia, una función por consulta, SQL parametrizado | — |
| Front | HTML/CSS/JS + **Alpine.js por CDN**, sin build | React, Vue |
| Servidor de estáticos | a definir (ver §13) | nginx (contenedor propio) o servido por la API |
| Generación de datos | Python 3.11+ + `psycopg` + `Faker` + `random`, semilla fija | — |
| Documentación API | OpenAPI/Swagger o colección Postman | — |
| Despliegue | Docker + Docker Compose (local) y proveedor cloud a definir | Neon, Render, Railway, Fly.io, etc. |
| Control de versiones | Git en GitHub/GitLab, commits de todos | — |

**Confirmado:** router `chi`. **Supuestos a confirmar:** versión exacta de Go y si el front lo sirve nginx o la API (ver §13).

---

## 3. Tech Stack

- **Base de datos:** PostgreSQL 14+ (local en contenedor, luego en la nube). Sin ORM ni query builders.
- **API:** Go, JSON, REST. Driver nativo `pgx`. Documentada con OpenAPI/Postman.
- **Front:** HTML/CSS/JS + Alpine.js. Consume únicamente la API.
- **Datos:** Python + Faker + random, semilla fija reproducible, catálogos reales desde CSV.
- **Modelado:** draw.io / dbdiagram.io / pgModeler (entregar imagen/PDF + fuente).
- **Infra:** Docker, Docker Compose. Un solo comando levanta base, API y front.
- **Cliente SQL:** `psql`, DBeaver o pgAdmin.

---

## 4. Comandos

```bash
# Infraestructura
docker compose up --build          # levanta base + API + front en local

# Migraciones (aplicar en orden sobre base vacía)
psql "$DATABASE_URL" -f db/migrations/001_esquema.sql
psql "$DATABASE_URL" -f db/migrations/002_constraints.sql
psql "$DATABASE_URL" -f db/migrations/003_funciones.sql
psql "$DATABASE_URL" -f db/migrations/004_procedimientos.sql
psql "$DATABASE_URL" -f db/migrations/005_triggers.sql
psql "$DATABASE_URL" -f db/migrations/006_vistas.sql
psql "$DATABASE_URL" -f db/migrations/007_roles.sql
psql "$DATABASE_URL" -f db/migrations/008_indices.sql

# Carga de datos (reproducible, semilla fija)
python db/seed/seed.py

# Pruebas de BD (casos que funcionan y que fallan)
psql "$DATABASE_URL" -f db/tests/db_tests.sql

# API
cd api && go build ./...           # compilar
cd api && go test ./...            # pruebas automáticas
cd api && go vet ./... && gofmt -l .   # lint básico
cd api && go run ./cmd/api         # correr en dev

# Backups
pg_dump "$DATABASE_URL" | gzip > dump_completo.sql.gz
```

---

## 5. Estructura del proyecto

```
/
|-- README.md                  # descripción, requisitos, cómo levantar, URL nube
|-- docker-compose.yml         # base + API + front
|-- .env.example               # variables sin secretos reales
|-- SPEC.md                    # este documento
|-- docs/                      # DER, esquema relacional, diccionario, informes
|-- db/
|   |-- migrations/            # 001_esquema.sql ... 008_indices.sql
|   |-- seed/                  # CSV de catálogos + script de carga + README
|   `-- tests/                 # db_tests.sql
|-- consultas/                 # insert.sql, update.sql, delete.sql, select.sql
|-- api/                       # código Go (cmd, internal, handlers, data)
|-- front/                     # estáticos Alpine.js (index.html, js/, css/)
`-- tasks/                     # plan.md y todo.md (planificación)
```

**Estructura interna de `api/` (propuesta):**

```
api/
|-- go.mod
|-- cmd/api/main.go            # arranque, config desde env, wiring
|-- internal/
|   |-- db/                    # pool, transacciones, capa de acceso a datos (una función por consulta)
|   |-- httpapi/               # router, handlers, DTOs
|   |-- httperr/               # traducción SQLSTATE -> HTTP
|   `-- config/                # lectura de variables de entorno
`-- .../*_test.go              # pruebas automáticas (junto al código)
```

---

## 6. Modelo de dominio (entidades mínimas)

Resumen del escenario (detalle completo en §3 y §5 del enunciado). Atributos y claves son guía; se pueden agregar y justificar.

| Área | Entidades | Notas |
|---|---|---|
| Ubicación | Localidad, Sala de venta, Empleado | Localidad→encargado regional (uno por localidad); sala en una localidad; empleado en una sala |
| Producción | Finca, Parcela, Cepa, Lote de uva, Análisis de calidad | Parcela = entidad débil (finca, n.º); una cosecha por parcela/campaña; varios análisis por lote |
| Bodega | Bodega, Vino, Composición (vino-cepa), Maridaje, Vino-maridaje | Composición N:M con atributo (porcentaje suma 100); maridaje N:M |
| Clientes | Cliente (supertipo) + Socio/Distribuidor/Exportador, Permiso de exportación | Jerarquía total y disjunta: supertipo + tabla por subtipo (resuelto, ver §6) |
| Ventas | Comprobante, Renglón de comprobante | Clave (comprobante, vino); descuento según tipo de cliente |
| Distribución | Transportista, Transportista-cubre-localidad, Ingreso, Renglón de ingreso, Transferencia, Renglón de transferencia, Stock de sala, Stock de depósito | Estados con ENUM: en_confeccion → terminado → procesado |
| Auditoría | Auditoría de precio | Completada por trigger AFTER UPDATE sobre vino |

**Modelo y decisiones ya resueltas** (fuente: `docs/resumen.md`, 31 tablas). El esquema completo en 3FN queda documentado allí; aquí se fija lo acordado:

1. **Jerarquía de clientes:** supertipo `cliente` + una tabla por subtipo (`socio`, `distribuidor`, `exportador`); jerarquía total y disjunta, con FK compuesta `(id_cliente, tipo)`. Los joins se resuelven con una vista.
2. **Claves:** subrogadas (`IDENTITY`) en casi todas las tablas; **CUIT natural** en `bodega` y `empleado` (validado con DOMAIN `cuit`); transportista con código propio y CUIT `UNIQUE`; parcela con clave compuesta `(id_finca, nro_parcela)`; localidad subrogada (varias comparten código postal); permiso de exportación con código natural.
3. **Tipos de datos:** `NUMERIC` para dinero y porcentajes (nunca `FLOAT`); `DATE` para fechas y `TIMESTAMPTZ` para la auditoría; `ENUM` para estado, tipo de cliente, tipo de vino, tipo de cepa y día de la semana; `DOMAIN cuit`.
4. **Atributos derivados:** se **almacenan** totales, % de descuento, precio unitario, descuento del cliente y stocks (historia + rendimiento, mantenidos por triggers); la **campaña se calcula** de `fecha_cosecha` (índice único de expresión).
5. **Acciones referenciales:** `CASCADE` solo en lo dependiente (renglones, composición, maridajes, análisis, permisos, subtipos, coberturas); `RESTRICT` en el resto (movimientos, catálogos, stock, auditoría); `ON UPDATE CASCADE` solo en claves naturales.
6. **Normalización:** `departamento` en tabla propia (elimina dependencia transitiva en `finca`).

---

## 7. Reglas de negocio (RN-01 … RN-15)

Cada regla debe estar protegida por al menos un mecanismo en la base y tener al menos un caso de prueba en `db/tests/db_tests.sql`.

| N.º | Regla | Mecanismo esperado |
|---|---|---|
| RN-01 | Precio del vino único en la red y > 0 | Atributo en vino + CHECK |
| RN-02 | Sala en una sola localidad; localidad con único encargado | FK + diseño 3FN |
| RN-03 | Empleado en una sola sala | FK NOT NULL |
| RN-04 | Parcela con una cepa; cosecha máx. una vez por campaña | FK + UNIQUE (parcela, campaña) |
| RN-05 | Porcentajes de corte suman 100 | Constraint trigger diferido |
| RN-06 | Descuento por tipo: socio 10 %, distribuidor 20 %, exportador 30 % | Función + CHECK de rango |
| RN-07 | Exportador con varios permisos; vencimiento > emisión | Tabla permisos + CHECK entre columnas |
| RN-08 | Total del comprobante = suma de renglones con descuento (no se carga a mano) | Función + trigger |
| RN-09 | No vender más que el stock de la sala; stock nunca negativo | Trigger BEFORE INSERT + CHECK (cantidad ≥ 0) |
| RN-10 | Solo ingreso terminado impacta el depósito; transiciones sin retroceso | ENUM + trigger + procedimiento |
| RN-11 | Ídem transferencias; fecha de confección = actual e inmutable | Trigger de estados y de fecha + procedimiento |
| RN-12 | Documento no en confección no admite tocar renglones | Trigger sobre renglones |
| RN-13 | Cambio de precio auditado (fecha, usuario, precio anterior/nuevo) | Trigger AFTER UPDATE + tabla auditoría |
| RN-14 | No borrar transportista/bodega/vino con movimientos | FK ON DELETE RESTRICT |
| RN-15 | Cantidades, superficies, kg y precios > 0; graduación 5–20 | CHECK |

> **Atención:** no usar `CURRENT_DATE` ni funciones no deterministas en un `CHECK` (se rompe al restaurar backup). Las reglas dependientes de la fecha van en un trigger.

### Reglas implícitas (RI-01 … RI-07)

Detectadas en el refinamiento del modelo (`docs/resumen.md`). También requieren mecanismo en la base y caso de prueba.

| Cód. | Regla | Mecanismo |
|---|---|---|
| RI-01 | El encargado trabaja en una sala de su misma localidad | Trigger + FK diferible para romper el ciclo de dependencias |
| RI-02 | Todo vino tiene al menos un maridaje | Constraint trigger diferido (junto con RN-05) |
| RI-03 | El precio unitario es una copia histórica de `vino.precio` | Trigger BEFORE INSERT en el renglón |
| RI-04 | Los vinos de un ingreso son de la bodega de origen | Trigger en `renglon_ingreso` |
| RI-05 | El transportista cubre la localidad del depósito | Trigger en `ingreso` |
| RI-06 | Exportador con más de 3 permisos recibe 35 % | Trigger sobre `permiso_exportacion` que recalcula con `fn_descuento_cliente` |
| RI-07 | El subtipo coincide con el tipo del cliente | FK compuesta `(id_cliente, tipo)` |

---

## 8. Etapas (capability map / orden de construcción)

El proyecto se entrega en 9 etapas con dependencias en cadena. Orden de construcción:

```
1 Modelado → 2 Integridad/lógica → 3 Carga masiva → 4 Índices → 5 Consultas
          → 6 API → 7 Front → 8 Nube → 9 Documentación/defensa
```

| Etapa | Responsabilidad | Entregables clave | Depende de |
|---|---|---|---|
| 1. Modelado | DER, esquema relacional 3FN, diccionario, `001_esquema.sql` | DER, diccionario, DDL | — |
| 2. Integridad y lógica | `002_constraints`…`007_roles`, funciones, procs, triggers, vistas, roles, `db_tests.sql` | SQL 002–007 + tests + demo concurrencia | 1 |
| 3. Carga masiva | Catálogos CSV, script Python con semilla, `dump_completo.sql.gz` | `db/seed/`, reporte de volúmenes/tiempos | 2 |
| 4. Índices | `008_indices.sql`, mediciones `EXPLAIN (ANALYZE, BUFFERS)` | índice SQL + informe rendimiento | 3 |
| 5. Consultas SQL | `consultas/{insert,update,delete,select}.sql` (U1–U6, I1–I6, D1–D6, S1–S12) | archivos comentados + probadas en transacción | 3 |
| 6. API REST | Endpoints vinos/clientes/comprobantes/transferencias/ingresos, `/salud`, errores, tests | `api/` + docker-compose + documentación | 2, 5 |
| 7. Front | Catálogo, alta/edición de vino, venta, transferencias, tablero | `front/` | 6 |
| 8. Nube | Despliegue HTTPS, roles, cifrado, backup/restore probados | URL pública + README | 2–7 |
| 9. Documentación y defensa | README, informe final, trazabilidad, demo + defensa oral | informe + demo | todo |

**Nota:** si en el futuro se quiere granular, estas 9 etapas son los "module ids" estables para specs/plans por módulo (`SPEC-modelado.md`, `SPEC-integridad.md`, …). Por ahora un único `SPEC.md` cubre el proyecto.

---

## 9. Estilo de código

### SQL (convenciones del enunciado)

- Nombres de tablas/columnas en `snake_case`; PK generada con `GENERATED ALWAYS AS IDENTITY` cuando sea subrogada.
- Prefijos: `fn_` (funciones), `sp_` (procedimientos), `trg_` (funciones de trigger), `idx_` (índices), `v_` (vistas).
- Tipos propios: `CREATE TYPE estado_documento AS ENUM (...)`; `CREATE DOMAIN cuit_dom AS CHAR(11) CHECK (VALUE ~ '^[0-9]{11}$')`.
- Dinero con `NUMERIC(10,2)`, nunca `FLOAT`.
- Cada función/procedimiento/trigger con comentario de cabecera: propósito, parámetros, `STABLE`/`IMMUTABLE`, y (triggers) la regla que protege (p. ej. `-- RN-09`).

```sql
CREATE DOMAIN cuit_dom AS CHAR(11) CHECK (VALUE ~ '^[0-9]{11}$');

CREATE TABLE vino (
  cod_vino   INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  nombre     VARCHAR(80) NOT NULL,
  tipo       VARCHAR(12) NOT NULL CHECK (tipo IN ('tinto','blanco','rosado','espumante')),
  anada      SMALLINT NOT NULL CHECK (anada BETWEEN 1990 AND 2100),
  volumen_ml INTEGER NOT NULL CHECK (volumen_ml IN (187, 375, 750, 1500, 3000)),
  graduacion NUMERIC(4,2) NOT NULL CHECK (graduacion BETWEEN 5 AND 20),
  precio     NUMERIC(10,2) NOT NULL CHECK (precio > 0),
  cuit_bodega cuit_dom NOT NULL REFERENCES bodega (cuit) ON DELETE RESTRICT ON UPDATE CASCADE,
  UNIQUE (nombre, anada, volumen_ml)
);

-- Índice parcial: solo lo pendiente (tabla chica dentro de una grande)
CREATE INDEX idx_transferencia_pendientes
  ON transferencia (id_sala, fecha_confeccion) WHERE estado <> 'procesado';
```

### Go (API)

- Paquetes separados por responsabilidad: `internal/db` (acceso a datos), `internal/httpapi` (handlers), `internal/httperr` (errores), `internal/config`.
- **Una función por consulta** en la capa de datos; todo parametrizado con `$1, $2, …` (nunca concatenar input del usuario).
- Errores de PostgreSQL traducidos por `SQLSTATE` → HTTP (tabla en §6 de la API).
- `gofmt` obligatorio; manejo explícito de transacciones cuando hay más de una sentencia.

```go
// internal/db/vinos.go — capa de acceso a datos: una función por consulta
func (r *Repo) VinoPorCodigo(ctx context.Context, cod int) (Vino, error) {
    const q = `SELECT cod_vino, nombre, tipo, anada, volumen_ml, graduacion, precio
               FROM vino WHERE cod_vino = $1`
    var v Vino
    err := r.pool.QueryRow(ctx, q, cod).Scan(&v.Codigo, &v.Nombre, &v.Tipo,
        &v.Anada, &v.VolumenMl, &v.Graduacion, &v.Precio)
    if err != nil {
        return Vino{}, httperr.FromPg(err) // SQLSTATE -> HTTP
    }
    return v, nil
}
```

---

## 10. Estrategia de pruebas

| Nivel | Qué | Dónde | Cómo |
|---|---|---|---|
| Integridad BD | Cada RN-01…RN-15 con casos que funcionan y casos que fallan | `db/tests/db_tests.sql` | `psql -f`; comentar error esperado |
| Concurrencia | Dos sesiones compitiendo por la última botella (con/sin `FOR UPDATE`) | informe etapa 2 | capturas psql |
| API | ≥ 8 pruebas automáticas; ≥ 3 provocan violación de regla y verifican código | `api/*_test.go` | `go test ./...` |
| Carga | Conteos, huérfanos, stock negativo, totales inconsistentes | reporte etapa 3 | consultas de control |
| Rendimiento | ≥ 3 consultas medidas antes/después de índices | informe etapa 4 | `EXPLAIN (ANALYZE, BUFFERS)` |
| Nube | Backup restaurado en base nueva; conteos coinciden | informe etapa 8 | `pg_dump`/`pg_restore` |

**Cobertura esperada:** trazabilidad explícita regla → mecanismo → caso de prueba (tabla en informe final). Sin `--coverage` de Go exigido, pero se recomienda `go test -cover` informativo.

---

## 11. Límites (Always / Ask first / Never)

### Always (siempre)
- SQL escrito a mano; migraciones aplicables desde cero en orden.
- Consultas parametrizadas en la API; pool de conexiones; credenciales en variables de entorno.
- Semilla fija en la carga de datos (reproducible).
- Una función por consulta en la capa de acceso a datos.
- Registrar trazabilidad regla → mecanismo → prueba.
- Commits de todos los integrantes; correr tests antes de commits.

### Ask first (consultar antes)
- Cambios al esquema o al modelo de datos (actualizar spec primero).
- Agregar dependencias (Go modules, CDN, paquetes Python).
- Elegir/confirmar proveedor cloud y su plan.
- Cambiar la estructura del repo o la configuración de CI/Docker.
- Modificar la rúbrica/alcance (recortar o sumar etapas).

### Never (nunca)
- Usar ORM ni generadores que oculten el SQL.
- `FLOAT`/`REAL` para importes monetarios.
- Recalcular totales, descuentos o stock en la API o el front.
- Conectar la API con el usuario propietario o un superusuario.
- Commitear secretos (contraseñas, cadenas de conexión) al repo, ni en el historial.
- Funciones no determinísticas (`CURRENT_DATE`, etc.) dentro de un `CHECK`.
- Concatenar input del usuario dentro de una sentencia SQL.

---

## 12. Criterios de éxito

Derivados de la rúbrica (100 pts) y de los criterios de aceptación por etapa. La capa de datos pesa 70 %.

- **Modelado (15):** DER correcto, esquema 3FN justificado, diccionario y `001_esquema.sql` que corre de punta a punta sobre base vacía.
- **Constraints (8):** cobertura de PK/FK/NOT NULL/UNIQUE/CHECK/DEFAULT, acciones referenciales justificadas, ENUM y DOMAIN.
- **Lógica (17):** funciones, procedimientos, triggers cubriendo RN-01…RN-15, casos de prueba, demo de concurrencia, vistas, 3 roles con privilegios mínimos.
- **Carga (8):** volúmenes mínimos (≥100.000 filas en una tabla; renglones de comprobante → 500.000), coherente, reproducible, eficiente y validada.
- **Índices (10):** ≥ 5 índices (compuesto, parcial, FK, variante) con `EXPLAIN`, mejora medida en ≥ 3 consultas, costo de escritura documentado.
- **Consultas (12):** U1–U6, I1–I6, D1–D6, S1–S12 resueltas, comentadas y probadas en transacción.
- **API (10):** SQL parametrizado, capa de datos, transacciones, traducción SQLSTATE→HTTP, ≥ 8 tests (≥ 3 de reglas), documentación OpenAPI/Postman.
- **Front (5):** 5 pantallas funcionando contra la API, errores de reglas visibles, sin lógica de cálculo en el cliente.
- **Nube (10):** URL pública HTTPS, conexión cifrada, puerto no expuesto, secretos fuera del repo, backup/restauración probados.
- **Documentación/Git/demo (5):** README reproducible, informe, historial de commits de todos, demo en vivo.

---

## 13. Preguntas abiertas

Resolver antes o durante la implementación (no bloquean el arranque de la etapa 1):

1. **Servido del front:** ¿nginx (contenedor propio) o lo sirve la API? (abierto).
2. **Versión de Go** exacta a fijar en `go.mod` y en el Dockerfile.
3. **Proveedor cloud** y plan (Neon / Render / Railway / Fly.io / etc.) — verificar límites vigentes.
4. **Integrantes y roles** rotativos por etapa (Datos / API / Front-Integración / Infraestructura).
5. **Herramienta de modelado** (draw.io / dbdiagram / pgModeler).

**Ya resueltas:** router = `chi`; jerarquía de clientes = supertipo + tabla por subtipo (ver §6).
