# Operación

## Preflight

Antes de aceptar un pool en un entorno operativo:

```bash
npm ci
make verify
make release-check
```

Verifique además que:

- el pool fue creado por la factory esperada;
- token0 y token1 coinciden con el par aprobado;
- owner, fee recipient, fee manager, guard y oracle son los previstos;
- `cachedInvariant` coincide con el cálculo del lens;
- los balances físicos reconcilian con `gross0` y `gross1`.

## Runbook diario

```mermaid
flowchart LR
    S[Snapshot] --> R[Reconciliación]
    R --> O[Stress operativo]
    O --> Q[Quotes de referencia]
    Q --> D{Desviación}
    D -->|normal| M[Monitorizar]
    D -->|fuera de límite| P[Pausar y aislar]
    P --> I[Investigar estado y parámetros]
```

Métricas mínimas:

| Señal                  | Uso                                                 |
| ---------------------- | --------------------------------------------------- |
| `invariantDrift`       | Diferencia entre `cachedInvariant` y cálculo actual |
| `grossMatchesPhysical` | Reconciliación de custodia                          |
| `liabilitiesCovered`   | Cobertura de fees                                   |
| `worstCoveragePpm`     | Cobertura bajo shock                                |
| `requiredBuffer`       | Capital operativo adicional                         |
| `projectedSkewPpm`     | Concentración entre lados                           |

## Incidencia

1. pausar el pool sin cambiar parámetros;
2. fijar bloque, estado y balances físicos;
3. reproducir quotes desde el snapshot;
4. separar principal, fee LP y fee de protocolo;
5. ejecutar escenarios operativo y severo;
6. documentar toda transición administrativa;
7. reanudar solo después de reconciliación y revisión independiente.

## Release

La rama `production`, el tag `v1.0.0` y `main` deben resolver al mismo commit.
Los checks de Foundry y Node deben estar verdes en los tres refs. La publicación
incluye únicamente artefactos de código fuente y documentación versionada.
