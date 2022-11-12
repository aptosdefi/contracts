# Aptos DeFi smart contracts

## Configuration
1. Install Aptos CLI: https://aptos.dev/cli-tools/aptos-cli-tool/install-aptos-cli/
2. Go to this directory
3. Run: aptos init
Create new account or import existing account
4. cp Move.toml.example Move.toml
5. Update Move.toml to match with your local machine (Aptos path) and account

## Deployment
1. Run: aptos move publish --named-addresses publisher=default

## Add Liquidity on Liquidswap
1. Select tokens pair: APT and ADF
2. The ADF address: <0x(acount)>::adf_coin::ADF
