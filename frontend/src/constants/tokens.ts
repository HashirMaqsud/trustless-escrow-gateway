export interface TokenInfo {
  symbol: string;
  name: string;
  address: `0x${string}`;
  decimals: number;
}

export const SUPPORTED_TOKENS: Record<number, TokenInfo[]> = {
  // Sepolia Testnet
  11155111: [
    {
      symbol: 'USDC',
      name: 'USD Coin (Sepolia)',
      address: '0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238',
      decimals: 6,
    },
    {
      symbol: 'LINK',
      name: 'Chainlink Token',
      address: '0x779877A7B0D9E8603169DdbD7836e478b4624789',
      decimals: 18,
    },
  ],
  // Ethereum Mainnet
  1: [
    {
      symbol: 'USDC',
      name: 'USD Coin',
      address: '0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48',
      decimals: 6,
    },
    {
      symbol: 'USDT',
      name: 'Tether USD',
      address: '0xdAC17F958D2ee523a2206206994597C13D831ec7',
      decimals: 6,
    },
    {
      symbol: 'DAI',
      name: 'Dai Stablecoin',
      address: '0x6B175474E89094C44Da98b954EedeAC495271d0F',
      decimals: 18,
    },
  ],
};