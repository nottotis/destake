#!/usr/bin/env bash

source `dirname "$0"`/.bashvar
# Change this addresses
adminAddress=$(cat $(dirname "$0")/.deployed| sed -n 1p)
stakedGRTAddress=$(cat $(dirname "$0")/.deployed| sed -n 2p)
proxyAddress=$(cat $(dirname "$0")/.deployed| sed -n 3p)

forge verify-contract --chain-id 4 --num-of-optimizations 1337 --compiler-version v0.8.10+commit.fc410830 $adminAddress lib/openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol:ProxyAdmin $ETHERSCAN_API_KEY
forge verify-contract --chain-id 4 --num-of-optimizations 1337 --compiler-version v0.8.10+commit.fc410830 $stakedGRTAddress src/StakedGRT.sol:StakedGRT $ETHERSCAN_API_KEY
forge verify-contract --chain-id 4 --num-of-optimizations 1337 --compiler-version v0.8.10+commit.fc410830 $proxyAddress lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol:TransparentUpgradeableProxy $ETHERSCAN_API_KEY --constructor-args `cast abi-encode "constructor(address,address,bytes)" $stakedGRTAddress $adminAddress ""`