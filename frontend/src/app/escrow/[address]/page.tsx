'use client';

import { use, useEffect, useState } from 'react';
import Link from 'next/link';
import { useSearchParams } from 'next/navigation';
import { useEscrowState } from '@/hooks/useEscrowState';
import { useTokenMetadata } from '@/hooks/useTokenSymbol';
import { useEtherscanHistory } from '@/hooks/useEtherscanHistory';
import { StateTimeline } from '@/components/escrow/StateTimeline';
import { ActionPanel } from '@/components/escrow/ActionPanel';
import { getEscrowMetadata, setEscrowMetadata } from '@/utils/escrowMetadata';
import { Pencil, Check, X, FileText, History, ExternalLink, ArrowLeft, Wallet, Shield } from 'lucide-react';

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

  const { symbol, formatAmount } = useTokenMetadata(token);
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
      <div className="flex flex-col items-center justify-center min-h-[50vh]">
        <div className="w-8 h-8 border-3 border-red-600 border-t-transparent rounded-full animate-spin mb-3" />
        <p className="text-slate-500 text-xs font-medium">Synchronizing vault ledger with Sepolia...</p>
      </div>
    );
  }

  return (
    <div className="max-w-7xl mx-auto py-2">
      {/* Top Header */}
      <div className="flex items-center justify-between gap-4 mb-4">
        <div>
          <Link
            href="/dashboard"
            className="text-[11px] text-slate-500 hover:text-slate-900 transition inline-flex items-center gap-1 font-semibold mb-1"
          >
            <ArrowLeft className="w-3 h-3" /> Return to Portfolio
          </Link>

          {!isEditing ? (
            <div className="flex items-center gap-2">
              <h1 className="text-xl font-extrabold text-slate-900 tracking-tight">
                {title || 'Escrow Settlement Vault'}
              </h1>
              <button
                onClick={() => setIsEditing(true)}
                className="p-1 text-slate-400 hover:text-slate-700 transition"
                title="Edit title and terms"
              >
                <Pencil className="w-3.5 h-3.5" />
              </button>
              <span className="text-xs font-mono text-slate-400">({escrowAddress.slice(0, 8)}...{escrowAddress.slice(-6)})</span>
            </div>
          ) : (
            <div className="flex items-center gap-2 my-1">
              <input
                type="text"
                value={editTitle}
                onChange={(e) => setEditTitle(e.target.value)}
                placeholder="Agreement Title..."
                className="bg-white border border-slate-300 rounded px-2.5 py-1 text-xs text-slate-900 focus:outline-none focus:border-red-600"
              />
              <button
                onClick={handleSaveMetadata}
                className="px-2 py-1 bg-red-600 text-white rounded text-xs font-bold"
              >
                Save
              </button>
              <button
                onClick={handleCancelEdit}
                className="px-2 py-1 bg-slate-200 text-slate-600 rounded text-xs font-semibold"
              >
                Cancel
              </button>
            </div>
          )}
        </div>

        <a
          href={`https://sepolia.etherscan.io/address/${escrowAddress}`}
          target="_blank"
          rel="noopener noreferrer"
          className="px-3 py-1.5 bg-white hover:bg-slate-50 border border-slate-200 text-slate-700 rounded-lg text-xs font-semibold shadow-xs transition flex items-center gap-1.5"
        >
          Sepolia Ledger <ExternalLink className="w-3 h-3 text-slate-400" />
        </a>
      </div>

      {/* 1. Compact Milestone State Sequence */}
      <StateTimeline currentState={currentState} />

      {/* 2. Main 2-Column Split Dashboard */}
      <div className="grid grid-cols-1 lg:grid-cols-12 gap-5 items-start">
        
        {/* Left Column (5 Cols): Stakeholders, Locked Capital & Description */}
        <div className="lg:col-span-5 space-y-4">
          
          {/* Capital Card */}
          <div className="bg-white border border-slate-200 rounded-xl p-5 shadow-xs">
            <span className="text-[10px] uppercase font-bold tracking-wider text-slate-500 block">
              Locked Capital Balance
            </span>
            <p className="text-3xl font-extrabold text-slate-900 tracking-tight mt-1">
              {formatAmount(amount)} <span className="text-sm font-bold text-red-600">{symbol}</span>
            </p>
            {description && (
              <p className="text-xs text-slate-500 mt-2.5 pt-2.5 border-t border-slate-100 leading-relaxed">
                {description}
              </p>
            )}
          </div>

          {/* Stakeholders Card */}
          <div className="bg-white border border-slate-200 rounded-xl p-5 shadow-xs space-y-3">
            <span className="text-[10px] uppercase font-bold tracking-wider text-slate-500 block">
              Designated Stakeholders
            </span>

            <div className="p-2.5 bg-slate-50 rounded-lg border border-slate-200/80">
              <span className="text-[10px] font-bold text-slate-500 uppercase block">Client (Depositor)</span>
              <p className="text-xs font-mono text-slate-800 truncate mt-0.5" title={client}>{client}</p>
            </div>

            <div className="p-2.5 bg-slate-50 rounded-lg border border-slate-200/80">
              <span className="text-[10px] font-bold text-slate-500 uppercase block">Beneficiary (Freelancer)</span>
              <p className="text-xs font-mono text-slate-800 truncate mt-0.5" title={freelancer}>{freelancer}</p>
            </div>

            <div className="p-2.5 bg-slate-50 rounded-lg border border-slate-200/80">
              <span className="text-[10px] font-bold text-slate-500 uppercase block">Arbiter (Mediator)</span>
              <p className="text-xs font-mono text-slate-800 truncate mt-0.5" title={arbiter}>{arbiter}</p>
            </div>
          </div>

        </div>

        {/* Right Column (7 Cols): Settlement Panel & Compact Activity Trail */}
        <div className="lg:col-span-7 space-y-4">
          
          {/* Execution Panel */}
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

          {/* Compact Activity Trail with Internal Scroll */}
          <div className="bg-white border border-slate-200 rounded-xl p-4 shadow-xs">
            <h3 className="text-xs font-bold uppercase tracking-wider text-slate-900 mb-2.5 flex items-center gap-1.5">
              <History className="w-3.5 h-3.5 text-red-600" />
              On-Chain Activity Trail
            </h3>

            {isHistoryLoading ? (
              <p className="text-xs text-slate-400">Querying ledger events...</p>
            ) : history.length === 0 ? (
              <p className="text-xs text-slate-400">No public transactions recorded yet.</p>
            ) : (
              <div className="space-y-1.5 max-h-48 overflow-y-auto pr-1">
                {history.map((tx) => (
                  <div
                    key={tx.hash}
                    className="flex items-center justify-between p-2 bg-slate-50 rounded-md border border-slate-200 text-xs"
                  >
                    <div className="flex items-center gap-1.5 truncate max-w-[240px]">
                      <span className="font-mono text-slate-700 truncate">{tx.hash}</span>
                      <a
                        href={`https://sepolia.etherscan.io/tx/${tx.hash}`}
                        target="_blank"
                        rel="noopener noreferrer"
                        className="text-red-600 hover:text-red-700 font-semibold shrink-0"
                      >
                        <ExternalLink className="w-3 h-3" />
                      </a>
                    </div>
                    <span className="text-[10px] font-mono text-slate-400 shrink-0">
                      {new Date(tx.timestamp * 1000).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}
                    </span>
                  </div>
                ))}
              </div>
            )}
          </div>

        </div>

      </div>
    </div>
  );
}
