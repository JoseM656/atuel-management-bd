package db

import (
	"context"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

// Consultas del tablero del front (#56), con las rutas que pide el enunciado:
// /reportes/top-vinos, /reportes/ventas-por-sala y /reportes/vinos-sin-stock.
//
// Cada una usa la misma lógica que su consulta de la sección 8 (S1, S8 y S6,
// ver reporte.go y consultas/select.sql) y suma solo columnas para mostrar
// (añada, localidad, tipo, bodega). S1, S6 y S8 no se tocan: su texto es
// idéntico al de las mediciones de la Etapa 4.

// ---- Top 10 vinos más vendidos (S1) ----

type TopVino struct {
	CodVino   int    `json:"cod_vino"`
	Nombre    string `json:"nombre"`
	Anada     int    `json:"anada"`
	VolumenML int    `json:"volumen_ml"`
	Botellas  int64  `json:"botellas"`
}

func TopVinos(ctx context.Context, pool *pgxpool.Pool) ([]TopVino, error) {
	rows, err := pool.Query(ctx, `
		SELECT v.cod_vino, v.nombre, v.anada, v.volumen_ml, SUM(r.cantidad) AS botellas
		FROM renglon_comprobante r
		JOIN vino v ON v.cod_vino = r.cod_vino
		GROUP BY v.cod_vino
		ORDER BY botellas DESC, v.cod_vino
		LIMIT 10`)
	if err != nil {
		return nil, err
	}
	return collect(rows, func(r pgx.Row) (TopVino, error) {
		var v TopVino
		err := r.Scan(&v.CodVino, &v.Nombre, &v.Anada, &v.VolumenML, &v.Botellas)
		return v, err
	})
}

// ---- Ventas por sala del último trimestre (S8) ----

// VentasPorSala trae el período que usó la base (desde/hasta, con
// CURRENT_DATE) para que el front lo muestre sin calcular fechas.
type VentasPorSala struct {
	Desde string      `json:"desde"`
	Hasta string      `json:"hasta"`
	Salas []VentaSala `json:"salas"`
}

type VentaSala struct {
	IDSala     int     `json:"id_sala"`
	Localidad  string  `json:"localidad"`
	MontoTotal float64 `json:"monto_total"`
}

func VentasPorSalaTrimestre(ctx context.Context, pool *pgxpool.Pool) (*VentasPorSala, error) {
	res := &VentasPorSala{}
	if err := pool.QueryRow(ctx, `
		SELECT (CURRENT_DATE - INTERVAL '3 months')::date::text, CURRENT_DATE::text`,
	).Scan(&res.Desde, &res.Hasta); err != nil {
		return nil, err
	}

	rows, err := pool.Query(ctx, `
		SELECT c.id_sala, l.nombre, SUM(c.total) AS monto_total
		FROM comprobante c
		JOIN sala_venta s ON s.id_sala = c.id_sala
		JOIN localidad  l ON l.id_localidad = s.id_localidad
		WHERE c.fecha >= CURRENT_DATE - INTERVAL '3 months'
		GROUP BY c.id_sala, l.nombre
		ORDER BY monto_total DESC, c.id_sala`)
	if err != nil {
		return nil, err
	}
	res.Salas, err = collect(rows, func(r pgx.Row) (VentaSala, error) {
		var v VentaSala
		err := r.Scan(&v.IDSala, &v.Localidad, &v.MontoTotal)
		return v, err
	})
	return res, err
}

// ---- Vinos sin stock en una sala, con stock en el depósito (S6) ----

type VinoSinStock struct {
	CodVino       int    `json:"cod_vino"`
	Nombre        string `json:"nombre"`
	Anada         int    `json:"anada"`
	VolumenML     int    `json:"volumen_ml"`
	Tipo          string `json:"tipo"`
	Bodega        string `json:"bodega"`
	StockSala     int    `json:"stock_sala"`
	StockDeposito int    `json:"stock_deposito"`
}

// VinosSinStock: mismo anti-join que S6. El LEFT JOIN a stock_sala solo trae
// la cantidad de la sala para mostrarla (siempre 0 o sin fila, por el filtro).
func VinosSinStock(ctx context.Context, pool *pgxpool.Pool, sala int) ([]VinoSinStock, error) {
	rows, err := pool.Query(ctx, `
		SELECT v.cod_vino, v.nombre, v.anada, v.volumen_ml, v.tipo::text, b.razon_social,
		       COALESCE(ss.cantidad, 0) AS stock_sala, sd.cantidad AS stock_deposito
		FROM stock_deposito sd
		JOIN vino   v ON v.cod_vino = sd.cod_vino
		JOIN bodega b ON b.cuit = v.cuit_bodega
		LEFT JOIN stock_sala ss ON ss.id_sala = $1 AND ss.cod_vino = sd.cod_vino
		WHERE sd.cantidad > 0
		  AND NOT EXISTS (
		      SELECT 1 FROM stock_sala x
		      WHERE x.id_sala = $1 AND x.cod_vino = sd.cod_vino AND x.cantidad > 0
		  )
		ORDER BY v.cod_vino`, sala)
	if err != nil {
		return nil, err
	}
	return collect(rows, func(r pgx.Row) (VinoSinStock, error) {
		var v VinoSinStock
		err := r.Scan(&v.CodVino, &v.Nombre, &v.Anada, &v.VolumenML, &v.Tipo, &v.Bodega, &v.StockSala, &v.StockDeposito)
		return v, err
	})
}
