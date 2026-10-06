'use client';

import React, { useState, useSyncExternalStore } from 'react';
import Link from 'next/link';
import { isAddress, getAddress } from 'viem';
import { useAccount } from 'wagmi';
import { useCreateEscrow } from '@/hooks/useCreateEscrow';
import { AlertCircle, CheckCircle2, Loader2, ArrowUpRight, Copy, Check } from 'lucide-react';

const subscribe = () => () => {};

export const CreateEscrowForm = () => {
  const mounted = useSyncExternalStore(
    subscribe,
    () => true,
    () => false
  );

  const { isConnected, address: clientAddress } = useAccount();
  const { createEscrow, isLoading, isSuccess, txHash, deployedAddress, error } = useCreateEscrow();

  const [freelancer, setFreelancer] = useState('');
  const [arbiter, setArbiter] = useState('');
  const [depositAmount, setDepositAmount] = useState('');
  const [validationError, setValidationError] = useState<string | null>(null);
  const [copied, setCopied] = useState(false);

  const shareableUrl = deployedAddress
    ? `${typeof window !== 'undefined' ? window.location.origin : ''}/escrow/${deployedAddress}`
    : '';

  const handleCopy = () => {
    if (!shareableUrl) return;
    navigator.clipboard.writeText(shareableUrl);
    setCopied(true);
    setTimeout(() => setCopied(false), 2000);
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setValidationError(null);

    if (!isConnected) {
      setValidationError('Please connect your Web3 wallet first.');
      return;
    }

    if (!isAddress(freelancer)) {
      setValidationError('Invalid Freelancer Ethereum address.');
      return;
    }

    if (!isAddress(arbiter)) {
      setValidationError('Invalid Arbiter Ethereum address.');
      return;
    }

    const cleanFreelancer = getAddress(freelancer);
    const cleanArbiter = getAddress(arbiter);
    const cleanClient = clientAddress ? getAddress(clientAddress) : '';

    if (cleanFreelancer === cleanClient) {
      setValidationError('Freelancer address cannot be the same as Client address.');
      return;
    }

    if (cleanArbiter === cleanClient || cleanArbiter === cleanFreelancer) {
      setValidationError('Arbiter must be an independent third party.');
      return;
    }

    const numAmount = parseFloat(depositAmount);
    if (isNaN(numAmount) || numAmount <= 0) {
      setValidationError('Deposit amount must be greater than 0 ETH.');
      return;
    }

    try {
      await createEscrow({
        freelancer: cleanFreelancer,
        arbiter: cleanArbiter,
        depositAmount,
      });
    } catch {
      // Handled in hook
    }
  };

  return (
    <div className="w-full max-w-xl mx-auto bg-zinc-900 border border-zinc-800 rounded-xl p-6 sm:p-8 shadow-xl">
      <div className="mb-6">
        <h2 className="text-xl font-bold text-white tracking-tight">Deploy Milestone Escrow</h2>
        <p className="text-sm text-zinc-400 mt-1">
          Lock funds trustlessly. Payment will be released upon milestone approval.
        </p>
      </div>

      {validationError && (
        <div className="mb-5 flex items-center gap-2 p-3 bg-red-950/40 border border-red-800/60 rounded-lg text-red-300 text-sm">
          <AlertCircle className="w-4 h-4 shrink-0" />
          <span>{validationError}</span>
        </div>
      )}

      {error && (
        <div className="mb-5 flex items-center gap-2 p-3 bg-red-950/40 border border-red-800/60 rounded-lg text-red-300 text-sm">
          <AlertCircle className="w-4 h-4 shrink-0" />
          <span className="truncate">{error.message || 'Transaction rejected or reverted.'}</span>
        </div>
      )}

      {isSuccess && (
        <div className="mb-6 p-4 bg-emerald-950/40 border border-emerald-800/80 rounded-xl text-emerald-300 text-sm space-y-3">
          <div className="flex items-center gap-2 font-semibold text-emerald-400">
            <CheckCircle2 className="w-5 h-5 shrink-0" />
            <span>Escrow Initialized Successfully!</span>
          </div>

          {deployedAddress && (
            <div className="bg-zinc-950/80 p-3 rounded-lg border border-zinc-800 text-xs font-mono text-zinc-300 space-y-2">
              <span className="text-[11px] uppercase tracking-wider text-zinc-500 font-semibold block">
                Shareable Agreement URL
              </span>
              <div className="flex items-center justify-between gap-2">
                <span className="truncate text-zinc-400">{shareableUrl}</span>
                <button
                  type="button"
                  onClick={handleCopy}
                  className="px-2.5 py-1 bg-zinc-800 hover:bg-zinc-700 text-white rounded border border-zinc-700 flex items-center gap-1 shrink-0 font-sans text-xs transition"
                >
                  {copied ? <Check className="w-3.5 h-3.5 text-emerald-400" /> : <Copy className="w-3.5 h-3.5" />}
                  {copied ? 'Copied' : 'Copy'}
                </button>
              </div>

              <div className="pt-2 flex items-center justify-between border-t border-zinc-800/80">
                <Link
                  href={`/escrow/${deployedAddress}`}
                  className="inline-flex items-center gap-1 font-semibold text-indigo-400 hover:text-indigo-300 font-sans"
                >
                  Open Escrow Agreement →
                </Link>
                {txHash && (
                  <a
                    href={`https://sepolia.etherscan.io/tx/${txHash}`}
                    target="_blank"
                    rel="noopener noreferrer"
                    className="inline-flex items-center gap-1 text-[11px] text-zinc-400 hover:text-zinc-300 underline font-sans"
                  >
                    Etherscan <ArrowUpRight className="w-3 h-3" />
                  </a>
                )}
              </div>
            </div>
          )}
        </div>
      )}

      <form onSubmit={handleSubmit} className="space-y-4">
        <div>
          <label className="block text-xs font-medium uppercase tracking-wider text-zinc-400 mb-1">
            Freelancer Address
          </label>
          <input
            type="text"
            placeholder="0x..."
            value={freelancer}
            onChange={(e) => setFreelancer(e.target.value.trim())}
            disabled={isLoading}
            className="w-full bg-zinc-950 border border-zinc-800 rounded-lg px-3 py-2 text-sm text-zinc-100 placeholder-zinc-600 focus:outline-none focus:border-indigo-500 font-mono"
            required
          />
        </div>

        <div>
          <label className="block text-xs font-medium uppercase tracking-wider text-zinc-400 mb-1">
            Arbiter Address
          </label>
          <input
            type="text"
            placeholder="0x..."
            value={arbiter}
            onChange={(e) => setArbiter(e.target.value.trim())}
            disabled={isLoading}
            className="w-full bg-zinc-950 border border-zinc-800 rounded-lg px-3 py-2 text-sm text-zinc-100 placeholder-zinc-600 focus:outline-none focus:border-indigo-500 font-mono"
            required
          />
        </div>

        <div>
          <label className="block text-xs font-medium uppercase tracking-wider text-zinc-400 mb-1">
            Deposit Amount (ETH)
          </label>
          <input
            type="number"
            step="any"
            placeholder="0.01"
            value={depositAmount}
            onChange={(e) => setDepositAmount(e.target.value)}
            disabled={isLoading}
            className="w-full bg-zinc-950 border border-zinc-800 rounded-lg px-3 py-2 text-sm text-zinc-100 placeholder-zinc-600 focus:outline-none focus:border-indigo-500"
            required
          />
        </div>

        <button
          type="submit"
          disabled={!mounted || isLoading || !isConnected}
          className="w-full mt-2 flex items-center justify-center gap-2 bg-indigo-600 hover:bg-indigo-500 disabled:bg-zinc-800 disabled:text-zinc-600 text-white font-medium py-2.5 px-4 rounded-lg transition-colors text-sm cursor-pointer disabled:cursor-not-allowed"
        >
          {!mounted ? (
            'Loading...'
          ) : isLoading ? (
            <>
              <Loader2 className="w-4 h-4 animate-spin" />
              <span>Confirming on Chain...</span>
            </>
          ) : !isConnected ? (
            'Connect Wallet to Deploy'
          ) : (
            'Deploy & Initialize Escrow'
          )}
        </button>
      </form>
    </div>
  );
};