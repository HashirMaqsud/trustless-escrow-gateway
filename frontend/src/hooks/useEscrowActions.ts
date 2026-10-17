'use client';

import { useWriteContract, useWaitForTransactionReceipt } from 'wagmi';
import { zeroAddress } from 'viem';
import { ESCROW_ABI } from '@/constants/contracts';

const ERC20_ABI = [
  {
    name: 'approve',
    type: 'function',
    stateMutability: 'nonpayable',
    inputs: [
      { name: 'spender', type: 'address' },
      { name: 'amount', type: 'uint256' },
    ],
    outputs: [{ name: '', type: 'bool' }],
  },
] as const;

export function useEscrowActions(escrowAddress: `0x${string}`) {
  const { data: hash, isPending: isWritePending, error: writeError, writeContractAsync } = useWriteContract();

  const { isLoading: isConfirming, isSuccess: isConfirmed, error: receiptError } =
    useWaitForTransactionReceipt({
      hash,
    });

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

  const approveToken = async (tokenAddress: `0x${string}`, amount: bigint) => {
    // Include 1% protocol fee in approval
    const fee = (amount * BigInt(100)) / BigInt(10000);
    const totalRequired = amount + fee;

    return executeCall(() =>
      writeContractAsync({
        address: tokenAddress,
        abi: ERC20_ABI,
        functionName: 'approve',
        args: [escrowAddress, totalRequired],
      })
    );
  };

  const fundEscrow = async (amount: bigint, tokenAddress?: `0x${string}`) => {
    const isEth = !tokenAddress || tokenAddress === zeroAddress;
    // Escrow contract requires msg.value == AMOUNT + fee (fee = (AMOUNT * FEE_BPS) / 10000)
    const fee = (amount * BigInt(100)) / BigInt(10000);
    const totalDeposit = amount + fee;

    return executeCall(() =>
      writeContractAsync({
        address: escrowAddress,
        abi: ESCROW_ABI,
        functionName: 'fund',
        value: isEth ? totalDeposit : BigInt(0),
      })
    );
  };

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

  const releaseFunds = async () => {
    return executeCall(() =>
      writeContractAsync({
        address: escrowAddress,
        abi: ESCROW_ABI,
        functionName: 'releaseFunds',
      })
    );
  };

  const raiseDispute = async () => {
    return executeCall(() =>
      writeContractAsync({
        address: escrowAddress,
        abi: ESCROW_ABI,
        functionName: 'raiseDispute',
      })
    );
  };

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
    approveToken,
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
