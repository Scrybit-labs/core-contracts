-include .env

.PHONY:  all test clean deploy fund help install snapshot format anvil deploy-roothash

DEFAULT_ANVIL_KEY := 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80

all: clean remove install update build

# Clean the repo
clean :; forge clean

# Remove modules
remove :; rm -rf .gitmodules && rm -rf .git/modules/* && rm -rf lib && touch .gitmodules && git add . && git commit -m "modules"

install :; forge install OpenZeppelin/openzeppelin-contracts && forge install OpenZeppelin/openzeppelin-contracts-upgradeable && forge install foundry-rs/forge-std@v1.11.0 

# Update Dependencies
update:; forge update

build :; forge build 

test :; forge test

snapshot :; forge snapshot

format :; forge fmt 

anvil :; anvil -m 'test test test test test test test test test test test junk' --steps-tracing --block-time 1


# debug :; forge test --debug --mt method

# coverage :; forge coverage --report debug > coverage.txt

# forge test --mt "testInitialSupply"

# verify :; forge verify-contract 0xA464d41eE745af9274305D455fD0274Bd5669F8B src/Raffle.sol:Raffle --etherscan-api-key $(ETHERSCAN_API_KEY) --rpc-url $(SEPOLIA_RPC_URL) --show-standard-json-input > json.json

# wallet :; cast wallet import <accountName> --interactive

# verify-roothash:;

# forge verify-contract --rpc-url https://rpc-testnet.roothashpay.com --verifier blockscout --verifier-url "https://explorer-testnet.roothashpay.com/api/" 0x827CECc85B7b14E345F501bf2D307736f072487d src/VrfMinProxyFactory.sol:VrfMinProxyFactory

# --show-standard-json-input > json.json

NETWORK_ARGS := --rpc-url http://localhost:8545 --private-key $(DEFAULT_ANVIL_KEY) --broadcast
NETWORK_SEPOLIA:= --rpc-url $(SEPOLIA_RPC_URL) --account devWallet --broadcast --verify --etherscan-api-key $(ETHERSCAN_API_KEY) -vvvv
NETWORK_ROOTHASH:= --rpc-url $(RHS_TESTNET_RPC_URL) --private-key $(PRIVATE_KEY) --broadcast -vvvv
NETWORK_HASHKEY:= --rpc-url $(HASHKEY_RPC_URL) --private-key $(PRIVATE_KEY) --broadcast -vvvv

# ============ L2 部署配置 (推荐用于生产环境) ============
# Arbitrum One (主网)
NETWORK_ARBITRUM:= --rpc-url $(ARBITRUM_RPC_URL) --private-key $(SEPOLIA_PRIV_KEY) --broadcast --verify --etherscan-api-key $(ARBISCAN_API_KEY) --verifier-url https://api.arbiscan.io/api -vvvv

# Arbitrum Sepolia (测试网)
NETWORK_ARBITRUM_SEPOLIA:= --rpc-url $(ARBITRUM_SEPOLIA_RPC_URL) --private-key $(PRIVATE_KEY) --broadcast --verify --etherscan-api-key $(ARBISCAN_API_KEY) --verifier-url https://api-sepolia.arbiscan.io/api -vvvv

# Base (主网) - Gas 最低，推荐！
NETWORK_BASE:= --rpc-url $(BASE_RPC_URL) --private-key $(PRIVATE_KEY) --broadcast --verify --etherscan-api-key $(BASESCAN_API_KEY) --verifier-url https://api.basescan.org/api -vvvv

# Base Sepolia (测试网)
NETWORK_BASE_SEPOLIA:= --rpc-url $(BASE_SEPOLIA_RPC_URL) --private-key $(PRIVATE_KEY) --broadcast --verify --etherscan-api-key $(BASESCAN_API_KEY) --verifier-url https://api-sepolia.basescan.org/api -vvvv

# Optimism (主网)
NETWORK_OPTIMISM:= --rpc-url $(OPTIMISM_RPC_URL) --private-key $(PRIVATE_KEY) --broadcast --verify --etherscan-api-key $(OPTIMISTIC_ETHERSCAN_API_KEY) --verifier-url https://api-optimistic.etherscan.io/api -vvvv

# Optimism Sepolia (测试网)
NETWORK_OPTIMISM_SEPOLIA:= --rpc-url $(OPTIMISM_SEPOLIA_RPC_URL) --private-key $(PRIVATE_KEY) --broadcast --verify --etherscan-api-key $(OPTIMISTIC_ETHERSCAN_API_KEY) --verifier-url https://api-sepolia-optimistic.etherscan.io/api -vvvv

# ============ 部署命令 ============
deploy-sepolia:
	@forge script script/DeploySWToken.s.sol:DeploySWToken $(NETWORK_SEPOLIA)

deploy-local:
	@forge script script/DeploySWToken.s.sol:DeploySWToken $(NETWORK_ARGS)

deploy-roothash:
	@forge script script/DeploySWToken.s.sol:DeploySWToken $(NETWORK_ROOTHASH)

deploy-hashkey:
	@forge script script/DeploySWToken.s.sol:DeploySWToken $(NETWORK_HASHKEY)

# ============ L2 部署命令 (推荐) ============
deploy-arbitrum:
	@forge script script/DeploySWToken.s.sol:DeploySWToken $(NETWORK_ARBITRUM)

deploy-arbitrum-sepolia:
	@forge script script/DeploySWToken.s.sol:DeploySWToken $(NETWORK_ARBITRUM_SEPOLIA)

deploy-base:
	@forge script script/DeploySWToken.s.sol:DeploySWToken $(NETWORK_BASE)

deploy-base-sepolia:
	@forge script script/DeploySWToken.s.sol:DeploySWToken $(NETWORK_BASE_SEPOLIA)

deploy-optimism:
	@forge script script/DeploySWToken.s.sol:DeploySWToken $(NETWORK_OPTIMISM)

deploy-optimism-sepolia:
	@forge script script/DeploySWToken.s.sol:DeploySWToken $(NETWORK_OPTIMISM_SEPOLIA)

# ============ Prediction Market Deployment ============
DEPLOY_SCRIPT := script/deploy/V1/DeployV1.s.sol:DeployV1

deploy-prediction-local:
	@forge script $(DEPLOY_SCRIPT) --rpc-url http://localhost:8545 --private-key $(DEFAULT_ANVIL_KEY) --broadcast -vv

deploy-prediction-sepolia:
	@forge script $(DEPLOY_SCRIPT) $(NETWORK_SEPOLIA)

deploy-prediction-roothash:
	@forge script $(DEPLOY_SCRIPT) $(NETWORK_ROOTHASH)

deploy-prediction-hashkey:
	@forge script $(DEPLOY_SCRIPT) $(NETWORK_HASHKEY)

deploy-prediction-base-sepolia:
	@forge script $(DEPLOY_SCRIPT) $(NETWORK_BASE_SEPOLIA)

deploy-prediction-base:
	@forge script $(DEPLOY_SCRIPT) $(NETWORK_BASE)

deploy-prediction-arbitrum-sepolia:
	@forge script $(DEPLOY_SCRIPT) $(NETWORK_ARBITRUM_SEPOLIA)

deploy-prediction-arbitrum:
	@forge script $(DEPLOY_SCRIPT) $(NETWORK_ARBITRUM)

deploy-prediction-optimism-sepolia:
	@forge script $(DEPLOY_SCRIPT) $(NETWORK_OPTIMISM_SEPOLIA)

deploy-prediction-optimism:
	@forge script $(DEPLOY_SCRIPT) $(NETWORK_OPTIMISM)

# Create deployments directory
create-deployments-dir:
	@mkdir -p deployments

# ============ HashKey 合约验证 (Blockscout) ============
# 部署地址 (2026-04-20):
# Deployer:                   0x523df39cAe18ea125930DA730628213e4b147CDc
# MockOracle:                 0xaFdC7a7871a0207e5d2F079Aa6c101f78700d586
# MockOracleAdapter (proxy):  0xd5E9adD135979F436242B85fFD474aCec77950c5
# EventManager (proxy):       0xD3B32Dd902E4EFE5C5186A8a7900157d43a6B450
# FeeVaultManager (proxy):    0x5A39fE21B2d819EAE1c182749deb3fE2aBD6e597
# FundingManager (proxy):     0xF3499B0557AfA2336E9F31ECB345f0d088c8EfcD
# OrderBookManager (proxy):   0xa77ECe2c29480ffE59a4e8859791903277d756De
# OrderStorage (proxy):       0xE6CEA57f878e907259e579bC23e54626B53C7C09

HASHKEY_VERIFY_ARGS := --rpc-url https://mainnet.hsk.xyz --verifier blockscout --verifier-url 'https://hashkey.blockscout.com/api/'

verify-hashkey-mock-oracle:
	@forge verify-contract $(HASHKEY_VERIFY_ARGS) \
	  0xaFdC7a7871a0207e5d2F079Aa6c101f78700d586 \
	  src/oracle/mock/MockOracle.sol:MockOracle

verify-hashkey-oracle-adapter:
	@forge verify-contract $(HASHKEY_VERIFY_ARGS) \
	  0xd5E9adD135979F436242B85fFD474aCec77950c5 \
	  src/oracle/mock/MockOracleAdapterProxy.sol:MockOracleAdapterProxy

verify-hashkey-event-manager:
	@forge verify-contract $(HASHKEY_VERIFY_ARGS) \
	  0xD3B32Dd902E4EFE5C5186A8a7900157d43a6B450 \
	  src/core/proxies/EventManagerProxy.sol:EventManagerProxy

verify-hashkey-fee-vault-manager:
	@forge verify-contract $(HASHKEY_VERIFY_ARGS) \
	  0x5A39fE21B2d819EAE1c182749deb3fE2aBD6e597 \
	  src/core/proxies/FeeVaultManagerProxy.sol:FeeVaultManagerProxy

verify-hashkey-funding-manager:
	@forge verify-contract $(HASHKEY_VERIFY_ARGS) \
	  0xF3499B0557AfA2336E9F31ECB345f0d088c8EfcD \
	  src/core/proxies/FundingManagerProxy.sol:FundingManagerProxy

verify-hashkey-order-book-manager:
	@forge verify-contract $(HASHKEY_VERIFY_ARGS) \
	  0xa77ECe2c29480ffE59a4e8859791903277d756De \
	  src/core/proxies/OrderBookManagerProxy.sol:OrderBookManagerProxy


verify-hashkey-order-storage:
	@forge verify-contract $(HASHKEY_VERIFY_ARGS) \
	  0xE6CEA57f878e907259e579bC23e54626B53C7C09 \
	  src/core/proxies/OrderStorageProxy.sol:OrderStorageProxy

verify-hashkey-all: verify-hashkey-mock-oracle verify-hashkey-oracle-adapter verify-hashkey-event-manager verify-hashkey-fee-vault-manager verify-hashkey-funding-manager verify-hashkey-order-book-manager