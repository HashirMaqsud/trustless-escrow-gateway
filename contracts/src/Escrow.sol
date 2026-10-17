// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

/**
 * @title Escrow
 * @notice Trustless milestone-based escrow state machine supporting ETH and ERC-20 tokens,
 *         with protocol fees and EIP-712 gasless meta-transactions for freelancers and arbiters.
 */
contract Escrow is ReentrancyGuard, EIP712 {
    using SafeERC20 for IERC20;

    enum State {
        Pending,
        Funded,
        Delivered,
        Completed,
        Disputed
    }

    // --- State Variables ---
    address public immutable CLIENT;
    address public immutable FREELANCER;
    address public immutable ARBITER;
    address public immutable FEE_RECIPIENT;

    IERC20 public immutable TOKEN; // address(0) indicates native ETH
    uint256 public immutable AMOUNT;
    uint256 public immutable FEE_AMOUNT;

    State public currentState;
    string public deliverableUrl;

    // Nonces for EIP-712 replay protection
    mapping(address => uint256) public nonces;

    // EIP-712 TypeHashes
    bytes32 private constant SUBMIT_DELIVERABLE_TYPEHASH =
        keccak256("SubmitDeliverable(address freelancer,string deliverableUrl,uint256 nonce,uint256 deadline)");

    bytes32 private constant RESOLVE_DISPUTE_TYPEHASH =
        keccak256("ResolveDispute(address arbiter,uint256 clientRefund,uint256 freelancerPayout,uint256 nonce,uint256 deadline)");

    // --- Events ---
    event EscrowFunded(address indexed client, uint256 amount, uint256 feePaid);
    event DeliverableSubmitted(address indexed freelancer, string deliverableUrl);
    event FundsReleased(address indexed freelancer, uint256 amount);
    event DisputeRaised(address indexed raisedBy);
    event DisputeResolved(uint256 clientRefund, uint256 freelancerPayout);

    // --- Custom Gas-Optimized Errors ---
    error Unauthorized();
    error InvalidState(State expected, State actual);
    error InvalidDepositAmount();
    error InvalidSplitAmount();
    error TransferFailed();
    error SignatureExpired();
    error InvalidSignature();

    // --- Modifiers ---
    modifier onlyClient() {
        _checkClient();
        _;
    }

    modifier onlyFreelancer() {
        _checkFreelancer();
        _;
    }

    modifier onlyArbiter() {
        _checkArbiter();
        _;
    }

    modifier inState(State _state) {
        _checkState(_state);
        _;
    }

    function _checkClient() internal view {
        if (msg.sender != CLIENT) revert Unauthorized();
    }

    function _checkFreelancer() internal view {
        if (msg.sender != FREELANCER) revert Unauthorized();
    }

    function _checkArbiter() internal view {
        if (msg.sender != ARBITER) revert Unauthorized();
    }

    function _checkState(State _state) internal view {
        if (currentState != _state) revert InvalidState(_state, currentState);
    }

    /**
     * @notice Initializes the Escrow contract instance.
     * @param _client Address funding the escrow.
     * @param _freelancer Service provider executing deliverables.
     * @param _arbiter Designated mediator for dispute resolution.
     * @param _feeRecipient Address collecting protocol fees to sustain the relayer.
     * @param _token Token address (address(0) for native ETH).
     * @param _amount Agreed contract value locked in escrow.
     * @param _feeBps Protocol fee in basis points (e.g. 100 = 1%).
     */
    constructor(
        address _client,
        address _freelancer,
        address _arbiter,
        address _feeRecipient,
        address _token,
        uint256 _amount,
        uint256 _feeBps
    ) EIP712("TrustlessEscrow", "1") {
        if (
            _client == address(0) ||
            _freelancer == address(0) ||
            _arbiter == address(0) ||
            _feeRecipient == address(0)
        ) {
            revert Unauthorized();
        }
        if (_amount == 0) revert InvalidDepositAmount();

        CLIENT = _client;
        FREELANCER = _freelancer;
        ARBITER = _arbiter;
        FEE_RECIPIENT = _feeRecipient;
        TOKEN = IERC20(_token);
        AMOUNT = _amount;
        FEE_AMOUNT = (_amount * _feeBps) / 10000;

        currentState = State.Pending;
    }

    /**
     * @notice Locks ETH or ERC-20 tokens into the vault and transfers protocol fee to the fee recipient.
     */
    function fund() external payable nonReentrant onlyClient inState(State.Pending) {
        currentState = State.Funded;
        uint256 totalRequired = AMOUNT + FEE_AMOUNT;

        if (address(TOKEN) == address(0)) {
            if (msg.value != totalRequired) revert InvalidDepositAmount();

            if (FEE_AMOUNT > 0) {
                (bool feeSuccess, ) = FEE_RECIPIENT.call{value: FEE_AMOUNT}("");
                if (!feeSuccess) revert TransferFailed();
            }
        } else {
            if (msg.value != 0) revert InvalidDepositAmount();

            TOKEN.safeTransferFrom(msg.sender, address(this), totalRequired);

            if (FEE_AMOUNT > 0) {
                TOKEN.safeTransfer(FEE_RECIPIENT, FEE_AMOUNT);
            }
        }

        emit EscrowFunded(msg.sender, AMOUNT, FEE_AMOUNT);
    }

    /**
     * @notice Direct milestone submission by freelancer.
     * @param _deliverableUrl URL pointing to submitted work.
     */
    function submitDeliverable(string calldata _deliverableUrl)
        external
        onlyFreelancer
        inState(State.Funded)
    {
        _executeDeliverableSubmission(_deliverableUrl);
    }

    /**
     * @notice Gasless milestone submission via EIP-712 signature (called by relayer).
     * @param _deliverableUrl URL pointing to submitted work.
     * @param _deadline Timestamp limit for signature validity.
     * @param _signature Cryptographic ECDSA signature from freelancer.
     */
    function submitDeliverableWithSig(
        string calldata _deliverableUrl,
        uint256 _deadline,
        bytes calldata _signature
    ) external inState(State.Funded) {
        if (block.timestamp > _deadline) revert SignatureExpired();

        bytes32 structHash = keccak256(
            abi.encode(
                SUBMIT_DELIVERABLE_TYPEHASH,
                FREELANCER,
                keccak256(bytes(_deliverableUrl)),
                nonces[FREELANCER]++,
                _deadline
            )
        );

        bytes32 digest = _hashTypedDataV4(structHash);
        address recoveredSigner = ECDSA.recover(digest, _signature);
        if (recoveredSigner != FREELANCER) revert InvalidSignature();

        _executeDeliverableSubmission(_deliverableUrl);
    }

    function _executeDeliverableSubmission(string calldata _deliverableUrl) internal {
        deliverableUrl = _deliverableUrl;
        currentState = State.Delivered;

        emit DeliverableSubmitted(FREELANCER, _deliverableUrl);
    }

    /**
     * @notice Client approves deliverables and releases full vault balance.
     */
    function releaseFunds() external nonReentrant onlyClient inState(State.Delivered) {
        currentState = State.Completed;
        emit FundsReleased(FREELANCER, AMOUNT);

        _payout(FREELANCER, AMOUNT);
    }

    /**
     * @notice Either client or freelancer can initiate a dispute.
     */
    function raiseDispute() external {
        if (msg.sender != CLIENT && msg.sender != FREELANCER) revert Unauthorized();
        if (currentState != State.Funded && currentState != State.Delivered) {
            revert InvalidState(State.Delivered, currentState);
        }

        currentState = State.Disputed;
        emit DisputeRaised(msg.sender);
    }

    /**
     * @notice Direct dispute resolution by arbiter.
     * @param _clientRefund Amount returned to client.
     * @param _freelancerPayout Amount transferred to freelancer.
     */
    function resolveDispute(uint256 _clientRefund, uint256 _freelancerPayout)
        external
        nonReentrant
        onlyArbiter
        inState(State.Disputed)
    {
        _executeDisputeResolution(_clientRefund, _freelancerPayout);
    }

    /**
     * @notice Gasless dispute resolution via EIP-712 signature (called by relayer).
     * @param _clientRefund Amount returned to client.
     * @param _freelancerPayout Amount transferred to freelancer.
     * @param _deadline Timestamp limit for signature validity.
     * @param _signature Cryptographic ECDSA signature from arbiter.
     */
    function resolveDisputeWithSig(
        uint256 _clientRefund,
        uint256 _freelancerPayout,
        uint256 _deadline,
        bytes calldata _signature
    ) external nonReentrant inState(State.Disputed) {
        if (block.timestamp > _deadline) revert SignatureExpired();

        bytes32 structHash = keccak256(
            abi.encode(
                RESOLVE_DISPUTE_TYPEHASH,
                ARBITER,
                _clientRefund,
                _freelancerPayout,
                nonces[ARBITER]++,
                _deadline
            )
        );

        bytes32 digest = _hashTypedDataV4(structHash);
        address recoveredSigner = ECDSA.recover(digest, _signature);
        if (recoveredSigner != ARBITER) revert InvalidSignature();

        _executeDisputeResolution(_clientRefund, _freelancerPayout);
    }

    function _executeDisputeResolution(uint256 _clientRefund, uint256 _freelancerPayout) internal {
        if (_clientRefund + _freelancerPayout != AMOUNT) revert InvalidSplitAmount();

        currentState = State.Completed;
        emit DisputeResolved(_clientRefund, _freelancerPayout);

        if (_clientRefund > 0) {
            _payout(CLIENT, _clientRefund);
        }
        if (_freelancerPayout > 0) {
            _payout(FREELANCER, _freelancerPayout);
        }
    }

    /**
     * @dev Internal payout dispatcher handling both native ETH and ERC-20 transfers.
     */
    function _payout(address _recipient, uint256 _amt) internal {
        if (address(TOKEN) == address(0)) {
            (bool success, ) = _recipient.call{value: _amt}("");
            if (!success) revert TransferFailed();
        } else {
            TOKEN.safeTransfer(_recipient, _amt);
        }
    }
}