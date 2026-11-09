// Package httperr traduce errores de PostgreSQL (SQLSTATE) a códigos HTTP.
// Mapeo: 23505/23503→409 · 23514/23502→422 · 22P02→400 · 40001/40P01→503 ·
// P0001 (RAISE EXCEPTION de reglas RN/RI)→409 · resto→500.
package httperr

import (
	"encoding/json"
	"errors"
	"net/http"

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

type response struct {
	Error string `json:"error"`
}

// Write escribe err como JSON con el código HTTP correspondiente.
func Write(w http.ResponseWriter, err error) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(Status(err))
	_ = json.NewEncoder(w).Encode(response{Error: err.Error()})
}
