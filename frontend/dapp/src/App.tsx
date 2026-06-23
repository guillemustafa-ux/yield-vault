import { useWallet } from "./hooks/useWallet";
import { useVault } from "./hooks/useVault";
import { ConnectWallet } from "./components/ConnectWallet";
import { NetworkBadge } from "./components/NetworkBadge";
import { VaultCard } from "./components/VaultCard";
import { NETWORKS } from "./lib/contract";

export default function App() {
  const wallet = useWallet();
  const vault = useVault(wallet.signer, wallet.account, wallet.chainId);

  const net = wallet.chainId ? NETWORKS[wallet.chainId] : null;

  async function switchToSepolia() {
    if (!window.ethereum) return;
    try {
      await window.ethereum.request({
        method: "wallet_switchEthereumChain",
        params: [{ chainId: "0xaa36a7" }],
      });
    } catch {
      // user rejected or chain not added
    }
  }

  return (
    <div className="min-h-screen bg-[#0b0e14] text-slate-100 flex flex-col">
      {/* ── Header ── */}
      <header className="border-b border-slate-800 px-6 py-4 flex items-center justify-between">
        <div className="flex items-center gap-3">
          <span className="text-xl font-bold tracking-tight">YieldVault</span>
          <span className="text-xs px-2 py-0.5 rounded-full bg-slate-800 text-slate-500 border border-slate-700 select-none">
            ERC-4626 · testnet
          </span>
        </div>
        <div className="flex items-center gap-3">
          <NetworkBadge chainId={wallet.chainId} onSwitch={switchToSepolia} />
          <ConnectWallet
            account={wallet.account}
            isConnecting={wallet.isConnecting}
            onConnect={wallet.connect}
            onDisconnect={wallet.disconnect}
          />
        </div>
      </header>

      {/* ── Main ── */}
      <main className="flex-1 flex flex-col items-center justify-center px-4 py-12 gap-8">
        {/* Hero */}
        <div className="text-center max-w-md">
          <h1 className="text-3xl font-bold mb-2 tracking-tight">
            Vault de rendimiento on-chain
          </h1>
          <p className="text-slate-400 text-sm leading-relaxed">
            Depositás{" "}
            <code className="text-blue-400 text-xs bg-blue-950/40 px-1 py-0.5 rounded">
              mUSDC
            </code>{" "}
            y recibís shares (ERC-4626). Cuando entra rendimiento, cada share vale
            más: quien depositó antes gana. Protegido contra el ataque de inflación
            con <em>virtual shares</em>.
          </p>
        </div>

        {/* Vault card */}
        <VaultCard
          account={wallet.account}
          chainId={wallet.chainId}
          vault={vault}
        />

        {/* Wallet error */}
        {wallet.error && (
          <p className="text-sm text-red-400 text-center max-w-sm">
            {wallet.error}
          </p>
        )}
      </main>

      {/* ── Footer ── */}
      <footer className="border-t border-slate-800 px-6 py-4 text-center text-xs text-slate-600">
        {net ? (
          <>
            <a
              href={`${net.explorer}/address/${net.vault}`}
              target="_blank"
              rel="noopener noreferrer"
              className="hover:text-slate-400 transition-colors"
            >
              Vault verificado en {net.name} →
            </a>
            <span className="mx-3 opacity-30">|</span>
          </>
        ) : null}
        <span>YieldVault — ERC-4626 con Solidity + Foundry · on-ramp a RWA (ERC-7540)</span>
      </footer>
    </div>
  );
}
