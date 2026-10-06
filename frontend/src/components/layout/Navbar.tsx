'use client';

import React from 'react';
import Link from 'next/link';
import { ConnectButton } from '@rainbow-me/rainbowkit';
import { ShieldCheck, PlusCircle, LayoutDashboard } from 'lucide-react';

export const Navbar = () => {
  return (
    <header className="sticky top-0 z-50 w-full border-b border-zinc-800 bg-zinc-950/80 backdrop-blur">
      <div className="mx-auto flex h-16 max-w-7xl items-center justify-between px-4 sm:px-6 lg:px-8">
        
        {/* Brand Logo & Routes */}
        <div className="flex items-center gap-6">
          <Link href="/" className="flex items-center gap-3 transition-opacity hover:opacity-90">
            <div className="flex h-10 w-10 items-center justify-center rounded-lg bg-indigo-600/20 text-indigo-400 border border-indigo-500/30">
              <ShieldCheck className="h-6 w-6" />
            </div>
            <div>
              <span className="text-lg font-bold tracking-tight text-white">Trustless Escrow</span>
              <span className="block text-xs text-zinc-400 font-mono">Sepolia Testnet</span>
            </div>
          </Link>

          {/* Navigation Route Links */}
          <nav className="hidden sm:flex items-center gap-2 pl-4 border-l border-zinc-800">
            <Link
              href="/"
              className="flex items-center gap-1.5 px-3 py-1.5 rounded-lg text-xs font-medium text-zinc-300 hover:text-white hover:bg-zinc-900 transition"
            >
              <PlusCircle className="w-3.5 h-3.5 text-zinc-400" />
              Create Escrow
            </Link>
            <Link
              href="/dashboard"
              className="flex items-center gap-1.5 px-3 py-1.5 rounded-lg text-xs font-medium text-zinc-300 hover:text-white hover:bg-zinc-900 transition"
            >
              <LayoutDashboard className="w-3.5 h-3.5 text-zinc-400" />
              Dashboard
            </Link>
          </nav>
        </div>

        {/* Web3 Wallet Connect */}
        <div className="flex items-center gap-4">
          <ConnectButton
            showBalance={false}
            chainStatus="icon"
            accountStatus={{
              smallScreen: 'avatar',
              largeScreen: 'full',
            }}
          />
        </div>
      </div>
    </header>
  );
};