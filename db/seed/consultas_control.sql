-- =====================================================================
-- TPI Bases de Datos · Bodegas del Atuel
-- db/seed/consultas_control.sql
-- Etapa 3: Consultas de control de integridad y coherencia (Issue #30)
-- Compatible tanto con `psql -v ON_ERROR_STOP=1 -f` como con `psycopg`.
-- =====================================================================

-- ---------------------------------------------------------------------
-- BLOQUE A: Conteo de filas por cada una de las 31 tablas y mínimos
-- ---------------------------------------------------------------------
SELECT table_name,
       (xpath('/row/cnt/text()', xml_count))[1]::text::bigint AS total_filas
FROM (
    SELECT table_name,
           query_to_xml(format('SELECT count(*) AS cnt FROM public.%I', table_name), false, true, '') AS xml_count
    FROM information_schema.tables
    WHERE table_schema = 'public' AND table_type = 'BASE TABLE'
) q
ORDER BY total_filas DESC, table_name ASC;

DO $$
DECLARE
    v_tablas_total   INTEGER;
    v_tablas_vacias  INTEGER;
    v_tablas_gt_10k  INTEGER;
    v_tablas_gt_100k INTEGER;
BEGIN
    SELECT count(*),
           count(*) FILTER (WHERE cnt < 1),
           count(*) FILTER (WHERE cnt > 10000),
           count(*) FILTER (WHERE cnt > 100000)
    INTO v_tablas_total, v_tablas_vacias, v_tablas_gt_10k, v_tablas_gt_100k
    FROM (
        SELECT table_name,
               (xpath('/row/cnt/text()', query_to_xml(format('SELECT count(*) AS cnt FROM public.%I', table_name), false, true, '')))[1]::text::bigint AS cnt
        FROM information_schema.tables
        WHERE table_schema = 'public' AND table_type = 'BASE TABLE'
    ) t;

    IF v_tablas_total <> 31 THEN
        RAISE EXCEPTION 'Se esperaban 31 tablas y hay %', v_tablas_total;
    END IF;

    IF v_tablas_vacias > 0 THEN
        RAISE EXCEPTION 'Existen % tablas vacías (todas deben tener >= 1 fila)', v_tablas_vacias;
    END IF;

    IF v_tablas_gt_10k < 3 THEN
        RAISE EXCEPTION 'Mínimo de tablas con > 10.000 filas no alcanzado (hay %)', v_tablas_gt_10k;
    END IF;

    IF v_tablas_gt_100k < 1 THEN
        RAISE EXCEPTION 'Mínimo de tablas con > 100.000 filas no alcanzado (hay %)', v_tablas_gt_100k;
    END IF;

    RAISE NOTICE 'Bloque A OK: 31 tablas con >=1 fila, % tablas >10k y % tablas >100k.', v_tablas_gt_10k, v_tablas_gt_100k;
END $$;

-- ---------------------------------------------------------------------
-- BLOQUE B: Batería de 14 controles de integridad y coherencia (C01..C14)
-- ---------------------------------------------------------------------
DO $$
DECLARE
    v_errores INTEGER := 0;
    v_cnt     INTEGER;
BEGIN
    -- C01: Stock negativo (RN-09)
    SELECT count(*) INTO v_cnt FROM (
        SELECT 1 FROM stock_sala WHERE cantidad < 0
        UNION ALL
        SELECT 1 FROM stock_deposito WHERE cantidad < 0
    ) q;
    IF v_cnt > 0 THEN
        RAISE WARNING 'C01 FALLO: % filas con stock negativo', v_cnt;
        v_errores := v_errores + 1;
    ELSE
        RAISE NOTICE 'C01 OK: Cero stock negativo (RN-09)';
    END IF;

    -- C02: Descuadre subtotal comprobante (RN-08)
    SELECT count(*) INTO v_cnt FROM (
        SELECT c.nro
        FROM comprobante c
        LEFT JOIN renglon_comprobante r ON c.nro = r.nro
        GROUP BY c.nro, c.subtotal
        HAVING c.subtotal <> COALESCE(SUM(r.cantidad * r.precio_unitario), 0)
           OR COUNT(r.cod_vino) = 0
    ) q;
    IF v_cnt > 0 THEN
        RAISE WARNING 'C02 FALLO: % comprobantes con subtotal descuadrado o vacíos', v_cnt;
        v_errores := v_errores + 1;
    ELSE
        RAISE NOTICE 'C02 OK: Subtotales de comprobantes consistentes con renglones (RN-08)';
    END IF;

    -- C03: Descuadre total comprobante (RN-08)
    SELECT count(*) INTO v_cnt FROM (
        SELECT c.nro
        FROM comprobante c
        LEFT JOIN renglon_comprobante r ON c.nro = r.nro
        GROUP BY c.nro, c.total, c.subtotal, c.porcentaje_descuento
        HAVING c.total <> ROUND(c.subtotal * (1 - c.porcentaje_descuento / 100.0), 2)
           OR c.total <> COALESCE(SUM(r.subtotal), 0)
    ) q;
    IF v_cnt > 0 THEN
        RAISE WARNING 'C03 FALLO: % comprobantes con total descuadrado', v_cnt;
        v_errores := v_errores + 1;
    ELSE
        RAISE NOTICE 'C03 OK: Totales de comprobantes cuadran con cabecera y renglones (RN-08)';
    END IF;

    -- C04: Descuadre de renglones (RN-08)
    SELECT count(*) INTO v_cnt FROM (
        SELECT r.nro, r.cod_vino
        FROM renglon_comprobante r
        JOIN comprobante c ON c.nro = r.nro
        WHERE r.importe_descuento <> ROUND(r.cantidad * r.precio_unitario * (c.porcentaje_descuento / 100.0), 2)
           OR r.subtotal <> ROUND(r.cantidad * r.precio_unitario, 2) - r.importe_descuento
    ) q;
    IF v_cnt > 0 THEN
        RAISE WARNING 'C04 FALLO: % renglones con cálculo de descuento o subtotal erróneo', v_cnt;
        v_errores := v_errores + 1;
    ELSE
        RAISE NOTICE 'C04 OK: Renglones de venta con cálculo exacto (RN-08)';
    END IF;

    -- C05: Suma de cortes = 100 (RN-05)
    SELECT count(*) INTO v_cnt FROM (
        SELECT v.cod_vino
        FROM vino v
        LEFT JOIN composicion c ON v.cod_vino = c.cod_vino
        GROUP BY v.cod_vino
        HAVING COALESCE(SUM(c.porcentaje), 0) <> 100.00
    ) q;
    IF v_cnt > 0 THEN
        RAISE WARNING 'C05 FALLO: % vinos cuya composición no suma 100', v_cnt;
        v_errores := v_errores + 1;
    ELSE
        RAISE NOTICE 'C05 OK: Toda composición de vino suma exactamente 100 (RN-05)';
    END IF;

    -- C06: Vinos sin maridaje (RI-02)
    SELECT count(*) INTO v_cnt
    FROM vino v
    WHERE NOT EXISTS (SELECT 1 FROM vino_maridaje vm WHERE vm.cod_vino = v.cod_vino);
    IF v_cnt > 0 THEN
        RAISE WARNING 'C06 FALLO: % vinos sin maridaje', v_cnt;
        v_errores := v_errores + 1;
    ELSE
        RAISE NOTICE 'C06 OK: Todo vino posee al menos un maridaje (RI-02)';
    END IF;

    -- C07: Encargado regional en sala de su localidad (RI-01)
    SELECT count(*) INTO v_cnt
    FROM localidad l
    JOIN empleado e ON e.cuit = l.cuit_encargado
    JOIN sala_venta s ON s.id_sala = e.id_sala
    WHERE s.id_localidad <> l.id_localidad;
    IF v_cnt > 0 THEN
        RAISE WARNING 'C07 FALLO: % encargados asignados a sala de otra localidad', v_cnt;
        v_errores := v_errores + 1;
    ELSE
        RAISE NOTICE 'C07 OK: Encargados trabajan en sala de su localidad (RI-01)';
    END IF;

    -- C08: Totalidad y disjunción de subtipos de cliente (RI-07)
    SELECT count(*) INTO v_cnt
    FROM cliente c
    WHERE (
        (CASE WHEN EXISTS (SELECT 1 FROM socio s WHERE s.id_cliente = c.id_cliente) THEN 1 ELSE 0 END) +
        (CASE WHEN EXISTS (SELECT 1 FROM distribuidor d WHERE d.id_cliente = c.id_cliente) THEN 1 ELSE 0 END) +
        (CASE WHEN EXISTS (SELECT 1 FROM exportador e WHERE e.id_cliente = c.id_cliente) THEN 1 ELSE 0 END)
    ) <> 1
    OR (c.tipo = 'socio' AND NOT EXISTS (SELECT 1 FROM socio s WHERE s.id_cliente = c.id_cliente))
    OR (c.tipo = 'distribuidor' AND NOT EXISTS (SELECT 1 FROM distribuidor d WHERE d.id_cliente = c.id_cliente))
    OR (c.tipo = 'exportador' AND NOT EXISTS (SELECT 1 FROM exportador e WHERE e.id_cliente = c.id_cliente));
    IF v_cnt > 0 THEN
        RAISE WARNING 'C08 FALLO: % clientes con jerarquía de subtipo inconsistente', v_cnt;
        v_errores := v_errores + 1;
    ELSE
        RAISE NOTICE 'C08 OK: Jerarquía cliente-subtipo total y disjunta (RI-07)';
    END IF;

    -- C09: Descuento consistente con función (RN-06 / RI-06)
    SELECT count(*) INTO v_cnt
    FROM cliente c
    WHERE c.descuento <> fn_descuento_cliente(c.id_cliente);
    IF v_cnt > 0 THEN
        RAISE WARNING 'C09 FALLO: % clientes con descuento inconsistente', v_cnt;
        v_errores := v_errores + 1;
    ELSE
        RAISE NOTICE 'C09 OK: Descuentos de cliente sincronizados con fn_descuento_cliente (RN-06/RI-06)';
    END IF;

    -- C10: RI-04 (origen bodega) y RI-05 (transportista cubre depósito)
    SELECT count(*) INTO v_cnt FROM (
        SELECT ri.cod_ingreso, ri.cod_vino
        FROM renglon_ingreso ri
        JOIN ingreso i ON i.cod_ingreso = ri.cod_ingreso
        JOIN vino v ON v.cod_vino = ri.cod_vino
        WHERE v.cuit_bodega <> i.cuit_bodega
        UNION ALL
        SELECT i.cod_ingreso, i.cod_transportista
        FROM ingreso i
        JOIN deposito d ON d.id = 1
        WHERE NOT EXISTS (
            SELECT 1 FROM transportista_localidad tl
            WHERE tl.cod_transportista = i.cod_transportista AND tl.id_localidad = d.id_localidad
        )
    ) q;
    IF v_cnt > 0 THEN
        RAISE WARNING 'C10 FALLO: % ingresos violan RI-04 o RI-05', v_cnt;
        v_errores := v_errores + 1;
    ELSE
        RAISE NOTICE 'C10 OK: Vinos de origen propio (RI-04) y transportistas con cobertura de depósito (RI-05)';
    END IF;

    -- C11: Conciliación contable de stock, saldo acumulado diario >= 0 y precios históricos (RI-03)
    SELECT count(*) INTO v_cnt FROM (
        -- 1) Stock final depósito = ingresos procesados - transferencias procesadas
        SELECT sd.cod_vino AS ref_id
        FROM stock_deposito sd
        LEFT JOIN (
            SELECT ri.cod_vino, SUM(ri.cantidad) AS tot_ing
            FROM renglon_ingreso ri
            JOIN ingreso i ON i.cod_ingreso = ri.cod_ingreso
            WHERE i.estado = 'procesado'
            GROUP BY ri.cod_vino
        ) ing ON ing.cod_vino = sd.cod_vino
        LEFT JOIN (
            SELECT rt.cod_vino, SUM(rt.cantidad) AS tot_transf
            FROM renglon_transferencia rt
            JOIN transferencia t ON t.nro = rt.nro
            WHERE t.estado = 'procesado'
            GROUP BY rt.cod_vino
        ) tr ON tr.cod_vino = sd.cod_vino
        WHERE sd.cantidad <> (COALESCE(ing.tot_ing, 0) - COALESCE(tr.tot_transf, 0))

        UNION ALL

        -- 2) Stock final sala = transferencias procesadas - ventas
        SELECT ss.id_sala AS ref_id
        FROM stock_sala ss
        LEFT JOIN (
            SELECT t.id_sala, rt.cod_vino, SUM(rt.cantidad) AS tot_transf
            FROM renglon_transferencia rt
            JOIN transferencia t ON t.nro = rt.nro
            WHERE t.estado = 'procesado'
            GROUP BY t.id_sala, rt.cod_vino
        ) tr ON tr.id_sala = ss.id_sala AND tr.cod_vino = ss.cod_vino
        LEFT JOIN (
            SELECT c.id_sala, rc.cod_vino, SUM(rc.cantidad) AS tot_ventas
            FROM renglon_comprobante rc
            JOIN comprobante c ON c.nro = rc.nro
            GROUP BY c.id_sala, rc.cod_vino
        ) vta ON vta.id_sala = ss.id_sala AND vta.cod_vino = ss.cod_vino
        WHERE ss.cantidad <> (COALESCE(tr.tot_transf, 0) - COALESCE(vta.tot_ventas, 0))

        UNION ALL

        -- 3) Saldo acumulado diario en depósito nunca negativo
        SELECT cod_vino AS ref_id FROM (
            SELECT cod_vino,
                   SUM(delta) OVER (PARTITION BY cod_vino ORDER BY fecha, orden_tipo) AS saldo_acum
            FROM (
                SELECT ri.cod_vino, i.fecha AS fecha, 1 AS orden_tipo, SUM(ri.cantidad) AS delta
                FROM renglon_ingreso ri
                JOIN ingreso i ON i.cod_ingreso = ri.cod_ingreso
                WHERE i.estado = 'procesado'
                GROUP BY ri.cod_vino, i.fecha
                UNION ALL
                SELECT rt.cod_vino, t.fecha_confeccion AS fecha, 2 AS orden_tipo, -SUM(rt.cantidad) AS delta
                FROM renglon_transferencia rt
                JOIN transferencia t ON t.nro = rt.nro
                WHERE t.estado = 'procesado'
                GROUP BY rt.cod_vino, t.fecha_confeccion
            ) mov_dep
        ) s_dep
        WHERE saldo_acum < 0

        UNION ALL

        -- 4) Saldo acumulado diario en salas nunca negativo
        SELECT id_sala AS ref_id FROM (
            SELECT id_sala, cod_vino,
                   SUM(delta) OVER (PARTITION BY id_sala, cod_vino ORDER BY fecha, orden_tipo) AS saldo_acum
            FROM (
                SELECT t.id_sala, rt.cod_vino, t.fecha_confeccion AS fecha, 1 AS orden_tipo, SUM(rt.cantidad) AS delta
                FROM renglon_transferencia rt
                JOIN transferencia t ON t.nro = rt.nro
                WHERE t.estado = 'procesado'
                GROUP BY t.id_sala, rt.cod_vino, t.fecha_confeccion
                UNION ALL
                SELECT c.id_sala, rc.cod_vino, c.fecha AS fecha, 2 AS orden_tipo, -SUM(rc.cantidad) AS delta
                FROM renglon_comprobante rc
                JOIN comprobante c ON c.nro = rc.nro
                GROUP BY c.id_sala, rc.cod_vino, c.fecha
            ) mov_sala
        ) s_sala
        WHERE saldo_acum < 0

        UNION ALL

        -- 5) Precios históricos acordes a auditoria_precio (RI-03)
        SELECT rc.nro AS ref_id
        FROM renglon_comprobante rc
        JOIN comprobante c ON c.nro = rc.nro
        JOIN auditoria_precio ap ON ap.cod_vino = rc.cod_vino
        WHERE (c.fecha < ap.fecha_hora::date AND rc.precio_unitario <> ap.precio_anterior)
           OR (c.fecha >= ap.fecha_hora::date AND rc.precio_unitario <> ap.precio_nuevo)
    ) q;
    IF v_cnt > 0 THEN
        RAISE WARNING 'C11 FALLO: % registros con descuadre contable, saldo acumulado negativo o precios históricos erróneos', v_cnt;
        v_errores := v_errores + 1;
    ELSE
        RAISE NOTICE 'C11 OK: Conciliación contable de stock, saldo diario >= 0 y precios históricos perfectos';
    END IF;

    -- C12: Coherencia temporal
    SELECT count(*) INTO v_cnt FROM (
        SELECT 1 FROM analisis_calidad ac
        JOIN lote_uva lu ON lu.nro_lote = ac.nro_lote
        WHERE ac.fecha < lu.fecha_cosecha
        UNION ALL
        SELECT 1 FROM permiso_exportacion pe
        WHERE pe.fecha_vencimiento <= pe.fecha_emision
        UNION ALL
        SELECT 1 FROM comprobante c
        JOIN cliente cl ON cl.id_cliente = c.id_cliente
        WHERE c.fecha < cl.fecha_alta
        UNION ALL
        SELECT 1 FROM renglon_ingreso ri
        JOIN ingreso i ON i.cod_ingreso = ri.cod_ingreso
        JOIN vino v ON v.cod_vino = ri.cod_vino
        WHERE i.fecha < make_date(v.anada + 1, 1, 1)
    ) q;
    IF v_cnt > 0 THEN
        RAISE WARNING 'C12 FALLO: % registros con fechas incoherentes', v_cnt;
        v_errores := v_errores + 1;
    ELSE
        RAISE NOTICE 'C12 OK: Coherencia temporal de cosechas, añadas, análisis, permisos y ventas';
    END IF;

    -- C13: Sincronización de secuencias IDENTITY
    SELECT count(*) INTO v_cnt FROM (
        SELECT 1 FROM departamento HAVING (SELECT last_value FROM departamento_id_departamento_seq) < MAX(id_departamento)
        UNION ALL
        SELECT 1 FROM localidad HAVING (SELECT last_value FROM localidad_id_localidad_seq) < MAX(id_localidad)
        UNION ALL
        SELECT 1 FROM sala_venta HAVING (SELECT last_value FROM sala_venta_id_sala_seq) < MAX(id_sala)
        UNION ALL
        SELECT 1 FROM cepa HAVING (SELECT last_value FROM cepa_id_cepa_seq) < MAX(id_cepa)
        UNION ALL
        SELECT 1 FROM finca HAVING (SELECT last_value FROM finca_id_finca_seq) < MAX(id_finca)
        UNION ALL
        SELECT 1 FROM lote_uva HAVING (SELECT last_value FROM lote_uva_nro_lote_seq) < MAX(nro_lote)
        UNION ALL
        SELECT 1 FROM analisis_calidad HAVING (SELECT last_value FROM analisis_calidad_id_analisis_seq) < MAX(id_analisis)
        UNION ALL
        SELECT 1 FROM vino HAVING (SELECT last_value FROM vino_cod_vino_seq) < MAX(cod_vino)
        UNION ALL
        SELECT 1 FROM maridaje HAVING (SELECT last_value FROM maridaje_id_maridaje_seq) < MAX(id_maridaje)
        UNION ALL
        SELECT 1 FROM auditoria_precio HAVING (SELECT last_value FROM auditoria_precio_id_auditoria_seq) < MAX(id_auditoria)
        UNION ALL
        SELECT 1 FROM cliente HAVING (SELECT last_value FROM cliente_id_cliente_seq) < MAX(id_cliente)
        UNION ALL
        SELECT 1 FROM comprobante HAVING (SELECT last_value FROM comprobante_nro_seq) < MAX(nro)
        UNION ALL
        SELECT 1 FROM transportista HAVING (SELECT last_value FROM transportista_cod_transportista_seq) < MAX(cod_transportista)
        UNION ALL
        SELECT 1 FROM ingreso HAVING (SELECT last_value FROM ingreso_cod_ingreso_seq) < MAX(cod_ingreso)
        UNION ALL
        SELECT 1 FROM transferencia HAVING (SELECT last_value FROM transferencia_nro_seq) < MAX(nro)
    ) q;
    IF v_cnt > 0 THEN
        RAISE WARNING 'C13 FALLO: % secuencias desincronizadas', v_cnt;
        v_errores := v_errores + 1;
    ELSE
        RAISE NOTICE 'C13 OK: Las 15 secuencias IDENTITY sincronizadas correctamente';
    END IF;

    -- C14: Triggers de usuario habilitados
    SELECT count(*) INTO v_cnt
    FROM pg_trigger
    WHERE NOT tgisinternal AND tgenabled <> 'O';
    IF v_cnt > 0 THEN
        RAISE WARNING 'C14 FALLO: % triggers no se encuentran habilitados (tgenabled <> O)', v_cnt;
        v_errores := v_errores + 1;
    ELSE
        RAISE NOTICE 'C14 OK: Todos los triggers de usuario activos (tgenabled = O)';
    END IF;

    IF v_errores > 0 THEN
        RAISE EXCEPTION 'Se detectaron % controles fallidos en el Bloque B.', v_errores;
    END IF;

    RAISE NOTICE 'BATERIA DE CONTROLES C01..C14 COMPLETADA EXITOSAMENTE: 0 INCONSISTENCIAS.';
END $$;
