'use client';

import { use } from 'react';
import Link from 'next/link';
import { formatEther } from 'viem';
import { useEscrowState } from '@/hooks/useEscrowState';
import { StateTimeline } from '@/components/escrow/StateTimeline';
import { ActionPanel } from '@/components/escrow/ActionPanel';

interface EscrowPageProps {
  params: Promise<{ address: string }>;
}

export default function EscrowDetailPage({ params }: EscrowPageProps) {
  const resolvedParams = use(params);
  const escrowAddress = resolvedParams.address as `0x${string}`;

  const {
    client,
    freelancer,
    arbiter,
    amount,
    currentState,
    deliverableUrl,
    isLoading,
    refetch,
  } = useEscrowState(escrowAddress);

  if (isLoading) {
    return (
      <div className="flex flex-col items-center justify-center min-h-[60vh]">
        <div className="w-10 h-10 border-4 border-indigo-500 border-t-transparent rounded-full animate-spin mb-4" />
        <p className="text-zinc-400 text-sm">Querying escrow state machine from Sepolia...</p>
      </div>
    );
  }

  return (
    <div className="max-w-4xl mx-auto py-8 px-4">
      {/* Top Navigation & Header */}
      <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4 mb-6">
        <div>
          <div className="flex items-center gap-2 mb-1">
            <Link
              href="/"
              className="text-xs text-zinc-400 hover:text-white transition flex items-center gap-1"
            >
              ← Back to Portal
            </Link>
          </div>
          <h1 className="text-2xl font-bold text-white flex items-center gap-2">
            Escrow Agreement
          </h1>
          <span className="text-xs font-mono text-zinc-500 break-all">{escrowAddress}</span>
        </div>

        <div className="flex items-center gap-2">
          <a
            href={`https://sepolia.etherscan.io/address/${escrowAddress}`}
            target="_blank"
            rel="noopener noreferrer"
            className="px-3 py-1.5 bg-zinc-900 hover:bg-zinc-800 border border-zinc-700 text-zinc-300 rounded-lg text-xs font-medium transition"
          >
            Sepolia Etherscan ↗
          </a>
        </div>
      </div>

      {/* State Tracker */}
      <StateTimeline currentState={currentState} />

      {/* Contract Details Card */}
      <div className="bg-zinc-900/80 border border-zinc-800 rounded-xl p-6 mb-8">
        <h2 className="text-sm font-semibold uppercase tracking-wider text-zinc-400 mb-4">
          Vault Specification
        </h2>
        <div className="grid grid-cols-1 sm:grid-cols-2 md:grid-cols-4 gap-4">
          <div className="p-3 bg-zinc-950 rounded-lg border border-zinc-800/80">
            <span className="text-xs text-zinc-500 font-medium">Locked Balance</span>
            <p className="text-lg font-bold text-white mt-1">
              {amount ? `${formatEther(amount)} ETH` : '0 ETH'}
            </p>
          </div>

          <div className="p-3 bg-zinc-950 rounded-lg border border-zinc-800/80">
            <span className="text-xs text-zinc-500 font-medium">Client</span>
            <p className="text-xs font-mono text-zinc-300 mt-1 truncate" title={client}>
              {client || 'Loading...'}
            </p>
          </div>

          <div className="p-3 bg-zinc-950 rounded-lg border border-zinc-800/80">
            <span className="text-xs text-zinc-500 font-medium">Freelancer</span>
            <p className="text-xs font-mono text-zinc-300 mt-1 truncate" title={freelancer}>
              {freelancer || 'Loading...'}
            </p>
          </div>

          <div className="p-3 bg-zinc-950 rounded-lg border border-zinc-800/80">
            <span className="text-xs text-zinc-500 font-medium">Arbiter</span>
            <p className="text-xs font-mono text-zinc-300 mt-1 truncate" title={arbiter}>
              {arbiter || 'Loading...'}
            </p>
          </div>
        </div>
      </div>

      {/* Action Controls */}
      <ActionPanel
        escrowAddress={escrowAddress}
        client={client}
        freelancer={freelancer}
        arbiter={arbiter}
        amount={amount}
        currentState={currentState}
        deliverableUrl={deliverableUrl}
        onActionSuccess={() => refetch()}
      />
    </div>
  );
}