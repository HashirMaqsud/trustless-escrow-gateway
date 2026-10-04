import EscrowFactoryABI from './abis/EscrowFactory.json';
import EscrowABI from './abis/Escrow.json';

export const ESCROW_FACTORY_ADDRESS = (process.env.NEXT_PUBLIC_ESCROW_FACTORY_ADDRESS ||
  '0x9954a01DAf26E1BE24593449E6b8F09cA47c247c') as `0x${string}`;

export const ESCROW_FACTORY_ABI = EscrowFactoryABI;
export const ESCROW_ABI = EscrowABI;

export enum EscrowState {
  Pending = 0,
  Funded = 1,
  Delivered = 2,
  Completed = 3,
  Disputed = 4,
}