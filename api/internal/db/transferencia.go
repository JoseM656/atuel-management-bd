package db

import (
	"context"

	"github.com/jackc/pgx/v5/pgxpool"
)

// RenglonTransferenciaInput es un renglón de una transferencia en confección:
// vino y cantidad. El resto lo resuelven los procedimientos al procesar.
type RenglonTransferenciaInput struct {
	CodVino  int `json:"cod_vino"`
	Cantidad int `json:"cantidad"`
}

// CrearTransferencia crea una transferencia en_confeccion para una sala. La
// fecha_confeccion la fuerza el trigger trg_transferencia_fecha a la fecha
// actual y el estado nace en_confeccion (RN-11). Devuelve el número generado.
func CrearTransferencia(ctx context.Context, pool *pgxpool.Pool, idSala int) (int, error) {
	var nro int
	err := pool.QueryRow(ctx, `
		INSERT INTO transferencia (id_sala)
		VALUES ($1)
		RETURNING nro`, idSala).Scan(&nro)
	return nro, err
}

// AgregarRenglones carga renglones a una transferencia en confección, en una
// sola transacción. El trigger trg_renglon_transferencia_doc (RN-12) rechaza
// cualquier inserción si la transferencia ya no está en_confeccion.
func AgregarRenglones(ctx context.Context, pool *pgxpool.Pool, nro int, renglones []RenglonTransferenciaInput) error {
	tx, err := pool.Begin(ctx)
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx)

	for _, r := range renglones {
		if _, err := tx.Exec(ctx, `
			INSERT INTO renglon_transferencia (nro, cod_vino, cantidad)
			VALUES ($1, $2, $3)`, nro, r.CodVino, r.Cantidad); err != nil {
			return err
		}
	}

	return tx.Commit(ctx)
}

// TerminarTransferencia pasa la transferencia de en_confeccion a terminado
// (RN-11) invocando el procedimiento sp_terminar_transferencia (SECURITY
// DEFINER, ya que la API no tiene UPDATE sobre la columna estado).
func TerminarTransferencia(ctx context.Context, pool *pgxpool.Pool, nro int) error {
	_, err := pool.Exec(ctx, `CALL sp_terminar_transferencia($1)`, nro)
	return err
}

// ProcesarTransferencia procesa una transferencia terminado (RN-11): descuenta
// el stock del depósito, lo suma a la sala y la marca procesado, todo dentro
// del procedimiento sp_procesar_transferencia (atómico). Stock insuficiente
// lanza P0001 (→409) sin cambios a medias.
func ProcesarTransferencia(ctx context.Context, pool *pgxpool.Pool, nro int) error {
	_, err := pool.Exec(ctx, `CALL sp_procesar_transferencia($1)`, nro)
	return err
}
