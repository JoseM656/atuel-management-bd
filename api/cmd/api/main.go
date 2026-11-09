package main

import (
	"context"
	"log"
	"net/http"

	"github.com/JoseM656/atuel-management-bd/internal/config"
	"github.com/JoseM656/atuel-management-bd/internal/db"
	"github.com/JoseM656/atuel-management-bd/internal/httpapi"
	"github.com/go-chi/chi/v5"
	"github.com/go-chi/chi/v5/middleware"
)

func main() {
	cfg, err := config.Load()
	if err != nil {
		log.Fatal(err)
	}

	pool, err := db.NewPool(context.Background(), cfg.DatabaseURL)
	if err != nil {
		log.Fatal(err)
	}
	defer pool.Close()

	health := &httpapi.HealthHandler{Pool: pool}
	vinos := &httpapi.VinosHandler{Pool: pool}
	clientes := &httpapi.ClientesHandler{Pool: pool}
	comprobantes := &httpapi.ComprobantesHandler{Pool: pool}

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

	log.Printf("[API] escuchando en :%s", cfg.Port)
	http.ListenAndServe(":"+cfg.Port, r)
}
