package httpapi

import (
	"github.com/go-chi/chi/v5"
	"github.com/go-chi/chi/v5/middleware"
	"github.com/jackc/pgx/v5/pgxpool"
)

// NewRouter arma el router de la API con todas sus rutas. Lo usan main.go y
// los tests de integración (para no duplicar el registro de rutas).
func NewRouter(pool *pgxpool.Pool) *chi.Mux {
	health := &HealthHandler{Pool: pool}
	vinos := &VinosHandler{Pool: pool}
	clientes := &ClientesHandler{Pool: pool}
	comprobantes := &ComprobantesHandler{Pool: pool}
	transferencias := &TransferenciasHandler{Pool: pool}
	ingresos := &IngresosHandler{Pool: pool}
	reportes := &ReportesHandler{Pool: pool}
	catalogo := &CatalogoHandler{Pool: pool}

	r := chi.NewRouter()
	r.Use(middleware.Logger, middleware.Recoverer)

	r.Get("/salud", health.Salud)

	r.Get("/vinos", vinos.Listar)
	r.Post("/vinos", vinos.Crear)
	r.Get("/vinos/{cod}", vinos.Obtener)
	r.Put("/vinos/{cod}", vinos.Actualizar)
	r.Delete("/vinos/{cod}", vinos.Borrar)

	r.Get("/clientes", clientes.Listar)
	r.Post("/clientes", clientes.Crear)
	r.Get("/clientes/{id}", clientes.Obtener)
	r.Put("/clientes/{id}", clientes.Actualizar)
	r.Delete("/clientes/{id}", clientes.Borrar)

	r.Post("/comprobantes", comprobantes.Crear)
	r.Get("/comprobantes/{nro}", comprobantes.Obtener)

	r.Get("/transferencias", transferencias.Listar)
	r.Post("/transferencias", transferencias.Crear)
	r.Get("/transferencias/{nro}", transferencias.Obtener)
	r.Post("/transferencias/{nro}/renglones", transferencias.AgregarRenglones)
	r.Post("/transferencias/{nro}/terminar", transferencias.Terminar)
	r.Post("/transferencias/{nro}/procesar", transferencias.Procesar)

	r.Post("/ingresos", ingresos.Crear)
	r.Post("/ingresos/{cod}/renglones", ingresos.AgregarRenglones)
	r.Post("/ingresos/{cod}/terminar", ingresos.Terminar)
	r.Post("/ingresos/{cod}/procesar", ingresos.Procesar)

	catalogo.Registrar(r)
	reportes.Registrar(r)

	return r
}
