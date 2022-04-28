// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "./StakedGRT.sol";
import "graph-protocol/staking/IStaking.sol";
import "graph-protocol/staking/StakingStorage.sol";

contract DeStake is Initializable,OwnableUpgradeable,ReentrancyGuardUpgradeable,PausableUpgradeable{
    using EnumerableSet for EnumerableSet.AddressSet;

    struct PendingUndelegate{
        uint256 availableAmount;
        uint256 lockedAmount;
        uint256 lockedUntilBlock;
    }

    struct TokenStatus{
        uint256 waitingToDelegate;
        uint256 delegated;
        uint256 waitingToUndelegate;
        uint256 undelegated;
    }

    // GRT token address
    ERC20 public grtToken;

    // StakedGRT token address;
    StakedGRT public sGRT;

    // max amount of sGRT to be issued (10% GRT total supply)
    uint256 public max_sgrt;

    // Addresses for deposited GRT to be delegated to
    EnumerableSet.AddressSet private delegationAddress;

    // Amount of deposited GRT for each address;
    mapping(address => uint256) public deposit;

    uint256 public redeemEndblock;
    uint256 public unbondingEndblock;

    // Amount of GRT token deposited to this contract (before delegation tax)
    // if 1000GRT deposited, only 9995 sGRT are minted to account for token burn (0.5%, 5GRT of 1000GRt) from delegation
    // uint256 public depositedGRTAmount;

    // The Graph Protocol Staking contract (for delegation and undelegation)
    IStaking public grtStakingAddress;

    uint32 public fee;

    TokenStatus tokenStatus;
    
    // shares owned per delegation
    mapping(address => uint256) public delegationShares;

    // pending undelegated balance
    mapping(address => PendingUndelegate) public pendingUndelegates;

    // emitted on changes of GRT address
    event GRTTokenAddressChanged(address grtToken);

    // emitted on delegation address added to DeStake.delegationAddress 
    event DelegationAddressAdded(address toBeDelegated);

    // emitted on delegation address added to DeStake.delegationAddress 
    event DelegationAddressRemoved(address toBeRemoved);

    // emitted on deposited GRT to this contract
    event GRTDeposited(address depositor, uint256 grtAmount);

    // emitted when delegating GRT to indexer
    event GRTDelegatedToIndexer(address indexer, uint256 grtAmount);

    event GRTUndelegatedFromIndexer(address indexer, uint256 grtAmount);

    event MaxIssuanceChanged(uint256 _newMax);

    event NewFee(uint32);

    event UserWithdraw(address user,uint256 amount);

    event UserDepositAndDelegate(address user, address indexer, uint256 amount);


    function initialize(address _grtAddress, address _grtStakingAddress) public initializer {
        __Ownable_init();
        __Pausable_init();
        sGRT = new StakedGRT();
        grtToken = ERC20(_grtAddress);
        max_sgrt = 1000000000e18;
        grtStakingAddress = IStaking(_grtStakingAddress);
        fee = 5000; //0.5%
    }



    function setGRTToken(address _grtTokenAddress) external onlyOwner{
        grtToken = ERC20(_grtTokenAddress);
        emit GRTTokenAddressChanged(_grtTokenAddress);
    }

    function setGRTStakingAddress(address _grtStakingAddress) external onlyOwner{
        grtStakingAddress = IStaking(_grtStakingAddress);
    }

    function addDelegationAddress(address _toBeDelegated) public onlyOwner {
        require(!delegationAddress.contains(_toBeDelegated),"Address already exist.");
        //todo Should additionally check if the address is a really an indexer
        delegationAddress.add(_toBeDelegated);
        emit DelegationAddressAdded(_toBeDelegated);
    }

    function removeDelegationAddress(address _toBeRemoved) public onlyOwner{
        require(delegationAddress.contains(_toBeRemoved),"Cannot be removed.");
        delegationAddress.remove(_toBeRemoved);
        emit DelegationAddressRemoved(_toBeRemoved);
    }

    function getDelegationAddressSize() external view returns(uint256){
        return delegationAddress.length();
    }

    function getDelegationAddress() external view returns(address[] memory){
        return delegationAddress.values();
    }

    function depositGRT(uint256 _grtAmount) external nonReentrant whenNotPaused {
        uint256 depositedGRT = tokenStatus.waitingToDelegate + tokenStatus.delegated;
        require(depositedGRT + _grtAmount <= max_sgrt,"Max deposit amount reached");
        require(_grtAmount<=grtToken.balanceOf(msg.sender),"Not enough GRT");
        uint256 allowedAmount = grtToken.allowance(msg.sender,address(this));
        require(_grtAmount <= allowedAmount,"Insufficient allowance");

        grtToken.transferFrom(msg.sender, address(this), _grtAmount);
        sGRT.mint(msg.sender,_grtAmount-taxGRTAmount(_grtAmount)-feeGRTAmount(_grtAmount));

        tokenStatus.waitingToDelegate += _grtAmount;
        emit GRTDeposited(msg.sender,_grtAmount);
    }

    function startDelegation() external onlyOwner{
        uint256 numberOfIndexers = delegationAddress.length();
        uint256 depositedGRTAmount = tokenStatus.waitingToDelegate;
        require(numberOfIndexers>0,"No indexer to delegate to.");
        require(depositedGRTAmount>0,"No grt deposited");
        grtToken.approve(address(grtStakingAddress), depositedGRTAmount);
        uint256 GRTPerIndexers = depositedGRTAmount / numberOfIndexers;

        tokenStatus.delegated += depositedGRTAmount;
        tokenStatus.waitingToDelegate -= depositedGRTAmount;


        for (uint256 i=0;i<numberOfIndexers;i++){
            address addressToBeDelegated = delegationAddress.at(i);
            delegationShares[addressToBeDelegated] += grtStakingAddress.delegate(addressToBeDelegated, GRTPerIndexers);
            emit GRTDelegatedToIndexer(addressToBeDelegated, GRTPerIndexers);
        }
    }

    function depositAndDelegate(uint256 _delegateAmount) external nonReentrant whenNotPaused{
        uint256 depositedGRT = tokenStatus.waitingToDelegate + tokenStatus.delegated;
        require(depositedGRT + _delegateAmount <= max_sgrt,"Max deposit amount reached");
        require(_delegateAmount<=grtToken.balanceOf(msg.sender),"Not enough GRT");
        uint256 allowedAmount = grtToken.allowance(msg.sender,address(this));
        require(_delegateAmount <= allowedAmount,"Insufficient allowance");
        uint256 numberOfIndexers = delegationAddress.length();
        require(numberOfIndexers>0,"No indexer to delegate to.");

        grtToken.transferFrom(msg.sender, address(this), _delegateAmount);
        uint256 sGRTAmount = _delegateAmount-taxGRTAmount(_delegateAmount)-feeGRTAmount(_delegateAmount);
        sGRT.mint(msg.sender,sGRTAmount);

        uint256 GRTPerIndexers = sGRTAmount / numberOfIndexers;
        tokenStatus.delegated += _delegateAmount;

        for (uint256 i=0;i<numberOfIndexers;i++){
            address addressToBeDelegated = delegationAddress.at(i);
            delegationShares[addressToBeDelegated] += grtStakingAddress.delegate(addressToBeDelegated, GRTPerIndexers);
            emit UserDepositAndDelegate(msg.sender, addressToBeDelegated, GRTPerIndexers);
        }

    }

    function setMaxIssuance(uint256 _newMaxIssuance) external onlyOwner{
        max_sgrt = _newMaxIssuance;
        emit MaxIssuanceChanged(_newMaxIssuance);
    }


/// @notice Begins redeeming of sGRT to GRT (need to wait for unbonding period)
/// @param _amountToRedeem amount of sGRT to be redeemed
    function redeemGRT(uint256 _amountToRedeem) external nonReentrant {
        require(_amountToRedeem <= sGRT.allowance(msg.sender, address(this)),"Not enough allowance");
        require(_amountToRedeem<=sGRT.balanceOf(msg.sender), "Not enough sGRT to redeem");
        sGRT.burn(_amountToRedeem);
        PendingUndelegate memory userPendingUndelegate = pendingUndelegates[msg.sender];

        // keep note on available redeem amount msg.sender
        userPendingUndelegate.lockedAmount+= _amountToRedeem;
        userPendingUndelegate.lockedUntilBlock = unbondingEndblock;

        // staking.undelegate(_amountToRedeem)
        uint256 numberOfIndexers = delegationAddress.length();
        uint256 GRTPerIndexers = _amountToRedeem / numberOfIndexers;
        for (uint256 i=0;i<numberOfIndexers;i++){
                address addressToBeDelegated = delegationAddress.at(i);
                delegationShares[addressToBeDelegated] += grtStakingAddress.undelegate(addressToBeDelegated, GRTPerIndexers);
                emit GRTUndelegatedFromIndexer(addressToBeDelegated, GRTPerIndexers);
         }

    }

/// @notice users to claim GRT after unbonding period ended
    function withdrawUnbondedGRT() external nonReentrant{
        PendingUndelegate memory userPendingUndelegate = pendingUndelegates[msg.sender];
        uint256 pendingAmount = userPendingUndelegate.lockedAmount;
        require(pendingAmount > 0,"No locked GRT");
        require(userPendingUndelegate.lockedUntilBlock <= block.number ,"Unbonding endblock not reached");

        // claim from GRT staking contract for unbonded GRTs (check if unbonding period ended)
        claimIfEnded();

        userPendingUndelegate.lockedAmount = 0;
        userPendingUndelegate.lockedUntilBlock = 0;
        pendingUndelegates[msg.sender] = userPendingUndelegate;
        // get amount of available to be claimed by msg.sender
        grtToken.transfer(msg.sender, pendingAmount);
        emit UserWithdraw(msg.sender, pendingAmount);
    }

    function claimIfEnded() public {
        if(block.number >= unbondingEndblock){
            uint256 numberOfIndexers = delegationAddress.length();
            uint256 GRTPerIndexers = tokenStatus.waitingToUndelegate / numberOfIndexers;
            for (uint256 i=0;i<numberOfIndexers;i++){
                address addressToBeDelegated = delegationAddress.at(i);
                delegationShares[addressToBeDelegated] += grtStakingAddress.withdrawDelegated(addressToBeDelegated, address(0));
                emit GRTUndelegatedFromIndexer(addressToBeDelegated, GRTPerIndexers);
            }
            uint256 thawingPeriod = StakingV1Storage(address(grtStakingAddress)).thawingPeriod();
            redeemEndblock = unbondingEndblock + (thawingPeriod*5/28); //+ 5 days
            unbondingEndblock = block.number + thawingPeriod;
        }
    }

    function getDelegationTaxPercentage() public view returns(uint32){
        require(address(grtStakingAddress) != address(0),"Staking address not set");
        return StakingV1Storage(address(grtStakingAddress)).delegationTaxPercentage();
    }

    function taxGRTAmount(uint256 _grtAmount) public view returns(uint256){
        return (_grtAmount*(getDelegationTaxPercentage()))/1000000;
    }

    function feeGRTAmount(uint256 _grtAmount) public view returns(uint256){
        return (_grtAmount*(fee))/1000000;
    }

    function setProtocolFee(uint32 _newFee) external onlyOwner {
        fee = _newFee;
        emit NewFee(_newFee);
    }

    function getToBeDelegatedAmount() external view returns(uint256){
        return tokenStatus.waitingToDelegate;
    }

    function pause() external whenNotPaused{
        _pause();
    }
    function unpause() external whenPaused{
        _unpause();
    }


}