package db

import (
	"context"

	"github.com/jackc/pgx/v5/pgxpool"
)

// RenglonIngresoInput es un renglón de un ingreso en confección: vino y
// cantidad. El vino debe pertenecer a la bodega de origen (RI-04).
type RenglonIngresoInput struct {
	CodVino  int `json:"cod_vino"`
	Cantidad int `json:"cantidad"`
}

// CrearIngreso crea un ingreso en_confeccion para un transportista y una
// bodega. La fecha la fuerza la base y el estado nace en_confeccion (RN-10).
// El transportista debe cubrir la localidad del depósito (RI-05). Devuelve el
// código generado.
func CrearIngreso(ctx context.Context, pool *pgxpool.Pool, codTransportista int, cuitBodega string) (int, error) {
	var cod int
	err := pool.QueryRow(ctx, `
		INSERT INTO ingreso (cod_transportista, cuit_bodega)
		VALUES ($1, $2)
		RETURNING cod_ingreso`, codTransportista, cuitBodega).Scan(&cod)
	return cod, err
}

// AgregarRenglonesIngreso carga renglones a un ingreso en confección, en una
// sola transacción. El trigger trg_renglon_ingreso_doc (RN-12) rechaza
// cualquier inserción si el ingreso ya no está en_confeccion, y
// trg_renglon_ingreso_bodega (RI-04) exige que el vino sea de la bodega.
func AgregarRenglonesIngreso(ctx context.Context, pool *pgxpool.Pool, cod int, renglones []RenglonIngresoInput) error {
	tx, err := pool.Begin(ctx)
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx)

	for _, r := range renglones {
		if _, err := tx.Exec(ctx, `
			INSERT INTO renglon_ingreso (cod_ingreso, cod_vino, cantidad)
			VALUES ($1, $2, $3)`, cod, r.CodVino, r.Cantidad); err != nil {
			return err
		}
	}

	return tx.Commit(ctx)
}

// TerminarIngreso pasa el ingreso de en_confeccion a terminado (RN-10)
// invocando el procedimiento sp_terminar_ingreso (SECURITY DEFINER).
func TerminarIngreso(ctx context.Context, pool *pgxpool.Pool, cod int) error {
	_, err := pool.Exec(ctx, `CALL sp_terminar_ingreso($1)`, cod)
	return err
}

// ProcesarIngreso procesa un ingreso terminado (RN-10): suma sus renglones al
// stock del depósito y lo marca procesado, dentro del procedimiento
// sp_procesar_ingreso (atómico). Solo un ingreso terminado impacta el depósito.
func ProcesarIngreso(ctx context.Context, pool *pgxpool.Pool, cod int) error {
	_, err := pool.Exec(ctx, `CALL sp_procesar_ingreso($1)`, cod)
	return err
}
