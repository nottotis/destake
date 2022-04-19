// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
contract GrtSwaps is Initializable, OwnableUpgradeable, ReentrancyGuardUpgradeable {
    struct WantSwapGRT{
        address owner;
        uint256 amount;
    }
    struct WantSwapSGRT{
        address owner;
        uint256 amount;
    }

    mapping(address => WantSwapGRT) wantSwapGrts;
    mapping(address => WantSwapSGRT) wantSwapSgrts;

    IERC20 grtAddress;
    IERC20 sgrtAddress;

    event ProposeGRT(address _owner,uint256 amount);
    event ProposeSGRT(address _owner,uint256 amount);
    event SwapGRT(address taker, address proposer, uint256 amount);
    event SwapSGRT(address taker, address proposer, uint256 amount);

    function initialize(address _grt, address _sgrt) public initializer {
        __Ownable_init();
        grtAddress = IERC20(_grt);
        sgrtAddress = IERC20(_sgrt);
    }

    function proposeGRTSwap(uint256 _grtAmount) external nonReentrant {
        wantSwapGrts[msg.sender] = WantSwapGRT(msg.sender,_grtAmount);
        grtAddress.transferFrom(msg.sender, address(this), _grtAmount);
        emit ProposeGRT(msg.sender,_grtAmount);
    }
    function removeGRTSwap() external nonReentrant {
        require(wantSwapGrts[msg.sender].amount > 0,"No available proposal");
        uint256 amount = wantSwapGrts[msg.sender].amount;
        wantSwapGrts[msg.sender] = WantSwapGRT(address(0),0);
        grtAddress.transfer(msg.sender, amount);
        emit ProposeGRT(address(0),0);
    }

    function acceptGRTProposal(address proposer) external nonReentrant{
        uint256 amount = wantSwapGrts[proposer].amount;
        require(amount > 0,"No available proposal");
        require(sgrtAddress.balanceOf(msg.sender) >= amount);

        //swaps
        grtAddress.transfer(msg.sender,amount );
        sgrtAddress.transferFrom(msg.sender, proposer, amount );

        wantSwapGrts[proposer] = WantSwapGRT(address(0),0);
        emit SwapGRT(msg.sender, proposer, amount);
    }



    function proposeSGRTSwap(uint256 _sgrtAmount) external nonReentrant {
        wantSwapSgrts[msg.sender] = WantSwapSGRT(msg.sender,_sgrtAmount);
        sgrtAddress.transferFrom(msg.sender, address(this), _sgrtAmount);
        emit ProposeSGRT(msg.sender,_sgrtAmount);
    }
    function removeSGRTSwap() external nonReentrant {
        require(wantSwapSgrts[msg.sender].amount > 0,"No available proposal");
        uint256 amount = wantSwapSgrts[msg.sender].amount;
        wantSwapSgrts[msg.sender] = WantSwapSGRT(address(0),0);
        sgrtAddress.transfer( msg.sender, amount);
        emit ProposeSGRT(address(0),0);
    }

    function acceptSGRTProposal(address proposer) external nonReentrant{
        uint256 amount = wantSwapSgrts[proposer].amount;
        require(amount > 0,"No available proposal");
        require(grtAddress.balanceOf(msg.sender) >= amount);

        //swaps
        sgrtAddress.transfer(msg.sender,amount );
        grtAddress.transferFrom(msg.sender, proposer, amount );

        wantSwapSgrts[proposer] = WantSwapSGRT(address(0),0);
        emit SwapSGRT(msg.sender, proposer, amount);
    }
}