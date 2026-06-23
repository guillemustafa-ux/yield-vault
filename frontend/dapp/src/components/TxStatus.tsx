import type { TxStatus as TxStatusType } from "../hooks/useVault";
import { NETWORKS } from "../lib/contract";

interface Props {
  status: TxStatusType;
  txHash: string | null;
  txError: string | null;
  chainId: number | null;
  onDismiss: () => void;
}

export function TxStatus({ status, txHash, txError, chainId, onDismiss }: Props) {
  if (status === "idle") return null;

  const net = chainId ? NETWORKS[chainId] : null;

  const styles: Record<Exclude<TxStatusType, "idle">, string> = {
    pending: "bg-blue-950/60 border-blue-800 text-blue-300",
    confirmed: "bg-green-950/60 border-green-800 text-green-300",
    error: "bg-red-950/60 border-red-800 text-red-300",
  };

  const key = status as Exclude<TxStatusType, "idle">;

  return (
    <div
      className={`mt-4 p-3 rounded-xl text-sm flex items-start gap-2 border ${styles[key]}`}
    >
      {status === "pending" && (
        <svg
          className="size-4 animate-spin shrink-0 mt-0.5"
          viewBox="0 0 24 24"
          fill="none"
          aria-hidden="true"
        >
          <circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4" />
          <path className="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4z" />
        </svg>
      )}
      {status === "confirmed" && <span className="shrink-0 mt-0.5">✅</span>}
      {status === "error" && <span className="shrink-0 mt-0.5">❌</span>}

      <div className="flex-1 min-w-0 break-words">
        {status === "pending" && "Esperando confirmación…"}
        {status === "confirmed" && (
          <>
            Confirmado.{" "}
            {txHash && net && (
              <a
                href={`${net.explorer}/tx/${txHash}`}
                target="_blank"
                rel="noopener noreferrer"
                className="underline underline-offset-2 hover:opacity-80"
              >
                Ver en {net.name}
              </a>
            )}
          </>
        )}
        {status === "error" && txError}
      </div>

      <button
        onClick={onDismiss}
        aria-label="Cerrar"
        className="shrink-0 opacity-60 hover:opacity-100 transition-opacity text-lg leading-none cursor-pointer"
      >
        ×
      </button>
    </div>
  );
}
