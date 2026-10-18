'use client';

import { useState } from 'react';
import { useAccount, useReadContract } from 'wagmi';
import { parseEther, zeroAddress } from 'viem';
import { EscrowState } from '@/constants/contracts';
import { useEscrowActions } from '@/hooks/useEscrowActions';
import { useGaslessDeliverable } from '@/hooks/useGaslessDeliverable';
import { Check, Copy, Loader2, Sparkles, Shield, AlertTriangle } from 'lucide-react';

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

  const [activeAction, setActiveAction] = useState<string | null>(null);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);
  const [inputUrl, setInputUrl] = useState('');
  const [refundEth, setRefundEth] = useState('');
  const [payoutEth, setPayoutEth] = useState('');
  const [copied, setCopied] = useState(false);

  const isEth = !token || token === zeroAddress;

  const { data: freelancerNonce, refetch: refetchNonce } = useReadContract({
    address: escrowAddress,
    abi: ESCROW_NONCE_ABI,
    functionName: 'nonces',
    args: freelancer ? [freelancer] : undefined,
    query: {
      enabled: !!freelancer,
    },
  });

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
      <div className="bg-white border border-slate-200 p-8 rounded-xl text-center text-slate-500 shadow-xs">
        Connect your Web3 wallet to authorize settlement actions.
      </div>
    );
  }

  if (!isClient && !isFreelancer && !isArbiter) {
    return (
      <div className="bg-white border border-slate-200 p-6 rounded-xl text-center shadow-xs">
        <p className="text-slate-600 text-xs">
          Connected wallet is an <span className="text-amber-700 font-bold">Observer</span>. Only designated stakeholders (Client, Freelancer, Arbiter) can sign transactions.
        </p>
      </div>
    );
  }

  const hasSufficientAllowance = isEth || (allowance !== undefined && amount !== undefined && allowance >= amount);
  const isAnyLoading = activeAction !== null;

  return (
    <div className="bg-white border border-slate-200 rounded-xl p-6 shadow-xs">
      <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4 mb-6 pb-4 border-b border-slate-100">
        <div>
          <h3 className="text-sm font-bold uppercase tracking-wider text-slate-900 flex items-center gap-2">
            <Shield className="w-4 h-4 text-red-600" />
            Authorized Settlement Panel
          </h3>
          <span className="text-xs text-red-600 font-semibold">
            Stakeholder Role: {isClient ? 'Client (Vault Originator)' : isFreelancer ? 'Beneficiary (Freelancer)' : 'Appointed Arbiter'}
          </span>
        </div>

        <button
          onClick={handleCopyLink}
          className="px-3 py-1.5 bg-slate-50 hover:bg-slate-100 text-slate-700 text-xs font-semibold rounded-lg border border-slate-200 flex items-center gap-1.5 transition self-start sm:self-auto"
        >
          {copied ? <Check className="w-3.5 h-3.5 text-emerald-600" /> : <Copy className="w-3.5 h-3.5 text-slate-400" />}
          {copied ? 'Link Copied' : 'Share Settlement Link'}
        </button>
      </div>

      {errorMessage && (
        <div className="mb-4 p-3 bg-red-50 border border-red-200 rounded-lg text-red-700 text-xs font-medium">
          {errorMessage}
        </div>
      )}

      {/* Deliverable Link Display */}
      {deliverableUrl && (
        <div className="bg-slate-50 p-4 rounded-lg border border-slate-200 mb-6">
          <span className="text-[11px] uppercase tracking-wider text-slate-500 font-bold block">Submitted Deliverable Proof</span>
          <p className="mt-1 break-all">
            <a
              href={deliverableUrl}
              target="_blank"
              rel="noopener noreferrer"
              className="text-red-600 hover:text-red-700 underline text-xs font-medium"
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
                  className="w-full py-2.5 px-4 bg-amber-600 hover:bg-amber-700 disabled:opacity-50 text-white rounded-lg font-bold text-xs uppercase tracking-wider transition flex items-center justify-center gap-2"
                >
                  {activeAction === 'approve' ? (
                    <>
                      <Loader2 className="w-4 h-4 animate-spin" />
                      <span>Approving ERC-20 Tokens...</span>
                    </>
                  ) : (
                    'Step 1: Approve Token Allowance'
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
                  className="w-full py-2.5 px-4 bg-red-600 hover:bg-red-700 disabled:opacity-50 text-white rounded-lg font-bold text-xs uppercase tracking-wider transition flex items-center justify-center gap-2 shadow-xs cursor-pointer"
                >
                  {activeAction === 'fund' ? (
                    <>
                      <Loader2 className="w-4 h-4 animate-spin" />
                      <span>Confirming Settlement Deposit...</span>
                    </>
                  ) : (
                    `Deposit Settlement Funds into Vault (${isEth ? 'ETH' : 'ERC-20'})`
                  )}
                </button>
              )}
            </div>
          )}

          {currentState === EscrowState.Funded && (
            <div className="p-4 rounded-lg bg-slate-50 border border-slate-200 text-center">
              <p className="text-xs text-slate-800 font-semibold">
                Vault is funded. Awaiting deliverable submission from beneficiary.
              </p>
              <p className="text-[11px] text-slate-500 mt-0.5">
                Share this agreement page with your freelancer to submit proof of work.
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
              className="w-full py-2.5 px-4 bg-emerald-600 hover:bg-emerald-700 disabled:opacity-50 text-white rounded-lg font-bold text-xs uppercase tracking-wider transition flex items-center justify-center gap-2 shadow-xs cursor-pointer"
            >
              {activeAction === 'release' ? (
                <>
                  <Loader2 className="w-4 h-4 animate-spin" />
                  <span>Releasing Vault Funds...</span>
                </>
              ) : (
                'Approve Deliverable & Disburse Payout'
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
              className="w-full py-2 px-4 bg-white hover:bg-red-50 border border-red-300 text-red-700 rounded-lg text-xs font-semibold transition flex items-center justify-center gap-2 disabled:opacity-50 cursor-pointer"
            >
              {activeAction === 'dispute' ? (
                <>
                  <Loader2 className="w-4 h-4 animate-spin" />
                  <span>Submitting Dispute...</span>
                </>
              ) : (
                <>
                  <AlertTriangle className="w-3.5 h-3.5" />
                  Raise Dispute (Request Arbitration)
                </>
              )}
            </button>
          )}
        </div>
      )}

      {/* 2. FREELANCER ACTIONS */}
      {isFreelancer && (
        <div className="space-y-4">
          {currentState === EscrowState.Pending && (
            <div className="p-4 rounded-lg bg-slate-50 border border-slate-200 text-center text-slate-600 text-xs font-medium">
              Awaiting client deposit. Funds must be locked in the contract before commencing work.
            </div>
          )}

          {currentState === EscrowState.Funded && (
            <div className="space-y-3">
              <div className="flex items-center justify-between">
                <label className="text-[11px] text-slate-500 uppercase font-bold">Proof of Work / Deliverable URL</label>
                <span className="text-[11px] text-emerald-700 font-semibold flex items-center gap-1 bg-emerald-50 px-2 py-0.5 rounded border border-emerald-200">
                  <Sparkles className="w-3 h-3 text-emerald-600" /> Gasless (Sponsored Meta-Tx)
                </span>
              </div>
              <input
                type="url"
                value={inputUrl}
                onChange={(e) => setInputUrl(e.target.value)}
                placeholder="https://github.com/... or https://..."
                disabled={isAnyLoading}
                className="w-full bg-slate-50 border border-slate-300 rounded-lg p-2.5 text-xs text-slate-900 focus:outline-none focus:border-red-600"
              />
              <button
                onClick={handleFreelancerSubmit}
                disabled={isAnyLoading || !inputUrl}
                className="w-full py-2.5 px-4 bg-red-600 hover:bg-red-700 disabled:opacity-50 text-white rounded-lg font-bold text-xs uppercase tracking-wider transition flex items-center justify-center gap-2 shadow-xs cursor-pointer"
              >
                {activeAction === 'submitDeliverable' ? (
                  <>
                    <Loader2 className="w-4 h-4 animate-spin" />
                    <span>Signing Free Meta-Transaction...</span>
                  </>
                ) : (
                  'Sign Deliverable Submission (Gasless)'
                )}
              </button>
            </div>
          )}

          {currentState === EscrowState.Delivered && (
            <div className="p-4 rounded-lg bg-slate-50 border border-slate-200 text-center text-slate-700 text-xs font-medium">
              Deliverable verified and recorded. Awaiting client release confirmation.
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
              className="w-full py-2 px-4 bg-white hover:bg-red-50 border border-red-300 text-red-700 rounded-lg text-xs font-semibold transition flex items-center justify-center gap-2 disabled:opacity-50 cursor-pointer"
            >
              {activeAction === 'dispute' ? (
                <>
                  <Loader2 className="w-4 h-4 animate-spin" />
                  <span>Submitting Dispute...</span>
                </>
              ) : (
                <>
                  <AlertTriangle className="w-3.5 h-3.5" />
                  Raise Dispute (Request Arbitration)
                </>
              )}
            </button>
          )}
        </div>
      )}

      {/* 3. ARBITER ACTIONS */}
      {isArbiter && currentState === EscrowState.Disputed && (
        <div className="space-y-4">
          <p className="text-xs text-slate-600">
            Specify capital split between stakeholders. Sum of client refund and freelancer payout must strictly equal total vault balance.
          </p>
          <div className="grid grid-cols-2 gap-3">
            <div>
              <label className="text-[11px] text-slate-500 uppercase font-bold block mb-1">Client Refund ({isEth ? 'ETH' : 'Tokens'})</label>
              <input
                type="text"
                value={refundEth}
                onChange={(e) => setRefundEth(e.target.value)}
                placeholder="0.0"
                disabled={isAnyLoading}
                className="w-full bg-slate-50 border border-slate-300 rounded-lg p-2 text-xs text-slate-900 focus:outline-none focus:border-red-600"
              />
            </div>
            <div>
              <label className="text-[11px] text-slate-500 uppercase font-bold block mb-1">Freelancer Payout ({isEth ? 'ETH' : 'Tokens'})</label>
              <input
                type="text"
                value={payoutEth}
                onChange={(e) => setPayoutEth(e.target.value)}
                placeholder="0.0"
                disabled={isAnyLoading}
                className="w-full bg-slate-50 border border-slate-300 rounded-lg p-2 text-xs text-slate-900 focus:outline-none focus:border-red-600"
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
            className="w-full py-2.5 px-4 bg-red-600 hover:bg-red-700 disabled:opacity-50 text-white rounded-lg font-bold text-xs uppercase tracking-wider transition flex items-center justify-center gap-2 shadow-xs cursor-pointer"
          >
            {activeAction === 'resolve' ? (
              <>
                <Loader2 className="w-4 h-4 animate-spin" />
                <span>Enforcing Dispute Settlement...</span>
              </>
            ) : (
              'Enforce Arbitrated Resolution'
            )}
          </button>
        </div>
      )}

      {currentState === EscrowState.Completed && (
        <div className="text-center py-3 text-emerald-700 font-bold text-xs bg-emerald-50 rounded-lg border border-emerald-200">
          ✓ Agreement finalized. All vault funds disbursed according to smart contract rules.
        </div>
      )}
    </div>
  );
}
