// venta.js — Nueva venta (#54).
//
//   1. Elegir cliente (GET /clientes?q=&tipo=) y sala (GET /salas).
//   2. Agregar vinos (GET /vinos?nombre=) con su cantidad.
//   3. Cada cambio pide a la base que calcule la venta SIN guardarla
//      (POST /comprobantes/simular: mismos triggers que una venta real y
//      ROLLBACK). Así se ven precio, descuento y total antes de confirmar.
//   4. Confirmar: POST /comprobantes → GET /comprobantes/{nro}.
//
// El front NO calcula importes, descuentos ni stock: los muestra tal cual
// vienen de la base (RI-03 precio, RN-08 descuento, RN-09 stock). Si falta
// stock, el mensaje del trigger se muestra sin cambios.

document.addEventListener('alpine:init', () => {

  const TIPOS_CLIENTE = ['socio', 'distribuidor', 'exportador'];
  const RESULTADOS = 20;   // filas del desplegable de clientes
  const RESULTADOS_VINO = 10;
  const ESPERA_MS = 250;   // debounce de los buscadores

  const formatoPrecio = new Intl.NumberFormat('es-AR', {
    style: 'currency', currency: 'ARS', minimumFractionDigits: 0, maximumFractionDigits: 2,
  });
  const formatoNumero = new Intl.NumberFormat('es-AR', { maximumFractionDigits: 2 });

  Alpine.data('venta', () => ({
    tiposCliente: TIPOS_CLIENTE,
    hoy: new Date().toLocaleDateString('es-AR'),

    // --- Cliente ---
    qCliente: '',
    tipoCliente: '',          // '' = todos
    clientes: [],
    totalClientes: 0,
    buscandoClientes: false,
    abiertoCliente: false,
    cliente: null,            // cliente elegido (fila de GET /clientes)
    errorCliente: '',

    // --- Sala (36 salas: se traen una vez y se filtran en el navegador) ---
    salas: [],
    qSala: '',
    abiertoSala: false,
    sala: null,
    errorSala: '',

    // --- Vino a agregar ---
    qVino: '',
    vinos: [],
    buscandoVinos: false,
    abiertoVino: false,
    vinoElegido: null,
    cantidad: 1,
    avisoVino: '',            // aviso del front (vino repetido), no es un error de la base

    // --- Renglones y cálculo de la base ---
    renglones: [],            // [{ cod_vino, nombre, anada, volumen_ml, cantidad }]
    calculo: null,            // respuesta de /comprobantes/simular
    calculando: false,
    errorVenta: '',           // ApiError (p. ej. RN-09) tal cual; '' = sin error
    pedido: 0,                // descarta respuestas viejas de la simulación

    // --- Confirmación ---
    confirmando: false,
    comprobante: null,        // GET /comprobantes/{nro} tras confirmar

    _esperaCliente: null,
    _esperaVino: null,

    async init() {
      try {
        this.salas = await api.listarSalas();
      } catch (e) {
        this.errorSala = e.message;
      }
    },

    // ================= Cliente =================
    escribirCliente() {
      this.abiertoCliente = true;
      clearTimeout(this._esperaCliente);
      this._esperaCliente = setTimeout(() => this.buscarClientes(), ESPERA_MS);
    },

    elegirTipo(tipo) {
      this.tipoCliente = tipo;
      this.abiertoCliente = true;
      this.buscarClientes();
    },

    async buscarClientes() {
      this.buscandoClientes = true;
      this.errorCliente = '';
      try {
        const r = await api.listarClientes({ q: this.qCliente.trim(), tipo: this.tipoCliente, limit: RESULTADOS });
        this.clientes = r.clientes;
        this.totalClientes = r.total;
      } catch (e) {
        this.errorCliente = e.message;
        this.clientes = [];
      } finally {
        this.buscandoClientes = false;
      }
    },

    elegirCliente(c) {
      this.cliente = c;
      this.abiertoCliente = false;
      this.recalcular();
    },

    cambiarCliente() {
      this.cliente = null;
      this.calculo = null;
      this.abiertoCliente = true;
      this.$nextTick(() => this.$refs.buscadorCliente && this.$refs.buscadorCliente.focus());
      if (this.clientes.length === 0) this.buscarClientes();
    },

    // ================= Sala =================
    // Filtro de la lista ya traída (por ID, dirección o localidad): solo
    // presentación, no es una regla de negocio.
    get salasFiltradas() {
      const q = this.qSala.trim().toLowerCase();
      if (!q) return this.salas;
      return this.salas.filter(s =>
        String(s.id_sala) === q ||
        s.localidad.toLowerCase().includes(q) ||
        s.direccion.toLowerCase().includes(q));
    },

    elegirSala(s) {
      this.sala = s;
      this.abiertoSala = false;
      this.recalcular();
    },

    cambiarSala() {
      this.sala = null;
      this.calculo = null;
      this.abiertoSala = true;
      this.$nextTick(() => this.$refs.buscadorSala && this.$refs.buscadorSala.focus());
    },

    // ================= Vino =================
    escribirVino() {
      this.vinoElegido = null;
      this.abiertoVino = true;
      clearTimeout(this._esperaVino);
      this._esperaVino = setTimeout(() => this.buscarVinos(), ESPERA_MS);
    },

    async buscarVinos() {
      this.buscandoVinos = true;
      try {
        const r = await api.listarVinos({ nombre: this.qVino.trim(), limit: RESULTADOS_VINO });
        this.vinos = r.vinos;
      } catch (e) {
        this.errorVenta = e;
        this.vinos = [];
      } finally {
        this.buscandoVinos = false;
      }
    },

    elegirVino(v) {
      this.vinoElegido = v;
      this.avisoVino = '';
      this.qVino = this.etiquetaVino(v);
      this.abiertoVino = false;
      this.$nextTick(() => this.$refs.cantidad && this.$refs.cantidad.focus());
    },

    // Agrega el vino. Si ya hay cliente y sala, la base valida el stock en ese
    // momento: si lo rechaza (RN-09), el renglón no se agrega y se muestra el
    // mensaje tal cual.
    async agregar() {
      if (!this.vinoElegido) return;
      const v = this.vinoElegido;
      this.avisoVino = '';

      // La base admite un renglón por vino (PK nro + cod_vino). El front no
      // suma cantidades: para cambiarla se quita el renglón y se agrega de nuevo.
      if (this.renglones.some(r => r.cod_vino === v.cod_vino)) {
        this.avisoVino = 'Ese vino ya está en la venta. Quitalo y volvé a agregarlo con la cantidad que corresponde.';
        return;
      }
      // La cantidad va tal cual: si no es válida, la rechaza el CHECK de la base.
      const nuevos = [...this.renglones,
        { cod_vino: v.cod_vino, nombre: v.nombre, anada: v.anada, volumen_ml: v.volumen_ml, cantidad: Number(this.cantidad) }];

      if (this.cliente && this.sala) {
        const ok = await this.simular(nuevos);
        if (!ok) return;          // se conservan los renglones anteriores
      }
      this.renglones = nuevos;
      this.vinoElegido = null;
      this.qVino = '';
      this.cantidad = 1;
    },

    quitar(cod) {
      this.renglones = this.renglones.filter(r => r.cod_vino !== cod);
      this.recalcular();
    },

    // ================= Cálculo en la base =================
    cuerpo(renglones) {
      return {
        id_cliente: this.cliente.id_cliente,
        id_sala: this.sala.id_sala,
        renglones: renglones.map(r => ({ cod_vino: r.cod_vino, cantidad: r.cantidad })),
      };
    },

    // Pide a la base el cálculo de la venta (sin guardar). Devuelve true si la
    // base la aceptó.
    async simular(renglones) {
      const pedido = ++this.pedido;
      this.calculando = true;
      this.errorVenta = '';
      try {
        const r = await api.simularComprobante(this.cuerpo(renglones));
        if (pedido !== this.pedido) return false;
        this.calculo = r;
        return true;
      } catch (e) {
        if (pedido !== this.pedido) return false;
        this.errorVenta = e;   // p. ej. «stock insuficiente del vino …» (RN-09)
        return false;
      } finally {
        if (pedido === this.pedido) this.calculando = false;
      }
    },

    // Se llama al cambiar cliente, sala o renglones.
    async recalcular() {
      this.calculo = null;
      this.errorVenta = '';
      if (!this.cliente || !this.sala || this.renglones.length === 0) {
        this.pedido++;                  // invalida una simulación en curso
        this.calculando = false;
        return;
      }
      await this.simular(this.renglones);
    },

    // Importes de un renglón según la base (o null si todavía no se calculó).
    calculado(cod) {
      return this.calculo ? this.calculo.renglones.find(r => r.cod_vino === cod) || null : null;
    },

    get puedeConfirmar() {
      return this.cliente && this.sala && this.renglones.length > 0 && !this.calculando && !this.confirmando;
    },

    // ================= Confirmar =================
    async confirmar() {
      if (!this.puedeConfirmar) return;
      this.confirmando = true;
      this.errorVenta = '';
      try {
        const { nro } = await api.crearComprobante(this.cuerpo(this.renglones));
        this.comprobante = await api.obtenerComprobante(nro);
        window.scrollTo({ top: 0, behavior: 'smooth' });
      } catch (e) {
        this.errorVenta = e;    // tal cual (RN-09 si otro vendió antes, etc.)
      } finally {
        this.confirmando = false;
      }
    },

    // Cancelar / Nueva venta: vuelve todo a cero (no hay nada guardado).
    limpiar() {
      this.pedido++;
      Object.assign(this, {
        qCliente: '', tipoCliente: '', clientes: [], totalClientes: 0, abiertoCliente: false, cliente: null,
        qSala: '', abiertoSala: false, sala: null,
        qVino: '', vinos: [], abiertoVino: false, vinoElegido: null, cantidad: 1, avisoVino: '',
        renglones: [], calculo: null, calculando: false, errorVenta: '', comprobante: null,
      });
    },

    // ================= Formato (solo presentación) =================
    precio(valor) { return valor === null || valor === undefined ? '' : formatoPrecio.format(valor); },
    porcentaje(valor) { return formatoNumero.format(valor) + ' %'; },
    mayuscula(t) { return t ? t[0].toUpperCase() + t.slice(1) : ''; },
    etiquetaVino(v) { return `${v.nombre} ${v.anada} · ${v.volumen_ml} ml`; },

    // CUIT 30800014018 → 30-80001401-8; DNI 20000018 → 20.000.018.
    documento(c) {
      const n = c.nro_doc;
      if (c.tipo_doc === 'CUIT' && n.length === 11) return `CUIT ${n.slice(0, 2)}-${n.slice(2, 10)}-${n.slice(10)}`;
      return `${c.tipo_doc} ${formatoNumero.format(Number(n))}`;
    },
  }));
});
