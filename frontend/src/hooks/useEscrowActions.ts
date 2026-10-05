'use client';

import { useWriteContract, useWaitForTransactionReceipt } from 'wagmi';
import { ESCROW_ABI } from '@/constants/contracts';

export function useEscrowActions(escrowAddress: `0x${string}`) {
  const { data: hash, isPending: isWritePending, error: writeError, writeContractAsync } = useWriteContract();

  const { isLoading: isConfirming, isSuccess: isConfirmed, error: receiptError } =
    useWaitForTransactionReceipt({
      hash,
    });

  // Helper to prevent unhandled rejection overlays on user cancel
  const executeCall = async (fn: () => Promise<`0x${string}`>) => {
    try {
      return await fn();
    } catch (err: unknown) {
      const errorMsg = err instanceof Error ? err.message : String(err);
      if (errorMsg.includes('User rejected') || errorMsg.includes('User denied')) {
        console.warn('Transaction signature cancelled by user.');
        return null;
      }
      console.error('Contract execution error:', err);
      throw err;
    }
  };

  // 1. Client deposits agreed funds
  const fundEscrow = async (amountInWei: bigint) => {
    return executeCall(() =>
      writeContractAsync({
        address: escrowAddress,
        abi: ESCROW_ABI,
        functionName: 'fund',
        value: amountInWei,
      })
    );
  };

  // 2. Freelancer submits project URL
  const submitDeliverable = async (url: string) => {
    return executeCall(() =>
      writeContractAsync({
        address: escrowAddress,
        abi: ESCROW_ABI,
        functionName: 'submitDeliverable',
        args: [url],
      })
    );
  };

  // 3. Client approves and releases payment
  const releaseFunds = async () => {
    return executeCall(() =>
      writeContractAsync({
        address: escrowAddress,
        abi: ESCROW_ABI,
        functionName: 'releaseFunds',
      })
    );
  };

  // 4. Client or Freelancer raises dispute
  const raiseDispute = async () => {
    return executeCall(() =>
      writeContractAsync({
        address: escrowAddress,
        abi: ESCROW_ABI,
        functionName: 'raiseDispute',
      })
    );
  };

  // 5. Arbiter resolves dispute with payout split
  const resolveDispute = async (clientRefund: bigint, freelancerPayout: bigint) => {
    return executeCall(() =>
      writeContractAsync({
        address: escrowAddress,
        abi: ESCROW_ABI,
        functionName: 'resolveDispute',
        args: [clientRefund, freelancerPayout],
      })
    );
  };

  return {
    fundEscrow,
    submitDeliverable,
    releaseFunds,
    raiseDispute,
    resolveDispute,
    txHash: hash,
    isLoading: isWritePending || isConfirming,
    isSuccess: isConfirmed,
    error: writeError || receiptError,
  };
}