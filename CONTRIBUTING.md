# Contribución

## Flujo

1. cree una rama con alcance único;
2. mantenga código y comentarios técnicos en inglés;
3. documente comportamiento operativo en español;
4. añada pruebas nominales, de borde y de reconciliación;
5. ejecute `make verify` y `make release-check`;
6. describa parámetros, unidades y redondeos en el pull request.

## Solidity

- Use errores custom en rutas de protocolo.
- Evite llamadas externas dentro de librerías matemáticas.
- Mantenga efectos antes de interacciones y protección `nonReentrant`.
- Exprese ratios en ppm y cantidades en unidades mínimas.
- No cambie storage layout sin documentar migración.

Los cambios de interfaz deben actualizar implementaciones, periphery y tests en
el mismo commit.
