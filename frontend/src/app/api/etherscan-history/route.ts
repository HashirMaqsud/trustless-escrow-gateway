import { NextRequest, NextResponse } from 'next/server';

export async function GET(req: NextRequest) {
  const { searchParams } = new URL(req.url);
  const address = searchParams.get('address');

  if (!address) {
    return NextResponse.json({ error: 'Address is required' }, { status: 400 });
  }

  const apiKey =
    process.env.NEXT_PUBLIC_ETHERSCAN_API_KEY ||
    process.env.ETHERSCAN_API_KEY ||
    '';

  const base = 'https://api.etherscan.io/v2/api?chainid=11155111';

  try {
    const txUrl = `${base}&module=account&action=txlist&address=${address}&startblock=0&endblock=99999999&page=1&offset=15&sort=desc${
      apiKey ? `&apikey=${apiKey}` : ''
    }`;

    const internalUrl = `${base}&module=account&action=txlistinternal&address=${address}&startblock=0&endblock=99999999&page=1&offset=15&sort=desc${
      apiKey ? `&apikey=${apiKey}` : ''
    }`;

    const [txRes, internalRes] = await Promise.all([
      fetch(txUrl, { cache: 'no-store' })
        .then((r) => r.json())
        .catch(() => null),
      fetch(internalUrl, { cache: 'no-store' })
        .then((r) => r.json())
        .catch(() => null),
    ]);

    const directTxs = txRes?.status === '1' && Array.isArray(txRes.result) ? txRes.result : [];
    const internalTxs = internalRes?.status === '1' && Array.isArray(internalRes.result) ? internalRes.result : [];

    return NextResponse.json({ directTxs, internalTxs });
  } catch (error: unknown) {
    return NextResponse.json(
      { error: error instanceof Error ? error.message : 'Server error fetching Etherscan' },
      { status: 500 }
    );
  }
}