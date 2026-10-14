# Etapa 1 · Paso 3: Esquema relacional 

TPI Bases de Datos · Bodegas del Atuel · Oct 13, 2026  

## 1. Relaciones 

El DER se transforma en 31 relaciones. Convención: **negrita** = clave primaria (PK), _cursiva_ = clave foránea (FK), ***negrita y cursiva*** = PK que además es FK. AK = clave alternativa (UNIQUE). 

### Ubicación y personal 

- departamento(**id\_departamento**, nombre, provincia) · AK(nombre, provincia) 
- localidad(**id\_localidad**, nombre, provincia, codigo\_postal, _cuit\_encargado_) · AK(cuit\_encargado) 
- deposito(**id**, _id\_localidad_) 
- sala\_venta(**id\_sala**, calle, numero, dia\_cierre, _id\_localidad_) 
- empleado(**cuit**, nombre, fecha\_ingreso, salario, _id\_sala_) 

### Producción 

- finca(**id\_finca**, nombre, superficie\_ha, _id\_departamento_) 
- parcela(***id\_finca***, **nro\_parcela**, superficie\_ha, anio\_plantacion, _id\_cepa_) 
- cepa(**id\_cepa**, nombre, tipo) · AK(nombre) 
- lote\_uva(**nro\_lote**, _id\_finca_, _nro\_parcela_, fecha\_cosecha, kg, _cuit\_bodega_) · índice único (id\_finca, nro\_parcela, año de fecha\_cosecha) 
- analisis\_calidad(**id\_analisis**, _nro\_lote_, fecha, brix, ph, acidez\_total) 

### Bodegas y vinos 

- bodega(**cuit**, razon\_social, domicilio) 
- vino(**cod\_vino**, nombre, tipo, anada, volumen\_ml, graduacion, precio, _cuit\_bodega_) · AK(nombre, anada, volumen\_ml) 
- composicion(***cod\_vino***, ***id\_cepa***, porcentaje) 
- maridaje(**id\_maridaje**, nombre, temperatura\_servicio) · AK(nombre) 
- vino\_maridaje(***cod\_vino***, ***id\_maridaje***) 
- auditoria\_precio(**id\_auditoria**, _cod\_vino_, precio\_anterior, precio\_nuevo, fecha\_hora, usuario) 

### Clientes y ventas 

- cliente(**id\_cliente**, nombre\_razon\_social, tipo\_doc, nro\_doc, direccion, _id\_localidad_, fecha\_alta, tipo, descuento) · AK1(tipo\_doc, nro\_doc) · AK2(id\_cliente, tipo) 
- socio(***id\_cliente***, _tipo_) 
- distribuidor(***id\_cliente***, _tipo_, zona\_cobertura, nro\_habilitacion) 
- exportador(***id\_cliente***, _tipo_, pais\_destino) 
- permiso\_exportacion(**codigo**, _id\_cliente_, fecha\_emision, fecha\_vencimiento) 
- comprobante(**nro**, fecha, _id\_cliente_, _id\_sala_, subtotal, porcentaje\_descuento, total) 
- renglon\_comprobante(***nro***, ***cod\_vino***, cantidad, precio\_unitario, importe\_descuento, subtotal) 

### Logística y stock 

- transportista(**cod\_transportista**, razon\_social, cuit, email, telefono, domicilio) · AK(cuit) 
- transportista\_localidad(***cod\_transportista***, ***id\_localidad***) 
- ingreso(**cod\_ingreso**, fecha, estado, _cod\_transportista_, _cuit\_bodega_) 
- renglon\_ingreso(***cod\_ingreso***, ***cod\_vino***, cantidad) 
- transferencia(**nro**, _id\_sala_, fecha\_confeccion, estado) 
- renglon\_transferencia(***nro***, ***cod\_vino***, cantidad) 
- stock\_sala(***id\_sala***, ***cod\_vino***, cantidad) 
- stock\_deposito(***cod\_vino***, cantidad) 

stock\_deposito no lleva columna de depósito porque existe un único depósito central (deposito tiene una sola fila, id = 1). 

## 2. Claves foráneas y acciones referenciales 

Hay 37 claves foráneas: CASCADE solo donde la fila no existe sin su cabecera, RESTRICT en el resto, y ON UPDATE CASCADE solo cuando la referencia es un CUIT (clave natural). 

| Tabla.columna  | Referencia  | ON DELETE  | ON UPDATE  |
| --- | --- | --- | --- |
| finca.id\_departamento  | departamento  | RESTRICT  | NO ACTION  |
| localidad.cuit\_encargado  | empleado(cuit)  | RESTRICT  | CASCADE  |
| deposito.id\_localidad  | localidad  | RESTRICT  | NO ACTION  |
| sala\_venta.id\_localidad  | localidad  | RESTRICT  | NO ACTION  |
| empleado.id\_sala  | sala\_venta  | RESTRICT  | NO ACTION  |
| parcela.id\_finca  | finca  | CASCADE  | NO ACTION  |
| parcela.id\_cepa  | cepa  | RESTRICT  | NO ACTION  |
| lote\_uva.(id\_finca, nro\_parcela)  | parcela  | RESTRICT  | NO ACTION  |
| lote\_uva.cuit\_bodega  | bodega(cuit)  | RESTRICT  | CASCADE  |
| analisis\_calidad.nro\_lote  | lote\_uva  | CASCADE  | NO ACTION  |
| vino.cuit\_bodega  | bodega(cuit)  | RESTRICT  | CASCADE  |
| composicion.cod\_vino  | vino  | CASCADE  | NO ACTION  |
| composicion.id\_cepa  | cepa  | RESTRICT  | NO ACTION  |
| vino\_maridaje.cod\_vino  | vino  | CASCADE  | NO ACTION  |
| vino\_maridaje.id\_maridaje  | maridaje  | RESTRICT  | NO ACTION  |
| auditoria\_precio.cod\_vino  | vino  | RESTRICT  | NO ACTION  |
| cliente.id\_localidad  | localidad  | RESTRICT  | NO ACTION  |
| socio.(id\_cliente, tipo)  | cliente(id\_cliente, tipo)  | CASCADE  | NO ACTION  |
| distribuidor.(id\_cliente, tipo)  | cliente(id\_cliente, tipo)  | CASCADE  | NO ACTION  |
| exportador.(id\_cliente, tipo)  | cliente(id\_cliente, tipo)  | CASCADE  | NO ACTION  |
| permiso\_exportacion.id\_cliente  | exportador  | CASCADE  | NO ACTION  |
| comprobante.id\_cliente  | cliente  | RESTRICT  | NO ACTION  |
| comprobante.id\_sala  | sala\_venta  | RESTRICT  | NO ACTION  |
| renglon\_comprobante.nro  | comprobante  | CASCADE  | NO ACTION  |
| renglon\_comprobante.cod\_vino  | vino  | RESTRICT  | NO ACTION  |
| transportista\_localidad.cod\_transportista  | transportista  | CASCADE  | NO ACTION  |
| transportista\_localidad.id\_localidad  | localidad  | RESTRICT  | NO ACTION  |
| ingreso.cod\_transportista  | transportista  | RESTRICT  | NO ACTION  |
| ingreso.cuit\_bodega  | bodega(cuit)  | RESTRICT  | CASCADE  |
| renglon\_ingreso.cod\_ingreso  | ingreso  | CASCADE  | NO ACTION  |
| renglon\_ingreso.cod\_vino  | vino  | RESTRICT  | NO ACTION  |
| renglon\_transferencia.nro  | transferencia  | CASCADE  | NO ACTION  |
| renglon\_transferencia.cod\_vino  | vino  | RESTRICT  | NO ACTION  |
| stock\_sala.id\_sala  | sala\_venta  | RESTRICT  | NO ACTION  |
| stock\_sala.cod\_vino  | vino  | RESTRICT  | NO ACTION  |
| stock\_deposito.cod\_vino  | vino  | RESTRICT  | NO ACTION  |

localidad.cuit\_encargado se declara DEFERRABLE INITIALLY DEFERRED: forma un ciclo localidad → empleado → sala\_venta → localidad, y diferirla permite cargar las tres filas en una misma transacción. 

El CASCADE de composicion y vino\_maridaje no permite borrar vinos con movimientos: los RESTRICT de renglones, stock y auditoría lo impiden antes (RN-14). 

## 3. Transformación del DER 

Las 23 entidades y 27 relaciones del DER se convierten en 31 tablas aplicando seis reglas. 

| Elemento del DER  | Regla aplicada  | Casos  |
| --- | --- | --- |
| Entidad fuerte  | Una tabla; su identificador es la PK  | departamento, localidad, sala\_venta, empleado, finca, cepa, lote\_uva, analisis\_calidad, bodega, vino, maridaje, cliente, permiso\_exportacion, comprobante, transportista, ingreso, transferencia, auditoria\_precio, deposito  |
| Entidad débil  | Una tabla con PK compuesta: PK de la entidad fuerte + clave parcial  | parcela (id\_finca, nro\_parcela)  |
| Relación 1:N  | FK en la tabla del lado N; no genera tabla  | se ubica, genera, entregado a, elabora, audita, vive en, emitido a, realizado en, solicita, trabaja en, ubicada en, traslada, proviene de, se analiza, tiene plantada, posee  |
| Relación 1:1  | FK con UNIQUE en el lado de participación parcial  | es encargado de (localidad.cuit\_encargado), ubicado en (deposito.id\_localidad)  |
| Relación N:M  | Una tabla con PK compuesta por las dos FK; los atributos de la relación pasan a esa tabla  | compuesto por → composicion, se recomienda con → vino\_maridaje, incluye → renglon\_comprobante, ingresa → renglon\_ingreso, transfiere → renglon\_transferencia, tiene stock → stock\_sala, cubre → transportista\_localidad  |
| Relación 1:N con depósito único  | Tabla con PK = FK al vino, sin columna de depósito  | almacena → stock\_deposito  |
| Jerarquía (t, d)  | Supertipo + una tabla por subtipo (ver sección 4)  | cliente → socio, distribuidor, exportador  |

El atributo derivado campaña no se transforma en columna: se calcula a partir de fecha\_cosecha, y la regla de una cosecha por parcela y campaña se garantiza con un índice único de expresión. 

## 4. Mapeo de la jerarquía de clientes 

Se eligió supertipo + una tabla por subtipo: es la única opción que permite que permiso\_exportacion apunte solo a exportadores con una FK simple y que no deja columnas en NULL. 

| Opción  | Ventajas  | Desventajas  |
| --- | --- | --- |
| Tabla única con columna tipo  | Sin joins; consultas simples  | zona\_cobertura, nro\_habilitacion y pais\_destino quedan en NULL para dos de cada tres tipos; los NOT NULL por subtipo requieren CHECK condicionales; un permiso no puede exigir por FK que el cliente sea exportador  |
| Una tabla por subtipo (sin supertipo)  | Sin NULL; cada tabla tiene solo sus columnas  | Datos comunes repetidos en tres tablas; comprobante no puede tener una FK única a "cliente"; documento único entre tablas solo con triggers  |
| **Supertipo + subtipos (elegida)**  | Sin NULL; comprobante apunta a cliente con una sola FK; permiso\_exportacion apunta a exportador; la disjunción se garantiza por FK  | Un join para leer los datos propios de cada subtipo, que se resuelve con una vista  |

La jerarquía es total y disjunta y se garantiza así: 

- **Disjunta:** cada subtipo referencia cliente(id\_cliente, tipo) con su tipo fijo por CHECK (por ejemplo, tipo = 'exportador'), así un cliente no puede tener fila en dos subtipos. 
- **Total:** cliente.tipo es NOT NULL. Que exista la fila en el subtipo correspondiente se verifica con un constraint trigger diferido (etapa 2). 
