'use client';

import React, { useState, useSyncExternalStore } from 'react';
import { isAddress, getAddress } from 'viem';
import { useAccount } from 'wagmi';
import { useCreateEscrow } from '@/hooks/useCreateEscrow';
import { AlertCircle, CheckCircle2, Loader2, ArrowUpRight } from 'lucide-react';

const subscribe = () => () => {};

export const CreateEscrowForm = () => {
  const mounted = useSyncExternalStore(
    subscribe,
    () => true,
    () => false
  );

  const { isConnected, address: clientAddress } = useAccount();
  const { createEscrow, isLoading, isSuccess, txHash, error } = useCreateEscrow();

  const [freelancer, setFreelancer] = useState('');
  const [arbiter, setArbiter] = useState('');
  const [depositAmount, setDepositAmount] = useState('');
  const [validationError, setValidationError] = useState<string | null>(null);

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
      // Error handled by useCreateEscrow hook
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
        <div className="mb-5 p-4 bg-emerald-950/40 border border-emerald-800/60 rounded-lg text-emerald-300 text-sm">
          <div className="flex items-center gap-2 font-medium">
            <CheckCircle2 className="w-4 h-4 shrink-0 text-emerald-400" />
            <span>Escrow deployed successfully on Sepolia!</span>
          </div>
          {txHash && (
            <a
              href={`https://sepolia.etherscan.io/tx/${txHash}`}
              target="_blank"
              rel="noopener noreferrer"
              className="mt-2 inline-flex items-center gap-1 text-xs text-emerald-400 underline hover:text-emerald-300"
            >
              View on Sepolia Etherscan <ArrowUpRight className="w-3 h-3" />
            </a>
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
            'Deploy & Lock Funds'
          )}
        </button>
      </form>
    </div>
  );
};