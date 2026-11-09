package db

import (
	"context"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

// Listados de catálogo para los desplegables del front (#87): salas, cepas,
// bodegas y maridajes. Son de solo lectura y sin cálculos. Las tablas son
// chicas (decenas de filas), así que se devuelven completas, sin paginar,
// ordenadas por nombre para mostrarlas tal cual en un <select>.
//
// Cada fila trae el id (lo que se envía en POST /vinos y POST /comprobantes)
// y el nombre (lo que filtra GET /vinos?cepa=&bodega=).

// Sala es una sala de venta. sala_venta no tiene nombre: se describe con su
// dirección y localidad.
type Sala struct {
	IDSala      int    `json:"id_sala"`
	Descripcion string `json:"descripcion"` // "Av. Principal 10 115, San Rafael"
	Localidad   string `json:"localidad"`
}

// CepaItem es una cepa del catálogo.
type CepaItem struct {
	IDCepa int    `json:"id_cepa"`
	Nombre string `json:"nombre"`
	Tipo   string `json:"tipo"`
}

// Bodega es una bodega proveedora; el CUIT es su clave.
type Bodega struct {
	Cuit        string `json:"cuit"`
	RazonSocial string `json:"razon_social"`
}

// MaridajeItem es un maridaje del catálogo.
type MaridajeItem struct {
	IDMaridaje          int     `json:"id_maridaje"`
	Nombre              string  `json:"nombre"`
	TemperaturaServicio float64 `json:"temperatura_servicio"`
}

// listar ejecuta una consulta sin parámetros y mapea cada fila, por posición
// de columna, a un struct T. Devuelve una lista vacía (no nil) si no hay filas,
// así el JSON es [] y no null.
func listar[T any](ctx context.Context, pool *pgxpool.Pool, query string) ([]T, error) {
	rows, err := pool.Query(ctx, query)
	if err != nil {
		return nil, err
	}
	lista, err := pgx.CollectRows(rows, pgx.RowToStructByPos[T])
	if err != nil {
		return nil, err
	}
	if lista == nil {
		lista = []T{}
	}
	return lista, nil
}

// ListarSalas devuelve las salas de venta ordenadas por localidad y dirección.
func ListarSalas(ctx context.Context, pool *pgxpool.Pool) ([]Sala, error) {
	return listar[Sala](ctx, pool, `
		SELECT s.id_sala, `+salaDescripcion+`, l.nombre
		FROM sala_venta s
		JOIN localidad l ON l.id_localidad = s.id_localidad
		ORDER BY l.nombre, s.calle, s.numero`)
}

// ListarCepas devuelve las cepas ordenadas por nombre.
func ListarCepas(ctx context.Context, pool *pgxpool.Pool) ([]CepaItem, error) {
	return listar[CepaItem](ctx, pool, `
		SELECT id_cepa, nombre, tipo::text
		FROM cepa
		ORDER BY nombre`)
}

// ListarBodegas devuelve las bodegas ordenadas por razón social.
func ListarBodegas(ctx context.Context, pool *pgxpool.Pool) ([]Bodega, error) {
	return listar[Bodega](ctx, pool, `
		SELECT cuit::text, razon_social
		FROM bodega
		ORDER BY razon_social`)
}

// ListarMaridajes devuelve los maridajes ordenados por nombre.
func ListarMaridajes(ctx context.Context, pool *pgxpool.Pool) ([]MaridajeItem, error) {
	return listar[MaridajeItem](ctx, pool, `
		SELECT id_maridaje, nombre, temperatura_servicio::float8
		FROM maridaje
		ORDER BY nombre`)
}
