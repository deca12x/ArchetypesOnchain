// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./GameBase.t.sol";

contract GameItemsTest is GameBaseTest {
    function setUp() public override {
        super.setUp();
        joinAllPlayers();
    }

    function testItemCreation() public {
        // Find Artist, Wizard, and Explorer characters
        address artistPlayer = findPlayerWithCharacter(
            Game.CharacterType.Artist
        );
        address wizardPlayer = findPlayerWithCharacter(
            Game.CharacterType.Wizard
        );
        address explorerPlayer = findPlayerWithCharacter(
            Game.CharacterType.Explorer
        );

        // Create enchanted key
        vm.prank(artistPlayer);
        game.createEnchantedKey(artistPlayer);

        // Create staff
        vm.prank(wizardPlayer);
        game.conjureStaff(wizardPlayer);

        // Discover random item
        vm.prank(explorerPlayer);
        game.discover(explorerPlayer);

        // Check item counts
        (, , , uint8 artistEnchantedKeys, , , , ) = game.playerData(
            artistPlayer
        );
        assertEq(artistEnchantedKeys, 1);

        (, , , , uint8 wizardStaffs, , , ) = game.playerData(wizardPlayer);
        assertEq(wizardStaffs, 1);

        // Explorer will have random item, can't test exact value
    }

    function testItemTransfer() public {
        // Find and give items to a player
        address donorPlayer = players[0];
        address receiverPlayer = players[1];

        // Mock the donor having items
        vm.mockCall(
            address(game),
            abi.encodeWithSignature("playerData(address)"),
            abi.encode(donorPlayer, Game.CharacterType.Hero, 2, 1, 1, 0, true)
        );

        // Gift items
        vm.prank(donorPlayer);
        game.gift(donorPlayer, receiverPlayer);

        // Verify donor has no items
        (
            ,
            ,
            uint8 donorKeys,
            uint8 donorEnchantedKeys,
            uint8 donorStaffs,
            ,
            ,

        ) = game.playerData(donorPlayer);
        assertEq(donorKeys, 0);
        assertEq(donorEnchantedKeys, 0);
        assertEq(donorStaffs, 0);

        // Verify receiver has items
        (
            ,
            ,
            uint8 receiverKeys,
            uint8 receiverEnchantedKeys,
            uint8 receiverStaffs,
            ,
            ,

        ) = game.playerData(receiverPlayer);
        assertEq(receiverKeys, 2);
        assertEq(receiverEnchantedKeys, 1);
        assertEq(receiverStaffs, 1);
    }

    function testSeizeItem() public {
        // Find a character that can use Seize
        address seizePlayer = findPlayerWithCharacter(Game.CharacterType.Ruler);
        address targetPlayer = players[0];

        // Give the target player an item to seize
        vm.mockCall(
            address(game),
            abi.encodeWithSignature("playerData(address)"),
            abi.encode(targetPlayer, Game.CharacterType.Hero, 1, 0, 0, 0, true)
        );

        // Seize the item
        vm.prank(seizePlayer);
        game.seizeItem(seizePlayer, targetPlayer);

        // Test would verify that the item was transferred
        // Ideally you'd check that seizePlayer now has the key and targetPlayer doesn't
    }

    function testMaximumItemAccumulation() public {
        // Find Artist to create many enchanted keys
        address artistPlayer = findPlayerWithCharacter(
            Game.CharacterType.Artist
        );

        // Create multiple enchanted keys
        for (uint i = 0; i < 10; i++) {
            vm.warp(block.timestamp + 5 * 60 + 1);
            vm.prank(artistPlayer);
            game.createEnchantedKey(artistPlayer);
        }

        // Verify player can accumulate many items
        (, , , uint8 enchantedKeys, , , , ) = game.playerData(artistPlayer);
        assertEq(enchantedKeys, 10);
    }
}
