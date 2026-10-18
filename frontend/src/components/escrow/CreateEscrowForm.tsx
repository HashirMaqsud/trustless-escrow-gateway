'use client';

import React, { useState, useSyncExternalStore, useEffect } from 'react';
import Link from 'next/link';
import { isAddress, getAddress, zeroAddress } from 'viem';
import { useAccount, useChainId, usePublicClient } from 'wagmi';
import { useCreateEscrow } from '@/hooks/useCreateEscrow';
import { setEscrowMetadata } from '@/utils/escrowMetadata';
import { SUPPORTED_TOKENS } from '@/constants/tokens';
import { AlertCircle, CheckCircle2, Loader2, ArrowUpRight, Copy, Check, Coins, Shield, LayoutDashboard, X } from 'lucide-react';

const subscribe = () => () => {};

const ERC20_BASIC_ABI = [
  {
    type: 'function',
    name: 'decimals',
    stateMutability: 'view',
    inputs: [],
    outputs: [{ name: '', type: 'uint8' }],
  },
] as const;

const TEXT_ONLY_REGEX = /^[a-zA-Z\s.,'-]*$/;
const MAX_TITLE_LENGTH = 60;
const MAX_DESC_LENGTH = 250;

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
  const [isDismissed, setIsDismissed] = useState(false);

  const availableTokens = SUPPORTED_TOKENS[chainId] || SUPPORTED_TOKENS[11155111] || [];

  // Metadata synchronizer without triggering synchronous setState in effect
  useEffect(() => {
    if (isSuccess && deployedAddress && (projectTitle || description)) {
      setEscrowMetadata(deployedAddress, {
        title: projectTitle.trim() || undefined,
        description: description.trim() || undefined,
      });
    }
  }, [isSuccess, deployedAddress, projectTitle, description]);

  const showModal = isSuccess && Boolean(deployedAddress) && !isDismissed;

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

  const handleTitleChange = (val: string) => {
    setValidationError(null);
    if (!TEXT_ONLY_REGEX.test(val)) {
      setValidationError('Agreement Title must contain text letters only (no numbers or symbols).');
      return;
    }
    if (val.length <= MAX_TITLE_LENGTH) {
      setProjectTitle(val);
    }
  };

  const handleDescriptionChange = (val: string) => {
    setValidationError(null);
    if (!TEXT_ONLY_REGEX.test(val)) {
      setValidationError('Deliverable Scope must contain text letters only (no numbers or symbols).');
      return;
    }
    if (val.length <= MAX_DESC_LENGTH) {
      setDescription(val);
    }
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setValidationError(null);
    setIsDismissed(false);

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
        setValidationError('Invalid ERC-20 token address format.');
        return;
      }

      const cleanToken = getAddress(resolvedAddress);

      if (cleanToken.toLowerCase() === zeroAddress.toLowerCase()) {
        setValidationError('Zero address cannot be an ERC-20 token. Use the Native ETH tab instead.');
        return;
      }

      if (
        cleanToken === cleanClient ||
        cleanToken === cleanFreelancer ||
        cleanToken === cleanArbiter
      ) {
        setValidationError('Invalid ERC-20 token address. Address must be a verified ERC-20 contract, not a personal wallet.');
        return;
      }

      setIsValidatingToken(true);
      try {
        if (!publicClient) {
          throw new Error('RPC unavailable');
        }

        const bytecode = await publicClient.getBytecode({ address: cleanToken });
        if (!bytecode || bytecode === '0x') {
          setValidationError('Invalid ERC-20 token address. Address must be a verified ERC-20 contract, not a personal wallet.');
          setIsValidatingToken(false);
          return;
        }

        await publicClient.readContract({
          address: cleanToken,
          abi: ERC20_BASIC_ABI,
          functionName: 'decimals',
        });
      } catch {
        setValidationError('Invalid ERC-20 token address. Address must be a verified ERC-20 contract, not a personal wallet.');
        setIsValidatingToken(false);
        return;
      }
      setIsValidatingToken(false);

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
    <>
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
          <form onSubmit={handleSubmit} id="escrow-create-form" className="space-y-3">
            
            {/* Project Title Field */}
            <div>
              <div className="flex items-center justify-between mb-1">
                <label className="block text-[10px] font-bold uppercase tracking-wider text-slate-600">
                  Agreement Title <span className="text-slate-400 font-normal lowercase">(text only)</span>
                </label>
                <span className="text-[10px] font-mono text-slate-400">
                  {projectTitle.length}/{MAX_TITLE_LENGTH}
                </span>
              </div>
              <input
                type="text"
                placeholder="e.g. Frontend Architecture Milestone"
                value={projectTitle}
                maxLength={MAX_TITLE_LENGTH}
                onChange={(e) => handleTitleChange(e.target.value)}
                disabled={isLoading || isValidatingToken}
                className="w-full bg-slate-50 border border-slate-300 rounded-lg px-2.5 py-1.5 text-xs text-slate-900 placeholder-slate-400 focus:outline-none focus:border-red-600"
              />
            </div>

            {/* Milestone Description Field */}
            <div>
              <div className="flex items-center justify-between mb-1">
                <label className="block text-[10px] font-bold uppercase tracking-wider text-slate-600">
                  Deliverable Scope <span className="text-slate-400 font-normal lowercase">(text only)</span>
                </label>
                <span className="text-[10px] font-mono text-slate-400">
                  {description.length}/{MAX_DESC_LENGTH}
                </span>
              </div>
              <textarea
                rows={2}
                placeholder="e.g. Audited smart contracts and verified frontend integration."
                value={description}
                maxLength={MAX_DESC_LENGTH}
                onChange={(e) => handleDescriptionChange(e.target.value)}
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
                  className={`flex items-center justify-center gap-1.5 py-1.5 px-2.5 rounded-lg text-xs font-bold border transition cursor-pointer ${
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
                  className={`flex items-center justify-center gap-1.5 py-1.5 px-2.5 rounded-lg text-xs font-bold border transition cursor-pointer ${
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
                    className="w-full bg-slate-50 border border-slate-300 rounded-lg px-2.5 py-1.5 text-xs text-slate-900 focus:outline-none focus:border-red-600 cursor-pointer"
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
        <div className="p-4 border-t border-slate-100 bg-slate-50/90 shrink-0 space-y-2">
          
          {/* Validation Error positioned right above the action button */}
          {validationError && (
            <div className="flex items-center gap-2 p-2 bg-red-50 border border-red-200 rounded-lg text-red-700 text-xs font-medium">
              <AlertCircle className="w-3.5 h-3.5 shrink-0" />
              <span className="leading-tight">{validationError}</span>
            </div>
          )}

          {error && (
            <div className="flex items-center gap-2 p-2 bg-red-50 border border-red-200 rounded-lg text-red-700 text-xs font-medium">
              <AlertCircle className="w-3.5 h-3.5 shrink-0" />
              <span className="truncate leading-tight">{error.message || 'Transaction rejected or reverted.'}</span>
            </div>
          )}

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

      {/* Modern Center Success Pop-up Modal */}
      {showModal && deployedAddress && (
        <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-slate-900/40 backdrop-blur-xs animate-in fade-in duration-200">
          <div className="bg-white border border-slate-200 rounded-2xl p-6 max-w-lg w-full shadow-2xl space-y-4">
            
            {/* Modal Header */}
            <div className="flex items-center justify-between pb-3 border-b border-slate-100">
              <div className="flex items-center gap-2.5">
                <div className="w-9 h-9 rounded-full bg-emerald-50 border border-emerald-200 flex items-center justify-center text-emerald-600 shrink-0">
                  <CheckCircle2 className="w-5 h-5" />
                </div>
                <div>
                  <h3 className="text-base font-extrabold text-slate-900">
                    Escrow Vault Initialized
                  </h3>
                  <p className="text-xs text-slate-500">Autonomous settlement contract deployed to Sepolia</p>
                </div>
              </div>
              <button
                type="button"
                onClick={() => setIsDismissed(true)}
                className="text-slate-400 hover:text-slate-600 p-1 rounded-lg hover:bg-slate-100 transition cursor-pointer"
              >
                <X className="w-4 h-4" />
              </button>
            </div>

            {/* Shareable Link Box */}
            <div className="bg-slate-50 border border-slate-200 p-3.5 rounded-xl space-y-2">
              <span className="text-[10px] uppercase font-bold tracking-wider text-slate-500 block">
                Shareable Agreement URL
              </span>
              <div className="flex items-center gap-2">
                <input
                  type="text"
                  readOnly
                  value={shareableUrl}
                  className="w-full bg-white border border-slate-200 rounded-lg px-2.5 py-1.5 text-xs font-mono text-slate-700 outline-none select-all"
                />
                <button
                  type="button"
                  onClick={handleCopy}
                  className="px-3 py-1.5 bg-slate-900 hover:bg-slate-800 text-white rounded-lg text-xs font-bold flex items-center gap-1.5 shrink-0 transition cursor-pointer"
                >
                  {copied ? <Check className="w-3.5 h-3.5 text-emerald-400" /> : <Copy className="w-3.5 h-3.5" />}
                  {copied ? 'Copied' : 'Copy'}
                </button>
              </div>
            </div>

            {/* Direct Navigation Action Links */}
            <div className="pt-2 flex flex-col sm:flex-row items-center justify-between gap-3">
              <Link
                href={`/escrow/${deployedAddress}${projectTitle ? `?title=${encodeURIComponent(projectTitle)}` : ''}`}
                className="w-full sm:w-auto flex-1 inline-flex items-center justify-center gap-1.5 bg-red-600 hover:bg-red-700 text-white font-bold py-2.5 px-4 rounded-lg text-xs transition shadow-xs cursor-pointer"
              >
                Open Escrow Agreement →
              </Link>
              <Link
                href="/dashboard"
                className="w-full sm:w-auto inline-flex items-center justify-center gap-1.5 bg-white hover:bg-slate-50 border border-slate-300 text-slate-700 font-bold py-2.5 px-4 rounded-lg text-xs transition shadow-xs cursor-pointer"
              >
                <LayoutDashboard className="w-3.5 h-3.5 text-slate-500" />
                Go to Dashboard
              </Link>
              {txHash && (
                <a
                  href={`https://sepolia.etherscan.io/tx/${txHash}`}
                  target="_blank"
                  rel="noopener noreferrer"
                  className="text-[11px] text-slate-400 hover:text-slate-600 underline inline-flex items-center gap-0.5"
                >
                  Ledger <ArrowUpRight className="w-3 h-3" />
                </a>
              )}
            </div>

          </div>
        </div>
      )}
    </>
  );
};
