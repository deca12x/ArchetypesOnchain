// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import {Script, console2} from "forge-std/Script.sol";

contract SendMNT is Script {
    // Array of recipient addresses
    address[12] recipients = [
        0x2973BFb328DCb32933De3b14FcED06f36812c215,
        0x2Aa9a61f337773D189577E90115267678c7FaADF,
        0x4e81431A427F9A09efC64723ba5E8aDaf55f6863,
        0x65478DF7bBa7E43a0d5B8902643f7e0CBD148674,
        0x93bFE6e5B13005d63ca8952D6d782d937C7a625A,
        0xfC85E784628e887235c2e434a6097eaCF637b54c,
        0x3C34bFe46b663D3BB6fDc6109a55Bae65c479A1e,
        0xEa7Aa383a34046fe6BfbCf2eB86C3E5591A3794c,
        0x6a53f98DA82fF6FC211E7Bc2aB045F13Df0aF6Ed,
        0xdB33e10D4C1394aEf4aD2B91ded0F9e09abbA84A,
        0x4765860835D04bB39009FFb97772bdA2b3159715,
        0x6F4c09F3F4F8c5a312639D56787F01CBf418aC53
    ];

    function run() public {
        uint256 senderPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(senderPrivateKey);

        // Amount to send to each recipient (10 MNT = 10 * 10^18 wei)
        uint256 amountPerRecipient = 10 ether;

        // Send MNT to each recipient
        for (uint256 i = 0; i < recipients.length; i++) {
            (bool success,) = recipients[i].call{value: amountPerRecipient}("");
            require(success, string(abi.encodePacked("Failed to send MNT to recipient ", i)));
            console2.log("Sent", amountPerRecipient, "wei to", recipients[i]);
        }

        vm.stopBroadcast();
    }
}
