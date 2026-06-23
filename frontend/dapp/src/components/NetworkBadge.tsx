import { NETWORKS } from "../lib/contract";

interface Props {
  chainId: number | null;
  onSwitch: () => void;
}

export function NetworkBadge({ chainId, onSwitch }: Props) {
  if (!chainId) return null;

  const net = NETWORKS[chainId];
  if (net) {
    return (
      <span className="px-2.5 py-1 rounded-full text-xs font-medium bg-slate-800 text-slate-400 border border-slate-700 select-none">
        {net.name}
      </span>
    );
  }

  return (
    <button
      onClick={onSwitch}
      className="px-2.5 py-1 rounded-full text-xs font-medium bg-yellow-950/60 text-yellow-400 border border-yellow-800 hover:bg-yellow-950 transition-colors cursor-pointer"
    >
      Red no soportada — cambiar a Sepolia
    </button>
  );
}
