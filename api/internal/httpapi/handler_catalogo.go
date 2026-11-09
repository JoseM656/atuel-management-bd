package httpapi

import (
	"net/http"

	"github.com/JoseM656/atuel-management-bd/internal/db"
	"github.com/go-chi/chi/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

// CatalogoHandler expone los listados de catálogo para los desplegables del
// front (#87): GET /salas, /cepas, /bodegas y /maridajes. Solo lectura.
type CatalogoHandler struct {
	Pool *pgxpool.Pool
}

// Registrar agrega las rutas de catálogo al router.
func (h *CatalogoHandler) Registrar(r chi.Router) {
	r.Get("/salas", h.Salas)
	r.Get("/cepas", h.Cepas)
	r.Get("/bodegas", h.Bodegas)
	r.Get("/maridajes", h.Maridajes)
}

// Salas responde GET /salas: [{id_sala, descripcion, localidad}].
func (h *CatalogoHandler) Salas(w http.ResponseWriter, r *http.Request) {
	filas, err := db.ListarSalas(r.Context(), h.Pool)
	writeReporte(w, err, filas)
}

// Cepas responde GET /cepas: [{id_cepa, nombre, tipo}].
func (h *CatalogoHandler) Cepas(w http.ResponseWriter, r *http.Request) {
	filas, err := db.ListarCepas(r.Context(), h.Pool)
	writeReporte(w, err, filas)
}

// Bodegas responde GET /bodegas: [{cuit, razon_social}].
func (h *CatalogoHandler) Bodegas(w http.ResponseWriter, r *http.Request) {
	filas, err := db.ListarBodegas(r.Context(), h.Pool)
	writeReporte(w, err, filas)
}

// Maridajes responde GET /maridajes: [{id_maridaje, nombre, temperatura_servicio}].
func (h *CatalogoHandler) Maridajes(w http.ResponseWriter, r *http.Request) {
	filas, err := db.ListarMaridajes(r.Context(), h.Pool)
	writeReporte(w, err, filas)
}
