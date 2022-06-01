// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import "ds-test/test.sol";
import "../DeStake.sol";
import "../MockGraphToken.sol";
import "./utils/Cheats.sol";
import "./utils/MockStaking.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

address constant DEPLOYER = address(0xb4c79daB8f259C7Aee6E5b2Aa729821864227e84);

contract ContractTest is DSTest {
    Cheats constant cheats = Cheats(HEVM_ADDRESS);
    DeStake deStake;
    address alice = address(1);
    DeStake proxy;
    ProxyAdmin proxyAdmin;
    ERC20 graphToken;
    ERC20 stakedGRT;
    MockStaking mockStaking;

    
        function setUp() public {//this run on before every test
            deStake = new DeStake();
            proxyAdmin = new ProxyAdmin();
            TransparentUpgradeableProxy tmpProxy = new TransparentUpgradeableProxy(address(deStake),address(proxyAdmin),"");
            proxy = DeStake(address(tmpProxy));

            cheats.startPrank(DEPLOYER);
            graphToken = MockGraphToken(0x54Fe55d5d255b8460fB3Bc52D5D676F9AE5697CD);
            mockStaking = MockStaking(0x2d44C0e097F6cD0f514edAC633d82E01280B4A5c);
            proxy.initialize(address(graphToken),address(mockStaking), address(0));
            stakedGRT = proxy.sGRT();
            assert(proxy.grtToken() == graphToken);

            
            cheats.stopPrank();
            
            cheats.startPrank(0x460cA3721131BC978e3CF3A49EfC545A2901A828);
            MockGraphToken(address(graphToken)).mint(alice,10000000000e18);//1 million
            cheats.stopPrank();
            // emit log_named_address("deStake address",address(deStake));
            // emit log_named_address("proxyAdmin address",address(proxyAdmin));
            // emit log_named_address("proxy address",address(proxy));
    }

    function testOwnerships() public view {
        address owner = proxy.owner();
        address ownerERC20 = StakedGRT(address(proxy.sGRT())).owner();
        // emit log_named_address("Owner of proxy",owner);
        // emit log_named_address("Owner of sGRT",ownerERC20);
        assert(owner == DEPLOYER);
        assert(ownerERC20 == address(proxy));
    }

    // function testAddDelegationAddress(address indexer) public {
    //     proxy.addDelegationAddress(indexer);
    //     assert(proxy.getDelegationAddressSize() == 1);
    //     assert(proxy.getDelegationAddress()[0] == indexer);
    // }

    // function testFailOnSecondInitialize() public{
    //     proxy.initialize(address(0));
    // }

    // function testTransferOwnership(address newOwner) public {
    //     //skip if zero address
    //     if(newOwner == address(0)){
    //         return;
    //     }
    //     //test if not
    //     proxy.transferOwnership(newOwner);
    //     assert(proxy.owner() == newOwner);
    // }

    function testOnDepositGRT() public{
        uint256 amountToDeposit = 100e18;
        // uint256 grtTax = proxy.taxGRTAmount(amountToDeposit);
        // uint256 protocolFee = proxy.feeGRTAmount(amountToDeposit);
        // uint256 amountToDepositAfterTax = amountToDeposit - grtTax - protocolFee;
        uint256 aliceBalance = graphToken.balanceOf(alice);

        cheats.startPrank(alice);
        graphToken.approve(address(proxy),amountToDeposit);
        proxy.depositGRT(amountToDeposit);
        cheats.stopPrank();

        // emit log_named_uint("Alice GRT balance", graphToken.balanceOf(alice));
        assert(graphToken.balanceOf(alice) == (aliceBalance - amountToDeposit));
    }

    function testGetDelegationTax() public view  { 
        assert(proxy.getDelegationTaxPercentage() == 5000);
    }

    function testStartDelegation() external{
        testOnDepositGRT();
        uint256 amountAvailable = proxy.getToBeDelegatedAmount();
        uint256 stakingContractAmountBefore = graphToken.balanceOf(address(mockStaking));
        cheats.startPrank(DEPLOYER);
        graphToken.approve(address(mockStaking),amountAvailable);

        proxy.addDelegationAddress(address(0x0F6Feb3BA20c56E94CfbCD98339E99bcE629D912));
        proxy.addDelegationAddress(address(0x9b0B5b9e628a76A183cF7c3E2DC82F61aFBE3a39));
        // emit log_named_address("msg address",proxy.owner());
        proxy.startDelegation();
        cheats.stopPrank();
        assert(graphToken.balanceOf(address(proxy)) == 0);
        assert(graphToken.balanceOf(address(mockStaking)) == stakingContractAmountBefore + (stakedGRT.balanceOf(alice)*995/990));
        // assert(stakedGRT.balanceOf(alice) == amountToDepositAfterTax);
    }

    function testFailOnMaxDeposit() external{
        uint256 maxSgrtIssuance = proxy.max_sgrt();

        //deposit to max
        cheats.startPrank(alice);
        graphToken.approve(address(proxy),maxSgrtIssuance);
        proxy.depositGRT(maxSgrtIssuance);

        //deposit additional grt, should fail
        graphToken.approve(address(proxy),1);
        proxy.depositGRT(1);

        cheats.stopPrank();
    }
    function testSetMaxIssuance() external{
        uint256 maxSgrtIssuance = proxy.max_sgrt();

        cheats.prank(DEPLOYER);
        proxy.setMaxIssuance(maxSgrtIssuance+1);

        //deposit to max
        cheats.startPrank(alice);
        graphToken.approve(address(proxy),maxSgrtIssuance);
        proxy.depositGRT(maxSgrtIssuance);

        //deposit additional grt
        graphToken.approve(address(proxy),1);
        proxy.depositGRT(1);

        cheats.stopPrank();
    }

    function testFailDepositOnpause() external{
        proxy.pause();
        testOnDepositGRT();
    }
    function testPauseThenUnpause() external{
        proxy.pause();
        proxy.unpause();
        testOnDepositGRT();
    }

    function testDepositAndDelegate() external {
        this.testStartDelegation();

        uint256 grtAmountAliceBefore = graphToken.balanceOf(alice);
        uint256 grtAmountStakingContractBefore = graphToken.balanceOf(address(mockStaking));

        cheats.startPrank(alice);
        graphToken.approve(address(proxy),1e18);
        proxy.depositAndDelegate(1e18);
        cheats.stopPrank();
        require(grtAmountAliceBefore - graphToken.balanceOf(alice) == 1e18,"GRT sent amount mismatch");
        require(graphToken.balanceOf(address(mockStaking)) - grtAmountStakingContractBefore == 1e18 - proxy.taxGRTAmount(1e18),"Contract GRT amount mismatch");
    }

// todo finish redeem grt part
    function testRedeemGRT() external {
        this.testStartDelegation();

        cheats.startPrank(alice);
        stakedGRT.approve(address(proxy),1e18);
        proxy.redeemGRT(1e18);
        emit log_named_uint("Current", block.number);
        proxy.withdrawUnbondedGRT();
        cheats.stopPrank();
    }




    // function testGetDelegationTax() public{ //this test on mainnet
    //     proxy.setGRTStakingAddress(0xF55041E37E12cD407ad00CE2910B8269B01263b9);
    //     assert(proxy.getDelegationTaxPercentage() == 5000);
    //     // emit log_named_uint("Tax",proxy.getDelegationTaxPercentage());
    // }
    // function testAfterTaxGRT() public {
    //     proxy.setGRTStakingAddress(0xF55041E37E12cD407ad00CE2910B8269B01263b9);
    //     emit log_named_uint("After tax",proxy.afterTaxGRTAmount(1000));
    // }
}
