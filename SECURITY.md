# Política de seguridad

LumenSwapProtocol mantiene controles orientados a proteger reservas de pool,
participaciones LP, acumulación de fees y ejecución de swaps sobre una curva
stable-swap amplificada.

## Alcance de revisión

Quedan dentro del alcance:

- cálculo del invariante estable y sus solvers iterativos;
- emisión y quema de participaciones LP;
- retiradas proporcionales, a un token y desbalanceadas;
- separación entre balances virtuales, balances brutos y fees pendientes;
- acumulación y claim de fees de LP;
- comisiones de protocolo y su recolección;
- factory canónica, router y quoteadores;
- guards de reserva, ratio y circuit breaker;
- simuladores de diagnóstico económico.

Quedan fuera del alcance:

- custodia de claves;
- frontends o indexadores externos;
- activos con rebases o transfer fees, salvo mocks de rechazo;
- oráculos externos;
- integraciones con bridges.

## Invariantes esperadas

Para cada token:

```text
gross = virtual + pendingLPFee + protocolFee
physical balance = gross
```

Para operaciones económicas sanas:

- un swap no debe reducir `D` después de considerar fees;
- una retirada proporcional debe quemar shares antes de transferir reservas;
- una retirada desbalanceada debe quemar shares según el cambio real de
  invariante;
- las fees de LP deben ser reclamables solo por titulares checkpointed;
- las fees de protocolo no deben entrar en el valor principal de LP shares;
- el guard debe evaluar balances virtuales proyectados.

## Validación requerida

```bash
forge fmt --check
forge build --deny warnings
FOUNDRY_PROFILE=ci forge test --deny warnings
```

Los cambios en rutas de liquidez, swaps, accounting o guards deben incluir tests
que cubran el flujo nominal y el límite de riesgo afectado.

## Reporte responsable

Un reporte de seguridad debe incluir:

- componente afectado;
- secuencia mínima de verificación;
- impacto económico;
- precondiciones;
- comportamiento esperado y observado;
- propuesta de mitigación;
- tests recomendados.

No incluyas claves privadas, credenciales ni datos de terceros.
