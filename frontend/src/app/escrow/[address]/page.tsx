'use client';

import { use, useEffect, useState } from 'react';
import Link from 'next/link';
import { useSearchParams } from 'next/navigation';
import { formatEther } from 'viem';
import { useEscrowState } from '@/hooks/useEscrowState';
import { useEtherscanHistory } from '@/hooks/useEtherscanHistory';
import { StateTimeline } from '@/components/escrow/StateTimeline';
import { ActionPanel } from '@/components/escrow/ActionPanel';
import { getEscrowMetadata, setEscrowMetadata } from '@/utils/escrowMetadata';
import { Pencil, Check, X, FileText, History, ExternalLink } from 'lucide-react';

interface EscrowPageProps {
  params: Promise<{ address: string }>;
}

export default function EscrowDetailPage({ params }: EscrowPageProps) {
  const resolvedParams = use(params);
  const escrowAddress = resolvedParams.address as `0x${string}`;
  const searchParams = useSearchParams();

  const urlTitle = searchParams.get('title') || '';
  const urlDesc = searchParams.get('desc') || '';

  const [title, setTitle] = useState(() => {
    if (urlTitle) return urlTitle;
    return getEscrowMetadata(escrowAddress).title || '';
  });

  const [description, setDescription] = useState(() => {
    if (urlDesc) return urlDesc;
    return getEscrowMetadata(escrowAddress).description || '';
  });

  const [isEditing, setIsEditing] = useState(false);
  const [editTitle, setEditTitle] = useState(title);
  const [editDesc, setEditDesc] = useState(description);

  const {
    client,
    freelancer,
    arbiter,
    token,
    amount,
    currentState,
    deliverableUrl,
    isLoading,
    refetch,
  } = useEscrowState(escrowAddress);

  const { history, isLoading: isHistoryLoading } = useEtherscanHistory(escrowAddress);

  useEffect(() => {
    if (urlTitle || urlDesc) {
      setEscrowMetadata(escrowAddress, {
        title: urlTitle || undefined,
        description: urlDesc || undefined,
      });
    }
  }, [escrowAddress, urlTitle, urlDesc]);

  const handleSaveMetadata = () => {
    setEscrowMetadata(escrowAddress, {
      title: editTitle.trim() || undefined,
      description: editDesc.trim() || undefined,
    });
    setTitle(editTitle.trim());
    setDescription(editDesc.trim());
    setIsEditing(false);
  };

  const handleCancelEdit = () => {
    setEditTitle(title);
    setEditDesc(description);
    setIsEditing(false);
  };

  if (isLoading) {
    return (
      <div className="flex flex-col items-center justify-center min-h-[60vh]">
        <div className="w-10 h-10 border-4 border-indigo-500 border-t-transparent rounded-full animate-spin mb-4" />
        <p className="text-zinc-400 text-sm">Querying escrow state machine from Sepolia...</p>
      </div>
    );
  }

  return (
    <div className="max-w-4xl mx-auto py-8 px-4">
      {/* Top Navigation & Header */}
      <div className="flex flex-col sm:flex-row sm:items-start justify-between gap-4 mb-6">
        <div className="w-full">
          <div className="flex items-center gap-2 mb-2">
            <Link
              href="/dashboard"
              className="text-xs text-zinc-400 hover:text-white transition flex items-center gap-1 font-medium"
            >
              ← Back to Dashboard
            </Link>
          </div>

          {!isEditing ? (
            <div className="space-y-1">
              <div className="flex items-center gap-2.5">
                <h1 className="text-2xl font-bold text-white tracking-tight">
                  {title || 'Escrow Agreement'}
                </h1>
                <button
                  onClick={() => setIsEditing(true)}
                  className="p-1 text-zinc-500 hover:text-zinc-300 rounded transition"
                  title="Edit title and description"
                >
                  <Pencil className="w-4 h-4" />
                </button>
              </div>
              <span className="text-xs font-mono text-zinc-500 break-all block">{escrowAddress}</span>
              {description && (
                <div className="mt-2.5 p-3 rounded-lg bg-zinc-900/60 border border-zinc-800 text-xs text-zinc-300 flex items-start gap-2">
                  <FileText className="w-4 h-4 text-indigo-400 shrink-0 mt-0.5" />
                  <p className="leading-relaxed">{description}</p>
                </div>
              )}
            </div>
          ) : (
            <div className="space-y-2 p-3 bg-zinc-900/90 rounded-lg border border-zinc-700 max-w-xl">
              <div>
                <label className="text-[11px] uppercase tracking-wider text-zinc-400 font-semibold block mb-1">
                  Project Title
                </label>
                <input
                  type="text"
                  value={editTitle}
                  onChange={(e) => setEditTitle(e.target.value)}
                  placeholder="e.g. Next.js DApp Frontend & Smart Contracts"
                  className="w-full bg-zinc-950 border border-zinc-800 rounded px-2.5 py-1.5 text-sm text-white focus:outline-none focus:border-indigo-500"
                />
              </div>

              <div>
                <label className="text-[11px] uppercase tracking-wider text-zinc-400 font-semibold block mb-1">
                  Milestone Scope / Description
                </label>
                <textarea
                  rows={2}
                  value={editDesc}
                  onChange={(e) => setEditDesc(e.target.value)}
                  placeholder="Milestone description..."
                  className="w-full bg-zinc-950 border border-zinc-800 rounded px-2.5 py-1.5 text-xs text-white focus:outline-none focus:border-indigo-500 resize-none"
                />
              </div>

              <div className="flex items-center gap-2 pt-1">
                <button
                  onClick={handleSaveMetadata}
                  className="px-2.5 py-1 bg-indigo-600 hover:bg-indigo-500 text-white rounded text-xs font-semibold flex items-center gap-1 transition"
                >
                  <Check className="w-3.5 h-3.5" /> Save Changes
                </button>
                <button
                  onClick={handleCancelEdit}
                  className="px-2.5 py-1 bg-zinc-800 hover:bg-zinc-700 text-zinc-400 rounded text-xs font-semibold flex items-center gap-1 transition"
                >
                  <X className="w-3.5 h-3.5" /> Cancel
                </button>
              </div>
            </div>
          )}
        </div>

        <div className="flex items-center gap-2 shrink-0">
          <a
            href={`https://sepolia.etherscan.io/address/${escrowAddress}`}
            target="_blank"
            rel="noopener noreferrer"
            className="px-3 py-1.5 bg-zinc-900 hover:bg-zinc-800 border border-zinc-700 text-zinc-300 rounded-lg text-xs font-medium transition"
          >
            Sepolia Etherscan ↗
          </a>
        </div>
      </div>

      {/* State Tracker */}
      <StateTimeline currentState={currentState} />

      {/* Contract Details Card */}
      <div className="bg-zinc-900/80 border border-zinc-800 rounded-xl p-6 mb-8">
        <h2 className="text-sm font-semibold uppercase tracking-wider text-zinc-400 mb-4">
          Vault Specification
        </h2>
        <div className="grid grid-cols-1 sm:grid-cols-2 md:grid-cols-4 gap-4">
          <div className="p-3 bg-zinc-950 rounded-lg border border-zinc-800/80">
            <span className="text-xs text-zinc-500 font-medium">Locked Balance</span>
            <p className="text-lg font-bold text-white mt-1">
              {amount ? `${formatEther(amount)} ETH` : '0 ETH'}
            </p>
          </div>

          <div className="p-3 bg-zinc-950 rounded-lg border border-zinc-800/80">
            <span className="text-xs text-zinc-500 font-medium">Client</span>
            <p className="text-xs font-mono text-zinc-300 mt-1 truncate" title={client}>
              {client || 'Loading...'}
            </p>
          </div>

          <div className="p-3 bg-zinc-950 rounded-lg border border-zinc-800/80">
            <span className="text-xs text-zinc-500 font-medium">Freelancer</span>
            <p className="text-xs font-mono text-zinc-300 mt-1 truncate" title={freelancer}>
              {freelancer || 'Loading...'}
            </p>
          </div>

          <div className="p-3 bg-zinc-950 rounded-lg border border-zinc-800/80">
            <span className="text-xs text-zinc-500 font-medium">Arbiter</span>
            <p className="text-xs font-mono text-zinc-300 mt-1 truncate" title={arbiter}>
              {arbiter || 'Loading...'}
            </p>
          </div>
        </div>
      </div>

      {/* Action Controls */}
      <ActionPanel
        escrowAddress={escrowAddress}
        client={client}
        freelancer={freelancer}
        arbiter={arbiter}
        token={token}
        amount={amount}
        currentState={currentState}
        deliverableUrl={deliverableUrl}
        onActionSuccess={() => refetch()}
      />

      {/* Etherscan On-Chain Audit History */}
      <div className="mt-8 bg-zinc-900/60 border border-zinc-800 rounded-xl p-6">
        <h3 className="text-sm font-semibold uppercase tracking-wider text-zinc-400 mb-4 flex items-center gap-2">
          <History className="w-4 h-4 text-indigo-400" />
          On-Chain Activity Trail (Etherscan Verified)
        </h3>

        {isHistoryLoading ? (
          <p className="text-xs text-zinc-500">Querying transaction history from Sepolia Etherscan...</p>
        ) : history.length === 0 ? (
          <p className="text-xs text-zinc-500">No public transactions recorded on Etherscan for this contract yet.</p>
        ) : (
          <div className="space-y-2">
            {history.map((tx) => (
              <div
                key={tx.hash}
                className="flex flex-col sm:flex-row sm:items-center justify-between p-3 bg-zinc-950 rounded-lg border border-zinc-800/70 text-xs"
              >
                <div className="flex items-center gap-2">
                  <span className="font-mono text-zinc-400 truncate max-w-[200px] sm:max-w-xs">
                    {tx.hash}
                  </span>
                  <a
                    href={`https://sepolia.etherscan.io/tx/${tx.hash}`}
                    target="_blank"
                    rel="noopener noreferrer"
                    className="text-indigo-400 hover:text-indigo-300 inline-flex items-center gap-0.5"
                  >
                    View <ExternalLink className="w-3 h-3" />
                  </a>
                </div>
                <div className="text-zinc-500 font-mono mt-1 sm:mt-0">
                  {new Date(tx.timestamp * 1000).toLocaleString()}
                </div>
              </div>
            ))}
          </div>
        )}
      </div>
    </div>
  );
}