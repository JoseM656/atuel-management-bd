# Bodegas del Atuel

Sistema de gestión y distribución para la empresa vitivinícola ficticia «Bodegas del Atuel»: producción de uva y vino, distribución a través de un depósito central y venta en una red de salas. TPI Bases de Datos · UTN FRSR · 2026.

## Objetivos

<!-- pendiente -->

## Reglas y consultas

<!-- pendiente -->

## API

API REST en Go (`chi` + `pgx`) que expone la capa de datos; la API **no recalcula** totales, descuentos ni stock (delega en los triggers/funciones/procedimientos de la base).

Documentación completa en [`api/docs/api.md`](api/docs/api.md): requisitos, ejecución, endpoints, errores SQLSTATE→HTTP y tests. Especificación OpenAPI en [`api/docs/openapi.yaml`](api/docs/openapi.yaml) y comandos de prueba en [`api/docs/curl.md`](api/docs/curl.md).


## Front

<!-- pendiente -->

## Nube

<!-- pendiente -->
