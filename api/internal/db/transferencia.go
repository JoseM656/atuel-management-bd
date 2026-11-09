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

// TransferenciaDetalle es la respuesta de GET /transferencias/{nro}: la
// cabecera con su estado actual y los renglones cargados. El front usa el
// estado para habilitar los botones Terminar / Procesar (RN-11).
type TransferenciaDetalle struct {
	Nro             int                    `json:"nro"`
	IDSala          int                    `json:"id_sala"`
	Sala            string                 `json:"sala"`
	FechaConfeccion string                 `json:"fecha_confeccion"`
	Estado          string                 `json:"estado"`
	Renglones       []RenglonTransferencia `json:"renglones"`
}

// RenglonTransferencia es un renglón ya cargado: vino y cantidad.
type RenglonTransferencia struct {
	CodVino  int    `json:"cod_vino"`
	Vino     string `json:"vino"`
	Cantidad int    `json:"cantidad"`
}

// salaDescripcion arma un texto legible de la sala (sala_venta no tiene
// nombre): "San Martín 123, General Alvear".
const salaDescripcion = `s.calle || ' ' || s.numero || ', ' || l.nombre`

// ObtenerTransferencia devuelve la cabecera y los renglones de una
// transferencia. Devuelve pgx.ErrNoRows si el número no existe.
func ObtenerTransferencia(ctx context.Context, pool *pgxpool.Pool, nro int) (*TransferenciaDetalle, error) {
	cabecera := `
		SELECT t.nro, t.id_sala, ` + salaDescripcion + `,
		       t.fecha_confeccion::text, t.estado::text
		FROM transferencia t
		JOIN sala_venta s ON s.id_sala = t.id_sala
		JOIN localidad  l ON l.id_localidad = s.id_localidad
		WHERE t.nro = $1`

	d := &TransferenciaDetalle{Renglones: []RenglonTransferencia{}}
	if err := pool.QueryRow(ctx, cabecera, nro).Scan(
		&d.Nro, &d.IDSala, &d.Sala, &d.FechaConfeccion, &d.Estado,
	); err != nil {
		return nil, err
	}

	rows, err := pool.Query(ctx, `
		SELECT r.cod_vino, v.nombre, r.cantidad
		FROM renglon_transferencia r
		JOIN vino v ON v.cod_vino = r.cod_vino
		WHERE r.nro = $1
		ORDER BY r.cod_vino`, nro)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	for rows.Next() {
		var r RenglonTransferencia
		if err := rows.Scan(&r.CodVino, &r.Vino, &r.Cantidad); err != nil {
			return nil, err
		}
		d.Renglones = append(d.Renglones, r)
	}
	return d, rows.Err()
}

// TransferenciaFiltro son los filtros de GET /transferencias. Un puntero nil
// significa «sin filtro».
type TransferenciaFiltro struct {
	Estado *string // en_confeccion | terminado | procesado
	IDSala *int
	Limit  int
	Offset int
}

// TransferenciaResumen es una fila del listado: la cabecera y cuántos
// renglones tiene, sin el detalle.
type TransferenciaResumen struct {
	Nro             int    `json:"nro"`
	IDSala          int    `json:"id_sala"`
	Sala            string `json:"sala"`
	FechaConfeccion string `json:"fecha_confeccion"`
	Estado          string `json:"estado"`
	CantRenglones   int    `json:"cant_renglones"`
}

// transferenciaWhere filtra con parámetros fijos: si el filtro es NULL no
// restringe. El cast $1::estado_documento lo valida la base: un estado
// inexistente falla con 22P02, que httperr traduce a 400.
const transferenciaWhere = `
	WHERE ($1::text IS NULL OR t.estado = $1::estado_documento)
	  AND ($2::int  IS NULL OR t.id_sala = $2)`

// ListarTransferencias devuelve una página de transferencias, de la más
// reciente a la más antigua.
func ListarTransferencias(ctx context.Context, pool *pgxpool.Pool, f TransferenciaFiltro) ([]TransferenciaResumen, error) {
	query := `
		SELECT t.nro, t.id_sala, ` + salaDescripcion + `,
		       t.fecha_confeccion::text, t.estado::text,
		       (SELECT count(*) FROM renglon_transferencia r WHERE r.nro = t.nro)
		FROM transferencia t
		JOIN sala_venta s ON s.id_sala = t.id_sala
		JOIN localidad  l ON l.id_localidad = s.id_localidad` +
		transferenciaWhere + `
		ORDER BY t.nro DESC
		LIMIT $3 OFFSET $4`

	rows, err := pool.Query(ctx, query, f.Estado, f.IDSala, f.Limit, f.Offset)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	lista := []TransferenciaResumen{}
	for rows.Next() {
		var t TransferenciaResumen
		if err := rows.Scan(&t.Nro, &t.IDSala, &t.Sala, &t.FechaConfeccion, &t.Estado, &t.CantRenglones); err != nil {
			return nil, err
		}
		lista = append(lista, t)
	}
	return lista, rows.Err()
}

// ContarTransferencias devuelve cuántas transferencias cumplen el filtro, para
// la paginación.
func ContarTransferencias(ctx context.Context, pool *pgxpool.Pool, f TransferenciaFiltro) (int, error) {
	var total int
	err := pool.QueryRow(ctx,
		`SELECT count(*) FROM transferencia t`+transferenciaWhere,
		f.Estado, f.IDSala).Scan(&total)
	return total, err
}

// ProcesarTransferencia procesa una transferencia terminado (RN-11): descuenta
// el stock del depósito, lo suma a la sala y la marca procesado, todo dentro
// del procedimiento sp_procesar_transferencia (atómico). Stock insuficiente
// lanza P0001 (→409) sin cambios a medias.
func ProcesarTransferencia(ctx context.Context, pool *pgxpool.Pool, nro int) error {
	_, err := pool.Exec(ctx, `CALL sp_procesar_transferencia($1)`, nro)
	return err
}
