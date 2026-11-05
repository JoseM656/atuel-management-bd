# Informe de la Etapa 4: Índices y Rendimiento · Bodegas del Atuel

## 1. Medición baseline (#31)

Esta medición es el punto de partida contra el que se comparan los índices de `008_indices.sql`. Se hizo solo con los índices de claves primarias y UNIQUE: la base no tiene ningún índice no único.

### 1.1 Entorno y método

| Dato | Valor |
| :--- | :--- |
| Motor | PostgreSQL 16.15 en contenedor `postgres:16`, configuración por defecto |
| Migraciones aplicadas | `001_esquema.sql` a `007_roles.sql` |
| Datos | `seed.py --seed 42 --fecha-ref 2026-11-05` (729.551 filas, C01..C14 sin inconsistencias) |
| Estadísticas | `VACUUM ANALYZE` antes de medir |
| Consultas | [`consultas_medicion.sql`](consultas_medicion.sql), con `EXPLAIN (ANALYZE, BUFFERS)` |
| Corridas | 6: la primera calienta la caché y se informa la mediana de las otras 5 |

`--fecha-ref` coincide con la fecha de la medición porque S3, S4 y S8 calculan su ventana con `CURRENT_DATE`. A las candidatas sugeridas por el enunciado (S1, S4, S8 y S10) se agregaron S3, porque filtra una tabla grande por dos columnas y devuelve pocas filas; S5, porque casi todas las transferencias ya están procesadas; y la condición de D4, medida como `SELECT`, porque depende de una clave foránea sin índice.

Parámetros usados: sala 12 en S3 y vino 1 («Malbec Reserva B1», 2020, 750 ml) en S4.

La decisión de comparar S10 dentro de cada campaña está explicada en el encabezado de la consulta.

### 1.2 Resultados

| Consulta | Tiempo (mediana) | Recorrido principal | Filas leídas | Filas útiles | Buffers |
| :--- | ---: | :--- | ---: | ---: | ---: |
| S1 | 241,3 ms | Parallel Seq Scan en `renglon_comprobante` | 500.000 | 500.000 | 3.745 |
| S3 | 9,2 ms | Parallel Seq Scan en `comprobante` | 150.000 | 835 | 2.938 |
| S4 | 1,1 ms | Seq Scan en `renglon_transferencia` y `transferencia` | 10.000 y 2.500 | 327 y 186 | 69 |
| S5 | 0,4 ms | Seq Scan en `transferencia` | 2.500 | 150 | 15 |
| S8 | 26,0 ms | Parallel Seq Scan en `comprobante` | 150.000 | 42.115 | 1.260 |
| S10 | 531,7 ms | CTE Scan repetido sobre `rendimiento` | 10.562.500 | 16 por recorrido del CTE, en promedio | 36 |
| D4 (condición) | 112,2 ms | Seq Scan en `comprobante` y `cliente` | 150.000 y 20.000 | 2.773 en el resultado | 1.535 |

Los planes completos y el tiempo de cada corrida están en [`anexo_planes_baseline.txt`](anexo_planes_baseline.txt).

### 1.3 Qué muestran los planes

- **S1:** lee toda la tabla porque agrega todos los renglones. No hay filas que un índice pueda descartar, así que la mejora dependerá de un recorrido solo de índice o de evitar el ordenamiento.
- **S3:** es el caso más claro de filtro sin índice. Lee 150.000 filas para quedarse con 835, un 0,6 %.
- **S4:** la PK `(nro, cod_vino)` no sirve para buscar por `cod_vino`, porque esa no es su primera columna. Las tablas son chicas, así que la mejora en tiempo será pequeña.
- **S8:** conserva un 28 % de las filas. Esa selectividad es baja para un índice común, por lo que un índice solo sobre `fecha` podría no usarse.
- **S10:** es la más lenta, pero el índice no es la solución. Referenciar el CTE dentro de la subconsulta correlacionada lo recorre entero 3.250 veces (3.250 × 3.250 = 10.562.500 filas), y un CTE materializado no tiene índices. Para mejorarla hay que reescribir la consulta.
- **S5:** es muy rápida porque la tabla es chica, pero lee 2.500 filas para usar 150.
- **D4 (condición):** para saber qué socios no compraron, recorre todo `comprobante`, porque su clave foránea `id_cliente` no tiene índice.

## 2. Índices creados (#32)

Los índices están en [`008_indices.sql`](../../../db/migrations/008_indices.sql). Se probaron dentro de transacciones con `ROLLBACK`, para no alterar el baseline, y quedaron solo los que mostraron una mejora.

| Índice | Tipo pedido | Definición | Consulta | Tamaño |
| :--- | :--- | :--- | :--- | ---: |
| `idx_comprobante_sala_fecha` | Compuesto | `comprobante (id_sala, fecha)` | S3 | 1.632 kB |
| `idx_comprobante_cliente` | Clave foránea | `comprobante (id_cliente)` | D4 | 1.064 kB |
| `idx_transferencia_pendientes` | Parcial | `transferencia (id_sala) WHERE estado <> 'procesado'` | S5 | 16 kB |
| `idx_renglon_transferencia_vino` | Variante `INCLUDE` | `renglon_transferencia (cod_vino) INCLUDE (nro, cantidad)` | S4 | 328 kB |
| `idx_transferencia_fecha` | Simple | `transferencia (fecha_confeccion)` | S4 | 40 kB |

**Orden de columnas del índice compuesto:** primero `id_sala`, que S3 compara por igualdad, y después `fecha`, que compara por rango. Con ese orden, el índice llega a una sola sala y recorre solo su tramo de fechas. Con `(fecha, id_sala)` recorrería todas las salas dentro del rango de fechas.

### 2.1 Candidatos descartados

Estas pruebas también se hicieron dentro de transacciones con `ROLLBACK`, con la mediana de 5 corridas salvo donde se indica. Se hicieron sobre la carga anterior, con `--fecha-ref 2026-11-03`, por lo que sus tiempos no se comparan directamente con los de la sección 1.2.

| Candidato | Consulta | Resultado | Por qué se descartó |
| :--- | :--- | :--- | :--- |
| `comprobante (fecha) INCLUDE (id_sala, total)` | S8 | Baja de 1.257 a 165 buffers, pero sube de 25,6 a 32,3 ms | Ocupa 4.640 kB y empeora el tiempo |
| `renglon_comprobante (cod_vino) INCLUDE (cantidad)` | S1 | El planificador no lo usó (una corrida) | S1 agrega toda la tabla y el índice ocupa 11 MB |
| BRIN sobre `comprobante (fecha)` | S8 | No se creó: la correlación física de `fecha` es 0,025 | BRIN necesita filas ordenadas físicamente por esa columna |
| Índice para S10 | S10 | No hay candidato | El tiempo se va en recorrer el CTE, que no admite índices |

El índice de S8 pierde porque el plan original usa dos procesos en paralelo y el Index Only Scan corre en uno solo. Sin paralelismo (`max_parallel_workers_per_gather = 0`), el mismo índice sí gana: baja de 42,2 a 31,4 ms. Conviene volver a evaluarlo si el servidor en la nube tiene un solo núcleo.

## 3. Comparativa, costo de escritura y caso sin uso de índice (#33)

Pendiente.
