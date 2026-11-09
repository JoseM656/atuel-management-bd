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

// fstr convierte un float64 (de JSON) a entero y luego a string, para armar
// la ruta. Los números de JSON se decodifican como float64.
func fstr(n float64) string {
	return strconv.Itoa(int(n))
}
