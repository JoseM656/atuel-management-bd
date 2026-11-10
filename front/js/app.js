// app.js — estado general del front: navegación entre pantallas y salud de la API.
// No tiene lógica de negocio: cada pantalla pide los datos a `api` (api.js).
//
// Rutas (en el hash de la URL, así recargar o compartir el link abre la misma
// pantalla y funcionan atrás/adelante):
//   #catalogo            catálogo de vinos (#52)
//   #vino/101            ficha del vino 101 (#53)
//   #vino/101/editar     edición del vino 101 (#53)
//   #vino/nuevo          alta de vino (#53)
//   #venta, #transferencias, #tablero

document.addEventListener('alpine:init', () => {

  // Entradas de la barra lateral. La ficha y el formulario de vino no tienen
  // entrada propia: se llega desde el catálogo.
  const MENU = [
    { id: 'catalogo',       titulo: 'Catálogo de vinos' },
    { id: 'venta',          titulo: 'Nueva venta' },
    { id: 'transferencias', titulo: 'Transferencias' },
    { id: 'tablero',        titulo: 'Tablero' },
  ];
  const PANTALLAS = ['catalogo', 'vino', 'venta', 'transferencias', 'tablero'];

  // Ruta actual, compartida con los componentes de cada pantalla.
  Alpine.store('ruta', { pantalla: 'catalogo', params: [] });

  Alpine.data('app', () => ({
    menu: MENU,
    pantalla: 'catalogo',
    apiBase: api.base,
    salud: 'consultando',   // 'consultando' | 'ok' | mensaje de error

    // La ficha y el formulario de vino «pertenecen» al catálogo en el menú.
    get seccion() { return this.pantalla === 'vino' ? 'catalogo' : this.pantalla; },

    init() {
      this.leerHash();
      window.addEventListener('hashchange', () => this.leerHash());
      this.consultarSalud();
    },

    leerHash() {
      const [id, ...params] = location.hash.slice(1).split('/');
      const pantalla = PANTALLAS.includes(id) ? id : 'catalogo';
      this.pantalla = pantalla;
      Alpine.store('ruta').pantalla = pantalla;
      Alpine.store('ruta').params = params;
      window.scrollTo(0, 0);
      // Aviso a las pantallas para que carguen sus datos (p. ej. la ficha del vino).
      window.dispatchEvent(new CustomEvent('ruta', { detail: { pantalla, params } }));
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
