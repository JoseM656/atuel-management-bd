package httperr

// Mensajes en castellano para las restricciones de la base que el front puede
// provocar (#88). PostgreSQL no deja ponerle un mensaje propio a un CHECK,
// UNIQUE o FK, así que la API traduce por nombre de restricción.
//
// La regla sigue viviendo solo en la base: acá está únicamente el texto. Si
// alguien renombra o borra una restricción, TestMensajesRestriccionesExisten
// (api_test.go) falla contra pg_constraint y avisa que este archivo quedó
// desactualizado.

// mensajes: violaciones al insertar o actualizar la fila que tiene la
// restricción (CHECK, UNIQUE/PK y FK hacia una fila que no existe).
var mensajes = map[string]string{
	// vino (002_constraints.sql)
	"ck_vino_anada":                "La añada debe estar entre 1990 y 2100.",
	"ck_vino_graduacion":           "La graduación debe estar entre 5 y 20 % vol.", // RN-15
	"ck_vino_precio":               "El precio debe ser mayor que 0.",              // RN-01
	"ck_vino_volumen":              "El volumen debe ser 187, 375, 750, 1500 o 3000 ml.",
	"uq_vino_nombre_anada_volumen": "Ya existe un vino con ese nombre, añada y volumen.",
	"fk_vino_bodega":               "La bodega elegida no existe.",

	// composición y maridajes del vino
	"ck_composicion_porcentaje": "Cada porcentaje del corte debe ser mayor que 0 y hasta 100.",
	"pk_composicion":            "Una cepa no puede repetirse en el corte.",
	"fk_composicion_cepa":       "La cepa elegida no existe.",
	"pk_vino_maridaje":          "Un maridaje no puede repetirse.",
	"fk_vm_maridaje":            "El maridaje elegido no existe.",

	// venta
	"fk_comprobante_cliente": "El cliente elegido no existe.",
	"fk_comprobante_sala":    "La sala elegida no existe.",
	"ck_rc_cantidad":         "La cantidad debe ser mayor que 0.",
	"pk_renglon_comprobante": "Ese vino ya está cargado en la venta.",
	"fk_rc_vino":             "El vino elegido no existe.",

	// transferencia
	"fk_transferencia_sala":    "La sala elegida no existe.",
	"ck_rt_cantidad":           "La cantidad debe ser mayor que 0.",
	"pk_renglon_transferencia": "Ese vino ya está cargado en la transferencia.",
	"fk_rt_vino":               "El vino elegido no existe.",

	// ingreso
	"ck_ri_cantidad":     "La cantidad debe ser mayor que 0.",
	"pk_renglon_ingreso": "Ese vino ya está cargado en el ingreso.",
	"fk_ri_vino":         "El vino elegido no existe.",
}

// mensajeVinoEnUso es el texto de RN-14: un vino con movimientos no se borra.
const mensajeVinoEnUso = "No se puede eliminar el vino porque tiene ventas, stock, transferencias, ingresos o historial de precios."

// mensajesBorrado: violaciones de FK al borrar la fila referenciada (la base
// las informa con el nombre de la FK de la tabla hija). Son el mecanismo de
// RN-14 para vino.
var mensajesBorrado = map[string]string{
	"fk_auditoria_vino": mensajeVinoEnUso,
	"fk_rc_vino":        mensajeVinoEnUso,
	"fk_rt_vino":        mensajeVinoEnUso,
	"fk_ri_vino":        mensajeVinoEnUso,
	"fk_ss_vino":        mensajeVinoEnUso,
	"fk_sd_vino":        mensajeVinoEnUso,
}

// Restricciones devuelve los nombres de todas las restricciones con mensaje
// propio. Lo usa el test que las verifica contra pg_constraint.
func Restricciones() []string {
	vistos := map[string]bool{}
	var nombres []string
	for _, m := range []map[string]string{mensajes, mensajesBorrado} {
		for n := range m {
			if !vistos[n] {
				vistos[n] = true
				nombres = append(nombres, n)
			}
		}
	}
	return nombres
}
