TPI Bases de Datos · Bodegas del Atuel · Oct 13, 2026 · @Arantxa

1. Entidades y atributos

El modelo queda en 31 tablas. Referencias: PK = clave primaria, FK = clave foránea, U = restricción UNIQUE.

### Ubicación y personal

| Tabla | Atributos |
| --- | --- |
| departamento | PK id\_departamento, nombre, provincia ·U(nombre, provincia) |
| localidad | PK id\_localidad, nombre, provincia, codigo\_postal,FK cuit\_encargado → empleado (U, diferible) |
| deposito | PK id (fila única, CHECK id = 1), FK id\_localidad |
| sala\_venta | PK id\_sala, calle, numero, dia\_cierre (ENUM), FKid\_localidad |
| empleado | PK cuit, nombre, fecha\_ingreso, salario, FK id\_sala(NOT NULL) |

### Producción

| Tabla | Atributos |
| --- | --- |
| finca | PK id\_finca, nombre, superficie\_ha, FKid\_departamento |
| parcela (débil) | PK (FK id\_finca, nro\_parcela), superficie\_ha,anio\_plantacion, FK id\_cepa |
| cepa | PK id\_cepa, nombre (U), tipo (ENUM tinta/blanca) |
| lote\_uva | PK nro\_lote (global), FK (id\_finca, nro\_parcela),fecha\_cosecha, kg, FK cuit\_bodega · índice único(parcela, año de fecha\_cosecha) |
| analisis\_calidad | PK id\_analisis, FK nro\_lote, fecha, brix, ph,acidez\_total |

### Bodegas y vinos

| Tabla | Atributos |
| --- | --- |
| bodega | PK cuit, razon\_social, domicilio |
| vino | PK cod\_vino, nombre, tipo (ENUM), anada,volumen\_ml, graduacion, precio, FK cuit\_bodega ·U(nombre, anada, volumen\_ml) |
| composicion | PK (FK cod\_vino, FK id\_cepa), porcentaje |
| maridaje | PK id\_maridaje, nombre (U), temperatura\_servicio |
| vino\_maridaje | PK (FK cod\_vino, FK id\_maridaje) |

### Clientes y ventas

| Tabla | Atributos |
| --- | --- |
| cliente | PK id\_cliente, nombre\_razon\_social, tipo\_doc,nro\_doc, direccion, FK id\_localidad, fecha\_alta, tipo(ENUM), descuento · U(tipo\_doc, nro\_doc) ·U(id\_cliente, tipo) |
| socio | PK/FK (id\_cliente, tipo = 'socio') |
| distribuidor | PK/FK (id\_cliente, tipo = 'distribuidor'),zona\_cobertura, nro\_habilitacion |
| exportador | PK/FK (id\_cliente, tipo = 'exportador'),pais\_destino |
| permiso\_exportacion | PK codigo, FK id\_cliente (exportador),fecha\_emision, fecha\_vencimiento |
| comprobante | PK nro, fecha, FK id\_cliente, FK id\_sala, subtotal,porcentaje\_descuento, total |
| renglon\_comprobante | PK (FK nro, FK cod\_vino), cantidad, precio\_unitario,importe\_descuento, subtotal |

### Logística y stock

| Tabla | Atributos |
| --- | --- |
| transportista | PK cod\_transportista, razon\_social, cuit (U), email,telefono, domicilio |
| transportista\_localidad | PK (FK cod\_transportista, FK id\_localidad) |
| ingreso | PK cod\_ingreso, fecha, estado (ENUM), FKcod\_transportista, FK cuit\_bodega |
| renglon\_ingreso | PK (FK cod\_ingreso, FK cod\_vino), cantidad |
| transferencia | PK nro, FK id\_sala, fecha\_confeccion, estado(ENUM) |
| renglon\_transferencia | PK (FK nro, FK cod\_vino), cantidad |
| stock\_sala | PK (FK id\_sala, FK cod\_vino), cantidad |
| stock\_deposito | PK/FK cod\_vino, cantidad |
| auditoria\_precio | PK id, FK cod\_vino, precio\_anterior, precio\_nuevo,fecha\_hora, usuario |

2. Relaciones y cardinalidades

Hay 27 relaciones: cinco N:M con atributos, una entidad débil (Parcela) y una jerarquía total y disjunta (Cliente).

| Relación | Cardinalidad |
| --- | --- |
| Departamento – Finca | 1 : (0,N) |
| Localidad – Sala | 1 : (0,N) |
| Localidad – Empleado (encargado) | (1,1) : (0,1) |
| Localidad – Depósito | 1 : (0,1) |
| Sala – Empleado | 1 : (1,N) |
| Finca – Parcela (identificadora) | 1 : (1,N) |
| Cepa – Parcela | 1 : (0,N) |
| Parcela – Lote | 1 : (0,N), máximo uno por año |
| Bodega – Lote | 1 : (0,N) |
| Lote – Análisis | 1 : (0,N) |
| Bodega – Vino | 1 : (0,N) |
| Vino – Cepa (composición, con %) | (1,N) : (0,N) |
| Vino – Maridaje | (1,N) : (0,N) |
| Localidad – Cliente | 1 : (0,N) |
| Cliente – Socio / Distribuidor / Exportador | jerarquía (t, d): total y disjunta |
| Exportador – Permiso | 1 : (0,N) |
| Cliente – Comprobante | 1 : (0,N) |
| Sala – Comprobante | 1 : (0,N) |
| Comprobante – Vino (renglón) | (1,N) : (0,N) |
| Sala – Vino (stock) | (0,N) : (0,N) |
| Transportista – Localidad (cobertura) | (0,N) : (0,N) |
| Transportista – Ingreso | 1 : (0,N) |
| Bodega – Ingreso | 1 : (0,N) |
| Ingreso – Vino (renglón) | (1,N) : (0,N) |
| Sala – Transferencia | 1 : (0,N) |
| Transferencia – Vino (renglón) | (1,N) : (0,N) |

La cardinalidad mínima de análisis por lote se relaja a 0: el análisis se hace después de la cosecha, así que exigirlo en la misma transacción impediría registrar el lote.

La jerarquía es total porque no existe un cliente sin subtipo, y disjunta porque un cliente pertenece a un solo subtipo.

3. Reglas de negocio y mecanismos

Siete reglas se resuelven con constraints, ocho requieren lógica adicional y se detectaron siete reglas implícitas (RI).

### Declarativas (constraints)

| Regla | Mecanismo |
| --- | --- |
| RN-01 | CHECK precio \> 0 |
| RN-02 | FK de sala a localidad y FK a empleado comoencargado |
| RN-03 | FK NOT NULL de empleado a sala |
| RN-04 | FK a cepa e índice único (parcela, año) |
| RN-07 | CHECK vencimiento \> emisión |
| RN-14 | FK con ON DELETE RESTRICT |
| RN-15 | CHECK de positivos y de graduación entre 5 y 20 |

### Con lógica adicional

| Regla | Mecanismo |
| --- | --- |
| RN-05 | Constraint trigger diferido: la suma de cortes es100 |
| RN-06 | fn\_descuento\_cliente + CHECK de rango |
| RN-08 | fn\_total\_comprobante + trigger AFTER en elrenglón |
| RN-09 | Trigger BEFORE INSERT + CHECK ≥ 0 + FORUPDATE |
| RN-10 | ENUM + trigger de estados + sp\_procesar\_ingreso |
| RN-11 | Trigger de estados + trigger de fecha +sp\_procesar\_transferencia |
| RN-12 | Trigger de bloqueo sobre los renglones |
| RN-13 | Trigger AFTER UPDATE + auditoria\_precio |

### Reglas implícitas

| Código | Regla | Mecanismo |
| --- | --- | --- |
| RI-01 | El encargado trabaja en una sala de sumisma localidad | Trigger + FK diferible para romper el ciclode dependencias |
| RI-02 | Todo vino tiene al menos un maridaje | Constraint trigger diferido (junto conRN-05) |
| RI-03 | El precio unitario es una copiahistórica de vino.precio | Trigger BEFORE INSERT en el renglón |
| RI-04 | Los vinos de un ingreso son de labodega de origen | Trigger en renglon\_ingreso |
| RI-05 | El transportista cubre la localidad deldepósito | Trigger en ingreso |
| RI-06 | Exportador con más de 3 permisos(todos) recibe 35 % | Trigger sobre permiso que recalcula confn\_descuento\_cliente |
| RI-07 | El subtipo coincide con el tipo delcliente | FK compuesta (id\_cliente, tipo) |

RI-03 se resuelve con un trigger porque el precio del vino cambia (U3, U5, RN-13) y una venta pasada no puede cambiar su importe; además, la API no debe enviar ni calcular precios.

4. Decisiones de diseño (sección 5)

El esquema queda completo en 3FN, sin excepciones.

| Decisión | Elección | Justificación |
| --- | --- | --- |
| Jerarquía declientes | Supertipo + una tabla porsubtipo | Evita columnas en NULL y permiteque permiso\_exportacion apuntesolo a exportador con una FKsimple. La desventaja (más joins) seresuelve con una vista. |
| Claves | Subrogadas en casi todas lastablas | Los IDENTITY son estables ycompactos para las FK de tablasgrandes. |
| Claves | CUIT natural en bodega yempleado | Es estable, único y validable con elDOMAIN cuit. |
| Claves | Código propio en transportista,CUIT como UNIQUE | El enunciado le asigna un código detransporte. |
| Claves | Compuesta en parcela (finca, n.° parcela) | Es entidad débil. |
| Claves | Localidad subrogada | Varias localidades puedencompartir código postal. |
| Claves | Permiso con código naturalglobal | Lo emite un organismo, así que elcódigo ya identifica al permiso. |
| Tipos de datos | NUMERIC para dinero yporcentajes | Nunca FLOAT, por precisión exacta. |
| Tipos de datos | DATE para fechas,TIMESTAMPTZ para la auditoría | La auditoría necesita la hora exactadel cambio. |
| Tipos de datos | ENUM para estado, tipo decliente, tipo de vino, tipo decepa y día de la semana;DOMAIN cuit | Los estados no son texto libre. |
| Atributosderivados | Se guardan totales, % dedescuento, precio unitario,descuento del cliente y stocks | Por historia (los precios ydescuentos cambian) y porrendimiento (150.000comprobantes). Los mantienentriggers. |
| Atributosderivados | La campaña se calcula a partirde fecha\_cosecha | Evita la dependencia transitivanro\_lote → fecha → campaña. Launicidad se garantiza con un índiceúnico de expresión. |
| Accionesreferenciales | CASCADE solo en lodependiente | Renglones, composición, maridajes,análisis, permisos, subtipos ycoberturas no existen sin sucabecera. |
| Accionesreferenciales | RESTRICT en todo lo demás | Movimientos, catálogos, stock yauditoría (RN-14). |
| Accionesreferenciales | ON UPDATE CASCADE solo enclaves naturales | Las IDENTITY nunca cambian. |
| Normalización | Departamento en tabla propia | Elimina la dependencia transitivadepartamento → provincia en finca. |

Las columnas derivadas guardadas son redundancia controlada: el enunciado pide almacenarlas y justificarlas, y su consistencia la garantizan triggers.
