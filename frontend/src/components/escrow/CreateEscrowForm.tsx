'use client';

import React, { useState, useSyncExternalStore, useEffect } from 'react';
import Link from 'next/link';
import { isAddress, getAddress, zeroAddress } from 'viem';
import { useAccount } from 'wagmi';
import { useCreateEscrow } from '@/hooks/useCreateEscrow';
import { setEscrowMetadata } from '@/utils/escrowMetadata';
import { AlertCircle, CheckCircle2, Loader2, ArrowUpRight, Copy, Check, Coins } from 'lucide-react';

const subscribe = () => () => {};

export const CreateEscrowForm = () => {
  const mounted = useSyncExternalStore(
    subscribe,
    () => true,
    () => false
  );

  const { isConnected, address: clientAddress } = useAccount();
  const { createEscrow, isLoading, isSuccess, txHash, deployedAddress, error } = useCreateEscrow();

  const [assetType, setAssetType] = useState<'ETH' | 'ERC20'>('ETH');
  const [tokenAddress, setTokenAddress] = useState('');
  const [projectTitle, setProjectTitle] = useState('');
  const [description, setDescription] = useState('');
  const [freelancer, setFreelancer] = useState('');
  const [arbiter, setArbiter] = useState('');
  const [depositAmount, setDepositAmount] = useState('');
  const [validationError, setValidationError] = useState<string | null>(null);
  const [copied, setCopied] = useState(false);

  useEffect(() => {
    if (isSuccess && deployedAddress && (projectTitle || description)) {
      setEscrowMetadata(deployedAddress, {
        title: projectTitle.trim() || undefined,
        description: description.trim() || undefined,
      });
    }
  }, [isSuccess, deployedAddress, projectTitle, description]);

  const getShareableUrl = () => {
    if (!deployedAddress) return '';
    const origin = typeof window !== 'undefined' ? window.location.origin : '';
    const params = new URLSearchParams();
    if (projectTitle.trim()) params.set('title', projectTitle.trim());
    if (description.trim()) params.set('desc', description.trim());
    const queryString = params.toString();
    return `${origin}/escrow/${deployedAddress}${queryString ? `?${queryString}` : ''}`;
  };

  const shareableUrl = getShareableUrl();

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

    if (assetType === 'ERC20' && !isAddress(tokenAddress)) {
      setValidationError('Invalid ERC-20 token contract address.');
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
      setValidationError('Deposit amount must be greater than 0.');
      return;
    }

    try {
      await createEscrow({
        freelancer: cleanFreelancer,
        arbiter: cleanArbiter,
        depositAmount,
        token: assetType === 'ERC20' ? getAddress(tokenAddress) : zeroAddress,
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
              <span className="text-[11px] uppercase tracking-wider text-zinc-500 font-semibold block font-sans">
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

              <div className="pt-2 flex items-center justify-between border-t border-zinc-800/80 font-sans">
                <Link
                  href={shareableUrl ? shareableUrl.replace(typeof window !== 'undefined' ? window.location.origin : '', '') : `/escrow/${deployedAddress}`}
                  className="inline-flex items-center gap-1 font-semibold text-indigo-400 hover:text-indigo-300"
                >
                  Open Escrow Agreement →
                </Link>
                {txHash && (
                  <a
                    href={`https://sepolia.etherscan.io/tx/${txHash}`}
                    target="_blank"
                    rel="noopener noreferrer"
                    className="inline-flex items-center gap-1 text-[11px] text-zinc-400 hover:text-zinc-300 underline"
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
        {/* Project Title Field */}
        <div>
          <label className="block text-xs font-medium uppercase tracking-wider text-zinc-400 mb-1">
            Project Title <span className="text-zinc-500 font-normal lowercase">(optional identifier)</span>
          </label>
          <input
            type="text"
            placeholder="e.g. Next.js DApp Frontend & Smart Contracts"
            value={projectTitle}
            onChange={(e) => setProjectTitle(e.target.value)}
            disabled={isLoading}
            className="w-full bg-zinc-950 border border-zinc-800 rounded-lg px-3 py-2 text-sm text-zinc-100 placeholder-zinc-600 focus:outline-none focus:border-indigo-500"
          />
        </div>

        {/* Project Description Field */}
        <div>
          <label className="block text-xs font-medium uppercase tracking-wider text-zinc-400 mb-1">
            Milestone Scope / Description <span className="text-zinc-500 font-normal lowercase">(optional)</span>
          </label>
          <textarea
            rows={2}
            placeholder="Deliverables: Tested escrow smart contracts, integration hooks, and verified Sepolia deployment."
            value={description}
            onChange={(e) => setDescription(e.target.value)}
            disabled={isLoading}
            className="w-full bg-zinc-950 border border-zinc-800 rounded-lg px-3 py-2 text-sm text-zinc-100 placeholder-zinc-600 focus:outline-none focus:border-indigo-500 resize-none"
          />
        </div>

        {/* Asset Selection Toggle (ETH vs ERC-20) */}
        <div>
          <label className="block text-xs font-medium uppercase tracking-wider text-zinc-400 mb-1.5">
            Escrow Asset
          </label>
          <div className="grid grid-cols-2 gap-2">
            <button
              type="button"
              onClick={() => setAssetType('ETH')}
              className={`flex items-center justify-center gap-2 py-2 px-3 rounded-lg text-xs font-semibold border transition ${
                assetType === 'ETH'
                  ? 'bg-indigo-600/20 border-indigo-500 text-indigo-300'
                  : 'bg-zinc-950 border-zinc-800 text-zinc-400 hover:border-zinc-700'
              }`}
            >
              <Coins className="w-3.5 h-3.5" />
              Native ETH
            </button>
            <button
              type="button"
              onClick={() => setAssetType('ERC20')}
              className={`flex items-center justify-center gap-2 py-2 px-3 rounded-lg text-xs font-semibold border transition ${
                assetType === 'ERC20'
                  ? 'bg-indigo-600/20 border-indigo-500 text-indigo-300'
                  : 'bg-zinc-950 border-zinc-800 text-zinc-400 hover:border-zinc-700'
              }`}
            >
              <Coins className="w-3.5 h-3.5" />
              ERC-20 Token
            </button>
          </div>
        </div>

        {/* ERC-20 Address Input (Conditional) */}
        {assetType === 'ERC20' && (
          <div>
            <label className="block text-xs font-medium uppercase tracking-wider text-zinc-400 mb-1">
              Token Contract Address
            </label>
            <input
              type="text"
              placeholder="0x... (e.g. Sepolia testnet USDC/USDT)"
              value={tokenAddress}
              onChange={(e) => setTokenAddress(e.target.value.trim())}
              disabled={isLoading}
              className="w-full bg-zinc-950 border border-zinc-800 rounded-lg px-3 py-2 text-sm text-zinc-100 placeholder-zinc-600 focus:outline-none focus:border-indigo-500 font-mono"
              required
            />
          </div>
        )}

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
            Deposit Amount {assetType === 'ETH' ? '(ETH)' : '(Tokens)'}
          </label>
          <input
            type="number"
            step="any"
            placeholder={assetType === 'ETH' ? '0.01' : '100'}
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
            `Deploy & Initialize Escrow (${assetType})`
          )}
        </button>
      </form>
    </div>
  );
};