'use client';

import { useState } from 'react';
import Link from 'next/link';
import { useAccount, useReadContract } from 'wagmi';
import { ESCROW_FACTORY_ADDRESS, ESCROW_FACTORY_ABI } from '@/constants/contracts';
import { EscrowCard } from '@/components/escrow/EscrowCard';
import { getHiddenEscrows } from '@/utils/escrowMetadata';
import { Plus, FolderKanban, Layers, Archive, ShieldCheck, ArrowUpRight, Activity } from 'lucide-react';

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
    <div className="max-w-7xl mx-auto py-4">
      {/* Background Subtle Gradient Mesh */}
      <div className="fixed inset-0 pointer-events-none -z-10 bg-[radial-gradient(ellipse_80%_60%_at_70%_-10%,rgba(220,38,38,0.06),transparent),radial-gradient(ellipse_60%_50%_at_10%_90%,rgba(203,213,225,0.3),transparent)]" />

      {/* Top Header */}
      <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4 mb-6">
        <div>
          <div className="flex items-center gap-2 mb-1">
            <div className="w-7 h-7 rounded-md bg-red-50 border border-red-200 flex items-center justify-center text-red-600">
              <FolderKanban className="w-4 h-4" />
            </div>
            <h1 className="text-xl font-extrabold text-slate-900 tracking-tight">
              Escrow Portfolio
            </h1>
          </div>
          <p className="text-xs text-slate-500">
            Real-time management of smart contract settlement vaults linked to your account.
          </p>
        </div>

        <Link
          href="/"
          className="inline-flex items-center gap-1.5 bg-red-600 hover:bg-red-700 text-white text-xs font-bold py-2.5 px-4 rounded-lg shadow-xs transition self-start sm:self-auto cursor-pointer"
        >
          <Plus className="w-3.5 h-3.5" />
          Create New Agreement
        </Link>
      </div>

      {/* Institutional Metric Strip */}
      {isConnected && (
        <div className="grid grid-cols-1 sm:grid-cols-3 gap-3.5 mb-6">
          <div className="bg-white/90 backdrop-blur-xs border border-slate-200 p-4 rounded-xl shadow-xs">
            <span className="text-[10px] font-bold uppercase tracking-wider text-slate-500 block">
              Total Managed Positions
            </span>
            <p className="text-2xl font-extrabold text-slate-900 mt-1">
              {escrows.length} <span className="text-xs font-semibold text-slate-500">Vaults</span>
            </p>
          </div>

          <div className="bg-white/90 backdrop-blur-xs border border-slate-200 p-4 rounded-xl shadow-xs">
            <span className="text-[10px] font-bold uppercase tracking-wider text-slate-500 block">
              Active In Progress
            </span>
            <p className="text-2xl font-extrabold text-red-600 mt-1">
              {activeEscrows.length} <span className="text-xs font-semibold text-slate-500">Positions</span>
            </p>
          </div>

          <div className="bg-white/90 backdrop-blur-xs border border-slate-200 p-4 rounded-xl shadow-xs">
            <span className="text-[10px] font-bold uppercase tracking-wider text-slate-500 block">
              Network Protocol
            </span>
            <p className="text-sm font-bold text-slate-800 mt-2 flex items-center gap-1.5">
              <span className="w-2 h-2 rounded-full bg-emerald-500" />
              Sepolia Testnet
            </p>
          </div>
        </div>
      )}

      {/* Tabs Filter Bar */}
      {isConnected && escrows.length > 0 && (
        <div className="flex items-center gap-2 border-b border-slate-200 mb-6 pb-2">
          <button
            onClick={() => setActiveTab('active')}
            className={`flex items-center gap-2 px-3.5 py-1.5 rounded-lg text-xs font-bold transition cursor-pointer ${
              activeTab === 'active'
                ? 'bg-white text-slate-900 border border-slate-200 shadow-xs'
                : 'text-slate-500 hover:text-slate-900 hover:bg-slate-100'
            }`}
          >
            <Layers className="w-3.5 h-3.5 text-slate-500" />
            Active Vaults
            <span className="ml-1 px-1.5 py-0.5 rounded-full bg-slate-100 text-[10px] text-slate-700 font-mono font-semibold">
              {activeEscrows.length}
            </span>
          </button>

          <button
            onClick={() => setActiveTab('archived')}
            className={`flex items-center gap-2 px-3.5 py-1.5 rounded-lg text-xs font-bold transition cursor-pointer ${
              activeTab === 'archived'
                ? 'bg-white text-slate-900 border border-slate-200 shadow-xs'
                : 'text-slate-500 hover:text-slate-900 hover:bg-slate-100'
            }`}
          >
            <Archive className="w-3.5 h-3.5 text-slate-500" />
            Archived
            <span className="ml-1 px-1.5 py-0.5 rounded-full bg-slate-100 text-[10px] text-slate-700 font-mono font-semibold">
              {archivedEscrows.length}
            </span>
          </button>
        </div>
      )}

      {/* Main Content Area */}
      {!isConnected ? (
        <div className="bg-white border border-slate-200 rounded-xl p-12 text-center shadow-xs">
          <p className="text-slate-600 text-sm font-medium mb-1">Wallet Disconnected</p>
          <p className="text-slate-400 text-xs">Connect your Web3 account to inspect escrow positions.</p>
        </div>
      ) : isLoading ? (
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-5">
          {[1, 2, 3].map((n) => (
            <div key={n} className="bg-white border border-slate-200 p-6 rounded-xl shadow-xs animate-pulse h-48" />
          ))}
        </div>
      ) : escrows.length === 0 ? (
        <div className="bg-white border border-slate-200 rounded-xl p-12 text-center shadow-xs">
          <FolderKanban className="w-10 h-10 text-slate-300 mx-auto mb-3" />
          <h3 className="text-base font-bold text-slate-900">No Settlement Vaults Found</h3>
          <p className="text-xs text-slate-500 mt-1 mb-6 max-w-sm mx-auto">
            You are not currently linked as Client, Freelancer, or Arbiter on any active agreements.
          </p>
          <Link
            href="/"
            className="inline-flex items-center gap-1.5 bg-red-600 hover:bg-red-700 text-white text-xs font-bold py-2 px-4 rounded-lg shadow-xs transition"
          >
            Deploy First Escrow
          </Link>
        </div>
      ) : currentDisplayList.length === 0 ? (
        <div className="bg-white border border-slate-200 rounded-xl p-10 text-center shadow-xs">
          <p className="text-slate-500 text-xs font-medium">
            {activeTab === 'active'
              ? 'All agreements are currently archived.'
              : 'No agreements have been archived.'}
          </p>
        </div>
      ) : (
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-5">
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
