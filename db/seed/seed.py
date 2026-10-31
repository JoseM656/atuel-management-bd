#!/usr/bin/env python3
"""
seed.py - Script de carga masiva y reproducible para Bodegas del Atuel.
Cumple con las Issues #26, #27, #28, #29 y #30 (Etapa 3).
"""

import argparse
import csv
import os
import random
import sys
import time
from datetime import date, datetime, timedelta, timezone
from decimal import Decimal, ROUND_HALF_UP

from faker import Faker
import psycopg

# -----------------------------------------------------------------------------
# Constantes y configuraciones por defecto
# -----------------------------------------------------------------------------
DEFAULT_SEED = 42
DEFAULT_FECHA_REF = "2026-10-30"
DEFAULT_DSN = os.environ.get(
    "DATABASE_URL", "postgresql://postgres:postgres@localhost:5433/atuel"
)

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))

TABLAS_ORDEN_TOPOLOGICO = [
    # Nivel 1: Raíces sin FK
    "departamento",
    "cepa",
    "maridaje",
    "bodega",
    "transportista",
    # Nivel 2: Ubicación, personal y cobertura
    "localidad",
    "deposito",
    "sala_venta",
    "empleado",
    "finca",
    "transportista_localidad",
    # Nivel 3: Producción base y supertipo
    "parcela",
    "vino",
    "cliente",
    # Nivel 4: Subtipos, documentos y N:M de vino
    "socio",
    "distribuidor",
    "exportador",
    "lote_uva",
    "composicion",
    "vino_maridaje",
    "auditoria_precio",
    "ingreso",
    "transferencia",
    # Nivel 5: Detalles y ventas cabecera
    "analisis_calidad",
    "permiso_exportacion",
    "renglon_ingreso",
    "renglon_transferencia",
    "comprobante",
    # Nivel 6: Renglones de venta y saldos de stock
    "renglon_comprobante",
    "stock_deposito",
    "stock_sala",
]

TABLAS_CON_IDENTITY = [
    ("departamento", "id_departamento"),
    ("localidad", "id_localidad"),
    ("sala_venta", "id_sala"),
    ("cepa", "id_cepa"),
    ("finca", "id_finca"),
    ("lote_uva", "nro_lote"),
    ("analisis_calidad", "id_analisis"),
    ("vino", "cod_vino"),
    ("maridaje", "id_maridaje"),
    ("auditoria_precio", "id_auditoria"),
    ("cliente", "id_cliente"),
    ("comprobante", "nro"),
    ("transportista", "cod_transportista"),
    ("ingreso", "cod_ingreso"),
    ("transferencia", "nro"),
]

DIAS_SEMANA = [
    "lunes",
    "martes",
    "miercoles",
    "jueves",
    "viernes",
    "sabado",
    "domingo",
]


def leer_csv(nombre_archivo):
    ruta = os.path.join(SCRIPT_DIR, nombre_archivo)
    with open(ruta, mode="r", encoding="utf-8") as f:
        return list(csv.DictReader(f))


def format_cuit(num):
    return f"{num:011d}"


# -----------------------------------------------------------------------------
# Generador de datos determinista en memoria
# -----------------------------------------------------------------------------
def generar_dataset(seed, fecha_ref_str):
    rng = random.Random(seed)
    fake = Faker("es_AR")
    Faker.seed(seed)
    fake.seed_instance(seed)

    fecha_ref = datetime.strptime(fecha_ref_str, "%Y-%m-%d").date()

    # Pools deterministas generados con Faker para acelerar 20k clientes
    pool_nombres = [fake.name() for _ in range(600)]
    pool_apellidos = [fake.last_name() for _ in range(200)]
    pool_empresas = [fake.company() for _ in range(600)]
    pool_calles = [fake.street_name() for _ in range(300)]
    pool_ciudades = [fake.city() for _ in range(120)]
    pool_paises = [fake.country() for _ in range(80)]

    # 1. Catálogos CSV (Nivel 1)
    csv_deptos = leer_csv("departamentos.csv")
    csv_cepas = leer_csv("cepas.csv")
    csv_maridajes = leer_csv("maridajes.csv")
    csv_localidades = leer_csv("localidades.csv")
    csv_bodegas = leer_csv("bodegas.csv")
    csv_transportistas = leer_csv("transportistas.csv")
    csv_tipos_pres = leer_csv("tipos_vino_presentaciones.csv")

    departamentos = [
        (i, d["nombre"].strip(), d["provincia"].strip())
        for i, d in enumerate(csv_deptos, start=1)
    ]

    cepas = []
    cepas_activas_ids = []
    for i, c in enumerate(csv_cepas, start=1):
        cepas.append((i, c["nombre"].strip(), c["tipo"].strip()))
        if c.get("activa_en_produccion", "true").strip().lower() == "true":
            cepas_activas_ids.append(i)

    maridajes = [
        (i, m["nombre"].strip(), Decimal(m["temperatura_servicio"].strip()))
        for i, m in enumerate(csv_maridajes, start=1)
    ]

    bodegas = []
    bodegas_cuits = []
    for b in csv_bodegas:
        cuit = b["cuit"].strip()
        bodegas.append((cuit, b["razon_social"].strip(), b["domicilio"].strip()))
        bodegas_cuits.append(cuit)

    transportistas = [
        (
            i,
            t["razon_social"].strip(),
            t["cuit"].strip(),
            t["email"].strip(),
            t["telefono"].strip(),
            t["domicilio"].strip(),
        )
        for i, t in enumerate(csv_transportistas, start=1)
    ]

    # 2. Nivel 2: Ubicación, personal, depósito, fincas y cobertura
    salas = []
    dia_cierre_sala_idx = {}
    for i in range(1, 25):
        loc_id = i
        dia = "lunes" if i % 2 == 0 else "miercoles"  # Para U4
        salas.append((i, f"Av. Principal {i * 10}", i * 100 + 15, dia, loc_id))
        dia_cierre_sala_idx[i] = DIAS_SEMANA.index(dia)

    extra_locs = [1, 2, 4, 8, 10, 11, 14, 17, 19, 21, 23, 24]
    for idx, loc_id in enumerate(extra_locs, start=25):
        dia = DIAS_SEMANA[idx % len(DIAS_SEMANA)]
        salas.append((idx, f"Calle Comercial {idx}", idx * 50 + 20, dia, loc_id))
        dia_cierre_sala_idx[idx] = DIAS_SEMANA.index(dia)

    empleados = []
    empleados_cuits = []
    cuit_base_emp = 20300000010

    for i in range(1, 25):
        cuit = format_cuit(cuit_base_emp + i)
        empleados_cuits.append(cuit)
        f_ing = (
            fecha_ref - timedelta(days=365 * 6 + i * 10)
            if i <= 12
            else fecha_ref - timedelta(days=365 * 3 + i * 5)
        )
        salario = Decimal("650000.00") + Decimal(i * 15000)
        empleados.append((cuit, pool_nombres[i % len(pool_nombres)], f_ing, salario, i))

    for i in range(25, 121):
        cuit = format_cuit(cuit_base_emp + i)
        empleados_cuits.append(cuit)
        sala_id = ((i - 25) % 36) + 1
        if sala_id == 5:
            f_ing = fecha_ref - timedelta(days=rng.randint(60, 400))  # < 2 años (D3)
        elif i % 3 == 0:
            f_ing = fecha_ref - timedelta(days=365 * 6 + rng.randint(30, 300))  # > 5 años (U2)
        else:
            f_ing = fecha_ref - timedelta(days=365 * 3 + rng.randint(10, 200))
        salario = Decimal("550000.00") + Decimal(rng.randint(10, 80) * 10000)
        empleados.append(
            (cuit, pool_nombres[i % len(pool_nombres)], f_ing, salario, sala_id)
        )

    localidades = [
        (
            i,
            loc["nombre"].strip(),
            loc["provincia"].strip(),
            loc["codigo_postal"].strip(),
            empleados_cuits[i - 1],
        )
        for i, loc in enumerate(csv_localidades, start=1)
    ]

    deposito = [(1, 1)]

    fincas = []
    for i in range(1, 41):
        depto_id = ((i - 1) % len(departamentos)) + 1
        sup = Decimal(f"{rng.randint(35, 180)}.00")
        fincas.append((i, f"Finca {pool_apellidos[i % len(pool_apellidos)]} {i}", sup, depto_id))

    # Cobertura transportista_localidad (60 filas exactas)
    # Todos cubren id_localidad = 1 (San Rafael, RI-05).
    # Transportista 15 NO cubre id_localidad = 2 (General Alvear) para I1.
    transportista_localidad = []
    for t_id in range(1, 16):
        transportista_localidad.append((t_id, 1))
        if t_id == 15:
            transportista_localidad.append((15, 3))
        else:
            if t_id in (1, 2, 8):
                transportista_localidad.append((t_id, 2))
            for loc_id in [(t_id * 2) % 24 + 1, (t_id * 3) % 24 + 1]:
                if loc_id not in (1, 2) and (t_id, loc_id) not in transportista_localidad:
                    transportista_localidad.append((t_id, loc_id))

    curr_t = 1
    loc_cursor = 3
    while len(transportista_localidad) < 60:
        if not (curr_t == 15 and loc_cursor == 2):
            if (curr_t, loc_cursor) not in transportista_localidad:
                transportista_localidad.append((curr_t, loc_cursor))
        curr_t = (curr_t % 14) + 1
        loc_cursor = (loc_cursor % 23) + 2

    # 3. Nivel 3: Parcelas (650 filas), Vinos (400 filas), Clientes (20.000 filas)
    parcelas = []
    nro_tot = 0
    for f_id in range(1, 41):
        cant_p = 17 if f_id <= 10 else 16
        for p_idx in range(1, cant_p + 1):
            nro_tot += 1
            sup_p = Decimal(f"{rng.randint(2, 10)}.{rng.choice([0, 25, 50, 75]):02d}")
            anio_p = rng.randint(1995, 2020)
            cepa_id = cepas_activas_ids[(nro_tot - 1) % len(cepas_activas_ids)]
            parcelas.append((f_id, p_idx, sup_p, anio_p, cepa_id))

    # Vinos (400 filas: 20 por cada una de las 20 bodegas)
    # En Bodega 1 (b_idx=0): todos los 20 vinos tienen añada 2018..2020 para poder venderse desde 2021 y cubrir S12.
    # En Bodegas 2..20: v_idx 1..12 tienen añada 2018..2020 (ingresos desde 2021-01-05, participan en salas);
    #                   v_idx 13..20 tienen añada 2021..2024 (ingresos desde 2025-01-10, en stock_deposito).
    nombres_vino = [
        "Malbec Reserva",
        "Gran Malbec",
        "Cabernet Clásico",
        "Syrah Gran Reserva",
        "Bonarda Roble",
        "Tempranillo Crianza",
        "Chardonnay Fumé",
        "Sauvignon Blanc Estate",
        "Torrontés Riojano",
        "Corte de Altura",
        "Assemblage Especial",
        "Blend de Blancas",
        "Rosado de Malbec",
        "Espumante Extra Brut",
        "Espumante Brut Nature",
        "Pinot Noir Selección",
        "Merlot Clásico",
        "Chenin Blanc Dulce Natural",
        "Semillón Reserva",
        "Gran Corte Icono",
    ]

    vinos = []
    vinos_elegibles_salas = []
    for b_idx, cuit_bodega in enumerate(bodegas_cuits):
        for v_idx in range(1, 21):
            cod_vino = b_idx * 20 + v_idx
            nombre_base = nombres_vino[v_idx - 1]
            if cod_vino == 1:
                t_vino = "tinto"
                anada = 2020
                vol = 750
                grad = Decimal("14.50")
                precio = Decimal("12500.00")
                vinos_elegibles_salas.append(cod_vino)
            else:
                if b_idx == 0 or v_idx <= 12:
                    anada = 2018 + (cod_vino % 3)  # 2018..2020
                    vinos_elegibles_salas.append(cod_vino)
                else:
                    anada = 2021 + (cod_vino % 4)  # 2021..2024

                tp = csv_tipos_pres[(cod_vino + v_idx) % len(csv_tipos_pres)]
                t_vino = tp["tipo"].strip()
                vol = int(tp["volumen_ml"].strip())
                if t_vino == "tinto" and v_idx % 2 == 0:
                    grad = Decimal(f"{rng.randint(14, 15)}.{rng.choice([0, 25, 50, 75]):02d}")
                else:
                    grad = Decimal(f"{rng.randint(11, 13)}.{rng.choice([0, 25, 50, 75]):02d}")
                precio_base = int(float(tp["precio_base_sugerido"].strip()))
                precio = Decimal(precio_base + ((cod_vino % 7) - 2) * 400)
                if precio < Decimal("1500.00"):
                    precio = Decimal("1500.00")

            # Nombre único por (nombre, anada, volumen_ml)
            vinos.append(
                (
                    cod_vino,
                    f"{nombre_base} B{b_idx + 1}",
                    t_vino,
                    anada,
                    vol,
                    grad,
                    precio,
                    cuit_bodega,
                )
            )

    # 4. Nivel 4: Composición (750 filas exactas), Vino-Maridaje (900 filas exactas), Auditoría Precio (400)
    # Composición: 150 vinos x 3 cepas (450) + 50 vinos x 2 cepas (100) + 200 vinos x 1 cepa (200) = 750 filas
    composicion = []
    for cod_vino in range(1, 401):
        if cod_vino <= 150:
            c1 = cepas_activas_ids[(cod_vino * 2) % len(cepas_activas_ids)]
            c2 = cepas_activas_ids[(cod_vino * 2 + 1) % len(cepas_activas_ids)]
            c3 = cepas_activas_ids[(cod_vino * 2 + 2) % len(cepas_activas_ids)]
            composicion.append((cod_vino, c1, Decimal("60.00")))
            composicion.append((cod_vino, c2, Decimal("25.00")))
            composicion.append((cod_vino, c3, Decimal("15.00")))
        elif cod_vino <= 200:
            c1 = cepas_activas_ids[(cod_vino * 3) % len(cepas_activas_ids)]
            c2 = cepas_activas_ids[(cod_vino * 3 + 1) % len(cepas_activas_ids)]
            composicion.append((cod_vino, c1, Decimal("70.00")))
            composicion.append((cod_vino, c2, Decimal("30.00")))
        else:
            c1 = cepas_activas_ids[cod_vino % len(cepas_activas_ids)]
            composicion.append((cod_vino, c1, Decimal("100.00")))

    # Vino-Maridaje: 100 vinos x 3 maridajes (300) + 300 vinos x 2 maridajes (600) = 900 filas
    vino_maridaje = []
    for cod_vino in range(1, 401):
        m1 = (cod_vino % 12) + 1
        m2 = ((cod_vino + 3) % 12) + 1
        vino_maridaje.append((cod_vino, m1))
        vino_maridaje.append((cod_vino, m2))
        if cod_vino <= 100:
            m3 = ((cod_vino + 7) % 12) + 1
            vino_maridaje.append((cod_vino, m3))

    # Auditoría de precio (400 filas)
    tz_ar = timezone(timedelta(hours=-3))
    fecha_cambio_dt = datetime(2025, 6, 1, 10, 0, 0, tzinfo=tz_ar)
    fecha_cambio_date = date(2025, 6, 1)
    auditoria_precio = []
    precio_anterior_dict = {}
    precio_actual_dict = {}
    tipo_vino_dict = {}

    for cod_vino, nombre, t_vino, anada, vol, grad, precio_act, cuit_bod in vinos:
        p_ant = precio_act - Decimal("800.00")
        if p_ant <= Decimal("0.00"):
            p_ant = Decimal("1000.00")
        precio_anterior_dict[cod_vino] = p_ant
        precio_actual_dict[cod_vino] = precio_act
        tipo_vino_dict[cod_vino] = t_vino
        auditoria_precio.append(
            (cod_vino, cod_vino, p_ant, precio_act, fecha_cambio_dt, "propietario")
        )

    # Lotes de uva (3.250 filas: 650 parcelas x 5 campañas 2022..2026) y Análisis (6.500 filas)
    lotes_uva = []
    analisis_calidad = []
    nro_lote = 0
    id_analisis = 0

    for anio in range(2022, 2027):
        for f_id, p_nro, sup_p, anio_p, c_id in parcelas:
            nro_lote += 1
            mes_c = ((nro_lote % 3) + 2)  # 2, 3 o 4 (feb a abr)
            dia_c = ((nro_lote % 25) + 1)
            f_cosecha = date(anio, mes_c, dia_c)
            # Varianza por parcela para S10 (rendimiento kg/ha respecto al promedio de su finca)
            factor_rend = Decimal(8500 + (p_nro * 450))
            kg = (sup_p * factor_rend).quantize(Decimal("0.01"), rounding=ROUND_HALF_UP)
            b_cuit = bodegas_cuits[(f_id + p_nro) % len(bodegas_cuits)]
            lotes_uva.append((nro_lote, f_id, p_nro, f_cosecha, kg, b_cuit))

            for a_idx in (1, 2):
                id_analisis += 1
                f_an = f_cosecha + timedelta(days=a_idx * 3)
                brix = Decimal(f"{21 + (id_analisis % 5)}.{(id_analisis * 3) % 10}")
                ph = Decimal(f"3.{20 + (id_analisis % 60):02d}")
                acidez = Decimal(f"{4 + (id_analisis % 3)}.{10 + (id_analisis % 80):02d}")
                analisis_calidad.append((id_analisis, nro_lote, f_an, brix, ph, acidez))

    # Clientes (20.000), Subtipos y Permisos de exportación (4.500)
    clientes = []
    socios = []
    distribuidores = []
    exportadores = []
    permisos_exportacion = []
    descuentos_cliente_dict = {}
    fecha_alta_cliente_dict = {}

    cod_permiso_idx = 0
    for i in range(1, 20001):
        if i <= 14000:
            tipo = "socio"
            desc = Decimal("10.00")
            if i <= 600:
                f_alta = date(2020, (i % 10) + 1, (i % 25) + 1)  # > 5 años (D1, D4)
            else:
                f_alta = date(2021, 1, 1) + timedelta(days=(i * 3) % 1400)
            tipo_doc = "DNI"
            nro_doc = f"{20000000 + i}"
            nombre = pool_nombres[i % len(pool_nombres)]
            socios.append((i, tipo))
        elif i <= 18000:
            tipo = "distribuidor"
            desc = Decimal("20.00")
            f_alta = date(2021, 1, 1) + timedelta(days=(i * 5) % 1400)
            tipo_doc = "CUIT"
            nro_doc = format_cuit(30800000000 + i)
            nombre = f"{pool_empresas[i % len(pool_empresas)]} #{i}"
            zona = f"Zona {pool_ciudades[i % len(pool_ciudades)]}"
            hab = f"HAB-{10000 + i}"
            distribuidores.append((i, tipo, zona, hab))
        else:
            tipo = "exportador"
            f_alta = date(2021, 1, 1) + timedelta(days=(i * 7) % 1200)
            tipo_doc = "CUIT"
            nro_doc = format_cuit(30800000000 + i)
            nombre = f"Exportadora {pool_empresas[i % len(pool_empresas)]} #{i}"
            pais = pool_paises[i % len(pool_paises)]
            exportadores.append((i, tipo, pais))

            if i <= 18500:
                cant_perm = 4
                desc = Decimal("35.00")  # RI-06 (> 3 permisos)
            elif i <= 19000:
                cant_perm = 3
                desc = Decimal("30.00")
            else:
                cant_perm = 1
                desc = Decimal("30.00")

            for p_idx in range(1, cant_perm + 1):
                cod_permiso_idx += 1
                cod_p = f"EXP-{i}-{cod_permiso_idx}"
                f_emision = f_alta + timedelta(days=p_idx * 25)
                f_venc = f_emision + timedelta(days=365)
                permisos_exportacion.append((cod_p, i, f_emision, f_venc))

        direccion = f"{pool_calles[i % len(pool_calles)]} {(i * 13) % 4500 + 10}"
        loc_id = ((i - 1) % 24) + 1

        clientes.append((i, nombre, tipo_doc, nro_doc, direccion, loc_id, f_alta, tipo, desc))
        descuentos_cliente_dict[i] = desc
        fecha_alta_cliente_dict[i] = f_alta

    # -------------------------------------------------------------------------
    # 5. Algoritmo Bottom-Up de Stock, Ventas, Transferencias e Ingresos
    # -------------------------------------------------------------------------
    # Surtido de 40 vinos por sala (de vinos_elegibles_salas que tienen añada 2018..2020)
    # Sala 1 incluye todos los 20 vinos de Bodega 1 (cod_vino 1..20) para S12.
    # Todas las 36 salas incluyen cod_vino 1, 2, 3 para S2 (división relacional).
    catalogo_sala = {}
    otros_elegibles = [v for v in vinos_elegibles_salas if v > 3]

    for s_id in range(1, 37):
        if s_id == 1:
            vinos_s = list(range(1, 21)) + otros_elegibles[17:37]
        else:
            vinos_s = [1, 2, 3]
            start_pos = ((s_id - 1) * 6) % len(otros_elegibles)
            for k in range(37):
                vinos_s.append(otros_elegibles[(start_pos + k) % len(otros_elegibles)])
        catalogo_sala[s_id] = sorted(vinos_s)

    # 150.000 comprobantes y 500.000 renglones exactos:
    # Comprobantes 1..4: Cliente 200 compra en Sala 1 los 20 vinos de Bodega 1 (4 comp x 5 reng = 20 renglones) -> S12
    # Comprobantes 5..50000 (49.996 comp): 5 renglones c/u = 249.980 renglones
    # Comprobantes 50001..100000 (50.000 comp): 3 renglones c/u = 150.000 renglones
    # Comprobantes 100001..150000 (50.000 comp): 2 renglones c/u = 100.000 renglones
    # Total = 20 + 249.980 + 150.000 + 100.000 = 500.000 renglones!
    # Clientes 1..150 quedan SIN compras (socios antiguos y de todas las localidades para D4 y D6, además de no comprar tintos para S12).
    comprobantes = []
    renglones_comprobante = []
    demanda_sala = {(s_id, v_id): 0 for s_id in range(1, 37) for v_id in catalogo_sala[s_id]}

    fecha_inicio_ventas = date(2021, 3, 1)
    dias_rango_ventas = (fecha_ref - fecha_inicio_ventas).days  # ~2069 días

    for nro_c in range(1, 150001):
        if nro_c <= 4:
            c_id = 200
            s_id = 1
            cant_reng = 5
            f_comp = date(2024, 5, 10 + nro_c)
            vinos_elegidos = list(range((nro_c - 1) * 5 + 1, nro_c * 5 + 1))
        else:
            if nro_c <= 50000:
                cant_reng = 5
            elif nro_c <= 100000:
                cant_reng = 3
            else:
                cant_reng = 2

            s_id = ((nro_c - 5) % 36) + 1

            # Selección de cliente
            if nro_c <= 1200:
                # Socios con > 5 años de antigüedad (151..599) y ventas de 2021 (> 5 años para D1)
                c_id = 151 + (nro_c % 440)
                f_comp = date(2021, 3, 5) + timedelta(days=(nro_c % 180))
            else:
                c_id = 300 + ((nro_c * 11) % 19701)
                f_alta = fecha_alta_cliente_dict[c_id]
                # Distribución temporal: última semana (S3), último trimestre (S8) e historial
                mod_t = nro_c % 20
                if mod_t == 0:
                    f_comp = fecha_ref - timedelta(days=(nro_c % 6))  # Última semana (S3)
                elif mod_t <= 4:
                    f_comp = fecha_ref - timedelta(days=7 + (nro_c % 80))  # Último trimestre (S8)
                else:
                    f_comp = fecha_inicio_ventas + timedelta(days=(nro_c * 17) % dias_rango_ventas)

                if f_comp < f_alta:
                    f_comp = f_alta + timedelta(days=1)
                if f_comp < fecha_inicio_ventas:
                    f_comp = fecha_inicio_ventas
                if f_comp > fecha_ref:
                    f_comp = fecha_ref

            # Evitar día de cierre de la sala
            if f_comp.weekday() == dia_cierre_sala_idx[s_id]:
                if f_comp > fecha_inicio_ventas and f_comp > fecha_alta_cliente_dict[c_id]:
                    f_comp = f_comp - timedelta(days=1)
                elif f_comp < fecha_ref:
                    f_comp = f_comp + timedelta(days=1)

            vinos_s = catalogo_sala[s_id]
            start_v = (nro_c * 3) % len(vinos_s)
            vinos_elegidos = [vinos_s[(start_v + k) % len(vinos_s)] for k in range(cant_reng)]

        pct_desc = descuentos_cliente_dict[c_id]
        es_precio_ant = f_comp < fecha_cambio_date

        subtotal_cab = Decimal("0.00")
        total_cab = Decimal("0.00")

        for v_id in vinos_elegidos:
            cant = ((nro_c + v_id) % 4) + 1
            p_unit = precio_anterior_dict[v_id] if es_precio_ant else precio_actual_dict[v_id]

            bruto_reng = Decimal(cant) * p_unit
            imp_desc = (bruto_reng * pct_desc / Decimal("100.0")).quantize(
                Decimal("0.01"), rounding=ROUND_HALF_UP
            )
            sub_reng = bruto_reng - imp_desc

            renglones_comprobante.append((nro_c, v_id, cant, p_unit, imp_desc, sub_reng))
            subtotal_cab += bruto_reng
            total_cab += sub_reng
            demanda_sala[(s_id, v_id)] += cant

        comprobantes.append((nro_c, f_comp, c_id, s_id, subtotal_cab, pct_desc, total_cab))

    # Stock final en cada sala (1.440 filas: 36 salas x 40 vinos)
    # Los primeros 32 vinos de cada sala tienen stock > 0; los últimos 8 tienen stock = 0 (para S6).
    stock_sala = []
    stock_sala_final = {}
    for s_id in range(1, 37):
        for idx_v, v_id in enumerate(catalogo_sala[s_id]):
            if idx_v >= 32:
                s_fin = 0
            else:
                s_fin = ((s_id + v_id) % 80) + 20  # >= 20 botellas
            stock_sala.append((s_id, v_id, s_fin))
            stock_sala_final[(s_id, v_id)] = s_fin

    # -------------------------------------------------------------------------
    # Transferencias (2.500 filas: 2.350 procesadas, 75 terminadas, 75 en_confeccion)
    # Renglones de transferencia: 10.000 filas (4 por transferencia)
    # -------------------------------------------------------------------------
    # Para que el saldo acumulado diario NUNCA sea negativo:
    # Todas las transferencias procesadas previas a las ventas ocurren entre 2021-02-05 y 2021-02-25
    # (antes del primer comprobante del 2021-03-01) y cubren el 100% de demanda_sala[(s_id, v_id)]!
    # Y en la última aparición de los grupos con stock_sala_final > 0, la transferencia puede ocurrir
    # en los últimos 15 días (2026-10-18..2026-10-28, para S4) aportando únicamente parte de stock_sala_final!
    transferencias = []
    renglones_transferencia = []
    demanda_deposito = {v_id: 0 for v_id in range(1, 401)}
    nro_transf = 0

    for s_id in range(1, 37):
        vinos_s = catalogo_sala[s_id]
        grupos_s = [vinos_s[i : i + 4] for i in range(0, 40, 4)]  # 10 grupos de 4 vinos
        cant_transf_sala = 66 if s_id <= (2350 % 36) else 65

        # Contamos cuántas veces aparece cada grupo (0..9) en cant_transf_sala
        apariciones_grupo = {g_idx: [] for g_idx in range(10)}
        for t_local in range(cant_transf_sala):
            apariciones_grupo[t_local % 10].append(t_local)

        for t_local in range(cant_transf_sala):
            nro_transf += 1
            g_idx = t_local % 10
            grupo = grupos_s[g_idx]
            lista_ap = apariciones_grupo[g_idx]
            pos_en_grupo = lista_ap.index(t_local)
            total_ap_grupo = len(lista_ap)

            # Si es la última aparición del grupo 0 (que contiene cod_vino 1, 2, 3 y tiene stock_final >= 20),
            # la fechamos en los últimos 15 días para que S4 tenga transferencias recientes en las salas!
            es_ultima_ap_grupo_0 = (g_idx == 0 and pos_en_grupo == total_ap_grupo - 1)
            if es_ultima_ap_grupo_0:
                f_tr = fecha_ref - timedelta(days=(s_id % 12) + 1)  # Últimos 15 días (S4)
            else:
                f_tr = date(2021, 2, 5) + timedelta(days=(t_local % 20))

            transferencias.append((nro_transf, s_id, f_tr, "procesado"))

            for v_id in grupo:
                dem_v = demanda_sala[(s_id, v_id)]
                fin_v = stock_sala_final[(s_id, v_id)]
                tot_v = dem_v + fin_v

                if g_idx == 0:
                    # En las primeras (total_ap_grupo - 1) entregas (en feb 2021) se entrega todo dem_v + (fin_v - 15)
                    # En la última entrega (oct 2026, S4) se entregan 15 + s_id botellas (parte del stock final)
                    reserva_s4 = 10 + (s_id % 10)  # <= 19 <= fin_v (que es >= 20)
                    tot_feb = tot_v - reserva_s4
                    n_feb = total_ap_grupo - 1
                    base_q = tot_feb // n_feb
                    rem_q = tot_feb % n_feb
                    if pos_en_grupo < n_feb:
                        cant = base_q + (1 if pos_en_grupo < rem_q else 0)
                    else:
                        cant = reserva_s4
                else:
                    # Todas las entregas ocurren en feb 2021 (antes de cualquier venta)
                    base_q = tot_v // total_ap_grupo
                    rem_q = tot_v % total_ap_grupo
                    cant = base_q + (1 if pos_en_grupo < rem_q else 0)

                demanda_deposito[v_id] += cant
                renglones_transferencia.append((nro_transf, v_id, cant))

    # 75 transferencias 'terminado' y 75 'en_confeccion' (con fecha_confeccion = fecha_ref)
    for i in range(1, 76):
        nro_transf += 1
        s_id = ((i - 1) % 36) + 1
        transferencias.append((nro_transf, s_id, fecha_ref, "terminado"))
        for v_id in catalogo_sala[s_id][:4]:
            renglones_transferencia.append((nro_transf, v_id, 24))

    for i in range(1, 76):
        nro_transf += 1
        s_id = ((i + 10) % 36) + 1
        transferencias.append((nro_transf, s_id, fecha_ref, "en_confeccion"))
        for v_id in catalogo_sala[s_id][4:8]:
            renglones_transferencia.append((nro_transf, v_id, 12))

    # -------------------------------------------------------------------------
    # Stock Depósito (400 filas) e Ingresos (1.500 filas: 1.400 procesados, 50 terminados, 50 en_confeccion)
    # Renglones de ingreso: 6.000 filas (4 por ingreso)
    # -------------------------------------------------------------------------
    stock_deposito = []
    stock_deposito_final = {}
    for v_id in range(1, 401):
        s_dep = 250 + ((v_id * 7) % 350)  # Entre 250 y 600 botellas (> 0 para todos los vinos)
        stock_deposito.append((v_id, s_dep))
        stock_deposito_final[v_id] = s_dep

    ingresos = []
    renglon_ingreso = []
    cod_ingreso = 0

    for b_idx, cuit_bodega in enumerate(bodegas_cuits):
        vinos_bodega = list(range(b_idx * 20 + 1, b_idx * 20 + 21))
        grupos_bodega = [vinos_bodega[i : i + 4] for i in range(0, 20, 4)]  # 5 grupos de 4 vinos

        # 70 ingresos procesados por bodega -> 14 apariciones exactas por cada uno de los 5 grupos
        for ing_local in range(70):
            cod_ingreso += 1
            g_idx = ing_local % 5
            pos_en_grupo = ing_local // 5  # 0..13 (14 apariciones)
            grupo = grupos_bodega[g_idx]

            # Determinamos fecha del ingreso:
            # Para grupos que se transfieren en feb 2021 (todos los de Bodega 1, y g_idx 0,1,2 del resto):
            # Las primeras 12 apariciones (pos 0..11) ocurren en enero 2021 (2021-01-05..2021-01-25),
            # cubriendo el 100% de demanda_deposito[v] + parte de stock_deposito_final[v]!
            # La aparición 12 ocurre en el último trimestre (2026-09-10, I1) y la 13 en el último mes (2026-10-12, S7).
            # Para g_idx 3,4 de Bodegas 2..20 (que tienen añada 2021..2024 y demanda_deposito == 0):
            # Sus ingresos ocurren desde 2025-01-10 hasta 2026-10-12 (>= make_date(anada+1, 1, 1)).
            es_grupo_reciente = (b_idx > 0 and g_idx >= 3)

            if pos_en_grupo == 12:
                f_ing = fecha_ref - timedelta(days=45)  # Último trimestre (I1)
            elif pos_en_grupo == 13:
                f_ing = fecha_ref - timedelta(days=15)  # Último mes (S7)
            elif es_grupo_reciente:
                f_ing = date(2025, 1, 10) + timedelta(days=pos_en_grupo * 25)  # > 365 días para pos 0..6 (D5)
            else:
                f_ing = date(2021, 1, 5) + timedelta(days=pos_en_grupo * 2)  # Enero 2021 (antes de feb 2021 y > 365d D5)

            # Transportista: transportista 15 solo tiene 1 envío en 2021 (0 en último trimestre -> el menos activo para I1)
            if b_idx == 0 and ing_local == 0:
                t_id = 15
            elif pos_en_grupo == 13:
                # Transportista 1 domina en el último mes para S7
                t_id = 1 if (b_idx % 2 == 0) else ((b_idx % 13) + 2)
            else:
                t_id = ((b_idx + ing_local) % 14) + 1

            ingresos.append((cod_ingreso, f_ing, "procesado", t_id, cuit_bodega))

            for v_id in grupo:
                tot_ing_v = demanda_deposito[v_id] + stock_deposito_final[v_id]
                # Reservamos 40 botellas para pos 12 y 40 botellas para pos 13 (total 80 <= stock_deposito_final >= 250)
                reserva_reciente = 80
                tot_previo = tot_ing_v - reserva_reciente
                base_q = tot_previo // 12
                rem_q = tot_previo % 12
                if pos_en_grupo < 12:
                    cant = base_q + (1 if pos_en_grupo < rem_q else 0)
                else:
                    cant = 40
                renglon_ingreso.append((cod_ingreso, v_id, cant))

    # 50 ingresos 'terminado' y 50 'en_confeccion'
    for i in range(1, 51):
        cod_ingreso += 1
        b_idx = (i - 1) % 20
        cuit_b = bodegas_cuits[b_idx]
        t_id = ((i - 1) % 14) + 1
        ingresos.append((cod_ingreso, fecha_ref, "terminado", t_id, cuit_b))
        for v_id in range(b_idx * 20 + 1, b_idx * 20 + 5):
            renglon_ingreso.append((cod_ingreso, v_id, 100))

    for i in range(1, 51):
        cod_ingreso += 1
        b_idx = ((i + 5) % 20)
        cuit_b = bodegas_cuits[b_idx]
        t_id = ((i + 2) % 14) + 1
        ingresos.append((cod_ingreso, fecha_ref, "en_confeccion", t_id, cuit_b))
        for v_id in range(b_idx * 20 + 5, b_idx * 20 + 9):
            renglon_ingreso.append((cod_ingreso, v_id, 120))

    return {
        "departamento": (["id_departamento", "nombre", "provincia"], departamentos),
        "cepa": (["id_cepa", "nombre", "tipo"], cepas),
        "maridaje": (["id_maridaje", "nombre", "temperatura_servicio"], maridajes),
        "bodega": (["cuit", "razon_social", "domicilio"], bodegas),
        "transportista": (
            ["cod_transportista", "razon_social", "cuit", "email", "telefono", "domicilio"],
            transportistas,
        ),
        "localidad": (
            ["id_localidad", "nombre", "provincia", "codigo_postal", "cuit_encargado"],
            localidades,
        ),
        "deposito": (["id", "id_localidad"], deposito),
        "sala_venta": (["id_sala", "calle", "numero", "dia_cierre", "id_localidad"], salas),
        "empleado": (["cuit", "nombre", "fecha_ingreso", "salario", "id_sala"], empleados),
        "finca": (["id_finca", "nombre", "superficie_ha", "id_departamento"], fincas),
        "transportista_localidad": (
            ["cod_transportista", "id_localidad"],
            transportista_localidad,
        ),
        "parcela": (
            ["id_finca", "nro_parcela", "superficie_ha", "anio_plantacion", "id_cepa"],
            parcelas,
        ),
        "vino": (
            [
                "cod_vino",
                "nombre",
                "tipo",
                "anada",
                "volumen_ml",
                "graduacion",
                "precio",
                "cuit_bodega",
            ],
            vinos,
        ),
        "cliente": (
            [
                "id_cliente",
                "nombre_razon_social",
                "tipo_doc",
                "nro_doc",
                "direccion",
                "id_localidad",
                "fecha_alta",
                "tipo",
                "descuento",
            ],
            clientes,
        ),
        "socio": (["id_cliente", "tipo"], socios),
        "distribuidor": (
            ["id_cliente", "tipo", "zona_cobertura", "nro_habilitacion"],
            distribuidores,
        ),
        "exportador": (["id_cliente", "tipo", "pais_destino"], exportadores),
        "lote_uva": (
            ["nro_lote", "id_finca", "nro_parcela", "fecha_cosecha", "kg", "cuit_bodega"],
            lotes_uva,
        ),
        "composicion": (["cod_vino", "id_cepa", "porcentaje"], composicion),
        "vino_maridaje": (["cod_vino", "id_maridaje"], vino_maridaje),
        "auditoria_precio": (
            [
                "id_auditoria",
                "cod_vino",
                "precio_anterior",
                "precio_nuevo",
                "fecha_hora",
                "usuario",
            ],
            auditoria_precio,
        ),
        "ingreso": (
            ["cod_ingreso", "fecha", "estado", "cod_transportista", "cuit_bodega"],
            ingresos,
        ),
        "transferencia": (["nro", "id_sala", "fecha_confeccion", "estado"], transferencias),
        "analisis_calidad": (
            ["id_analisis", "nro_lote", "fecha", "brix", "ph", "acidez_total"],
            analisis_calidad,
        ),
        "permiso_exportacion": (
            ["codigo", "id_cliente", "fecha_emision", "fecha_vencimiento"],
            permisos_exportacion,
        ),
        "renglon_ingreso": (["cod_ingreso", "cod_vino", "cantidad"], renglon_ingreso),
        "renglon_transferencia": (["nro", "cod_vino", "cantidad"], renglones_transferencia),
        "comprobante": (
            [
                "nro",
                "fecha",
                "id_cliente",
                "id_sala",
                "subtotal",
                "porcentaje_descuento",
                "total",
            ],
            comprobantes,
        ),
        "renglon_comprobante": (
            [
                "nro",
                "cod_vino",
                "cantidad",
                "precio_unitario",
                "importe_descuento",
                "subtotal",
            ],
            renglones_comprobante,
        ),
        "stock_deposito": (["cod_vino", "cantidad"], stock_deposito),
        "stock_sala": (["id_sala", "cod_vino", "cantidad"], stock_sala),
    }


# -----------------------------------------------------------------------------
# Carga Masiva Transaccional
# -----------------------------------------------------------------------------
def ejecutar_carga(conn, dataset):
    t0_total = time.perf_counter()
    tiempos_por_tabla = {}

    with conn.transaction():
        with conn.cursor() as cur:
            cur.execute("SET ROLE propietario;")

            print("==> Vaciando 31 tablas (TRUNCATE CASCADE)...", flush=True)
            todas_tablas_sql = ", ".join(TABLAS_ORDEN_TOPOLOGICO)
            cur.execute(f"TRUNCATE TABLE {todas_tablas_sql} RESTART IDENTITY CASCADE;")

            print("==> Deshabilitando triggers de usuario (DISABLE TRIGGER USER)...", flush=True)
            for tabla in TABLAS_ORDEN_TOPOLOGICO:
                cur.execute(f"ALTER TABLE {tabla} DISABLE TRIGGER USER;")

            print("==> Cargando tablas con COPY ... FROM STDIN...", flush=True)
            for tabla in TABLAS_ORDEN_TOPOLOGICO:
                t0_tab = time.perf_counter()
                cols, filas = dataset[tabla]
                cols_sql = ", ".join(cols)
                query_copy = f"COPY {tabla} ({cols_sql}) FROM STDIN"

                with cur.copy(query_copy) as copy:
                    for row in filas:
                        copy.write_row(row)

                dt_tab = time.perf_counter() - t0_tab
                tiempos_por_tabla[tabla] = (len(filas), dt_tab)
                print(f"    - {tabla:25s}: {len(filas):8d} filas en {dt_tab:6.3f}s", flush=True)

            print("==> Sincronizando secuencias IDENTITY (setval)...", flush=True)
            for tabla, pk in TABLAS_CON_IDENTITY:
                cur.execute(
                    f"SELECT setval(pg_get_serial_sequence('{tabla}', '{pk}'), "
                    f"COALESCE((SELECT MAX({pk}) FROM {tabla}), 1), true);"
                )

            print("==> Validando constraints diferidas (SET CONSTRAINTS ALL IMMEDIATE)...", flush=True)
            cur.execute("SET CONSTRAINTS ALL IMMEDIATE;")

            print("==> Rehabilitando triggers de usuario (ENABLE TRIGGER USER)...", flush=True)
            for tabla in TABLAS_ORDEN_TOPOLOGICO:
                cur.execute(f"ALTER TABLE {tabla} ENABLE TRIGGER USER;")

            print("==> Refrescando vista materializada v_ventas_mensuales_sala...", flush=True)
            cur.execute("REFRESH MATERIALIZED VIEW v_ventas_mensuales_sala;")

    with conn.cursor() as cur:
        print("==> Actualizando estadísticas (ANALYZE)...", flush=True)
        cur.execute("ANALYZE;")

    tiempo_total = time.perf_counter() - t0_total
    total_filas = sum(cnt for cnt, _ in tiempos_por_tabla.values())
    print(f"\n[OK] Carga finalizada: {total_filas:,} filas en {tiempo_total:.2f} segundos.", flush=True)
    return tiempos_por_tabla, tiempo_total


# -----------------------------------------------------------------------------
# Benchmark de inserción (Issue #29)
# -----------------------------------------------------------------------------
def ejecutar_benchmark(conn):
    print("\n" + "=" * 60, flush=True)
    print("EJECUTANDO BENCHMARK DE MÉTODOS DE INSERCIÓN (10.000 filas)", flush=True)
    print("=" * 60, flush=True)

    muestra_filas = [
        (
            i,
            f"Cliente Benchmark {i}",
            "DNI",
            f"{30000000 + i}",
            "Calle Falsa 123",
            1,
            date(2024, 1, 1),
            "socio",
            Decimal("10.00"),
        )
        for i in range(900001, 910001)
    ]

    with conn.transaction():
        with conn.cursor() as cur:
            cur.execute(
                """
                CREATE TEMP TABLE test_benchmark (
                    id_cliente INT,
                    nombre_razon_social VARCHAR(120),
                    tipo_doc VARCHAR(10),
                    nro_doc VARCHAR(15),
                    direccion VARCHAR(150),
                    id_localidad INT,
                    fecha_alta DATE,
                    tipo tipo_cliente,
                    descuento NUMERIC(5,2)
                ) ON COMMIT DROP;
            """
            )

            t0 = time.perf_counter()
            for row in muestra_filas:
                cur.execute(
                    "INSERT INTO test_benchmark VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s);",
                    row,
                )
            t_fila = time.perf_counter() - t0
            fps_fila = len(muestra_filas) / t_fila
            cur.execute("TRUNCATE test_benchmark;")

            t0 = time.perf_counter()
            batch_size = 1000
            for i in range(0, len(muestra_filas), batch_size):
                cur.executemany(
                    "INSERT INTO test_benchmark VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s);",
                    muestra_filas[i : i + batch_size],
                )
            t_batch = time.perf_counter() - t0
            fps_batch = len(muestra_filas) / t_batch
            cur.execute("TRUNCATE test_benchmark;")

            t0 = time.perf_counter()
            with cur.copy("COPY test_benchmark FROM STDIN") as copy:
                for row in muestra_filas:
                    copy.write_row(row)
            t_copy = time.perf_counter() - t0
            fps_copy = len(muestra_filas) / t_copy

    print(
        "\n| Método de Inserción | Filas | Tiempo Total (s) | Filas / Seg | Speedup vs Fila a Fila |",
        flush=True,
    )
    print("| :--- | :--- | :--- | :--- | :--- |", flush=True)
    print(
        f"| Fila por fila (`execute`) | 10.000 | {t_fila:6.3f} s | {fps_fila:10.1f} | 1.00x (base) |",
        flush=True,
    )
    print(
        f"| Por lotes (`executemany` 1k) | 10.000 | {t_batch:6.3f} s | {fps_batch:10.1f} | {t_fila / t_batch:6.2f}x |",
        flush=True,
    )
    print(
        f"| Flujo `COPY ... FROM STDIN` | 10.000 | {t_copy:6.3f} s | {fps_copy:10.1f} | {t_fila / t_copy:6.2f}x |",
        flush=True,
    )
    print("=" * 60 + "\n", flush=True)


# -----------------------------------------------------------------------------
# Verificación con consultas_control.sql (Issue #30)
# -----------------------------------------------------------------------------
def ejecutar_verificacion(conn):
    print("\n" + "=" * 60, flush=True)
    print("EJECUTANDO CONSULTAS DE CONTROL (consultas_control.sql)", flush=True)
    print("=" * 60, flush=True)

    ruta_control = os.path.join(SCRIPT_DIR, "consultas_control.sql")
    if not os.path.exists(ruta_control):
        print(f"[ERROR] Archivo {ruta_control} no encontrado.", flush=True)
        sys.exit(1)

    with open(ruta_control, mode="r", encoding="utf-8") as f:
        sql_control = f.read()

    conn.add_notice_handler(lambda diag: print(f"    [NOTICE] {diag.message_primary}", flush=True))

    with conn.transaction():
        with conn.cursor() as cur:
            cur.execute(sql_control)

    print("[OK] Todas las consultas de control C01..C14 pasaron con 0 inconsistencias.", flush=True)


# -----------------------------------------------------------------------------
# Main CLI
# -----------------------------------------------------------------------------
def main():
    parser = argparse.ArgumentParser(description="Carga masiva para Bodegas del Atuel.")
    parser.add_argument("--dsn", default=DEFAULT_DSN, help="Cadena de conexión PostgreSQL")
    parser.add_argument("--seed", type=int, default=DEFAULT_SEED, help="Semilla aleatoria")
    parser.add_argument(
        "--fecha-ref", default=DEFAULT_FECHA_REF, help="Fecha de referencia YYYY-MM-DD"
    )
    parser.add_argument(
        "--benchmark", action="store_true", help="Ejecuta benchmark de inserción"
    )
    parser.add_argument(
        "--verificar", action="store_true", help="Ejecuta consultas de control al finalizar"
    )

    args = parser.parse_args()

    t0_gen = time.perf_counter()
    print(f"Iniciando generador (seed={args.seed}, fecha_ref={args.fecha_ref})...", flush=True)
    dataset = generar_dataset(args.seed, args.fecha_ref)
    dt_gen = time.perf_counter() - t0_gen

    total_filas_gen = sum(len(filas) for _, filas in dataset.values())
    print(
        f"Dataset generado en memoria en {dt_gen:.2f}s: {total_filas_gen:,} filas para {len(dataset)} tablas.",
        flush=True,
    )

    try:
        with psycopg.connect(args.dsn, autocommit=False) as conn:
            if args.benchmark:
                ejecutar_benchmark(conn)

            ejecutar_carga(conn, dataset)

            if args.verificar:
                ejecutar_verificacion(conn)

    except Exception as e:
        print(f"[ERROR FATAL]: {e}", flush=True)
        import traceback

        traceback.print_exc()
        sys.exit(1)


if __name__ == "__main__":
    main()
