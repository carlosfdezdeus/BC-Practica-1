# Ejercicio 5 — Contrato inteligente: FreelanceEscrow

**Objetivo**: contrato de escrow entre **CLIENTE** y **FREELANCER** con opción de **ÁRBITRO**, que automatiza pagos, disputas y reembolsos usando Ethereum.

## 1) Análisis (por qué blockchain)
- Pagos condicionados y transparentes sin confianza entre partes (automatizados por código).
- Prueba inmutable de eventos (fundeado, entrega, disputas, resolución).
- Eliminación de terceros de custodia salvo árbitro opcional, con reglas públicas.

## 2) Diseño
**Roles**: `client`, `freelancer`, `arbiter (opcional)`  
**Datos clave**: `amount`, `deadline`, `challengePeriod`, `state`, `deliveredAt`, `disputed`  
**Estados**: `Created → Funded → Delivered → (Disputed → Resolved) | Released | Refunded`  
**Reglas**:
- El cliente deposita exactamente `amount`.
- El freelancer marca entrega antes de `deadline`.
- El cliente puede aprobar y pagar; si no actúa, cualquiera puede **liberar** tras el `challengePeriod`.
- Si hay disputa dentro del `challengePeriod`, el **árbitro** reparte total/parcialmente.
- Si vence `deadline` sin entrega, el cliente recupera fondos.

## 3) Implementación
- Archivo: `Ej5_FreelanceEscrow.sol`; Solidity `^0.8.30`.
- Sin dependencias externas; anti-reentradas con `nonReentrant`.
- Eventos para auditoría on-chain.

## 4) Pruebas (Remix IDE)
1. Abrir https://remix.ethereum.org → crear `contracts/Ej5_FreelanceEscrow.sol` y pegar el código.
2. Compilar con `0.8.30`.
3. Deploy (`Remix VM`):
   - `client` = account[0], `freelancer` = account[1], `arbiter` = account[2]
   - `amount` = p.ej. `100000000000000000` (0.1 ETH), `deadline` = `now + 1 day`, `challengePeriod` = `600` (10 min).
4. **Camino feliz**:
   - Con `account[0]` ejecutar `fund` con `Value` = `amount` → `state=Funded`.
   - Con `account[1]` ejecutar `markDelivered` → `state=Delivered`.
   - Con `account[0]` ejecutar `approveRelease` → saldo de `account[1]` sube, `state=Released`.
5. **Auto-release** (sin acción del cliente):
   - Re-deploy con `challengePeriod` corto (p.ej. 60s). Entregar. Esperar >60s. Llamar `releaseAfterChallenge` desde cualquiera.
6. **Disputa**:
   - Tras `markDelivered`, llamar `raiseDispute`. Con `account[2]` (árbitro), ejecutar `resolveDispute(payToFreelancer)` con reparto deseado.
7. **Reembolso por vencimiento**:
   - Re-deploy con `deadline` muy próximo, **no** llamar `markDelivered`. Tras vencer, llamar `refundIfDeadlinePassed` y verificar reembolso.
8. Verificar eventos y estados en **Logs** de Remix.

## 5) Despliegue en testnet (opcional)
- Conectar MetaMask a **Sepolia**, obtener ETH de faucet, y desplegar desde Remix con “Injected Provider - MetaMask”.
- Ver transacciones en https://sepolia.etherscan.io/

---

## Repositorio
- Subir este `.sol` y este `README` a GitHub/GitLab junto con capturas de pruebas.
