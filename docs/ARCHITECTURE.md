# Architecture Specification: Milestone-Based Trustless Escrow

## 1. System Overview
The Trustless Escrow Payment Gateway is a non-custodial milestone payment protocol designed to eliminate counterparty risk between clients and service providers without relying on centralized intermediaries.

## 2. State Machine Design
The lifecycle of every escrow instance is governed by an immutable finite state machine:


```

[ Pending ] ──(fund)──► [ Funded ] ──(submitDeliverable)──► [ Delivered ] ──(releaseFunds)──► [ Completed ]
│                                     │
└──(raiseDispute)──┐   ┌──(raiseDispute)┘
▼   ▼
[ Disputed ]
│
(resolveDispute)
│
▼
[ Completed ]

```

### State Definitions
* **Pending:** Initial state post-instantiation. Awaiting client deposit.
* **Funded:** Client funds locked in the contract vault. Service provider executes work off-chain.
* **Delivered:** Service provider submits deliverable reference (URI/hash). Funds remain locked pending review.
* **Completed:** Terminal state. Vault balance distributed to recipient(s).
* **Disputed:** Automated flows paused. Fund resolution delegated strictly to the arbiter.

## 3. Factory & Deployment Architecture
* **Factory Pattern (`EscrowFactory.sol`):** Acts as an immutable registry and deterministic deployer.
* **Minimal Proxies (EIP-1167):** Deploys lightweight clone contracts pointing to a master `Escrow.sol` logic contract to minimize gas overhead during project creation.

## 4. Multi-Asset Compatibility
* **Native Currency:** Direct handling of Ethereum (Sepolia ETH) via `.call{value: amount}("")`.
* **ERC-20 Standard:** Integrates OpenZeppelin's `SafeERC20` wrapper for testnet USDC/USDT to handle non-standard return values securely.

## 5. Web3 Integration Stack
* **Frontend:** Next.js 15 (App Router), TypeScript, Tailwind CSS.
* **Contract Interface:** Wagmi v2 and Viem hooks for reactive state synchronization.
* **Wallet Abstraction:** RainbowKit connector modal.
* **Historical Indexing:** Etherscan API integration for event timestamps and transaction verification.