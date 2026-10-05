'use client';

import dynamic from 'next/dynamic';
import { useAccount } from 'wagmi';
import { ConnectButton } from '@rainbow-me/rainbowkit';

const CreateEscrowForm = dynamic(
  () => import('@/components/escrow/CreateEscrowForm').then((mod) => mod.CreateEscrowForm),
  { ssr: false }
);

export default function Home() {
  const { isConnected } = useAccount();

  return (
    <div className="flex flex-col items-center justify-center py-6 sm:py-12 px-4 max-w-5xl mx-auto">
      {/* Hero Header */}
      <div className="text-center max-w-3xl mx-auto mb-10">
        <span className="inline-block px-3 py-1 mb-4 text-xs font-semibold tracking-wider text-indigo-400 uppercase bg-indigo-950/60 rounded-full border border-indigo-800">
          Decentralized Milestone Escrow
        </span>
        <h1 className="text-4xl sm:text-5xl font-extrabold tracking-tight text-white leading-tight">
          Milestone Payments, <span className="text-indigo-400">Zero Trust Required</span>
        </h1>
        <p className="mt-4 text-zinc-400 text-sm sm:text-base leading-relaxed max-w-2xl mx-auto">
          Lock funds trustlessly on Ethereum Sepolia. Payments release only upon milestone approval,
          with designated arbiters to protect both clients and freelancers.
        </p>
      </div>

      {!isConnected ? (
        /* Landing View: How it Works & Role Instructions */
        <div className="w-full flex flex-col items-center">
          {/* Roles Grid */}
          <div className="grid grid-cols-1 md:grid-cols-3 gap-6 w-full mb-12">
            <div className="bg-zinc-900/80 border border-zinc-800 p-6 rounded-xl">
              <div className="w-10 h-10 rounded-lg bg-indigo-950 flex items-center justify-center text-indigo-400 font-bold mb-4">
                1
              </div>
              <h3 className="text-lg font-semibold text-white mb-2">Client</h3>
              <p className="text-sm text-zinc-400 leading-relaxed">
                Initializes the escrow vault, deposits test ETH/ERC20, and reviews deliverables before approving final payout.
              </p>
            </div>

            <div className="bg-zinc-900/80 border border-zinc-800 p-6 rounded-xl">
              <div className="w-10 h-10 rounded-lg bg-indigo-950 flex items-center justify-center text-indigo-400 font-bold mb-4">
                2
              </div>
              <h3 className="text-lg font-semibold text-white mb-2">Freelancer</h3>
              <p className="text-sm text-zinc-400 leading-relaxed">
                Works knowing funds are already locked on-chain. Submits proof of work directly through the portal.
              </p>
            </div>

            <div className="bg-zinc-900/80 border border-zinc-800 p-6 rounded-xl">
              <div className="w-10 h-10 rounded-lg bg-indigo-950 flex items-center justify-center text-indigo-400 font-bold mb-4">
                3
              </div>
              <h3 className="text-lg font-semibold text-white mb-2">Arbiter</h3>
              <p className="text-sm text-zinc-400 leading-relaxed">
                Neutral mediator chosen at creation. Steps in to split or refund funds only if an unresolved dispute arises.
              </p>
            </div>
          </div>

          {/* Action Trigger Card */}
          <div className="bg-zinc-900 border border-zinc-800 p-8 rounded-2xl text-center max-w-lg w-full flex flex-col items-center shadow-xl">
            <h2 className="text-xl font-bold text-white mb-2">Ready to Start an Escrow?</h2>
            <p className="text-sm text-zinc-400 mb-6">
              Connect your Sepolia testnet wallet to initialize a contract or access your active escrows.
            </p>
            <ConnectButton />
          </div>
        </div>
      ) : (
        /* Connected View: Escrow Form */
        <div className="w-full flex justify-center">
          <CreateEscrowForm />
        </div>
      )}
    </div>
  );
}