'use client';

import { useState } from 'react';
import Link from 'next/link';
import { useAccount, useReadContract } from 'wagmi';
import { ESCROW_FACTORY_ADDRESS, ESCROW_FACTORY_ABI } from '@/constants/contracts';
import { EscrowCard } from '@/components/escrow/EscrowCard';
import { getHiddenEscrows } from '@/utils/escrowMetadata';
import { Plus, FolderKanban, Layers, Archive } from 'lucide-react';

type TabType = 'active' | 'archived';

export default function DashboardPage() {
  const { address, isConnected } = useAccount();
  const [activeTab, setActiveTab] = useState<TabType>('active');
  const [hiddenList, setHiddenList] = useState<string[]>(() => getHiddenEscrows());

  const { data: userEscrows, isLoading } = useReadContract({
    address: ESCROW_FACTORY_ADDRESS,
    abi: ESCROW_FACTORY_ABI,
    functionName: 'getUserEscrows',
    args: address ? [address] : undefined,
    query: {
      enabled: !!address,
    },
  });

  const escrows = (userEscrows as `0x${string}`[] | undefined) || [];

  const refreshHiddenList = () => {
    setHiddenList(getHiddenEscrows());
  };

  const activeEscrows = escrows.filter(
    (addr) => !hiddenList.includes(addr.toLowerCase())
  );

  const archivedEscrows = escrows.filter(
    (addr) => hiddenList.includes(addr.toLowerCase())
  );

  const currentDisplayList = activeTab === 'active' ? activeEscrows : archivedEscrows;

  return (
    <div className="max-w-6xl mx-auto py-8 px-4">
      {/* Top Header */}
      <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4 mb-6">
        <div>
          <h1 className="text-2xl font-bold text-white tracking-tight flex items-center gap-2">
            <FolderKanban className="w-6 h-6 text-indigo-400" />
            Escrow Dashboard
          </h1>
          <p className="text-sm text-zinc-400 mt-1">
            Overview of all smart contract agreements associated with your connected wallet.
          </p>
        </div>

        <Link
          href="/"
          className="inline-flex items-center gap-2 bg-indigo-600 hover:bg-indigo-500 text-white text-sm font-semibold py-2 px-4 rounded-lg transition self-start sm:self-auto"
        >
          <Plus className="w-4 h-4" />
          Create New Escrow
        </Link>
      </div>

      {/* Tabs Filter Bar */}
      {isConnected && escrows.length > 0 && (
        <div className="flex items-center gap-2 border-b border-zinc-800 mb-6 pb-2">
          <button
            onClick={() => setActiveTab('active')}
            className={`flex items-center gap-2 px-3.5 py-1.5 rounded-lg text-xs font-semibold transition ${
              activeTab === 'active'
                ? 'bg-zinc-800 text-white border border-zinc-700'
                : 'text-zinc-400 hover:text-zinc-200 hover:bg-zinc-900'
            }`}
          >
            <Layers className="w-3.5 h-3.5" />
            Active Agreements
            <span className="ml-1 px-1.5 py-0.5 rounded-full bg-zinc-900 text-[10px] text-zinc-300 font-mono">
              {activeEscrows.length}
            </span>
          </button>

          <button
            onClick={() => setActiveTab('archived')}
            className={`flex items-center gap-2 px-3.5 py-1.5 rounded-lg text-xs font-semibold transition ${
              activeTab === 'archived'
                ? 'bg-zinc-800 text-white border border-zinc-700'
                : 'text-zinc-400 hover:text-zinc-200 hover:bg-zinc-900'
            }`}
          >
            <Archive className="w-3.5 h-3.5" />
            Archived / Hidden
            <span className="ml-1 px-1.5 py-0.5 rounded-full bg-zinc-900 text-[10px] text-zinc-300 font-mono">
              {archivedEscrows.length}
            </span>
          </button>
        </div>
      )}

      {/* Main Content Area */}
      {!isConnected ? (
        <div className="bg-zinc-900 border border-zinc-800 rounded-xl p-10 text-center">
          <p className="text-zinc-400 text-sm mb-3">Please connect your wallet to view your escrow agreements.</p>
        </div>
      ) : isLoading ? (
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
          {[1, 2, 3].map((n) => (
            <div key={n} className="bg-zinc-900/60 border border-zinc-800 p-5 rounded-xl animate-pulse h-44" />
          ))}
        </div>
      ) : escrows.length === 0 ? (
        <div className="bg-zinc-900 border border-zinc-800 rounded-xl p-12 text-center">
          <FolderKanban className="w-10 h-10 text-zinc-600 mx-auto mb-3" />
          <h3 className="text-base font-semibold text-white">No Escrow Agreements Found</h3>
          <p className="text-xs text-zinc-500 mt-1 mb-5">
            You are not currently linked to any active escrows as a Client, Freelancer, or Arbiter.
          </p>
          <Link
            href="/"
            className="inline-flex items-center gap-1.5 bg-zinc-800 hover:bg-zinc-700 text-zinc-200 text-xs font-semibold py-2 px-3.5 rounded-lg border border-zinc-700 transition"
          >
            Deploy Your First Escrow
          </Link>
        </div>
      ) : currentDisplayList.length === 0 ? (
        <div className="bg-zinc-900/50 border border-zinc-800/80 rounded-xl p-10 text-center">
          <p className="text-zinc-400 text-sm">
            {activeTab === 'active'
              ? 'All agreements are currently archived.'
              : 'No agreements have been archived or hidden.'}
          </p>
        </div>
      ) : (
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
          {currentDisplayList.map((escrowAddr) => (
            <EscrowCard
              key={escrowAddr}
              escrowAddress={escrowAddr}
              onVisibilityChange={refreshHiddenList}
            />
          ))}
        </div>
      )}
    </div>
  );
}