'use client';

import { EscrowState } from '@/constants/contracts';
import { Check, AlertTriangle, ShieldCheck } from 'lucide-react';

interface StateTimelineProps {
  currentState: EscrowState | undefined;
}

const steps = [
  { id: EscrowState.Pending, label: 'Pending Deposit' },
  { id: EscrowState.Funded, label: 'Funded' },
  { id: EscrowState.Delivered, label: 'Delivered' },
  { id: EscrowState.Completed, label: 'Settled' },
];

export function StateTimeline({ currentState }: StateTimelineProps) {
  const isDisputed = currentState === EscrowState.Disputed;

  if (isDisputed) {
    return (
      <div className="w-full bg-red-50 border border-red-200 rounded-xl px-4 py-3 mb-5 flex items-center justify-between shadow-xs">
        <div className="flex items-center gap-2">
          <AlertTriangle className="w-4 h-4 text-red-600" />
          <span className="text-xs font-bold text-red-900">Vault Under Arbitration</span>
        </div>
        <span className="text-[11px] text-red-700 font-medium">Awaiting arbiter settlement ruling</span>
      </div>
    );
  }

  const activeIndex = currentState !== undefined ? currentState : 0;

  return (
    <div className="w-full bg-white border border-slate-200 rounded-xl px-5 py-3.5 mb-5 shadow-xs">
      <div className="flex items-center justify-between gap-2">
        {steps.map((step, idx) => {
          const isDone = activeIndex > step.id || activeIndex === EscrowState.Completed;
          const isCurrent = activeIndex === step.id && activeIndex !== EscrowState.Completed;

          return (
            <div key={step.id} className="flex items-center gap-2 flex-1 last:flex-none">
              <div className="flex items-center gap-2">
                <div
                  className={`w-6 h-6 rounded-full flex items-center justify-center font-bold text-[11px] shrink-0 transition-all ${
                    isDone
                      ? 'bg-emerald-600 text-white'
                      : isCurrent
                      ? 'bg-red-600 text-white ring-3 ring-red-100'
                      : 'bg-slate-100 text-slate-400 border border-slate-200'
                  }`}
                >
                  {isDone ? <Check className="w-3 h-3" /> : idx + 1}
                </div>
                <span
                  className={`text-xs font-bold tracking-tight uppercase ${
                    isDone ? 'text-emerald-700' : isCurrent ? 'text-red-600' : 'text-slate-400'
                  }`}
                >
                  {step.label}
                </span>
              </div>
              {idx < steps.length - 1 && (
                <div className={`h-[2px] flex-1 mx-3 rounded ${isDone ? 'bg-emerald-400' : 'bg-slate-200'}`} />
              )}
            </div>
          );
        })}
      </div>
    </div>
  );
}
