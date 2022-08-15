// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import "ds-test/test.sol";
import "../StakedGRT.sol";
import "./utils/Cheats.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./utils/mocks/MockGraphToken.sol";
import "./utils/mocks/MockStaking.sol";

address constant DEPLOYER = address(0xb4c79daB8f259C7Aee6E5b2Aa729821864227e84);

contract ContractTest_Rinkeby is DSTest {
    StakedGRT stakedGRT;
    Cheats constant cheats = Cheats(HEVM_ADDRESS);
    address alice = address(1);
    StakedGRT proxy;
    ProxyAdmin proxyAdmin;
    IERC20 graphToken;
    MockStaking mockStaking;

    
        function setUp() public {
            stakedGRT = new StakedGRT();
            proxyAdmin = new ProxyAdmin();
            TransparentUpgradeableProxy tmpProxy = new TransparentUpgradeableProxy(address(stakedGRT), address(proxyAdmin),"");
            proxy = StakedGRT(address(tmpProxy));

            cheats.startPrank(DEPLOYER);
            graphToken = MockGraphToken(0x5c946740441C12510a167B447B7dE565C20b9E3C);
            mockStaking = MockStaking(0x35e3Cb6B317690d662160d5d02A5b364578F62c9);
            proxy.initialize(address(graphToken),address(mockStaking), address(0));
            assert(proxy.grtToken() == graphToken);
            cheats.stopPrank();

            cheats.startPrank(0x1246D7c4c903fDd6147d581010BD194102aD4ee2);
            MockGraphToken(address(graphToken)).mint(alice,10000000000e18);//1 million
            cheats.stopPrank();
    }

    function testOwnerships() public view {
        address owner = proxy.owner();
        assert(owner == DEPLOYER);
    }

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
        assert(proxy.balanceOf(alice) == amountToDepositAfterTax);
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

        proxy.addDelegationAddress(address(0xf88f95785F4048f20789c94132E3AcDeEc4bcFaB));
        proxy.addDelegationAddress(address(0xe91Ba60341095E3a5802d308d77496277B6dE39E));
        proxy.addDelegationAddress(address(0x0F6Feb3BA20c56E94CfbCD98339E99bcE629D912));
        proxy.addDelegationAddress(address(0xF7355cC64e05acAeB0aB147293eEB85600463E5b));
        proxy.addDelegationAddress(address(0xAC7f6653186F4013fba9502236934c4156883240));

        proxy.startDelegation();
        cheats.stopPrank();
        assert(graphToken.balanceOf(address(proxy)) == 0);
        assert(graphToken.balanceOf(address(mockStaking)) == stakingContractAmountBefore + (proxy.balanceOf(alice)*995/990));
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
        proxy.setMaxIssuance(maxSgrtIssuance+1e18);

        //deposit to max
        cheats.startPrank(alice);
        graphToken.approve(address(proxy),maxSgrtIssuance);
        proxy.depositGRT(maxSgrtIssuance);

        //deposit additional grt
        graphToken.approve(address(proxy),1e18);
        proxy.depositGRT(1e18);

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

        uint256 aliceBalanceBefore = proxy.balanceOf(alice);

        cheats.startPrank(alice);
        graphToken.approve(address(proxy),1e18);
        proxy.depositAndDelegate(1e18);
        cheats.stopPrank();

        uint256 aliceReceiveSGRT = 1e18*0.99;
        uint256 aliceBalanceAfter = proxy.balanceOf(alice);
        assert(aliceReceiveSGRT == aliceBalanceAfter-aliceBalanceBefore);
    }
}
