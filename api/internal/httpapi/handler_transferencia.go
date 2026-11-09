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

type TransferenciasHandler struct {
	Pool *pgxpool.Pool
}

// Crear responde POST /transferencias: alta de una transferencia en_confeccion
// para una sala. La fecha la fuerza la base (RN-11).
func (h *TransferenciasHandler) Crear(w http.ResponseWriter, r *http.Request) {
	var body struct {
		IDSala int `json:"id_sala"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "JSON inválido: " + err.Error()})
		return
	}
	nro, err := db.CrearTransferencia(r.Context(), h.Pool, body.IDSala)
	if err != nil {
		httperr.Write(w, err)
		return
	}
	writeJSON(w, http.StatusCreated, map[string]int{"nro": nro})
}

// AgregarRenglones responde POST /transferencias/{nro}/renglones: carga
// renglones mientras la transferencia está en_confeccion. Fuera de confección
// el trigger RN-12 lo rechaza (409).
func (h *TransferenciasHandler) AgregarRenglones(w http.ResponseWriter, r *http.Request) {
	nro, err := strconv.Atoi(chi.URLParam(r, "nro"))
	if err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "nro inválido"})
		return
	}
	var renglones []db.RenglonTransferenciaInput
	if err := json.NewDecoder(r.Body).Decode(&renglones); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "JSON inválido: " + err.Error()})
		return
	}
	if err := db.AgregarRenglones(r.Context(), h.Pool, nro, renglones); err != nil {
		httperr.Write(w, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

// Listar responde GET /transferencias con filtros opcionales (estado, id_sala)
// y paginación (limit, offset). Devuelve {total, limit, offset, transferencias}.
// Un estado inexistente lo rechaza la base al castear al ENUM (22P02 → 400).
func (h *TransferenciasHandler) Listar(w http.ResponseWriter, r *http.Request) {
	q := r.URL.Query()

	limit, err := queryInt(q.Get("limit"), 20)
	if err != nil || limit < 1 {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "parámetro 'limit' inválido: debe ser un entero mayor que 0"})
		return
	}
	offset, err := queryInt(q.Get("offset"), 0)
	if err != nil || offset < 0 {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "parámetro 'offset' inválido: debe ser un entero mayor o igual que 0"})
		return
	}

	f := db.TransferenciaFiltro{Limit: limit, Offset: offset}
	if s := q.Get("estado"); s != "" {
		f.Estado = &s
	}
	if s := q.Get("id_sala"); s != "" {
		id, err := strconv.Atoi(s)
		if err != nil {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": "parámetro 'id_sala' inválido"})
			return
		}
		f.IDSala = &id
	}

	lista, err := db.ListarTransferencias(r.Context(), h.Pool, f)
	if err != nil {
		httperr.Write(w, err)
		return
	}
	total, err := db.ContarTransferencias(r.Context(), h.Pool, f)
	if err != nil {
		httperr.Write(w, err)
		return
	}

	writeJSON(w, http.StatusOK, map[string]any{
		"total":          total,
		"limit":          limit,
		"offset":         offset,
		"transferencias": lista,
	})
}

// Obtener responde GET /transferencias/{nro} con la cabecera (incluido el
// estado actual, RN-11) y los renglones. 404 si no existe.
func (h *TransferenciasHandler) Obtener(w http.ResponseWriter, r *http.Request) {
	nro, err := strconv.Atoi(chi.URLParam(r, "nro"))
	if err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "nro inválido"})
		return
	}

	d, err := db.ObtenerTransferencia(r.Context(), h.Pool, nro)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			writeJSON(w, http.StatusNotFound, map[string]string{"error": "transferencia no encontrada"})
			return
		}
		httperr.Write(w, err)
		return
	}
	writeJSON(w, http.StatusOK, d)
}

// Terminar responde POST /transferencias/{nro}/terminar: pasa de
// en_confeccion a terminado (sp_terminar_transferencia, RN-11).
func (h *TransferenciasHandler) Terminar(w http.ResponseWriter, r *http.Request) {
	nro, err := strconv.Atoi(chi.URLParam(r, "nro"))
	if err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "nro inválido"})
		return
	}
	if err := db.TerminarTransferencia(r.Context(), h.Pool, nro); err != nil {
		httperr.Write(w, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

// Procesar responde POST /transferencias/{nro}/procesar: procesa una
// transferencia terminado moviendo stock (sp_procesar_transferencia, RN-11).
func (h *TransferenciasHandler) Procesar(w http.ResponseWriter, r *http.Request) {
	nro, err := strconv.Atoi(chi.URLParam(r, "nro"))
	if err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "nro inválido"})
		return
	}
	if err := db.ProcesarTransferencia(r.Context(), h.Pool, nro); err != nil {
		httperr.Write(w, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}
