package db

import (
	"context"
	"fmt"
	"strings"

	"github.com/jackc/pgx/v5/pgxpool"
)

// Vino es la proyección de vino + bodega que devuelve GET /vinos.
type Vino struct {
	CodVino    int     `json:"cod_vino"`
	Nombre     string  `json:"nombre"`
	Tipo       string  `json:"tipo"`
	Anada      int     `json:"anada"`
	VolumenMl  int     `json:"volumen_ml"`
	Graduacion float64 `json:"graduacion"`
	Precio     float64 `json:"precio"`
	Bodega     string  `json:"bodega"`
}

// VinoFiltro reúne los filtros opcionales y la paginación de GET /vinos.
// Un string vacío o un 0 no filtran.
type VinoFiltro struct {
	Tipo   string
	Cepa   string
	Bodega string
	Anada  int
	Limit  int
	Offset int
}

const vinoSelect = `
	SELECT v.cod_vino, v.nombre, v.tipo, v.anada, v.volumen_ml,
	       v.graduacion, v.precio, b.razon_social
	FROM vino v
	JOIN bodega b ON b.cuit = v.cuit_bodega`

// buildVinoWhere arma la cláusula WHERE (y sus argumentos) según los filtros.
// Solo el valor viaja como parámetro ($n); el texto del usuario nunca se
// concatena en el SQL.
func buildVinoWhere(f VinoFiltro) (string, []any) {
	var conds []string
	var args []any

	if f.Tipo != "" {
		args = append(args, f.Tipo)
		conds = append(conds, fmt.Sprintf("v.tipo::text = $%d", len(args)))
	}
	if f.Cepa != "" {
		args = append(args, f.Cepa)
		conds = append(conds, fmt.Sprintf(
			"EXISTS (SELECT 1 FROM composicion co JOIN cepa c ON c.id_cepa = co.id_cepa WHERE co.cod_vino = v.cod_vino AND c.nombre = $%d)",
			len(args)))
	}
	if f.Bodega != "" {
		args = append(args, f.Bodega)
		conds = append(conds, fmt.Sprintf("b.razon_social = $%d", len(args)))
	}
	if f.Anada != 0 {
		args = append(args, f.Anada)
		conds = append(conds, fmt.Sprintf("v.anada = $%d", len(args)))
	}

	if len(conds) == 0 {
		return "", args
	}
	return " WHERE " + strings.Join(conds, " AND "), args
}

// ListarVinos devuelve los vinos que cumplen los filtros, paginados.
func ListarVinos(ctx context.Context, pool *pgxpool.Pool, f VinoFiltro) ([]Vino, error) {
	where, args := buildVinoWhere(f)
	query := vinoSelect + where + " ORDER BY v.cod_vino"
	if f.Limit > 0 {
		args = append(args, f.Limit)
		query += fmt.Sprintf(" LIMIT $%d", len(args))
		args = append(args, f.Offset)
		query += fmt.Sprintf(" OFFSET $%d", len(args))
	}

	rows, err := pool.Query(ctx, query, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	vinos := make([]Vino, 0)
	for rows.Next() {
		var v Vino
		if err := rows.Scan(&v.CodVino, &v.Nombre, &v.Tipo, &v.Anada, &v.VolumenMl, &v.Graduacion, &v.Precio, &v.Bodega); err != nil {
			return nil, err
		}
		vinos = append(vinos, v)
	}
	return vinos, rows.Err()
}

// ContarVinos cuenta cuántos vinos cumplen los filtros (sin paginar). Sirve
// para devolver el total junto a la página.
func ContarVinos(ctx context.Context, pool *pgxpool.Pool, f VinoFiltro) (int, error) {
	where, args := buildVinoWhere(f)
	query := "SELECT count(*) FROM vino v JOIN bodega b ON b.cuit = v.cuit_bodega" + where

	var total int
	if err := pool.QueryRow(ctx, query, args...).Scan(&total); err != nil {
		return 0, err
	}
	return total, nil
}

// VinoDetalle es la ficha completa de un vino (GET /vinos/{cod}), equivalente
// a la consulta S9: cabecera, bodega, stock total, cepas del corte y
// maridajes.
type VinoDetalle struct {
	CodVino    int        `json:"cod_vino"`
	Nombre     string     `json:"nombre"`
	Tipo       string     `json:"tipo"`
	Anada      int        `json:"anada"`
	VolumenMl  int        `json:"volumen_ml"`
	Graduacion float64    `json:"graduacion"`
	Precio     float64    `json:"precio"`
	Bodega     string     `json:"bodega"`
	StockTotal int        `json:"stock_total"`
	Cepas      []Cepa     `json:"cepas"`
	Maridajes  []Maridaje `json:"maridajes"`
}

// Cepa resume una cepa del corte de un vino (S9).
type Cepa struct {
	Nombre     string  `json:"nombre"`
	Porcentaje float64 `json:"porcentaje"`
}

// Maridaje resume un maridaje recomendado (S9).
type Maridaje struct {
	Nombre              string  `json:"nombre"`
	TemperaturaServicio float64 `json:"temperatura_servicio"`
}

// ObtenerVino devuelve la ficha de un vino: cabecera + bodega + stock total,
// cepas del corte y maridajes. Devuelve pgx.ErrNoRows si el vino no existe.
func ObtenerVino(ctx context.Context, pool *pgxpool.Pool, cod int) (*VinoDetalle, error) {
	const cabecera = `
		SELECT v.cod_vino, v.nombre, v.tipo, v.anada, v.volumen_ml,
		       v.graduacion, v.precio, b.razon_social, st.stock_total
		FROM vino v
		JOIN bodega b ON b.cuit = v.cuit_bodega
		JOIN v_stock_total_vino st ON st.cod_vino = v.cod_vino
		WHERE v.cod_vino = $1`

	d := &VinoDetalle{Cepas: []Cepa{}, Maridajes: []Maridaje{}}
	if err := pool.QueryRow(ctx, cabecera, cod).Scan(
		&d.CodVino, &d.Nombre, &d.Tipo, &d.Anada, &d.VolumenMl,
		&d.Graduacion, &d.Precio, &d.Bodega, &d.StockTotal,
	); err != nil {
		return nil, err
	}

	const cepasQuery = `
		SELECT c.nombre, co.porcentaje
		FROM composicion co
		JOIN cepa c ON c.id_cepa = co.id_cepa
		WHERE co.cod_vino = $1
		ORDER BY co.porcentaje DESC, c.nombre`

	rows, err := pool.Query(ctx, cepasQuery, cod)
	if err != nil {
		return nil, err
	}
	for rows.Next() {
		var c Cepa
		if err := rows.Scan(&c.Nombre, &c.Porcentaje); err != nil {
			rows.Close()
			return nil, err
		}
		d.Cepas = append(d.Cepas, c)
	}
	rows.Close()
	if err := rows.Err(); err != nil {
		return nil, err
	}

	const maridajesQuery = `
		SELECT m.nombre, m.temperatura_servicio
		FROM vino_maridaje vm
		JOIN maridaje m ON m.id_maridaje = vm.id_maridaje
		WHERE vm.cod_vino = $1
		ORDER BY m.nombre`

	rows, err = pool.Query(ctx, maridajesQuery, cod)
	if err != nil {
		return nil, err
	}
	for rows.Next() {
		var m Maridaje
		if err := rows.Scan(&m.Nombre, &m.TemperaturaServicio); err != nil {
			rows.Close()
			return nil, err
		}
		d.Maridajes = append(d.Maridajes, m)
	}
	rows.Close()
	if err := rows.Err(); err != nil {
		return nil, err
	}

	return d, nil
}
