// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./GameBase.t.sol";

contract GameMovesTest is GameBaseTest {
    function setUp() public override {
        super.setUp();
        joinAllPlayers();
    }

    function testCooldownEnforcement() public {
        // Find a Hero character
        address heroPlayer = findPlayerWithCharacter(Game.CharacterType.Hero);

        // Use the Hero's inspire alliance move
        vm.prank(heroPlayer);
        game.inspireAlliance(heroPlayer, players[0]);

        // Try using it again immediately (should fail due to cooldown)
        vm.prank(heroPlayer);
        vm.expectRevert();
        game.inspireAlliance(heroPlayer, players[1]);

        // Advance time past cooldown (4 minutes)
        vm.warp(block.timestamp + 4 * 60 + 1);

        // Should succeed now
        vm.prank(heroPlayer);
        game.inspireAlliance(heroPlayer, players[1]);
    }

    function testIdlePlayerMechanics() public {
        // Record an initial player's character type
        address idlePlayer = players[5];
        Game.CharacterType playerChar = getCharacterType(idlePlayer);

        // Make player idle for 7+ minutes
        vm.warp(block.timestamp + 7 * 60 + 1);

        // Another player should be able to use idle player's moves
        vm.prank(players[0]);

        // Determine which move to use based on character type
        if (playerChar == Game.CharacterType.Hero) {
            game.inspireAlliance(idlePlayer, players[1]);
        } else if (playerChar == Game.CharacterType.Explorer) {
            game.discover(idlePlayer);
        } else if (playerChar == Game.CharacterType.Innocent) {
            game.purify(idlePlayer);
        }
    }

    function testCharacterTypeVerification() public {
        // Find a non-Hero character
        address nonHeroPlayer;
        for (uint i = 0; i < 12; i++) {
            if (getCharacterType(players[i]) != Game.CharacterType.Hero) {
                nonHeroPlayer = players[i];
                break;
            }
        }

        // Try using Hero-specific move with non-Hero character
        vm.prank(nonHeroPlayer);
        vm.expectRevert("Character cannot use this move");
        game.inspireAlliance(nonHeroPlayer, players[0]);
    }

    function testUniqueMoves() public {
        // Test Artist's unique move
        address artistPlayer = findPlayerWithCharacter(
            Game.CharacterType.Artist
        );

        vm.prank(artistPlayer);
        game.createEnchantedKey(artistPlayer);

        (, , , uint8 enchantedKeys, , , , ) = game.playerData(artistPlayer);
        assertEq(enchantedKeys, 1);
    }

    function testSharedMoves() public {
        // Test a move that multiple character types can use
        // Find Artist and Wizard (both can use ForgeKey)
        address artistPlayer = findPlayerWithCharacter(
            Game.CharacterType.Artist
        );
        address wizardPlayer = findPlayerWithCharacter(
            Game.CharacterType.Wizard
        );

        // Both should be able to use ForgeKey
        vm.prank(artistPlayer);
        game.forgeKey(artistPlayer);

        (, , uint8 artistKeys, , , , , ) = game.playerData(artistPlayer);
        assertEq(artistKeys, 1);

        // Wait for cooldown
        vm.warp(block.timestamp + 3 * 60 + 1);

        vm.prank(wizardPlayer);
        game.forgeKey(wizardPlayer);

        (, , uint8 wizardKeys, , , , , ) = game.playerData(wizardPlayer);
        assertEq(wizardKeys, 1);
    }
}
