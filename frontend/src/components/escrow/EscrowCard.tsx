'use client';

import { useState } from 'react';
import Link from 'next/link';
import { formatEther } from 'viem';
import { useAccount } from 'wagmi';
import { useEscrowState } from '@/hooks/useEscrowState';
import { EscrowState } from '@/constants/contracts';
import { getEscrowMetadata, setEscrowMetadata, toggleHideEscrow, isEscrowHidden } from '@/utils/escrowMetadata';
import { ExternalLink, ArrowRight, EyeOff, Eye, Pencil, Check, X } from 'lucide-react';

interface EscrowCardProps {
  escrowAddress: `0x${string}`;
  onVisibilityChange?: () => void;
}

const stateLabels: Record<EscrowState, { label: string; color: string }> = {
  [EscrowState.Pending]: { label: 'Pending Deposit', color: 'bg-zinc-800 text-zinc-300 border-zinc-700' },
  [EscrowState.Funded]: { label: 'Funded', color: 'bg-indigo-950 text-indigo-300 border-indigo-800' },
  [EscrowState.Delivered]: { label: 'Delivered', color: 'bg-amber-950 text-amber-300 border-amber-800' },
  [EscrowState.Completed]: { label: 'Completed', color: 'bg-emerald-950 text-emerald-300 border-emerald-800' },
  [EscrowState.Disputed]: { label: 'Disputed', color: 'bg-red-950 text-red-300 border-red-800' },
};

export function EscrowCard({ escrowAddress, onVisibilityChange }: EscrowCardProps) {
  const { address } = useAccount();
  const { client, freelancer, arbiter, amount, currentState, isLoading } = useEscrowState(escrowAddress);

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
      <div className="bg-zinc-900/60 border border-zinc-800 p-5 rounded-xl animate-pulse">
        <div className="h-4 bg-zinc-800 rounded w-1/3 mb-4"></div>
        <div className="h-6 bg-zinc-800 rounded w-1/2 mb-3"></div>
        <div className="h-4 bg-zinc-800 rounded w-2/3"></div>
      </div>
    );
  }

  const isClient = address?.toLowerCase() === client?.toLowerCase();
  const isFreelancer = address?.toLowerCase() === freelancer?.toLowerCase();
  const isArbiter = address?.toLowerCase() === arbiter?.toLowerCase();

  const roleLabel = isClient
    ? 'Client'
    : isFreelancer
    ? 'Freelancer'
    : isArbiter
    ? 'Arbiter'
    : 'Participant';

  const statusInfo = currentState !== undefined ? stateLabels[currentState] : stateLabels[EscrowState.Pending];

  return (
    <div className={`bg-zinc-900 border ${hidden ? 'border-zinc-800/40 opacity-70' : 'border-zinc-800 hover:border-zinc-700'} transition rounded-xl p-5 flex flex-col justify-between`}>
      <div>
        {/* Top Badges & Actions */}
        <div className="flex items-center justify-between gap-2 mb-3">
          <span className={`text-xs px-2.5 py-0.5 rounded-full border font-medium ${statusInfo.color}`}>
            {statusInfo.label}
          </span>
          <div className="flex items-center gap-1.5">
            <span className="text-xs bg-zinc-800 text-zinc-400 px-2 py-0.5 rounded font-mono">
              {roleLabel}
            </span>
            <button
              onClick={handleToggleHide}
              title={hidden ? 'Unhide contract' : 'Archive / Hide contract'}
              className="p-1 rounded text-zinc-500 hover:text-zinc-300 hover:bg-zinc-800 transition"
            >
              {hidden ? <Eye className="w-3.5 h-3.5 text-amber-400" /> : <EyeOff className="w-3.5 h-3.5" />}
            </button>
          </div>
        </div>

        {/* Project Title / Renaming */}
        <div className="mb-3">
          {!isEditing ? (
            <div className="flex items-center justify-between gap-2 group">
              <h3 className="text-sm font-semibold text-white truncate" title={title || escrowAddress}>
                {title || 'Untitled Agreement'}
              </h3>
              <button
                onClick={() => setIsEditing(true)}
                className="opacity-0 group-hover:opacity-100 p-0.5 text-zinc-500 hover:text-zinc-300 transition"
                title="Rename agreement"
              >
                <Pencil className="w-3 h-3" />
              </button>
            </div>
          ) : (
            <div className="flex items-center gap-1 my-1">
              <input
                type="text"
                value={editTitle}
                onChange={(e) => setEditTitle(e.target.value)}
                placeholder="Project title..."
                className="w-full bg-zinc-950 border border-zinc-700 rounded px-2 py-1 text-xs text-white focus:outline-none focus:border-indigo-500"
                autoFocus
              />
              <button
                onClick={handleSaveTitle}
                className="p-1 text-emerald-400 hover:bg-zinc-800 rounded"
              >
                <Check className="w-3.5 h-3.5" />
              </button>
              <button
                onClick={handleCancelTitle}
                className="p-1 text-zinc-400 hover:bg-zinc-800 rounded"
              >
                <X className="w-3.5 h-3.5" />
              </button>
            </div>
          )}
        </div>

        <div className="mb-4">
          <span className="text-xs text-zinc-500 font-medium">Vault Value</span>
          <p className="text-xl font-bold text-white mt-0.5">
            {amount ? `${formatEther(amount)} ETH` : '0 ETH'}
          </p>
        </div>

        <div className="space-y-1 text-xs font-mono text-zinc-400 mb-4 bg-zinc-950 p-2.5 rounded-lg border border-zinc-800/60">
          <div className="truncate">
            <span className="text-zinc-500">Contract: </span>
            {escrowAddress}
          </div>
          <div className="truncate">
            <span className="text-zinc-500">Freelancer: </span>
            {freelancer || '...'}
          </div>
        </div>
      </div>

      <div className="flex items-center justify-between pt-3 border-t border-zinc-800">
        <a
          href={`https://sepolia.etherscan.io/address/${escrowAddress}`}
          target="_blank"
          rel="noopener noreferrer"
          className="text-xs text-zinc-500 hover:text-zinc-300 flex items-center gap-1 transition"
        >
          Etherscan <ExternalLink className="w-3 h-3" />
        </a>

        <Link
          href={`/escrow/${escrowAddress}`}
          className="text-xs font-semibold text-indigo-400 hover:text-indigo-300 flex items-center gap-1 transition"
        >
          Manage <ArrowRight className="w-3.5 h-3.5" />
        </Link>
      </div>
    </div>
  );
}