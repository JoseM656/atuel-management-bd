package db

import (
	"context"
	"fmt"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

// Cliente es la proyección del supertipo + subtipos (vista v_clientes). Los
// campos propios de un subtipo quedan NULL cuando no aplican.
type Cliente struct {
	IDCliente               int     `json:"id_cliente"`
	NombreRazonSocial       string  `json:"nombre_razon_social"`
	TipoDoc                 string  `json:"tipo_doc"`
	NroDoc                  string  `json:"nro_doc"`
	Direccion               string  `json:"direccion"`
	IDLocalidad             int     `json:"id_localidad"`
	Localidad               string  `json:"localidad"`
	Provincia               string  `json:"provincia"`
	FechaAlta               string  `json:"fecha_alta"`
	Tipo                    string  `json:"tipo"`
	Descuento               float64 `json:"descuento"`
	ZonaCobertura           *string `json:"zona_cobertura"`
	NroHabilitacion         *string `json:"nro_habilitacion"`
	PaisDestino             *string `json:"pais_destino"`
	CantPermisosExportacion int     `json:"cant_permisos_exportacion"`
}

// ClienteFiltro reúne el filtro y la paginación de GET /clientes.
type ClienteFiltro struct {
	Tipo   string
	Limit  int
	Offset int
}

// ClienteNuevo es el cuerpo de POST /clientes. El descuento NO va: lo asigna
// la base (trg_cliente_descuento, RN-06/RI-06). Los campos de subtipo van
// según el tipo: distribuidor -> zona_cobertura/nro_habilitacion, exportador
// -> pais_destino (y opcionalmente permisos), socio -> ninguno.
type ClienteNuevo struct {
	NombreRazonSocial string         `json:"nombre_razon_social"`
	TipoDoc           string         `json:"tipo_doc"`
	NroDoc            string         `json:"nro_doc"`
	Direccion         string         `json:"direccion"`
	IDLocalidad       int            `json:"id_localidad"`
	Tipo              string         `json:"tipo"`
	ZonaCobertura     *string        `json:"zona_cobertura"`
	NroHabilitacion   *string        `json:"nro_habilitacion"`
	PaisDestino       *string        `json:"pais_destino"`
	Permisos          []PermisoInput `json:"permisos"`
}

// PermisoInput es un permiso de exportación (POST de un exportador).
type PermisoInput struct {
	Codigo           string `json:"codigo"`
	FechaEmision     string `json:"fecha_emision"`
	FechaVencimiento string `json:"fecha_vencimiento"`
}

// ClienteActualizar es el cuerpo de PUT /clientes/{id}. El tipo no se cambia
// por esta vía (define el subtipo); se actualizan los campos comunes y los
// propios del subtipo actual.
type ClienteActualizar struct {
	NombreRazonSocial string  `json:"nombre_razon_social"`
	TipoDoc           string  `json:"tipo_doc"`
	NroDoc            string  `json:"nro_doc"`
	Direccion         string  `json:"direccion"`
	IDLocalidad       int     `json:"id_localidad"`
	ZonaCobertura     *string `json:"zona_cobertura"`
	NroHabilitacion   *string `json:"nro_habilitacion"`
	PaisDestino       *string `json:"pais_destino"`
}

const clienteSelect = `
	SELECT id_cliente, nombre_razon_social, tipo_doc, nro_doc, direccion,
	       id_localidad, localidad, provincia,
	       fecha_alta::text, tipo::text, descuento,
	       zona_cobertura, nro_habilitacion, pais_destino,
	       cant_permisos_exportacion
	FROM v_clientes`

// rowScanner es lo común a pgx.Row y pgx.Rows: un método Scan.
type rowScanner interface {
	Scan(dest ...any) error
}

func scanCliente(s rowScanner) (Cliente, error) {
	var c Cliente
	err := s.Scan(
		&c.IDCliente, &c.NombreRazonSocial, &c.TipoDoc, &c.NroDoc, &c.Direccion,
		&c.IDLocalidad, &c.Localidad, &c.Provincia,
		&c.FechaAlta, &c.Tipo, &c.Descuento,
		&c.ZonaCobertura, &c.NroHabilitacion, &c.PaisDestino, &c.CantPermisosExportacion,
	)
	return c, err
}

// ListarClientes devuelve los clientes (con su subtipo), filtrados por tipo y
// paginados.
func ListarClientes(ctx context.Context, pool *pgxpool.Pool, f ClienteFiltro) ([]Cliente, error) {
	query := clienteSelect + ` WHERE ($1 = '' OR tipo::text = $1) ORDER BY id_cliente LIMIT $2 OFFSET $3`
	rows, err := pool.Query(ctx, query, f.Tipo, f.Limit, f.Offset)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	clientes := make([]Cliente, 0)
	for rows.Next() {
		c, err := scanCliente(rows)
		if err != nil {
			return nil, err
		}
		clientes = append(clientes, c)
	}
	return clientes, rows.Err()
}

// ContarClientes cuenta cuántos clientes cumplen el filtro (sin paginar).
func ContarClientes(ctx context.Context, pool *pgxpool.Pool, f ClienteFiltro) (int, error) {
	var total int
	err := pool.QueryRow(ctx, `SELECT count(*) FROM v_clientes WHERE ($1 = '' OR tipo::text = $1)`, f.Tipo).Scan(&total)
	return total, err
}

// ObtenerCliente devuelve un cliente con su subtipo. pgx.ErrNoRows si no existe.
func ObtenerCliente(ctx context.Context, pool *pgxpool.Pool, id int) (*Cliente, error) {
	c, err := scanCliente(pool.QueryRow(ctx, clienteSelect+` WHERE id_cliente = $1`, id))
	if err != nil {
		return nil, err
	}
	return &c, nil
}

// CrearCliente inserta el cliente y su subtipo (y permisos si es exportador)
// en una sola transacción. El descuento lo asigna el trigger. El constraint
// trigger de totalidad (trg_cliente_subtipo) se evalúa en el COMMIT.
func CrearCliente(ctx context.Context, pool *pgxpool.Pool, c ClienteNuevo) (int, error) {
	tx, err := pool.Begin(ctx)
	if err != nil {
		return 0, err
	}
	defer tx.Rollback(ctx)

	var id int
	if err := tx.QueryRow(ctx, `
		INSERT INTO cliente (nombre_razon_social, tipo_doc, nro_doc, direccion, id_localidad, tipo)
		VALUES ($1, $2, $3, $4, $5, $6)
		RETURNING id_cliente`,
		c.NombreRazonSocial, c.TipoDoc, c.NroDoc, c.Direccion, c.IDLocalidad, c.Tipo,
	).Scan(&id); err != nil {
		return 0, err
	}

	switch c.Tipo {
	case "socio":
		_, err = tx.Exec(ctx, `INSERT INTO socio (id_cliente) VALUES ($1)`, id)
	case "distribuidor":
		_, err = tx.Exec(ctx,
			`INSERT INTO distribuidor (id_cliente, zona_cobertura, nro_habilitacion) VALUES ($1, $2, $3)`,
			id, c.ZonaCobertura, c.NroHabilitacion)
	case "exportador":
		if _, err = tx.Exec(ctx,
			`INSERT INTO exportador (id_cliente, pais_destino) VALUES ($1, $2)`, id, c.PaisDestino); err != nil {
			return 0, err
		}
		for _, p := range c.Permisos {
			if _, err = tx.Exec(ctx, `
				INSERT INTO permiso_exportacion (codigo, id_cliente, fecha_emision, fecha_vencimiento)
				VALUES ($1, $2, $3, $4)`, p.Codigo, id, p.FechaEmision, p.FechaVencimiento); err != nil {
				return 0, err
			}
		}
	default:
		return 0, fmt.Errorf("tipo de cliente inválido: %s", c.Tipo)
	}
	if err != nil {
		return 0, err
	}

	if err := tx.Commit(ctx); err != nil {
		return 0, err
	}
	return id, nil
}

// ActualizarCliente reemplaza los campos comunes y los del subtipo actual.
// El tipo no se cambia. pgx.ErrNoRows si no existe.
func ActualizarCliente(ctx context.Context, pool *pgxpool.Pool, id int, c ClienteActualizar) error {
	tx, err := pool.Begin(ctx)
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx)

	tag, err := tx.Exec(ctx, `
		UPDATE cliente
		SET nombre_razon_social = $1, tipo_doc = $2, nro_doc = $3, direccion = $4, id_localidad = $5
		WHERE id_cliente = $6`,
		c.NombreRazonSocial, c.TipoDoc, c.NroDoc, c.Direccion, c.IDLocalidad, id)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return pgx.ErrNoRows
	}

	var tipo string
	if err := tx.QueryRow(ctx, `SELECT tipo::text FROM cliente WHERE id_cliente = $1`, id).Scan(&tipo); err != nil {
		return err
	}

	switch tipo {
	case "distribuidor":
		_, err = tx.Exec(ctx,
			`UPDATE distribuidor SET zona_cobertura = $1, nro_habilitacion = $2 WHERE id_cliente = $3`,
			c.ZonaCobertura, c.NroHabilitacion, id)
	case "exportador":
		_, err = tx.Exec(ctx,
			`UPDATE exportador SET pais_destino = $1 WHERE id_cliente = $2`, c.PaisDestino, id)
	}
	if err != nil {
		return err
	}

	return tx.Commit(ctx)
}

// BorrarCliente elimina un cliente. La FK comprobante -> cliente (RESTRICT)
// lo rechaza si tiene comprobantes (RN-14). El subtipo y los permisos se
// borran por CASCADE. pgx.ErrNoRows si no existe.
func BorrarCliente(ctx context.Context, pool *pgxpool.Pool, id int) error {
	tag, err := pool.Exec(ctx, `DELETE FROM cliente WHERE id_cliente = $1`, id)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return pgx.ErrNoRows
	}
	return nil
}
