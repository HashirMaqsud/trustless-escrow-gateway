'use client';

import { useWriteContract, useWaitForTransactionReceipt } from 'wagmi';
import { parseEther } from 'viem';
import { ESCROW_FACTORY_ADDRESS, ESCROW_FACTORY_ABI } from '@/constants/contracts';

export interface CreateEscrowParams {
  freelancer: `0x${string}`;
  arbiter: `0x${string}`;
  depositAmount: string;
}

export function useCreateEscrow() {
  const { data: hash, isPending: isWritePending, error: writeError, writeContractAsync } = useWriteContract();

  const { isLoading: isConfirming, isSuccess: isConfirmed, error: receiptError } =
    useWaitForTransactionReceipt({
      hash,
    });

  const createEscrow = async ({ freelancer, arbiter, depositAmount }: CreateEscrowParams) => {
    return await writeContractAsync({
      address: ESCROW_FACTORY_ADDRESS,
      abi: ESCROW_FACTORY_ABI,
      functionName: 'createEscrow',
      args: [freelancer, arbiter],
      value: parseEther(depositAmount),
    });
  };

  return {
    createEscrow,
    txHash: hash,
    isLoading: isWritePending || isConfirming,
    isSuccess: isConfirmed,
    error: writeError || receiptError,
  };
}
