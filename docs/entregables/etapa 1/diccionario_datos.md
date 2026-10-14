# Etapa 1 · Paso 5: Diccionario de datos 

TPI Bases de Datos · Bodegas del Atuel · Oct 13, 2026 

## 0. Tipos propios 

El esquema define cinco tipos ENUM y un DOMAIN; ningún importe usa FLOAT (todo dinero es NUMERIC) y ningún estado es texto libre. 

| Tipo  | Clase  | Valores o regla  | Usado en  |
| --- | --- | --- | --- |
| estado\_documento  | ENUM  | 'en\_confeccion', 'terminado', 'procesado'  | ingreso.estado, transferencia.estado  |
| tipo\_cliente  | ENUM  | 'socio', 'distribuidor', 'exportador'  | cliente.tipo y subtipos  |
| tipo\_vino  | ENUM  | 'tinto', 'blanco', 'rosado', 'espumante'  | vino.tipo  |
| tipo\_cepa  | ENUM  | 'tinta', 'blanca'  | cepa.tipo  |
| dia\_semana  | ENUM  | 'lunes', 'martes', 'miercoles', 'jueves', 'viernes', 'sabado', 'domingo'  | sala\_venta.dia\_cierre  |
| cuit  | DOMAIN sobre CHAR(11)  | CHECK (VALUE ~ '^\[0-9\]{11}$'): 11 dígitos, sin guiones  | bodega, empleado, transportista y sus FK  |

En las tablas siguientes, Nulos = Sí indica que la columna admite NULL. Los identificadores subrogados usan INTEGER GENERATED ALWAYS AS IDENTITY. 

## 1. Ubicación y personal 

### departamento 

Departamentos donde se ubican las fincas (catálogo del Anexo B). 

| Columna  | Tipo  | Nulos  | Restricciones  | Descripción  |
| --- | --- | --- | --- | --- |
| id\_departamento  | INTEGER  | No  | PK, IDENTITY  | Identificador del departamento  |
| nombre  | VARCHAR(60)  | No  | UNIQUE(nombre, provincia)  | Nombre del departamento  |
| provincia  | VARCHAR(40)  | No  | UNIQUE(nombre, provincia)  | Provincia a la que pertenece  |

### localidad 

Localidades con salas, clientes, depósito o cobertura de transporte. 

| Columna  | Tipo  | Nulos  | Restricciones  | Descripción  |
| --- | --- | --- | --- | --- |
| id\_localidad  | INTEGER  | No  | PK, IDENTITY  | Identificador de la localidad  |
| nombre  | VARCHAR(80)  | No  |   | Nombre de la localidad  |
| provincia  | VARCHAR(40)  | No  |   | Provincia de la localidad  |
| codigo\_postal  | VARCHAR(8)  | No  |   | Código postal (puede repetirse entre localidades)  |
| cuit\_encargado  | cuit  | No  | FK → empleado(cuit), UNIQUE, DEFERRABLE INITIALLY DEFERRED  | Empleado que es encargado regional de la localidad  |

### deposito 

Depósito central único de la empresa. 

| Columna  | Tipo  | Nulos  | Restricciones  | Descripción  |
| --- | --- | --- | --- | --- |
| id  | SMALLINT  | No  | PK, DEFAULT 1, CHECK (id = 1)  | Identificador fijo: garantiza una sola fila  |
| id\_localidad  | INTEGER  | No  | FK → localidad, UNIQUE  | Localidad donde está el depósito  |

### sala\_venta 

Salas de venta al público. 

| Columna  | Tipo  | Nulos  | Restricciones  | Descripción  |
| --- | --- | --- | --- | --- |
| id\_sala  | INTEGER  | No  | PK, IDENTITY  | Identificador de la sala  |
| calle  | VARCHAR(80)  | No  |   | Calle del domicilio  |
| numero  | INTEGER  | No  | CHECK (numero \> 0)  | Número del domicilio  |
| dia\_cierre  | dia\_semana  | No  |   | Día de cierre semanal  |
| id\_localidad  | INTEGER  | No  | FK → localidad  | Localidad donde está la sala  |

### empleado 

Empleados de las salas de venta. 

| Columna  | Tipo  | Nulos  | Restricciones  | Descripción  |
| --- | --- | --- | --- | --- |
| cuit  | cuit  | No  | PK  | CUIT del empleado  |
| nombre  | VARCHAR(100)  | No  |   | Apellido y nombre  |
| fecha\_ingreso  | DATE  | No  |   | Fecha de ingreso laboral  |
| salario  | NUMERIC(12,2)  | No  | CHECK (salario \> 0)  | Salario mensual en pesos  |
| id\_sala  | INTEGER  | No  | FK → sala\_venta  | Sala donde trabaja (RN-03)  |

## 2. Producción 

### finca 

Fincas donde la empresa cultiva uva. 

| Columna  | Tipo  | Nulos  | Restricciones  | Descripción  |
| --- | --- | --- | --- | --- |
| id\_finca  | INTEGER  | No  | PK, IDENTITY  | Identificador de la finca  |
| nombre  | VARCHAR(80)  | No  |   | Nombre de la finca  |
| superficie\_ha  | NUMERIC(10,2)  | No  | CHECK (superficie\_ha \> 0)  | Superficie total en hectáreas  |
| id\_departamento  | INTEGER  | No  | FK → departamento  | Departamento donde se ubica  |

### parcela 

Parcelas de cada finca (entidad débil). 

| Columna  | Tipo  | Nulos  | Restricciones  | Descripción  |
| --- | --- | --- | --- | --- |
| id\_finca  | INTEGER  | No  | PK(id\_finca, nro\_parcela), FK → finca ON DELETE CASCADE  | Finca a la que pertenece  |
| nro\_parcela  | SMALLINT  | No  | PK(id\_finca, nro\_parcela), CHECK (nro\_parcela \> 0)  | Número de parcela dentro de la finca  |
| superficie\_ha  | NUMERIC(10,2)  | No  | CHECK (superficie\_ha \> 0)  | Superficie en hectáreas  |
| anio\_plantacion  | SMALLINT  | No  | CHECK (anio\_plantacion BETWEEN 1900 AND 2100)  | Año de plantación  |
| id\_cepa  | INTEGER  | No  | FK → cepa  | Cepa plantada, una sola (RN-04)  |

### cepa 

Catálogo de cepas (Anexo B). 

| Columna  | Tipo  | Nulos  | Restricciones  | Descripción  |
| --- | --- | --- | --- | --- |
| id\_cepa  | INTEGER  | No  | PK, IDENTITY  | Identificador de la cepa  |
| nombre  | VARCHAR(40)  | No  | UNIQUE  | Nombre de la cepa  |
| tipo  | tipo\_cepa  | No  |   | Tinta o blanca  |

### lote\_uva 

Cosecha de una parcela en una campaña. 

| Columna  | Tipo  | Nulos  | Restricciones  | Descripción  |
| --- | --- | --- | --- | --- |
| nro\_lote  | INTEGER  | No  | PK, IDENTITY  | Número de lote, único global  |
| id\_finca  | INTEGER  | No  | FK (id\_finca, nro\_parcela) → parcela  | Finca de la parcela cosechada  |
| nro\_parcela  | SMALLINT  | No  | FK (id\_finca, nro\_parcela) → parcela  | Parcela cosechada  |
| fecha\_cosecha  | DATE  | No  | Índice único (id\_finca, nro\_parcela, EXTRACT(YEAR FROM fecha\_cosecha))  | Fecha de cosecha; su año es la campaña (RN-04)  |
| kg  | NUMERIC(10,2)  | No  | CHECK (kg \> 0)  | Kilos cosechados  |
| cuit\_bodega  | cuit  | No  | FK → bodega  | Bodega a la que se entregó  |

### analisis\_calidad 

Análisis practicados a cada lote. 

| Columna  | Tipo  | Nulos  | Restricciones  | Descripción  |
| --- | --- | --- | --- | --- |
| id\_analisis  | INTEGER  | No  | PK, IDENTITY  | Identificador del análisis  |
| nro\_lote  | INTEGER  | No  | FK → lote\_uva ON DELETE CASCADE  | Lote analizado  |
| fecha  | DATE  | No  |   | Fecha del análisis  |
| brix  | NUMERIC(4,1)  | No  | CHECK (brix BETWEEN 0 AND 40)  | Grado Brix (azúcar)  |
| ph  | NUMERIC(3,2)  | No  | CHECK (ph \> 0 AND ph \< 14)  | pH del mosto  |
| acidez\_total  | NUMERIC(5,2)  | No  | CHECK (acidez\_total \> 0)  | Acidez total en g/L  |

## 3. Bodegas y vinos 

### bodega 

Bodegas del grupo que elaboran los vinos. 

| Columna  | Tipo  | Nulos  | Restricciones  | Descripción  |
| --- | --- | --- | --- | --- |
| cuit  | cuit  | No  | PK  | CUIT de la bodega  |
| razon\_social  | VARCHAR(120)  | No  |   | Razón social  |
| domicilio  | VARCHAR(150)  | No  |   | Domicilio de la bodega  |

### vino 

Vinos que comercializa la empresa. 

| Columna  | Tipo  | Nulos  | Restricciones  | Descripción  |
| --- | --- | --- | --- | --- |
| cod\_vino  | INTEGER  | No  | PK, IDENTITY  | Código del vino  |
| nombre  | VARCHAR(80)  | No  | UNIQUE(nombre, anada, volumen\_ml)  | Nombre comercial  |
| tipo  | tipo\_vino  | No  |   | Tinto, blanco, rosado o espumante  |
| anada  | SMALLINT  | No  | UNIQUE(nombre, anada, volumen\_ml), CHECK (anada BETWEEN 1990 AND 2100)  | Año de cosecha del vino  |
| volumen\_ml  | INTEGER  | No  | UNIQUE(nombre, anada, volumen\_ml), CHECK (volumen\_ml IN (187, 375, 750, 1500, 3000))  | Presentación en mililitros  |
| graduacion  | NUMERIC(4,2)  | No  | CHECK (graduacion BETWEEN 5 AND 20)  | Graduación alcohólica (RN-15)  |
| precio  | NUMERIC(12,2)  | No  | CHECK (precio \> 0)  | Precio de venta, único para toda la red (RN-01)  |
| cuit\_bodega  | cuit  | No  | FK → bodega  | Bodega que lo elabora  |

### composicion 

Cepas que componen cada vino (N:M con atributo). 

| Columna  | Tipo  | Nulos  | Restricciones  | Descripción  |
| --- | --- | --- | --- | --- |
| cod\_vino  | INTEGER  | No  | PK(cod\_vino, id\_cepa), FK → vino ON DELETE CASCADE  | Vino  |
| id\_cepa  | INTEGER  | No  | PK(cod\_vino, id\_cepa), FK → cepa  | Cepa que lo compone  |
| porcentaje  | NUMERIC(5,2)  | No  | CHECK (porcentaje \> 0 AND porcentaje \<= 100)  | Porcentaje de corte; la suma por vino es 100 (RN-05, trigger diferido)  |

### maridaje 

Catálogo de maridajes (Anexo B). 

| Columna  | Tipo  | Nulos  | Restricciones  | Descripción  |
| --- | --- | --- | --- | --- |
| id\_maridaje  | INTEGER  | No  | PK, IDENTITY  | Identificador del maridaje  |
| nombre  | VARCHAR(60)  | No  | UNIQUE  | Nombre (por ejemplo, carnes rojas)  |
| temperatura\_servicio  | NUMERIC(4,1)  | No  | CHECK (temperatura\_servicio BETWEEN 0 AND 25)  | Temperatura de servicio sugerida en °C  |

### vino\_maridaje 

Maridajes recomendados para cada vino (N:M). 

| Columna  | Tipo  | Nulos  | Restricciones  | Descripción  |
| --- | --- | --- | --- | --- |
| cod\_vino  | INTEGER  | No  | PK(cod\_vino, id\_maridaje), FK → vino ON DELETE CASCADE  | Vino  |
| id\_maridaje  | INTEGER  | No  | PK(cod\_vino, id\_maridaje), FK → maridaje  | Maridaje recomendado  |

### auditoria\_precio 

Historial de cambios de precio; la completa un trigger (RN-13). 

| Columna  | Tipo  | Nulos  | Restricciones  | Descripción  |
| --- | --- | --- | --- | --- |
| id\_auditoria  | BIGINT  | No  | PK, IDENTITY  | Identificador del registro  |
| cod\_vino  | INTEGER  | No  | FK → vino  | Vino cuyo precio cambió  |
| precio\_anterior  | NUMERIC(12,2)  | No  |   | Precio antes del cambio  |
| precio\_nuevo  | NUMERIC(12,2)  | No  |   | Precio después del cambio  |
| fecha\_hora  | TIMESTAMPTZ  | No  | DEFAULT now()  | Momento del cambio  |
| usuario  | VARCHAR(63)  | No  | DEFAULT current\_user  | Usuario de la base que hizo el cambio  |

## 4. Clientes y ventas 

### cliente 

Supertipo de la jerarquía de clientes. 

| Columna  | Tipo  | Nulos  | Restricciones  | Descripción  |
| --- | --- | --- | --- | --- |
| id\_cliente  | INTEGER  | No  | PK, IDENTITY, UNIQUE(id\_cliente, tipo)  | Identificador del cliente  |
| nombre\_razon\_social  | VARCHAR(120)  | No  |   | Apellido y nombre, o razón social  |
| tipo\_doc  | VARCHAR(10)  | No  | UNIQUE(tipo\_doc, nro\_doc)  | Tipo de documento (DNI, CUIT, pasaporte)  |
| nro\_doc  | VARCHAR(15)  | No  | UNIQUE(tipo\_doc, nro\_doc)  | Número de documento  |
| direccion  | VARCHAR(150)  | No  |   | Domicilio  |
| id\_localidad  | INTEGER  | No  | FK → localidad  | Localidad del domicilio  |
| fecha\_alta  | DATE  | No  | DEFAULT CURRENT\_DATE  | Fecha de alta como cliente  |
| tipo  | tipo\_cliente  | No  | UNIQUE(id\_cliente, tipo)  | Subtipo: socio, distribuidor o exportador  |
| descuento  | NUMERIC(5,2)  | No  | CHECK (descuento BETWEEN 0 AND 35)  | Descuento vigente en %; lo mantiene fn\_descuento\_cliente (RN-06): 10, 20, 30 o 35  |

### socio 

Subtipo: socios del club (consumidores finales). 

| Columna  | Tipo  | Nulos  | Restricciones  | Descripción  |
| --- | --- | --- | --- | --- |
| id\_cliente  | INTEGER  | No  | PK, FK (id\_cliente, tipo) → cliente ON DELETE CASCADE  | Cliente socio  |
| tipo  | tipo\_cliente  | No  | DEFAULT 'socio', CHECK (tipo = 'socio')  | Fija el subtipo para garantizar la disjunción  |

### distribuidor 

Subtipo: distribuidores. 

| Columna  | Tipo  | Nulos  | Restricciones  | Descripción  |
| --- | --- | --- | --- | --- |
| id\_cliente  | INTEGER  | No  | PK, FK (id\_cliente, tipo) → cliente ON DELETE CASCADE  | Cliente distribuidor  |
| tipo  | tipo\_cliente  | No  | DEFAULT 'distribuidor', CHECK (tipo = 'distribuidor')  | Fija el subtipo  |
| zona\_cobertura  | VARCHAR(100)  | No  |   | Zona que cubre  |
| nro\_habilitacion  | VARCHAR(30)  | No  | UNIQUE  | Número de habilitación  |

### exportador 

Subtipo: exportadores. 

| Columna  | Tipo  | Nulos  | Restricciones  | Descripción  |
| --- | --- | --- | --- | --- |
| id\_cliente  | INTEGER  | No  | PK, FK (id\_cliente, tipo) → cliente ON DELETE CASCADE  | Cliente exportador  |
| tipo  | tipo\_cliente  | No  | DEFAULT 'exportador',  | Fija el subtipo  |
|  |  |  | CHECK (tipo = 'exportador')  |  |
| pais\_destino  | VARCHAR(60)  | No  |   | País de destino principal  |

### permiso\_exportacion 

Permisos de exportación de cada exportador (RN-07). 

| Columna  | Tipo  | Nulos  | Restricciones  | Descripción  |
| --- | --- | --- | --- | --- |
| codigo  | VARCHAR(30)  | No  | PK  | Código del permiso, único global  |
| id\_cliente  | INTEGER  | No  | FK → exportador ON DELETE CASCADE  | Exportador titular  |
| fecha\_emision  | DATE  | No  |   | Fecha de emisión  |
| fecha\_vencimiento  | DATE  | No  | CHECK (fecha\_vencimiento \> fecha\_emision)  | Fecha de vencimiento  |

### comprobante 

Cabecera de cada venta. 

| Columna  | Tipo  | Nulos  | Restricciones  | Descripción  |
| --- | --- | --- | --- | --- |
| nro  | INTEGER  | No  | PK, IDENTITY  | Número de comprobante  |
| fecha  | DATE  | No  | DEFAULT CURRENT\_DATE  | Fecha de la venta  |
| id\_cliente  | INTEGER  | No  | FK → cliente  | Cliente que compra  |
| id\_sala  | INTEGER  | No  | FK → sala\_venta  | Sala donde se realizó  |
| subtotal  | NUMERIC(12,2)  | No  | DEFAULT 0, CHECK (subtotal \>= 0)  | Suma de renglones sin descuento; la  |
|  |  |  |  | calcula un trigger (RN-08)  |
| porcentaje\_descuento  | NUMERIC(5,2)  | No  | CHECK (porcentaje\_descuento BETWEEN 0 AND 35)  | Descuento del cliente al momento de la venta (copia histórica)  |
| total  | NUMERIC(12,2)  | No  | DEFAULT 0, CHECK (total \>= 0)  | Total con descuento; lo calcula un trigger (RN-08)  |

### renglon\_comprobante 

Vinos incluidos en cada comprobante. 

| Columna  | Tipo  | Nulos  | Restricciones  | Descripción  |
| --- | --- | --- | --- | --- |
| nro  | INTEGER  | No  | PK(nro, cod\_vino), FK → comprobante ON DELETE CASCADE  | Comprobante  |
| cod\_vino  | INTEGER  | No  | PK(nro, cod\_vino), FK → vino  | Vino vendido  |
| cantidad  | INTEGER  | No  | CHECK (cantidad \> 0)  | Botellas vendidas; no puede superar el stock de la sala (RN-09)  |
| precio\_unitario  | NUMERIC(12,2)  | No  | CHECK (precio\_unitario \> 0)  | Copia del precio del vino al vender; la completa un trigger  |
| importe\_descuento  | NUMERIC(12,2)  | No  | CHECK (importe\_descuento \>= 0)  | Descuento en pesos del renglón  |
| subtotal  | NUMERIC(12,2)  | No  | CHECK (subtotal \>= 0)  | cantidad × precio\_unitario − importe\_descuento  |

## 5. Logística y stock 

### transportista 

Empresas de transporte habilitadas. 

| Columna  | Tipo  | Nulos  | Restricciones  | Descripción  |
| --- | --- | --- | --- | --- |
| cod\_transportista  | INTEGER  | No  | PK, IDENTITY  | Código de transporte  |
| razon\_social  | VARCHAR(120)  | No  |   | Razón social  |
| cuit  | cuit  | No  | UNIQUE  | CUIT de la empresa  |
| email  | VARCHAR(120)  | No  | CHECK (email LIKE '%_@_%')  | Correo de contacto  |
| telefono  | VARCHAR(30)  | No  |   | Teléfono de contacto  |
| domicilio  | VARCHAR(150)  | No  |   | Domicilio  |

### transportista\_localidad 

Localidades que alcanza cada transportista (N:M). 

| Columna  | Tipo  | Nulos  | Restricciones  | Descripción  |
| --- | --- | --- | --- | --- |
| cod\_transportista  | INTEGER  | No  | PK(cod\_transportista, id\_localidad), FK → transportista ON DELETE CASCADE  | Transportista  |
| id\_localidad  | INTEGER  | No  | PK(cod\_transportista, id\_localidad), FK → localidad  | Localidad cubierta  |

### ingreso 

Cabecera de cada ingreso al depósito central. 

| Columna  | Tipo  | Nulos  | Restricciones  | Descripción  |
| --- | --- | --- | --- | --- |
| cod\_ingreso  | INTEGER  | No  | PK, IDENTITY  | Código de ingreso  |
| fecha  | DATE  | No  | DEFAULT CURRENT\_DATE  | Fecha del ingreso  |
| estado  | estado\_documento  | No  | DEFAULT 'en\_confeccion'  | Estado; solo avanza (RN-10, trigger)  |
| cod\_transportista  | INTEGER  | No  | FK → transportista  | Transportista que trasladó; debe cubrir la localidad del depósito (trigger)  |
| cuit\_bodega  | cuit  | No  | FK → bodega  | Bodega de origen  |

### renglon\_ingreso 

Vinos de cada ingreso. 

| Columna  | Tipo  | Nulos  | Restricciones  | Descripción  |
| --- | --- | --- | --- | --- |
| cod\_ingreso  | INTEGER  | No  | PK(cod\_ingreso, cod\_vino), FK → ingreso ON DELETE CASCADE  | Ingreso  |
| cod\_vino  | INTEGER  | No  | PK(cod\_ingreso, cod\_vino), FK → vino  | Vino ingresado; debe ser de la bodega de origen (trigger)  |
| cantidad  | INTEGER  | No  | CHECK (cantidad \> 0)  | Botellas ingresadas  |

### transferencia 

Cabecera de cada pedido de una sala al depósito. 

| Columna  | Tipo  | Nulos  | Restricciones  | Descripción  |
| --- | --- | --- | --- | --- |
| nro  | INTEGER  | No  | PK, IDENTITY  | Número de solicitud  |
| id\_sala  | INTEGER  | No  | FK → sala\_venta  | Sala solicitante  |
| fecha\_confeccion  | DATE  | No  | DEFAULT CURRENT\_DATE  | Fecha actual, no modificable (RN-11, trigger)  |
| estado  | estado\_documento  | No  | DEFAULT 'en\_confeccion'  | Estado; solo avanza (RN-11, trigger)  |

### renglon\_transferencia 

Vinos de cada transferencia. 

| Columna  | Tipo  | Nulos  | Restricciones  | Descripción  |
| --- | --- | --- | --- | --- |
| nro  | INTEGER  | No  | PK(nro, cod\_vino), FK → transferencia ON DELETE CASCADE  | Transferencia  |
| cod\_vino  | INTEGER  | No  | PK(nro, cod\_vino), FK → vino  | Vino solicitado  |
| cantidad  | INTEGER  | No  | CHECK (cantidad \> 0)  | Botellas solicitadas  |

### stock\_sala 

Stock de cada vino en cada sala. 

| Columna  | Tipo  | Nulos  | Restricciones  | Descripción  |
| --- | --- | --- | --- | --- |
| id\_sala  | INTEGER  | No  | PK(id\_sala, cod\_vino), FK → sala\_venta  | Sala  |
| cod\_vino  | INTEGER  | No  | PK(id\_sala, cod\_vino), FK → vino  | Vino  |
| cantidad  | INTEGER  | No  | DEFAULT 0, CHECK (cantidad \>= 0)  | Botellas disponibles (RN-09)  |

### stock\_deposito 

Stock de cada vino en el depósito central. 

| Columna  | Tipo  | Nulos  | Restricciones  | Descripción  |
| --- | --- | --- | --- | --- |
| cod\_vino  | INTEGER  | No  | PK, FK → vino  | Vino  |
| cantidad  | INTEGER  | No  | DEFAULT 0, CHECK (cantidad \>= 0)  | Botellas disponibles en el depósito  |

Todas las restricciones listadas que no son PK ni FK (UNIQUE, CHECK, DEFAULT) se implementan en 002\_constraints.sql (etapa 2); 001\_esquema.sql crea tipos, tablas, PK y FK. 
