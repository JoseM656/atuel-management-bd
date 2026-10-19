-- Datos mínimos para probar las reglas (se confirman con COMMIT)
BEGIN;

INSERT INTO departamento (nombre, provincia) VALUES ('San Rafael', 'Mendoza');

INSERT INTO localidad (nombre, provincia, codigo_postal, cuit_encargado) VALUES
  ('San Rafael',     'Mendoza', '5600', '20111111111'),   -- id 1
  ('General Alvear', 'Mendoza', '5620', '20222222222');   -- id 2

INSERT INTO deposito (id_localidad) VALUES (1);

INSERT INTO sala_venta (calle, numero, dia_cierre, id_localidad) VALUES
  ('Av. Mitre', 100, 'lunes', 1),     -- sala 1
  ('Alvear O.', 200, 'martes', 2);    -- sala 2

INSERT INTO empleado (cuit, nombre, fecha_ingreso, salario, id_sala) VALUES
  ('20111111111', 'Ana Pérez', '2018-01-01', 500000, 1),
  ('20222222222', 'Juan Gómez', '2023-01-01', 400000, 2);

INSERT INTO cepa (nombre, tipo) VALUES
  ('Malbec', 'tinta'), ('Cabernet Sauvignon', 'tinta'), ('Chardonnay', 'blanca');

INSERT INTO maridaje (nombre, temperatura_servicio) VALUES
  ('Carnes rojas', 17), ('Quesos duros', 16);

INSERT INTO bodega (cuit, razon_social, domicilio) VALUES
  ('30111111111', 'Bodega Uno', 'Calle 1'),
  ('30222222222', 'Bodega Dos', 'Calle 2');

INSERT INTO vino (nombre, tipo, anada, volumen_ml, graduacion, precio, cuit_bodega) VALUES
  ('Malbec Reserva',   'tinto',  2021, 750, 14.0, 12500, '30111111111'),  -- vino 1
  ('Chardonnay Joven', 'blanco', 2023, 750, 12.5,  8000, '30111111111'),  -- vino 2
  ('Tinto Dos',        'tinto',  2022, 750, 13.0,  9000, '30222222222');  -- vino 3

INSERT INTO composicion (cod_vino, id_cepa, porcentaje) VALUES
  (1, 1, 85), (1, 2, 15), (2, 3, 100), (3, 1, 100);

INSERT INTO vino_maridaje (cod_vino, id_maridaje) VALUES (1, 1), (1, 2), (2, 2), (3, 1);

INSERT INTO finca (nombre, superficie_ha, id_departamento) VALUES ('Finca A', 50, 1);
INSERT INTO parcela (id_finca, nro_parcela, superficie_ha, anio_plantacion, id_cepa)
VALUES (1, 1, 10, 2010, 1);

INSERT INTO transportista (razon_social, cuit, email, telefono, domicilio) VALUES
  ('Trans Sur',   '30333333333', 'sur@mail.com',   '111', 'Dom 1'),  -- cubre depósito
  ('Trans Norte', '30444444444', 'norte@mail.com', '222', 'Dom 2');  -- no cubre
INSERT INTO transportista_localidad (cod_transportista, id_localidad) VALUES (1, 1);

-- Clientes: 1 socio, 2 distribuidor, 3 exportador (descuento lo pisa el trigger)
INSERT INTO cliente (nombre_razon_social, tipo_doc, nro_doc, direccion, id_localidad, tipo, descuento) VALUES
  ('Socio Uno',  'DNI',  '30000001',    'Dir 1', 1, 'socio',        0),
  ('Distrib SA', 'CUIT', '30555555555', 'Dir 2', 1, 'distribuidor', 0),
  ('Export SA',  'CUIT', '30666666666', 'Dir 3', 1, 'exportador',   0);
INSERT INTO socio (id_cliente) VALUES (1);
INSERT INTO distribuidor (id_cliente, zona_cobertura, nro_habilitacion) VALUES (2, 'Sur', 'HAB-1');
INSERT INTO exportador (id_cliente, pais_destino) VALUES (3, 'Chile');

INSERT INTO stock_deposito (cod_vino, cantidad) VALUES (1, 100), (2, 50);
INSERT INTO stock_sala (id_sala, cod_vino, cantidad) VALUES (1, 1, 5), (1, 2, 1);

-- Ingreso 1: en confección. Ingreso 2: terminado.
INSERT INTO ingreso (cod_transportista, cuit_bodega) VALUES (1, '30111111111'), (1, '30111111111');
INSERT INTO renglon_ingreso (cod_ingreso, cod_vino, cantidad) VALUES (1, 1, 10), (2, 2, 5);
UPDATE ingreso SET estado = 'terminado' WHERE cod_ingreso = 2;

-- Transferencia 1: en confección. 2: terminada SIN stock suficiente (vino 2 x 500). 3: terminada OK.
INSERT INTO transferencia (id_sala) VALUES (1), (1), (2);
INSERT INTO renglon_transferencia (nro, cod_vino, cantidad) VALUES
  (1, 1, 10), (2, 1, 10), (2, 2, 500), (3, 2, 5);
UPDATE transferencia SET estado = 'terminado' WHERE nro IN (2, 3);

COMMIT;
