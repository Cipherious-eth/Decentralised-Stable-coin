
🪙 Decentralised Stable Coin System (DSC)
A fully decentralized, exogenous-collateral-backed, algorithmic stablecoin protocol built on Ethereum. This system consists of two main contracts:

DecentralisedStableCoin.sol — The ERC20 stablecoin implementation.

DSCEngine.sol — The core engine responsible for managing minting, burning, collateral, and price stability.

📌 Table of Contents
Overview

Architecture

Contracts

Features

Tech Stack

Installation

Usage

Security

Contributing

License

🧠 Overview
This protocol creates a decentralized stablecoin (DSC) that is:

💵 Pegged to USD — Each DSC token aims to maintain a $1 value.

🔐 Overcollateralized — Backed by exogenous crypto assets like ETH and BTC.

🤖 Algorithmically Managed — All minting and burning logic is handled by the DSCEngine based on collateral value and system parameters.

🔄 Trust-Minimized — Operates with no central authority or intermediary.

🧱 Architecture
text
Copy
Edit
            +----------------------------+
            |      Price Feeds (Chainlink)|
            +----------------------------+
                         |
                         v
+----------------------+        +--------------------------+
| DecentralisedStableCoin |<-----|        DSCEngine        |
+----------------------+        +--------------------------+
| - ERC20 Token         |        | - Collateral Mgmt       |
| - Mint/Burn Access    |        | - Mint/Burn Logic       |
| - Ownable             |        | - Health Checks         |
+----------------------+        | - Price Feed Integrations|
                                | - Liquidation Logic      |
                                +--------------------------+
📄 Contracts
1. DecentralisedStableCoin.sol
An ERC20Burnable token contract that:

Can only be minted/burned by the DSCEngine (contract owner)

Reverts on invalid operations (zero address mint, zero amount, over-burn)

Is intended to be used only via the DSCEngine

2. DSCEngine.sol
The protocol’s control center. Responsibilities include:

🧮 Minting & Burning DSC

💰 Depositing & Withdrawing Collateral (e.g., ETH, wBTC)

⚖️ Health Checks (Collateral value ≥ DSC minted)

🪙 Maintaining Stability via overcollateralization

🔍 Fetching Prices using Chainlink oracles

💣 Triggering Liquidations when positions fall below health threshold

✨ Features
✅ DecentralisedStableCoin.sol
ERC20-compliant stablecoin

Custom minting/burning logic

Ownable by DSCEngine

Gas-optimized with custom errors

✅ DSCEngine.sol
Collateral deposit & withdrawal

Minting & burning DSC based on collateral ratio

Price fetching from Chainlink

Liquidation mechanics

Reentrancy protection

🛠 Tech Stack
Solidity ^0.8.18

Foundry (recommended)

Chainlink Price Feeds

OpenZeppelin Contracts

🧪 Installation
bash
Copy
Edit
git clone https://github.com/Cipherious-eth/DecentralisedStableCoin.git
cd DecentralisedStableCoin

# Install dependencies
forge install

# Build contracts
forge build
🚀 Usage
Mint DSC
solidity
Copy
Edit
// Only DSCEngine (owner) can call this
DecentralisedStableCoin.mint(user, amount);
Burn DSC
solidity
Copy
Edit
// Only DSCEngine can call this
DecentralisedStableCoin.burn(amount);
Deposit Collateral
solidity
Copy
Edit
DSCEngine.depositCollateral(ETH, msg.value);
Redeem Collateral
solidity
Copy
Edit
DSCEngine.redeemCollateral(wbtcAddress, amountToRedeem);
Liquidation
solidity
Copy
Edit
DSCEngine.liquidate(userWithBadDebt, collateralToken, debtToCover);
Get Health Factor
solidity
Copy
Edit
DSCEngine.getHealthFactor(user);
🔐 Security
Access Control: Only DSCEngine can mint/burn DSC.

Price Safety: Uses Chainlink oracles for price feeds.

Custom Errors: Optimized gas and clear failure reasons.

Overcollateralization: Users must maintain >100% collateral.

Liquidations: Unsafe positions can be liquidated by others.

Reentrancy Guard: Prevents reentrancy in state-changing functions.

🤝 Contributing
Pull requests are welcome! For major changes, please open an issue first to discuss what you'd like to change.

Write tests in Foundry

Ensure all checks are covered (e.g., health factor, collateral ratio)

Consider edge cases (oracle fails, flash loans, etc.)

📄 License
This project is licensed under the MIT License.

👤 Author
Cipherious.xyz
Decentralised Finance Developer | Smart Contract Auditor | Solidity Advocate

