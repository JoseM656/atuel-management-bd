// tablero.js — Tablero de reportes (#56).
//
//   Top 10 vinos más vendidos           GET /reportes/top-vinos        (S1)
//   Ventas por sala, último trimestre   GET /reportes/ventas-por-sala  (S8)
//   Transportista más activo, último mes GET /reportes/transportista-activo (S7)
//   Vinos sin stock en una sala         GET /reportes/vinos-sin-stock?sala= (S6)
//
// Los reportes son de solo lectura y vienen calculados por la base. El front
// solo los dibuja: el largo de cada barra es el monto de la sala dividido por
// el mayor monto (escala del gráfico, no un dato de negocio).

document.addEventListener('alpine:init', () => {

  const SALAS_RESUMEN = 10;   // barras visibles antes de «Ver todas»
  const POR_PAGINA = 10;      // filas de la tabla de S6

  const formatoNumero = new Intl.NumberFormat('es-AR');
  const formatoMillones = new Intl.NumberFormat('es-AR', { minimumFractionDigits: 1, maximumFractionDigits: 2 });
  const formatoPrecio = new Intl.NumberFormat('es-AR', {
    style: 'currency', currency: 'ARS', minimumFractionDigits: 0, maximumFractionDigits: 0,
  });

  Alpine.data('tablero', () => ({
    // Top vinos
    top: [],
    cargandoTop: false,
    errorTop: '',

    // Ventas por sala
    ventas: { desde: '', hasta: '', salas: [] },
    cargandoVentas: false,
    errorVentas: '',
    todasLasSalas: false,

    // Transportista más activo
    activo: { desde: '', hasta: '', transportista: null },
    cargandoActivo: false,
    errorActivo: '',

    // Vinos sin stock
    salas: [],
    salaElegida: '',
    sinStock: [],
    cargandoSinStock: false,
    errorSinStock: '',
    pagina: 1,

    cargado: false,

    init() {
      this.alCambiarRuta(Alpine.store('ruta'));
    },

    // Se carga al entrar al tablero (y se refresca cada vez que se vuelve),
    // así una venta o transferencia recién hecha ya aparece.
    alCambiarRuta({ pantalla }) {
      if (pantalla !== 'tablero') return;
      this.cargarTop();
      this.cargarVentas();
      this.cargarActivo();
      if (this.cargado) {
        if (this.salaElegida) this.cargarSinStock();
        return;
      }
      this.cargado = true;
      api.listarSalas()
        .then(s => {
          this.salas = [...s].sort((a, b) => a.id_sala - b.id_sala);
          if (this.salas.length) {
            this.salaElegida = String(this.salas[0].id_sala);
            this.cargarSinStock();
          }
        })
        .catch(e => { this.errorSinStock = e.message; });
    },

    async cargarTop() {
      this.cargandoTop = true;
      this.errorTop = '';
      try { this.top = await api.topVinos(); }
      catch (e) { this.errorTop = e.message; this.top = []; }
      finally { this.cargandoTop = false; }
    },

    async cargarVentas() {
      this.cargandoVentas = true;
      this.errorVentas = '';
      try { this.ventas = await api.ventasPorSala(); }
      catch (e) { this.errorVentas = e.message; this.ventas = { desde: '', hasta: '', salas: [] }; }
      finally { this.cargandoVentas = false; }
    },

    async cargarActivo() {
      this.cargandoActivo = true;
      this.errorActivo = '';
      try { this.activo = await api.transportistaActivo(); }
      catch (e) { this.errorActivo = e.message; this.activo = { desde: '', hasta: '', transportista: null }; }
      finally { this.cargandoActivo = false; }
    },

    async cargarSinStock() {
      this.cargandoSinStock = true;
      this.errorSinStock = '';
      this.pagina = 1;
      try { this.sinStock = await api.vinosSinStock(this.salaElegida); }
      catch (e) { this.errorSinStock = e.message; this.sinStock = []; }
      finally { this.cargandoSinStock = false; }
    },

    // ---- Gráfico de ventas por sala ----
    get salasVisibles() {
      return this.todasLasSalas ? this.ventas.salas : this.ventas.salas.slice(0, SALAS_RESUMEN);
    },
    get montoMaximo() {
      return this.ventas.salas.length ? this.ventas.salas[0].monto_total : 0; // ya viene ordenado desc
    },
    anchoBarra(monto) {
      return this.montoMaximo ? `${(monto / this.montoMaximo) * 100}%` : '0%';
    },

    // ---- Tabla de vinos sin stock (paginada en pantalla) ----
    get totalPaginas() { return Math.max(1, Math.ceil(this.sinStock.length / POR_PAGINA)); },
    get filasSinStock() {
      const desde = (this.pagina - 1) * POR_PAGINA;
      return this.sinStock.slice(desde, desde + POR_PAGINA);
    },
    irA(p) { if (p >= 1 && p <= this.totalPaginas) this.pagina = p; },

    // ---- Formato (solo presentación) ----
    numero(n) { return formatoNumero.format(n); },
    millones(n) { return `$ ${formatoMillones.format(n / 1e6)} M`; },
    pesos(n) { return formatoPrecio.format(n); },
    cuit(c) { return c && c.length === 11 ? `${c.slice(0, 2)}-${c.slice(2, 10)}-${c.slice(10)}` : c; },
    fecha(iso) { return iso ? iso.split('-').reverse().join('/') : ''; },
    etiquetaSala(s) { return `#${s.id_sala} · ${s.direccion} · ${s.localidad}`; },
    claseDeposito(n) { return n >= 100 ? 'stock-ok' : 'stock-bajo'; }, // solo color, como en el catálogo
  }));
});
