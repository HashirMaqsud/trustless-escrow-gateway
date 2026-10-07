export interface EscrowMetadata {
  title?: string;
  description?: string;
}

const METADATA_KEY = 'trustless_escrow_metadata';
const HIDDEN_KEY = 'trustless_escrow_hidden';

// 1. Metadata Read/Write
export const getAllEscrowMetadata = (): Record<string, EscrowMetadata> => {
  if (typeof window === 'undefined') return {};
  try {
    const raw = localStorage.getItem(METADATA_KEY);
    return raw ? JSON.parse(raw) : {};
  } catch {
    return {};
  }
};

export const getEscrowMetadata = (address: string): EscrowMetadata => {
  if (!address) return {};
  const all = getAllEscrowMetadata();
  return all[address.toLowerCase()] || {};
};

export const setEscrowMetadata = (address: string, data: Partial<EscrowMetadata>) => {
  if (typeof window === 'undefined' || !address) return;
  try {
    const all = getAllEscrowMetadata();
    const cleanAddr = address.toLowerCase();
    all[cleanAddr] = { ...all[cleanAddr], ...data };
    localStorage.setItem(METADATA_KEY, JSON.stringify(all));
  } catch (err) {
    console.error('Failed to save metadata:', err);
  }
};

// 2. Hidden/Archived Escrows Read/Write
export const getHiddenEscrows = (): string[] => {
  if (typeof window === 'undefined') return [];
  try {
    const raw = localStorage.getItem(HIDDEN_KEY);
    return raw ? JSON.parse(raw) : [];
  } catch {
    return [];
  }
};

export const isEscrowHidden = (address: string): boolean => {
  if (!address) return false;
  const hidden = getHiddenEscrows();
  return hidden.includes(address.toLowerCase());
};

export const toggleHideEscrow = (address: string): boolean => {
  if (typeof window === 'undefined' || !address) return false;
  try {
    const hidden = getHiddenEscrows();
    const cleanAddr = address.toLowerCase();
    const exists = hidden.includes(cleanAddr);
    const updated = exists ? hidden.filter((a) => a !== cleanAddr) : [...hidden, cleanAddr];
    localStorage.setItem(HIDDEN_KEY, JSON.stringify(updated));
    return !exists; // true if hidden now, false if unhidden
  } catch {
    return false;
  }
};