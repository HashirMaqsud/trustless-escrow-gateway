'use client';

import { useState } from 'react';
import { useSignTypedData, useAccount, useChainId } from 'wagmi';

// EIP-712 Domain and Type definitions matching Escrow.sol
const EIP712_TYPES = {
  SubmitDeliverable: [
    { name: 'freelancer', type: 'address' },
    { name: 'deliverableUrl', type: 'string' },
    { name: 'nonce', type: 'uint256' },
    { name: 'deadline', type: 'uint256' },
  ],
} as const;

interface GaslessDeliverableParams {
  escrowAddress: `0x${string}`;
  deliverableUrl: string;
  nonce: bigint;
}

export function useGaslessDeliverable() {
  const { address } = useAccount();
  const chainId = useChainId();
  const { signTypedDataAsync } = useSignTypedData();

  const [isLoading, setIsLoading] = useState(false);
  const [txHash, setTxHash] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  const submitGaslessDeliverable = async ({
    escrowAddress,
    deliverableUrl,
    nonce,
  }: GaslessDeliverableParams) => {
    setIsLoading(true);
    setError(null);
    setTxHash(null);

    try {
      if (!address) {
        throw new Error('Wallet not connected');
      }

      // Set signature validity window (1 hour from current timestamp)
      const deadline = BigInt(Math.floor(Date.now() / 1000) + 3600);

      // Request cryptographic signature via EIP-712
      const signature = await signTypedDataAsync({
        domain: {
          name: 'TrustlessEscrow',
          version: '1',
          chainId,
          verifyingContract: escrowAddress,
        },
        types: EIP712_TYPES,
        primaryType: 'SubmitDeliverable',
        message: {
          freelancer: address,
          deliverableUrl,
          nonce,
          deadline,
        },
      });

      // Transmit signed payload to backend relayer route
      const response = await fetch('/api/relay', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          action: 'submitDeliverable',
          escrowAddress,
          deliverableUrl,
          deadline: deadline.toString(),
          signature,
        }),
      });

      const data = await response.json();

      if (!response.ok || !data.success) {
        throw new Error(data.error || 'Relayer submission rejected');
      }

      setTxHash(data.txHash);
      return data.txHash;
    } catch (err: unknown) {
      const msg = err instanceof Error ? err.message : 'Meta-transaction dispatch failed';
      setError(msg);
      throw err;
    } finally {
      setIsLoading(false);
    }
  };

  return {
    submitGaslessDeliverable,
    isLoading,
    txHash,
    error,
  };
}