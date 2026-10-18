'use client';

import { useState } from 'react';
import Link from 'next/link';
import { useAccount } from 'wagmi';
import { useEscrowState } from '@/hooks/useEscrowState';
import { useTokenMetadata } from '@/hooks/useTokenSymbol';
import { EscrowState } from '@/constants/contracts';
import { getEscrowMetadata, setEscrowMetadata, toggleHideEscrow, isEscrowHidden } from '@/utils/escrowMetadata';
import { ExternalLink, ArrowRight, EyeOff, Eye, Pencil, Check, X } from 'lucide-react';

interface EscrowCardProps {
  escrowAddress: `0x${string}`;
  onVisibilityChange?: () => void;
}

const stateLabels: Record<EscrowState, { label: string; color: string }> = {
  [EscrowState.Pending]: { label: 'Pending Deposit', color: 'bg-amber-50 text-amber-700 border-amber-200' },
  [EscrowState.Funded]: { label: 'Active Vault', color: 'bg-blue-50 text-blue-700 border-blue-200' },
  [EscrowState.Delivered]: { label: 'In Review', color: 'bg-purple-50 text-purple-700 border-purple-200' },
  [EscrowState.Completed]: { label: 'Settled', color: 'bg-emerald-50 text-emerald-700 border-emerald-200' },
  [EscrowState.Disputed]: { label: 'Disputed', color: 'bg-red-50 text-red-700 border-red-200' },
};

export function EscrowCard({ escrowAddress, onVisibilityChange }: EscrowCardProps) {
  const { address } = useAccount();
  const { client, freelancer, token, amount, currentState, isLoading } = useEscrowState(escrowAddress);

  const { symbol, formatAmount } = useTokenMetadata(token);

  const [title, setTitle] = useState(() => getEscrowMetadata(escrowAddress).title || '');
  const [isEditing, setIsEditing] = useState(false);
  const [editTitle, setEditTitle] = useState(title);
  const [hidden, setHidden] = useState(() => isEscrowHidden(escrowAddress));

  const handleSaveTitle = () => {
    setEscrowMetadata(escrowAddress, { title: editTitle.trim() || undefined });
    setTitle(editTitle.trim());
    setIsEditing(false);
  };

  const handleCancelTitle = () => {
    setEditTitle(title);
    setIsEditing(false);
  };

  const handleToggleHide = () => {
    const isNowHidden = toggleHideEscrow(escrowAddress);
    setHidden(isNowHidden);
    if (onVisibilityChange) onVisibilityChange();
  };

  if (isLoading) {
    return (
      <div className="bg-white border border-slate-200 p-6 rounded-xl shadow-xs animate-pulse">
        <div className="h-4 bg-slate-100 rounded w-1/3 mb-4"></div>
        <div className="h-7 bg-slate-100 rounded w-1/2 mb-3"></div>
        <div className="h-4 bg-slate-100 rounded w-2/3"></div>
      </div>
    );
  }

  const isClient = address?.toLowerCase() === client?.toLowerCase();
  const isFreelancer = address?.toLowerCase() === freelancer?.toLowerCase();

  const roleLabel = isClient
    ? 'Client'
    : isFreelancer
    ? 'Freelancer'
    : 'Observer';

  const statusInfo = currentState !== undefined ? stateLabels[currentState] : stateLabels[EscrowState.Pending];

  return (
    <div className={`bg-white border ${hidden ? 'border-slate-200 opacity-60' : 'border-slate-200 hover:border-slate-300 hover:shadow-md'} transition-all duration-150 rounded-xl p-6 flex flex-col justify-between shadow-xs`}>
      <div>
        {/* Top Badges & Actions */}
        <div className="flex items-center justify-between gap-2 mb-4">
          <span className={`text-[11px] uppercase tracking-wider px-2.5 py-0.5 rounded-full border font-semibold ${statusInfo.color}`}>
            {statusInfo.label}
          </span>
          <div className="flex items-center gap-1.5">
            <span className="text-[11px] font-semibold bg-slate-100 text-slate-700 px-2.5 py-0.5 rounded-full border border-slate-200">
              {roleLabel}
            </span>
            <button
              onClick={handleToggleHide}
              title={hidden ? 'Unhide contract' : 'Archive / Hide contract'}
              className="p-1 rounded text-slate-400 hover:text-slate-600 hover:bg-slate-100 transition"
            >
              {hidden ? <Eye className="w-3.5 h-3.5 text-red-600" /> : <EyeOff className="w-3.5 h-3.5" />}
            </button>
          </div>
        </div>

        {/* Project Title / Renaming */}
        <div className="mb-4">
          {!isEditing ? (
            <div className="flex items-center justify-between gap-2 group">
              <h3 className="text-base font-bold text-slate-900 tracking-tight truncate" title={title || escrowAddress}>
                {title || 'Untitled Agreement'}
              </h3>
              <button
                onClick={() => setIsEditing(true)}
                className="opacity-0 group-hover:opacity-100 p-1 text-slate-400 hover:text-slate-700 transition"
                title="Rename agreement"
              >
                <Pencil className="w-3.5 h-3.5" />
              </button>
            </div>
          ) : (
            <div className="flex items-center gap-1.5 my-1">
              <input
                type="text"
                value={editTitle}
                onChange={(e) => setEditTitle(e.target.value)}
                placeholder="Project title..."
                className="w-full bg-slate-50 border border-slate-300 rounded px-2.5 py-1 text-xs text-slate-900 focus:outline-none focus:border-red-600"
                autoFocus
              />
              <button
                onClick={handleSaveTitle}
                className="p-1 text-emerald-600 hover:bg-emerald-50 rounded"
              >
                <Check className="w-3.5 h-3.5" />
              </button>
              <button
                onClick={handleCancelTitle}
                className="p-1 text-slate-400 hover:bg-slate-100 rounded"
              >
                <X className="w-3.5 h-3.5" />
              </button>
            </div>
          )}
        </div>

        {/* Vault Value */}
        <div className="mb-5 pb-4 border-b border-slate-100">
          <span className="text-[11px] uppercase tracking-wider text-slate-500 font-semibold block">Escrow Valuation</span>
          <p className="text-2xl font-bold text-slate-900 tracking-tight mt-0.5">
            {formatAmount(amount)} <span className="text-sm font-semibold text-slate-500">{symbol}</span>
          </p>
        </div>

        {/* Contract Identifiers */}
        <div className="space-y-1.5 text-xs font-mono text-slate-600 mb-5 bg-slate-50 p-3 rounded-lg border border-slate-200">
          <div className="truncate">
            <span className="text-slate-400 font-sans font-medium text-[11px]">Vault: </span>
            {escrowAddress}
          </div>
          <div className="truncate">
            <span className="text-slate-400 font-sans font-medium text-[11px]">Beneficiary: </span>
            {freelancer || '...'}
          </div>
        </div>
      </div>

      {/* Footer Actions */}
      <div className="flex items-center justify-between pt-2 border-t border-slate-100">
        <a
          href={`https://sepolia.etherscan.io/address/${escrowAddress}`}
          target="_blank"
          rel="noopener noreferrer"
          className="text-xs font-medium text-slate-500 hover:text-slate-800 flex items-center gap-1 transition"
        >
          Audit Ledger <ExternalLink className="w-3 h-3" />
        </a>

        <Link
          href={`/escrow/${escrowAddress}`}
          className="text-xs font-bold text-red-600 hover:text-red-700 flex items-center gap-1 transition"
        >
          Manage Vault <ArrowRight className="w-3.5 h-3.5" />
        </Link>
      </div>
    </div>
  );
}
