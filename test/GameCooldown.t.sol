// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./GameBase.t.sol";

contract GameCooldownTest is GameBaseTest {
    function setUp() public override {
        super.setUp();
        joinAllPlayers();
    }

    function testInitialCooldownState() public {
        // Find a Hero character
        address heroPlayer = findPlayerWithCharacter(Game.CharacterType.Hero);

        // Verify the player can use a move immediately after game start
        vm.prank(heroPlayer);
        game.inspireAlliance(heroPlayer, players[1]);

        // The move should now be on cooldown
        vm.prank(heroPlayer);
        vm.expectRevert("Move on cooldown");
        game.inspireAlliance(heroPlayer, players[2]);

        // Log the current timestamp for reference
        console.log("Current timestamp:", block.timestamp);
    }

    function testMultipleCooldowns() public {
        // Test cooldowns for different moves
        address heroPlayer = findPlayerWithCharacter(Game.CharacterType.Hero);
        address wizardPlayer = findPlayerWithCharacter(
            Game.CharacterType.Wizard
        );

        // Hero uses a move (4 min cooldown)
        vm.prank(heroPlayer);
        game.inspireAlliance(heroPlayer, players[1]);

        // Advance time by 3 minutes (not enough for Hero's move)
        vm.warp(block.timestamp + 3 * 60);

        // Hero move should still be on cooldown
        vm.prank(heroPlayer);
        vm.expectRevert("Move on cooldown");
        game.inspireAlliance(heroPlayer, players[2]);

        // Wizard uses a move (5 min cooldown)
        vm.prank(wizardPlayer);
        game.conjureStaff(wizardPlayer);

        // Advance time by 2 more minutes (5 min total, enough for Hero but not Wizard)
        vm.warp(block.timestamp + 2 * 60);

        // Hero's move should now be available
        vm.prank(heroPlayer);
        game.inspireAlliance(heroPlayer, players[2]);

        // Wizard's move should still be on cooldown
        vm.prank(wizardPlayer);
        vm.expectRevert("Move on cooldown");
        game.conjureStaff(wizardPlayer);

        // Advance time by 1 more minute (6 min total, enough for Wizard)
        vm.warp(block.timestamp + 1 * 60);

        // Wizard's move should now be available
        vm.prank(wizardPlayer);
        game.conjureStaff(wizardPlayer);
    }

    function testZeroCooldownMoves() public {
        // Test moves with no cooldown
        address heroPlayer = findPlayerWithCharacter(Game.CharacterType.Hero);

        // Mock hero having keys
        vm.store(
            address(game),
            keccak256(abi.encode(heroPlayer, keccak256(abi.encode("keys")))),
            bytes32(uint256(1))
        );

        // Hero uses unlock chest (should have 0 cooldown)
        vm.prank(heroPlayer);
        game.unlockChest(heroPlayer, false);

        // Should be able to use it again immediately
        vm.prank(heroPlayer);
        game.unlockChest(heroPlayer, false);
    }

    function testCooldownAfterIdleTakeover() public {
        // Test cooldown when using another player's move
        address heroPlayer = findPlayerWithCharacter(Game.CharacterType.Hero);
        address player2 = players[1];

        // Make hero idle for 7+ minutes
        vm.warp(block.timestamp + 7 * 60 + 1);

        // Player2 uses hero's move
        vm.prank(player2);
        game.inspireAlliance(heroPlayer, players[3]);

        // Player2 should not be able to use hero's move again due to cooldown
        vm.prank(player2);
        vm.expectRevert("Move on cooldown");
        game.inspireAlliance(heroPlayer, players[4]);

        // Wait for cooldown to expire
        vm.warp(block.timestamp + 4 * 60 + 1);

        // Player2 should now be able to use hero's move again
        vm.prank(player2);
        game.inspireAlliance(heroPlayer, players[4]);
    }

    function testResetCooldownWithEnergyFlow() public {
        // Test Sage's ability to reset cooldowns
        address sagePlayer = findPlayerWithCharacter(Game.CharacterType.Sage);
        address heroPlayer = findPlayerWithCharacter(Game.CharacterType.Hero);

        // Create alliance between sage and hero
        vm.prank(sagePlayer);
        game.soulBond(sagePlayer, heroPlayer);

        // Hero uses a move
        vm.warp(block.timestamp + 4 * 60 + 1);
        vm.prank(heroPlayer);
        game.inspireAlliance(heroPlayer, players[1]);

        // Hero's move should be on cooldown
        vm.prank(heroPlayer);
        vm.expectRevert("Move on cooldown");
        game.inspireAlliance(heroPlayer, players[2]);

        // Sage uses Energy Flow to reset cooldowns
        vm.warp(block.timestamp + 5 * 60 + 1);
        vm.prank(sagePlayer);
        game.energyFlow(sagePlayer);

        // Hero's move should now be available
        vm.prank(heroPlayer);
        game.inspireAlliance(heroPlayer, players[2]);
    }
}
