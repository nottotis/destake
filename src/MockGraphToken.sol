// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract MockGraphToken is ERC20, Ownable {
    constructor() ERC20("MockGraphToken", "GRT") {
        _mint(msg.sender, 10000000000e18);
    }
}