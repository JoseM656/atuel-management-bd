package httpapi

import (
	"net/http"

	"github.com/jackc/pgx/v5/pgxpool"
)

type HealthHandler struct {
	Pool *pgxpool.Pool
}

func (h *HealthHandler) Salud(w http.ResponseWriter, r *http.Request) {
	if err := h.Pool.Ping(r.Context()); err != nil {
		http.Error(w, "base no accesible", http.StatusServiceUnavailable)
		return
	}
	w.WriteHeader(http.StatusOK)
	w.Write([]byte(`{"estado":"ok"}`))
}
