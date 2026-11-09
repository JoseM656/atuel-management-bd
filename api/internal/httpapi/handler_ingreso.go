package httpapi

import (
	"encoding/json"
	"net/http"
	"strconv"

	"github.com/JoseM656/atuel-management-bd/internal/db"
	"github.com/JoseM656/atuel-management-bd/internal/httperr"
	"github.com/go-chi/chi/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

type IngresosHandler struct {
	Pool *pgxpool.Pool
}

// Crear responde POST /ingresos: alta de un ingreso en_confeccion. La base
// valida transportista (RI-05) y pone fecha/estado (RN-10).
func (h *IngresosHandler) Crear(w http.ResponseWriter, r *http.Request) {
	var body struct {
		CodTransportista int    `json:"cod_transportista"`
		CuitBodega       string `json:"cuit_bodega"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "JSON inválido: " + err.Error()})
		return
	}
	cod, err := db.CrearIngreso(r.Context(), h.Pool, body.CodTransportista, body.CuitBodega)
	if err != nil {
		httperr.Write(w, err)
		return
	}
	writeJSON(w, http.StatusCreated, map[string]int{"cod_ingreso": cod})
}

// AgregarRenglones responde POST /ingresos/{cod}/renglones: carga renglones
// mientras el ingreso está en_confeccion. Fuera de confección lo rechaza
// RN-12 (409); un vino ajeno a la bodega lo rechaza RI-04 (409).
func (h *IngresosHandler) AgregarRenglones(w http.ResponseWriter, r *http.Request) {
	cod, err := strconv.Atoi(chi.URLParam(r, "cod"))
	if err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "cod inválido"})
		return
	}
	var renglones []db.RenglonIngresoInput
	if err := json.NewDecoder(r.Body).Decode(&renglones); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "JSON inválido: " + err.Error()})
		return
	}
	if err := db.AgregarRenglonesIngreso(r.Context(), h.Pool, cod, renglones); err != nil {
		httperr.Write(w, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

// Terminar responde POST /ingresos/{cod}/terminar: pasa de en_confeccion a
// terminado (sp_terminar_ingreso, RN-10).
func (h *IngresosHandler) Terminar(w http.ResponseWriter, r *http.Request) {
	cod, err := strconv.Atoi(chi.URLParam(r, "cod"))
	if err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "cod inválido"})
		return
	}
	if err := db.TerminarIngreso(r.Context(), h.Pool, cod); err != nil {
		httperr.Write(w, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

// Procesar responde POST /ingresos/{cod}/procesar: procesa un ingreso
// terminado impactando el depósito (sp_procesar_ingreso, RN-10).
func (h *IngresosHandler) Procesar(w http.ResponseWriter, r *http.Request) {
	cod, err := strconv.Atoi(chi.URLParam(r, "cod"))
	if err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "cod inválido"})
		return
	}
	if err := db.ProcesarIngreso(r.Context(), h.Pool, cod); err != nil {
		httperr.Write(w, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}
