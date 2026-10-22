# Historial de cambios

## 2.0.0 - 2026-10-22

### Añadido

- Programación y parada de rampas de amplificación con interpolación por bloque,
  duración mínima de 24 horas y límite de variación de diez veces.
- Lectura `amplificationRamp()` y eventos de cambios de política matemática.
- Pruebas de interpolación, límites de gobierno y cotización de liquidez.

### Cambiado

- Cotizaciones de liquidez valoradas con el parámetro efectivo del bloque.
- Documentación de integración y operación para cambios de amplificación.
- Versión estable y contrato de release actualizados a 2.0.0.

## 1.0.0 - 2026-10-17

### Añadido

- Stress de liquidez por token y agregado.
- Escenarios operativo, severo y personalizado.
- Escalera de salidas proporcionales y sensibilidad de swaps.
- Documentación de arquitectura, economía, riesgo, operación e integración.
- Validación de superficie pública e integridad de release.
- CI Foundry y Node sobre Linux y Windows.

### Cambiado

- Normalización de nombres de invariant y superficies de diagnóstico.
- Flujo reproducible mediante Make y npm.
- Banner común de Solguard Labs.
