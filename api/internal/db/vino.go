package db

import (
	"context"

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

// ListarVinos devuelve los vinos con su bodega, opcionalmente filtrados por
// tipo. Una función por consulta, siempre parametrizada ($1), nunca se
// concatena texto del usuario en el SQL.
func ListarVinos(ctx context.Context, pool *pgxpool.Pool, tipo string) ([]Vino, error) {
	const query = `
		SELECT v.cod_vino, v.nombre, v.tipo, v.anada, v.volumen_ml,
		       v.graduacion, v.precio, b.razon_social
		FROM vino v
		JOIN bodega b ON b.cuit = v.cuit_bodega
		WHERE ($1 = '' OR v.tipo::text = $1)
		ORDER BY v.cod_vino`

	rows, err := pool.Query(ctx, query, tipo)
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
