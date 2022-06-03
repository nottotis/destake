// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.0;

import {ERC20Rebasing} from "src/ERC20Rebasing.sol";

contract MockERC20 is ERC20Rebasing {
    constructor(
        string memory _name,
        string memory _symbol,
        uint8 _decimals
    ){
        __ERC20Rebasing_init(_name, _symbol, _decimals);
    }

    function mint(address to, uint256 value) public virtual {
        _mint(to, value);
    }

    function burn(address from, uint256 value) public virtual {
        _burn(from, value);
    }

    function rebase(uint256 newTotalSupply) external {
        _rebase(newTotalSupply);
    }
}
