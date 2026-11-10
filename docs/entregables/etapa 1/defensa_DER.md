# Defensa del DER «Bodegas del Atuel» (V1)

## 1. Criterio general

Seguimos tres principios:
1. **Todo lo que dice el escenario (sección 3) y las reglas de negocio (sección 4) tiene que estar en el DER**, y toda entidad de la tabla de la sección 5 tiene que estar representada.
2. **El DER es conceptual.** Dibuja lo que se puede expresar con entidades, relaciones y cardinalidades. Lo que no se puede dibujar queda escrito en la leyenda y se resuelve en la base (sección 5 de este texto).
3. **Modelamos pensando en 3FN.** Cuando un atributo habría generado una dependencia transitiva, lo separamos en entidad desde el DER, no recién en el paso relacional.

## 2. Notación

Usamos notación de Chen con (mín,máx) junto a cada entidad, que indica la participación de *esa* entidad en la relación. Por ejemplo, `Finca (1,1) — se ubica — (0,N) Departamento` se lee "cada finca está en exactamente un departamento; un departamento puede tener de cero a muchas fincas".

La elegimos porque el paso 2 de la etapa 1 pide dibujar entidad débil, jerarquía, cardinalidades mínima y máxima y N:M **con atributos**. Chen permite poner los atributos directamente sobre el rombo (`cantidad` en stock, `porcentaje` en composición). En pie de cuervo habría que convertirlos ya en tablas intermedias y el DER dejaría de ser conceptual. Coloreamos por área (producción, vinos, ventas, logística) para que un diagrama de 23 entidades se pueda leer.

## 3. Decisiones por bloque

### Ubicación y personal

**Localidad, Sala de venta y Empleado.** Una sala está en una sola localidad y una localidad puede tener varias salas (`Sala (1,1)` / `Localidad (0,N)`). Cada empleado trabaja en una sola sala (RN-03, `Empleado (1,1)`), y una sala tiene al menos un empleado (`(1,N)`, "en cada sala trabajan varios empleados").

**Encargado regional como relación con Empleado, no como atributo.** Tiene tres anclas en el enunciado:
- La sección 3.1 dice "por cada localidad **existe** un único encargado".
- La RN-02 dice "cada localidad tiene un único encargado".
- La tabla de la sección 5 aclara "el encargado depende de la localidad".

Por eso es `Localidad (1,1) — es encargado de — (0,1) Empleado`: toda localidad tiene exactamente un encargado, y un empleado es encargado de como máximo una localidad.

Lo modelamos como relación hacia Empleado porque el encargado es una persona con CUIT, no un texto. Además evita una dependencia transitiva: si el encargado fuera un atributo de la sala, tendríamos sala → localidad → encargado. Es la dependencia funcional `localidad → encargado regional` que el propio enunciado cita como ejemplo en el paso 4.

**Departamento como entidad propia.** El enunciado da departamento y provincia como datos de la finca. Pero cada departamento pertenece a una provincia, así que dejar ambos en Finca crearía la dependencia transitiva finca → departamento → provincia. Además el Anexo B trae los departamentos de Mendoza como catálogo cargado desde CSV, o sea que se comportan como una entidad de catálogo.

### Producción de uva

**Parcela es entidad débil** (doble rectángulo, rombo doble "posee"). Se identifica por (finca, nº de parcela): el enunciado dice "una parcela no existe sin su finca" y la tabla de la sección 5 lo pide expresamente. `Finca (1,N)` porque "cada finca se divide en parcelas".

**Parcela—Cepa.** La parcela tiene una sola cepa (`Parcela (1,1)`, RN-04); la cepa puede estar en muchas parcelas o en ninguna (`Cepa (0,N)`). La cepa es catálogo y es la misma entidad que usa la composición del vino.

**Lote de uva es entidad fuerte con número propio.** Podría haber sido débil de Parcela, pero el enunciado le da número propio ("de cada lote se registra su número") y la tabla lo lista con ese identificador. Además se relaciona con dos entidades distintas (parcela de origen y bodega destino) y de él cuelgan los análisis, que así referencian una sola columna.

**La campaña no está dibujada como atributo.** Es derivada: se calcula del año de `fecha_cosecha`. La regla "una cosecha por parcela y campaña" (RN-04) no se puede expresar en un DER, así que quedó escrita en la leyenda y se garantiza con un índice único de expresión.

**Análisis de calidad (0,N) por lote.** Un lote se registra al cosechar y el análisis se hace después. Con mínimo 1 no podríamos registrar el lote antes de analizarlo. La leyenda lo aclara.

### Bodegas y vinos

**Vino—Bodega.** `Vino (1,1) — elabora — (0,N) Bodega`: un vino lo elabora una sola bodega (tabla de la sección 5). La bodega también aparece en dos relaciones más, con significados distintos: destino del lote (`entregado a`) y origen del ingreso (`genera`). Son tres relaciones y no una porque cada una responde a una pregunta diferente del escenario.

**La presentación (volumen) es atributo del vino y no una entidad.** El enunciado define el precio como atributo del vino y pide poder consultar "vinos con el mismo nombre y distinta añada o presentación". El Malbec Reserva 2021 de 375 ml y el de 750 ml son vinos distintos, con código y precio distintos. Una entidad Presentación los haría un solo vino con varios precios, lo que contradice el ejemplo del enunciado.

**Composición y Maridaje.** Son N:M. La composición lleva el atributo `porcentaje` sobre el rombo y `Vino (1,N)`, porque un vino tiene "una o más cepas". `se recomienda con` también es N:M con `Vino (1,N)`. El maridaje es entidad propia porque "un maridaje puede repetirse para distintos vinos" y tiene atributos propios (temperatura de servicio).

**Auditoría de precio** es entidad con ID propio (la completa un trigger, RN-13), y `Auditoría (1,1) — audita — (0,N) Vino`.

### Clientes y ventas

**Jerarquía total y disjunta (círculo «d»).** Total, porque el enunciado dice "existen tres tipos de cliente". Disjunta, porque cada cliente es de un solo tipo. Los subtipos tienen atributos y relaciones diferentes, lo que justifica una jerarquía en lugar de un simple atributo `tipo`.

Lo más importante: **Permiso de exportación cuelga de Exportador y no de Cliente.** Así el DER ya garantiza que solo un exportador tiene permisos (`Permiso (1,1)` / `Exportador (0,N)`), y un exportador puede tener varios (RN-07). Socio no tiene atributos propios, pero queda como subtipo para que la jerarquía sea completa y para que el tipo quede explícito.

**`descuento` es atributo de Cliente.** Podría parecer derivable del tipo (10, 20, 30 %), pero la consigna U6 sube el descuento de los exportadores con más de 3 permisos al 35 %. Por eso el descuento de un cliente no es función solo de su tipo y necesita su propio atributo.

**Comprobante y Renglón.** El comprobante se relaciona con un cliente y una sala (`(1,1)` en ambos). El renglón es una N:M entre Comprobante y Vino con atributos (cantidad, precio unitario, descuento, subtotal), y su clave es (comprobante, vino), tal como lo indica el enunciado. Eso impide repetir un vino dentro del mismo comprobante. `Comprobante (1,N)` porque un comprobante sin renglones no tiene sentido.

**Atributos derivados que sí se guardan.** `subtotal`, `total`, `porcentaje_descuento` y `precio_unitario` aparecen en el DER porque se almacenan a propósito. Lo justificamos en las decisiones de diseño (sección 4): `precio_unitario` guarda el precio al momento de la venta, porque el precio del vino cambia después (U3, U5, RN-13). Los totales se guardan por rendimiento. La consistencia la garantizan triggers y funciones, no la carga manual.

### Stock y logística

**Depósito como entidad.** El enunciado habla de "un único depósito central". Lo modelamos como entidad con stock N:M con Vino, igual que Sala, para que ambos stocks sean simétricos. La unicidad es una regla que se declara en la leyenda y se garantiza en la base (`id = 1`).

**Stock de sala y stock de depósito como N:M con atributo `cantidad`.** Son estados (cuántas botellas hay), no eventos, y su clave es (sala, vino) y (vino) respectivamente, como pide la tabla de la sección 5.

**Ingreso y Transferencia como entidades.** No son una simple N:M, porque tienen identidad propia (código, número), fecha y un estado con ciclo de vida (RN-10, RN-11, RN-12). Sus renglones sí son N:M con atributo `cantidad`. El ingreso se relaciona con el transportista que lo trasladó y con la bodega de origen. La transferencia se relaciona con la sala solicitante.

**Transportista cubre Localidad (0,N)–(0,N).** El mínimo es 0 en ambos lados porque la cobertura se carga después (la consigna I1 inserta una cobertura nueva). Un transportista recién dado de alta no tiene por qué tenerla ya.

## 4. Qué agregamos nosotros al enunciado

La sección 5 dice que los atributos y claves son una guía y que el grupo puede agregar lo que considere necesario, justificándolo. Agregamos:
- **Departamento** como entidad (por la dependencia transitiva vista arriba).
- **Depósito** como entidad, para que el stock del depósito sea simétrico al de sala.
- **La relación Depósito—Localidad (`ubicado en`)**, para que el depósito físico tenga una ubicación. Ninguna regla depende de ella y cuesta una sola clave foránea.

## 5. Lo que el DER no puede mostrar y dónde se garantiza

| Regla | Por qué no se dibuja | Dónde se garantiza |
|---|---|---|
| Una cosecha por parcela y campaña (RN-04) | La campaña es derivada | Índice único de expresión (parcela, año de cosecha) |
| Porcentajes de corte suman 100 (RN-05) | Es una suma entre filas | Constraint trigger diferido |
| Un único depósito | Es una restricción de cantidad de filas | `CHECK (id = 1)` |
| Estados y transiciones (RN-10, 11, 12) | El DER no dibuja ciclos de vida | `ENUM` + triggers |
| Descuento por tipo (RN-06) | Es un cálculo | `fn_descuento_cliente` + `CHECK` de rango |
| Totales (RN-08) | Son derivados | Trigger + función de cálculo |
| Stock nunca negativo (RN-09) | Es una regla de valor | `CHECK` + trigger de venta |
| Jerarquía total y disjunta | Se dibuja pero no se impone | FK compuesta (id_cliente, tipo) con `CHECK` de tipo fijo, y constraint trigger diferido para la totalidad |
| Ciclo localidad → empleado → sala → localidad | Es consecuencia del modelo | FK del encargado `DEFERRABLE INITIALLY DEFERRED` |

## 6. Puntos que te pueden preguntar

1. **"El enunciado dice 'uno o más análisis por lote' y ustedes pusieron (0,N)."**
   Es deliberado: el lote se registra al cosechar y el análisis es posterior. Un (1,N) obligaría a cargar los dos a la vez. Lo dejamos escrito en la leyenda.

2. **"¿Por qué Ingreso y Transferencia tienen (1,N) con sus renglones si en confección pueden estar vacíos?"**
   El (1,N) describe el documento válido, es decir, cuando pasa a terminado. Mientras está en confección es un estado intermedio que controlan los triggers de estados, y los procedimientos `sp_terminar_ingreso` y `sp_terminar_transferencia` (`004_procedimientos.sql`) exigen explícitamente que exista al menos un renglón antes de pasar a `'terminado'`.

3. **"El encargado es obligatorio para toda localidad, ¿y si una localidad no tiene sala?"**
   El enunciado dice tres veces que cada localidad tiene un único encargado, y el DDL lo implementa con `NOT NULL`. Además, la regla implícita **RI-01** (`trg_encargado_localidad`, `trg_encargado_empleado` y `trg_encargado_sala` en `005_triggers.sql`) verifica al cierre de la transacción que el encargado trabaje en una sala de esa misma localidad.

4. **"La campaña figura en la tabla de la sección 5 como atributo del lote y ustedes no la dibujaron."**
   Es derivada de `fecha_cosecha`. Guardarla duplicaría un dato y abriría la posibilidad de inconsistencia entre campaña y fecha. Está declarada en la leyenda y la regla se garantiza con el índice único de expresión `idx_lote_uva_parcela_campana`.

5. **"¿Por qué hay atributos derivados dibujados como atributos normales?"**
   Porque se almacenan. Los nueve derivados guardados (subtotales, totales, descuentos, precio histórico, stocks) están listados en `desiciones_diseño.md`, sección 4, con la razón de cada uno y el mecanismo que los mantiene consistentes.

6. **"Su leyenda dice que la línea doble es participación total, pero la mayoría de las líneas son simples."**
   En V1 solo la relación identificadora de Parcela y la jerarquía usan línea doble. La participación se lee de los números `(mín,máx)` junto a cada entidad, y la línea doble quedó reservada para esos dos casos estructurales.

7. **"¿Por qué el depósito tiene localidad si el enunciado no lo pide?"**
   Es un agregado de nuestro grupo, permitido por la sección 5. El depósito es un lugar físico y su ubicación en `deposito.id_localidad` permite además que el trigger `trg_ingreso_transportista` (**RI-05**) valide automáticamente que el transportista asignado a un ingreso cubra la localidad donde está ubicado el depósito central.

8. **"¿Por qué provincia es atributo y no entidad?"**
   Provincia no tiene atributos propios ni participa de ninguna regla. Convertirla en entidad agregaría una tabla de una sola columna sin ganar integridad. Departamento sí se separó porque aparecía como determinante de otro atributo en Finca.
