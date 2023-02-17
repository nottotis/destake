// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import "ds-test/test.sol";
import "forge-std/Test.sol";

import "../StakedGRT.sol";
import "./utils/Cheats.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./utils/mocks/MockGraphToken.sol";
import "./utils/mocks/MockStaking.sol";

address constant DEPLOYER = address(0xb4c79daB8f259C7Aee6E5b2Aa729821864227e84);

contract ContractTest is Test {
    StakedGRT stakedGRT;
    Cheats constant cheats = Cheats(HEVM_ADDRESS);
    address alice = address(1);
    address bob = address(2);
    StakedGRT proxy;
    ProxyAdmin proxyAdmin;
    IERC20 graphToken;
    MockStaking mockStaking;

    function setUp() public {
        stakedGRT = new StakedGRT();
        proxyAdmin = new ProxyAdmin();
        TransparentUpgradeableProxy tmpProxy =
            new TransparentUpgradeableProxy(address(stakedGRT), address(proxyAdmin),"");
        proxy = StakedGRT(address(tmpProxy));

        cheats.startPrank(DEPLOYER);
        graphToken = new MockGraphToken();
        mockStaking = new MockStaking(address(graphToken));
        proxy.initialize(address(graphToken), address(mockStaking), address(0));
        assert(proxy.grtToken() == graphToken);

        graphToken.transfer(alice, 10000000000e18);
        cheats.stopPrank();
        // emit log_named_address("stakedGRT address",address(stakedGRT));
        // emit log_named_address("proxyAdmin address",address(proxyAdmin));
        // emit log_named_address("proxy address",address(proxy));
    }

    function testOwnerships() public view {
        address owner = proxy.owner();
        // emit log_named_address("Owner of proxy",owner);
        // emit log_named_address("Owner of sGRT",ownerERC20);
        assert(owner == DEPLOYER);
    }

    function testAddDelegationAddress(address indexer) public {
        // prank as owner
        cheats.startPrank(DEPLOYER);
        proxy.addDelegationAddress(indexer);
        assert(proxy.getDelegationAddressSize() == 1);
        assert(proxy.getDelegationAddress()[0] == indexer);

        cheats.stopPrank();
    }

    // function testFailOnSecondInitialize() public{
    //     proxy.initialize(address(0));
    // }

    function testTransferOwnership(address newOwner) public {
        //skip if zero address
        if (newOwner == address(0)) {
            return;
        }

        //as owner
        cheats.startPrank(DEPLOYER);
        //test if not
        proxy.transferOwnership(newOwner);
        assert(proxy.owner() == newOwner);
        cheats.stopPrank();
    }

    function testOnDepositGRT() public {
        uint256 amountToDeposit = 100e18;
        uint256 grtTax = proxy.taxGRTAmount(amountToDeposit);
        uint256 protocolFee = proxy.feeGRTAmount(amountToDeposit);
        uint256 amountToDepositAfterTax = amountToDeposit - grtTax - protocolFee;
        uint256 aliceBalance = graphToken.balanceOf(alice);

        cheats.startPrank(alice);
        graphToken.approve(address(proxy), amountToDeposit);
        proxy.depositGRT(amountToDeposit);
        cheats.stopPrank();

        assert(graphToken.balanceOf(alice) == (aliceBalance - amountToDeposit));
        assert(proxy.balanceOf(alice) == amountToDepositAfterTax);
    }

    function testGetDelegationTax() public view {
        assert(proxy.getDelegationTaxPercentage() == 5000);
    }

    function testStartDelegation() external {
        testOnDepositGRT();
        uint256 amountAvailable = proxy.getToBeDelegatedAmount();
        cheats.startPrank(DEPLOYER);
        graphToken.approve(address(mockStaking), amountAvailable);

        for (uint256 i = 0; i < 100; i++) {
            proxy.addDelegationAddress(address(uint160(i)));
        }

        //StartDelegation consume max 13517112 gas on 100 delegation address set.
        //run "forge test" with --gas-report flag to confirm
        proxy.startDelegation();
        cheats.stopPrank();
        // emit log_named_uint("msg address",graphToken.balanceOf(address(proxy)));
        assert(graphToken.balanceOf(address(proxy)) == 0);
        assert(graphToken.balanceOf(address(mockStaking)) == amountAvailable);
    }

    function testFailOnMaxDeposit() external {
        uint256 maxSgrtIssuance = proxy.max_sgrt();

        //deposit to max
        cheats.startPrank(alice);
        graphToken.approve(address(proxy), maxSgrtIssuance);
        proxy.depositGRT(maxSgrtIssuance);

        //deposit additional grt, should fail
        graphToken.approve(address(proxy), 1);
        proxy.depositGRT(1);

        cheats.stopPrank();
    }

    function testSetMaxIssuance() external {
        uint256 maxSgrtIssuance = proxy.max_sgrt();

        cheats.prank(DEPLOYER);
        proxy.setMaxIssuance(maxSgrtIssuance + 1e18);

        //deposit to max
        cheats.startPrank(alice);
        graphToken.approve(address(proxy), maxSgrtIssuance);
        proxy.depositGRT(maxSgrtIssuance);

        //deposit additional grt
        graphToken.approve(address(proxy), 1e18);
        proxy.depositGRT(1e18);

        cheats.stopPrank();
    }

    function testFailDepositOnpause() external {
        proxy.pause();
        testOnDepositGRT();
    }

    function testPauseThenUnpause() external {
        // as owner
        cheats.startPrank(DEPLOYER);

        proxy.pause();
        proxy.unpause();
        cheats.stopPrank();

        testOnDepositGRT();
    }

    function testDepositAndDelegate() external {
        this.testStartDelegation();

        uint256 aliceBalanceBefore = proxy.balanceOf(alice);

        cheats.startPrank(alice);
        graphToken.approve(address(proxy), 1e18);
        proxy.depositAndDelegate(1e18);
        cheats.stopPrank();

        uint256 aliceReceiveSGRT = 1e18 * 0.99;
        uint256 aliceBalanceAfter = proxy.balanceOf(alice);
        assert(aliceReceiveSGRT == aliceBalanceAfter - aliceBalanceBefore);
    }

    function testPauseThenUnpauseAsNonOwner() external {
        // as non owner
        uint256 aliceBalanceBefore = graphToken.balanceOf(alice);
        cheats.startPrank(alice);
        graphToken.approve(address(proxy), 1000000e18);
        proxy.pause();
        cheats.stopPrank();
        //compare before and after balance
        uint256 aliceBalanceAfter = graphToken.balanceOf(alice);
        assert(aliceBalanceBefore - 1000000e18 == aliceBalanceAfter);

        // unpause as owner
        cheats.startPrank(DEPLOYER);
        proxy.unpause();
        cheats.stopPrank();

        testOnDepositGRT();
    }

    function testFailPauseThenUnpauseAsNonOwner() external {
        // as non owner
        cheats.startPrank(alice);
        proxy.pause();
        proxy.unpause();
        cheats.stopPrank();
    }

    function testCannotTransferWhenPaused() external {
        // as non owner
        testOnDepositGRT();

        // as owner
        cheats.startPrank(DEPLOYER);
        proxy.pause();
        cheats.stopPrank();

        cheats.startPrank(alice);
        vm.expectRevert("Pausable: paused");
        proxy.transfer(bob, 1e18);
        cheats.stopPrank();
    }

    function testCannotTransferFromWhenPaused() external {
        // as non owner
        testOnDepositGRT();

        // as owner
        cheats.startPrank(DEPLOYER);
        proxy.pause();
        cheats.stopPrank();

        cheats.startPrank(alice);
        vm.expectRevert("Pausable: paused");
        proxy.transferFrom(alice, bob, 1e18);
        cheats.stopPrank();
    }

    function testCannotMintWhenPaused() external {
        // as owner
        cheats.startPrank(DEPLOYER);
        proxy.pause();
        cheats.stopPrank();

        cheats.startPrank(alice);
        graphToken.approve(address(proxy), 1e18);
        vm.expectRevert("Pausable: paused");
        proxy.depositGRT(1e18); //inside depositGRT() call mint
        cheats.stopPrank();
    }

    // function testRebaseRewards() external {// should test on rinkeby only
    //     this.testDepositAndDelegate();
    //     emit log_named_uint("In staking",proxy.totalGrtOnGraphStakingContract());
    //     emit log_named_uint("Supply",proxy.totalSupply());
    //     proxy.rebase();
    // }

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
