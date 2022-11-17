// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "../lib/forge-std/src/Test.sol";
import {STFXToken} from "../src/STFXToken.sol";

contract STFXTokenTest is Test {
    STFXToken internal stfxToken;

    function setUp() public {
        vm.prank(address(0xBEEF));
        stfxToken = new STFXToken();
    }

    function testMintAll() public {
        assertEq(stfxToken.balanceOf(address(0xBEEF)), 0);
        vm.prank(address(0xBEEF));
        stfxToken.mint(address(0xBEEF), 1_000_000e18);
        assertEq(stfxToken.balanceOf(address(0xBEEF)), 1_000_000e18);
    }

    function testFailMintOverflow() public {
        testMintAll();
        vm.prank(address(0xBEEF));
        stfxToken.mint(address(0xBEEF), 1);
    }
}
