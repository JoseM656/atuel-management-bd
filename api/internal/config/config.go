package config

import (
	"fmt"
	"os"
)

// Config reúne la configuración de la API que viene del entorno.
type Config struct {
	DatabaseURL string // DSN de PostgreSQL (rol app_rw)
	Port        string // puerto HTTP, default "3333"
}

// Load lee el entorno y valida lo mínimo.
func Load() (Config, error) {
	cfg := Config{
		DatabaseURL: os.Getenv("DATABASE_URL"),
		Port:        getenv("PORT", "3333"),
	}
	if cfg.DatabaseURL == "" {
		return cfg, fmt.Errorf("[API] DATABASE_URL no está definida en el entorno")
	}
	return cfg, nil
}

func getenv(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}
