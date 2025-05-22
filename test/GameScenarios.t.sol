// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./GameBase.t.sol";

contract GameScenariosTest is GameBaseTest {
    function setUp() public override {
        super.setUp();
        joinAllPlayers();
    }

    function testBlockVictoryScenario() public {
        // This test simulates a complete game where players work together to achieve a block victory

        // Find necessary character types
        address rulerPlayer = findPlayerWithCharacter(Game.CharacterType.Ruler);
        address wizardPlayer = findPlayerWithCharacter(
            Game.CharacterType.Wizard
        );
        address sagePlayer = findPlayerWithCharacter(Game.CharacterType.Sage);
        address caregiverPlayer = findPlayerWithCharacter(
            Game.CharacterType.Caregiver
        );

        // Step 1: Form alliances
        vm.prank(rulerPlayer);
        game.inspireAlliance(rulerPlayer, wizardPlayer);

        vm.warp(block.timestamp + 5 * 60);
        vm.prank(caregiverPlayer);
        game.guardianBond(caregiverPlayer, rulerPlayer);

        // Step 2: Ruler adds padlock
        vm.warp(block.timestamp + 5 * 60);
        vm.prank(rulerPlayer);
        game.secureChest(rulerPlayer);

        // Step 3: Wizard adds first seal
        vm.warp(block.timestamp + 5 * 60);
        vm.prank(wizardPlayer);
        game.arcaneSeal(wizardPlayer);

        // Step 4: Sage adds second seal
        vm.warp(block.timestamp + 5 * 60);
        vm.prank(sagePlayer);
        game.arcaneSeal(sagePlayer);

        // Verify game state
        assertEq(game.padlocks(), 3);
        assertEq(game.seals(), 3);

        // Verify game is over and alliance members won
        assertTrue(game.gameOver());
        // Here we'd verify the winners array contains all alliance members
    }

    function testOpenVictoryScenario() public {
        // This test simulates a complete game where players work together to open the chest

        // Find necessary character types
        address heroPlayer = findPlayerWithCharacter(Game.CharacterType.Hero);
        address loverPlayer = findPlayerWithCharacter(Game.CharacterType.Lover);
        address artistPlayer = findPlayerWithCharacter(
            Game.CharacterType.Artist
        );
        address innocentPlayer = findPlayerWithCharacter(
            Game.CharacterType.Innocent
        );

        // Step 1: Form alliances
        vm.prank(heroPlayer);
        game.inspireAlliance(heroPlayer, artistPlayer);

        vm.warp(block.timestamp + 5 * 60);
        vm.prank(loverPlayer);
        game.soulBond(loverPlayer, heroPlayer);

        // Step 2: Create items
        vm.warp(block.timestamp + 5 * 60);
        vm.prank(artistPlayer);
        game.createEnchantedKey(artistPlayer);

        // Step 3: Transfer items to hero
        vm.warp(block.timestamp + 5 * 60);

        // Mock artist having items
        vm.mockCall(
            address(game),
            abi.encodeWithSignature("playerData(address)"),
            abi.encode(
                artistPlayer,
                Game.CharacterType.Artist,
                0,
                1,
                0,
                0,
                true
            )
        );

        vm.prank(artistPlayer);
        game.gift(artistPlayer, heroPlayer);

        // Step 4: Remove seal with Innocent
        vm.warp(block.timestamp + 5 * 60);
        vm.prank(innocentPlayer);
        game.purify(innocentPlayer);

        // Step 5: Hero unlocks padlocks
        vm.warp(block.timestamp + 5 * 60);

        // Mock hero having enchanted keys
        vm.mockCall(
            address(game),
            abi.encodeWithSignature("playerData(address)"),
            abi.encode(heroPlayer, Game.CharacterType.Hero, 0, 1, 0, 0, true)
        );

        vm.prank(heroPlayer);
        game.unlockChest(heroPlayer, true);

        // Verify chest is open
        assertEq(game.padlocks(), 1);
        assertEq(game.seals(), 0);

        // Give hero another key
        vm.mockCall(
            address(game),
            abi.encodeWithSignature("playerData(address)"),
            abi.encode(heroPlayer, Game.CharacterType.Hero, 1, 0, 0, 0, true)
        );

        // Remove last padlock
        vm.prank(heroPlayer);
        game.unlockChest(heroPlayer, false);

        // Verify game is over and alliance members won
        assertTrue(game.gameOver());
        // Here we'd verify the winners array contains all alliance members
    }
}
