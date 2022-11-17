// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "../lib/forge-std/src/Script.sol";

import "../test/MockUSDC.sol";
import "../test/MockERC20.sol";
import "../src/STFXToken.sol";
import "../src/Presale.sol";

/**
# To load the variables in the .env file
source .env

# To deploy and verify our contract
forge script script/Deploy.s.sol:MyScript --rpc-url $GOERLI_RPC_URL --broadcast --verify -vvvv
forge script script/Deploy.s.sol:MyScript --rpc-url $GOERLI_RPC_URL --broadcast --verifier-url $VERIFIER_URL -vvvv
 --verifier-url

# To flattern
forge flatten [name]file --output [file]
 */
contract MyScript is Script {
    function run() external {
        address deployerPub = vm.envAddress("PUBLIC_KEY");
        uint256 deployerPriv = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPriv);

        MockUSDC usdc = new MockUSDC();
        MockUSDC usdt = new MockUSDC();
        MockERC20 dai = new MockERC20();
        STFXToken stfx = new STFXToken();

        Presale presale = new Presale(
            address(dai),
            address(usdt),
            address(usdc),
            address(stfx)
        );

        usdc.mint(deployerPub, 1_000e6);
        stfx.mint(deployerPub, 500e18);

        usdc.approve(address(presale), 1_000e6);
        stfx.approve(address(presale), 500e18);

        presale.initialise(
            uint40(block.timestamp + 10),
            uint40(6 hours),
            500e18,
            5e4
        );

        vm.stopBroadcast();
    }
}

/*
source .env
forge script script/Deploy.s.sol:StartSale --rpc-url $GOERLI_RPC_URL --broadcast -vvvv
*/
contract StartSale is Script {
    function run() external {
        uint256 deployerPriv = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPriv);

        execute();

        vm.stopBroadcast();
    }

    function execute() internal {
        address deployerPub = vm.envAddress("PUBLIC_KEY");

        // Use existing deployments
        MockERC20 dai = MockERC20(0xBcaf3cAb324a1241E456D372AB9aDE8554AF91EC);
        MockUSDC usdc = MockUSDC(0x6ab8A066998baB709953A933fd7f7BDa0fA6c913);
        STFXToken stfx = STFXToken(0x4b31F8eaE29F30cAaDF94EF22C5Fe9F8691f5F17);
        Presale presale = Presale(0x3cd1453Cb3170AEB9482360fAbE7ea8fC6aa2071);

        // Mint dai to deployer
        dai.mint(deployerPub, 1_000e18);
        usdc.mint(deployerPub, 1_000e6);
        stfx.mint(deployerPub, 500e18);

        // Mint dai to user 1
        dai.mint(0xd202E20fF8E124278cD6A83A26bE21c71f9da7C2, 1_000e18);
        usdc.mint(0xd202E20fF8E124278cD6A83A26bE21c71f9da7C2, 1_000e6);
        stfx.mint(0xd202E20fF8E124278cD6A83A26bE21c71f9da7C2, 500e18);

        // Mint dai to user 2
        dai.mint(0x258D365e432b18531f4736AA6128f256c144f55c, 1_000e18);
        usdc.mint(0x258D365e432b18531f4736AA6128f256c144f55c, 1_000e6);
        stfx.mint(0x258D365e432b18531f4736AA6128f256c144f55c, 500e18);

        // Approve deployer's
        dai.approve(address(presale), 1_000e18);
        usdc.approve(address(presale), 1_000e6);
        stfx.approve(address(presale), 500e18);

        presale.initialise(
            uint40(block.timestamp + 10),
            uint40(3 days),
            500e18,
            5e4
        );
    }
}
