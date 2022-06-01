// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;


import "graph-protocol/epochs/IEpochManager.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract EpochDuration is Ownable{
    address public stakingEpochManager;

    constructor(address _stakingEpochManager){
        stakingEpochManager=_stakingEpochManager;
    }

    function setStakingEpochManager(address _stakingEpochManager) external {
        stakingEpochManager=_stakingEpochManager;
    }

    function getEpoch() external view returns(uint256){
        return IEpochManager(stakingEpochManager).currentEpoch();
    }

    function epochStartBlock(uint256 _epoch) public view returns(uint256){
        uint256 updatedEpoch = IEpochManager(stakingEpochManager).lastLengthUpdateEpoch();
        uint256 updatedBlock = IEpochManager(stakingEpochManager).lastLengthUpdateBlock();
        uint256 epochLenght = IEpochManager(stakingEpochManager).epochLength();
        require(_epoch >= updatedEpoch);
        
        return updatedBlock + ((_epoch - updatedEpoch)*epochLenght);
    }
    function epochEndBlock(uint256 _epoch) public view returns(uint256){
        return epochStartBlock(_epoch+1);
    }
}