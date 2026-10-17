'use client';

import { useReadContracts } from 'wagmi';
import { zeroAddress, formatUnits, formatEther } from 'viem';
import { SUPPORTED_TOKENS } from '@/constants/tokens';

const ERC20_METADATA_ABI = [
  {
    name: 'symbol',
    type: 'function',
    stateMutability: 'view',
    inputs: [],
    outputs: [{ name: '', type: 'string' }],
  },
  {
    name: 'decimals',
    type: 'function',
    stateMutability: 'view',
    inputs: [],
    outputs: [{ name: '', type: 'uint8' }],
  },
] as const;

export function useTokenMetadata(tokenAddress: `0x${string}` | undefined, chainId = 11155111) {
  const isEth = !tokenAddress || tokenAddress.toLowerCase() === zeroAddress.toLowerCase();

  // Check known token registry first for fast resolution
  const knownTokens = SUPPORTED_TOKENS[chainId] || [];
  const matchedToken = knownTokens.find(
    (t) => t.address.toLowerCase() === tokenAddress?.toLowerCase()
  );

  // Fallback to on-chain read for custom tokens
  const { data } = useReadContracts({
    contracts: [
      {
        address: tokenAddress,
        abi: ERC20_METADATA_ABI,
        functionName: 'symbol',
      },
      {
        address: tokenAddress,
        abi: ERC20_METADATA_ABI,
        functionName: 'decimals',
      },
    ],
    query: {
      enabled: !isEth && !matchedToken && !!tokenAddress,
    },
  });

  if (isEth) {
    return {
      symbol: 'ETH',
      decimals: 18,
      formatAmount: (rawAmount: bigint | undefined) =>
        rawAmount ? formatEther(rawAmount) : '0',
    };
  }

  const symbol = matchedToken?.symbol || (data?.[0]?.result as string) || 'Tokens';
  const decimals = matchedToken?.decimals ?? (data?.[1]?.result as number) ?? 18;

  return {
    symbol,
    decimals,
    formatAmount: (rawAmount: bigint | undefined) =>
      rawAmount ? formatUnits(rawAmount, decimals) : '0',
  };
}