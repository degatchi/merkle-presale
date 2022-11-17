// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "../lib/forge-std/src/Test.sol";
import {STFXToken} from "../src/STFXToken.sol";
import {MockUSDC} from "./MockUSDC.sol";
import {MockERC20} from "./MockERC20.sol";
import {Presale} from "../src/Presale.sol";

error SaleNotStarted(uint256 current, uint256 start);
error SaleEnded(uint256 current, uint256 ends);
error InvalidProof();
error AlreadyClaimed();
error ClaimsNotOpen();
error NotPaymentToken();
error ModularError(uint120 by, uint120 remainder);

/**
 Merkle being used:
[
  {
    "inputs": [
      "0x599a9d94b12dd3313211bd1ae9e35a30c0753f5e",
      "50000000000000000000",
      "0",
      "0",
      "0"
    ],
    "proof": [
      "0x91fa7ab2e733260d8b0ea8319e7d400aa9a4fea78f7f642c82bad79c55005534",
      "0x700d0be68d4459f95844e3ed504fb71baaac5ff9992b2eb709dc915326f4f110"
    ],
    "root": "0x14ad8b71aa540fba7c7fb6a445baf9cb0be31a21b3d80930324f8fcfeb16fb4d",
    "leaf": "0x76a852e3eb5928fef11b51eadbbb75e6fce7d8fda9b1031bc53437cd3386e11b"
  },
  {
    "inputs": [
      "0x599a9d94b12dd3313211bd1ae9e35a30c0753f5e",
      "200000000000000000000",
      "12500000",
      "0",
      "25000000000000000"
    ],
    "proof": [
      "0x76a852e3eb5928fef11b51eadbbb75e6fce7d8fda9b1031bc53437cd3386e11b",
      "0x700d0be68d4459f95844e3ed504fb71baaac5ff9992b2eb709dc915326f4f110"
    ],
    "root": "0x14ad8b71aa540fba7c7fb6a445baf9cb0be31a21b3d80930324f8fcfeb16fb4d",
    "leaf": "0x91fa7ab2e733260d8b0ea8319e7d400aa9a4fea78f7f642c82bad79c55005534"
  },
  {
    "inputs": [
      "0x599a9d94b12dd3313211bd1ae9e35a30c0753f5e",
      "250000000000000000000",
      "0",
      "0",
      "0"
    ],
    "proof": [
      "0xbf43232ec48fc7a41b395ef85562900fee8c1d89d497673be068fc4c8f154aec",
      "0xa143f62d0c134dda9e9a749dd9d400ad0e2458b053426fcd4ff78a019099883e"
    ],
    "root": "0x14ad8b71aa540fba7c7fb6a445baf9cb0be31a21b3d80930324f8fcfeb16fb4d",
    "leaf": "0xbf43232ec48fc7a41b395ef85562900fee8c1d89d497673be068fc4c8f154aec"
  }
]
 */

// run test: forge test --match-contract PresaleTest -vvv
contract PresaleTest is Test {
    STFXToken internal stfxToken;
    Presale internal presale;
    MockUSDC internal usdc;
    MockUSDC internal usdt;
    MockERC20 internal dai;
    MockERC20 internal random_erc20;

    // Have a set address to create the merkle tree.
    address internal deployer = 0x599A9d94b12dD3313211BD1AE9E35a30c0753f5E;

    /// Set up the environment.
    function setUp() public {
        vm.startPrank(deployer);

        stfxToken = new STFXToken();
        usdc = new MockUSDC(); // 6 decimals
        usdt = new MockUSDC(); // 6 decimals
        dai = new MockERC20(); // 18 decimals
        random_erc20 = new MockERC20(); // 18 decimals

        stfxToken.mint(deployer, 500e18);
        usdc.mint(deployer, 1_000e6); // USDC has 6 decimals.
        dai.mint(deployer, 1_000e18); // 18 decimals.

        presale = new Presale(
            address(dai),
            address(usdt),
            address(usdc),
            address(stfxToken)
        );

        vm.stopPrank();
    }

    /// Expect pass:
    /// - Deployer initialises the sale.
    function testStartPresale() public {
        vm.startPrank(deployer);

        stfxToken.approve(address(presale), 500e18);
        presale.initialise(
            // Start.
            uint40(block.timestamp + 5),
            // Duration.
            uint40(10),
            // 500 tokens for sale.
            500e18,
            // 0.05 USDC per token.
            5e4
        );

        vm.stopPrank();

        assertTrue(presale.initialised());
        assertEq(stfxToken.balanceOf(address(presale)), 500e18);
    }

    /// Expect revert:
    /// - User attempts to creates a buy order before sale has started.
    function testBuyOrder_before_sale() public {
        testStartPresale();

        vm.startPrank(deployer);

        assertEq(usdc.balanceOf(deployer), 1_000e6);
        usdc.approve(address(presale), 1_000e6);

        vm.expectRevert(
            abi.encodeWithSelector(
                SaleNotStarted.selector,
                block.timestamp,
                presale.start()
            )
        );
        presale.createBuyOrder(1e18, address(usdc));

        vm.stopPrank();
    }

    /// Expect revert:
    /// - User attempts to creates a buy order after sale has finalised.
    function testBuyOrder_after_sale() public {
        testStartPresale();

        vm.startPrank(deployer);

        vm.warp(block.timestamp + 16);

        assertEq(usdc.balanceOf(deployer), 1_000e6);
        usdc.approve(address(presale), 1_000e6);

        uint256 end = uint256(presale.start()) + uint256(presale.duration());
        vm.expectRevert(
            abi.encodeWithSelector(SaleEnded.selector, block.timestamp, end)
        );
        presale.createBuyOrder(1e18, address(usdc));

        vm.stopPrank();
    }

    /// Expect revert:
    /// - User attempts to buy token with non-payment token.
    function testBuyOrder_wrong_payment_token() public {
        testStartPresale();

        vm.startPrank(deployer);

        vm.warp(block.timestamp + 5);

        vm.expectRevert(abi.encodeWithSelector(NotPaymentToken.selector));
        presale.createBuyOrder(250e18, address(random_erc20));

        vm.stopPrank();
    }

    /// Expect pass:
    /// - User creates a buy order for `_amount` tokens.
    function testBuyOrder_fuzz(uint120 _amount) public {
        testStartPresale();

        // price per token: 1e18 <> 5e4
        // lowest amount before free: 1e14 <> 5
        // anything below 1e14 creates a 0 payment and reverts.
        vm.assume(_amount <= 500e18); // 500 token supply.
        vm.assume(_amount % 1e18 == 0);
        vm.assume(_amount != 0);

        vm.startPrank(deployer);

        vm.warp(block.timestamp + 5);

        assertEq(usdc.balanceOf(deployer), 1_000e6);
        usdc.approve(address(presale), 1_000e6);
        presale.createBuyOrder(_amount, address(usdc));

        vm.stopPrank();

        uint256 payment = (_amount * presale.price()) / 1e18;

        assertEq(usdc.balanceOf(address(presale)), payment);
        assertEq(usdc.balanceOf(deployer), 1_000e6 - payment);

        (, , uint256 _usdc, uint256 _tokens, ) = presale.receipt(deployer);
        assertEq(_usdc, payment);
        assertEq(_tokens, _amount);
    }

    /// Expect pass:
    /// - User creates a buy order for 250e18 tokens.
    function testBuyOrder_above_1e18() public {
        testStartPresale();

        vm.startPrank(deployer);

        vm.warp(block.timestamp + 5);

        assertEq(usdc.balanceOf(deployer), 1_000e6);
        usdc.approve(address(presale), 1_000e6);
        presale.createBuyOrder(250e18, address(usdc));

        vm.stopPrank();

        assertEq(usdc.balanceOf(address(presale)), 125e5);
        assertEq(usdc.balanceOf(deployer), 1_000e6 - 125e5);

        (, , uint256 _usdc, uint256 _tokens, ) = presale.receipt(deployer);
        assertEq(_tokens, 250e18);
        assertEq(_usdc, 125e5);
    }

    /// Expect revert.
    /// - The issue: User tries to buy 100000009999999999999.
    /// - Reverts bc it isn't divisible by 1e18.
    function testBuyOrder_precision_abuse() public {
        testStartPresale();

        vm.startPrank(deployer);

        vm.warp(block.timestamp + 5);

        assertEq(usdc.balanceOf(deployer), 1_000e6);
        usdc.approve(address(presale), 1_000e6);
        uint120 buying = 100000009999999999999;

        vm.expectRevert(
            abi.encodeWithSelector(ModularError.selector, 1e18, 9999999999999)
        );
        presale.createBuyOrder(buying, address(usdc));

        vm.stopPrank();
    }

    /// Expect revert.
    /// - The issue: User tries to buy 9999999999999
    /// - Reverts bc it isn't divisible by 1e18.
    function testBuyOrder_below_1e18() public {
        testStartPresale();

        vm.startPrank(deployer);

        vm.warp(block.timestamp + 5);

        assertEq(usdc.balanceOf(deployer), 1_000e6);
        usdc.approve(address(presale), 1_000e6);
        uint120 buying = 9999999999999;

        vm.expectRevert(
            abi.encodeWithSelector(ModularError.selector, 1e18, 9999999999999)
        );
        presale.createBuyOrder(buying, address(usdc));

        vm.stopPrank();
    }

    /// Expect pass.
    /// - The issue: User tries to buy 1e18
    function testBuyOrder_exactly_1e18() public {
        testStartPresale();

        vm.startPrank(deployer);

        vm.warp(block.timestamp + 5);

        assertEq(usdc.balanceOf(deployer), 1_000e6);
        usdc.approve(address(presale), 1_000e6);
        uint120 buying = 1e18;

        presale.createBuyOrder(buying, address(usdc));

        vm.stopPrank();
    }

    /// Expect revert:
    /// - User attempts to claim with no root set.
    function testClaim_root_not_set() public {
        testBuyOrder_above_1e18();

        vm.warp(block.timestamp + 16);

        vm.prank(deployer);
        bytes32[] memory proof = new bytes32[](2);
        proof[0] = bytes32(
            0xbf43232ec48fc7a41b395ef85562900fee8c1d89d497673be068fc4c8f154aec
        );
        proof[1] = bytes32(
            0xa143f62d0c134dda9e9a749dd9d400ad0e2458b053426fcd4ff78a019099883e
        );

        vm.expectRevert(ClaimsNotOpen.selector);
        presale.claim(deployer, 250e18, 0, 0, 0, proof);
    }

    /// Expect pass:
    /// - Deployer sets root after sale ends.
    function testSetRoot() public {
        vm.warp(block.timestamp + 16);

        vm.prank(deployer);
        bytes32 root = bytes32(
            0x14ad8b71aa540fba7c7fb6a445baf9cb0be31a21b3d80930324f8fcfeb16fb4d
        );
        presale.setClaimRoot(root);

        assertEq(presale.claimRoot(), root);
    }

    /// Expect pass:
    /// - User claims their own allocation.
    function testClaim_by_sender() public {
        testBuyOrder_above_1e18();
        testSetRoot();

        vm.prank(deployer);
        bytes32[] memory proof = new bytes32[](2);
        proof[0] = bytes32(
            0xbf43232ec48fc7a41b395ef85562900fee8c1d89d497673be068fc4c8f154aec
        );
        proof[1] = bytes32(
            0xa143f62d0c134dda9e9a749dd9d400ad0e2458b053426fcd4ff78a019099883e
        );
        presale.claim(deployer, 250e18, 0, 0, 0, proof);

        assertEq(stfxToken.balanceOf(address(presale)), 500e18 - 250e18);
        assertEq(stfxToken.balanceOf(deployer), 250e18);
    }

    /// Expect pass:
    /// - User claims another user's allocation for them.
    function testClaim_by_another_user() public {
        testBuyOrder_above_1e18();
        testSetRoot();

        vm.prank(address(0xBEEF));
        bytes32[] memory proof = new bytes32[](2);
        proof[0] = bytes32(
            0xbf43232ec48fc7a41b395ef85562900fee8c1d89d497673be068fc4c8f154aec
        );
        proof[1] = bytes32(
            0xa143f62d0c134dda9e9a749dd9d400ad0e2458b053426fcd4ff78a019099883e
        );
        presale.claim(deployer, 250e18, 0, 0, 0, proof);

        assertEq(stfxToken.balanceOf(address(presale)), 500e18 - 250e18);
        assertEq(stfxToken.balanceOf(deployer), 250e18);
    }

    /// Expect revert:
    /// - User attempts to claim with made-up params.
    function testClaim_wrong_node_params() public {
        testBuyOrder_above_1e18();
        testSetRoot();

        vm.prank(deployer);
        bytes32[] memory proof = new bytes32[](2);
        proof[0] = bytes32(
            0xbf43232ec48fc7a41b395ef85562900fee8c1d89d497673be068fc4c8f154aec
        );
        proof[1] = bytes32(
            0xa143f62d0c134dda9e9a749dd9d400ad0e2458b053426fcd4ff78a019099883e
        );

        vm.expectRevert(abi.encodeWithSelector(InvalidProof.selector));
        presale.claim(deployer, 250e18, 125e18, 0, 0, proof);
    }

    /// Expects revert:
    /// - User attempts to claim using someone elses's proof params, replacing the `user` param.
    function testClaim_invalid_proof() public {
        testBuyOrder_above_1e18();
        testSetRoot();

        vm.prank(address(0xBEEF));
        bytes32[] memory proof = new bytes32[](2);
        proof[0] = bytes32(
            0xbf43232ec48fc7a41b395ef85562900fee8c1d89d497673be068fc4c8f154aec
        );
        proof[1] = bytes32(
            0xa143f62d0c134dda9e9a749dd9d400ad0e2458b053426fcd4ff78a019099883e
        );

        vm.expectRevert(abi.encodeWithSelector(InvalidProof.selector));
        presale.claim(address(0xBEEF), 250e18, 0, 0, 0, proof);
    }

    /// Expects revert:
    /// - User claims successfully once, then attempts to claim again.
    function testClaim_already_claimed() public {
        testClaim_by_sender();
        testSetRoot();

        vm.prank(deployer);
        bytes32[] memory proof = new bytes32[](2);
        proof[0] = bytes32(
            0xbf43232ec48fc7a41b395ef85562900fee8c1d89d497673be068fc4c8f154aec
        );
        proof[1] = bytes32(
            0xa143f62d0c134dda9e9a749dd9d400ad0e2458b053426fcd4ff78a019099883e
        );

        (, , , , bool claimed) = presale.receipt(deployer);
        assertTrue(claimed);

        vm.expectRevert(abi.encodeWithSelector(AlreadyClaimed.selector));
        presale.claim(deployer, 250e18, 0, 0, 0, proof);
    }

    /// Expect pass:
    /// - User creates a buy order for 250e18 tokens w/ DAI.
    function testBuyOrder_dai() public {
        testBuyOrder_above_1e18();

        vm.startPrank(deployer);

        assertEq(dai.balanceOf(deployer), 1_000e18);
        dai.approve(address(presale), 1_000e18);
        presale.createBuyOrder(50e18, address(dai));

        vm.stopPrank();

        assertEq(dai.balanceOf(address(presale)), 25e17);
        assertEq(dai.balanceOf(deployer), 1_000e18 - 25e17);

        (uint256 _dai, , uint256 _usdc, uint256 _tokens, ) = presale.receipt(
            deployer
        );
        assertEq(_dai, 25e17);
        assertEq(_tokens, 250e18 + 50e18);
        assertEq(_usdc, 125e5);
    }

    /// Expect pass:
    /// - User claims their own allocation.
    function testClaim_dai() public {
        testBuyOrder_dai();
        testSetRoot();

        vm.prank(deployer);
        bytes32[] memory proof = new bytes32[](2);
        proof[0] = bytes32(
            0x91fa7ab2e733260d8b0ea8319e7d400aa9a4fea78f7f642c82bad79c55005534
        );
        proof[1] = bytes32(
            0x700d0be68d4459f95844e3ed504fb71baaac5ff9992b2eb709dc915326f4f110
        );
        presale.claim(deployer, 50e18, 0, 0, 0, proof);

        assertEq(stfxToken.balanceOf(address(presale)), 500e18 - 50e18);
        assertEq(stfxToken.balanceOf(deployer), 50e18);
    }

    /// Expects pass:
    /// - Protocol claims all the used USDC and unused STFX tokens.
    function testClaim_by_protocol() public {
        testBuyOrder_dai();
        testSetRoot();

        vm.startPrank(deployer);
        bytes32[] memory proof = new bytes32[](2);
        proof[0] = bytes32(
            0x76a852e3eb5928fef11b51eadbbb75e6fce7d8fda9b1031bc53437cd3386e11b
        );
        proof[1] = bytes32(
            0x700d0be68d4459f95844e3ed504fb71baaac5ff9992b2eb709dc915326f4f110
        );

        uint256 before_stfx_bal = stfxToken.balanceOf(address(deployer));
        uint256 before_usdc_bal = usdc.balanceOf(address(deployer));
        uint256 before_dai_bal = dai.balanceOf(address(deployer));
        presale.claim(
            deployer,
            200000000000000000000,
            12500000,
            0,
            25000000000000000,
            proof
        );

        assertEq(usdc.balanceOf(address(deployer)), before_usdc_bal + 12500000);
        assertEq(
            dai.balanceOf(address(deployer)),
            before_dai_bal + 25000000000000000
        );
        assertEq(
            stfxToken.balanceOf(address(deployer)),
            before_stfx_bal + 200e18
        );
    }
}
