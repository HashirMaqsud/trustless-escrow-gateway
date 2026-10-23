// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

/**
 * @title Escrow
 * @notice Production-grade trustless milestone escrow supporting ETH and ERC-20 tokens,
 *         dynamic relayer gas pool, hybrid IPFS submissions, tamper-proof timelocks,
 *         reentrancy safety, and 100% post-deposit EIP-712 gasless operations.
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

    struct Milestone {
        string description;
        uint256 amount;
        bool approved;
    }

    struct Submission {
        string deliverableUrl;
        string ipfsHash;
        string submissionNotes;
        uint256 milestoneIndex;
        uint256 submittedAt;
    }

    // --- Stakeholders & Immutable Addresses ---
    address public immutable CLIENT;
    address public immutable FREELANCER;
    address public immutable ARBITER;
    address public immutable FEE_RECIPIENT;

    IERC20 public immutable TOKEN; // address(0) indicates native ETH
    uint256 public immutable TOTAL_AMOUNT;
    uint256 public immutable PROTOCOL_FEE;
    uint256 public immutable RELAYER_FEE_PER_TX;
    uint256 public immutable TOTAL_RELAYER_POOL;

    // --- Strict Limits & Timelocks ---
    uint256 public constant MAX_REVISIONS_PER_MILESTONE = 3;
    uint256 public constant DEPOSIT_TIMEOUT = 30 days;
    uint256 public constant REVIEW_TIMEOUT = 14 days;

    // --- Mutable State Variables ---
    uint256 public fundedAt;
    uint256 public lastDeliveredAt;
    uint256 public totalReleased;
    State public currentState;

    Milestone[] public milestones;
    Submission[] private submissions;

    mapping(uint256 => uint256) public milestoneSubmissionCount;
    mapping(address => uint256) public nonces;

    // --- EIP-712 TypeHashes ---
    bytes32 public constant SUBMIT_DELIVERABLE_TYPEHASH =
        keccak256("SubmitDeliverable(address freelancer,string deliverableUrl,string ipfsHash,string submissionNotes,uint256 milestoneIndex,uint256 nonce,uint256 deadline)");

    bytes32 public constant RELEASE_MILESTONE_TYPEHASH =
        keccak256("ReleaseMilestone(address client,uint256 milestoneIndex,uint256 nonce,uint256 deadline)");

    bytes32 public constant RELEASE_ALL_FUNDS_TYPEHASH =
        keccak256("ReleaseAllFunds(address client,uint256 nonce,uint256 deadline)");

    bytes32 public constant RAISE_DISPUTE_TYPEHASH =
        keccak256("RaiseDispute(address sender,uint256 nonce,uint256 deadline)");

    bytes32 public constant RESOLVE_DISPUTE_TYPEHASH =
        keccak256("ResolveDispute(address arbiter,uint256 clientRefund,uint256 freelancerPayout,uint256 nonce,uint256 deadline)");

    // --- Events ---
    event EscrowFunded(address indexed client, uint256 amount, uint256 feePaid, uint256 relayerPool);
    event DeliverableSubmitted(address indexed freelancer, string deliverableUrl, string ipfsHash, uint256 milestoneIndex, uint256 revisionNumber);
    event MilestoneReleased(uint256 indexed milestoneIndex, uint256 amount);
    event FundsReleased(address indexed freelancer, uint256 amount);
    event DisputeRaised(address indexed raisedBy);
    event DisputeResolved(uint256 clientRefund, uint256 freelancerPayout);
    event RelayerReimbursed(address indexed relayer, uint256 feePaid);
    event InactivityRefundClaimed(address indexed client, uint256 amount);
    event ReviewTimeoutClaimed(address indexed freelancer, uint256 amount);
    event RelayerPoolRefunded(address indexed client, uint256 amount);

    // --- Custom Gas-Optimized Errors ---
    error Unauthorized();
    error InvalidState(State expected, State actual);
    error InvalidDepositAmount();
    error InvalidSplitAmount();
    error TransferFailed();
    error SignatureExpired();
    error InvalidSignature();
    error TimelockNotExpired();
    error MilestoneAlreadyApproved();
    error InvalidMilestoneIndex();
    error RevisionsLimitExceeded();
    error SubmissionsAlreadyExist();

    modifier onlyClient() {
        if (msg.sender != CLIENT) revert Unauthorized();
        _;
    }

    modifier onlyFreelancer() {
        if (msg.sender != FREELANCER) revert Unauthorized();
        _;
    }

    modifier onlyArbiter() {
        if (msg.sender != ARBITER) revert Unauthorized();
        _;
    }

    constructor(
        address _client,
        address _freelancer,
        address _arbiter,
        address _feeRecipient,
        address _token,
        uint256[] memory _milestoneAmounts,
        string[] memory _milestoneDescriptions,
        uint256 _feeBps,
        uint256 _relayerFeePerTx
    ) EIP712("TrustlessEscrow", "1") {
        if (_client == address(0) || _freelancer == address(0) || _arbiter == address(0) || _feeRecipient == address(0)) {
            revert Unauthorized();
        }
        if (_milestoneAmounts.length == 0 || _milestoneAmounts.length != _milestoneDescriptions.length) {
            revert InvalidDepositAmount();
        }

        CLIENT = _client;
        FREELANCER = _freelancer;
        ARBITER = _arbiter;
        FEE_RECIPIENT = _feeRecipient;
        TOKEN = IERC20(_token);

        // Economic Scale Fix: Safely handle 6-decimal tokens (USDC/USDT) without truncation
        if (_token != address(0)) {
            uint8 dec = 18;
            try IERC20Metadata(_token).decimals() returns (uint8 tokenDecimals) {
                dec = tokenDecimals;
            } catch {}

            if (dec <= 6) {
                RELAYER_FEE_PER_TX = 250_000; // 0.25 USDC/USDT
            } else if (dec < 18) {
                RELAYER_FEE_PER_TX = 250_000 * (10 ** (dec - 6));
            } else {
                RELAYER_FEE_PER_TX = _relayerFeePerTx;
            }
        } else {
            RELAYER_FEE_PER_TX = _relayerFeePerTx;
        }

        uint256 total = 0;
        for (uint256 i = 0; i < _milestoneAmounts.length; i++) {
            if (_milestoneAmounts[i] == 0) revert InvalidDepositAmount();
            milestones.push(Milestone({
                description: _milestoneDescriptions[i],
                amount: _milestoneAmounts[i],
                approved: false
            }));
            total += _milestoneAmounts[i];
        }

        TOTAL_AMOUNT = total;
        PROTOCOL_FEE = (total * _feeBps) / 10000;

        uint256 estimatedOperations = (_milestoneAmounts.length * (MAX_REVISIONS_PER_MILESTONE + 1)) + 2;
        TOTAL_RELAYER_POOL = RELAYER_FEE_PER_TX * estimatedOperations;

        currentState = State.Pending;
    }

    /**
     * @notice Locks ETH or ERC-20 tokens into the vault and transfers protocol fee to the fee recipient[cite: 2].
     */
    function fund() external payable nonReentrant onlyClient {
        if (currentState != State.Pending) revert InvalidState(State.Pending, currentState);

        currentState = State.Funded;
        fundedAt = block.timestamp;

        uint256 totalRequired = TOTAL_AMOUNT + PROTOCOL_FEE + TOTAL_RELAYER_POOL;

        if (address(TOKEN) == address(0)) {
            if (msg.value != totalRequired) revert InvalidDepositAmount();

            if (PROTOCOL_FEE > 0) {
                (bool feeSuccess, ) = FEE_RECIPIENT.call{value: PROTOCOL_FEE}("");
                if (!feeSuccess) revert TransferFailed();
            }
        } else {
            if (msg.value != 0) revert InvalidDepositAmount();

            TOKEN.safeTransferFrom(msg.sender, address(this), totalRequired);

            if (PROTOCOL_FEE > 0) {
                TOKEN.safeTransfer(FEE_RECIPIENT, PROTOCOL_FEE);
            }
        }

        emit EscrowFunded(msg.sender, TOTAL_AMOUNT, PROTOCOL_FEE, TOTAL_RELAYER_POOL);
    }

    // =============================================================
    //                    DELIVERABLE SUBMISSIONS
    // =============================================================

    function submitDeliverable(
        string calldata _deliverableUrl,
        string calldata _ipfsHash,
        string calldata _notes,
        uint256 _milestoneIndex
    ) external onlyFreelancer nonReentrant {
        _validateSubmissionState(_milestoneIndex);
        _executeDeliverableSubmission(_deliverableUrl, _ipfsHash, _notes, _milestoneIndex);
    }

    function submitDeliverableWithSig(
        string calldata _deliverableUrl,
        string calldata _ipfsHash,
        string calldata _notes,
        uint256 _milestoneIndex,
        uint256 _deadline,
        bytes calldata _signature
    ) external nonReentrant {
        _validateSubmissionState(_milestoneIndex);
        if (block.timestamp > _deadline) revert SignatureExpired();

        bytes32 structHash = keccak256(
            abi.encode(
                SUBMIT_DELIVERABLE_TYPEHASH,
                FREELANCER,
                keccak256(bytes(_deliverableUrl)),
                keccak256(bytes(_ipfsHash)),
                keccak256(bytes(_notes)),
                _milestoneIndex,
                nonces[FREELANCER]++,
                _deadline
            )
        );

        bytes32 digest = _hashTypedDataV4(structHash);
        address recoveredSigner = ECDSA.recover(digest, _signature);
        if (recoveredSigner != FREELANCER) revert InvalidSignature();

        _executeDeliverableSubmission(_deliverableUrl, _ipfsHash, _notes, _milestoneIndex);
        _reimburseRelayer();
    }

    function _validateSubmissionState(uint256 _milestoneIndex) internal view {
        if (currentState != State.Funded && currentState != State.Delivered) {
            revert InvalidState(State.Funded, currentState);
        }
        if (_milestoneIndex >= milestones.length) revert InvalidMilestoneIndex();
        if (milestones[_milestoneIndex].approved) revert MilestoneAlreadyApproved();
        if (milestoneSubmissionCount[_milestoneIndex] >= MAX_REVISIONS_PER_MILESTONE) {
            revert RevisionsLimitExceeded();
        }
    }

    function _executeDeliverableSubmission(
        string calldata _deliverableUrl,
        string calldata _ipfsHash,
        string calldata _notes,
        uint256 _milestoneIndex
    ) internal {
        milestoneSubmissionCount[_milestoneIndex]++;

        submissions.push(
            Submission({
                deliverableUrl: _deliverableUrl,
                ipfsHash: _ipfsHash,
                submissionNotes: _notes,
                milestoneIndex: _milestoneIndex,
                submittedAt: block.timestamp
            })
        );

        currentState = State.Delivered;
        lastDeliveredAt = block.timestamp;

        emit DeliverableSubmitted(
            FREELANCER,
            _deliverableUrl,
            _ipfsHash,
            _milestoneIndex,
            milestoneSubmissionCount[_milestoneIndex]
        );
    }

    // =============================================================
    //                 TRANCHES / MILESTONES RELEASES
    // =============================================================

    function releaseMilestone(uint256 _milestoneIndex) external nonReentrant onlyClient {
        _executeMilestoneRelease(_milestoneIndex);
    }

    function releaseMilestoneWithSig(
        uint256 _milestoneIndex,
        uint256 _deadline,
        bytes calldata _signature
    ) external nonReentrant {
        if (block.timestamp > _deadline) revert SignatureExpired();

        bytes32 structHash = keccak256(
            abi.encode(RELEASE_MILESTONE_TYPEHASH, CLIENT, _milestoneIndex, nonces[CLIENT]++, _deadline)
        );

        bytes32 digest = _hashTypedDataV4(structHash);
        address recoveredSigner = ECDSA.recover(digest, _signature);
        if (recoveredSigner != CLIENT) revert InvalidSignature();

        _reimburseRelayer();
        _executeMilestoneRelease(_milestoneIndex);
    }

    function _executeMilestoneRelease(uint256 _milestoneIndex) internal {
        if (currentState != State.Delivered && currentState != State.Funded) {
            revert InvalidState(State.Delivered, currentState);
        }
        if (_milestoneIndex >= milestones.length) revert InvalidMilestoneIndex();
        Milestone storage m = milestones[_milestoneIndex];
        if (m.approved) revert MilestoneAlreadyApproved();

        m.approved = true;
        totalReleased += m.amount;

        emit MilestoneReleased(_milestoneIndex, m.amount);

        // State Check: Return to Funded if more milestones remain
        if (totalReleased >= TOTAL_AMOUNT) {
            currentState = State.Completed;
            emit FundsReleased(FREELANCER, totalReleased);
        } else {
            currentState = State.Funded;
        }

        _payout(FREELANCER, m.amount);

        // Return unused relayer gas pool to client when all milestones are done
        if (currentState == State.Completed) {
            _refundRemainingPoolToClient();
        }
    }

    function releaseFunds() external nonReentrant onlyClient {
        _executeFullRelease();
    }

    function releaseFundsWithSig(uint256 _deadline, bytes calldata _signature) external nonReentrant {
        if (block.timestamp > _deadline) revert SignatureExpired();

        bytes32 structHash = keccak256(
            abi.encode(RELEASE_ALL_FUNDS_TYPEHASH, CLIENT, nonces[CLIENT]++, _deadline)
        );

        bytes32 digest = _hashTypedDataV4(structHash);
        address recoveredSigner = ECDSA.recover(digest, _signature);
        if (recoveredSigner != CLIENT) revert InvalidSignature();

        _reimburseRelayer();
        _executeFullRelease();
    }

    function _executeFullRelease() internal {
        if (currentState != State.Delivered && currentState != State.Funded) {
            revert InvalidState(State.Delivered, currentState);
        }

        // Set all milestones to approved for frontend synchronization
        for (uint256 i = 0; i < milestones.length; i++) {
            milestones[i].approved = true;
        }

        uint256 remainingToFreelancer = TOTAL_AMOUNT > totalReleased ? TOTAL_AMOUNT - totalReleased : 0;
        currentState = State.Completed;
        totalReleased = TOTAL_AMOUNT;

        emit FundsReleased(FREELANCER, remainingToFreelancer);

        if (remainingToFreelancer > 0) {
            _payout(FREELANCER, remainingToFreelancer);
        }

        // Return unused pool to client
        _refundRemainingPoolToClient();
    }

    // =============================================================
    //                       DISPUTES
    // =============================================================

    function raiseDispute() external nonReentrant {
        if (msg.sender != CLIENT && msg.sender != FREELANCER) revert Unauthorized();
        _executeRaiseDispute(msg.sender);
    }

    function raiseDisputeWithSig(address _sender, uint256 _deadline, bytes calldata _signature) external nonReentrant {
        if (_sender != CLIENT && _sender != FREELANCER) revert Unauthorized();
        if (block.timestamp > _deadline) revert SignatureExpired();

        bytes32 structHash = keccak256(
            abi.encode(RAISE_DISPUTE_TYPEHASH, _sender, nonces[_sender]++, _deadline)
        );

        bytes32 digest = _hashTypedDataV4(structHash);
        address recoveredSigner = ECDSA.recover(digest, _signature);
        if (recoveredSigner != _sender) revert InvalidSignature();

        _executeRaiseDispute(_sender);
        _reimburseRelayer();
    }

    function _executeRaiseDispute(address _sender) internal {
        if (currentState != State.Funded && currentState != State.Delivered) {
            revert InvalidState(State.Funded, currentState);
        }
        currentState = State.Disputed;
        emit DisputeRaised(_sender);
    }

    function resolveDispute(uint256 _clientRefund, uint256 _freelancerPayout) external nonReentrant onlyArbiter {
        if (currentState != State.Disputed) revert InvalidState(State.Disputed, currentState);
        _executeDisputeResolution(_clientRefund, _freelancerPayout);
    }

    function resolveDisputeWithSig(
        uint256 _clientRefund,
        uint256 _freelancerPayout,
        uint256 _deadline,
        bytes calldata _signature
    ) external nonReentrant {
        if (currentState != State.Disputed) revert InvalidState(State.Disputed, currentState);
        if (block.timestamp > _deadline) revert SignatureExpired();

        bytes32 structHash = keccak256(
            abi.encode(RESOLVE_DISPUTE_TYPEHASH, ARBITER, _clientRefund, _freelancerPayout, nonces[ARBITER]++, _deadline)
        );

        bytes32 digest = _hashTypedDataV4(structHash);
        address recoveredSigner = ECDSA.recover(digest, _signature);
        if (recoveredSigner != ARBITER) revert InvalidSignature();

        _reimburseRelayer();
        _executeDisputeResolution(_clientRefund, _freelancerPayout);
    }

    function _executeDisputeResolution(uint256 _clientRefund, uint256 _freelancerPayout) internal {
        uint256 lockedMilestonesBalance = TOTAL_AMOUNT > totalReleased ? TOTAL_AMOUNT - totalReleased : 0;
        
        // Mathematical invariant: Arbiter must account for 100% of disputed balance
        if (_clientRefund + _freelancerPayout != lockedMilestonesBalance) revert InvalidSplitAmount();

        currentState = State.Completed;
        emit DisputeResolved(_clientRefund, _freelancerPayout);

        if (_clientRefund > 0) {
            _payout(CLIENT, _clientRefund);
        }
        if (_freelancerPayout > 0) {
            _payout(FREELANCER, _freelancerPayout);
        }

        // Return remaining gas pool to client
        _refundRemainingPoolToClient();
    }

    // =============================================================
    //         TAMPER-PROOF EMERGENCY TIMELOCKS (ANTI-FREEZE)
    // =============================================================

    function claimInactivityRefund() external nonReentrant onlyClient {
        if (currentState != State.Funded) revert InvalidState(State.Funded, currentState);
        if (submissions.length != 0) revert SubmissionsAlreadyExist();
        if (block.timestamp < fundedAt + DEPOSIT_TIMEOUT) revert TimelockNotExpired();

        currentState = State.Completed;
        uint256 remaining = _getVaultBalance();
        emit InactivityRefundClaimed(CLIENT, remaining);

        _payout(CLIENT, remaining);
    }

    function claimReviewTimeoutPayout() external nonReentrant onlyFreelancer {
        if (currentState != State.Delivered) revert InvalidState(State.Delivered, currentState);
        if (block.timestamp < lastDeliveredAt + REVIEW_TIMEOUT) revert TimelockNotExpired();

        // Mark all remaining milestones approved for frontend consistency
        for (uint256 i = 0; i < milestones.length; i++) {
            milestones[i].approved = true;
        }

        currentState = State.Completed;
        uint256 remainingToFreelancer = TOTAL_AMOUNT > totalReleased ? TOTAL_AMOUNT - totalReleased : 0;
        totalReleased = TOTAL_AMOUNT;

        emit ReviewTimeoutClaimed(FREELANCER, remainingToFreelancer);

        if (remainingToFreelancer > 0) {
            _payout(FREELANCER, remainingToFreelancer);
        }

        // Return remaining gas pool balance to client
        _refundRemainingPoolToClient();
    }

    // =============================================================
    //                 INTERNAL HELPERS & PAYOUTS
    // =============================================================

    function _refundRemainingPoolToClient() internal {
        uint256 unusedPool = _getVaultBalance();
        if (unusedPool > 0) {
            _payout(CLIENT, unusedPool);
            emit RelayerPoolRefunded(CLIENT, unusedPool);
        }
    }

    function _reimburseRelayer() internal {
        if (RELAYER_FEE_PER_TX == 0) return;
        if (msg.sender == CLIENT || msg.sender == FREELANCER || msg.sender == ARBITER) return;

        uint256 bal = _getVaultBalance();
        if (bal >= RELAYER_FEE_PER_TX) {
            _payout(msg.sender, RELAYER_FEE_PER_TX);
            emit RelayerReimbursed(msg.sender, RELAYER_FEE_PER_TX);
        }
    }

    function _getVaultBalance() internal view returns (uint256) {
        if (address(TOKEN) == address(0)) {
            return address(this).balance;
        } else {
            return TOKEN.balanceOf(address(this));
        }
    }

    function _payout(address _recipient, uint256 _amt) internal {
        if (_amt == 0) return;

        if (address(TOKEN) == address(0)) {
            (bool success, ) = _recipient.call{value: _amt}("");
            if (!success) revert TransferFailed();
        } else {
            TOKEN.safeTransfer(_recipient, _amt);
        }
    }

    // =============================================================
    //                        VIEW HELPERS
    // =============================================================

    function getMilestonesCount() external view returns (uint256) {
        return milestones.length;
    }

    function getSubmissionsCount() external view returns (uint256) {
        return submissions.length;
    }

    function getSubmission(uint256 index) external view returns (Submission memory) {
        require(index < submissions.length, "Invalid index");
        return submissions[index];
    }

    function getLatestSubmission() external view returns (Submission memory) {
        if (submissions.length == 0) {
            return Submission("", "", "", 0, 0);
        }
        return submissions[submissions.length - 1];
    }
}