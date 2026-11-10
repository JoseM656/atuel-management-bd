package httperr

import (
	"errors"
	"fmt"
	"net/http"
	"testing"

	"github.com/jackc/pgx/v5/pgconn"
)

// Tests unitarios de la traducción (#88): no necesitan base, arman el
// *pgconn.PgError a mano con los campos que manda PostgreSQL.

func TestTraducir(t *testing.T) {
	casos := []struct {
		nombre  string
		err     *pgconn.PgError
		status  int
		mensaje string
	}{
		{
			nombre:  "CHECK con mensaje propio",
			err:     &pgconn.PgError{Code: "23514", ConstraintName: "ck_vino_anada", Message: `new row for relation "vino" violates check constraint "ck_vino_anada"`},
			status:  http.StatusUnprocessableEntity,
			mensaje: "La añada debe estar entre 1990 y 2100.",
		},
		{
			nombre:  "P0001 sin envoltorio",
			err:     &pgconn.PgError{Code: "P0001", Message: "stock insuficiente del vino 1 en la sala 1: hay 15 y se piden 99"},
			status:  http.StatusConflict,
			mensaje: "stock insuficiente del vino 1 en la sala 1: hay 15 y se piden 99",
		},
		{
			nombre:  "FK al borrar el vino (RN-14)",
			err:     &pgconn.PgError{Code: "23503", ConstraintName: "fk_rc_vino", Message: `update or delete on table "vino" violates foreign key constraint "fk_rc_vino" on table "renglon_comprobante"`},
			status:  http.StatusConflict,
			mensaje: mensajeVinoEnUso,
		},
		{
			nombre:  "la misma FK al cargar un vino inexistente",
			err:     &pgconn.PgError{Code: "23503", ConstraintName: "fk_rc_vino", Message: `insert or update on table "renglon_comprobante" violates foreign key constraint "fk_rc_vino"`},
			status:  http.StatusConflict,
			mensaje: "El vino elegido no existe.",
		},
		{
			nombre:  "restricción sin mensaje: genérico con el nombre",
			err:     &pgconn.PgError{Code: "23514", ConstraintName: "ck_otra"},
			status:  http.StatusUnprocessableEntity,
			mensaje: "El dato no cumple la restricción ck_otra.",
		},
		{
			nombre:  "serialización: sugiere reintentar",
			err:     &pgconn.PgError{Code: "40001"},
			status:  http.StatusServiceUnavailable,
			mensaje: "La base no pudo completar la operación por otra que corría al mismo tiempo. Reintentá.",
		},
	}

	for _, c := range casos {
		t.Run(c.nombre, func(t *testing.T) {
			// Envuelto, como llega desde las capas de db.
			err := fmt.Errorf("db: %w", c.err)
			if s := Status(err); s != c.status {
				t.Errorf("status: esperaba %d, obtuve %d", c.status, s)
			}
			r := Traducir(err)
			if r.Error != c.mensaje || r.Codigo != c.err.Code || r.Restriccion != c.err.ConstraintName {
				t.Errorf("respuesta inesperada: %+v", r)
			}
		})
	}
}

func TestTraducirErrorNoPostgres(t *testing.T) {
	r := Traducir(errors.New("se cortó la conexión"))
	if r.Error != "se cortó la conexión" || r.Codigo != "" || r.Restriccion != "" {
		t.Fatalf("respuesta inesperada: %+v", r)
	}
}
