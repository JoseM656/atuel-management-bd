package httpapi

import (
	"encoding/json"
	"errors"
	"net/http"
	"strconv"

	"github.com/JoseM656/atuel-management-bd/internal/db"
	"github.com/JoseM656/atuel-management-bd/internal/httperr"
	"github.com/go-chi/chi/v5"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

type ComprobantesHandler struct {
	Pool *pgxpool.Pool
}

// Crear responde POST /comprobantes: crea cabecera + renglones en una sola
// transacción. La base calcula descuento, precios y totales, y valida el stock
// (RN-09). Vender sin stock devuelve 409 y no deja datos a medias.
func (h *ComprobantesHandler) Crear(w http.ResponseWriter, r *http.Request) {
	var c db.ComprobanteNuevo
	if err := json.NewDecoder(r.Body).Decode(&c); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "JSON inválido: " + err.Error()})
		return
	}
	nro, err := db.CrearComprobante(r.Context(), h.Pool, c)
	if err != nil {
		httperr.Write(w, err)
		return
	}
	writeJSON(w, http.StatusCreated, map[string]int{"nro": nro})
}

// Obtener responde GET /comprobantes/{nro} con la cabecera y los renglones.
func (h *ComprobantesHandler) Obtener(w http.ResponseWriter, r *http.Request) {
	nro, err := strconv.Atoi(chi.URLParam(r, "nro"))
	if err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "nro inválido"})
		return
	}

	d, err := db.ObtenerComprobante(r.Context(), h.Pool, nro)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			writeJSON(w, http.StatusNotFound, map[string]string{"error": "comprobante no encontrado"})
			return
		}
		httperr.Write(w, err)
		return
	}
	writeJSON(w, http.StatusOK, d)
}
