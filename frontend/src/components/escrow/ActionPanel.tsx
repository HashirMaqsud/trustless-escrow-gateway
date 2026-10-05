'use client';

import { useState } from 'react';
import { useAccount } from 'wagmi';
import { parseEther } from 'viem';
import { EscrowState } from '@/constants/contracts';
import { useEscrowActions } from '@/hooks/useEscrowActions';

interface ActionPanelProps {
  escrowAddress: `0x${string}`;
  client: `0x${string}` | undefined;
  freelancer: `0x${string}` | undefined;
  arbiter: `0x${string}` | undefined;
  amount: bigint | undefined;
  currentState: EscrowState | undefined;
  deliverableUrl: string | undefined;
  onActionSuccess: () => void;
}

export function ActionPanel({
  escrowAddress,
  client,
  freelancer,
  arbiter,
  amount,
  currentState,
  deliverableUrl,
  onActionSuccess,
}: ActionPanelProps) {
  const { address } = useAccount();
  const {
    fundEscrow,
    submitDeliverable,
    releaseFunds,
    raiseDispute,
    resolveDispute,
    isLoading,
  } = useEscrowActions(escrowAddress);

  const [inputUrl, setInputUrl] = useState('');
  const [refundEth, setRefundEth] = useState('');
  const [payoutEth, setPayoutEth] = useState('');
  const [copied, setCopied] = useState(false);

  const isClient = address?.toLowerCase() === client?.toLowerCase();
  const isFreelancer = address?.toLowerCase() === freelancer?.toLowerCase();
  const isArbiter = address?.toLowerCase() === arbiter?.toLowerCase();

  const handleCopyLink = () => {
    navigator.clipboard.writeText(window.location.href);
    setCopied(true);
    setTimeout(() => setCopied(false), 2000);
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
          {copied ? '✓ Link Copied' : '📋 Share Agreement Link'}
        </button>
      </div>

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
            <button
              onClick={async () => {
                if (amount) {
                  await fundEscrow(amount);
                  onActionSuccess();
                }
              }}
              disabled={isLoading}
              className="w-full py-2.5 px-4 bg-indigo-600 hover:bg-indigo-500 disabled:bg-zinc-700 text-white rounded-lg font-semibold text-sm transition"
            >
              {isLoading ? 'Confirming Deposit...' : 'Deposit Agreed Funds into Vault'}
            </button>
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
                await releaseFunds();
                onActionSuccess();
              }}
              disabled={isLoading}
              className="w-full py-2.5 px-4 bg-emerald-600 hover:bg-emerald-500 disabled:bg-zinc-700 text-white rounded-lg font-semibold text-sm transition"
            >
              {isLoading ? 'Releasing...' : 'Approve Deliverable & Release Funds'}
            </button>
          )}

          {(currentState === EscrowState.Funded || currentState === EscrowState.Delivered) && (
            <button
              onClick={async () => {
                await raiseDispute();
                onActionSuccess();
              }}
              disabled={isLoading}
              className="w-full py-2 px-4 bg-red-950/40 hover:bg-red-900/60 border border-red-800 text-red-300 rounded-lg text-sm font-medium transition"
            >
              {isLoading ? 'Raising Dispute...' : 'Raise Dispute (Invoke Arbiter)'}
            </button>
          )}
        </div>
      )}

      {/* 2. FREELANCER ACTIONS */}
      {isFreelancer && (
        <div className="space-y-4">
          {currentState === EscrowState.Pending && (
            <div className="p-4 rounded-lg bg-zinc-950/70 border border-zinc-800 text-center text-zinc-400 text-sm">
              Awaiting client deposit. Do not begin work until funds are locked in the vault.
            </div>
          )}

          {currentState === EscrowState.Funded && (
            <div className="space-y-2">
              <label className="text-xs text-zinc-400 uppercase font-medium">Proof of Work (URL)</label>
              <input
                type="url"
                value={inputUrl}
                onChange={(e) => setInputUrl(e.target.value)}
                placeholder="https://github.com/..."
                className="w-full bg-zinc-950 border border-zinc-800 rounded-lg p-2.5 text-sm text-white focus:outline-none focus:border-indigo-500"
              />
              <button
                onClick={async () => {
                  if (inputUrl) {
                    await submitDeliverable(inputUrl);
                    onActionSuccess();
                  }
                }}
                disabled={isLoading || !inputUrl}
                className="w-full py-2.5 px-4 bg-indigo-600 hover:bg-indigo-500 disabled:bg-zinc-700 text-white rounded-lg font-semibold text-sm transition"
              >
                {isLoading ? 'Submitting...' : 'Submit Deliverable'}
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
                await raiseDispute();
                onActionSuccess();
              }}
              disabled={isLoading}
              className="w-full py-2 px-4 bg-red-950/40 hover:bg-red-900/60 border border-red-800 text-red-300 rounded-lg text-sm font-medium transition"
            >
              {isLoading ? 'Raising Dispute...' : 'Raise Dispute (Invoke Arbiter)'}
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
              <label className="text-xs text-zinc-400">Client Refund (ETH)</label>
              <input
                type="text"
                value={refundEth}
                onChange={(e) => setRefundEth(e.target.value)}
                placeholder="0.0"
                className="w-full bg-zinc-950 border border-zinc-800 rounded-lg p-2 text-sm text-white focus:outline-none focus:border-indigo-500"
              />
            </div>
            <div>
              <label className="text-xs text-zinc-400">Freelancer Payout (ETH)</label>
              <input
                type="text"
                value={payoutEth}
                onChange={(e) => setPayoutEth(e.target.value)}
                placeholder="0.0"
                className="w-full bg-zinc-950 border border-zinc-800 rounded-lg p-2 text-sm text-white focus:outline-none focus:border-indigo-500"
              />
            </div>
          </div>
          <button
            onClick={async () => {
              if (refundEth && payoutEth) {
                await resolveDispute(parseEther(refundEth), parseEther(payoutEth));
                onActionSuccess();
              }
            }}
            disabled={isLoading || !refundEth || !payoutEth}
            className="w-full py-2.5 px-4 bg-amber-600 hover:bg-amber-500 disabled:bg-zinc-700 text-white rounded-lg font-semibold text-sm transition"
          >
            {isLoading ? 'Executing Split...' : 'Enforce Dispute Resolution'}
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