package httpapi

import (
	"bytes"
	"context"
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"net/url"
	"os"
	"strconv"
	"strings"
	"testing"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
)

// Estos tests son de integración: requieren una base migrada (001–008) y
// cargada con `db/seed/seed.py` (semilla 42). Se conectan con TEST_DATABASE_URL
// o DATABASE_URL; si ninguna está definida, se omiten. Algunos tests mutan
// datos (una venta, una transferencia), así que conviene re-seedar antes de
// correr `go test ./...`.

var testPool *pgxpool.Pool

func TestMain(m *testing.M) {
	dsn := os.Getenv("TEST_DATABASE_URL")
	if dsn == "" {
		dsn = os.Getenv("DATABASE_URL")
	}
	if dsn != "" {
		pool, err := pgxpool.New(context.Background(), dsn)
		if err != nil {
			panic(err)
		}
		testPool = pool
	}
	code := m.Run()
	if testPool != nil {
		testPool.Close()
	}
	os.Exit(code)
}

// nuevoServer levanta el router real con httptest. Si no hay base, omite el test.
func nuevoServer(t *testing.T) *httptest.Server {
	t.Helper()
	if testPool == nil {
		t.Skip("sin TEST_DATABASE_URL/DATABASE_URL: se omiten los tests de integración")
	}
	return httptest.NewServer(NewRouter(testPool))
}

// doJSON hace una petición JSON y devuelve el código y el cuerpo como texto.
func doJSON(t *testing.T, method, endpoint string, body any) (int, string) {
	t.Helper()
	var buf bytes.Buffer
	if body != nil {
		if err := json.NewEncoder(&buf).Encode(body); err != nil {
			t.Fatalf("encode: %v", err)
		}
	}
	req, err := http.NewRequest(method, endpoint, &buf)
	if err != nil {
		t.Fatalf("new request: %v", err)
	}
	req.Header.Set("Content-Type", "application/json")
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatalf("do: %v", err)
	}
	defer resp.Body.Close()
	b, _ := io.ReadAll(resp.Body)
	return resp.StatusCode, string(b)
}

// decodeJSON decodifica el cuerpo en un mapa genérico.
func decodeJSON(t *testing.T, body string) map[string]any {
	t.Helper()
	var m map[string]any
	if err := json.Unmarshal([]byte(body), &m); err != nil {
		t.Fatalf("respuesta no es JSON válido (%v): %s", err, body)
	}
	return m
}

// TestVentaValida: una venta con stock se crea y la base calcula los totales.
func TestVentaValida(t *testing.T) {
	srv := nuevoServer(t)
	defer srv.Close()

	code, body := doJSON(t, http.MethodPost, srv.URL+"/comprobantes", map[string]any{
		"id_cliente": 2,
		"id_sala":    1,
		"renglones":  []map[string]any{{"cod_vino": 1, "cantidad": 1}},
	})
	if code != http.StatusCreated {
		t.Fatalf("esperaba 201, obtuve %d: %s", code, body)
	}
	if decodeJSON(t, body)["nro"] == nil {
		t.Fatalf("esperaba el campo nro en la respuesta: %s", body)
	}
}

// TestVentaSinStock: vender más de lo que hay devuelve 409 (RN-09) y no deja
// datos a medias.
func TestVentaSinStock(t *testing.T) {
	srv := nuevoServer(t)
	defer srv.Close()

	code, body := doJSON(t, http.MethodPost, srv.URL+"/comprobantes", map[string]any{
		"id_cliente": 2,
		"id_sala":    1,
		"renglones":  []map[string]any{{"cod_vino": 1, "cantidad": 999999}},
	})
	if code != http.StatusConflict {
		t.Fatalf("esperaba 409, obtuve %d: %s", code, body)
	}
	if !strings.Contains(body, "stock insuficiente") {
		t.Fatalf("esperaba el mensaje de stock insuficiente: %s", body)
	}
}

// TestPrecioNegativo: un precio no positivo viola el CHECK de RN-01 -> 422.
func TestPrecioNegativo(t *testing.T) {
	srv := nuevoServer(t)
	defer srv.Close()

	code, body := doJSON(t, http.MethodPost, srv.URL+"/vinos", map[string]any{
		"nombre": "Vino Test Precio", "tipo": "tinto", "anada": 2020,
		"volumen_ml": 750, "graduacion": 13, "precio": -1,
		"cuit_bodega": "30700000019",
		"cepas":       []map[string]any{{"id_cepa": 1, "porcentaje": 100}},
		"maridajes":   []int{1},
	})
	if code != http.StatusUnprocessableEntity {
		t.Fatalf("esperaba 422, obtuve %d: %s", code, body)
	}
}

// TestCambioEstadoInvalido: procesar una transferencia todavía en_confeccion
// es un salto de estado inválido (RN-11) -> 409.
func TestCambioEstadoInvalido(t *testing.T) {
	srv := nuevoServer(t)
	defer srv.Close()

	code, body := doJSON(t, http.MethodPost, srv.URL+"/transferencias", map[string]any{"id_sala": 1})
	if code != http.StatusCreated {
		t.Fatalf("crear transferencia: esperaba 201, obtuve %d: %s", code, body)
	}
	nro := decodeJSON(t, body)["nro"].(float64)

	code, body = doJSON(t, http.MethodPost, srv.URL+"/transferencias/"+fstr(nro)+"/procesar", nil)
	if code != http.StatusConflict {
		t.Fatalf("esperaba 409 al procesar en_confeccion, obtuve %d: %s", code, body)
	}
}

// TestVinoInexistente: GET de un vino que no existe -> 404.
func TestVinoInexistente(t *testing.T) {
	srv := nuevoServer(t)
	defer srv.Close()

	code, _ := doJSON(t, http.MethodGet, srv.URL+"/vinos/99999999", nil)
	if code != http.StatusNotFound {
		t.Fatalf("esperaba 404, obtuve %d", code)
	}
}

// TestListarVinosTipo: el filtro por tipo devuelve resultados paginados.
func TestListarVinosTipo(t *testing.T) {
	srv := nuevoServer(t)
	defer srv.Close()

	code, body := doJSON(t, http.MethodGet, srv.URL+"/vinos?tipo=tinto&limit=5", nil)
	if code != http.StatusOK {
		t.Fatalf("esperaba 200, obtuve %d: %s", code, body)
	}
	m := decodeJSON(t, body)
	if m["total"] == nil {
		t.Fatalf("esperaba el campo total: %s", body)
	}
}

// TestInyeccionSQL: un valor malicioso en un filtro se trata como texto (la
// consulta está parametrizada) y no rompe ni ejecuta SQL.
func TestInyeccionSQL(t *testing.T) {
	srv := nuevoServer(t)
	defer srv.Close()

	payload := "'; DROP TABLE vino; --"
	q := url.Values{}
	q.Set("tipo", payload)
	endpoint := srv.URL + "/vinos?" + q.Encode()
	t.Logf("solicitud: GET %s", endpoint)

	code, body := doJSON(t, http.MethodGet, endpoint, nil)
	t.Logf("respuesta: HTTP %d · body %s", code, body)
	if code != http.StatusOK {
		t.Fatalf("esperaba 200 (filtro tratado como texto), obtuve %d: %s", code, body)
	}

	// Por estar parametrizado, el valor se compara como texto y no coincide
	// con ningún tipo de vino: la lista vuelve vacía (total = 0), no un error
	// ni una ejecución del DROP.
	m := decodeJSON(t, body)
	if total, ok := m["total"].(float64); !ok || total != 0 {
		t.Fatalf("el valor malicioso debería tratarse como texto (total=0), obtuve %v", m["total"])
	}

	// La tabla vino sigue existiendo: GET /vinos sin filtro responde 200 y
	// devuelve datos.
	code, body = doJSON(t, http.MethodGet, srv.URL+"/vinos?limit=1", nil)
	if code != http.StatusOK {
		t.Fatalf("tras la inyección la tabla vino debería seguir accesible, obtuve %d: %s", code, body)
	}
	t.Logf("verificación: la tabla vino sigue accesible (HTTP %d)", code)
}

// TestListarClientes: el listado de clientes responde con datos.
func TestListarClientes(t *testing.T) {
	srv := nuevoServer(t)
	defer srv.Close()

	code, body := doJSON(t, http.MethodGet, srv.URL+"/clientes?limit=5", nil)
	if code != http.StatusOK {
		t.Fatalf("esperaba 200, obtuve %d: %s", code, body)
	}
	if decodeJSON(t, body)["total"] == nil {
		t.Fatalf("esperaba el campo total: %s", body)
	}
}

// TestObtenerTransferencia: GET /transferencias/{nro} devuelve el estado real
// y los renglones, y el estado cambia cuando se termina (RN-11). Es lo que usa
// el front para habilitar los botones.
func TestObtenerTransferencia(t *testing.T) {
	srv := nuevoServer(t)
	defer srv.Close()

	code, body := doJSON(t, http.MethodPost, srv.URL+"/transferencias", map[string]any{"id_sala": 1})
	if code != http.StatusCreated {
		t.Fatalf("crear transferencia: esperaba 201, obtuve %d: %s", code, body)
	}
	nro := fstr(decodeJSON(t, body)["nro"].(float64))

	code, body = doJSON(t, http.MethodPost, srv.URL+"/transferencias/"+nro+"/renglones",
		[]map[string]any{{"cod_vino": 1, "cantidad": 2}})
	if code != http.StatusNoContent {
		t.Fatalf("agregar renglón: esperaba 204, obtuve %d: %s", code, body)
	}

	code, body = doJSON(t, http.MethodGet, srv.URL+"/transferencias/"+nro, nil)
	if code != http.StatusOK {
		t.Fatalf("esperaba 200, obtuve %d: %s", code, body)
	}
	m := decodeJSON(t, body)
	if m["estado"] != "en_confeccion" {
		t.Fatalf("esperaba estado en_confeccion, obtuve %v", m["estado"])
	}
	if r, ok := m["renglones"].([]any); !ok || len(r) != 1 {
		t.Fatalf("esperaba 1 renglón, obtuve %v", m["renglones"])
	}

	code, body = doJSON(t, http.MethodPost, srv.URL+"/transferencias/"+nro+"/terminar", nil)
	if code != http.StatusNoContent {
		t.Fatalf("terminar: esperaba 204, obtuve %d: %s", code, body)
	}
	_, body = doJSON(t, http.MethodGet, srv.URL+"/transferencias/"+nro, nil)
	if e := decodeJSON(t, body)["estado"]; e != "terminado" {
		t.Fatalf("tras terminar esperaba estado terminado, obtuve %v", e)
	}
}

// TestTransferenciaInexistente: GET de una transferencia que no existe -> 404.
func TestTransferenciaInexistente(t *testing.T) {
	srv := nuevoServer(t)
	defer srv.Close()

	code, _ := doJSON(t, http.MethodGet, srv.URL+"/transferencias/99999999", nil)
	if code != http.StatusNotFound {
		t.Fatalf("esperaba 404, obtuve %d", code)
	}
}

// TestListarTransferenciasEstadoInvalido: un estado que no existe en el ENUM
// estado_documento lo rechaza la base (22P02) y la API responde 400.
func TestListarTransferenciasEstadoInvalido(t *testing.T) {
	srv := nuevoServer(t)
	defer srv.Close()

	code, body := doJSON(t, http.MethodGet, srv.URL+"/transferencias?estado=anulado", nil)
	if code != http.StatusBadRequest {
		t.Fatalf("esperaba 400, obtuve %d: %s", code, body)
	}

	code, body = doJSON(t, http.MethodGet, srv.URL+"/transferencias?estado=terminado&limit=5", nil)
	if code != http.StatusOK {
		t.Fatalf("con un estado válido esperaba 200, obtuve %d: %s", code, body)
	}
	if decodeJSON(t, body)["total"] == nil {
		t.Fatalf("esperaba el campo total: %s", body)
	}
}

// TestCatalogos: los cuatro listados de catálogo responden 200 con una lista
// no vacía (sobre la base cargada) y cada fila trae el campo id que el front
// envía después en POST /vinos y POST /comprobantes.
func TestCatalogos(t *testing.T) {
	srv := nuevoServer(t)
	defer srv.Close()

	casos := []struct{ ruta, campoID string }{
		{"/salas", "id_sala"},
		{"/cepas", "id_cepa"},
		{"/bodegas", "cuit"},
		{"/maridajes", "id_maridaje"},
	}
	for _, c := range casos {
		code, body := doJSON(t, http.MethodGet, srv.URL+c.ruta, nil)
		if code != http.StatusOK {
			t.Fatalf("%s: esperaba 200, obtuve %d: %s", c.ruta, code, body)
		}
		var filas []map[string]any
		if err := json.Unmarshal([]byte(body), &filas); err != nil {
			t.Fatalf("%s: esperaba una lista JSON (%v): %s", c.ruta, err, body)
		}
		if len(filas) == 0 {
			t.Fatalf("%s: esperaba al menos una fila", c.ruta)
		}
		if filas[0][c.campoID] == nil {
			t.Fatalf("%s: esperaba el campo %s: %v", c.ruta, c.campoID, filas[0])
		}
	}
}

// TestEditarVinoComposicion: PUT /vinos/{cod} reemplaza el corte en una sola
// transacción. Si los porcentajes no suman 100, la base lo rechaza (RN-05,
// 409) y el corte anterior queda intacto; con una suma válida se guarda. Al
// final se borra el vino de prueba (no tiene movimientos, RN-14 lo permite).
func TestEditarVinoComposicion(t *testing.T) {
	srv := nuevoServer(t)
	defer srv.Close()

	nombre := "Vino Test Edición " + strconv.FormatInt(time.Now().UnixNano(), 36)
	vino := map[string]any{
		"nombre": nombre, "tipo": "tinto", "anada": 2022,
		"volumen_ml": 750, "graduacion": 13.5, "precio": 9000,
		"cuit_bodega": "30700000019",
		"cepas":       []map[string]any{{"id_cepa": 1, "porcentaje": 100}},
		"maridajes":   []int{1},
	}
	code, body := doJSON(t, http.MethodPost, srv.URL+"/vinos", vino)
	if code != http.StatusCreated {
		t.Fatalf("alta: esperaba 201, obtuve %d: %s", code, body)
	}
	cod := fstr(decodeJSON(t, body)["cod_vino"].(float64))
	defer doJSON(t, http.MethodDelete, srv.URL+"/vinos/"+cod, nil)

	cantCepas := func() int {
		_, body := doJSON(t, http.MethodGet, srv.URL+"/vinos/"+cod, nil)
		return len(decodeJSON(t, body)["cepas"].([]any))
	}

	// Suma 90 → 409 con el mensaje del trigger, y el corte sigue siendo el original.
	vino["cepas"] = []map[string]any{{"id_cepa": 1, "porcentaje": 60}, {"id_cepa": 2, "porcentaje": 30}}
	code, body = doJSON(t, http.MethodPut, srv.URL+"/vinos/"+cod, vino)
	if code != http.StatusConflict || !strings.Contains(body, "no suma 100") {
		t.Fatalf("suma 90: esperaba 409 «no suma 100», obtuve %d: %s", code, body)
	}
	if n := cantCepas(); n != 1 {
		t.Fatalf("tras el rechazo el corte debía quedar intacto (1 cepa), quedó con %d", n)
	}

	// Suma 100 → 204 y el corte nuevo tiene 2 cepas.
	vino["cepas"] = []map[string]any{{"id_cepa": 1, "porcentaje": 60}, {"id_cepa": 2, "porcentaje": 40}}
	code, body = doJSON(t, http.MethodPut, srv.URL+"/vinos/"+cod, vino)
	if code != http.StatusNoContent {
		t.Fatalf("suma 100: esperaba 204, obtuve %d: %s", code, body)
	}
	if n := cantCepas(); n != 2 {
		t.Fatalf("esperaba 2 cepas tras editar, hay %d", n)
	}
}

// TestBuscarVinoPorNombre: ?nombre= busca parte del nombre sin distinguir
// mayúsculas, se combina con otros filtros, y un comodín de LIKE ("%") se
// busca como texto literal (no devuelve todos los vinos).
func TestBuscarVinoPorNombre(t *testing.T) {
	srv := nuevoServer(t)
	defer srv.Close()

	total := func(query string) float64 {
		t.Helper()
		code, body := doJSON(t, http.MethodGet, srv.URL+"/vinos?"+query, nil)
		if code != http.StatusOK {
			t.Fatalf("%s: esperaba 200, obtuve %d: %s", query, code, body)
		}
		return decodeJSON(t, body)["total"].(float64)
	}

	todos := total("limit=1")
	mayus := total("nombre=RESERVA&limit=1")
	minus := total("nombre=reserva&limit=1")
	if mayus == 0 || mayus != minus || mayus >= todos {
		t.Fatalf("«reserva» debía encontrar algunos vinos (no todos) sin importar mayúsculas: RESERVA=%v reserva=%v todos=%v", mayus, minus, todos)
	}
	if conTipo := total("nombre=reserva&tipo=tinto&limit=1"); conTipo > minus {
		t.Fatalf("combinado con tipo no puede devolver más que solo por nombre: %v > %v", conTipo, minus)
	}
	if comodin := total(url.Values{"nombre": {"%"}}.Encode() + "&limit=1"); comodin != 0 {
		t.Fatalf("«%%» debía buscarse como texto literal (0 vinos), devolvió %v", comodin)
	}
}

// TestSimularVenta: POST /comprobantes/simular devuelve los importes que
// calcula la base (precio copiado, descuento del cliente, total) sin guardar
// nada: el stock de la sala queda igual. Sin stock responde 409 (RN-09), igual
// que una venta real.
func TestSimularVenta(t *testing.T) {
	srv := nuevoServer(t)
	defer srv.Close()

	stockSala := func() float64 {
		t.Helper()
		var n float64
		if err := testPool.QueryRow(context.Background(),
			`SELECT cantidad FROM stock_sala WHERE id_sala = 1 AND cod_vino = 1`).Scan(&n); err != nil {
			t.Fatalf("leer stock: %v", err)
		}
		return n
	}
	antes := stockSala()

	venta := map[string]any{
		"id_cliente": 2, "id_sala": 1,
		"renglones": []map[string]any{{"cod_vino": 1, "cantidad": 1}},
	}
	code, body := doJSON(t, http.MethodPost, srv.URL+"/comprobantes/simular", venta)
	if code != http.StatusOK {
		t.Fatalf("esperaba 200, obtuve %d: %s", code, body)
	}
	m := decodeJSON(t, body)
	renglones := m["renglones"].([]any)
	if len(renglones) != 1 || m["total"].(float64) <= 0 || renglones[0].(map[string]any)["precio_unitario"].(float64) <= 0 {
		t.Fatalf("esperaba 1 renglón con precio y total calculados por la base: %s", body)
	}
	if m["nro"].(float64) != 0 {
		t.Fatalf("una simulación no tiene nro de comprobante: %v", m["nro"])
	}
	if despues := stockSala(); despues != antes {
		t.Fatalf("la simulación no debe descontar stock: antes %v, después %v", antes, despues)
	}

	venta["renglones"] = []map[string]any{{"cod_vino": 1, "cantidad": 999999}}
	code, body = doJSON(t, http.MethodPost, srv.URL+"/comprobantes/simular", venta)
	if code != http.StatusConflict || !strings.Contains(body, "stock insuficiente") {
		t.Fatalf("sin stock: esperaba 409 «stock insuficiente», obtuve %d: %s", code, body)
	}
}

// TestBuscarClientes: ?q= encuentra por ID exacto (primero en la lista), por
// documento con guiones y por nombre; se combina con ?tipo=.
func TestBuscarClientes(t *testing.T) {
	srv := nuevoServer(t)
	defer srv.Close()

	buscar := func(query string) map[string]any {
		t.Helper()
		code, body := doJSON(t, http.MethodGet, srv.URL+"/clientes?"+query, nil)
		if code != http.StatusOK {
			t.Fatalf("%s: esperaba 200, obtuve %d: %s", query, code, body)
		}
		return decodeJSON(t, body)
	}
	primero := func(m map[string]any) map[string]any {
		t.Helper()
		l := m["clientes"].([]any)
		if len(l) == 0 {
			t.Fatalf("esperaba al menos un cliente: %v", m)
		}
		return l[0].(map[string]any)
	}

	porID := primero(buscar("q=2&limit=5"))
	if porID["id_cliente"].(float64) != 2 {
		t.Fatalf("el ID exacto debía aparecer primero, apareció %v", porID["id_cliente"])
	}

	doc := porID["nro_doc"].(string)
	conGuion := doc[:2] + "-" + doc[2:]
	if c := primero(buscar(url.Values{"q": {conGuion}}.Encode())); c["nro_doc"] != doc && !strings.HasPrefix(c["nro_doc"].(string), doc) {
		t.Fatalf("buscar el documento con guion debía encontrar %s, encontró %v", doc, c["nro_doc"])
	}

	nombre := strings.Fields(porID["nombre_razon_social"].(string))[0]
	if buscar(url.Values{"q": {strings.ToUpper(nombre)}}.Encode())["total"].(float64) == 0 {
		t.Fatalf("buscar por nombre «%s» debía encontrar clientes", nombre)
	}

	if m := buscar("q=Exportadora&tipo=socio"); m["total"].(float64) != 0 {
		t.Fatalf("«Exportadora» entre socios no debía encontrar nada, encontró %v", m["total"])
	}
}

// fstr convierte un float64 (de JSON) a entero y luego a string, para armar
// la ruta. Los números de JSON se decodifican como float64.
func fstr(n float64) string {
	return strconv.Itoa(int(n))
}
