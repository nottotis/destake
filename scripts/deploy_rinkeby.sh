#!/usr/bin/env bash
set -e

source `dirname "$0"`/.bashvar

echo "Deploy ProxyAdmin"
proxyAdmin=$(forge create --rpc-url $RPC_URL_RINKEBY --private-key $PRIVATE_KEY ProxyAdmin)
proxyAdminAddress=$(echo $proxyAdmin | grep '0x[a-fA-F0-9]*' -o | sed -n 2p)
echo $proxyAdminAddress

echo "Deploy StakedGRT"
stakedGRT=$(forge create --rpc-url $RPC_URL_RINKEBY --private-key $PRIVATE_KEY StakedGRT)
stakedGRTAddress=$(echo $stakedGRT | grep '0x[a-fA-F0-9]*' -o | sed -n 2p)
echo $stakedGRTAddress

echo "Deploy Proxy"
proxy=$(forge create --rpc-url $RPC_URL_RINKEBY --private-key $PRIVATE_KEY TransparentUpgradeableProxy --constructor-args $stakedGRTAddress $proxyAdminAddress "")
proxyAddress=$(echo $proxy | grep '0x[a-fA-F0-9]*' -o | sed -n 2p)
echo $proxyAddress

echo "Initializing proxy"
initialize=$(cast send --rpc-url $RPC_URL_RINKEBY --private-key $PRIVATE_KEY $proxyAddress `cast calldata "initialize(address,address,address)" $GRT_ADDRESS $GRAPH_STAKING_ADDRESS $GRAPH_EPOCH_MANAGER`)

printf "$proxyAdminAddress\n$stakedGRTAddress\n$proxyAddress\n" > `dirname "$0"`/.deployed

# forge verify-contract --chain-id 4 --num-of-optimizations 1337 --compiler-version v0.8.10+commit.fc410830 $deployed src/GrtSwaps.sol:GrtSwaps $ETHERSCAN_API_KEY
    #  --constructor-args (cast abi-encode "constructor(string,string,uint256,uint256)" "ForgeUSD" "FUSD" 18 1000000000000000000000) \