# 🏦 KipuBank

KipuBank es un contrato inteligente escrito en Solidity que implementa una **bóveda de depósitos en ETH** con reglas de seguridad estrictas:

- Los usuarios pueden **depositar ETH** en su bóveda personal.
- Pueden **retirar ETH**, pero únicamente hasta un **umbral fijo por transacción** (`withdrawThreshold`).
- El contrato impone un **límite global de depósitos** (`bankCap`).
- Se lleva un registro de:
  - Depósitos por usuario (`vaultOf(address)`).
  - Conteo global de depósitos (`depositCount`).
  - Conteo global de retiros (`withdrawalCount`).
- Los depósitos y retiros emiten **eventos detallados** (`Deposited`, `Withdrawn`).
- Se aplican **errores personalizados** para revertir condiciones inválidas.

Este contrato sigue buenas prácticas modernas de seguridad:
- Uso de **CEI (Checks → Effects → Interactions)**.
- Transferencias de ETH con `call` y verificación de éxito.
- `receive` y `fallback` bloqueados para evitar envíos accidentales.
- Variables inmutables y bien documentadas.

---

## 🚀 Despliegue con Remix IDE

### Pasos

1. Abre [Remix IDE](https://remix.ethereum.org/).  
2. Crea un nuevo archivo en la carpeta `contracts/` llamado `KipuBank.sol`.  
3. Copia y pega el código del contrato.  
4. Compila el contrato usando el compilador de Solidity `^0.8.24` o superior.  
5. Ve a la pestaña **Deploy & Run Transactions**.  
6. Selecciona el contrato `KipuBank` en el desplegable.  
7. Ingresa los parámetros del constructor:  
   - `bankCap`: límite global en wei (ejemplo: `100000000000000000000` para `100 ether`).  
   - `withdrawThreshold`: umbral máximo de retiro por transacción en wei (ejemplo: `1000000000000000000` para `1 ether`).  
8. Haz clic en **Deploy**.  
9. El contrato estará desplegado y listo para usarse en la red seleccionada (JavaScript VM, Injected Provider, o una red real como Sepolia/Mainnet).  

---

## 💻 Interacción

### 1. Depositar ETH
En Remix, selecciona la función `deposit()` y especifica el valor en ETH en el campo **Value**.  
Ejemplo:  
- Seleccionar `deposit`  
- Poner `2` en el campo Value (ETH)  
- Ejecutar  

### 2. Retirar ETH
En Remix, selecciona la función `withdraw(uint256 amount)` y especifica el monto en wei.  
Ejemplo:  
- `amount = 500000000000000000` (`0.5 ether`)  
- Ejecutar  

### 3. Consultar saldo de bóveda
En Remix, llama a la función `vaultOf(address account)` con la dirección de interés.  

### 4. Consultar configuración inmutable
En Remix, llama a la función `getConfig()` para ver los valores de `bankCap` y `withdrawThreshold`.  

---

## 🔧 Mejoras adicionales implementadas

Además de los requisitos básicos, el contrato incluye mejoras que fortalecen seguridad, consistencia y usabilidad.  

### 1. `receive` / `fallback` bloqueados
- **Problema sin esto**: Si alguien envía ETH directo o un contrato usa `selfdestruct` para forzar un depósito, el ETH entra sin actualizar `totalVault`. Esto genera **desincronización** entre la contabilidad interna y el balance real del contrato.
- **Solución aplicada**: Ambos métodos revierten si entra ETH sin pasar por `deposit()`. De esta manera, todos los depósitos siguen un único flujo auditado.

---

### 2. Errores personalizados
- **Problema sin esto**: Usar `require("mensaje")` consume más gas y no es fácil de parsear en UIs o herramientas.
- **Solución aplicada**: Se definen errores como `ZeroAmount()`, `CapExceeded(...)`, `InsufficientVault(...)`.  
  Estos devuelven datos ABI que pueden ser leídos eficientemente por frontends y scripts.

---

### 3. Contadores de depósitos y retiros
- **Problema sin esto**: Solo se puede saber el historial revisando logs de eventos.  
- **Solución aplicada**: Variables `depositCount` y `withdrawalCount` permiten métricas rápidas sin leer todo el historial en la blockchain.

---

### 4. Inmutables en lugar de variables mutables
- **Problema sin esto**: Si `bankCap` o `withdrawThreshold` fueran mutables, un admin podría cambiar las reglas y romper expectativas de los usuarios.
- **Solución aplicada**: Se marcan como `immutable`, asegurando que nunca cambien tras el despliegue.

---

### 5. Transferencia de ETH con `call` y revert explícito
- **Problema sin esto**: Usar `transfer` o `send` limita gas a 2300, lo que puede romper compatibilidad con wallets o contratos que necesitan más gas al recibir ETH.
- **Solución aplicada**: `_sendETH()` usa `call{value: amount}("")` y revierte con `NativeTransferFailed()` si falla, garantizando seguridad y compatibilidad.

---

### 6. Bloqueo de depósitos de valor `0`
- **Problema sin esto**: Llamadas con `msg.value = 0` incrementarían `depositCount` sin cambiar balances → ruido en métricas y posible abuso.  
- **Solución aplicada**: Modificador `nonZero` revierte con `ZeroAmount()`.

---

## 📖 Referencias
- [NatSpec en Solidity](https://docs.soliditylang.org/en/latest/natspec-format.html)  
- [Checks-Effects-Interactions](https://solidity-by-example.org/hacks/re-entrancy/)  
- [Solidity docs: receive / fallback](https://docs.soliditylang.org/en/latest/contracts.html#receive-ether-function)

---
