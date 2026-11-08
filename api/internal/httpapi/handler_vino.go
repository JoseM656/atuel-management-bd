package httpapi

import (
	"net/http"

	"github.com/JoseM656/atuel-management-bd/internal/db"
	"github.com/JoseM656/atuel-management-bd/internal/httperr"
	"github.com/jackc/pgx/v5/pgxpool"
)

type VinosHandler struct {
	Pool *pgxpool.Pool
}

// Listar responde GET /vinos. Filtro opcional por ?tipo=.
func (h *VinosHandler) Listar(w http.ResponseWriter, r *http.Request) {
	tipo := r.URL.Query().Get("tipo")

	vinos, err := db.ListarVinos(r.Context(), h.Pool, tipo)
	if err != nil {
		httperr.Write(w, err)
		return
	}
	writeJSON(w, http.StatusOK, vinos)
}
