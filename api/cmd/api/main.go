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

	h := &httpapi.HealthHandler{Pool: pool}

	r := chi.NewRouter()
	r.Use(middleware.Logger, middleware.Recoverer)
	r.Get("/salud", h.Salud)

	log.Printf("[API] escuchando en :%s", cfg.Port)
	http.ListenAndServe(":"+cfg.Port, r)
}
