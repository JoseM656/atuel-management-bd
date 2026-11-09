// Package httperr traduce errores de PostgreSQL (SQLSTATE) a códigos HTTP y a
// un mensaje en castellano (#88).
//
// Mapeo HTTP (tabla del enunciado): 23505/23503→409 · 23514/23502→422 ·
// 22P02→400 · 40001/40P01→503 · P0001 (RAISE EXCEPTION de reglas RN/RI)→409 ·
// resto→500.
//
// Respuesta: {"error": "<mensaje>", "codigo": "<SQLSTATE>", "restriccion": "<nombre>"}.
// El mensaje sale de:
//   - P0001: el texto del RAISE EXCEPTION, sin el envoltorio «ERROR: … (SQLSTATE)».
//   - Restricción con entrada en mensajes.go: su texto.
//   - Resto: un texto genérico por SQLSTATE con el nombre de la restricción.
package httperr

import (
	"encoding/json"
	"errors"
	"net/http"
	"strings"

	"github.com/jackc/pgx/v5/pgconn"
)

// Status devuelve el código HTTP que corresponde al error. Si el error no es
// de PostgreSQL, devuelve 500.
func Status(err error) int {
	var pgErr *pgconn.PgError
	if !errors.As(err, &pgErr) {
		return http.StatusInternalServerError
	}

	switch pgErr.Code {
	case "23505", "23503": // unique_violation, foreign_key_violation
		return http.StatusConflict
	case "23514", "23502": // check_violation, not_null_violation
		return http.StatusUnprocessableEntity
	case "22P02": // invalid_text_representation
		return http.StatusBadRequest
	case "40001", "40P01": // serialization_failure, deadlock_detected
		return http.StatusServiceUnavailable
	case "P0001": // raise_exception: reglas RN/RI de triggers y procedimientos
		return http.StatusConflict
	default:
		return http.StatusInternalServerError
	}
}

// Respuesta es el cuerpo JSON de un error de la base.
type Respuesta struct {
	Error       string `json:"error"`
	Codigo      string `json:"codigo,omitempty"`
	Restriccion string `json:"restriccion,omitempty"`
}

// Traducir arma la respuesta para err. Si no es un error de PostgreSQL, el
// mensaje es err.Error() sin código.
func Traducir(err error) Respuesta {
	var pgErr *pgconn.PgError
	if !errors.As(err, &pgErr) {
		return Respuesta{Error: err.Error()}
	}
	return Respuesta{
		Error:       mensaje(pgErr),
		Codigo:      pgErr.Code,
		Restriccion: pgErr.ConstraintName,
	}
}

// mensaje elige el texto en castellano para un error de PostgreSQL.
func mensaje(e *pgconn.PgError) string {
	// RAISE EXCEPTION de triggers y procedimientos: ya está en castellano.
	if e.Code == "P0001" {
		return e.Message
	}

	if e.ConstraintName != "" {
		// Una FK se informa igual al cargar un hijo inexistente que al borrar
		// un padre en uso; PostgreSQL distingue el segundo caso con este prefijo.
		if e.Code == "23503" && strings.HasPrefix(e.Message, "update or delete on table") {
			if m, ok := mensajesBorrado[e.ConstraintName]; ok {
				return m
			}
			return "No se puede eliminar porque otros datos lo usan (restricción " + e.ConstraintName + ")."
		}
		if m, ok := mensajes[e.ConstraintName]; ok {
			return m
		}
	}

	switch e.Code {
	case "23505":
		return "Ya existe un registro con esos datos (restricción " + e.ConstraintName + ")."
	case "23503":
		return "El dato referenciado no existe (restricción " + e.ConstraintName + ")."
	case "23514":
		return "El dato no cumple la restricción " + e.ConstraintName + "."
	case "23502":
		return "Falta un dato obligatorio: " + e.ColumnName + "."
	case "22P02":
		return "Formato inválido: " + e.Message + "."
	case "40001", "40P01":
		return "La base no pudo completar la operación por otra que corría al mismo tiempo. Reintentá."
	default:
		return e.Message
	}
}

// Write escribe err como JSON con el código HTTP correspondiente.
func Write(w http.ResponseWriter, err error) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(Status(err))
	_ = json.NewEncoder(w).Encode(Traducir(err))
}
