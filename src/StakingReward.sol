// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/security/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract StakingReward is Pausable, ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;

    IERC20 public sgrtToken;
    uint256 public maxClaimAmount;

    bool public isMerkleRootSet;

    bytes32 public merkleRoot;

    uint256 public endTimestamp;

    uint256 public startTimestamp;

    mapping(address => bool) public hasClaimed;

    event AirdropRewardsClaim(address indexed user, uint256 amount);
    event MerkleRootSet(bytes32 merkleRoot);

    constructor(
        uint256 _startTimestamp,//1647518400
        uint256 _endTimestamp,//1648382400
        uint256 _maximumAmountToClaim,//10000*10**18
        address _fraktalToken,
        bytes32 _merkleRoot//0x8dfab5f1445c86bab8ddecc22981110b60bb14aa0e326226e3974785643a4e57
    ) {
        startTimestamp = _startTimestamp;
        endTimestamp = _endTimestamp;
        maxClaimAmount = _maximumAmountToClaim;

        sgrtToken = IERC20(_fraktalToken);
        merkleRoot = _merkleRoot;
        isMerkleRootSet = true;
    }

    function claim(
        uint256 amount,
        bytes32[] calldata merkleProof
    ) external whenNotPaused nonReentrant {
        require(isMerkleRootSet, "Airdrop: Merkle root not set");
        require(amount <= maxClaimAmount, "Airdrop: Amount too high");

        // Verify the user has claimed
        require(!hasClaimed[msg.sender], "Airdrop: Already claimed");


        // Compute the node and verify the merkle proof
        bytes32 node = keccak256(abi.encodePacked(msg.sender, amount));
        require(MerkleProof.verify(merkleProof, merkleRoot, node), "Airdrop: Invalid proof");

        // Set as claimed
        hasClaimed[msg.sender] = true;

        // Transfer tokens
        sgrtToken.safeTransfer(msg.sender, amount);

        emit AirdropRewardsClaim(msg.sender, amount);
    }

    function canClaim(
        address user,
        uint256 amount,
        bytes32[] calldata merkleProof
    ) external view returns (bool) {
        if (block.timestamp <= endTimestamp) {
            // Compute the node and verify the merkle proof
            bytes32 node = keccak256(abi.encodePacked(user, amount));
            return MerkleProof.verify(merkleProof, merkleRoot, node);
        } else {
            return false;
        }
    }

    function pauseAirdrop() external onlyOwner whenNotPaused {
        _pause();
    }

    function unpauseAirdrop() external onlyOwner whenPaused {
        _unpause();
    }
}