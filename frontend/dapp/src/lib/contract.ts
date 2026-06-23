import { ethers } from "ethers";

export interface NetworkConfig {
  name: string;
  explorer: string;
  vault: string;
  asset: string;
  hexId: string;
}

// Direcciones desplegadas y VERIFICADAS en Sepolia.
export const NETWORKS: Record<number, NetworkConfig> = {
  11155111: {
    name: "Sepolia",
    explorer: "https://sepolia.etherscan.io",
    vault: "0xa32f9d514804084839b59972F8b43e616BB4E32b",
    asset: "0xc10b0e68f21c5fFf30D608Fe5179ED915A24e423",
    hexId: "0xaa36a7",
  },
};

// ABI del vault (ERC-4626 + extras). Formato "human-readable" de ethers.
export const VAULT_ABI = [
  "function asset() view returns (address)",
  "function decimals() view returns (uint8)",
  "function totalAssets() view returns (uint256)",
  "function totalSupply() view returns (uint256)",
  "function balanceOf(address) view returns (uint256)",
  "function depositCap() view returns (uint256)",
  "function maxDeposit(address) view returns (uint256)",
  "function previewDeposit(uint256 assets) view returns (uint256)",
  "function convertToAssets(uint256 shares) view returns (uint256)",
  "function deposit(uint256 assets, address receiver) returns (uint256)",
  "function redeem(uint256 shares, address receiver, address owner) returns (uint256)",
  "event Deposit(address indexed sender, address indexed owner, uint256 assets, uint256 shares)",
];

// ABI del activo (MockUSDC, ERC-20 estándar + faucet mint).
export const ASSET_ABI = [
  "function decimals() view returns (uint8)",
  "function symbol() view returns (string)",
  "function balanceOf(address) view returns (uint256)",
  "function allowance(address owner, address spender) view returns (uint256)",
  "function approve(address spender, uint256 amount) returns (bool)",
  "function mint(address to, uint256 amount)",
];

export function getVault(
  address: string,
  signerOrProvider: ethers.Signer | ethers.Provider
) {
  return new ethers.Contract(address, VAULT_ABI, signerOrProvider);
}

export function getAsset(
  address: string,
  signerOrProvider: ethers.Signer | ethers.Provider
) {
  return new ethers.Contract(address, ASSET_ABI, signerOrProvider);
}

/// Formatea un bigint con `decimals` decimales, recortando a `maxFrac` y sin ceros sobrantes.
export function fmtUnits(value: bigint, decimals: number, maxFrac = 4): string {
  const s = ethers.formatUnits(value, decimals);
  const [int, frac = ""] = s.split(".");
  const trimmed = frac.slice(0, maxFrac).replace(/0+$/, "");
  return trimmed ? `${int}.${trimmed}` : int;
}
