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
    constructor(address _grtToken) {
        delegationTaxPercentage = 5000;
        graphToken = ERC20(_grtToken);
    }

    function delegate(address _indexer, uint256 _tokens)
        external
        returns (uint256)
    {
        address delegator = msg.sender;

        // Transfer tokens to delegate to this contract
        graphToken.transferFrom(delegator, address(this), _tokens);

        uint256 afterTax = _tokens * (1000000 - delegationTaxPercentage) / 1000000;

        // Update state
        return afterTax;
    }
}
