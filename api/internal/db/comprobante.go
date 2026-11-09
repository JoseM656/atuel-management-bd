package db

import (
	"context"

	"github.com/jackc/pgx/v5/pgxpool"
)

// ComprobanteNuevo es el cuerpo de POST /comprobantes: la cabecera (cliente y
// sala) y los renglones (vino y cantidad). La API no envía ni calcula precios:
// el descuento, los precios y los totales los resuelve la base con sus
// funciones y triggers (RN-08, RN-09, RI-03).
type ComprobanteNuevo struct {
	IDCliente int                       `json:"id_cliente"`
	IDSala    int                       `json:"id_sala"`
	Renglones []RenglonComprobanteInput `json:"renglones"`
}

// RenglonComprobanteInput es un renglón de la venta: vino y cantidad. El resto
// (precio_unitario, importe_descuento, subtotal) lo completa el trigger
// trg_renglon_comprobante_bi.
type RenglonComprobanteInput struct {
	CodVino  int `json:"cod_vino"`
	Cantidad int `json:"cantidad"`
}

// CrearComprobante inserta la cabecera y sus renglones en una sola
// transacción. Los triggers de la base calculan descuento, precios, subtotal y
// total, validan el stock (RN-09) y lo descuentan. Si un renglón no tiene
// stock, el trigger lanza P0001 (→409) y el ROLLBACK deja la base sin datos a
// medias. Devuelve el número del comprobante generado.
func CrearComprobante(ctx context.Context, pool *pgxpool.Pool, c ComprobanteNuevo) (int, error) {
	tx, err := pool.Begin(ctx)
	if err != nil {
		return 0, err
	}
	defer tx.Rollback(ctx)

	var nro int
	if err := tx.QueryRow(ctx, `
		INSERT INTO comprobante (id_cliente, id_sala)
		VALUES ($1, $2)
		RETURNING nro`, c.IDCliente, c.IDSala).Scan(&nro); err != nil {
		return 0, err
	}

	for _, r := range c.Renglones {
		if _, err := tx.Exec(ctx, `
			INSERT INTO renglon_comprobante (nro, cod_vino, cantidad)
			VALUES ($1, $2, $3)`, nro, r.CodVino, r.Cantidad); err != nil {
			return 0, err
		}
	}

	if err := tx.Commit(ctx); err != nil {
		return 0, err
	}
	return nro, nil
}

// ComprobanteDetalle es la respuesta de GET /comprobantes/{nro}: la cabecera
// con su cliente y sala, y los renglones con los importes que calculó la base.
type ComprobanteDetalle struct {
	Nro                 int                  `json:"nro"`
	Fecha               string               `json:"fecha"`
	IDCliente           int                  `json:"id_cliente"`
	Cliente             string               `json:"cliente"`
	IDSala              int                  `json:"id_sala"`
	Subtotal            float64              `json:"subtotal"`
	PorcentajeDescuento float64              `json:"porcentaje_descuento"`
	Total               float64              `json:"total"`
	Renglones           []RenglonComprobante `json:"renglones"`
}

// RenglonComprobante es un renglón de un comprobante ya vendido, con los
// importes históricos que guardó la base (precio_unitario es copia del precio
// al vender, RI-03).
type RenglonComprobante struct {
	CodVino          int     `json:"cod_vino"`
	Vino             string  `json:"vino"`
	Cantidad         int     `json:"cantidad"`
	PrecioUnitario   float64 `json:"precio_unitario"`
	ImporteDescuento float64 `json:"importe_descuento"`
	Subtotal         float64 `json:"subtotal"`
}

// ObtenerComprobante devuelve la cabecera y los renglones de un comprobante.
// Devuelve pgx.ErrNoRows si el número no existe.
func ObtenerComprobante(ctx context.Context, pool *pgxpool.Pool, nro int) (*ComprobanteDetalle, error) {
	const cabecera = `
		SELECT c.nro, c.fecha::text, c.id_cliente, cl.nombre_razon_social,
		       c.id_sala, c.subtotal, c.porcentaje_descuento, c.total
		FROM comprobante c
		JOIN cliente cl ON cl.id_cliente = c.id_cliente
		WHERE c.nro = $1`

	d := &ComprobanteDetalle{Renglones: []RenglonComprobante{}}
	if err := pool.QueryRow(ctx, cabecera, nro).Scan(
		&d.Nro, &d.Fecha, &d.IDCliente, &d.Cliente,
		&d.IDSala, &d.Subtotal, &d.PorcentajeDescuento, &d.Total,
	); err != nil {
		return nil, err
	}

	const renglonesQuery = `
		SELECT r.cod_vino, v.nombre, r.cantidad, r.precio_unitario,
		       r.importe_descuento, r.subtotal
		FROM renglon_comprobante r
		JOIN vino v ON v.cod_vino = r.cod_vino
		WHERE r.nro = $1
		ORDER BY r.cod_vino`

	rows, err := pool.Query(ctx, renglonesQuery, nro)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	for rows.Next() {
		var r RenglonComprobante
		if err := rows.Scan(&r.CodVino, &r.Vino, &r.Cantidad, &r.PrecioUnitario, &r.ImporteDescuento, &r.Subtotal); err != nil {
			return nil, err
		}
		d.Renglones = append(d.Renglones, r)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}

	return d, nil
}
