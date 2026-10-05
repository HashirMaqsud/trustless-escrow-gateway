'use client';

import { EscrowState } from '@/constants/contracts';

interface StateTimelineProps {
  currentState: EscrowState | undefined;
}

const steps = [
  { id: EscrowState.Pending, label: 'Pending Deposit', desc: 'Awaiting client funds' },
  { id: EscrowState.Funded, label: 'Funded', desc: 'Work in progress' },
  { id: EscrowState.Delivered, label: 'Delivered', desc: 'Pending client review' },
  { id: EscrowState.Completed, label: 'Completed', desc: 'Funds settled on-chain' },
];

export function StateTimeline({ currentState }: StateTimelineProps) {
  const isDisputed = currentState === EscrowState.Disputed;

  if (isDisputed) {
    return (
      <div className="w-full bg-red-950/30 border border-red-800/60 rounded-xl p-4 sm:p-6 mb-8 text-center">
        <div className="inline-flex items-center gap-2 px-3 py-1 bg-red-900/60 text-red-300 rounded-full text-xs font-semibold mb-2">
          <span className="w-2 h-2 rounded-full bg-red-500 animate-ping" />
          Dispute Active
        </div>
        <h3 className="text-lg font-bold text-white">Under Arbitration</h3>
        <p className="text-xs sm:text-sm text-zinc-400 mt-1 max-w-md mx-auto">
          Funds are locked in arbitration. The assigned arbiter will review the terms and execute a split or refund.
        </p>
      </div>
    );
  }

  const activeIndex = currentState !== undefined ? currentState : 0;

  return (
    <div className="w-full bg-zinc-900/60 border border-zinc-800 rounded-xl p-4 sm:p-6 mb-8">
      <div className="grid grid-cols-2 md:grid-cols-4 gap-4 relative">
        {steps.map((step, idx) => {
          const isDone = activeIndex > step.id || activeIndex === EscrowState.Completed;
          const isCurrent = activeIndex === step.id && activeIndex !== EscrowState.Completed;

          return (
            <div key={step.id} className="flex flex-col items-center text-center relative z-10">
              <div
                className={`w-9 h-9 rounded-full flex items-center justify-center font-bold text-sm transition-all duration-300 ${
                  isDone
                    ? 'bg-emerald-600 text-white shadow-lg shadow-emerald-950'
                    : isCurrent
                    ? 'bg-indigo-600 text-white ring-4 ring-indigo-500/20 shadow-lg shadow-indigo-950'
                    : 'bg-zinc-800 text-zinc-500'
                }`}
              >
                {isDone ? '✓' : idx + 1}
              </div>
              <span
                className={`mt-2 text-xs font-semibold uppercase tracking-wider ${
                  isDone ? 'text-emerald-400' : isCurrent ? 'text-indigo-400' : 'text-zinc-500'
                }`}
              >
                {step.label}
              </span>
              <span className="text-[11px] text-zinc-400 mt-0.5 hidden sm:block">
                {step.desc}
              </span>
            </div>
          );
        })}
      </div>
    </div>
  );
}