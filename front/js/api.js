// api.js — única capa del front que habla con la API.
//
// Reglas de esta capa (SPEC.md §7 y rúbrica «Front»):
//   - Las pantallas NO llaman a fetch directamente: usan las funciones de `api`.
//   - No se calcula nada acá: totales, descuentos y stock los devuelve la API,
//     que a su vez los obtiene de la base (triggers y funciones).
//   - Los errores se muestran TAL CUAL los manda la API (p. ej. el RAISE
//     EXCEPTION de RN-05 o RN-09), sin reemplazarlos por mensajes genéricos.

// URL base configurable. Por defecto "/api", que nginx reenvía a la API
// (ver front/nginx.conf). Para apuntar a otra API sin tocar el código, se puede
// definir window.API_BASE antes de cargar este archivo.
const API_BASE = window.API_BASE || '/api';

// ApiError transporta el código HTTP y el mensaje exacto de la API.
//   status 409 → regla de negocio (P0001) o UNIQUE/FK
//   status 422 → CHECK / NOT NULL
//   status 400 → formato inválido
//   status 503 → serialización/deadlock (reintentar) o base no accesible
//   status 0   → no hubo respuesta (API caída o sin red)
//
// Si el error viene de la base, también trae `codigo` (SQLSTATE) y
// `restriccion` (nombre del CHECK/UNIQUE/FK), que el front muestra debajo del
// mensaje para que se vea que la regla la aplicó la base (#88). El mensaje en
// castellano lo arma la API; el front no traduce nada.
class ApiError extends Error {
  constructor(status, mensaje, codigo = '', restriccion = '') {
    super(mensaje);
    this.name = 'ApiError';
    this.status = status;
    this.codigo = codigo;
    this.restriccion = restriccion;
  }
}

// detalleError devuelve «SQLSTATE · restricción» de un error de la API, o ''
// si no lo tiene (por ejemplo, si la API no respondió).
function detalleError(e) {
  return e && e.codigo ? [e.codigo, e.restriccion].filter(Boolean).join(' · ') : '';
}

// request hace el pedido y devuelve el JSON de la respuesta (o null si es 204).
// Si la respuesta no es 2xx, lanza ApiError con el mensaje de la API.
async function request(metodo, ruta, { query, body } = {}) {
  let url = API_BASE + ruta;

  if (query) {
    // Solo se envían los filtros con valor: "" y null quedan afuera.
    const params = new URLSearchParams();
    for (const [k, v] of Object.entries(query)) {
      if (v !== undefined && v !== null && v !== '') params.append(k, v);
    }
    const qs = params.toString();
    if (qs) url += '?' + qs;
  }

  const opciones = { method: metodo, headers: { Accept: 'application/json' } };
  if (body !== undefined) {
    opciones.headers['Content-Type'] = 'application/json';
    opciones.body = JSON.stringify(body);
  }

  let resp;
  try {
    resp = await fetch(url, opciones);
  } catch {
    throw new ApiError(0, 'No se pudo conectar con la API.');
  }

  if (resp.status === 204) return null;

  // La API responde JSON ({"error": "..."} en los errores), pero algunas
  // rutas (p. ej. /salud con 503) devuelven texto plano: se leen ambos casos.
  const texto = await resp.text();
  let datos = null;
  try { datos = texto ? JSON.parse(texto) : null; } catch { datos = null; }

  if (!resp.ok) {
    const mensaje = (datos && datos.error) || texto.trim() || resp.statusText;
    throw new ApiError(resp.status, mensaje, datos && datos.codigo, datos && datos.restriccion);
  }
  return datos;
}

// Una función por ruta de la API (api/internal/httpapi/router.go).
const api = {
  base: API_BASE, // se muestra en el pie de la barra lateral

  salud: () => request('GET', '/salud'),

  // Catálogos para los desplegables (#87): listas completas, ordenadas por nombre.
  listarSalas:     () => request('GET', '/salas'),      // [{ id_sala, descripcion, direccion, localidad, provincia, codigo_postal, dia_cierre }]
  listarCepas:     () => request('GET', '/cepas'),      // [{ id_cepa, nombre, tipo }]
  listarBodegas:   () => request('GET', '/bodegas'),    // [{ cuit, razon_social }]
  listarMaridajes: () => request('GET', '/maridajes'),  // [{ id_maridaje, nombre, temperatura_servicio }]

  // Vinos — catálogo (#52) y alta/edición (#53)
  // filtros: { nombre, tipo, cepa, bodega, anada, limit, offset } → { total, limit, offset, vinos }
  listarVinos:   (filtros)     => request('GET', '/vinos', { query: filtros }),
  obtenerVino:   (cod)         => request('GET', `/vinos/${encodeURIComponent(cod)}`),
  crearVino:     (vino)        => request('POST', '/vinos', { body: vino }),         // → { cod_vino }
  actualizarVino:(cod, vino)   => request('PUT', `/vinos/${encodeURIComponent(cod)}`, { body: vino }),
  borrarVino:    (cod)         => request('DELETE', `/vinos/${encodeURIComponent(cod)}`),

  // Clientes — para elegir cliente en la venta (#54)
  // filtros: { q, tipo, limit, offset } → { total, limit, offset, clientes }
  listarClientes:(filtros)     => request('GET', '/clientes', { query: filtros }),
  obtenerCliente:(id)          => request('GET', `/clientes/${encodeURIComponent(id)}`),

  // Venta (#54): cabecera + renglones en un solo POST. La base calcula precios,
  // descuento y total; si falta stock (RN-09) responde 409 y no guarda nada.
  // venta: { id_cliente, id_sala, renglones: [{ cod_vino, cantidad }] } → { nro }
  crearComprobante: (venta)    => request('POST', '/comprobantes', { body: venta }),
  // Mismo cuerpo, pero la base hace ROLLBACK: devuelve los importes sin guardar nada.
  simularComprobante: (venta)  => request('POST', '/comprobantes/simular', { body: venta }),
  obtenerComprobante: (nro)    => request('GET', `/comprobantes/${encodeURIComponent(nro)}`),

  // Transferencias (#55): en_confeccion → terminado → procesado
  // filtros: { estado, id_sala, limit, offset } → { total, limit, offset, transferencias }
  listarTransferencias: (filtros) => request('GET', '/transferencias', { query: filtros }),
  // → { nro, id_sala, sala, localidad, fecha_confeccion, estado,
  //     renglones: [{ cod_vino, vino, anada, volumen_ml, cantidad, stock_deposito }] }
  obtenerTransferencia: (nro)     => request('GET', `/transferencias/${encodeURIComponent(nro)}`),
  crearTransferencia:   (idSala)        => request('POST', '/transferencias', { body: { id_sala: idSala } }), // → { nro }
  agregarRenglonesTransferencia: (nro, renglones) =>
    request('POST', `/transferencias/${encodeURIComponent(nro)}/renglones`, { body: renglones }),
  quitarRenglonTransferencia: (nro, cod) =>
    request('DELETE', `/transferencias/${encodeURIComponent(nro)}/renglones/${encodeURIComponent(cod)}`),
  terminarTransferencia: (nro)  => request('POST', `/transferencias/${encodeURIComponent(nro)}/terminar`),
  procesarTransferencia: (nro)  => request('POST', `/transferencias/${encodeURIComponent(nro)}/procesar`),

  // Reportes — tablero (#56). Rutas del enunciado; misma lógica que S1, S8 y S6.
  // → [{ cod_vino, nombre, anada, volumen_ml, botellas }]
  topVinos:       ()            => request('GET', '/reportes/top-vinos'),
  // → { desde, hasta, salas: [{ id_sala, localidad, monto_total }] }
  ventasPorSala:  ()            => request('GET', '/reportes/ventas-por-sala'),
  // → { desde, hasta, transportista: { cod_transportista, razon_social, cuit, ingresos_trasladados } | null }
  transportistaActivo: ()       => request('GET', '/reportes/transportista-activo'),
  // → [{ cod_vino, nombre, anada, volumen_ml, tipo, bodega, stock_sala, stock_deposito }]
  vinosSinStock:  (idSala)      => request('GET', '/reportes/vinos-sin-stock', { query: { sala: idSala } }),
};

window.api = api;
window.ApiError = ApiError;
window.detalleError = detalleError;
