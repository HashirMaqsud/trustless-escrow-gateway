# Security Specification & Threat Model

## 1. Access Control Matrix

| Function | Authorized Caller | Required State | Terminal State |
| :--- | :--- | :--- | :--- |
| `fund()` | `Client` | `Pending` | `Funded` |
| `submitDeliverable()` | `ServiceProvider` | `Funded` | `Delivered` |
| `releaseFunds()` | `Client` | `Delivered` | `Completed` |
| `raiseDispute()` | `Client` OR `ServiceProvider` | `Funded` OR `Delivered` | `Disputed` |
| `resolveDispute()` | `Arbiter` | `Disputed` | `Completed` |

## 2. Threat Analysis & Mitigations

### Reentrancy Attacks
* **Risk:** Malicious fallback functions triggering reentrancy during raw ETH payout executions to drain contract balances.
* **Mitigation:**
  1. Strict enforcement of the **Checks-Effects-Interactions (CEI)** pattern: State variables transition to `Completed` prior to invoking low-level external transfers.
  2. Integration of OpenZeppelin's `ReentrancyGuard` applying the `nonReentrant` modifier on all transfer paths.

### Unauthorized Fund Exfiltration
* **Risk:** Malicious arbiter or unauthorized participant redirecting escrowed funds to an external wallet.
* **Mitigation:** The contract contains no interface allowing arbitrary transfer targets. Payout recipients are immutably locked to the initialized `Client` and `ServiceProvider` addresses. Payout math strictly enforces that the sum of the refund and payout equals the total locked deposit (`clientRefund + freelancerPayout == amount`).

### Token Transfer Inconsistencies
* **Risk:** Non-standard ERC-20 tokens failing silently on transfers without reverting, leading to state desynchronization.
* **Mitigation:** Utilization of OpenZeppelin's `SafeERC20` wrapper library (`safeTransfer` and `safeTransferFrom`), enforcing proper revert handling for tokens with boolean or missing return values.

## 3. Automated Verification Pipelines
* **Slither Analysis:** Automated static analysis scans analyzing ASTs for uninitialized storage pointers, reentrancy vulnerabilities, and CEI compliance on every commit.
* **Foundry Fuzz & Invariant Testing:** Property-based tests verifying that transitions outside the defined state matrix fail deterministically and vault balances remain strictly solvent.