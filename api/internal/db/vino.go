package db

import (
	"context"
	"fmt"
	"strings"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

// Vino es la proyección de vino + bodega que devuelve GET /vinos. stock_total
// (depósito + salas) sale de la vista v_stock_total_vino, la misma que usa la
// ficha: el front lo muestra tal cual, no lo suma. cepas es el corte como
// texto, de mayor a menor porcentaje ("Merlot, Syrah, Bonarda"); el detalle
// con porcentajes está en GET /vinos/{cod}.
type Vino struct {
	CodVino    int     `json:"cod_vino"`
	Nombre     string  `json:"nombre"`
	Tipo       string  `json:"tipo"`
	Anada      int     `json:"anada"`
	VolumenMl  int     `json:"volumen_ml"`
	Graduacion float64 `json:"graduacion"`
	Precio     float64 `json:"precio"`
	Bodega     string  `json:"bodega"`
	Cepas      string  `json:"cepas"`
	StockTotal int     `json:"stock_total"`
}

// VinoFiltro reúne los filtros opcionales y la paginación de GET /vinos.
// Un string vacío o un 0 no filtran.
type VinoFiltro struct {
	Nombre string // búsqueda parcial, sin distinguir mayúsculas
	Tipo   string
	Cepa   string
	Bodega string
	Anada  int
	Limit  int
	Offset int
}

const vinoSelect = `
	SELECT v.cod_vino, v.nombre, v.tipo, v.anada, v.volumen_ml,
	       v.graduacion, v.precio, b.razon_social,
	       COALESCE((SELECT string_agg(c.nombre, ', ' ORDER BY co.porcentaje DESC, c.nombre)
	                 FROM composicion co
	                 JOIN cepa c ON c.id_cepa = co.id_cepa
	                 WHERE co.cod_vino = v.cod_vino), '') AS cepas,
	       st.stock_total
	FROM vino v
	JOIN bodega b ON b.cuit = v.cuit_bodega
	JOIN v_stock_total_vino st ON st.cod_vino = v.cod_vino`

// buildVinoWhere arma la cláusula WHERE (y sus argumentos) según los filtros.
// Solo el valor viaja como parámetro ($n); el texto del usuario nunca se
// concatena en el SQL.
func buildVinoWhere(f VinoFiltro) (string, []any) {
	var conds []string
	var args []any

	if f.Nombre != "" {
		// Búsqueda parcial sin distinguir mayúsculas: «reserva» encuentra
		// «Malbec Reserva B1». Los comodines de LIKE (% _ \) que escriba el
		// usuario se escapan para que se busquen como texto literal.
		args = append(args, likeEscape(f.Nombre))
		conds = append(conds, fmt.Sprintf("v.nombre ILIKE '%%' || $%d || '%%'", len(args)))
	}
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

// likeEscape escapa los comodines de LIKE para buscar el texto tal cual.
// PostgreSQL usa \ como carácter de escape por defecto en LIKE/ILIKE.
func likeEscape(s string) string {
	return strings.NewReplacer(`\`, `\\`, `%`, `\%`, `_`, `\_`).Replace(s)
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
		if err := rows.Scan(&v.CodVino, &v.Nombre, &v.Tipo, &v.Anada, &v.VolumenMl, &v.Graduacion, &v.Precio, &v.Bodega, &v.Cepas, &v.StockTotal); err != nil {
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
// a la consulta S9: cabecera, bodega, stock (depósito, salas y total, de la
// vista v_stock_total_vino), cepas del corte y maridajes. Los ids (cuit_bodega,
// id_cepa, id_maridaje) los usa el formulario de edición del front.
type VinoDetalle struct {
	CodVino       int        `json:"cod_vino"`
	Nombre        string     `json:"nombre"`
	Tipo          string     `json:"tipo"`
	Anada         int        `json:"anada"`
	VolumenMl     int        `json:"volumen_ml"`
	Graduacion    float64    `json:"graduacion"`
	Precio        float64    `json:"precio"`
	CuitBodega    string     `json:"cuit_bodega"`
	Bodega        string     `json:"bodega"`
	StockDeposito int        `json:"stock_deposito"`
	StockSalas    int        `json:"stock_salas"`
	StockTotal    int        `json:"stock_total"`
	Cepas         []Cepa     `json:"cepas"`
	Maridajes     []Maridaje `json:"maridajes"`
}

// Cepa resume una cepa del corte de un vino (S9).
type Cepa struct {
	IDCepa     int     `json:"id_cepa"`
	Nombre     string  `json:"nombre"`
	Porcentaje float64 `json:"porcentaje"`
}

// Maridaje resume un maridaje recomendado (S9).
type Maridaje struct {
	IDMaridaje          int     `json:"id_maridaje"`
	Nombre              string  `json:"nombre"`
	TemperaturaServicio float64 `json:"temperatura_servicio"`
}

// ObtenerVino devuelve la ficha de un vino: cabecera + bodega + stock total,
// cepas del corte y maridajes. Devuelve pgx.ErrNoRows si el vino no existe.
func ObtenerVino(ctx context.Context, pool *pgxpool.Pool, cod int) (*VinoDetalle, error) {
	const cabecera = `
		SELECT v.cod_vino, v.nombre, v.tipo, v.anada, v.volumen_ml,
		       v.graduacion, v.precio, v.cuit_bodega::text, b.razon_social,
		       st.stock_deposito, st.stock_salas, st.stock_total
		FROM vino v
		JOIN bodega b ON b.cuit = v.cuit_bodega
		JOIN v_stock_total_vino st ON st.cod_vino = v.cod_vino
		WHERE v.cod_vino = $1`

	d := &VinoDetalle{Cepas: []Cepa{}, Maridajes: []Maridaje{}}
	if err := pool.QueryRow(ctx, cabecera, cod).Scan(
		&d.CodVino, &d.Nombre, &d.Tipo, &d.Anada, &d.VolumenMl,
		&d.Graduacion, &d.Precio, &d.CuitBodega, &d.Bodega,
		&d.StockDeposito, &d.StockSalas, &d.StockTotal,
	); err != nil {
		return nil, err
	}

	const cepasQuery = `
		SELECT c.id_cepa, c.nombre, co.porcentaje
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
		if err := rows.Scan(&c.IDCepa, &c.Nombre, &c.Porcentaje); err != nil {
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
		SELECT m.id_maridaje, m.nombre, m.temperatura_servicio
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
		if err := rows.Scan(&m.IDMaridaje, &m.Nombre, &m.TemperaturaServicio); err != nil {
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

// VinoNuevo es el cuerpo de POST /vinos: el vino más su composición de cepas
// (la suma de porcentajes debe ser 100, RN-05) y sus maridajes (al menos uno,
// RI-02).
type VinoNuevo struct {
	Nombre     string      `json:"nombre"`
	Tipo       string      `json:"tipo"`
	Anada      int         `json:"anada"`
	VolumenMl  int         `json:"volumen_ml"`
	Graduacion float64     `json:"graduacion"`
	Precio     float64     `json:"precio"`
	CuitBodega string      `json:"cuit_bodega"`
	Cepas      []CepaInput `json:"cepas"`
	Maridajes  []int       `json:"maridajes"`
}

// CepaInput es una cepa del corte con su porcentaje (POST /vinos).
type CepaInput struct {
	IDCepa     int     `json:"id_cepa"`
	Porcentaje float64 `json:"porcentaje"`
}

// VinoActualizar es el cuerpo de PUT /vinos/{cod}. Cepas y Maridajes son
// opcionales: si el campo no viene en el JSON (nil) no se tocan; si viene, se
// reemplazan completos. Una lista vacía también reemplaza, y la base la
// rechaza (RN-05 / maridaje obligatorio).
type VinoActualizar struct {
	Nombre     string      `json:"nombre"`
	Tipo       string      `json:"tipo"`
	Anada      int         `json:"anada"`
	VolumenMl  int         `json:"volumen_ml"`
	Graduacion float64     `json:"graduacion"`
	Precio     float64     `json:"precio"`
	CuitBodega string      `json:"cuit_bodega"`
	Cepas      []CepaInput `json:"cepas"`
	Maridajes  []int       `json:"maridajes"`
}

// CrearVino inserta un vino con su composición y maridajes, en una sola
// transacción. Devuelve el código generado. Los triggers diferidos (RN-05
// suma=100 y RI-02 ≥1 maridaje) se evalúan en el COMMIT.
func CrearVino(ctx context.Context, pool *pgxpool.Pool, v VinoNuevo) (int, error) {
	tx, err := pool.Begin(ctx)
	if err != nil {
		return 0, err
	}
	defer tx.Rollback(ctx)

	var cod int
	if err := tx.QueryRow(ctx, `
		INSERT INTO vino (nombre, tipo, anada, volumen_ml, graduacion, precio, cuit_bodega)
		VALUES ($1, $2, $3, $4, $5, $6, $7)
		RETURNING cod_vino`,
		v.Nombre, v.Tipo, v.Anada, v.VolumenMl, v.Graduacion, v.Precio, v.CuitBodega,
	).Scan(&cod); err != nil {
		return 0, err
	}

	for _, c := range v.Cepas {
		if _, err := tx.Exec(ctx, `
			INSERT INTO composicion (cod_vino, id_cepa, porcentaje)
			VALUES ($1, $2, $3)`, cod, c.IDCepa, c.Porcentaje); err != nil {
			return 0, err
		}
	}

	for _, id := range v.Maridajes {
		if _, err := tx.Exec(ctx, `
			INSERT INTO vino_maridaje (cod_vino, id_maridaje)
			VALUES ($1, $2)`, cod, id); err != nil {
			return 0, err
		}
	}

	if err := tx.Commit(ctx); err != nil {
		return 0, err
	}
	return cod, nil
}

// ActualizarVino reemplaza los campos del vino y, si vienen, su composición y
// sus maridajes, todo en una sola transacción. Si cambia el precio, el trigger
// RN-13 lo audita. Los triggers de RN-05 (suma = 100) y del maridaje
// obligatorio son diferidos: se evalúan en el COMMIT, por eso se puede borrar
// y volver a insertar el corte sin que falle a mitad de camino. Si la regla no
// se cumple, el COMMIT falla y no queda ningún cambio a medias.
// Devuelve pgx.ErrNoRows si el vino no existe.
func ActualizarVino(ctx context.Context, pool *pgxpool.Pool, cod int, v VinoActualizar) error {
	tx, err := pool.Begin(ctx)
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx)

	tag, err := tx.Exec(ctx, `
		UPDATE vino
		SET nombre = $1, tipo = $2, anada = $3, volumen_ml = $4,
		    graduacion = $5, precio = $6, cuit_bodega = $7
		WHERE cod_vino = $8`,
		v.Nombre, v.Tipo, v.Anada, v.VolumenMl, v.Graduacion, v.Precio, v.CuitBodega, cod)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return pgx.ErrNoRows
	}

	if v.Cepas != nil {
		if _, err := tx.Exec(ctx, `DELETE FROM composicion WHERE cod_vino = $1`, cod); err != nil {
			return err
		}
		for _, c := range v.Cepas {
			if _, err := tx.Exec(ctx, `
				INSERT INTO composicion (cod_vino, id_cepa, porcentaje)
				VALUES ($1, $2, $3)`, cod, c.IDCepa, c.Porcentaje); err != nil {
				return err
			}
		}
	}

	if v.Maridajes != nil {
		if _, err := tx.Exec(ctx, `DELETE FROM vino_maridaje WHERE cod_vino = $1`, cod); err != nil {
			return err
		}
		for _, id := range v.Maridajes {
			if _, err := tx.Exec(ctx, `
				INSERT INTO vino_maridaje (cod_vino, id_maridaje)
				VALUES ($1, $2)`, cod, id); err != nil {
				return err
			}
		}
	}

	return tx.Commit(ctx)
}

// BorrarVino elimina un vino. Las FK ON DELETE RESTRICT (RN-14) lo rechazan
// si el vino tiene movimientos (renglones, stock o auditoría): devuelve
// 23503 (foreign_key_violation). Devuelve pgx.ErrNoRows si no existe.
func BorrarVino(ctx context.Context, pool *pgxpool.Pool, cod int) error {
	tag, err := pool.Exec(ctx, `DELETE FROM vino WHERE cod_vino = $1`, cod)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return pgx.ErrNoRows
	}
	return nil
}
