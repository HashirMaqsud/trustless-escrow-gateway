'use client';

import React, { useState, useSyncExternalStore, useEffect } from 'react';
import Link from 'next/link';
import { isAddress, getAddress, zeroAddress } from 'viem';
import { useAccount, useChainId, usePublicClient } from 'wagmi';
import { useCreateEscrow } from '@/hooks/useCreateEscrow';
import { setEscrowMetadata } from '@/utils/escrowMetadata';
import { SUPPORTED_TOKENS } from '@/constants/tokens';
import { AlertCircle, CheckCircle2, Loader2, ArrowUpRight, Copy, Check, Coins, Shield } from 'lucide-react';

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

    if (!isAddress(freelancer) || freelancer.toLowerCase() === zeroAddress.toLowerCase()) {
      setValidationError('Invalid Freelancer address. Zero address cannot be assigned.');
      return;
    }

    if (!isAddress(arbiter) || arbiter.toLowerCase() === zeroAddress.toLowerCase()) {
      setValidationError('Invalid Arbiter address. Zero address cannot be assigned.');
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

      if (cleanToken.toLowerCase() === zeroAddress.toLowerCase()) {
        setValidationError('Zero address cannot be an ERC-20 token. Use the Native ETH tab instead.');
        return;
      }

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
      // Handled in hook
    }
  };

  return (
    <div className="w-full max-w-md bg-white border border-slate-200 rounded-2xl shadow-lg shadow-slate-200/50 flex flex-col max-h-[82vh] overflow-hidden">
      
      {/* Fixed Form Header */}
      <div className="px-5 py-4 border-b border-slate-100 flex items-center justify-between shrink-0 bg-slate-50/50">
        <div className="flex items-center gap-2">
          <div className="w-7 h-7 rounded-md bg-red-50 border border-red-200 flex items-center justify-center text-red-600">
            <Shield className="w-4 h-4" />
          </div>
          <div>
            <h2 className="text-sm font-bold text-slate-900 leading-tight">Deploy Escrow Vault</h2>
            <span className="text-[11px] text-slate-500">Autonomous Settlement Contract</span>
          </div>
        </div>
        <span className="text-[10px] uppercase font-bold tracking-wider px-2 py-0.5 rounded bg-slate-100 text-slate-600 border border-slate-200">
          Sepolia
        </span>
      </div>

      {/* Scrollable Form Body */}
      <div className="p-5 overflow-y-auto space-y-3.5 text-xs">
        
        {validationError && (
          <div className="flex items-center gap-2 p-2.5 bg-red-50 border border-red-200 rounded-lg text-red-700 text-xs font-medium">
            <AlertCircle className="w-3.5 h-3.5 shrink-0" />
            <span>{validationError}</span>
          </div>
        )}

        {error && (
          <div className="flex items-center gap-2 p-2.5 bg-red-50 border border-red-200 rounded-lg text-red-700 text-xs font-medium">
            <AlertCircle className="w-3.5 h-3.5 shrink-0" />
            <span className="truncate">{error.message || 'Transaction rejected or reverted.'}</span>
          </div>
        )}

        {isSuccess && (
          <div className="p-3 bg-emerald-50 border border-emerald-200 rounded-xl text-emerald-800 space-y-2.5">
            <div className="flex items-center gap-1.5 font-bold text-emerald-700 text-xs">
              <CheckCircle2 className="w-4 h-4 shrink-0" />
              <span>Escrow Initialized Successfully!</span>
            </div>

            {deployedAddress && (
              <div className="bg-white p-2.5 rounded-lg border border-emerald-200 font-mono text-slate-700 space-y-1.5">
                <span className="text-[10px] uppercase tracking-wider text-slate-400 font-bold block font-sans">
                  Shareable Agreement URL
                </span>
                <div className="flex items-center justify-between gap-1.5">
                  <span className="truncate text-slate-600 text-[11px]">{shareableUrl}</span>
                  <button
                    type="button"
                    onClick={handleCopy}
                    className="px-2 py-0.5 bg-slate-100 hover:bg-slate-200 text-slate-800 rounded border border-slate-300 flex items-center gap-1 shrink-0 font-sans text-[11px] font-semibold transition"
                  >
                    {copied ? <Check className="w-3 h-3 text-emerald-600" /> : <Copy className="w-3 h-3 text-slate-500" />}
                    {copied ? 'Copied' : 'Copy'}
                  </button>
                </div>

                <div className="pt-1.5 flex items-center justify-between border-t border-slate-100 font-sans">
                  <Link
                    href={shareableUrl ? shareableUrl.replace(typeof window !== 'undefined' ? window.location.origin : '', '') : `/escrow/${deployedAddress}`}
                    className="inline-flex items-center gap-1 font-bold text-red-600 hover:text-red-700 text-[11px]"
                  >
                    Open Escrow Agreement →
                  </Link>
                  {txHash && (
                    <a
                      href={`https://sepolia.etherscan.io/tx/${txHash}`}
                      target="_blank"
                      rel="noopener noreferrer"
                      className="inline-flex items-center gap-0.5 text-[10px] text-slate-500 hover:text-slate-800 underline"
                    >
                      Etherscan <ArrowUpRight className="w-2.5 h-2.5" />
                    </a>
                  )}
                </div>
              </div>
            )}
          </div>
        )}

        <form onSubmit={handleSubmit} id="escrow-create-form" className="space-y-3">
          
          {/* Project Title Field */}
          <div>
            <label className="block text-[10px] font-bold uppercase tracking-wider text-slate-600 mb-1">
              Agreement Title <span className="text-slate-400 font-normal lowercase">(optional)</span>
            </label>
            <input
              type="text"
              placeholder="e.g. Frontend & Smart Contract Milestone"
              value={projectTitle}
              onChange={(e) => setProjectTitle(e.target.value)}
              disabled={isLoading || isValidatingToken}
              className="w-full bg-slate-50 border border-slate-300 rounded-lg px-2.5 py-1.5 text-xs text-slate-900 placeholder-slate-400 focus:outline-none focus:border-red-600"
            />
          </div>

          {/* Milestone Description Field */}
          <div>
            <label className="block text-[10px] font-bold uppercase tracking-wider text-slate-600 mb-1">
              Deliverable Scope <span className="text-slate-400 font-normal lowercase">(optional)</span>
            </label>
            <textarea
              rows={2}
              placeholder="Deliverables: Tested escrow smart contracts, integration hooks..."
              value={description}
              onChange={(e) => setDescription(e.target.value)}
              disabled={isLoading || isValidatingToken}
              className="w-full bg-slate-50 border border-slate-300 rounded-lg px-2.5 py-1.5 text-xs text-slate-900 placeholder-slate-400 focus:outline-none focus:border-red-600 resize-none"
            />
          </div>

          {/* Asset Selection Buttons */}
          <div>
            <label className="block text-[10px] font-bold uppercase tracking-wider text-slate-600 mb-1">
              Settlement Asset
            </label>
            <div className="grid grid-cols-2 gap-2">
              <button
                type="button"
                onClick={() => {
                  setAssetType('ETH');
                  setValidationError(null);
                }}
                className={`flex items-center justify-center gap-1.5 py-1.5 px-2.5 rounded-lg text-xs font-bold border transition ${
                  assetType === 'ETH'
                    ? 'bg-red-50 border-red-300 text-red-700 shadow-xs'
                    : 'bg-white border-slate-300 text-slate-600 hover:bg-slate-50'
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
                className={`flex items-center justify-center gap-1.5 py-1.5 px-2.5 rounded-lg text-xs font-bold border transition ${
                  assetType === 'ERC20'
                    ? 'bg-red-50 border-red-300 text-red-700 shadow-xs'
                    : 'bg-white border-slate-300 text-slate-600 hover:bg-slate-50'
                }`}
              >
                <Coins className="w-3.5 h-3.5" />
                ERC-20 Token
              </button>
            </div>
          </div>

          {/* ERC-20 Token Selector Dropdown */}
          {assetType === 'ERC20' && (
            <div className="space-y-2">
              <div>
                <label className="block text-[10px] font-bold uppercase tracking-wider text-slate-600 mb-1">
                  Select Token
                </label>
                <select
                  value={selectedTokenSymbol}
                  onChange={(e) => {
                    setSelectedTokenSymbol(e.target.value);
                    setValidationError(null);
                  }}
                  disabled={isLoading || isValidatingToken}
                  className="w-full bg-slate-50 border border-slate-300 rounded-lg px-2.5 py-1.5 text-xs text-slate-900 focus:outline-none focus:border-red-600"
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
                  <input
                    type="text"
                    placeholder="Contract Address (0x...)"
                    value={customTokenAddress}
                    onChange={(e) => {
                      setCustomTokenAddress(e.target.value.trim());
                      setValidationError(null);
                    }}
                    disabled={isLoading || isValidatingToken}
                    className="w-full bg-slate-50 border border-slate-300 rounded-lg px-2.5 py-1.5 text-xs text-slate-900 placeholder-slate-400 focus:outline-none focus:border-red-600 font-mono"
                    required
                  />
                </div>
              )}
            </div>
          )}

          {/* Beneficiary Address */}
          <div>
            <label className="block text-[10px] font-bold uppercase tracking-wider text-slate-600 mb-1">
              Freelancer Address (Beneficiary)
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
              className="w-full bg-slate-50 border border-slate-300 rounded-lg px-2.5 py-1.5 text-xs text-slate-900 placeholder-slate-400 focus:outline-none focus:border-red-600 font-mono"
              required
            />
          </div>

          {/* Arbiter Address */}
          <div>
            <label className="block text-[10px] font-bold uppercase tracking-wider text-slate-600 mb-1">
              Arbiter Address (Independent Mediator)
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
              className="w-full bg-slate-50 border border-slate-300 rounded-lg px-2.5 py-1.5 text-xs text-slate-900 placeholder-slate-400 focus:outline-none focus:border-red-600 font-mono"
              required
            />
          </div>

          {/* Deposit Amount */}
          <div>
            <label className="block text-[10px] font-bold uppercase tracking-wider text-slate-600 mb-1">
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
              className="w-full bg-slate-50 border border-slate-300 rounded-lg px-2.5 py-1.5 text-xs text-slate-900 placeholder-slate-400 focus:outline-none focus:border-red-600"
              required
            />
          </div>
        </form>
      </div>

      {/* Fixed Sticky Form Action Footer */}
      <div className="p-4 border-t border-slate-100 bg-slate-50/70 shrink-0">
        <button
          form="escrow-create-form"
          type="submit"
          disabled={!mounted || isLoading || isValidatingToken || !isConnected}
          className="w-full flex items-center justify-center gap-2 bg-red-600 hover:bg-red-700 disabled:bg-slate-200 disabled:text-slate-400 text-white font-bold py-2.5 px-4 rounded-lg transition-colors text-xs uppercase tracking-wider shadow-xs cursor-pointer disabled:cursor-not-allowed"
        >
          {!mounted ? (
            'Loading...'
          ) : isValidatingToken ? (
            <>
              <Loader2 className="w-3.5 h-3.5 animate-spin" />
              <span>Verifying Token...</span>
            </>
          ) : isLoading ? (
            <>
              <Loader2 className="w-3.5 h-3.5 animate-spin" />
              <span>Deploying to Sepolia...</span>
            </>
          ) : !isConnected ? (
            'Connect Wallet to Deploy'
          ) : (
            `Deploy Escrow (${assetType})`
          )}
        </button>
      </div>

    </div>
  );
};
