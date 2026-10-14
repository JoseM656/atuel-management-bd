# Etapa 1 · Paso 4: Decisiones de diseño 

## 1 Jerarquía de clientes 

Se mapeó como supertipo + una tabla por subtipo. Es la única opción que evita columnas en NULL, permite que comprobante apunte a cliente con una sola FK y que permiso\_exportacion apunte solo a exportador. La disjunción se garantiza con la FK compuesta (id\_cliente, tipo) y un CHECK de tipo fijo en cada subtipo. La comparación completa de las tres opciones está en el documento del esquema relacional. 

## 2 Claves naturales o subrogadas 

Criterio: clave natural solo si es estable, única y validable; en el resto, IDENTITY. 

| Tabla  | Clave  | Tipo  | Justificación  |
| --- | --- | --- | --- |
| bodega, empleado  | cuit  | Natural  | Estable, única y con formato validable (DOMAIN cuit); ON UPDATE CASCADE cubre una corrección  |
| transportista  | cod\_transportista  | Subrogada  | El enunciado le asigna un código; el CUIT queda como UNIQUE  |
| localidad  | id\_localidad  | Subrogada  | El código postal no sirve: varias localidades pueden compartirlo  |
| permiso\_exportacion  | codigo  | Natural  | Lo emite un organismo y ya identifica al permiso de forma global  |
| parcela  | (id\_finca, nro\_parcela)  | Compuesta  | Entidad débil: el número solo es único dentro de la finca  |
| Tablas de renglones, composición, stock y coberturas  | FK compuestas  | Compuesta  | Una fila por par; impide repetir un vino en el mismo documento  |
| Resto de las entidades (vino, cliente, comprobante, etc.)  | id o código  | Subrogada  | No hay un dato natural estable; IDENTITY es compacto para las FK de tablas grandes  |
| deposito  | id  | Subrogada fija  | CHECK (id = 1) garantiza un único depósito  |

### 3 Tipos de datos 

| Dato  | Tipo elegido  | Justificación  |
| --- | --- | --- |
| Dinero (precios, salarios, totales)  | NUMERIC(12,2)  | Precisión exacta; FLOAT produce errores de redondeo  |
| Porcentajes  | NUMERIC(5,2)  | Exactos, con dos decimales (85,50 %)  |
| Graduación, Brix, pH, acidez, superficies, kg  | NUMERIC con escala acotada  | Valores medidos con decimales fijos  |
| Fechas  | DATE  | No se necesita la hora  |
| Momento del cambio de precio  | TIMESTAMPTZ  | La auditoría necesita fecha y hora con zona horaria  |
| Estados, tipos y día de cierre  | ENUM  | Conjunto cerrado de valores; nunca texto libre  |
| CUIT  | DOMAIN cuit (CHAR(11))  | Una sola definición del formato, reutilizada en todas las tablas  |

## 4 Atributos derivados 

Nueve atributos derivados se guardan a propósito, por historia o por rendimiento; ninguno se carga a mano, porque la base los calcula con triggers, funciones o columnas generadas. 

| Atributo  | Se deriva de  | Por qué se guarda  | Cómo se garantiza la consistencia  |
| --- | --- | --- | --- |
| comprobante.subtotal  | Suma de los renglones  | Rendimiento: 150.000 comprobantes y consultas de ventas por sala (S8, S11)  | Trigger AFTER INSERT/UPDATE/DELETE en renglon\_comprobante (RN-08)  |
| comprobante.porcentaje\_descuento  | cliente.descuento  | Historia: el descuento del cliente puede cambiar después de la venta  | Trigger BEFORE INSERT en comprobante, con fn\_descuento\_cliente  |
| comprobante.total  | subtotal y descuento  | Rendimiento; además U1 pide recalcularlo con un UPDATE, por eso no es columna generada  | fn\_total\_comprobante, invocada por el trigger de RN-08  |
| renglon\_comprobante.precio\_unitario  | vino.precio  | Historia: los precios cambian (U3, U5, RN-13) y las ventas pasadas no  | Trigger BEFORE INSERT; la API no envía precios  |
| renglon\_comprobante.importe\_descuento  | cantidad, precio\_unitario y % del comprobante  | Historia, junto con el precio  | Trigger BEFORE INSERT en renglon\_comprobante  |
| renglon\_comprobante.subtotal  | cantidad × precio\_unitario − importe\_descuento  | Rendimiento en sumas de 500.000 renglones  | Columna GENERATED ALWAYS AS (...) STORED: la base la recalcula sola  |
| cliente.descuento  | tipo y cantidad de permisos  | Evita contar permisos en cada venta  | fn\_descuento\_cliente + triggers en cliente y permiso\_exportacion; CHECK de rango 0 a 35  |
| stock\_sala.cantidad  | Ingresos, transferencias y ventas  | Imprescindible: recalcular el stock desde todo el historial  | sp\_procesar\_transferencia y trigger de venta, con FOR UPDATE; CHECK (cantidad \>= 0)  |
|  |  | en cada venta sería inviable  |  |
| stock\_deposito.cantidad  | Ingresos y transferencias  | Igual que stock\_sala  | sp\_procesar\_ingreso y sp\_procesar\_transferencia; CHECK (cantidad \>= 0)  |

El único derivado que no se guarda es campaña: se calcula con el año de fecha\_cosecha, y la unicidad (parcela, campaña) se garantiza con un índice único de expresión. 

### 5 Acciones referenciales 

- **ON DELETE CASCADE** solo en filas que no existen sin su cabecera: renglones, composición, vino\_maridaje, análisis, parcelas, permisos, subtipos y coberturas. 
- **ON DELETE RESTRICT** en todo lo demás: movimientos, catálogos, stock y auditoría. Impide borrar un transportista, una bodega o un vino con movimientos (RN-14). 
- **ON UPDATE CASCADE** solo en las FK que apuntan a un CUIT; las claves IDENTITY nunca cambian. 

El detalle de las 37 claves foráneas está en el documento del esquema relacional. 
