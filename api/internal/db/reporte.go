package db

import (
	"context"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

// Este archivo expone las consultas S1–S12 (consultas/select.sql) como
// funciones de solo lectura. Cada una devuelve las filas tal como las define
// la consigna de la Etapa 5, sin efectos colaterales.

// collect ejecuta el patrón estándar de recorrer filas y devolver un slice,
// delegando el mapeo de cada fila en la función scan.
func collect[T any](rows pgx.Rows, scan func(pgx.Row) (T, error)) ([]T, error) {
	defer rows.Close()
	out := make([]T, 0)
	for rows.Next() {
		v, err := scan(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, v)
	}
	return out, rows.Err()
}

// ---- S1: top 10 vinos por botellas vendidas ----

type ReporteS1 struct {
	CodVino  int    `json:"cod_vino"`
	Nombre   string `json:"nombre"`
	Botellas int64  `json:"botellas"`
}

func S1(ctx context.Context, pool *pgxpool.Pool) ([]ReporteS1, error) {
	rows, err := pool.Query(ctx, `
		SELECT v.cod_vino, v.nombre, SUM(r.cantidad) AS botellas
		FROM renglon_comprobante r
		JOIN vino v ON v.cod_vino = r.cod_vino
		GROUP BY v.cod_vino, v.nombre
		ORDER BY botellas DESC, v.cod_vino
		LIMIT 10`)
	if err != nil {
		return nil, err
	}
	return collect(rows, func(r pgx.Row) (ReporteS1, error) {
		var v ReporteS1
		err := r.Scan(&v.CodVino, &v.Nombre, &v.Botellas)
		return v, err
	})
}

// ---- S2: vinos vendidos en todas las salas (división relacional) ----

type ReporteS2 struct {
	CodVino int    `json:"cod_vino"`
	Nombre  string `json:"nombre"`
}

func S2(ctx context.Context, pool *pgxpool.Pool) ([]ReporteS2, error) {
	rows, err := pool.Query(ctx, `
		SELECT v.cod_vino, v.nombre
		FROM vino v
		WHERE NOT EXISTS (
		    SELECT 1 FROM sala_venta s
		    WHERE NOT EXISTS (
		        SELECT 1
		        FROM comprobante c
		        JOIN renglon_comprobante r ON r.nro = c.nro
		        WHERE c.id_sala = s.id_sala AND r.cod_vino = v.cod_vino
		    )
		)
		ORDER BY v.cod_vino`)
	if err != nil {
		return nil, err
	}
	return collect(rows, func(r pgx.Row) (ReporteS2, error) {
		var v ReporteS2
		err := r.Scan(&v.CodVino, &v.Nombre)
		return v, err
	})
}

// ---- S3: clientes por tipo que compraron en una sala la última semana ----

type ReporteS3 struct {
	Tipo     string `json:"tipo"`
	Clientes int64  `json:"clientes"`
}

func S3(ctx context.Context, pool *pgxpool.Pool, sala int) ([]ReporteS3, error) {
	rows, err := pool.Query(ctx, `
		SELECT cl.tipo::text, COUNT(DISTINCT c.id_cliente) AS clientes
		FROM comprobante c
		JOIN cliente cl ON cl.id_cliente = c.id_cliente
		WHERE c.id_sala = $1 AND c.fecha >= CURRENT_DATE - 7
		GROUP BY cl.tipo`, sala)
	if err != nil {
		return nil, err
	}
	return collect(rows, func(r pgx.Row) (ReporteS3, error) {
		var v ReporteS3
		err := r.Scan(&v.Tipo, &v.Clientes)
		return v, err
	})
}

// ---- S4: top 5 salas que pidieron un vino por transferencia (15 días) ----

type ReporteS4 struct {
	IDSala              int   `json:"id_sala"`
	BotellasSolicitadas int64 `json:"botellas_solicitadas"`
}

func S4(ctx context.Context, pool *pgxpool.Pool, vino int) ([]ReporteS4, error) {
	rows, err := pool.Query(ctx, `
		SELECT t.id_sala, SUM(r.cantidad) AS botellas_solicitadas
		FROM renglon_transferencia r
		JOIN transferencia t ON t.nro = r.nro
		WHERE r.cod_vino = $1 AND t.fecha_confeccion >= CURRENT_DATE - 15
		GROUP BY t.id_sala
		ORDER BY botellas_solicitadas DESC, t.id_sala
		LIMIT 5`, vino)
	if err != nil {
		return nil, err
	}
	return collect(rows, func(r pgx.Row) (ReporteS4, error) {
		var v ReporteS4
		err := r.Scan(&v.IDSala, &v.BotellasSolicitadas)
		return v, err
	})
}

// ---- S5: salas con menos transferencias pendientes ----

type ReporteS5 struct {
	IDSala     int   `json:"id_sala"`
	Pendientes int64 `json:"pendientes"`
}

func S5(ctx context.Context, pool *pgxpool.Pool) ([]ReporteS5, error) {
	rows, err := pool.Query(ctx, `
		SELECT s.id_sala, COUNT(t.nro) AS pendientes
		FROM sala_venta s
		LEFT JOIN transferencia t ON t.id_sala = s.id_sala AND t.estado <> 'procesado'
		GROUP BY s.id_sala
		ORDER BY pendientes, s.id_sala`)
	if err != nil {
		return nil, err
	}
	return collect(rows, func(r pgx.Row) (ReporteS5, error) {
		var v ReporteS5
		err := r.Scan(&v.IDSala, &v.Pendientes)
		return v, err
	})
}

// ---- S6: vinos sin stock en sala pero con stock en depósito ----

type ReporteS6 struct {
	CodVino       int    `json:"cod_vino"`
	Nombre        string `json:"nombre"`
	StockDeposito int    `json:"stock_deposito"`
}

func S6(ctx context.Context, pool *pgxpool.Pool, sala int) ([]ReporteS6, error) {
	rows, err := pool.Query(ctx, `
		SELECT v.cod_vino, v.nombre, sd.cantidad AS stock_deposito
		FROM stock_deposito sd
		JOIN vino v ON v.cod_vino = sd.cod_vino
		WHERE sd.cantidad > 0
		  AND NOT EXISTS (
		      SELECT 1 FROM stock_sala ss
		      WHERE ss.id_sala = $1 AND ss.cod_vino = sd.cod_vino AND ss.cantidad > 0
		  )
		ORDER BY v.cod_vino`, sala)
	if err != nil {
		return nil, err
	}
	return collect(rows, func(r pgx.Row) (ReporteS6, error) {
		var v ReporteS6
		err := r.Scan(&v.CodVino, &v.Nombre, &v.StockDeposito)
		return v, err
	})
}

// ---- S7: transportista más activo del último mes ----

type ReporteS7 struct {
	CodTransportista    int    `json:"cod_transportista"`
	RazonSocial         string `json:"razon_social"`
	IngresosTrasladados int64  `json:"ingresos_trasladados"`
}

func S7(ctx context.Context, pool *pgxpool.Pool) ([]ReporteS7, error) {
	rows, err := pool.Query(ctx, `
		SELECT t.cod_transportista, t.razon_social, COUNT(i.cod_ingreso) AS ingresos_trasladados
		FROM transportista t
		JOIN ingreso i ON i.cod_transportista = t.cod_transportista
		WHERE i.fecha >= CURRENT_DATE - INTERVAL '1 month'
		GROUP BY t.cod_transportista, t.razon_social
		ORDER BY ingresos_trasladados DESC, t.cod_transportista
		LIMIT 1`)
	if err != nil {
		return nil, err
	}
	return collect(rows, func(r pgx.Row) (ReporteS7, error) {
		var v ReporteS7
		err := r.Scan(&v.CodTransportista, &v.RazonSocial, &v.IngresosTrasladados)
		return v, err
	})
}

// ---- S8: monto total de ventas por sala en el último trimestre ----

type ReporteS8 struct {
	IDSala     int     `json:"id_sala"`
	MontoTotal float64 `json:"monto_total"`
}

func S8(ctx context.Context, pool *pgxpool.Pool) ([]ReporteS8, error) {
	rows, err := pool.Query(ctx, `
		SELECT c.id_sala, SUM(c.total) AS monto_total
		FROM comprobante c
		WHERE c.fecha >= CURRENT_DATE - INTERVAL '3 months'
		GROUP BY c.id_sala
		ORDER BY monto_total DESC`)
	if err != nil {
		return nil, err
	}
	return collect(rows, func(r pgx.Row) (ReporteS8, error) {
		var v ReporteS8
		err := r.Scan(&v.IDSala, &v.MontoTotal)
		return v, err
	})
}

// ---- S9: ficha de un vino (cepas, bodega, maridajes, stock total) ----

type ReporteS9 struct {
	CodVino    int     `json:"cod_vino"`
	Nombre     string  `json:"nombre"`
	Tipo       string  `json:"tipo"`
	Anada      int     `json:"anada"`
	VolumenMl  int     `json:"volumen_ml"`
	Graduacion float64 `json:"graduacion"`
	Precio     float64 `json:"precio"`
	Bodega     string  `json:"bodega"`
	StockTotal int     `json:"stock_total"`
	Cepas      *string `json:"cepas"`
	Maridajes  *string `json:"maridajes"`
}

func S9(ctx context.Context, pool *pgxpool.Pool, vino int) ([]ReporteS9, error) {
	rows, err := pool.Query(ctx, `
		SELECT v.cod_vino, v.nombre, v.tipo::text, v.anada, v.volumen_ml,
		       v.graduacion, v.precio, b.razon_social AS bodega, st.stock_total,
		       (SELECT string_agg(c.nombre || ' ' || co.porcentaje::text || '%', ', '
		                           ORDER BY co.porcentaje DESC, c.nombre)
		        FROM composicion co JOIN cepa c ON c.id_cepa = co.id_cepa
		        WHERE co.cod_vino = v.cod_vino) AS cepas,
		       (SELECT string_agg(m.nombre || ' (' || m.temperatura_servicio::text || '°C)', ', '
		                           ORDER BY m.nombre)
		        FROM vino_maridaje vm JOIN maridaje m ON m.id_maridaje = vm.id_maridaje
		        WHERE vm.cod_vino = v.cod_vino) AS maridajes
		FROM vino v
		JOIN bodega b ON b.cuit = v.cuit_bodega
		JOIN v_stock_total_vino st ON st.cod_vino = v.cod_vino
		WHERE v.cod_vino = $1`, vino)
	if err != nil {
		return nil, err
	}
	return collect(rows, func(r pgx.Row) (ReporteS9, error) {
		var v ReporteS9
		err := r.Scan(&v.CodVino, &v.Nombre, &v.Tipo, &v.Anada, &v.VolumenMl,
			&v.Graduacion, &v.Precio, &v.Bodega, &v.StockTotal, &v.Cepas, &v.Maridajes)
		return v, err
	})
}

// ---- S10: rendimiento kg/ha por parcela/campaña vs promedio de la finca ----

type ReporteS10 struct {
	IDFinca            int     `json:"id_finca"`
	NroParcela         int     `json:"nro_parcela"`
	Campana            int     `json:"campana"`
	KgPorHa            float64 `json:"kg_por_ha"`
	RindeMenosQueFinca bool    `json:"rinde_menos_que_finca"`
}

func S10(ctx context.Context, pool *pgxpool.Pool) ([]ReporteS10, error) {
	rows, err := pool.Query(ctx, `
		WITH rendimiento AS (
		    SELECT l.id_finca, l.nro_parcela,
		           EXTRACT(YEAR FROM l.fecha_cosecha)::INTEGER AS campana,
		           l.kg / p.superficie_ha AS kg_por_ha
		    FROM lote_uva l
		    JOIN parcela p ON p.id_finca = l.id_finca AND p.nro_parcela = l.nro_parcela
		)
		SELECT r.id_finca, r.nro_parcela, r.campana, ROUND(r.kg_por_ha, 2) AS kg_por_ha,
		       r.kg_por_ha < (SELECT AVG(r2.kg_por_ha)
		                      FROM rendimiento r2
		                      WHERE r2.id_finca = r.id_finca AND r2.campana = r.campana) AS rinde_menos_que_finca
		FROM rendimiento r
		ORDER BY r.id_finca, r.campana, r.nro_parcela`)
	if err != nil {
		return nil, err
	}
	return collect(rows, func(r pgx.Row) (ReporteS10, error) {
		var v ReporteS10
		err := r.Scan(&v.IDFinca, &v.NroParcela, &v.Campana, &v.KgPorHa, &v.RindeMenosQueFinca)
		return v, err
	})
}

// ---- S11: ranking de vinos por sala y acumulado mensual por sala ----

type ReporteS11 struct {
	Reporte        string   `json:"reporte"`
	IDSala         int      `json:"id_sala"`
	CodVino        *int     `json:"cod_vino"`
	Nombre         *string  `json:"nombre"`
	Botellas       *int64   `json:"botellas"`
	Ranking        *int64   `json:"ranking"`
	Anio           *int     `json:"anio"`
	Mes            *int     `json:"mes"`
	MontoMensual   *float64 `json:"monto_mensual"`
	MontoAcumulado *float64 `json:"monto_acumulado"`
}

func S11(ctx context.Context, pool *pgxpool.Pool) ([]ReporteS11, error) {
	rows, err := pool.Query(ctx, `
		SELECT 'ranking_vinos'::text AS reporte, c.id_sala, v.cod_vino, v.nombre,
		       SUM(r.cantidad) AS botellas,
		       RANK() OVER (PARTITION BY c.id_sala ORDER BY SUM(r.cantidad) DESC) AS ranking,
		       NULL::INTEGER AS anio, NULL::INTEGER AS mes,
		       NULL::NUMERIC(12,2) AS monto_mensual, NULL::NUMERIC(12,2) AS monto_acumulado
		FROM comprobante c
		JOIN renglon_comprobante r ON r.nro = c.nro
		JOIN vino v ON v.cod_vino = r.cod_vino
		GROUP BY c.id_sala, v.cod_vino, v.nombre
		UNION ALL
		SELECT 'acumulado_mensual'::text AS reporte, id_sala,
		       NULL::INTEGER AS cod_vino, NULL::VARCHAR AS nombre,
		       NULL::BIGINT AS botellas, NULL::BIGINT AS ranking,
		       anio, mes, monto_mensual,
		       SUM(monto_mensual) OVER (PARTITION BY id_sala ORDER BY anio, mes
		                                 ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS monto_acumulado
		FROM (
		    SELECT id_sala,
		           EXTRACT(YEAR FROM fecha)::INTEGER AS anio,
		           EXTRACT(MONTH FROM fecha)::INTEGER AS mes,
		           SUM(total) AS monto_mensual
		    FROM comprobante
		    GROUP BY id_sala, EXTRACT(YEAR FROM fecha), EXTRACT(MONTH FROM fecha)
		) vm
		ORDER BY reporte, id_sala, ranking NULLS LAST, anio NULLS LAST, mes NULLS LAST`)
	if err != nil {
		return nil, err
	}
	return collect(rows, func(r pgx.Row) (ReporteS11, error) {
		var v ReporteS11
		err := r.Scan(&v.Reporte, &v.IDSala, &v.CodVino, &v.Nombre, &v.Botellas,
			&v.Ranking, &v.Anio, &v.Mes, &v.MontoMensual, &v.MontoAcumulado)
		return v, err
	})
}

// ---- S12: divisiones/anti-joins sobre clientes ----

type ReporteS12 struct {
	IDCliente         int    `json:"id_cliente"`
	NombreRazonSocial string `json:"nombre_razon_social"`
}

// S12a: clientes que compraron TODOS los vinos de una bodega determinada.
func S12a(ctx context.Context, pool *pgxpool.Pool, cuitBodega string) ([]ReporteS12, error) {
	rows, err := pool.Query(ctx, `
		SELECT c.id_cliente, c.nombre_razon_social
		FROM cliente c
		WHERE EXISTS (SELECT 1 FROM vino v WHERE v.cuit_bodega = $1)
		AND NOT EXISTS (
		    SELECT 1 FROM vino v
		    WHERE v.cuit_bodega = $1
		      AND NOT EXISTS (
		          SELECT 1
		          FROM comprobante co
		          JOIN renglon_comprobante rc ON rc.nro = co.nro
		          WHERE co.id_cliente = c.id_cliente AND rc.cod_vino = v.cod_vino
		      )
		)
		ORDER BY c.id_cliente`, cuitBodega)
	if err != nil {
		return nil, err
	}
	return collect(rows, func(r pgx.Row) (ReporteS12, error) {
		var v ReporteS12
		err := r.Scan(&v.IDCliente, &v.NombreRazonSocial)
		return v, err
	})
}

// S12b: clientes que NUNCA compraron ningún vino tinto.
func S12b(ctx context.Context, pool *pgxpool.Pool) ([]ReporteS12, error) {
	rows, err := pool.Query(ctx, `
		SELECT c.id_cliente, c.nombre_razon_social
		FROM cliente c
		WHERE NOT EXISTS (
		    SELECT 1
		    FROM comprobante co
		    JOIN renglon_comprobante rc ON rc.nro = co.nro
		    JOIN vino v ON v.cod_vino = rc.cod_vino
		    WHERE co.id_cliente = c.id_cliente AND v.tipo = 'tinto'
		)
		ORDER BY c.id_cliente`)
	if err != nil {
		return nil, err
	}
	return collect(rows, func(r pgx.Row) (ReporteS12, error) {
		var v ReporteS12
		err := r.Scan(&v.IDCliente, &v.NombreRazonSocial)
		return v, err
	})
}
