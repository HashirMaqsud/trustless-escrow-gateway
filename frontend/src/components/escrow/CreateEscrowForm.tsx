'use client';

import React, { useState, useSyncExternalStore, useEffect } from 'react';
import Link from 'next/link';
import { isAddress, getAddress, zeroAddress } from 'viem';
import { useAccount, useChainId, usePublicClient } from 'wagmi';
import { useCreateEscrow } from '@/hooks/useCreateEscrow';
import { setEscrowMetadata } from '@/utils/escrowMetadata';
import { SUPPORTED_TOKENS } from '@/constants/tokens';
import { AlertCircle, CheckCircle2, Loader2, ArrowUpRight, Copy, Check, Coins } from 'lucide-react';

const subscribe = () => () => {};

export const CreateEscrowForm = () => {
  const mounted = useSyncExternalStore(
    subscribe,
    () => true,
    () => false
  );

  const { isConnected, address: clientAddress } = useAccount();
  const chainId = useChainId();
  const publicClient = usePublicClient();
  const { createEscrow, isLoading, isSuccess, txHash, deployedAddress, error } = useCreateEscrow();

  const [assetType, setAssetType] = useState<'ETH' | 'ERC20'>('ETH');
  const [selectedTokenSymbol, setSelectedTokenSymbol] = useState<string>('USDC');
  const [customTokenAddress, setCustomTokenAddress] = useState('');
  const [projectTitle, setProjectTitle] = useState('');
  const [description, setDescription] = useState('');
  const [freelancer, setFreelancer] = useState('');
  const [arbiter, setArbiter] = useState('');
  const [depositAmount, setDepositAmount] = useState('');
  const [validationError, setValidationError] = useState<string | null>(null);
  const [isValidatingToken, setIsValidatingToken] = useState(false);
  const [copied, setCopied] = useState(false);

  // Retrieve tokens configured for the current connected chain
  const availableTokens = SUPPORTED_TOKENS[chainId] || SUPPORTED_TOKENS[11155111] || [];

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

    // Validate freelancer address and reject zero address
    if (!isAddress(freelancer) || freelancer.toLowerCase() === zeroAddress.toLowerCase()) {
      setValidationError('Invalid Freelancer address. Zero address cannot be assigned.');
      return;
    }

    // Validate arbiter address and reject zero address
    if (!isAddress(arbiter) || arbiter.toLowerCase() === zeroAddress.toLowerCase()) {
      setValidationError('Invalid Arbiter address. Zero address cannot be assigned.');
      return;
    }

    const cleanFreelancer = getAddress(freelancer);
    const cleanArbiter = getAddress(arbiter);
    const cleanClient = clientAddress ? getAddress(clientAddress) : '';

    // Prevent client from assigning self as freelancer
    if (cleanFreelancer === cleanClient) {
      setValidationError('Freelancer address cannot be the same as Client address.');
      return;
    }

    // Ensure arbiter is distinct from client and freelancer
    if (cleanArbiter === cleanClient || cleanArbiter === cleanFreelancer) {
      setValidationError('Arbiter must be an independent third party.');
      return;
    }

    const numAmount = parseFloat(depositAmount);
    if (isNaN(numAmount) || numAmount <= 0) {
      setValidationError('Deposit amount must be greater than 0.');
      return;
    }

    let finalTokenAddress: `0x${string}` = zeroAddress;

    if (assetType === 'ERC20') {
      let resolvedAddress = '';

      if (selectedTokenSymbol === 'CUSTOM') {
        resolvedAddress = customTokenAddress.trim();
      } else {
        const found = availableTokens.find((t) => t.symbol === selectedTokenSymbol);
        resolvedAddress = found ? found.address : '';
      }

      if (!isAddress(resolvedAddress)) {
        setValidationError('Invalid ERC-20 token contract address.');
        return;
      }

      const cleanToken = getAddress(resolvedAddress);

      // Prevent selecting zero address as an ERC-20 token
      if (cleanToken.toLowerCase() === zeroAddress.toLowerCase()) {
        setValidationError('Zero address cannot be an ERC-20 token. Use the Native ETH tab instead.');
        return;
      }

      // Verify whether the address contains deployed bytecode or is an EOA wallet
      if (publicClient) {
        setIsValidatingToken(true);
        try {
          const bytecode = await publicClient.getBytecode({ address: cleanToken });
          if (!bytecode || bytecode === '0x') {
            setValidationError('The selected token address is an EOA (wallet), not a deployed contract.');
            setIsValidatingToken(false);
            return;
          }
        } catch {
          setValidationError('Could not verify token contract bytecode on Sepolia.');
          setIsValidatingToken(false);
          return;
        }
        setIsValidatingToken(false);
      }

      finalTokenAddress = cleanToken;
    }

    try {
      await createEscrow({
        freelancer: cleanFreelancer,
        arbiter: cleanArbiter,
        depositAmount,
        token: finalTokenAddress,
      });
    } catch {
      // Error is caught and surfaced by the useCreateEscrow hook
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
            disabled={isLoading || isValidatingToken}
            className="w-full bg-zinc-950 border border-zinc-800 rounded-lg px-3 py-2 text-sm text-zinc-100 placeholder-zinc-600 focus:outline-none focus:border-indigo-500"
          />
        </div>

        {/* Milestone Description Field */}
        <div>
          <label className="block text-xs font-medium uppercase tracking-wider text-zinc-400 mb-1">
            Milestone Scope / Description <span className="text-zinc-500 font-normal lowercase">(optional)</span>
          </label>
          <textarea
            rows={2}
            placeholder="Deliverables: Tested escrow smart contracts, integration hooks, and verified Sepolia deployment."
            value={description}
            onChange={(e) => setDescription(e.target.value)}
            disabled={isLoading || isValidatingToken}
            className="w-full bg-zinc-950 border border-zinc-800 rounded-lg px-3 py-2 text-sm text-zinc-100 placeholder-zinc-600 focus:outline-none focus:border-indigo-500 resize-none"
          />
        </div>

        {/* Asset Selection Buttons */}
        <div>
          <label className="block text-xs font-medium uppercase tracking-wider text-zinc-400 mb-1.5">
            Escrow Asset
          </label>
          <div className="grid grid-cols-2 gap-2">
            <button
              type="button"
              onClick={() => {
                setAssetType('ETH');
                setValidationError(null);
              }}
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
              onClick={() => {
                setAssetType('ERC20');
                setValidationError(null);
              }}
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

        {/* ERC-20 Token Selector Dropdown */}
        {assetType === 'ERC20' && (
          <div className="space-y-3">
            <div>
              <label className="block text-xs font-medium uppercase tracking-wider text-zinc-400 mb-1">
                Select Token
              </label>
              <select
                value={selectedTokenSymbol}
                onChange={(e) => {
                  setSelectedTokenSymbol(e.target.value);
                  setValidationError(null);
                }}
                disabled={isLoading || isValidatingToken}
                className="w-full bg-zinc-950 border border-zinc-800 rounded-lg px-3 py-2 text-sm text-zinc-100 focus:outline-none focus:border-indigo-500"
              >
                {availableTokens.map((t) => (
                  <option key={t.symbol} value={t.symbol}>
                    {t.name} ({t.symbol})
                  </option>
                ))}
                <option value="CUSTOM">Custom Contract Address...</option>
              </select>
            </div>

            {selectedTokenSymbol === 'CUSTOM' && (
              <div>
                <label className="block text-xs font-medium uppercase tracking-wider text-zinc-400 mb-1">
                  Custom Contract Address
                </label>
                <input
                  type="text"
                  placeholder="0x..."
                  value={customTokenAddress}
                  onChange={(e) => {
                    setCustomTokenAddress(e.target.value.trim());
                    setValidationError(null);
                  }}
                  disabled={isLoading || isValidatingToken}
                  className="w-full bg-zinc-950 border border-zinc-800 rounded-lg px-3 py-2 text-sm text-zinc-100 placeholder-zinc-600 focus:outline-none focus:border-indigo-500 font-mono"
                  required
                />
              </div>
            )}
          </div>
        )}

        {/* Freelancer Address Field */}
        <div>
          <label className="block text-xs font-medium uppercase tracking-wider text-zinc-400 mb-1">
            Freelancer Address
          </label>
          <input
            type="text"
            placeholder="0x..."
            value={freelancer}
            onChange={(e) => {
              setFreelancer(e.target.value.trim());
              setValidationError(null);
            }}
            disabled={isLoading || isValidatingToken}
            className="w-full bg-zinc-950 border border-zinc-800 rounded-lg px-3 py-2 text-sm text-zinc-100 placeholder-zinc-600 focus:outline-none focus:border-indigo-500 font-mono"
            required
          />
        </div>

        {/* Arbiter Address Field */}
        <div>
          <label className="block text-xs font-medium uppercase tracking-wider text-zinc-400 mb-1">
            Arbiter Address
          </label>
          <input
            type="text"
            placeholder="0x..."
            value={arbiter}
            onChange={(e) => {
              setArbiter(e.target.value.trim());
              setValidationError(null);
            }}
            disabled={isLoading || isValidatingToken}
            className="w-full bg-zinc-950 border border-zinc-800 rounded-lg px-3 py-2 text-sm text-zinc-100 placeholder-zinc-600 focus:outline-none focus:border-indigo-500 font-mono"
            required
          />
        </div>

        {/* Deposit Amount Field */}
        <div>
          <label className="block text-xs font-medium uppercase tracking-wider text-zinc-400 mb-1">
            Deposit Amount {assetType === 'ETH' ? '(ETH)' : `(${selectedTokenSymbol === 'CUSTOM' ? 'Tokens' : selectedTokenSymbol})`}
          </label>
          <input
            type="number"
            step="any"
            placeholder={assetType === 'ETH' ? '0.01' : '100'}
            value={depositAmount}
            onChange={(e) => {
              setDepositAmount(e.target.value);
              setValidationError(null);
            }}
            disabled={isLoading || isValidatingToken}
            className="w-full bg-zinc-950 border border-zinc-800 rounded-lg px-3 py-2 text-sm text-zinc-100 placeholder-zinc-600 focus:outline-none focus:border-indigo-500"
            required
          />
        </div>

        {/* Submit Button */}
        <button
          type="submit"
          disabled={!mounted || isLoading || isValidatingToken || !isConnected}
          className="w-full mt-2 flex items-center justify-center gap-2 bg-indigo-600 hover:bg-indigo-500 disabled:bg-zinc-800 disabled:text-zinc-600 text-white font-medium py-2.5 px-4 rounded-lg transition-colors text-sm cursor-pointer disabled:cursor-not-allowed"
        >
          {!mounted ? (
            'Loading...'
          ) : isValidatingToken ? (
            <>
              <Loader2 className="w-4 h-4 animate-spin" />
              <span>Verifying Token Contract...</span>
            </>
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