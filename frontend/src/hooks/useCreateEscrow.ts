'use client';

import { useMemo } from 'react';
import { useWriteContract, useWaitForTransactionReceipt } from 'wagmi';
import { parseEther, zeroAddress, parseEventLogs } from 'viem';
import { ESCROW_FACTORY_ADDRESS, ESCROW_FACTORY_ABI } from '@/constants/contracts';

export interface CreateEscrowParams {
  freelancer: `0x${string}`;
  arbiter: `0x${string}`;
  depositAmount: string;
}

export function useCreateEscrow() {
  const { data: hash, isPending: isWritePending, error: writeError, writeContractAsync } = useWriteContract();

  const { data: receipt, isLoading: isConfirming, isSuccess: isConfirmed, error: receiptError } =
    useWaitForTransactionReceipt({
      hash,
    });

  const deployedAddress = useMemo(() => {
    if (!receipt?.logs) return undefined;
    try {
      const logs = parseEventLogs({
        abi: ESCROW_FACTORY_ABI,
        logs: receipt.logs,
        eventName: 'EscrowCreated',
      }) as unknown as Array<{ args: { escrowAddress: `0x${string}` } }>;

      return logs?.[0]?.args?.escrowAddress;
    } catch {
      return undefined;
    }
  }, [receipt]);

  const createEscrow = async ({ freelancer, arbiter, depositAmount }: CreateEscrowParams) => {
    return await writeContractAsync({
      address: ESCROW_FACTORY_ADDRESS,
      abi: ESCROW_FACTORY_ABI,
      functionName: 'createEscrow',
      args: [
        freelancer,
        arbiter,
        zeroAddress,
        parseEther(depositAmount),
      ],
    });
  };

  return {
    createEscrow,
    txHash: hash,
    deployedAddress,
    isLoading: isWritePending || isConfirming,
    isSuccess: isConfirmed,
    error: writeError || receiptError,
  };
}