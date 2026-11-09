package httpapi

import (
	"net/http"
	"strconv"

	"github.com/JoseM656/atuel-management-bd/internal/db"
	"github.com/JoseM656/atuel-management-bd/internal/httperr"
	"github.com/go-chi/chi/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

// ReportesHandler expone las consultas S1–S12 como endpoints de solo lectura.
type ReportesHandler struct {
	Pool *pgxpool.Pool
}

// Registrar registra todas las rutas de reportes en el router.
func (h *ReportesHandler) Registrar(r chi.Router) {
	r.Get("/reportes/s1", h.S1)
	r.Get("/reportes/s2", h.S2)
	r.Get("/reportes/s3", h.S3)
	r.Get("/reportes/s4", h.S4)
	r.Get("/reportes/s5", h.S5)
	r.Get("/reportes/s6", h.S6)
	r.Get("/reportes/s7", h.S7)
	r.Get("/reportes/s8", h.S8)
	r.Get("/reportes/s9", h.S9)
	r.Get("/reportes/s10", h.S10)
	r.Get("/reportes/s11", h.S11)
	r.Get("/reportes/s12a", h.S12a)
	r.Get("/reportes/s12b", h.S12b)
}

// queryIntObligatorio lee un parámetro de query entero y lo exige.
func queryIntObligatorio(r *http.Request, name string) (int, error) {
	s := r.URL.Query().Get(name)
	if s == "" {
		return 0, strconv.ErrSyntax
	}
	return strconv.Atoi(s)
}

func writeReporte[T any](w http.ResponseWriter, err error, filas []T) {
	if err != nil {
		httperr.Write(w, err)
		return
	}
	writeJSON(w, http.StatusOK, filas)
}

func (h *ReportesHandler) S1(w http.ResponseWriter, r *http.Request) {
	filas, err := db.S1(r.Context(), h.Pool)
	writeReporte(w, err, filas)
}

func (h *ReportesHandler) S2(w http.ResponseWriter, r *http.Request) {
	filas, err := db.S2(r.Context(), h.Pool)
	writeReporte(w, err, filas)
}

func (h *ReportesHandler) S3(w http.ResponseWriter, r *http.Request) {
	sala, err := queryIntObligatorio(r, "sala")
	if err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "parámetro 'sala' inválido"})
		return
	}
	filas, err := db.S3(r.Context(), h.Pool, sala)
	writeReporte(w, err, filas)
}

func (h *ReportesHandler) S4(w http.ResponseWriter, r *http.Request) {
	vino, err := queryIntObligatorio(r, "vino")
	if err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "parámetro 'vino' inválido"})
		return
	}
	filas, err := db.S4(r.Context(), h.Pool, vino)
	writeReporte(w, err, filas)
}

func (h *ReportesHandler) S5(w http.ResponseWriter, r *http.Request) {
	filas, err := db.S5(r.Context(), h.Pool)
	writeReporte(w, err, filas)
}

func (h *ReportesHandler) S6(w http.ResponseWriter, r *http.Request) {
	sala, err := queryIntObligatorio(r, "sala")
	if err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "parámetro 'sala' inválido"})
		return
	}
	filas, err := db.S6(r.Context(), h.Pool, sala)
	writeReporte(w, err, filas)
}

func (h *ReportesHandler) S7(w http.ResponseWriter, r *http.Request) {
	filas, err := db.S7(r.Context(), h.Pool)
	writeReporte(w, err, filas)
}

func (h *ReportesHandler) S8(w http.ResponseWriter, r *http.Request) {
	filas, err := db.S8(r.Context(), h.Pool)
	writeReporte(w, err, filas)
}

func (h *ReportesHandler) S9(w http.ResponseWriter, r *http.Request) {
	vino, err := queryIntObligatorio(r, "vino")
	if err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "parámetro 'vino' inválido"})
		return
	}
	filas, err := db.S9(r.Context(), h.Pool, vino)
	writeReporte(w, err, filas)
}

func (h *ReportesHandler) S10(w http.ResponseWriter, r *http.Request) {
	filas, err := db.S10(r.Context(), h.Pool)
	writeReporte(w, err, filas)
}

func (h *ReportesHandler) S11(w http.ResponseWriter, r *http.Request) {
	filas, err := db.S11(r.Context(), h.Pool)
	writeReporte(w, err, filas)
}

func (h *ReportesHandler) S12a(w http.ResponseWriter, r *http.Request) {
	bodega := r.URL.Query().Get("bodega")
	if bodega == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "parámetro 'bodega' inválido"})
		return
	}
	filas, err := db.S12a(r.Context(), h.Pool, bodega)
	writeReporte(w, err, filas)
}

func (h *ReportesHandler) S12b(w http.ResponseWriter, r *http.Request) {
	filas, err := db.S12b(r.Context(), h.Pool)
	writeReporte(w, err, filas)
}
