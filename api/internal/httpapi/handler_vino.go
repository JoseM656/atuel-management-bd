package httpapi

import (
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"strconv"
	"strings"

	"github.com/JoseM656/atuel-management-bd/internal/db"
	"github.com/JoseM656/atuel-management-bd/internal/httperr"
	"github.com/go-chi/chi/v5"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

type VinosHandler struct {
	Pool *pgxpool.Pool
}

// Listar responde GET /vinos con filtros (nombre, tipo, cepa, bodega, anada) y
// paginación (limit, offset). Devuelve {total, limit, offset, vinos}.
func (h *VinosHandler) Listar(w http.ResponseWriter, r *http.Request) {
	q := r.URL.Query()

	anada, err := queryInt(q.Get("anada"), 0)
	if err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": err.Error()})
		return
	}
	limit, err := queryInt(q.Get("limit"), 20)
	if err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": err.Error()})
		return
	}
	offset, err := queryInt(q.Get("offset"), 0)
	if err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": err.Error()})
		return
	}

	f := db.VinoFiltro{
		Nombre: strings.TrimSpace(q.Get("nombre")),
		Tipo:   q.Get("tipo"),
		Cepa:   q.Get("cepa"),
		Bodega: q.Get("bodega"),
		Anada:  anada,
		Limit:  limit,
		Offset: offset,
	}

	vinos, err := db.ListarVinos(r.Context(), h.Pool, f)
	if err != nil {
		httperr.Write(w, err)
		return
	}
	total, err := db.ContarVinos(r.Context(), h.Pool, f)
	if err != nil {
		httperr.Write(w, err)
		return
	}

	writeJSON(w, http.StatusOK, map[string]any{
		"total":  total,
		"limit":  limit,
		"offset": offset,
		"vinos":  vinos,
	})
}

// Obtener responde GET /vinos/{cod} con la ficha completa (S9): cabecera,
// bodega, stock total, cepas del corte y maridajes.
func (h *VinosHandler) Obtener(w http.ResponseWriter, r *http.Request) {
	cod, err := strconv.Atoi(chi.URLParam(r, "cod"))
	if err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "cod_vino inválido"})
		return
	}

	d, err := db.ObtenerVino(r.Context(), h.Pool, cod)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			writeJSON(w, http.StatusNotFound, map[string]string{"error": "vino no encontrado"})
			return
		}
		httperr.Write(w, err)
		return
	}
	writeJSON(w, http.StatusOK, d)
}

// Crear responde POST /vinos: alta de un vino con su composición y maridajes.
// Los triggers diferidos (RN-05 suma=100, RI-02 ≥1 maridaje) se validan en el
// commit y sus errores llegan como 409.
func (h *VinosHandler) Crear(w http.ResponseWriter, r *http.Request) {
	var v db.VinoNuevo
	if err := json.NewDecoder(r.Body).Decode(&v); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "JSON inválido: " + err.Error()})
		return
	}
	cod, err := db.CrearVino(r.Context(), h.Pool, v)
	if err != nil {
		httperr.Write(w, err)
		return
	}
	writeJSON(w, http.StatusCreated, map[string]int{"cod_vino": cod})
}

// Actualizar responde PUT /vinos/{cod}: reemplaza los campos del vino. Si
// cambia el precio, el trigger RN-13 lo audita.
func (h *VinosHandler) Actualizar(w http.ResponseWriter, r *http.Request) {
	cod, err := strconv.Atoi(chi.URLParam(r, "cod"))
	if err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "cod_vino inválido"})
		return
	}
	var v db.VinoActualizar
	if err := json.NewDecoder(r.Body).Decode(&v); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "JSON inválido: " + err.Error()})
		return
	}
	if err := db.ActualizarVino(r.Context(), h.Pool, cod, v); err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			writeJSON(w, http.StatusNotFound, map[string]string{"error": "vino no encontrado"})
			return
		}
		httperr.Write(w, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

// Borrar responde DELETE /vinos/{cod}: baja de un vino. RN-14 lo rechaza si
// tiene movimientos (23503 → 409).
func (h *VinosHandler) Borrar(w http.ResponseWriter, r *http.Request) {
	cod, err := strconv.Atoi(chi.URLParam(r, "cod"))
	if err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "cod_vino inválido"})
		return
	}
	if err := db.BorrarVino(r.Context(), h.Pool, cod); err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			writeJSON(w, http.StatusNotFound, map[string]string{"error": "vino no encontrado"})
			return
		}
		httperr.Write(w, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

// queryInt interpreta un parámetro de query como entero, con valor por
// defecto. Devuelve error si el valor está presente pero no es un entero.
func queryInt(s string, def int) (int, error) {
	if s == "" {
		return def, nil
	}
	v, err := strconv.Atoi(s)
	if err != nil {
		return 0, fmt.Errorf("parámetro inválido: se esperaba un entero, se recibió %q", s)
	}
	return v, nil
}
