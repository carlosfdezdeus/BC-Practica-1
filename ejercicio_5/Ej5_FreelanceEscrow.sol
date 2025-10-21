// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.30;

/**
 * @title FreelanceEscrow
 * @notice Contrato de escrow para 2 personas (CLIENTE ↔ FREELANCER) con opción de árbitro.
 *         Flujo básico:
 *         1) El CLIENTE fondea exactamente `amount` (ETH) -> Funded
 *         2) El FREELANCER marca entrega -> Delivered
 *         3a) El CLIENTE aprueba -> pago al FREELANCER (Released)
 *         3b) Si hay disputa antes de que acabe el período de challenge -> Disputed
 *             El ÁRBITRO resuelve pagando total o parcialmente al FREELANCER -> Released/Refunded
 *         3c) Si el CLIENTE no actúa y vence el challengePeriod -> cualquiera puede liberar al FREELANCER
 *         4) Si vence el deadline sin entrega -> reembolso al CLIENTE (Refunded)
 *
 * @dev Sin dependencias externas. Incluye guardas anti-reentradas y errores personalizados.
 */
contract FreelanceEscrow {
    // --- Tipos y estados ---
    enum State { Created, Funded, Delivered, Disputed, Released, Refunded }

    // --- Roles ---
    address public immutable client;
    address public immutable freelancer;
    address public immutable arbiter; // puede ser address(0) si no se quiere árbitro

    // --- Parámetros del acuerdo ---
    uint256 public immutable amount;            // cantidad exacta a depositar en ETH (wei)
    uint256 public immutable deadline;          // fecha límite para entregar (unix timestamp)
    uint256 public immutable challengePeriod;   // ventana para disputar tras la entrega (segundos)

    // --- Estado dinámico ---
    State   public state = State.Created;
    uint256 public deliveredAt;   // timestamp de cuando el freelancer marca entrega
    bool    public disputed;      // bandera de disputa

    // --- Reentrancy lock ---
    bool private locked;

    // --- Eventos ---
    event Funded(address indexed client, uint256 amount);
    event Delivered(address indexed freelancer, uint256 when);
    event Disputed(address indexed by, uint256 when);
    event Refunded(address indexed to, uint256 value);
    event Released(address indexed to, uint256 value);
    event Resolved(address indexed arbiter, uint256 toFreelancer, uint256 toClient);

    // --- Errores personalizados ---
    error OnlyClient();
    error OnlyFreelancer();
    error OnlyArbiter();
    error InvalidState(State expected, State got);
    error WrongValue(uint256 expected, uint256 got);
    error DeadlineNotReached();
    error ChallengeNotOver();
    error ChallengeWindowOver();
    error NoArbiter();
    error AlreadyDisputed();

    // --- Modificadores ---
    modifier nonReentrant() {
        require(!locked, "Reentrancy");
        locked = true;
        _;
        locked = false;
    }

    modifier inState(State expected) {
        if (state != expected) revert InvalidState(expected, state);
        _;
    }

    modifier onlyClient() {
        if (msg.sender != client) revert OnlyClient();
        _;
    }

    modifier onlyFreelancer() {
        if (msg.sender != freelancer) revert OnlyFreelancer();
        _;
    }

    modifier onlyArbiter() {
        if (arbiter == address(0)) revert NoArbiter();
        if (msg.sender != arbiter) revert OnlyArbiter();
        _;
    }

    // --- Constructor ---
    /**
     * @param _client        Dirección del cliente.
     * @param _freelancer    Dirección del freelancer.
     * @param _arbiter       Dirección del árbitro (puede ser 0x0 si no se desea).
     * @param _amount        Importe exacto a depositar (wei).
     * @param _deadline      Timestamp límite para la entrega.
     * @param _challengePeriod Ventana de disputa en segundos tras la entrega.
     */
    constructor(
        address _client,
        address _freelancer,
        address _arbiter,
        uint256 _amount,
        uint256 _deadline,
        uint256 _challengePeriod
    ) {
        require(_client != address(0) && _freelancer != address(0), "Zero address");
        require(_amount > 0, "Amount=0");
        require(_deadline > block.timestamp, "Past deadline");
        require(_challengePeriod > 0, "Challenge=0");

        client = _client;
        freelancer = _freelancer;
        arbiter = _arbiter;
        amount = _amount;
        deadline = _deadline;
        challengePeriod = _challengePeriod;
    }

    // --- Funciones principales ---

    /// @notice El CLIENTE deposita exactamente `amount` ETH.
    function fund() external payable onlyClient inState(State.Created) nonReentrant {
        if (msg.value != amount) revert WrongValue(amount, msg.value);
        state = State.Funded;
        emit Funded(msg.sender, msg.value);
    }

    /// @notice El FREELANCER marca la entrega antes del `deadline`.
    function markDelivered() external onlyFreelancer inState(State.Funded) {
        if (block.timestamp > deadline) revert DeadlineNotReached(); // reutilizamos error para indicar vencimiento
        deliveredAt = block.timestamp;
        state = State.Delivered;
        emit Delivered(msg.sender, deliveredAt);
    }

    /// @notice El CLIENTE aprueba y libera el pago tras la entrega (si no hubo disputa).
    function approveRelease() external onlyClient inState(State.Delivered) nonReentrant {
        if (disputed) revert AlreadyDisputed();
        state = State.Released;
        _payFreelancer(amount);
        emit Released(freelancer, amount);
    }

    /// @notice Cualquiera puede liberar el pago si terminó la ventana de disputa y no hubo disputa.
    function releaseAfterChallenge() external inState(State.Delivered) nonReentrant {
        if (disputed) revert AlreadyDisputed();
        if (block.timestamp < deliveredAt + challengePeriod) revert ChallengeNotOver();
        state = State.Released;
        _payFreelancer(amount);
        emit Released(freelancer, amount);
    }

    /// @notice CLIENTE o FREELANCER pueden abrir disputa dentro de la ventana de challenge.
    function raiseDispute() external inState(State.Delivered) {
        if (block.timestamp > deliveredAt + challengePeriod) revert ChallengeWindowOver();
        if (msg.sender != client && msg.sender != freelancer) revert();
        if (disputed) revert AlreadyDisputed();
        disputed = true;
        state = State.Disputed;
        emit Disputed(msg.sender, block.timestamp);
    }

    /// @notice El ÁRBITRO resuelve una disputa y reparte fondos.
    /// @param payToFreelancer Cantidad en wei que recibe el freelancer (el resto va al cliente).
    function resolveDispute(uint256 payToFreelancer) external onlyArbiter inState(State.Disputed) nonReentrant {
        require(payToFreelancer <= amount, "Too much");
        uint256 toClient = amount - payToFreelancer;
        state = State.Released;

        if (payToFreelancer > 0) _payFreelancer(payToFreelancer);
        if (toClient > 0) _refundClient(toClient);

        emit Resolved(msg.sender, payToFreelancer, toClient);
    }

    /// @notice Reembolso al CLIENTE si vence el plazo y no hubo entrega.
    function refundIfDeadlinePassed() external inState(State.Funded) nonReentrant {
        if (block.timestamp <= deadline) revert DeadlineNotReached();
        state = State.Refunded;
        _refundClient(address(this).balance);
        emit Refunded(client, amount);
    }

    // --- Internas ---
    function _payFreelancer(uint256 value) internal {
        (bool ok, ) = payable(freelancer).call{value: value}("");
        require(ok, "pay fail");
    }

    function _refundClient(uint256 value) internal {
        (bool ok, ) = payable(client).call{value: value}("");
        require(ok, "refund fail");
    }

    // --- Auxiliares de vista ---
    function timeLeftToDeadline() external view returns (int256) {
        return int256(deadline) - int256(block.timestamp);
    }

    function timeLeftToAutoRelease() external view returns (int256) {
        if (state != State.Delivered) return -1;
        return int256(deliveredAt + challengePeriod) - int256(block.timestamp);
    }

    receive() external payable {
        // no admitir envíos directos fuera de fund()
        revert("Use fund()");
    }
}
