import { NextRequest, NextResponse } from 'next/server';
import { createWalletClient, createPublicClient, http, isAddress, getAddress } from 'viem';
import { privateKeyToAccount } from 'viem/accounts';
import { sepolia } from 'viem/chains';

const ESCROW_RELAY_ABI = [
  {
    type: 'function',
    name: 'submitDeliverableWithSig',
    inputs: [
      { name: '_deliverableUrl', type: 'string' },
      { name: '_deadline', type: 'uint256' },
      { name: '_signature', type: 'bytes' },
    ],
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    name: 'resolveDisputeWithSig',
    inputs: [
      { name: '_clientRefund', type: 'uint256' },
      { name: '_freelancerPayout', type: 'uint256' },
      { name: '_deadline', type: 'uint256' },
      { name: '_signature', type: 'bytes' },
    ],
    outputs: [],
    stateMutability: 'nonpayable',
  },
] as const;

export async function POST(req: NextRequest) {
  try {
    const body = await req.json();
    const { action, escrowAddress, deadline, signature, deliverableUrl, clientRefund, freelancerPayout } = body;

    if (!escrowAddress || !isAddress(escrowAddress)) {
      return NextResponse.json({ error: 'Invalid escrow contract address' }, { status: 400 });
    }

    if (!signature || !deadline) {
      return NextResponse.json({ error: 'Missing cryptographic signature or deadline' }, { status: 400 });
    }

    const relayerKey = process.env.RELAYER_PRIVATE_KEY;
    if (!relayerKey) {
      return NextResponse.json({ error: 'Relayer private key is not configured on server' }, { status: 500 });
    }

    const formattedKey = relayerKey.startsWith('0x') ? (relayerKey as `0x${string}`) : (`0x${relayerKey}` as `0x${string}`);
    const account = privateKeyToAccount(formattedKey);
    const rpcUrl = process.env.NEXT_PUBLIC_SEPOLIA_RPC_URL || 'https://ethereum-sepolia-rpc.publicnode.com';

    const transport = http(rpcUrl);

    const publicClient = createPublicClient({
      chain: sepolia,
      transport,
    });

    const walletClient = createWalletClient({
      account,
      chain: sepolia,
      transport,
    });

    const targetEscrow = getAddress(escrowAddress);
    let txHash: `0x${string}`;

    if (action === 'submitDeliverable') {
      if (!deliverableUrl || typeof deliverableUrl !== 'string') {
        return NextResponse.json({ error: 'Deliverable URL is required' }, { status: 400 });
      }

      // Explicit gas limit (600,000) prevents EVM estimation failure on complex storage writes
      txHash = await walletClient.writeContract({
        address: targetEscrow,
        abi: ESCROW_RELAY_ABI,
        functionName: 'submitDeliverableWithSig',
        args: [deliverableUrl, BigInt(deadline), signature],
        gas: 600000n,
      });
    } else if (action === 'resolveDispute') {
      if (clientRefund === undefined || freelancerPayout === undefined) {
        return NextResponse.json({ error: 'Split allocations are required' }, { status: 400 });
      }

      txHash = await walletClient.writeContract({
        address: targetEscrow,
        abi: ESCROW_RELAY_ABI,
        functionName: 'resolveDisputeWithSig',
        args: [BigInt(clientRefund), BigInt(freelancerPayout), BigInt(deadline), signature],
        gas: 600000n,
      });
    } else {
      return NextResponse.json({ error: 'Unsupported relay action' }, { status: 400 });
    }

    const receipt = await publicClient.waitForTransactionReceipt({ hash: txHash });

    return NextResponse.json({
      success: true,
      txHash,
      blockNumber: receipt.blockNumber.toString(),
    });
  } catch (err: unknown) {
    const errorMessage = err instanceof Error ? err.message : 'Internal relayer execution failure';
    return NextResponse.json({ error: errorMessage }, { status: 500 });
  }
}
