'use client';

import { useMemo } from 'react';
import { useWriteContract, useWaitForTransactionReceipt } from 'wagmi';
import { parseUnits, zeroAddress, decodeEventLog } from 'viem';
import { ESCROW_FACTORY_ADDRESS, ESCROW_FACTORY_ABI } from '@/constants/contracts';

export interface CreateEscrowParams {
  freelancer: `0x${string}`;
  arbiter: `0x${string}`;
  depositAmount: string;
  token?: `0x${string}`;
  decimals?: number;
}

export function useCreateEscrow() {
  const { data: hash, isPending: isWritePending, error: writeError, writeContractAsync } = useWriteContract();

  const { data: receipt, isLoading: isConfirming, isSuccess: isConfirmed, error: receiptError } =
    useWaitForTransactionReceipt({
      hash,
    });

  const deployedAddress = useMemo(() => {
    if (!receipt?.logs || receipt.logs.length === 0) return undefined;

    // 1. Try decoding EscrowCreated event
    for (const log of receipt.logs) {
      try {
        const decoded = decodeEventLog({
          abi: ESCROW_FACTORY_ABI,
          data: log.data,
          topics: log.topics,
        });

        if (decoded.eventName === 'EscrowCreated') {
          const args = decoded.args as { escrowAddress?: `0x${string}` };
          if (args.escrowAddress) {
            return args.escrowAddress;
          }
        }
      } catch {
        // Continue scanning logs
      }
    }

    // 2. Fallback: EscrowCreated has topic0 as event hash, and first indexed topic is escrowAddress
    for (const log of receipt.logs) {
      if (log.address.toLowerCase() === ESCROW_FACTORY_ADDRESS.toLowerCase() && log.topics && log.topics.length > 1) {
        // topic[1] is indexed escrowAddress
        const rawAddr = log.topics[1];
        if (rawAddr && rawAddr.length === 66) {
          return `0x${rawAddr.slice(26)}` as `0x${string}`;
        }
      }
    }

    return undefined;
  }, [receipt]);

  const createEscrow = async ({
    freelancer,
    arbiter,
    depositAmount,
    token,
    decimals = 18,
  }: CreateEscrowParams) => {
    const isNativeEth = !token || token.toLowerCase() === zeroAddress.toLowerCase();
    const tokenDecimals = isNativeEth ? 18 : decimals;
    const rawAmount = parseUnits(depositAmount, tokenDecimals);

    return await writeContractAsync({
      address: ESCROW_FACTORY_ADDRESS,
      abi: ESCROW_FACTORY_ABI,
      functionName: 'createEscrow',
      args: [
        freelancer,
        arbiter,
        token || zeroAddress,
        rawAmount,
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
