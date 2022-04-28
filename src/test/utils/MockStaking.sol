// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;
pragma abicoder v2;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";


/**
 * @title Staking contract
 * @dev The Staking contract allows Indexers to Stake on Subgraphs. Indexers Stake by creating
 * Allocations on a Subgraph. It also allows Delegators to Delegate towards an Indexer. The
 * contract also has the slashing functionality.
 */
contract MockStaking {
    uint32 public delegationTaxPercentage;
    ERC20 public graphToken;

    struct DelegationPool {
        uint32 cooldownBlocks; // Blocks to wait before updating parameters
        uint32 indexingRewardCut; // in PPM
        uint32 queryFeeCut; // in PPM
        uint256 updatedAtBlock; // Block when the pool was last updated
        uint256 tokens; // Total tokens as pool reserves
        uint256 shares; // Total shares minted in the pool
        mapping(address => Delegation) delegators; // Mapping of delegator => Delegation
    }

    struct Delegation {
        uint256 shares; // Shares owned by a delegator in the pool
        uint256 tokensLocked; // Tokens locked for undelegation
        uint256 tokensLockedUntil; // Block when locked tokens can be withdrawn
    }


    mapping(address => DelegationPool) public delegationPools;


    constructor(address _grtToken) {
        delegationTaxPercentage = 5000;
        graphToken = ERC20(_grtToken);
    }

    function init_mockIndexer(address _indexer, uint256 _tokenAmount) public{
       DelegationPool storage pool = delegationPools[_indexer];
       pool.indexingRewardCut = 0;
       pool.queryFeeCut = 0;
       pool.cooldownBlocks = 0;
       pool.updatedAtBlock = block.number;
       pool.tokens = _tokenAmount;
       pool.shares = _tokenAmount;
       pool.delegators[_indexer] = Delegation(_tokenAmount,0,0);
    }

    function delegate(address _indexer, uint256 _tokens)
        external
        returns (uint256)
    {
        address delegator = msg.sender;

        



        // Transfer tokens to delegate to this contract
        graphToken.transferFrom(delegator, address(this), _tokens);

        uint256 afterTax = _tokens * (1000000 - delegationTaxPercentage) / 1000000;

        _delegate(_indexer, delegator, afterTax);

        // Update state
        return afterTax;
    }

    function _delegate(address _indexer, address _delegator, uint256 _delegateAmount) internal{
        if(delegationPools[_indexer].shares == 0){
            init_mockIndexer(_indexer,10000);
        }

        DelegationPool storage pool = delegationPools[_indexer];

        uint256 shares = (pool.shares * _delegateAmount) / pool.tokens;

        pool.delegators[_delegator] = Delegation(shares,0,0);
        pool.shares += shares;
    }
}
