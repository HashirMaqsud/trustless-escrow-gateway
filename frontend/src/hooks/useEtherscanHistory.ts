'use client';

import { useState, useEffect } from 'react';

export interface EscrowHistoryItem {
  hash: string;
  timestamp: number;
  from: string;
  value: string;
}

interface EtherscanTxResponse {
  hash?: string;
  transactionHash?: string;
  timeStamp: string;
  from: string;
  value: string;
}

export function useEtherscanHistory(escrowAddress: `0x${string}` | undefined) {
  const [history, setHistory] = useState<EscrowHistoryItem[]>([]);
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!escrowAddress) return;

    let isMounted = true;
    const fetchHistory = async () => {
      setIsLoading(true);
      setError(null);
      try {
        const res = await fetch(`/api/etherscan-history?address=${escrowAddress}`);
        
        if (!res.ok) {
          throw new Error(`API responded with status: ${res.status}`);
        }

        const data: { directTxs: EtherscanTxResponse[]; internalTxs: EtherscanTxResponse[] } = await res.json();

        if (isMounted) {
          const directTxs = Array.isArray(data.directTxs) ? data.directTxs : [];
          const internalTxs = Array.isArray(data.internalTxs) ? data.internalTxs : [];
          const combined = [...directTxs, ...internalTxs];

          const seen = new Set<string>();
          const mapped: EscrowHistoryItem[] = [];

          for (const tx of combined) {
            const txHash = tx.hash || tx.transactionHash;
            if (txHash && !seen.has(txHash.toLowerCase())) {
              seen.add(txHash.toLowerCase());
              mapped.push({
                hash: txHash,
                timestamp: Number(tx.timeStamp),
                from: tx.from,
                value: tx.value,
              });
            }
          }

          mapped.sort((a, b) => b.timestamp - a.timestamp);
          setHistory(mapped);
        }
      } catch (err: unknown) {
        if (isMounted) {
          setError(
            err instanceof Error ? err.message : 'Failed to fetch Etherscan history'
          );
        }
      } finally {
        if (isMounted) setIsLoading(false);
      }
    };

    fetchHistory();
    return () => {
      isMounted = false;
    };
  }, [escrowAddress]);

  return { history, isLoading, error };
}