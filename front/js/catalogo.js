// catalogo.js — pantalla «Catálogo de vinos» (#52).
//
// Listado paginado con filtros (tipo, cepa, bodega, añada). Todo sale de la API:
//   - GET /vinos           → filtros y paginación los resuelve la base (WHERE + LIMIT/OFFSET).
//   - GET /cepas, /bodegas → opciones de los desplegables (#87).
// El stock total viene de la vista v_stock_total_vino: el front no suma nada.
// «Ver detalle» lleva a la ficha del vino (#vino/{cod}, ver vino.js).

document.addEventListener('alpine:init', () => {

  // Valores del ENUM tipo_vino de la base (001_esquema.sql). Si la base
  // rechazara un valor, el error llega tal cual desde la API.
  const TIPOS = ['tinto', 'blanco', 'rosado', 'espumante'];

  const POR_PAGINA = 8;

  // Umbral solo visual para pintar el stock en naranja. No es una regla de
  // negocio: no bloquea ni cambia nada, solo ayuda a leer la tabla.
  const STOCK_BAJO = 50;

  const filtrosVacios = () => ({ tipo: '', cepa: '', bodega: '', anada: '' });

  const formatoPrecio = new Intl.NumberFormat('es-AR', {
    style: 'currency', currency: 'ARS', minimumFractionDigits: 0, maximumFractionDigits: 2,
  });

  Alpine.data('catalogo', () => ({
    tipos: TIPOS,
    cepas: [],
    bodegas: [],

    filtros: filtrosVacios(),   // lo que el usuario está editando
    aplicados: filtrosVacios(), // lo que se envió a la API (se cambia con «Aplicar»)

    vinos: [],
    total: 0,
    pagina: 1,
    cargando: false,
    error: '',

    async init() {
      // Desplegables y primera página en paralelo.
      await Promise.all([this.cargarOpciones(), this.buscar()]);
    },

    // Al volver al catálogo (p. ej. después de editar o eliminar un vino) se
    // recarga la página actual, manteniendo filtros y número de página.
    alCambiarRuta({ pantalla }) {
      if (pantalla === 'catalogo') this.buscar();
    },

    async cargarOpciones() {
      try {
        const [cepas, bodegas] = await Promise.all([api.listarCepas(), api.listarBodegas()]);
        this.cepas = cepas;
        this.bodegas = bodegas;
      } catch (e) {
        this.error = e.message;
      }
    },

    async buscar() {
      this.cargando = true;
      this.error = '';
      try {
        const r = await api.listarVinos({
          ...this.aplicados,
          limit: POR_PAGINA,
          offset: (this.pagina - 1) * POR_PAGINA,
        });
        this.vinos = r.vinos;
        this.total = r.total;
        // Si se eliminó el último vino de la última página, retroceder una.
        if (this.vinos.length === 0 && this.pagina > 1) {
          this.pagina = this.totalPaginas;
          return this.buscar();
        }
      } catch (e) {
        // Se muestra el mensaje de la API sin reemplazarlo.
        this.error = e.message;
        this.vinos = [];
        this.total = 0;
      } finally {
        this.cargando = false;
      }
    },

    aplicarFiltros() {
      this.aplicados = { ...this.filtros };
      this.pagina = 1;
      this.buscar();
    },

    limpiar() {
      this.filtros = filtrosVacios();
      this.aplicarFiltros();
    },

    // --- Paginación (solo navegación: el total lo cuenta la base) ---
    get totalPaginas() { return Math.max(1, Math.ceil(this.total / POR_PAGINA)); },
    get desde() { return this.total === 0 ? 0 : (this.pagina - 1) * POR_PAGINA + 1; },
    get hasta() { return (this.pagina - 1) * POR_PAGINA + this.vinos.length; },

    irA(pagina) {
      if (pagina < 1 || pagina > this.totalPaginas || this.cargando) return;
      this.pagina = pagina;
      this.buscar();
    },

    // --- Formato (solo presentación) ---
    precio(valor) { return formatoPrecio.format(valor); },

    claseStock(stock) {
      if (stock === 0) return 'stock-cero';
      return stock < STOCK_BAJO ? 'stock-bajo' : 'stock-ok';
    },
  }));
});
