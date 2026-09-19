// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title Escrow
 * @notice Trustless milestone-based escrow state machine supporting ETH and ERC-20 tokens.
 */
contract Escrow is ReentrancyGuard {
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

    IERC20 public immutable TOKEN; // address(0) indicates native ETH
    uint256 public immutable AMOUNT;

    State public currentState;
    string public deliverableUrl;

    // --- Events ---
    event EscrowFunded(address indexed client, uint256 amount);
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
     * @param _token Token address (address(0) for native ETH).
     * @param _amount Agreed contract value locked in escrow.
     */
    constructor(
        address _client,
        address _freelancer,
        address _arbiter,
        address _token,
        uint256 _amount
    ) {
        if (_client == address(0) || _freelancer == address(0) || _arbiter == address(0)) {
            revert Unauthorized();
        }
        if (_amount == 0) revert InvalidDepositAmount();

        CLIENT = _client;
        FREELANCER = _freelancer;
        ARBITER = _arbiter;
        TOKEN = IERC20(_token);
        AMOUNT = _amount;

        currentState = State.Pending;
    }

    /**
     * @notice Locks ETH or ERC-20 tokens into the vault.
     */
    function fund() external payable nonReentrant onlyClient inState(State.Pending) {
        currentState = State.Funded;

        if (address(TOKEN) == address(0)) {
            if (msg.value != AMOUNT) revert InvalidDepositAmount();
        } else {
            if (msg.value != 0) revert InvalidDepositAmount();
            TOKEN.safeTransferFrom(msg.sender, address(this), AMOUNT);
        }

        emit EscrowFunded(msg.sender, AMOUNT);
    }

    /**
     * @notice Freelancer submits proof of work.
     * @param _deliverableUrl URL pointing to submitted work.
     */
    function submitDeliverable(string calldata _deliverableUrl)
        external
        onlyFreelancer
        inState(State.Funded)
    {
        deliverableUrl = _deliverableUrl;
        currentState = State.Delivered;

        emit DeliverableSubmitted(msg.sender, _deliverableUrl);
    }

    /**
     * @notice Client approves deliverables and releases full vault balance.
     */
    function releaseFunds() external nonReentrant onlyClient inState(State.Delivered) {
        // Checks-Effects-Interactions (CEI): State and events updated BEFORE external call
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
     * @notice Arbiter resolves dispute by splitting funds between parties.
     * @param _clientRefund Amount returned to client.
     * @param _freelancerPayout Amount transferred to freelancer.
     */
    function resolveDispute(uint256 _clientRefund, uint256 _freelancerPayout)
        external
        nonReentrant
        onlyArbiter
        inState(State.Disputed)
    {
        if (_clientRefund + _freelancerPayout != AMOUNT) revert InvalidSplitAmount();

        // Checks-Effects-Interactions
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