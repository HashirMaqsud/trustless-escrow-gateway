'use client';

import { useReadContracts } from 'wagmi';
import { ESCROW_ABI, EscrowState } from '@/constants/contracts';

export function useEscrowState(escrowAddress: `0x${string}` | undefined) {
  const contract = {
    address: escrowAddress,
    abi: ESCROW_ABI,
  } as const;

  const { data, isLoading, error, refetch } = useReadContracts({
    contracts: [
      { ...contract, functionName: 'CLIENT' },
      { ...contract, functionName: 'FREELANCER' },
      { ...contract, functionName: 'ARBITER' },
      { ...contract, functionName: 'TOKEN' },
      { ...contract, functionName: 'AMOUNT' },
      { ...contract, functionName: 'currentState' },
      { ...contract, functionName: 'deliverableUrl' },
    ],
    query: {
      enabled: !!escrowAddress && escrowAddress.startsWith('0x'),
      refetchInterval: 4000, // Poll state every 4s for real-time transitions
    },
  });

  const client = data?.[0]?.result as `0x${string}` | undefined;
  const freelancer = data?.[1]?.result as `0x${string}` | undefined;
  const arbiter = data?.[2]?.result as `0x${string}` | undefined;
  const token = data?.[3]?.result as `0x${string}` | undefined;
  const amount = data?.[4]?.result as bigint | undefined;
  const currentState = data?.[5]?.result as EscrowState | undefined;
  const deliverableUrl = data?.[6]?.result as string | undefined;

  return {
    client,
    freelancer,
    arbiter,
    token,
    amount,
    currentState,
    deliverableUrl,
    isLoading,
    error,
    refetch,
  };
}