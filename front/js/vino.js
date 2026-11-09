// vino.js — ficha del vino y alta/edición (#53).
//
//   #vino/101          ficha: GET /vinos/{cod} (S9) con stock, composición y maridajes.
//   #vino/101/editar   edición: PUT /vinos/{cod} con el vino, su corte y sus maridajes.
//   #vino/nuevo        alta:    POST /vinos con lo mismo.
//   Eliminar           DELETE /vinos/{cod}; si la base lo impide (RN-14) se muestra su mensaje.
//
// El front NO valida que los porcentajes sumen 100 ni que haya un maridaje:
// lo hace la base (RN-05 y maridaje obligatorio, triggers diferidos). Si la
// base rechaza el cambio no se guarda nada y se muestra el error tal cual.

document.addEventListener('alpine:init', () => {

  // Valores permitidos por la base. Se listan acá solo para armar los
  // desplegables; quien los hace cumplir es la base:
  //   tipo     → ENUM tipo_vino (001_esquema.sql)
  //   volumen  → CHECK ck_vino_volumen (002_constraints.sql)
  const TIPOS = ['tinto', 'blanco', 'rosado', 'espumante'];
  const VOLUMENES = [187, 375, 750, 1500, 3000];

  const formatoPrecio = new Intl.NumberFormat('es-AR', {
    style: 'currency', currency: 'ARS', minimumFractionDigits: 0, maximumFractionDigits: 2,
  });
  const formatoDecimal = new Intl.NumberFormat('es-AR', { minimumFractionDigits: 1, maximumFractionDigits: 2 });

  const formVacio = () => ({
    nombre: '', tipo: 'tinto', anada: new Date().getFullYear(), volumen_ml: 750,
    graduacion: '', precio: '', cuit_bodega: '',
    cepas: [{ id_cepa: '', porcentaje: '' }],
    maridajes: [],
  });

  Alpine.data('vino', () => ({
    tipos: TIPOS,
    volumenes: VOLUMENES,

    modo: null,        // 'ficha' | 'editar' | 'nuevo'
    cod: null,

    // Ficha. `vino` nunca vuelve a null: al recargar se baja `hayVino`, que es
    // lo que muestra u oculta la ficha. Así Alpine no evalúa `vino.nombre`
    // sobre null mientras desmonta el template.
    vino: {},
    hayVino: false,
    cargando: false,
    error: '',         // error al cargar la ficha
    // errorAccion y errorForm guardan el ApiError entero ('' = sin error), para
    // mostrar debajo del mensaje el SQLSTATE y la restricción (#88).
    errorAccion: '',   // error al eliminar desde la ficha
    eliminando: false,
    confirmando: false, // ventana «¿Estás seguro…?» abierta

    // Formulario
    form: formVacio(),
    opciones: { cepas: [], bodegas: [], maridajes: [] },
    opcionesCargadas: false,
    guardando: false,
    errorForm: '',

    init() {
      this.alCambiarRuta(Alpine.store('ruta'));
    },

    // Se llama al entrar a la pantalla y cada vez que cambia el hash.
    async alCambiarRuta({ pantalla, params }) {
      this.confirmando = false;
      if (pantalla !== 'vino') return;
      this.error = this.errorAccion = this.errorForm = '';

      if (params[0] === 'nuevo') {
        this.modo = 'nuevo';
        this.cod = null;
        this.form = formVacio();
        await this.cargarOpciones();
        return;
      }

      this.cod = params[0];
      this.modo = params[1] === 'editar' ? 'editar' : 'ficha';
      await this.cargarVino();
      if (this.modo === 'editar' && this.hayVino) {
        await this.cargarOpciones();
        this.llenarForm();
      }
    },

    async cargarVino() {
      this.cargando = true;
      this.hayVino = false;
      try {
        this.vino = await api.obtenerVino(this.cod);
        this.hayVino = true;
      } catch (e) {
        this.error = e.message;
      } finally {
        this.cargando = false;
      }
    },

    async cargarOpciones() {
      if (this.opcionesCargadas) return;
      try {
        const [cepas, bodegas, maridajes] = await Promise.all([
          api.listarCepas(), api.listarBodegas(), api.listarMaridajes(),
        ]);
        this.opciones = { cepas, bodegas, maridajes };
        this.opcionesCargadas = true;
      } catch (e) {
        this.errorForm = e;
      }
    },

    llenarForm() {
      const v = this.vino;
      this.form = {
        nombre: v.nombre, tipo: v.tipo, anada: v.anada, volumen_ml: v.volumen_ml,
        graduacion: v.graduacion, precio: v.precio, cuit_bodega: v.cuit_bodega,
        cepas: v.cepas.map(c => ({ id_cepa: c.id_cepa, porcentaje: c.porcentaje })),
        maridajes: v.maridajes.map(m => m.id_maridaje),
      };
    },

    // --- Composición y maridajes en el formulario ---
    agregarCepa() { this.form.cepas.push({ id_cepa: '', porcentaje: '' }); },
    quitarCepa(i) { this.form.cepas.splice(i, 1); },

    tieneMaridaje(id) { return this.form.maridajes.includes(id); },
    alternarMaridaje(id) {
      const i = this.form.maridajes.indexOf(id);
      if (i === -1) this.form.maridajes.push(id); else this.form.maridajes.splice(i, 1);
    },

    // --- Guardar: un solo request con vino + corte + maridajes ---
    async guardar() {
      this.guardando = true;
      this.errorForm = '';
      const f = this.form;
      const cuerpo = {
        nombre: f.nombre.trim(),
        tipo: f.tipo,
        anada: Number(f.anada),
        volumen_ml: Number(f.volumen_ml),
        graduacion: Number(f.graduacion),
        precio: Number(f.precio),
        cuit_bodega: f.cuit_bodega,
        cepas: f.cepas.map(c => ({ id_cepa: Number(c.id_cepa), porcentaje: Number(c.porcentaje) })),
        maridajes: f.maridajes,
      };
      try {
        if (this.modo === 'nuevo') {
          const { cod_vino } = await api.crearVino(cuerpo);
          location.hash = `#vino/${cod_vino}`;
        } else {
          await api.actualizarVino(this.cod, cuerpo);
          location.hash = `#vino/${this.cod}`;
        }
      } catch (e) {
        // Mensaje de la base tal cual (p. ej. «la composición de un vino no suma 100»).
        this.errorForm = e;
        window.scrollTo({ top: 0, behavior: 'smooth' });
      } finally {
        this.guardando = false;
      }
    },

    cancelar() {
      location.hash = this.modo === 'nuevo' ? '#catalogo' : `#vino/${this.cod}`;
    },

    // --- Eliminar (desde la ficha o el formulario) ---
    // Primero se abre la ventana de confirmación; «Borrar vino» llama a eliminar().
    pedirEliminar() {
      this.errorAccion = this.errorForm = '';
      this.confirmando = true;
      // Foco en «Cancelar»: si se aprieta Enter sin querer, no se borra nada.
      this.$nextTick(() => this.$refs.cancelarBorrado && this.$refs.cancelarBorrado.focus());
    },

    cancelarEliminar() {
      if (!this.eliminando) this.confirmando = false;
    },

    async eliminar() {
      this.eliminando = true;
      try {
        await api.borrarVino(this.cod);
        this.confirmando = false;
        location.hash = '#catalogo';
      } catch (e) {
        // Si tiene ventas, stock o auditoría, la base lo impide (RN-14): se
        // cierra la ventana y se muestra el mensaje de la API tal cual.
        this.confirmando = false;
        if (this.modo === 'ficha') this.errorAccion = e; else this.errorForm = e;
        window.scrollTo({ top: 0, behavior: 'smooth' });
      } finally {
        this.eliminando = false;
      }
    },

    // --- Formato (solo presentación) ---
    precio(valor) { return formatoPrecio.format(valor); },
    decimal(valor) { return formatoDecimal.format(valor); },
    mayuscula(texto) { return texto ? texto[0].toUpperCase() + texto.slice(1) : ''; },
    botellas(n) { return `${n} ${n === 1 ? 'botella' : 'botellas'}`; },
  }));
});
