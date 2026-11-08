// Package db concentra el acceso a la base de datos: el pool de conexiones
// y, en la siguiente etapa, una función por consulta.
package db

import (
	"context"

	"github.com/jackc/pgx/v5/pgxpool"
)

// NewPool crea el pool de conexiones a partir de un DSN.
// No conecta de inmediato: la conexión real se valida en el primer uso
// (por ejemplo, el Ping del endpoint /salud).
func NewPool(ctx context.Context, dsn string) (*pgxpool.Pool, error) {
	return pgxpool.New(ctx, dsn)
}
