# Etapas del proyecto — Visión macro

> Bodegas del Atuel · TPI Bases de Datos · UTN FRSR · 2026.
> Vista de alto nivel del recorrido. El detalle de pasos, entregables y criterios está en `docs/TPI_Bodegas_del_Atuel.md` (§7) y el índice de qué se construye en `docs/SPEC.md`.

## Roadmap

```
1 Modelado ──▶ 2 Integridad ──▶ 3 Carga ──▶ 4 Índices ──▶ 5 Consultas
                                                              │
                                                              ▼
8 Nube ◀──── 7 Front ◀──── 6 API ◀─────────────────────────────┘
   │
   ▼
9 Documentación y defensa
```

## Resumen por etapa

| # | Etapa | Objetivo (una línea) | Entregable que la cierra |
|---|---|---|---|
| 1 | Modelado | Pasar del escenario a un esquema físico 3FN | `001_esquema.sql` + DER + diccionario |
| 2 | Integridad y lógica | Que las reglas vivan en la base | `002_constraints`…`007_roles` + `db_tests.sql` |
| 3 | Carga masiva | Datos reales y reproducibles (≥100k filas) | `db/seed/` + `dump_completo.sql.gz` |
| 4 | Índices | Rendimiento medido con evidencia | `008_indices.sql` + informe |
| 5 | Consultas SQL | Resolver U/I/D/S en SQL comentado | `consultas/*.sql` |
| 6 | API REST | Exponer la base sin ocultar ni duplicar SQL | `api/` + docker-compose + docs |
| 7 | Front | Ver el dato viajar hasta la pantalla | `front/` (5 pantallas) |
| 8 | Nube | Sistema público, seguro y restaurable | URL pública + backup/restore probados |
| 9 | Documentación y defensa | Reproducible por un tercero + demo | README + informe + defensa oral |

## Dependencias

- **Cadena dura:** 1 → 2 → 3 → 4 → 5. No hay vuelta atrás sin corregir la base.
- **API (6)** depende de 2 (roles, procedimientos) y 5 (consultas a exponer).
- **Front (7)** depende de 6 (consumir la API real).
- **Nube (8)** depende de todo lo anterior.
- **Defensa (9)** cierra el ciclo; cada integrante defiende cualquier parte.

## Peso en la nota (rúbrica)

| Bloque | Puntos |
|---|---:|
| Modelado + Constraints + Lógica + Carga + Índices + Consultas (capa de datos) | **70** |
| API | 10 |
| Front | 5 |
| Nube y seguridad | 10 |
| Documentación, Git y demo | 5 |
| **Total** | **100** |

## Hitos

| Hito | Cuándo | Señal de avance |
|---|---|---|
| H1 | fin etapa 1 | la base se crea desde cero sin errores |
| H2 | fin etapa 2 | cada regla RN/RI tiene mecanismo y test |
| H3 | fin etapa 3 | dos ejecuciones con la misma semilla dan los mismos datos |
| H4 | fin etapa 4 | ≥3 consultas más rápidas con índice |
| H5 | fin etapa 5 | consultas probadas en transacción |
| H6 | fin etapa 6 | `docker compose up` levanta base + API |
| H7 | fin etapa 7 | 5 pantallas funcionando contra la API |
| H8 | fin etapa 8 | URL pública HTTPS + backup restaurado |
| H9 | fin etapa 9 | informe + demo en vivo |
