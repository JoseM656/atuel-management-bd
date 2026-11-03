# Informe de la Etapa 4: Índices y Rendimiento · Bodegas del Atuel

## 1. Medición baseline (#31)

Esta medición es el punto de partida contra el que se comparan los índices de `008_indices.sql`. Se hizo solo con los índices de claves primarias y UNIQUE: la base no tiene ningún índice no único.

### 1.1 Entorno y método

| Dato | Valor |
| :--- | :--- |
| Motor | PostgreSQL 16.15 en contenedor `postgres:16`, configuración por defecto |
| Migraciones aplicadas | `001_esquema.sql` a `007_roles.sql` |
| Datos | `seed.py --seed 42 --fecha-ref 2026-11-03` (729.551 filas, C01..C14 sin inconsistencias) |
| Estadísticas | `VACUUM ANALYZE` antes de medir |
| Consultas | [`consultas_medicion.sql`](consultas_medicion.sql), con `EXPLAIN (ANALYZE, BUFFERS)` |
| Corridas | 6: la primera calienta la caché y se informa la mediana de las otras 5 |

`--fecha-ref` coincide con la fecha de la medición porque S3, S4 y S8 calculan su ventana con `CURRENT_DATE`. Se agregó S3 a las candidatas sugeridas por el enunciado (S1, S4, S8 y S10) porque filtra una tabla grande por dos columnas y devuelve pocas filas.

Parámetros usados: sala 12 en S3 y vino 1 («Malbec Reserva B1», 2020, 750 ml) en S4.

### 1.2 Resultados

| Consulta | Tiempo (mediana) | Recorrido principal | Filas leídas | Filas útiles | Buffers |
| :--- | ---: | :--- | ---: | ---: | ---: |
| S1 | 243,6 ms | Parallel Seq Scan en `renglon_comprobante` | 500.000 | 500.000 | 3.745 |
| S3 | 8,5 ms | Parallel Seq Scan en `comprobante` | 150.000 | 839 | 2.946 |
| S4 | 1,1 ms | Seq Scan en `renglon_transferencia` y `transferencia` | 10.000 y 2.500 | 327 y 186 | 69 |
| S8 | 25,3 ms | Parallel Seq Scan en `comprobante` | 150.000 | 42.130 | 1.260 |
| S10 | 522,8 ms | CTE Scan repetido sobre `rendimiento` | 10.562.500 | 16 por recorrido del CTE, en promedio | 36 |

Los planes completos y el tiempo de cada corrida están en [`anexo_planes_baseline.txt`](anexo_planes_baseline.txt).

### 1.3 Qué muestran los planes

- **S1:** lee toda la tabla porque agrega todos los renglones. No hay filas que un índice pueda descartar, así que la mejora dependerá de un recorrido solo de índice o de evitar el ordenamiento.
- **S3:** es el caso más claro de filtro sin índice. Lee 150.000 filas para quedarse con 839, un 0,6 %.
- **S4:** la PK `(nro, cod_vino)` no sirve para buscar por `cod_vino`, porque esa no es su primera columna. Las tablas son chicas, así que la mejora en tiempo será pequeña.
- **S8:** conserva un 28 % de las filas. Esa selectividad es baja para un índice común, por lo que un índice solo sobre `fecha` podría no usarse.
- **S10:** es la más lenta, pero el índice no es la solución. Referenciar el CTE dentro de la subconsulta correlacionada lo recorre entero 3.250 veces (3.250 × 3.250 = 10.562.500 filas), y un CTE materializado no tiene índices. Para mejorarla hay que reescribir la consulta.

## 2. Índices creados (#32)

Pendiente.

## 3. Comparativa, costo de escritura y caso sin uso de índice (#33)

Pendiente.
