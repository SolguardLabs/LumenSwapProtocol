# LumenSwapProtocol

![banner](./assets/banner.png)

LumenSwapProtocol es una implementación Solidity de un AMM tipo stable-swap para
pares de stablecoins. El protocolo incluye curva invariante amplificada,
participaciones LP ERC-20, fees separadas para LPs y protocolo, retiradas
proporcionales, retiradas a un solo token, retiradas desbalanceadas, factory,
router, lens, simuladores y controles de riesgo.

El diseño mantiene separadas la custodia del pool, el cálculo de invariant, la
política de comisiones, las vistas para integradores y los guards de balance.
Los contratos no dependen de paquetes externos de Solidity.

## Componentes

- `LumenPool`: pool stable-swap de dos tokens, custodia, swaps, LP shares y
  fees.
- `LumenLPToken`: ERC-20 minimalista para participaciones LP.
- `StableSwapMath`: cálculo iterativo de `D`, `y` y shares por cambio de
  invariante.
- `LumenFeeManager`: fees dinámicas por swap y penalización de retiradas
  desbalanceadas.
- `LumenBalanceGuard`: límites de reserva mínima, ratio y tamaño de salida.
- `LumenFactory`: creación canónica de pools por par.
- `LumenRouter`: wrappers de add/remove/swap para integradores.
- `LumenPoolLens`, `LumenQuoter`, `LumenScenarioSimulator`: vistas de
  diagnóstico y simulación.
- `LumenOracle`: oracle circular local de precios acumulados.
- `LumenAccounting`: helpers de reconciliación y comparación económica.

## Flujo principal

1. La factory despliega pools canónicos para pares de stablecoins.
2. Los LPs depositan ambos activos y reciben participaciones del pool.
3. Los traders intercambian activos contra la curva amplificada.
4. Las fees se separan entre acumulación para LPs y comisión de protocolo.
5. Los LPs pueden retirar de forma proporcional, a un solo token o con importes
   desbalanceados bajo los límites de riesgo.
6. Las vistas y quoteadores permiten simular operaciones antes de enviarlas.

## Seguridad y controles

- Invariante stable-swap calculado con aritmética fixed-point.
- Guard de balances para reservas mínimas, ratios y salidas máximas.
- Separación entre balances virtuales, balances brutos y fees pendientes.
- Pausa y control de administración en módulos sensibles.
- Router y lens separados de la custodia principal del pool.

Consulta [SECURITY.md](./SECURITY.md) para el alcance de revisión, las
invariantes esperadas y el proceso de reporte responsable.

## Requisitos

- Foundry estable con Solidity `0.8.26`.
- Bash si se quiere ejecutar `scripts/ci.sh`.

Comprobar instalación:

```bash
forge --version
```

## Compilación

```bash
forge build
```

Modo estricto:

```bash
forge build --deny warnings
```

## Tests

Ejecutar toda la suite:

```bash
forge test
```

Validación equivalente a CI:

```bash
bash scripts/ci.sh
```

## Estructura

```text
src/
  accounting/   Reconciliación económica y comparadores de shares
  core/         Pool, factory y deployer
  fees/         Política de fees dinámicas
  interfaces/   Superficies externas
  libraries/    Matemática fixed-point, stable-swap y transferencias seguras
  modules/      Registry operativo de pools
  oracle/       Observaciones circulares de precio
  periphery/    Router, lens, quoter y simulador
  risk/         Guard de balance y circuit breaker
  tokens/       Token LP
  types/        Structs y errores compartidos
  utils/        Ownable, pausa y reentrancy guard
tests/
  unit/         Rutas esperadas de liquidez, swaps y fees
  helpers/      Infraestructura de pruebas
  mocks/        Stablecoins mock
```
