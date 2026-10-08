# Escrow Contract — Ethereum & Foundry

Protocolo de **depósito en garantía (escrow)** desarrollado en Solidity y Foundry que permite gestionar acuerdos económicos entre un comprador, un vendedor y un árbitro mediante contratos inteligentes.

El contrato bloquea ETH hasta que se cumplen las condiciones acordadas, permitiendo la aprobación de entregas, cancelaciones, reembolsos y resolución de disputas.

**Tecnologías:** Solidity · Ethereum · Foundry · OpenZeppelin · Sepolia

## Características principales

- Depósito y custodia de ETH mediante contratos inteligentes.
- Máquina de estados para controlar el ciclo de vida del acuerdo.
- Tres roles independientes: comprador, vendedor y árbitro.
- Plazos configurables para la entrega del trabajo.
- Confirmación de entrega por parte del vendedor.
- Aprobación explícita por parte del comprador.
- Periodo de revisión de 3 días.
- Apertura de disputas por desacuerdo o falta de respuesta.
- Resolución de disputas mediante arbitraje.
- Protección contra reentrancy con OpenZeppelin.
- Validación de permisos, estados y parámetros del acuerdo.
- Pruebas unitarias, de seguridad, fuzzing e invariantes.
- Despliegue y ejecución de un acuerdo real en Ethereum Sepolia.

## Arquitectura

Cada instancia de `Escrow.sol` representa un acuerdo independiente entre tres participantes.

| Rol | Responsabilidad |
|---|---|
| Buyer (comprador/cliente) | Deposita ETH, aprueba la entrega o solicita una disputa |
| Seller (vendedor/proveedor) | Realiza el trabajo, declara su entrega y reclama el pago aprobado |
| Arbiter (árbitro) | Decide el destinatario de los fondos cuando existe una disputa |

Los participantes, el importe y la duración se establecen en el constructor mediante variables `immutable`.

### Máquina de estados

| Estado | Descripción |
|---|---|
| `CREATED` | Acuerdo creado, todavía sin financiación |
| `FUNDED` | ETH depositado y bloqueado en el contrato |
| `DELIVERED` | El vendedor declara la entrega y comienza el periodo de revisión |
| `APPROVED` | El comprador acepta la entrega |
| `DISPUTED` | Existe un conflicto pendiente de arbitraje |
| `RELEASED` | El vendedor ha recibido el pago |
| `REFUNDED` | El comprador ha recuperado el depósito |
| `CANCELLED` | Acuerdo cancelado antes de la financiación |

### Flujos principales

**Entrega aceptada**

1. `CREATED` → El comprador ejecuta `fund()`.
2. `FUNDED` → El vendedor ejecuta `markDelivered()`.
3. `DELIVERED` → El comprador ejecuta `approveDelivery()`.
4. `APPROVED` → El vendedor ejecuta `claimPayment()`.
5. `RELEASED` → Los fondos llegan al vendedor.

**Entrega rechazada**

1. El vendedor declara la entrega.
2. El comprador ejecuta `openDispute()` durante el periodo de revisión.
3. El acuerdo pasa a `DISPUTED`.
4. El árbitro ejecuta `resolveDispute(bool paySeller)`.
5. El acuerdo termina en `RELEASED` o `REFUNDED`.

**Otros escenarios**

- El comprador puede cancelar un acuerdo mientras esté en `CREATED`.
- Si el vendedor no declara la entrega antes del plazo de financiación, el comprador puede solicitar un reembolso.
- Si el comprador no responde durante los 3 días posteriores a la declaración de entrega, cualquier dirección puede ejecutar `triggerDispute()` para solicitar arbitraje.
- El comprador también puede liberar voluntariamente el pago desde `FUNDED` mediante `release()`.

## Gestión de plazos

El contrato utiliza dos periodos independientes:

**Delivery duration:** periodo configurable al crear el acuerdo. Se calcula desde el momento en que el comprador deposita ETH y limita cuándo el vendedor puede declarar la entrega.

**Review period:** periodo fijo de 3 días que comienza cuando el vendedor ejecuta `markDelivered()`.

La expiración de un plazo no ejecuta automáticamente una transacción. Los participantes o un servicio de automatización deben invocar la función correspondiente.

## Seguridad

El protocolo incorpora las siguientes medidas:

- **Role-based access control:** cada operación verifica la identidad del participante mediante `msg.sender`.
- **Finite-state machine:** las funciones únicamente pueden ejecutarse en estados permitidos.
- **ReentrancyGuard:** protección de las operaciones que transfieren ETH.
- **Checks-Effects-Interactions:** el estado cambia antes de realizar llamadas externas.
- **Atomicidad:** si una transferencia de ETH falla, la operación se revierte y se conserva el estado anterior.
- **Constructor validation:** rechazo de direcciones o parámetros inválidos.
- **Mutual confirmation:** la simple declaración de entrega no permite al vendedor cobrar automáticamente.
- **Restricted arbitration:** una disputa activa solo puede resolverse mediante el árbitro autorizado.
- **Terminal states:** se impide ejecutar nuevamente pagos o reembolsos después de finalizar el acuerdo.

### Limitaciones conocidas

Este proyecto es educativo y **no ha sido auditado para producción**.

- El árbitro es una entidad de confianza; su inactividad puede bloquear fondos indefinidamente.
- El contrato no verifica automáticamente la calidad o existencia de un trabajo realizado fuera de la blockchain.
- No incorpora mecanismos de apelación, sustitución de árbitro ni pagos parciales.
- Un destinatario que rechace permanentemente las transferencias de ETH puede impedir determinadas liquidaciones.
- La automatización de plazos requiere transacciones externas.
- Cada despliegue gestiona un único acuerdo, lo que incrementa el coste de despliegue por operación.

Estas limitaciones deben evaluarse antes de cualquier uso con activos de valor real.

## Testing

Las pruebas se desarrollaron utilizando Foundry y están organizadas en:

| Archivo | Contenido |
|---|---|
| `Escrow.t.sol` | Ciclo básico, financiación, cancelaciones y reembolsos |
| `EscrowDisputes.t.sol` | Entregas, confirmaciones, disputas y arbitraje |
| `EscrowSecurity.t.sol` | Reentrancy, transferencias fallidas, validaciones y fuzzing |
| `EscrowInvariant.t.sol` | Invariantes y secuencias aleatorias de operaciones |

Las pruebas de seguridad incluyen receptores maliciosos que rechazan ETH e intentos de reentrancy, además de entradas aleatorias para importes y plazos.

### Invariantes principales

**Balance según el estado:** un acuerdo activo y financiado debe conservar el importe acordado; un acuerdo terminado debe haber distribuido los fondos.

**Conservación de ETH:** dentro del entorno de pruebas controlado, la suma del ETH del comprador, vendedor y escrow permanece constante a través de múltiples acuerdos.

La prueba stateful ejecutó aproximadamente **128.000 llamadas aleatorias**, sin reversiones inesperadas en los handlers.

### Cobertura de producción

| Métrica | Cobertura |
|---|---:|
| Líneas | 100% |
| Statements | 100% |
| Branches | 100% |
| Funciones | 100% |

Estos valores corresponden a `src/Escrow.sol`, no al conjunto completo de scripts y contratos auxiliares.

Una cobertura del 100% no garantiza ausencia de vulnerabilidades.

### Ejecutar las pruebas

- Compilar: `forge build`
- Ejecutar todas las pruebas: `forge test -vv`
- Ejecutar invariantes: `forge test --match-contract EscrowInvariantTest -vv`
- Comprobar formato: `forge fmt --check`
- Generar cobertura: `forge coverage`

## Despliegue en Ethereum Sepolia

El contrato fue desplegado en Sepolia y se utilizó para completar un acuerdo real con financiación, declaración de entrega, apertura de disputa y devolución de ETH mediante arbitraje.

**Contrato:** [0x0B250e5E50D1b8608a2aBA3DAbB60fE874F775B3](https://sepolia.etherscan.io/address/0x0B250e5E50D1b8608a2aBA3DAbB60fE874F775B3)

**Chain ID:** `11155111`

### Configuración del acuerdo

| Parámetro | Valor |
|---|---|
| Importe | 0.001 Sepolia ETH |
| Duración de entrega | 7 días |
| Periodo de revisión | 3 días |
| Resultado | `REFUNDED` |

### Transacciones verificables

| Operación | Transacción |
|---|---|
| Despliegue | [Ver transacción](https://sepolia.etherscan.io/tx/0x8a01ab012f711a8148ae7750f53c33f75d458cb627822adb783d88f4d828d09b) |
| Depósito de ETH | [Ver transacción](https://sepolia.etherscan.io/tx/0x9ae132af122ed9281736b3620bb135bdb228b6abd122777253eb0802d94879d7) |
| Declaración de entrega | [Ver transacción](https://sepolia.etherscan.io/tx/0x148b0919caf361ca139df65b2418e6305b12cb919e14a7ce7e0ed5124a931676) |
| Apertura de disputa | [Ver transacción](https://sepolia.etherscan.io/tx/0xf4e64886474aa45aca40f04543768da4c36693856771c2b033b27b114d5703c1) |
| Resolución y reembolso | [Ver transacción](https://sepolia.etherscan.io/tx/0xf8f7d7f766df0a3373fbda4532417a52064d66c2a36db1c498793d33d59f1bfb) |

**Resultado comprobado on-chain:**

- Estado final: `REFUNDED` (enum = 6).
- ETH devuelto al comprador: 0.001 Sepolia ETH.
- Balance final del contrato: 0 ETH.
- Disputa resuelta por el árbitro autorizado.

La dirección mostrada corresponde a un acuerdo ya finalizado, por lo que no puede reutilizarse para crear otra operación.

## Instalación y ejecución local

**Requisitos:** Foundry, Git y un entorno compatible con Solidity.

Clonar el repositorio:

`git clone https://github.com/ikerbotana2002/escrow-contract.git`

Entrar en el directorio:

`cd escrow-contract`

Instalar dependencias:

`forge install`

Compilar:

`forge build`

Ejecutar tests:

`forge test`

Para desplegar nuevos acuerdos, el script `DeployEscrow.s.sol` utiliza las variables de entorno `SELLER_ADDRESS`, `ARBITER_ADDRESS`, `ESCROW_AMOUNT` y `ESCROW_DURATION`. Se requiere una wallet financiada, un RPC adecuado y estimar el gas conforme a las reglas actuales de la red.

## Aprendizajes

Este proyecto profundiza en la construcción de protocolos financieros mediante:

- Diseño de máquinas de estados y transiciones válidas.
- Separación de responsabilidades entre participantes.
- Gestión de fondos bloqueados y condiciones temporales.
- Arbitraje y resolución de conflictos.
- Diseño de permisos para evitar acciones unilaterales.
- Seguridad de llamadas externas y manejo de errores.
- Fuzz testing y verificación de invariantes económicas.
- Integración y ejecución real en Ethereum Sepolia.

---

# English Version

## Overview

A Solidity and Foundry **Ethereum escrow protocol** for managing financial agreements between a buyer, seller and independent arbiter.

The contract securely holds ETH until predefined conditions are satisfied, supporting delivery confirmation, refunds, cancellations, dispute resolution and role-based permissions.

**Stack:** Solidity · Ethereum · Foundry · OpenZeppelin · Sepolia

## Features

- ETH custody and agreement-specific smart contracts.
- Explicit finite-state machine.
- Independent buyer, seller and arbiter roles.
- Configurable delivery deadlines.
- Seller delivery declarations.
- Buyer approval before ordinary seller payment claims.
- Three-day buyer review period.
- Dispute creation and timeout-triggered arbitration.
- Authorized dispute resolution.
- Reentrancy protection and Checks-Effects-Interactions.
- Constructor and state validation.
- Unit, security, fuzz and invariant tests.
- Public Sepolia deployment with verified transaction history.

## Contract architecture

Each deployed `Escrow.sol` contract represents one agreement.

| Participant | Responsibilities |
|---|---|
| Buyer | Funds escrow, approves delivery, initiates disputes |
| Seller | Declares delivery and claims approved payment |
| Arbiter | Resolves disputed payments or refunds |

Participants and agreement parameters are configured at deployment and stored using immutable variables.

### State machine

| State | Meaning |
|---|---|
| `CREATED` | Agreement deployed but not funded |
| `FUNDED` | Agreed ETH amount is locked |
| `DELIVERED` | Seller has declared delivery |
| `APPROVED` | Buyer accepted delivery |
| `DISPUTED` | Agreement awaits arbitration |
| `RELEASED` | ETH transferred to seller |
| `REFUNDED` | ETH returned to buyer |
| `CANCELLED` | Agreement cancelled before funding |

### Successful payment

1. Buyer calls `fund()`.
2. Seller calls `markDelivered()`.
3. Buyer calls `approveDelivery()`.
4. Seller calls `claimPayment()`.
5. ETH transfers to the seller and the state becomes `RELEASED`.

### Dispute resolution

1. Seller declares delivery.
2. Buyer opens a dispute during the review window, or anyone triggers arbitration after an unanswered review period.
3. The contract enters `DISPUTED`.
4. The arbiter calls `resolveDispute(bool paySeller)`.
5. ETH is transferred to the selected recipient.

`true` pays the seller; `false` refunds the buyer.

Other supported flows include cancellation before funding, buyer refunds after missed delivery deadlines, and voluntary early payment while `FUNDED`.

## Deadline handling

Two separate time constraints are used:

**Delivery duration:** configured for each agreement and measured from the funding transaction. The seller must declare delivery before the deadline.

**Review period:** fixed at three days after `markDelivered()`.

Time passing does not execute blockchain transactions automatically. Authorized participants or external automation must submit the relevant calls.

## Security

- Role-specific permissions enforced through `msg.sender`.
- Explicit validation of allowed state transitions.
- OpenZeppelin `ReentrancyGuard`.
- Checks-Effects-Interactions around ETH transfers.
- Transaction atomicity if recipient transfers fail.
- Constructor validation for invalid actors and parameters.
- Buyer approval or arbiter decision required before payment following declared delivery.
- Prevention of repeated payments from terminal states.
- Dispute-state restrictions that prevent unilateral settlement.

### Known limitations

This is an educational protocol, **not an audited production system**.

The protocol relies on a trusted and available arbiter. Funds may become stuck if the arbiter is unavailable or the designated recipient permanently rejects ETH. Off-chain delivery quality cannot be independently verified by Solidity. Appeals, arbiter replacement, partial payments and automated transaction execution are not implemented.

Each deployment