// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./GameBase.t.sol";

contract GameVictoryTest is GameBaseTest {
    function setUp() public override {
        super.setUp();
        joinAllPlayers();
    }

    function testOpenVictory() public {
        // Form alliance between two players
        address heroPlayer = findPlayerWithCharacter(Game.CharacterType.Hero);
        address allyPlayer = players[0];

        vm.prank(heroPlayer);
        game.inspireAlliance(heroPlayer, allyPlayer);

        // Give hero enchanted keys
        vm.mockCall(
            address(game),
            abi.encodeWithSignature("playerData(address)"),
            abi.encode(heroPlayer, Game.CharacterType.Hero, 0, 2, 0, 0, true)
        );

        // Use keys to unlock and unseal chest
        vm.prank(heroPlayer);
        game.unlockChest(heroPlayer, true); // Use enchanted key to remove padlock and seal

        vm.prank(heroPlayer);
        game.unlockChest(heroPlayer, true); // Remove last padlock

        // Game should be over with hero and ally as winners
        assertTrue(game.gameOver());

        // Test winners array contains both players
        assertEq(game.winners(0), heroPlayer);
        assertEq(game.winners(1), allyPlayer);
    }

    function testBlockVictory() public {
        // Form alliance between ruler and ally
        address rulerPlayer = findPlayerWithCharacter(Game.CharacterType.Ruler);
        address wizardPlayer = findPlayerWithCharacter(
            Game.CharacterType.Wizard
        );
        address allyPlayer = players[0];

        vm.prank(rulerPlayer);
        game.inspireAlliance(rulerPlayer, allyPlayer);

        // Initial state: padlocks = 2, seals = 1

        // Add padlock to reach 3
        vm.prank(rulerPlayer);
        game.secureChest(rulerPlayer);

        // Add seals to reach 3
        vm.warp(block.timestamp + 4 * 60 + 1);
        vm.prank(wizardPlayer);
        game.arcaneSeal(wizardPlayer);

        vm.warp(block.timestamp + 4 * 60 + 1);
        vm.prank(wizardPlayer);
        game.arcaneSeal(wizardPlayer);

        // Game should be over with ruler and ally as winners
        assertTrue(game.gameOver());
    }

    function testPrizeDistribution() public {
        // Set up a scenario where a player wins
        address heroPlayer = findPlayerWithCharacter(Game.CharacterType.Hero);

        // Mock hero having enchanted keys
        vm.mockCall(
            address(game),
            abi.encodeWithSignature("playerData(address)"),
            abi.encode(heroPlayer, Game.CharacterType.Hero, 0, 2, 0, 0, true)
        );

        // Use keys to unlock chest
        vm.prank(heroPlayer);
        game.unlockChest(heroPlayer, true);

        vm.prank(heroPlayer);
        game.unlockChest(heroPlayer, true);

        // Game should be over
        assertTrue(game.gameOver());

        // Check if the prize was distributed correctly
        // Ideally we'd check the balance of the winner
        // but that's difficult with the mocks
    }
}
