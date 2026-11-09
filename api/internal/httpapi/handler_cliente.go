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

type ClientesHandler struct {
	Pool *pgxpool.Pool
}

// Listar responde GET /clientes con filtro por tipo y paginación.
func (h *ClientesHandler) Listar(w http.ResponseWriter, r *http.Request) {
	q := r.URL.Query()

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

	f := db.ClienteFiltro{Tipo: q.Get("tipo"), Limit: limit, Offset: offset}

	clientes, err := db.ListarClientes(r.Context(), h.Pool, f)
	if err != nil {
		httperr.Write(w, err)
		return
	}
	total, err := db.ContarClientes(r.Context(), h.Pool, f)
	if err != nil {
		httperr.Write(w, err)
		return
	}

	writeJSON(w, http.StatusOK, map[string]any{
		"total":    total,
		"limit":    limit,
		"offset":   offset,
		"clientes": clientes,
	})
}

// Obtener responde GET /clientes/{id} con el cliente y su subtipo.
func (h *ClientesHandler) Obtener(w http.ResponseWriter, r *http.Request) {
	id, err := strconv.Atoi(chi.URLParam(r, "id"))
	if err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "id_cliente inválido"})
		return
	}

	c, err := db.ObtenerCliente(r.Context(), h.Pool, id)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			writeJSON(w, http.StatusNotFound, map[string]string{"error": "cliente no encontrado"})
			return
		}
		httperr.Write(w, err)
		return
	}
	writeJSON(w, http.StatusOK, c)
}

// Crear responde POST /clientes. El descuento lo asigna la base.
func (h *ClientesHandler) Crear(w http.ResponseWriter, r *http.Request) {
	var c db.ClienteNuevo
	if err := json.NewDecoder(r.Body).Decode(&c); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "JSON inválido: " + err.Error()})
		return
	}
	id, err := db.CrearCliente(r.Context(), h.Pool, c)
	if err != nil {
		httperr.Write(w, err)
		return
	}
	writeJSON(w, http.StatusCreated, map[string]int{"id_cliente": id})
}

// Actualizar responde PUT /clientes/{id}: reemplaza los campos comunes y los
// del subtipo actual.
func (h *ClientesHandler) Actualizar(w http.ResponseWriter, r *http.Request) {
	id, err := strconv.Atoi(chi.URLParam(r, "id"))
	if err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "id_cliente inválido"})
		return
	}
	var c db.ClienteActualizar
	if err := json.NewDecoder(r.Body).Decode(&c); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "JSON inválido: " + err.Error()})
		return
	}
	if err := db.ActualizarCliente(r.Context(), h.Pool, id, c); err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			writeJSON(w, http.StatusNotFound, map[string]string{"error": "cliente no encontrado"})
			return
		}
		httperr.Write(w, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

// Borrar responde DELETE /clientes/{id}. RN-14 lo rechaza si tiene comprobantes.
func (h *ClientesHandler) Borrar(w http.ResponseWriter, r *http.Request) {
	id, err := strconv.Atoi(chi.URLParam(r, "id"))
	if err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "id_cliente inválido"})
		return
	}
	if err := db.BorrarCliente(r.Context(), h.Pool, id); err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			writeJSON(w, http.StatusNotFound, map[string]string{"error": "cliente no encontrado"})
			return
		}
		httperr.Write(w, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}
