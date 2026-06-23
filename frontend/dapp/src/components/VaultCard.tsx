import { useState } from "react";
import type { ReactNode } from "react";
import { ethers } from "ethers";
import { NETWORKS, fmtUnits } from "../lib/contract";
import type { VaultState } from "../hooks/useVault";
import { TxStatus } from "./TxStatus";

interface Props {
  account: string | null;
  chainId: number | null;
  vault: VaultState;
}

const FAUCET_AMOUNT = "1000"; // mUSDC que entrega el faucet de prueba

export function VaultCard({ account, chainId, vault }: Props) {
  const {
    symbol,
    assetDecimals,
    assetBalance,
    shares,
    sharesValue,
    sharePrice,
    totalAssets,
    capRemaining,
    allowance,
    isLoading,
    txStatus,
    txHash,
    txError,
    doFaucet,
    doApprove,
    doDeposit,
    doRedeemAll,
    resetTx,
  } = vault;

  const [amountStr, setAmountStr] = useState("");

  const isTxBusy = txStatus === "pending";
  const isUnsupported =
    account !== null && chainId !== null && !NETWORKS[chainId];

  // Parseo seguro del monto a depositar.
  let amount = 0n;
  let amountValid = false;
  try {
    if (amountStr.trim() !== "") {
      amount = ethers.parseUnits(amountStr.trim(), assetDecimals);
      amountValid = amount > 0n;
    }
  } catch {
    amountValid = false;
  }

  const needsApproval = amountValid && allowance < amount;
  const hasShares = shares > 0n;

  return (
    <div className="w-full max-w-md bg-slate-900 border border-slate-800 rounded-2xl p-7 shadow-2xl">
      {!account ? (
        <p className="text-center text-slate-400 py-8">
          Conectá tu wallet para empezar
        </p>
      ) : isUnsupported ? (
        <p className="text-center text-yellow-400 py-8">
          Red no soportada — cambiá a Sepolia
        </p>
      ) : (
        <>
          {/* Métricas del vault */}
          <div className="border border-slate-800 rounded-xl overflow-hidden mb-5 text-sm">
            <InfoRow label="Precio del share">
              {sharePrice > 0n
                ? `${fmtUnits(sharePrice, assetDecimals, 6)} ${symbol}`
                : "—"}
            </InfoRow>
            <InfoRow label="TVL del vault">
              {`${fmtUnits(totalAssets, assetDecimals)} ${symbol}`}
            </InfoRow>
            <InfoRow label={`Tu balance ${symbol}`}>
              {fmtUnits(assetBalance, assetDecimals)}
            </InfoRow>
            <InfoRow label="Tus shares (valor)" last>
              {hasShares
                ? `${fmtUnits(sharesValue, assetDecimals)} ${symbol}`
                : "—"}
            </InfoRow>
          </div>

          {/* Faucet */}
          <button
            onClick={() => doFaucet(ethers.parseUnits(FAUCET_AMOUNT, assetDecimals))}
            disabled={isTxBusy}
            className="w-full py-2 mb-4 rounded-xl border border-slate-700 text-slate-300 text-sm hover:border-slate-500 hover:text-white disabled:opacity-40 disabled:cursor-not-allowed transition-colors cursor-pointer"
          >
            🚰 Faucet: conseguir {FAUCET_AMOUNT} {symbol} de prueba
          </button>

          {/* Depositar */}
          <div className="flex gap-2 mb-3">
            <input
              type="number"
              min="0"
              placeholder={`Monto en ${symbol}`}
              value={amountStr}
              onChange={(e) => setAmountStr(e.target.value)}
              className="flex-1 min-w-0 px-3 py-3 rounded-xl bg-slate-800 border border-slate-700 text-slate-100 text-sm focus:outline-none focus:border-blue-600"
            />
            <button
              onClick={() => setAmountStr(fmtUnits(assetBalance, assetDecimals))}
              className="px-3 rounded-xl border border-slate-700 text-slate-400 text-xs hover:text-white hover:border-slate-500 transition-colors cursor-pointer shrink-0"
            >
              MAX
            </button>
          </div>

          {needsApproval ? (
            <button
              onClick={() => doApprove(amount)}
              disabled={isTxBusy || !amountValid}
              className="w-full py-3 rounded-xl bg-amber-600 hover:bg-amber-500 active:bg-amber-700 disabled:opacity-40 disabled:cursor-not-allowed text-white font-semibold transition-colors cursor-pointer"
            >
              {isTxBusy ? "Procesando…" : `1/2 · Aprobar ${symbol}`}
            </button>
          ) : (
            <button
              onClick={() => doDeposit(amount)}
              disabled={isTxBusy || isLoading || !amountValid}
              className="w-full py-3 rounded-xl bg-blue-600 hover:bg-blue-500 active:bg-blue-700 disabled:opacity-40 disabled:cursor-not-allowed text-white font-semibold transition-colors cursor-pointer"
            >
              {isTxBusy ? "Procesando…" : "Depositar"}
            </button>
          )}

          {/* Retirar todo */}
          {hasShares && (
            <button
              onClick={doRedeemAll}
              disabled={isTxBusy}
              className="w-full mt-3 py-2.5 rounded-xl border border-slate-700 text-slate-300 text-sm hover:border-slate-500 hover:text-white disabled:opacity-40 disabled:cursor-not-allowed transition-colors cursor-pointer"
            >
              Retirar todo (redeem)
            </button>
          )}

          {capRemaining === 0n && (
            <p className="text-xs text-yellow-500/80 text-center mt-3">
              Cupo del vault completo — no se aceptan más depósitos.
            </p>
          )}

          <TxStatus
            status={txStatus}
            txHash={txHash}
            txError={txError}
            chainId={chainId}
            onDismiss={resetTx}
          />
        </>
      )}
    </div>
  );
}

function InfoRow({
  label,
  children,
  last,
}: {
  label: string;
  children: ReactNode;
  last?: boolean;
}) {
  return (
    <div
      className={`flex justify-between items-center px-4 py-3 bg-slate-800/40 ${
        last ? "" : "border-b border-slate-800"
      }`}
    >
      <span className="text-slate-400">{label}</span>
      <code className="text-slate-100 font-mono text-xs">{children}</code>
    </div>
  );
}
