package httpapi

import (
	"encoding/json"
	"net/http"
)

// writeJSON escribe v como JSON con el status indicado. Centraliza la forma
// de las respuestas de la API.
func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(v)
}
