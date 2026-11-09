// app.js — estado general del front: navegación entre pantallas y salud de la API.
// No tiene lógica de negocio: cada pantalla pide los datos a `api` (api.js).

document.addEventListener('alpine:init', () => {

  // Pantallas del front. La pantalla activa se guarda en el hash de la URL
  // (#catalogo, #venta, ...), así recargar la página o compartir el link
  // abre la misma pantalla y funcionan los botones atrás/adelante.
  const PANTALLAS = [
    { id: 'catalogo',       titulo: 'Catálogo' },
    { id: 'vino',           titulo: 'Alta / edición de vino' },
    { id: 'venta',          titulo: 'Nueva venta' },
    { id: 'transferencias', titulo: 'Transferencias' },
    { id: 'tablero',        titulo: 'Tablero' },
  ];

  Alpine.data('app', () => ({
    pantallas: PANTALLAS,
    pantalla: 'catalogo',
    salud: 'consultando',   // 'consultando' | 'ok' | mensaje de error

    init() {
      this.leerHash();
      window.addEventListener('hashchange', () => this.leerHash());
      this.consultarSalud();
    },

    leerHash() {
      const id = location.hash.slice(1);
      this.pantalla = PANTALLAS.some(p => p.id === id) ? id : 'catalogo';
    },

    async consultarSalud() {
      try {
        await api.salud();
        this.salud = 'ok';
      } catch (e) {
        this.salud = e.message;
      }
    },
  }));
});
