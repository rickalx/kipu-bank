// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/**
 * @title KipuBank
 * @author Ricardo Flor
 * @notice Bóveda simple de tokens nativos (ETH) con umbral fijo de retiro por transacción
 *         y un límite global de depósitos (bankCap).
 * @dev Sigue el patrón checks-effects-interactions, usa errores personalizados,
 *      maneja ETH de forma segura mediante low-level call y expone eventos claros.
 */
contract KipuBank {
    /*//////////////////////////////////////////////////////////////
                                ERRORES
    //////////////////////////////////////////////////////////////*/

    /// @notice Cantidad cero no permitida.
    error ZeroAmount();

    /// @notice El depósito propuesto excede el límite global del banco.
    /// @param attempted Cantidad total que se intenta alcanzar (totalVault + msg.value).
    /// @param cap Límite máximo global permitido.
    error CapExceeded(uint256 attempted, uint256 cap);

    /// @notice El monto de retiro excede el umbral fijo por transacción.
    /// @param attempted Monto solicitado a retirar.
    /// @param threshold Umbral máximo permitido por transacción.
    error ThresholdExceeded(uint256 attempted, uint256 threshold);

    /// @notice El usuario no tiene suficiente saldo en su bóveda.
    /// @param balance Saldo disponible del usuario.
    /// @param attempted Monto solicitado.
    error InsufficientVault(uint256 balance, uint256 attempted);

    /// @notice No se permiten envíos directos de ETH sin usar la función `deposit`.
    error DirectETHNotAllowed();

    /// @notice Falló la transferencia nativa (ETH) al destinatario.
    error NativeTransferFailed();

    /// @notice Parámetros inválidos en el constructor.
    error InvalidConstructorParams();

    /*//////////////////////////////////////////////////////////////
                             EVENTOS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Emitido cuando un usuario deposita ETH en su bóveda.
     * @param account Dirección del depositante.
     * @param amount Cantidad depositada (en wei).
     * @param newBalance Nuevo saldo del depositante (en wei) después del depósito.
     * @param totalVault Nuevo total global en custodia (en wei) después del depósito.
     */
    event Deposited(address indexed account, uint256 amount, uint256 newBalance, uint256 totalVault);

    /**
     * @notice Emitido cuando un usuario retira ETH de su bóveda.
     * @param account Dirección del que retira.
     * @param amount Cantidad retirada (en wei).
     * @param newBalance Nuevo saldo del usuario (en wei) después del retiro.
     * @param totalVault Nuevo total global en custodia (en wei) después del retiro.
     */
    event Withdrawn(address indexed account, uint256 amount, uint256 newBalance, uint256 totalVault);

    /*//////////////////////////////////////////////////////////////
                         VARIABLES INMUTABLES
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Límite global de ETH (en wei) que puede custodiar el banco.
     * @dev Fijado en el despliegue; no puede cambiarse.
     */
    uint256 public immutable bankCap;

    /**
     * @notice Umbral máximo (en wei) que puede retirarse por transacción.
     * @dev Fijado en el despliegue; no puede cambiarse.
     */
    uint256 public immutable withdrawThreshold;

    /*//////////////////////////////////////////////////////////////
                         VARIABLES DE ALMACENAMIENTO
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Suma total de ETH (en wei) actualmente custodiada por el contrato.
     * @dev Se actualiza en depósitos y retiros; se prefiere a `address(this).balance`
     *      para evitar desalineaciones ante envíos forzados.
     */
    uint256 public totalVault;

    /**
     * @notice Conteo global de depósitos exitosos.
     */
    uint256 public depositCount;

    /**
     * @notice Conteo global de retiros exitosos.
     */
    uint256 public withdrawalCount;

    /**
     * @notice Saldo de bóveda por usuario (en wei).
     */
    mapping(address => uint256) private _vaults;

    /*//////////////////////////////////////////////////////////////
                             MODIFICADORES
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Garantiza que `amount` sea mayor que cero.
     * @param amount Cantidad a validar.
     */
    modifier nonZero(uint256 amount) {
        if (amount == 0) revert ZeroAmount();
        _;
    }

    /**
     * @notice Garantiza que `amount` no exceda el umbral de retiro por transacción.
     * @param amount Cantidad a validar.
     */
    modifier underThreshold(uint256 amount) {
        if (amount > withdrawThreshold) revert ThresholdExceeded(amount, withdrawThreshold);
        _;
    }

    /*//////////////////////////////////////////////////////////////
                             CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Inicializa el contrato con el límite global de depósitos y el umbral de retiro.
     * @param bankCap_ Límite global total de ETH en custodia (en wei).
     * @param withdrawThreshold_ Umbral máximo por retiro (en wei).
     * @dev Requiere parámetros válidos: ambos > 0 y `withdrawThreshold_ <= bankCap_`.
     */
    constructor(uint256 bankCap_, uint256 withdrawThreshold_) {
        if (bankCap_ == 0 || withdrawThreshold_ == 0 || withdrawThreshold_ > bankCap_) {
            revert InvalidConstructorParams();
        }
        bankCap = bankCap_;
        withdrawThreshold = withdrawThreshold_;
    }

    /*//////////////////////////////////////////////////////////////
                        FUNCIONES EXTERNAS (payable)
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Deposita ETH en la bóveda del `msg.sender`.
     * @dev Sigue CEI: checks (montos y cap) → effects (actualiza estado) → interactions (ninguna).
     *      No hay interacción externa; el ETH ya está adjunto en `msg.value`.
     * @custom:error ZeroAmount si `msg.value == 0`.
     * @custom:error CapExceeded si `totalVault + msg.value > bankCap`.
     */
    function deposit() external payable nonZero(msg.value) {
        uint256 newTotal = totalVault + msg.value;
        if (newTotal > bankCap) {
            revert CapExceeded(newTotal, bankCap);
        }

        // Effects
        _vaults[msg.sender] += msg.value;
        totalVault = newTotal;
        unchecked {
            depositCount += 1;
        }

        emit Deposited(msg.sender, msg.value, _vaults[msg.sender], totalVault);
    }

    /**
     * @notice Retira `amount` de la bóveda del `msg.sender` hacia su cuenta externa.
     * @param amount Monto a retirar (en wei).
     * @dev Sigue CEI: checks → effects → interactions (envío nativo seguro).
     * @custom:error ZeroAmount si `amount == 0`.
     * @custom:error ThresholdExceeded si `amount > withdrawThreshold`.
     * @custom:error InsufficientVault si el saldo del usuario es insuficiente.
     * @custom:error NativeTransferFailed si falla el envío de ETH.
     */
    function withdraw(uint256 amount)
        external
        nonZero(amount)
        underThreshold(amount)
    {
        uint256 balance = _vaults[msg.sender];
        if (balance < amount) revert InsufficientVault(balance, amount);

        // Effects
        unchecked {
            _vaults[msg.sender] = balance - amount;
            totalVault -= amount;
            withdrawalCount += 1;
        }

        // Interactions
        _sendETH(msg.sender, amount);

        emit Withdrawn(msg.sender, amount, _vaults[msg.sender], totalVault);
    }

    /*//////////////////////////////////////////////////////////////
                        FUNCIONES EXTERNAS (view)
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Devuelve el saldo de bóveda para una cuenta.
     * @param account Dirección a consultar.
     * @return balance Saldo en wei.
     */
    function vaultOf(address account) external view returns (uint256 balance) {
        return _vaults[account];
    }

    /**
     * @notice Retorna una vista compacta de la configuración inmutable.
     * @return cap Límite global del banco (wei).
     * @return threshold Umbral fijo por retiro (wei).
     */
    function getConfig() external view returns (uint256 cap, uint256 threshold) {
        return (bankCap, withdrawThreshold);
    }

    /*//////////////////////////////////////////////////////////////
                         FUNCIONES PRIVADAS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Envía ETH de forma segura usando `call`.
     * @param to Destinatario.
     * @param amount Monto en wei.
     * @dev No se reenvía gas fijo como `transfer`/`send`; se usa `call` y se valida el resultado.
     *      Mantiene CEI: solo se llama tras actualizar el estado.
     */
    function _sendETH(address to, uint256 amount) private {
        // solhint-disable-next-line avoid-low-level-calls
        (bool ok, ) = to.call{value: amount}("");
        if (!ok) revert NativeTransferFailed();
    }


    /*//////////////////////////////////////////////////////////////
                         RECEIVE / FALLBACK
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Evita depósitos accidentales vía `receive`. Fuerza el uso de `deposit()`.
     */
    receive() external payable {
        revert DirectETHNotAllowed();
    }

    /**
     * @dev Evita llamadas a funciones inexistentes con valor.
     */
    fallback() external payable {
        if (msg.value > 0) revert DirectETHNotAllowed();
        // De lo contrario, ignora silenciosamente llamadas sin valor.
    }
}
