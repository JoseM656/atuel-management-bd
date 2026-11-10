package db

import (
	"context"
	"errors"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

// Consultas del tablero del front (#56), con las rutas que pide el enunciado:
// /reportes/top-vinos, /reportes/ventas-por-sala, /reportes/transportista-activo
// y /reportes/vinos-sin-stock.
//
// Cada una usa la misma lógica que su consulta de la sección 8 (S1, S8, S7 y
// S6, ver reporte.go y consultas/select.sql) y suma solo columnas para mostrar
// (añada, localidad, tipo, bodega, CUIT, período). Las consultas S no se
// tocan: su texto es idéntico al de las mediciones de la Etapa 4.

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

// ---- Transportista más activo del último mes (S7) ----

// TransportistaActivo trae el período usado (CURRENT_DATE - 1 mes) y el
// transportista con más ingresos trasladados, o null si no hubo ingresos.
type TransportistaActivo struct {
	Desde         string            `json:"desde"`
	Hasta         string            `json:"hasta"`
	Transportista *TransportistaTop `json:"transportista"`
}

type TransportistaTop struct {
	CodTransportista    int    `json:"cod_transportista"`
	RazonSocial         string `json:"razon_social"`
	Cuit                string `json:"cuit"`
	IngresosTrasladados int64  `json:"ingresos_trasladados"`
}

// TransportistaMasActivo: misma lógica que S7 (empate → menor código), con el
// CUIT para mostrar.
func TransportistaMasActivo(ctx context.Context, pool *pgxpool.Pool) (*TransportistaActivo, error) {
	res := &TransportistaActivo{}
	if err := pool.QueryRow(ctx, `
		SELECT (CURRENT_DATE - INTERVAL '1 month')::date::text, CURRENT_DATE::text`,
	).Scan(&res.Desde, &res.Hasta); err != nil {
		return nil, err
	}

	var t TransportistaTop
	err := pool.QueryRow(ctx, `
		SELECT t.cod_transportista, t.razon_social, t.cuit::text, COUNT(i.cod_ingreso) AS ingresos_trasladados
		FROM transportista t
		JOIN ingreso i ON i.cod_transportista = t.cod_transportista
		WHERE i.fecha >= CURRENT_DATE - INTERVAL '1 month'
		GROUP BY t.cod_transportista, t.razon_social, t.cuit
		ORDER BY ingresos_trasladados DESC, t.cod_transportista
		LIMIT 1`).Scan(&t.CodTransportista, &t.RazonSocial, &t.Cuit, &t.IngresosTrasladados)
	if errors.Is(err, pgx.ErrNoRows) {
		return res, nil // sin ingresos en el período: transportista = null
	}
	if err != nil {
		return nil, err
	}
	res.Transportista = &t
	return res, nil
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
