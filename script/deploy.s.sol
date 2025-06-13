// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import {Script, console2} from "forge-std/Script.sol";

import "../src/GameMoves.sol";

contract Deploy is Script {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY1");
        vm.startBroadcast(deployerPrivateKey);
        new GameMoves();
        vm.stopBroadcast();
    }
}
