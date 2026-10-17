'use client';

import { useState } from 'react';
import { useAccount, useReadContract } from 'wagmi';
import { parseEther, zeroAddress } from 'viem';
import { EscrowState } from '@/constants/contracts';
import { useEscrowActions } from '@/hooks/useEscrowActions';
import { useGaslessDeliverable } from '@/hooks/useGaslessDeliverable';
import { Check, Copy, Loader2, Sparkles } from 'lucide-react';

interface ActionPanelProps {
  escrowAddress: `0x${string}`;
  client: `0x${string}` | undefined;
  freelancer: `0x${string}` | undefined;
  arbiter: `0x${string}` | undefined;
  token?: `0x${string}` | undefined;
  amount: bigint | undefined;
  currentState: EscrowState | undefined;
  deliverableUrl: string | undefined;
  onActionSuccess: () => void;
}

const ERC20_ALLOWANCE_ABI = [
  {
    name: 'allowance',
    type: 'function',
    stateMutability: 'view',
    inputs: [
      { name: 'owner', type: 'address' },
      { name: 'spender', type: 'address' },
    ],
    outputs: [{ name: '', type: 'uint256' }],
  },
] as const;

const ESCROW_NONCE_ABI = [
  {
    name: 'nonces',
    type: 'function',
    stateMutability: 'view',
    inputs: [{ name: '', type: 'address' }],
    outputs: [{ name: '', type: 'uint256' }],
  },
] as const;

export function ActionPanel({
  escrowAddress,
  client,
  freelancer,
  arbiter,
  token,
  amount,
  currentState,
  deliverableUrl,
  onActionSuccess,
}: ActionPanelProps) {
  const { address } = useAccount();
  const {
    approveToken,
    fundEscrow,
    releaseFunds,
    raiseDispute,
    resolveDispute,
  } = useEscrowActions(escrowAddress);

  const { submitGaslessDeliverable } = useGaslessDeliverable();

  // Granular action state to isolate loader spinners between buttons
  const [activeAction, setActiveAction] = useState<string | null>(null);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);
  const [inputUrl, setInputUrl] = useState('');
  const [refundEth, setRefundEth] = useState('');
  const [payoutEth, setPayoutEth] = useState('');
  const [copied, setCopied] = useState(false);

  const isEth = !token || token === zeroAddress;

  // Read current nonce for the freelancer to supply into EIP-712 payload
  const { data: freelancerNonce, refetch: refetchNonce } = useReadContract({
    address: escrowAddress,
    abi: ESCROW_NONCE_ABI,
    functionName: 'nonces',
    args: address ? [address] : undefined,
    query: {
      enabled: !!address,
    },
  });

  // Read ERC-20 allowance if this escrow uses a custom token
  const { data: allowance, refetch: refetchAllowance } = useReadContract({
    address: !isEth ? token : undefined,
    abi: ERC20_ALLOWANCE_ABI,
    functionName: 'allowance',
    args: address && !isEth ? [address, escrowAddress] : undefined,
    query: {
      enabled: !isEth && !!address,
    },
  });

  const isClient = address?.toLowerCase() === client?.toLowerCase();
  const isFreelancer = address?.toLowerCase() === freelancer?.toLowerCase();
  const isArbiter = address?.toLowerCase() === arbiter?.toLowerCase();

  const handleCopyLink = () => {
    navigator.clipboard.writeText(window.location.href);
    setCopied(true);
    setTimeout(() => setCopied(false), 2000);
  };

  // Gasless submission execution handler
  const handleFreelancerSubmit = async () => {
    if (!inputUrl) return;
    setErrorMessage(null);
    setActiveAction('submitDeliverable');

    try {
      const currentNonce = freelancerNonce !== undefined ? freelancerNonce : BigInt(0);
      await submitGaslessDeliverable({
        escrowAddress,
        deliverableUrl: inputUrl,
        nonce: currentNonce,
      });
      await refetchNonce();
      onActionSuccess();
    } catch (err: unknown) {
      const msg = err instanceof Error ? err.message : 'Meta-transaction relay failed';
      setErrorMessage(msg);
    } finally {
      setActiveAction(null);
    }
  };

  if (!address) {
    return (
      <div className="bg-zinc-900 border border-zinc-800 p-6 rounded-xl text-center text-zinc-400">
        Connect your wallet to interact with this contract.
      </div>
    );
  }

  if (!isClient && !isFreelancer && !isArbiter) {
    return (
      <div className="bg-zinc-900 border border-zinc-800 p-6 rounded-xl text-center">
        <p className="text-zinc-400 text-sm">
          Connected wallet is an <span className="text-amber-400 font-medium">Observer</span>. Only designated participants (Client, Freelancer, Arbiter) can sign transactions.
        </p>
      </div>
    );
  }

  const hasSufficientAllowance = isEth || (allowance !== undefined && amount !== undefined && allowance >= amount);
  const isAnyLoading = activeAction !== null;

  return (
    <div className="bg-zinc-900 border border-zinc-800 rounded-xl p-6">
      <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4 mb-6 pb-4 border-b border-zinc-800">
        <div>
          <h3 className="text-lg font-bold text-white">
            Available Actions
          </h3>
          <span className="text-xs text-indigo-400 font-medium">
            Active Role: {isClient ? 'Client (Vault Owner)' : isFreelancer ? 'Freelancer (Service Provider)' : 'Arbiter (Mediator)'}
          </span>
        </div>

        <button
          onClick={handleCopyLink}
          className="px-3 py-1.5 bg-zinc-800 hover:bg-zinc-700 text-zinc-300 text-xs font-semibold rounded-lg border border-zinc-700 flex items-center justify-center gap-1.5 transition self-start sm:self-auto"
        >
          {copied ? <Check className="w-3.5 h-3.5 text-emerald-400" /> : <Copy className="w-3.5 h-3.5" />}
          {copied ? '✓ Link Copied' : '📋 Share Agreement Link'}
        </button>
      </div>

      {errorMessage && (
        <div className="mb-4 p-3 bg-red-950/40 border border-red-800/60 rounded-lg text-red-300 text-xs">
          {errorMessage}
        </div>
      )}

      {/* Deliverable Review (Client/Freelancer/Arbiter can see) */}
      {deliverableUrl && (
        <div className="bg-zinc-950 p-4 rounded-lg border border-zinc-800 mb-6">
          <span className="text-xs uppercase text-zinc-500 font-semibold tracking-wider">Submitted Deliverable</span>
          <p className="mt-1 break-all">
            <a
              href={deliverableUrl}
              target="_blank"
              rel="noopener noreferrer"
              className="text-indigo-400 hover:text-indigo-300 underline text-sm"
            >
              {deliverableUrl}
            </a>
          </p>
        </div>
      )}

      {/* 1. CLIENT ACTIONS */}
      {isClient && (
        <div className="space-y-4">
          {currentState === EscrowState.Pending && (
            <div className="space-y-3">
              {!isEth && !hasSufficientAllowance ? (
                <button
                  onClick={async () => {
                    if (token && amount) {
                      try {
                        setActiveAction('approve');
                        await approveToken(token, amount);
                        refetchAllowance();
                      } finally {
                        setActiveAction(null);
                      }
                    }
                  }}
                  disabled={isAnyLoading}
                  className="w-full py-2.5 px-4 bg-amber-600 hover:bg-amber-500 disabled:opacity-50 text-white rounded-lg font-semibold text-sm transition flex items-center justify-center gap-2"
                >
                  {activeAction === 'approve' ? (
                    <>
                      <Loader2 className="w-4 h-4 animate-spin" />
                      <span>Approving Tokens...</span>
                    </>
                  ) : (
                    'Step 1: Approve ERC-20 Tokens'
                  )}
                </button>
              ) : (
                <button
                  onClick={async () => {
                    if (amount) {
                      try {
                        setActiveAction('fund');
                        await fundEscrow(amount, token);
                        onActionSuccess();
                      } finally {
                        setActiveAction(null);
                      }
                    }
                  }}
                  disabled={isAnyLoading}
                  className="w-full py-2.5 px-4 bg-indigo-600 hover:bg-indigo-500 disabled:opacity-50 text-white rounded-lg font-semibold text-sm transition flex items-center justify-center gap-2"
                >
                  {activeAction === 'fund' ? (
                    <>
                      <Loader2 className="w-4 h-4 animate-spin" />
                      <span>Confirming Deposit...</span>
                    </>
                  ) : (
                    `Deposit Agreed Funds into Vault (${isEth ? 'ETH' : 'ERC-20'})`
                  )}
                </button>
              )}
            </div>
          )}

          {currentState === EscrowState.Funded && (
            <div className="p-4 rounded-lg bg-zinc-950/70 border border-zinc-800 text-center">
              <p className="text-sm text-zinc-300 font-medium">
                Vault is funded. Awaiting deliverable submission from freelancer.
              </p>
              <p className="text-xs text-zinc-500 mt-1">
                Share this page URL with your freelancer so they can submit their work.
              </p>
            </div>
          )}

          {currentState === EscrowState.Delivered && (
            <button
              onClick={async () => {
                try {
                  setActiveAction('release');
                  await releaseFunds();
                  onActionSuccess();
                } finally {
                  setActiveAction(null);
                }
              }}
              disabled={isAnyLoading}
              className="w-full py-2.5 px-4 bg-emerald-600 hover:bg-emerald-500 disabled:opacity-50 text-white rounded-lg font-semibold text-sm transition flex items-center justify-center gap-2"
            >
              {activeAction === 'release' ? (
                <>
                  <Loader2 className="w-4 h-4 animate-spin" />
                  <span>Releasing Funds...</span>
                </>
              ) : (
                'Approve Deliverable & Release Funds'
              )}
            </button>
          )}

          {(currentState === EscrowState.Funded || currentState === EscrowState.Delivered) && (
            <button
              onClick={async () => {
                try {
                  setActiveAction('dispute');
                  await raiseDispute();
                  onActionSuccess();
                } finally {
                  setActiveAction(null);
                }
              }}
              disabled={isAnyLoading}
              className="w-full py-2 px-4 bg-red-950/40 hover:bg-red-900/60 border border-red-800 text-red-300 rounded-lg text-sm font-medium transition flex items-center justify-center gap-2 disabled:opacity-50"
            >
              {activeAction === 'dispute' ? (
                <>
                  <Loader2 className="w-4 h-4 animate-spin" />
                  <span>Raising Dispute...</span>
                </>
              ) : (
                'Raise Dispute (Invoke Arbiter)'
              )}
            </button>
          )}
        </div>
      )}

      {/* 2. FREELANCER ACTIONS (Zero-Gas Submission) */}
      {isFreelancer && (
        <div className="space-y-4">
          {currentState === EscrowState.Pending && (
            <div className="p-4 rounded-lg bg-zinc-950/70 border border-zinc-800 text-center text-zinc-400 text-sm">
              Awaiting client deposit. Do not begin work until funds are locked in the vault.
            </div>
          )}

          {currentState === EscrowState.Funded && (
            <div className="space-y-2">
              <div className="flex items-center justify-between">
                <label className="text-xs text-zinc-400 uppercase font-medium">Proof of Work (URL)</label>
                <span className="text-[11px] text-emerald-400 flex items-center gap-1">
                  <Sparkles className="w-3 h-3" /> Gasless (Sponsored by Protocol)
                </span>
              </div>
              <input
                type="url"
                value={inputUrl}
                onChange={(e) => setInputUrl(e.target.value)}
                placeholder="https://github.com/..."
                disabled={isAnyLoading}
                className="w-full bg-zinc-950 border border-zinc-800 rounded-lg p-2.5 text-sm text-white focus:outline-none focus:border-indigo-500"
              />
              <button
                onClick={handleFreelancerSubmit}
                disabled={isAnyLoading || !inputUrl}
                className="w-full py-2.5 px-4 bg-indigo-600 hover:bg-indigo-500 disabled:opacity-50 text-white rounded-lg font-semibold text-sm transition flex items-center justify-center gap-2 cursor-pointer disabled:cursor-not-allowed"
              >
                {activeAction === 'submitDeliverable' ? (
                  <>
                    <Loader2 className="w-4 h-4 animate-spin" />
                    <span>Signing Free Submission & Relaying...</span>
                  </>
                ) : (
                  'Sign Free Deliverable Submission'
                )}
              </button>
            </div>
          )}

          {currentState === EscrowState.Delivered && (
            <div className="p-4 rounded-lg bg-zinc-950/70 border border-zinc-800 text-center text-zinc-300 text-sm">
              Deliverable submitted. Awaiting client milestone approval and payout release.
            </div>
          )}

          {(currentState === EscrowState.Funded || currentState === EscrowState.Delivered) && (
            <button
              onClick={async () => {
                try {
                  setActiveAction('dispute');
                  await raiseDispute();
                  onActionSuccess();
                } finally {
                  setActiveAction(null);
                }
              }}
              disabled={isAnyLoading}
              className="w-full py-2 px-4 bg-red-950/40 hover:bg-red-900/60 border border-red-800 text-red-300 rounded-lg text-sm font-medium transition flex items-center justify-center gap-2 disabled:opacity-50"
            >
              {activeAction === 'dispute' ? (
                <>
                  <Loader2 className="w-4 h-4 animate-spin" />
                  <span>Raising Dispute...</span>
                </>
              ) : (
                'Raise Dispute (Invoke Arbiter)'
              )}
            </button>
          )}
        </div>
      )}

      {/* 3. ARBITER ACTIONS */}
      {isArbiter && currentState === EscrowState.Disputed && (
        <div className="space-y-4">
          <p className="text-xs text-zinc-400">
            Split the escrow vault between parties. Sum of refund and payout must equal total vault amount.
          </p>
          <div className="grid grid-cols-2 gap-3">
            <div>
              <label className="text-xs text-zinc-400">Client Refund ({isEth ? 'ETH' : 'Tokens'})</label>
              <input
                type="text"
                value={refundEth}
                onChange={(e) => setRefundEth(e.target.value)}
                placeholder="0.0"
                disabled={isAnyLoading}
                className="w-full bg-zinc-950 border border-zinc-800 rounded-lg p-2 text-sm text-white focus:outline-none focus:border-indigo-500"
              />
            </div>
            <div>
              <label className="text-xs text-zinc-400">Freelancer Payout ({isEth ? 'ETH' : 'Tokens'})</label>
              <input
                type="text"
                value={payoutEth}
                onChange={(e) => setPayoutEth(e.target.value)}
                placeholder="0.0"
                disabled={isAnyLoading}
                className="w-full bg-zinc-950 border border-zinc-800 rounded-lg p-2 text-sm text-white focus:outline-none focus:border-indigo-500"
              />
            </div>
          </div>
          <button
            onClick={async () => {
              if (refundEth && payoutEth) {
                try {
                  setActiveAction('resolve');
                  await resolveDispute(parseEther(refundEth), parseEther(payoutEth));
                  onActionSuccess();
                } finally {
                  setActiveAction(null);
                }
              }
            }}
            disabled={isAnyLoading || !refundEth || !payoutEth}
            className="w-full py-2.5 px-4 bg-amber-600 hover:bg-amber-500 disabled:opacity-50 text-white rounded-lg font-semibold text-sm transition flex items-center justify-center gap-2"
          >
            {activeAction === 'resolve' ? (
              <>
                <Loader2 className="w-4 h-4 animate-spin" />
                <span>Executing Split...</span>
              </>
            ) : (
              'Enforce Dispute Resolution'
            )}
          </button>
        </div>
      )}

      {currentState === EscrowState.Completed && (
        <div className="text-center py-2 text-emerald-400 font-medium text-sm">
          ✓ Agreement finalized. All vault funds have been disbursed.
        </div>
      )}
    </div>
  );
}