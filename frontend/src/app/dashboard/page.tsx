'use client';

import Link from 'next/link';
import { useAccount, useReadContract } from 'wagmi';
import { ESCROW_FACTORY_ADDRESS, ESCROW_FACTORY_ABI } from '@/constants/contracts';
import { EscrowCard } from '@/components/escrow/EscrowCard';
import { Plus, FolderKanban } from 'lucide-react';

export default function DashboardPage() {
  const { address, isConnected } = useAccount();

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

  return (
    <div className="max-w-6xl mx-auto py-8 px-4">
      <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4 mb-8">
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
      ) : (
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
          {escrows.map((escrowAddr) => (
            <EscrowCard key={escrowAddr} escrowAddress={escrowAddr} />
          ))}
        </div>
      )}
    </div>
  );
}