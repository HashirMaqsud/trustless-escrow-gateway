'use client';

import dynamic from 'next/dynamic';
import { useAccount } from 'wagmi';
import { ConnectButton } from '@rainbow-me/rainbowkit';
import { ShieldCheck, UserCheck, Briefcase, Scale, Lock, ArrowUpRight, Zap, CheckCircle2 } from 'lucide-react';

const CreateEscrowForm = dynamic(
  () => import('@/components/escrow/CreateEscrowForm').then((mod) => mod.CreateEscrowForm),
  { ssr: false }
);

export default function Home() {
  const { isConnected } = useAccount();

  return (
    <div className="min-h-[calc(100vh-6.5rem)] flex flex-col justify-center py-2 lg:py-4">
      {/* Background Subtle Gradient Mesh */}
      <div className="fixed inset-0 pointer-events-none -z-10 bg-[radial-gradient(ellipse_80%_60%_at_70%_-10%,rgba(220,38,38,0.08),transparent),radial-gradient(ellipse_60%_50%_at_10%_90%,rgba(203,213,225,0.35),transparent)]" />

      {!isConnected ? (
        /* Clean Banking Disconnected Hero */
        <div className="w-full max-w-6xl mx-auto flex flex-col justify-between space-y-8">
          
          {/* Hero Header */}
          <div className="text-center max-w-3xl mx-auto">
            <div className="inline-flex items-center gap-1.5 px-3 py-1 mb-3 text-xs font-bold tracking-wider text-red-700 uppercase bg-red-50 rounded-full border border-red-200 shadow-xs">
              <ShieldCheck className="w-3.5 h-3.5 text-red-600" />
              Decentralized Milestone Settlement
            </div>
            
            <h1 className="text-3xl sm:text-5xl font-extrabold tracking-tight text-slate-900 leading-tight">
              Milestone Settlements, <br className="hidden sm:inline" />
              <span className="text-red-600">Zero Counterparty Risk</span>
            </h1>
            
            <p className="mt-3 text-slate-600 text-xs sm:text-sm leading-relaxed max-w-2xl mx-auto">
              Single-use smart escrow vaults on Ethereum Sepolia. Capital stays locked on-chain until deliverable milestones are verified by stakeholders.
            </p>

            {/* Direct Centered Action Bar */}
            <div className="mt-6 flex items-center justify-center gap-3">
              <ConnectButton label="Connect Wallet to Launch" />
              <a
                href="https://sepolia.etherscan.io/address/0x1b21fdF32bbAC2e9b776259fF8fc25dC65129824"
                target="_blank"
                rel="noopener noreferrer"
                className="px-4 py-2 bg-white hover:bg-slate-50 border border-slate-300 text-slate-700 font-semibold text-xs rounded-lg shadow-xs transition inline-flex items-center gap-1.5"
              >
                Factory Ledger <ArrowUpRight className="w-3.5 h-3.5 text-slate-400" />
              </a>
            </div>
          </div>

          {/* Institutional Role Architecture Grid */}
          <div className="grid grid-cols-1 md:grid-cols-3 gap-4 w-full">
            <div className="bg-white/80 backdrop-blur-xs border border-slate-200/90 p-5 rounded-xl shadow-xs hover:border-slate-300 transition">
              <div className="w-9 h-9 rounded-lg bg-red-50 border border-red-200 flex items-center justify-center text-red-600 mb-3 shadow-xs">
                <Briefcase className="w-4 h-4" />
              </div>
              <h3 className="text-sm font-bold text-slate-900 mb-1">01. Client (Vault Originator)</h3>
              <p className="text-xs text-slate-500 leading-relaxed">
                Initializes the escrow vault, deposits test ETH/ERC20, and reviews deliverables before approving final payout.
              </p>
            </div>

            <div className="bg-white/80 backdrop-blur-xs border border-slate-200/90 p-5 rounded-xl shadow-xs hover:border-slate-300 transition">
              <div className="w-9 h-9 rounded-lg bg-red-50 border border-red-200 flex items-center justify-center text-red-600 mb-3 shadow-xs">
                <UserCheck className="w-4 h-4" />
              </div>
              <h3 className="text-sm font-bold text-slate-900 mb-1">02. Beneficiary (Freelancer)</h3>
              <p className="text-xs text-slate-500 leading-relaxed">
                Commences work knowing funds are locked in the smart contract. Submits proof of work with gasless signature relay.
              </p>
            </div>

            <div className="bg-white/80 backdrop-blur-xs border border-slate-200/90 p-5 rounded-xl shadow-xs hover:border-slate-300 transition">
              <div className="w-9 h-9 rounded-lg bg-red-50 border border-red-200 flex items-center justify-center text-red-600 mb-3 shadow-xs">
                <Scale className="w-4 h-4" />
              </div>
              <h3 className="text-sm font-bold text-slate-900 mb-1">03. Independent Arbiter</h3>
              <p className="text-xs text-slate-500 leading-relaxed">
                Neutral mediator selected at deployment. Resolves disputed contracts with fair custom split payouts.
              </p>
            </div>
          </div>

          {/* Clean Bottom Trust Indicators */}
          <div className="flex flex-wrap items-center justify-center gap-6 text-[11px] font-medium text-slate-500 pt-2 border-t border-slate-200/80">
            <span className="flex items-center gap-1.5">
              <CheckCircle2 className="w-3.5 h-3.5 text-emerald-600" /> Verified On-Chain
            </span>
            <span className="flex items-center gap-1.5">
              <Zap className="w-3.5 h-3.5 text-red-600" /> Gasless Relayer Ready
            </span>
            <span className="flex items-center gap-1.5">
              <Lock className="w-3.5 h-3.5 text-slate-700" /> Non-Custodial Architecture
            </span>
          </div>

        </div>
      ) : (
        /* Connected View: Modern Asymmetrical Split Layout */
        <div className="w-full max-w-7xl mx-auto grid grid-cols-1 lg:grid-cols-12 gap-8 lg:gap-12 items-center">
          
          {/* Left Column: Bold Financial Typography & Value Badges */}
          <div className="lg:col-span-6 space-y-5">
            <div className="inline-flex items-center gap-1.5 px-3 py-1 text-xs font-bold tracking-wider text-red-700 uppercase bg-red-50 rounded-full border border-red-200 shadow-xs">
              <ShieldCheck className="w-3.5 h-3.5 text-red-600" />
              Institutional Settlement Protocol
            </div>

            <h1 className="text-3xl sm:text-5xl font-extrabold tracking-tight text-slate-900 leading-[1.15]">
              Milestone Vaults, <br />
              <span className="text-red-600">Zero Counterparty Risk.</span>
            </h1>

            <p className="text-slate-600 text-xs sm:text-sm leading-relaxed max-w-lg">
              Deploy audited, single-use smart escrow vaults on Ethereum Sepolia. Funds remain deterministically locked until verified delivery approvals or mediator dispute resolutions.
            </p>

            {/* Financial Highlights */}
            <div className="grid grid-cols-2 gap-3 pt-1 max-w-lg">
              <div className="p-3 rounded-xl bg-white/80 backdrop-blur-xs border border-slate-200/80 shadow-xs">
                <div className="flex items-center gap-2 text-slate-900 font-bold text-xs mb-1">
                  <Lock className="w-3.5 h-3.5 text-red-600" />
                  Self-Custodial Vault
                </div>
                <p className="text-[11px] text-slate-500 leading-normal">
                  Isolated per-agreement contract storage. Zero pooled risk.
                </p>
              </div>

              <div className="p-3 rounded-xl bg-white/80 backdrop-blur-xs border border-slate-200/80 shadow-xs">
                <div className="flex items-center gap-2 text-slate-900 font-bold text-xs mb-1">
                  <Zap className="w-3.5 h-3.5 text-red-600" />
                  Gasless EIP-712
                </div>
                <p className="text-[11px] text-slate-500 leading-normal">
                  Freelancers submit proof of work with 0 ETH gas required.
                </p>
              </div>
            </div>

            <div className="pt-2 flex items-center gap-4 text-xs font-medium text-slate-500">
              <span className="flex items-center gap-1.5">
                <span className="w-2 h-2 rounded-full bg-emerald-500" />
                Sepolia Testnet Active
              </span>
              <span>•</span>
              <a
                href="https://sepolia.etherscan.io/address/0x1b21fdF32bbAC2e9b776259fF8fc25dC65129824"
                target="_blank"
                rel="noopener noreferrer"
                className="hover:text-slate-900 underline inline-flex items-center gap-1 transition"
              >
                Factory Contract <ArrowUpRight className="w-3 h-3" />
              </a>
            </div>
          </div>

          {/* Right Column: Compact Form Card */}
          <div className="lg:col-span-6 w-full flex justify-center lg:justify-end">
            <CreateEscrowForm />
          </div>

        </div>
      )}
    </div>
  );
}
