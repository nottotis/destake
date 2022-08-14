// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import "src/ERC20Rebasing.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "src/IStaking.sol";
import "src/IEpochManager.sol";

/**
 * @title StakedGRT contract
 * @dev StakedGRT contract implements ERC20 with rebasing function
 * Mints StakedGRT token for deposits of GRT token and delegates deposited GRT tokens to a set of indexers address.
 */
contract StakedGRT is Initializable, ERC20Rebasing, OwnableUpgradeable, ReentrancyGuardUpgradeable, PausableUpgradeable {
    using EnumerableSet for EnumerableSet.AddressSet;
    // GRT token address
    IERC20 public grtToken;
    // max amount of sGRT to be issued (10% GRT total supply)
    uint256 public max_sgrt;
    // The Graph Protocol Staking contract (for delegation and undelegation)
    IStaking public grtStakingAddress;

    uint32 public fee;

    TokenStatus tokenStatus;

    address public stakingEpochManager;

    // Addresses for deposited GRT to be delegated to
    EnumerableSet.AddressSet[100] private delegationAddress;
    uint256 delegationAddressIndex;

    // Addresses to be removed from delegation
    EnumerableSet.AddressSet[100] private toBeRemovedAddress;
    uint256 toBeRemovedAddressIndex;

    // Removed delegation addresses
    EnumerableSet.AddressSet[100] private removedDelegationAddress;
    uint256 removedDelegationAddressIndex;
    
    // shares owned per delegation (shares, not GRT token!)
    mapping(address => uint256) public delegationShares;

    // pending undelegated balance
    mapping(address => PendingUndelegate) public pendingUndelegates;

    uint256 public redeemEndblock;
    uint256 public unbondingEndblock;

    /**
     * @dev Initialize the contract.
     */
    function initialize(address _grtAddress, address _grtStakingAddress, address _stakingEpochManager) external initializer{
        __ERC20Rebasing_init("StakedGRT", "sGRT", 18);
        __Ownable_init();
        __Pausable_init();
        grtToken = IERC20(_grtAddress);
        max_sgrt = 1000000000e18;
        grtStakingAddress = IStaking(_grtStakingAddress);
        fee = 5000; //0.5%
        stakingEpochManager = _stakingEpochManager;
    }

    /**
     * @dev Set the GRT token address.
     * @param _grtTokenAddress GRT token address
     */
    function setGRTToken(address _grtTokenAddress) external onlyOwner{
        grtToken = IERC20(_grtTokenAddress);
        emit GRTTokenAddressChanged(_grtTokenAddress);
    }

    /**
     * @dev Set the GRT staking contract address.
     * @param _grtStakingAddress Staking contract address
     */
    function setGRTStakingAddress(address _grtStakingAddress) external onlyOwner{
        grtStakingAddress = IStaking(_grtStakingAddress);
    }

    /**
     * @dev Add delegation address to the indexers address set.
     * @param _toBeDelegated Indexer address to be added
     */
    function addDelegationAddress(address _toBeDelegated) public onlyOwner {
        require(!delegationAddress[delegationAddressIndex].contains(_toBeDelegated),"Address already exist.");
        //todo Should additionally check if the address is a really an indexer
        delegationAddress[delegationAddressIndex].add(_toBeDelegated);
        emit DelegationAddressAdded(_toBeDelegated);
    }

    /**
     * @dev Remove delegation address from the indexers address set.
     * @param _toBeRemoved Indexer address to be removed
     */
    function removeDelegationAddress(address _toBeRemoved) public onlyOwner{
        require(delegationAddress[delegationAddressIndex].contains(_toBeRemoved),"Cannot be removed.");
        require(!toBeRemovedAddress[toBeRemovedAddressIndex].contains(_toBeRemoved),"Already removed.");
        delegationAddress[delegationAddressIndex].remove(_toBeRemoved);
        toBeRemovedAddress[toBeRemovedAddressIndex].add(_toBeRemoved);
        emit DelegationAddressRemoved(_toBeRemoved);
    }

    /**
     * @dev Return the size of delegation address set.
     * @return Delegation address set size(length)
     */
    function getDelegationAddressSize() external view returns(uint256){
        return delegationAddress[delegationAddressIndex].length();
    }

    /**
     * @dev Return the delegation address set.
     * @return Delegation address set
     */
    function getDelegationAddress() external view returns(address[] memory){
        return delegationAddress[delegationAddressIndex].values();
    }

    /**
     * @dev Deposit GRT token into the contract.
     * @param _grtAmount GRT token deposit amount
     */
    function depositGRT(uint256 _grtAmount) external nonReentrant whenNotPaused {
        uint256 depositedGRT = tokenStatus.waitingToDelegate + tokenStatus.delegated;
        require(depositedGRT + _grtAmount <= max_sgrt,"Max deposit amount reached");
        require(_grtAmount<=grtToken.balanceOf(msg.sender),"Not enough GRT");
        uint256 allowedAmount = grtToken.allowance(msg.sender,address(this));
        require(_grtAmount <= allowedAmount,"Insufficient allowance");

        grtToken.transferFrom(msg.sender, address(this), _grtAmount);
        mint(msg.sender,_grtAmount-taxGRTAmount(_grtAmount)-feeGRTAmount(_grtAmount));
        mint(address(this),feeGRTAmount(_grtAmount));

        tokenStatus.waitingToDelegate += _grtAmount;
        emit GRTDeposited(msg.sender,_grtAmount);
    }

    /**
     * @dev Start delegation to delegation address set.
     */
    function startDelegation() external onlyOwner{
        uint256 numberOfIndexers = delegationAddress[delegationAddressIndex].length();
        uint256 depositedGRTAmount = tokenStatus.waitingToDelegate;
        require(numberOfIndexers>0,"No indexer to delegate to.");
        require(depositedGRTAmount>0,"No grt deposited");
        grtToken.approve(address(grtStakingAddress), depositedGRTAmount);
        uint256 GRTPerIndexers = depositedGRTAmount / numberOfIndexers;

        tokenStatus.delegated += depositedGRTAmount;
        tokenStatus.waitingToDelegate -= depositedGRTAmount;


        for (uint256 i=0;i<numberOfIndexers;i++){
            address addressToBeDelegated = delegationAddress[delegationAddressIndex].at(i);
            delegationShares[addressToBeDelegated] += grtStakingAddress.delegate(addressToBeDelegated, GRTPerIndexers);
            emit GRTDelegatedToIndexer(addressToBeDelegated, GRTPerIndexers);
        }
    }

    /**
     * @dev Start undelegation from to be removed address set.
     */
    function startUndelegation() external onlyOwner{
        uint256 toBeUndelegatedLength = toBeRemovedAddress[toBeRemovedAddressIndex].length();
        require(toBeUndelegatedLength > 0,"No address to be undelegated");

        for(uint256 i = 0; i<toBeUndelegatedLength;i++){
            address addressToBeUndelegated = toBeRemovedAddress[toBeRemovedAddressIndex].at(i);
            IStakingData.Delegation memory delegation = grtStakingAddress.getDelegation(addressToBeUndelegated, address(this));
            uint256 undelegatedAmount = grtStakingAddress.undelegate(addressToBeUndelegated, delegation.shares);
            delegationShares[addressToBeUndelegated] = 0;
            removedDelegationAddress[removedDelegationAddressIndex].add(addressToBeUndelegated);
            emit GRTUndelegatedFromIndexer(addressToBeUndelegated,undelegatedAmount);
        }

        // clear all
        toBeRemovedAddressIndex++;
        
    }

    /**
     * @dev Deposits and delegate GRT token
     * @param _delegateAmount To be delegated GRT token amount
     */
    function depositAndDelegate(uint256 _delegateAmount) external nonReentrant whenNotPaused{
        uint256 depositedGRT = tokenStatus.waitingToDelegate + tokenStatus.delegated;
        require(depositedGRT + _delegateAmount <= max_sgrt,"Max deposit amount reached");
        require(_delegateAmount<=grtToken.balanceOf(msg.sender),"Not enough GRT");
        uint256 allowedAmount = grtToken.allowance(msg.sender,address(this));
        require(_delegateAmount <= allowedAmount,"Insufficient allowance");
        uint256 numberOfIndexers = delegationAddress[delegationAddressIndex].length();
        require(numberOfIndexers>0,"No indexer to delegate to.");

        grtToken.transferFrom(msg.sender, address(this), _delegateAmount);
        uint256 sGRTAmount = _delegateAmount-taxGRTAmount(_delegateAmount)-feeGRTAmount(_delegateAmount);

        mint(address(this), feeGRTAmount(_delegateAmount));
        mint(msg.sender,  sGRTAmount);

        uint256 GRTPerIndexers = _delegateAmount / numberOfIndexers;
        tokenStatus.delegated += _delegateAmount;
        grtToken.approve(address(grtStakingAddress), _delegateAmount);

        for (uint256 i=0;i<numberOfIndexers;i++){
            address addressToBeDelegated = delegationAddress[delegationAddressIndex].at(i);
            delegationShares[addressToBeDelegated] += grtStakingAddress.delegate(addressToBeDelegated, GRTPerIndexers);
            emit UserDepositAndDelegate(msg.sender, addressToBeDelegated, GRTPerIndexers);
        }

    }

    /**
     * @dev Set new max issuance of StakedGRT token
     * @param _newMaxIssuance New max issuance amount
     */
    function setMaxIssuance(uint256 _newMaxIssuance) external onlyOwner{
        max_sgrt = _newMaxIssuance;
        emit MaxIssuanceChanged(_newMaxIssuance);
    }


    /**
     * @dev Begins redeeming of sGRT to GRT (need to wait for unbonding period)
     * @param _amountToRedeem amount of sGRT to be redeemed
     */
    function redeemGRT(uint256 _amountToRedeem) external nonReentrant {
        require(_amountToRedeem <= this.allowance(msg.sender, address(this)),"Not enough allowance");
        require(_amountToRedeem<=this.balanceOf(msg.sender), "Not enough sGRT to redeem");
        this.transferFrom(msg.sender, address(this), _amountToRedeem);
        this.burn(_amountToRedeem);
        PendingUndelegate storage userPendingUndelegate = pendingUndelegates[msg.sender];

        // keep note on available redeem amount msg.sender
        userPendingUndelegate.lockedAmount+= _amountToRedeem;
        userPendingUndelegate.lockedUntilBlock = unbondingEndblock;

        // staking.undelegate(_amountToRedeem)
        uint256 numberOfIndexers = delegationAddress[delegationAddressIndex].length();
        uint256 GRTPerIndexers = _amountToRedeem / numberOfIndexers;
        for (uint256 i=0;i<numberOfIndexers;i++){
                address addressToBeDelegated = delegationAddress[delegationAddressIndex].at(i);
                (,,,, uint256 totalTokens, uint256 totalShares) = StakingV2Storage(address(grtStakingAddress)).delegationPools(addressToBeDelegated);
                uint256 sharesToUndelegate = GRTPerIndexers*totalShares/totalTokens;
                delegationShares[addressToBeDelegated] -= grtStakingAddress.undelegate(addressToBeDelegated, sharesToUndelegate);
                emit GRTUndelegatedFromIndexer(addressToBeDelegated, GRTPerIndexers);
         }

    }

    /**
     * @dev Withdraw unbonded GRT
     */
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


    /**
     * @dev Claim GRT token after unbonding period
     */
    function claimIfEnded() public {
        if(block.number >= unbondingEndblock){
            uint256 numberOfIndexers = delegationAddress[delegationAddressIndex].length();
            uint256 GRTPerIndexers = tokenStatus.waitingToUndelegate / numberOfIndexers;
            for (uint256 i=0;i<numberOfIndexers;i++){
                address addressToBeDelegated = delegationAddress[delegationAddressIndex].at(i);
                delegationShares[addressToBeDelegated] += grtStakingAddress.withdrawDelegated(addressToBeDelegated, address(0));
                emit GRTUndelegatedFromIndexer(addressToBeDelegated, GRTPerIndexers);
            }
            uint256 thawingPeriod = StakingV2Storage(address(grtStakingAddress)).thawingPeriod();
            redeemEndblock = unbondingEndblock + (thawingPeriod*5/28); //+ 5 days
            unbondingEndblock = block.number + thawingPeriod;
        }
    }
    
    /**
     * @dev Mints token
     * @param to Address to be minted tokens
     * @param amount Amount of tokens to be minted
     */
    function mint(address to, uint256 amount) internal {
        _mint(to, amount);
    }

    /**
     * @dev Burns token
     * @param amount Amount of tokens to be burned
     */
    function burn(uint256 amount) public virtual {
        _burn(_msgSender(), amount);
    }

    /**
     * @dev Set protocol fee
     * @param newFee New fee
     */
    function setProtocolFee(uint32 newFee) external{
        fee = newFee;
        emit NewFee(newFee);
    }

    /**
     * @dev Return staking contract tax percentage
     * @return Tax percentage
     */
    function getDelegationTaxPercentage() public view returns(uint32){
        require(address(grtStakingAddress) != address(0),"Staking address not set");
        return grtStakingAddress.delegationTaxPercentage();
    }

    /**
     * @dev Return GRT amount after staking tax.
     * @param _grtAmount GRT amount to be converted.
     * @return GRT amount after tax
     */
    function taxGRTAmount(uint256 _grtAmount) public view returns(uint256){
        return (_grtAmount*(getDelegationTaxPercentage()))/1000000;
    }

    /**
     * @dev Return GRT amount after protocol tax.
     * @param _grtAmount GRT amount to be converted.
     * @return GRT amount after tax
     */
    function feeGRTAmount(uint256 _grtAmount) public view returns(uint256){
        return (_grtAmount*(fee))/1000000;
    }
    
    /**
     * @dev Return GRT amount pending to be delegated.
     * @return GRT amount to be delegated
     */
    function getToBeDelegatedAmount() external view returns(uint256){
        return tokenStatus.waitingToDelegate;
    }

    /**
     * @dev Set staking epoch manager contract address.
     * @param _stakingEpochManager Staking epoch manager address.
     */
    function setStakingEpochManager(address _stakingEpochManager) external onlyOwner {
        stakingEpochManager=_stakingEpochManager;
    }

    /**
     * @dev Return current epoch.
     * @return Staking epoch number
     */
    function getEpoch() external view returns(uint256){
        return IEpochManager(stakingEpochManager).currentEpoch();
    }

    /**
     * @dev Return Start block number for given epoch.
     * @param _epoch Epoch number
     * @return Epoch start block
     */
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

    /**
     * @dev Return GRT token delegated on staking contract.
     * @return Delegated GRT amount
     */
    function totalGrtOnGraphStakingContract() public view returns(uint256){

        uint256 totalAmount;

        for(uint256 i = 0; i<delegationAddress[delegationAddressIndex].length(); i++){
            IStakingData.Delegation memory delegation = grtStakingAddress.getDelegation(delegationAddress[delegationAddressIndex].at(i), address(this));
            (,,,, uint256 totalTokens, uint256 totalShares) = StakingV2Storage(address(grtStakingAddress)).delegationPools(delegationAddress[delegationAddressIndex].at(i));

            totalAmount += (delegation.shares*totalTokens/totalShares);
        }

        return totalAmount;
    }

    /**
     * @dev Rebases token.
     */
    function rebase() external onlyOwner{
        uint256 currentTotalStake = totalGrtOnGraphStakingContract();
        require(currentTotalStake>0,"No stake yet");
        require(currentTotalStake != totalSupply,"No rewards");
        _rebase(currentTotalStake);
        
        emit Rebase(currentTotalStake);
    }

    /**
     * @dev Pause contract.
     */
    function pause() external whenNotPaused{
        _pause();
    }

    /**
     * @dev Unpause contract.
     */
    function unpause() external whenPaused{
        _unpause();
    }



    /**
     * @dev Emitted when GRT token address changed to `grtToken`.
     */
    event GRTTokenAddressChanged(address grtToken);

    /**
     * @dev Emitted when new indexer address `toBeDelegated` is added to the indexers address set.
     */
    event DelegationAddressAdded(address toBeDelegated);

    /**
     * @dev Emitted when the indexer address `toBeRemoved` is removed from the indexers address set.
     */
    event DelegationAddressRemoved(address toBeRemoved);

    /**
     * @dev Emitted when the `depositor` deposits `grtAmount` amount of GRT token..
     */
    event GRTDeposited(address depositor, uint256 grtAmount);

    /**
     * @dev Emitted when `grtAmount` amount of GRT is delegated to `indexer` address.
     */
    event GRTDelegatedToIndexer(address indexer, uint256 grtAmount);

    /**
     * @dev Emitted when `grtAmount` amount of GRT is undelegated from `indexer` address.
     */
    event GRTUndelegatedFromIndexer(address indexer, uint256 grtAmount);

    /**
     * @dev Emitted when the max issuance of StakedGRT token is changed to `_newMax`.
     */
    event MaxIssuanceChanged(uint256 _newMax);

    /**
     * @dev Emitted when the protocol fee is changed to `newFee`.
     */
    event NewFee(uint32 newFee);

    /**
     * @dev Emitted when the `user` withdraws `amount` amount of unbonded GRT token.
     */
    event UserWithdraw(address user,uint256 amount);

    /**
     * @dev Emitted when the `user` deposits and delegate `amount` of GRT token.
     */
    event UserDepositAndDelegate(address user, address indexer, uint256 amount);

    /**
     * @dev Emitted when the this token rebases to a new token supply of `newSupply`.
     */
    event Rebase(uint256 newSupply);



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

    struct StakingRewardsClaimStatus{
        uint256 claimed;
    }

}
