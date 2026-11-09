// transferencias.js — Transferencias depósito → sala (#55).
//
//   #transferencias          lista (GET /transferencias?estado=) y nada elegido
//   #transferencias/nueva    alta: se elige la sala y POST /transferencias
//   #transferencias/58       detalle: GET /transferencias/{nro}
//
// Circuito (RN-11): en_confeccion → terminado → procesado, sin retroceso.
//   - Renglones: POST /transferencias/{nro}/renglones y
//     DELETE /transferencias/{nro}/renglones/{cod}. Fuera de confección los
//     rechaza el trigger de RN-12.
//   - Terminar: sp_terminar_transferencia. Procesar: sp_procesar_transferencia,
//     que mueve el stock del depósito a la sala; si no alcanza, rechaza todo y
//     la transferencia sigue en terminado.
//
// El front solo decide qué botones habilitar según el estado que devuelve la
// API. Si la base rechaza algo, se muestra su mensaje tal cual.

document.addEventListener('alpine:init', () => {

  const ESTADOS = ['en_confeccion', 'terminado', 'procesado'];
  const POR_PAGINA = 8;
  const RESULTADOS_VINO = 10;
  const ESPERA_MS = 250;

  // Qué se puede hacer en cada estado (lo hace cumplir la base; acá solo se
  // habilitan los botones). Se usa también para la tabla de ayuda.
  const ACCIONES = {
    en_confeccion: { renglones: true,  terminar: true,  procesar: false },
    terminado:     { renglones: false, terminar: false, procesar: true },
    procesado:     { renglones: false, terminar: false, procesar: false },
  };

  Alpine.data('transferencias', () => ({
    estados: ESTADOS,
    acciones: ACCIONES,

    // --- Lista ---
    filtroEstado: '',
    lista: [],
    total: 0,
    pagina: 1,
    cargandoLista: false,
    errorLista: '',

    // --- Detalle / alta ---
    modo: null,             // null | 'nueva' | 'detalle'
    nro: null,
    t: {},                  // detalle de GET /transferencias/{nro}
    hayDetalle: false,
    cargando: false,
    errorDetalle: '',       // no se pudo cargar
    error: '',              // error de una acción (RN-11, RN-12, stock…) tal cual
    ocupado: false,         // hay una acción en curso

    // --- Alta ---
    salas: [],
    salaNueva: '',

    // --- Agregar renglón ---
    qVino: '',
    vinos: [],
    buscandoVinos: false,
    abiertoVino: false,
    vinoElegido: null,
    cantidad: 1,
    aviso: '',
    _espera: null,

    async init() {
      this.cargarLista();
      api.listarSalas().then(s => { this.salas = s; }).catch(e => { this.error = e.message; });
      this.alCambiarRuta(Alpine.store('ruta'));
    },

    // ================= Ruta =================
    async alCambiarRuta({ pantalla, params }) {
      if (pantalla !== 'transferencias') return;
      this.error = this.errorDetalle = this.aviso = '';
      this.limpiarVino();

      if (params[0] === 'nueva') {
        this.modo = 'nueva';
        this.nro = null;
        this.hayDetalle = false;
        this.salaNueva = '';
        return;
      }
      if (params[0]) {
        this.modo = 'detalle';
        this.nro = params[0];
        await this.cargarDetalle();
        return;
      }
      this.modo = null;
      this.nro = null;
      this.hayDetalle = false;
    },

    // ================= Lista =================
    async cargarLista() {
      this.cargandoLista = true;
      this.errorLista = '';
      try {
        const r = await api.listarTransferencias({
          estado: this.filtroEstado, limit: POR_PAGINA, offset: (this.pagina - 1) * POR_PAGINA,
        });
        this.lista = r.transferencias;
        this.total = r.total;
      } catch (e) {
        this.errorLista = e.message;
        this.lista = [];
        this.total = 0;
      } finally {
        this.cargandoLista = false;
      }
    },

    filtrar() {
      this.pagina = 1;
      this.cargarLista();
    },

    get totalPaginas() { return Math.max(1, Math.ceil(this.total / POR_PAGINA)); },

    irA(p) {
      if (p < 1 || p > this.totalPaginas) return;
      this.pagina = p;
      this.cargarLista();
    },

    // ================= Detalle =================
    async cargarDetalle() {
      this.cargando = true;
      try {
        this.t = await api.obtenerTransferencia(this.nro);
        this.hayDetalle = true;
      } catch (e) {
        this.errorDetalle = e.message;
        this.hayDetalle = false;
      } finally {
        this.cargando = false;
      }
    },

    // Lo que se puede hacer según el estado actual que devolvió la API.
    get puede() {
      return (this.hayDetalle && ACCIONES[this.t.estado]) || { renglones: false, terminar: false, procesar: false };
    },

    // Ejecuta una acción, muestra el error de la base tal cual y refresca
    // detalle y lista (el estado o los renglones pueden haber cambiado).
    async accion(fn) {
      this.ocupado = true;
      this.error = '';
      this.aviso = '';
      try {
        await fn();
        return true;
      } catch (e) {
        this.error = e.message;
        return false;
      } finally {
        if (this.nro) await this.cargarDetalle();
        await this.cargarLista();
        this.ocupado = false;
      }
    },

    // ================= Alta =================
    async crear() {
      if (!this.salaNueva) return;
      this.ocupado = true;
      this.error = '';
      try {
        const { nro } = await api.crearTransferencia(Number(this.salaNueva));
        this.filtroEstado = '';
        this.pagina = 1;
        await this.cargarLista();
        location.hash = `#transferencias/${nro}`;
      } catch (e) {
        this.error = e.message;
      } finally {
        this.ocupado = false;
      }
    },

    // ================= Renglones =================
    escribirVino() {
      this.vinoElegido = null;
      this.abiertoVino = true;
      clearTimeout(this._espera);
      this._espera = setTimeout(() => this.buscarVinos(), ESPERA_MS);
    },

    async buscarVinos() {
      this.buscandoVinos = true;
      try {
        const r = await api.listarVinos({ nombre: this.qVino.trim(), limit: RESULTADOS_VINO });
        this.vinos = r.vinos;
      } catch (e) {
        this.error = e.message;
        this.vinos = [];
      } finally {
        this.buscandoVinos = false;
      }
    },

    elegirVino(v) {
      this.vinoElegido = v;
      this.qVino = this.etiquetaVino(v);
      this.abiertoVino = false;
      this.aviso = '';
      this.$nextTick(() => this.$refs.cantidadTr && this.$refs.cantidadTr.focus());
    },

    limpiarVino() {
      Object.assign(this, { qVino: '', vinos: [], abiertoVino: false, vinoElegido: null, cantidad: 1 });
    },

    async agregarRenglon() {
      if (!this.vinoElegido) return;
      const cod = this.vinoElegido.cod_vino;
      // Un renglón por vino (PK nro + cod_vino): el front no suma cantidades.
      if (this.t.renglones.some(r => r.cod_vino === cod)) {
        this.aviso = 'Ese vino ya está en la transferencia. Quitalo y volvé a agregarlo con la cantidad que corresponde.';
        return;
      }
      // La cantidad va tal cual: si no es válida, la rechaza el CHECK de la base.
      const ok = await this.accion(() =>
        api.agregarRenglonesTransferencia(this.nro, [{ cod_vino: cod, cantidad: Number(this.cantidad) }]));
      if (ok) this.limpiarVino();
    },

    quitar(cod) {
      return this.accion(() => api.quitarRenglonTransferencia(this.nro, cod));
    },

    // ================= Estado =================
    terminar() { return this.accion(() => api.terminarTransferencia(this.nro)); },
    procesar() { return this.accion(() => api.procesarTransferencia(this.nro)); },

    // ================= Formato (solo presentación) =================
    etiquetaEstado(e) { return e === 'en_confeccion' ? 'en confección' : e; },
    fecha(iso) { return iso ? iso.split('-').reverse().join('/') : ''; },
    etiquetaVino(v) { return `${v.nombre ?? v.vino} ${v.anada} · ${v.volumen_ml} ml`; },
    etiquetaSala(s) { return `#${s.id_sala} · ${s.direccion} · ${s.localidad}`; },

    // Color del stock del depósito: solo visual. Si de verdad no alcanza lo
    // decide sp_procesar_transferencia al procesar.
    claseStock(r) {
      if (r.stock_deposito === 0) return 'stock-cero';
      return r.stock_deposito < r.cantidad ? 'stock-bajo' : 'stock-ok';
    },
  }));
});
