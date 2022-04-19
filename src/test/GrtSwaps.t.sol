// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import "ds-test/test.sol";
import "../DeStake.sol";
import "../GrtSwaps.sol";
import "../MockGraphToken.sol";
import "./utils/Cheats.sol";
import "./utils/MockStaking.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

address constant DEPLOYER = address(0xb4c79daB8f259C7Aee6E5b2Aa729821864227e84);
address constant alice = address(1);
address constant bob = address(2);

contract ContractTest is DSTest {
    Cheats constant cheats = Cheats(HEVM_ADDRESS);
    GrtSwaps proxy;
    MockGraphToken graphToken;
    MockGraphToken stakedGraph;

    
        function setUp() public {
            GrtSwaps grtSwaps = new GrtSwaps();
            ProxyAdmin proxyAdmin = new ProxyAdmin();
            TransparentUpgradeableProxy tmpProxy = new TransparentUpgradeableProxy(address(grtSwaps), address(proxyAdmin),"");
            proxy = GrtSwaps(address(tmpProxy));

            cheats.prank(alice);
            graphToken = new MockGraphToken();

            cheats.prank(bob);
            stakedGraph = new MockGraphToken();

            cheats.startPrank(DEPLOYER);
            proxy.initialize(address(graphToken),address(stakedGraph));
            cheats.stopPrank();

            uint256 initialBalance = graphToken.balanceOf(alice);
            cheats.prank(alice);
            graphToken.approve(address(proxy),initialBalance);
            cheats.prank(bob);
            stakedGraph.approve(address(proxy),initialBalance);
    }

    function testOwnerships() public view {
        address owner = proxy.owner();
        // emit log_named_address("Owner of proxy",owner);
        // emit log_named_address("Owner of sGRT",ownerERC20);
        assert(owner == DEPLOYER);
    }

    function testPostOrderGRT() public {
        cheats.prank(alice);
        proxy.proposeGRTSwap(100);
        assert(graphToken.balanceOf(address(proxy))==100);
    }
    function testTakeOrderGRT() public {
        testPostOrderGRT();
        cheats.startPrank(bob);
        proxy.acceptGRTProposal(alice);
        cheats.stopPrank();
        assert(graphToken.balanceOf(bob)==100);
    }

    function testRemoveOrderGRT() public {
        testPostOrderGRT();
        cheats.prank(alice);
        proxy.removeGRTSwap();
        assert(graphToken.balanceOf(address(proxy))==0);
    }

    function testFailNoGRTOrder() public {
        cheats.startPrank(bob);
        proxy.acceptGRTProposal(alice);
        cheats.stopPrank();
    }



    function testPostOrderSGRT() public {
        cheats.prank(bob);
        proxy.proposeSGRTSwap(100);
        assert(stakedGraph.balanceOf(address(proxy))==100);
    }
    function testTakeOrderSGRT() public {
        testPostOrderSGRT();
        cheats.startPrank(alice);
        proxy.acceptSGRTProposal(bob);
        cheats.stopPrank();
        assert(stakedGraph.balanceOf(alice)==100);
    }

    function testRemoveOrderSGRT() public {
        testPostOrderSGRT();
        cheats.prank(bob);
        proxy.removeSGRTSwap();
        assert(stakedGraph.balanceOf(address(proxy))==0);
    }

    function testFailNoSGRTOrder() public {
        cheats.startPrank(alice);
        proxy.acceptSGRTProposal(bob);
        cheats.stopPrank();
    }
}
