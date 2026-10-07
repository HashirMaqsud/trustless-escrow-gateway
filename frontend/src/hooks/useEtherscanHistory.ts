'use client';

import { useState, useEffect } from 'react';

export interface EscrowHistoryItem {
  hash: string;
  timestamp: number;
  from: string;
  value: string;
}

interface EtherscanTxResponse {
  hash: string;
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
        const apiKey = process.env.NEXT_PUBLIC_ETHERSCAN_API_KEY || '';
        const url = `https://api-sepolia.etherscan.io/api?module=account&action=txlist&address=${escrowAddress}&startblock=0&endblock=99999999&page=1&offset=10&sort=asc${
          apiKey ? `&apikey=${apiKey}` : ''
        }`;

        const res = await fetch(url);
        const data = (await res.json()) as { status: string; result: EtherscanTxResponse[] };

        if (isMounted) {
          if (data.status === '1' && Array.isArray(data.result)) {
            const mapped: EscrowHistoryItem[] = data.result.map((tx) => ({
              hash: tx.hash,
              timestamp: Number(tx.timeStamp),
              from: tx.from,
              value: tx.value,
            }));
            setHistory(mapped);
          } else {
            setHistory([]);
          }
        }
      } catch (err: unknown) {
        if (isMounted) {
          setError(err instanceof Error ? err.message : 'Failed to fetch Etherscan history');
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