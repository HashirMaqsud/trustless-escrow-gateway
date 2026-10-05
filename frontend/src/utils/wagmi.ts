import { getDefaultConfig } from '@rainbow-me/rainbowkit';
import { sepolia } from 'wagmi/chains';
import { http, fallback } from 'viem';

const projectId = process.env.NEXT_PUBLIC_WALLETCONNECT_PROJECT_ID || '841954456e7a91cb59147dd04ecc5685';

export const config = getDefaultConfig({
  appName: 'Trustless Escrow Gateway',
  projectId,
  chains: [sepolia],
  transports: {
    [sepolia.id]: fallback([
      http(process.env.NEXT_PUBLIC_SEPOLIA_RPC_URL),
      http('https://rpc.sepolia.org'),
      http('https://sepolia.gateway.tenderly.co'),
      http('https://rpc2.sepolia.org'),
      http('https://ethereum-sepolia-rpc.publicnode.com'),
    ]),
  },
  ssr: true,
});