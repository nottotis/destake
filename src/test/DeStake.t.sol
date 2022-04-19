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

    
        function setUp() public {
            deStake = new DeStake();
            proxyAdmin = new ProxyAdmin();
            TransparentUpgradeableProxy tmpProxy = new TransparentUpgradeableProxy(address(deStake), address(proxyAdmin),"");
            proxy = DeStake(address(tmpProxy));

            cheats.startPrank(DEPLOYER);
            graphToken = new MockGraphToken();
            mockStaking = new MockStaking(address(graphToken));
            proxy.initialize(address(graphToken),address(mockStaking));
            stakedGRT = proxy.sGRT();
            assert(proxy.grtToken() == graphToken);

            graphToken.transfer(alice,10000000000e18);
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
        uint256 grtTax = proxy.taxGRTAmount(amountToDeposit);
        uint256 protocolFee = proxy.feeGRTAmount(amountToDeposit);
        uint256 amountToDepositAfterTax = amountToDeposit - grtTax - protocolFee;
        uint256 aliceBalance = graphToken.balanceOf(alice);

        cheats.startPrank(alice);
        graphToken.approve(address(proxy),amountToDeposit);
        proxy.depositGRT(amountToDeposit);
        cheats.stopPrank();

        assert(graphToken.balanceOf(alice) == (aliceBalance - amountToDeposit));
        assert(stakedGRT.balanceOf(alice) == amountToDepositAfterTax);
    }

    function testGetDelegationTax() public view  { 
        assert(proxy.getDelegationTaxPercentage() == 5000);
    }

    function testStartDelegation() external{
        testOnDepositGRT();
        uint256 amountAvailable = proxy.getToBeDelegatedAmount();
        cheats.startPrank(DEPLOYER);
        graphToken.approve(address(mockStaking),amountAvailable);

        proxy.addDelegationAddress(address(1337));
        proxy.addDelegationAddress(address(420));
        // emit log_named_address("msg address",proxy.owner());
        proxy.startDelegation();
        cheats.stopPrank();
        assert(graphToken.balanceOf(address(proxy)) == 0);
        assert(graphToken.balanceOf(address(mockStaking)) == amountAvailable);
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
