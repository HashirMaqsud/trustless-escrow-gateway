import { CreateEscrowForm } from '@/components/escrow/CreateEscrowForm';

export default function Home() {
  return (
    <div className="flex flex-col items-center justify-center py-6 sm:py-12">
      <div className="text-center max-w-2xl mx-auto mb-10">
        <h1 className="text-3xl sm:text-4xl font-extrabold tracking-tight text-white">
          Milestone Payments, <span className="text-indigo-400">Zero Trust Required</span>
        </h1>
        <p className="mt-3 text-zinc-400 text-sm sm:text-base leading-relaxed">
          Create cryptographic escrows on Ethereum Sepolia. Funds remain locked until the client approves the verified deliverable, with neutral arbiters resolving disputes.
        </p>
      </div>

      <CreateEscrowForm />
    </div>
  );
}