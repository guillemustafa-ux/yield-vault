import { useState, useEffect, useCallback } from "react";
import { ethers } from "ethers";
import { NETWORKS, getVault, getAsset } from "../lib/contract";

export type TxStatus = "idle" | "pending" | "confirmed" | "error";

export interface VaultState {
  symbol: string;
  assetDecimals: number;
  shareDecimals: number;
  assetBalance: bigint; // mUSDC del usuario
  shares: bigint; // shares del vault del usuario
  sharesValue: bigint; // cuánto valen esas shares en assets (convertToAssets)
  sharePrice: bigint; // assets por 1 share entera (en unidades de asset)
  totalAssets: bigint; // TVL del vault
  capRemaining: bigint; // cuánto más se puede depositar (maxDeposit)
  allowance: bigint; // allowance asset→vault del usuario
  isLoading: boolean;
  txStatus: TxStatus;
  txHash: string | null;
  txError: string | null;
  doFaucet: (amount: bigint) => Promise<void>;
  doApprove: (amount: bigint) => Promise<void>;
  doDeposit: (amount: bigint) => Promise<void>;
  doRedeemAll: () => Promise<void>;
  resetTx: () => void;
}

export function useVault(
  signer: ethers.JsonRpcSigner | null,
  account: string | null,
  chainId: number | null
): VaultState {
  const [symbol, setSymbol] = useState("mUSDC");
  const [assetDecimals, setAssetDecimals] = useState(6);
  const [shareDecimals, setShareDecimals] = useState(12);
  const [assetBalance, setAssetBalance] = useState<bigint>(0n);
  const [shares, setShares] = useState<bigint>(0n);
  const [sharesValue, setSharesValue] = useState<bigint>(0n);
  const [sharePrice, setSharePrice] = useState<bigint>(0n);
  const [totalAssets, setTotalAssets] = useState<bigint>(0n);
  const [capRemaining, setCapRemaining] = useState<bigint>(0n);
  const [allowance, setAllowance] = useState<bigint>(0n);
  const [isLoading, setIsLoading] = useState(false);
  const [txStatus, setTxStatus] = useState<TxStatus>("idle");
  const [txHash, setTxHash] = useState<string | null>(null);
  const [txError, setTxError] = useState<string | null>(null);

  const refresh = useCallback(async () => {
    if (!signer || !account || !chainId) return;
    const net = NETWORKS[chainId];
    if (!net) return;
    try {
      setIsLoading(true);
      const vault = getVault(net.vault, signer);
      const asset = getAsset(net.asset, signer);

      const [sym, aDec, sDec] = await Promise.all([
        asset.symbol(),
        asset.decimals(),
        vault.decimals(),
      ]);
      setSymbol(sym);
      setAssetDecimals(Number(aDec));
      setShareDecimals(Number(sDec));

      const oneShare = 10n ** BigInt(Number(sDec));
      const [bal, sh, tA, cap, allow] = await Promise.all([
        asset.balanceOf(account),
        vault.balanceOf(account),
        vault.totalAssets(),
        vault.maxDeposit(account),
        asset.allowance(account, net.vault),
      ]);
      setAssetBalance(bal);
      setShares(sh);
      setTotalAssets(tA);
      setCapRemaining(cap);
      setAllowance(allow);

      const [shVal, price] = await Promise.all([
        vault.convertToAssets(sh),
        vault.convertToAssets(oneShare),
      ]);
      setSharesValue(shVal);
      setSharePrice(price);
    } catch {
      // lecturas con error no son fatales para la UI
    } finally {
      setIsLoading(false);
    }
  }, [signer, account, chainId]);

  useEffect(() => {
    refresh();
  }, [refresh]);

  const sendTx = useCallback(
    async (fn: () => Promise<ethers.TransactionResponse>) => {
      try {
        setTxStatus("pending");
        setTxError(null);
        setTxHash(null);
        const tx = await fn();
        setTxHash(tx.hash);
        await tx.wait();
        setTxStatus("confirmed");
        await refresh();
      } catch (e: unknown) {
        setTxStatus("error");
        const err = e as { shortMessage?: string; message?: string };
        setTxError(err.shortMessage ?? err.message ?? "Error en la transacción");
      }
    },
    [refresh]
  );

  const withVaultAsset = (chain: number) => {
    const net = NETWORKS[chain];
    return net ? { net } : null;
  };

  const doFaucet = useCallback(
    async (amount: bigint) => {
      if (!signer || !chainId || !account) return;
      const ctx = withVaultAsset(chainId);
      if (!ctx) return;
      const asset = getAsset(ctx.net.asset, signer);
      await sendTx(
        () => asset.mint(account, amount) as Promise<ethers.TransactionResponse>
      );
    },
    [signer, chainId, account, sendTx]
  );

  const doApprove = useCallback(
    async (amount: bigint) => {
      if (!signer || !chainId) return;
      const ctx = withVaultAsset(chainId);
      if (!ctx) return;
      const asset = getAsset(ctx.net.asset, signer);
      await sendTx(
        () =>
          asset.approve(ctx.net.vault, amount) as Promise<ethers.TransactionResponse>
      );
    },
    [signer, chainId, sendTx]
  );

  const doDeposit = useCallback(
    async (amount: bigint) => {
      if (!signer || !chainId || !account) return;
      const ctx = withVaultAsset(chainId);
      if (!ctx) return;
      const vault = getVault(ctx.net.vault, signer);
      await sendTx(
        () =>
          vault.deposit(amount, account) as Promise<ethers.TransactionResponse>
      );
    },
    [signer, chainId, account, sendTx]
  );

  const doRedeemAll = useCallback(async () => {
    if (!signer || !chainId || !account || shares === 0n) return;
    const ctx = withVaultAsset(chainId);
    if (!ctx) return;
    const vault = getVault(ctx.net.vault, signer);
    await sendTx(
      () =>
        vault.redeem(shares, account, account) as Promise<ethers.TransactionResponse>
    );
  }, [signer, chainId, account, shares, sendTx]);

  const resetTx = useCallback(() => {
    setTxStatus("idle");
    setTxHash(null);
    setTxError(null);
  }, []);

  return {
    symbol,
    assetDecimals,
    shareDecimals,
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
  };
}
