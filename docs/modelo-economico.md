# Modelo económico

## Unidades

El pool opera con unidades mínimas de cada ERC-20. La curva no normaliza
decimales, por lo que un par productivo debe usar activos con escalas
compatibles o adaptadores externos explícitos.

## Invariante amplificado

El parámetro `amplification` controla la curvatura cerca del equilibrio. Un
valor alto reduce price impact en la zona central, pero concentra la
sensibilidad al aproximarse a reservas extremas.

El owner puede programar una transición lineal de `A₀` a `A₁` entre `t₀` y `t₁`.
Durante la rampa:

```text
A(t) = A₀ + (A₁ - A₀) × (t - t₀) / (t₁ - t₀)
```

El resultado se redondea en unidades enteras del parámetro. La duración mínima
es de 24 horas y cada transición se limita a un factor de diez; se puede
programar otra transición cuando termina la anterior. El parámetro efectivo se
consulta con `amplification()` y los extremos con `amplificationRamp()`. La
programación no cambia balances ni mueve tokens por sí sola.

```mermaid
flowchart LR
    B[Reservas virtuales] --> D[Cálculo iterativo de D]
    A[Amplificación] --> D
    D --> Q[Quote de swap o liquidez]
    Q --> P[Reservas proyectadas]
    P --> D2[Nuevo D]
    D2 --> S[Settlement]
```

Las divisiones usan `FullMath.mulDiv` cuando intervienen productos de 256 bits.
Los redondeos favorecen la permanencia de reserva: un swap resta una unidad del
output calculado y las shares mínimas se validan antes del settlement.

## Shares LP

En la primera aportación:

```text
shares = D_after - MINIMUM_LIQUIDITY
```

La fracción mínima se acuña a `DEAD_SHARES`. En aportaciones posteriores:

```text
shares = totalSupply × (D_after - D_before) / D_before
```

Una salida proporcional distribuye principal según:

```text
amountᵢ = shares × virtualᵢ / totalSupply
```

Las salidas a un token resuelven la reserva restante sobre el objetivo de `D`.
Para una salida por importes específicos, la cotización combina la variación de
`D` y una fee expresada en shares:

```text
baseShares = floor(totalSupply × (D_before - D_after) / D_before)
sharesToBurn = baseShares + imbalanceFeeShares
```

`maxShares` protege al usuario frente a cambios de estado entre la consulta y la
ejecución. En una rampa, las lecturas del parámetro y de las reservas deben
referirse al mismo bloque.

## Fees

La fee total de swap combina base, tamaño y desequilibrio, limitada por
`maxFeePpm`. Después se separa:

```text
protocolFee = totalFee × adminFeePpm / 1_000_000
lpFee       = totalFee - protocolFee
```

La fee LP incrementa el acumulador global por share. Cada titular materializa su
parte cuando transfiere shares, aporta, retira o reclama.

## Contabilidad

```text
active principal = virtual0 + virtual1
LP liabilities   = pendingLPFee0 + pendingLPFee1
admin liabilities= protocolFee0 + protocolFee1
gross assets     = active principal + liabilities
```

El NAV de principal y el valor de fees se publican por separado. Esto permite
reconciliar activos sin confundir obligaciones reclamables con liquidez activa.

## Ejemplo

Con 10 millones de unidades por lado, 20 millones de `D` aproximado y una
entrada adicional balanceada de 1 millón por lado, el delta de `D` es cercano a
2 millones. Si el supply previo es 20 millones, la emisión esperada es cercana a
2 millones de shares, sujeta al redondeo de la curva.
