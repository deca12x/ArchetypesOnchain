// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./GameBase.t.sol";

contract GameEndToEndTest is GameBaseTest {
    address artistPlayer;
    address heroPlayer;
    address wizardPlayer;
    address innocentPlayer;

    function setUp() public override {
        super.setUp();
        joinAllPlayers();

        // Find the players with the required character types
        artistPlayer = findPlayerWithCharacter(GameCore.CharacterType.Artist);
        heroPlayer = findPlayerWithCharacter(GameCore.CharacterType.Hero);
        wizardPlayer = findPlayerWithCharacter(GameCore.CharacterType.Wizard);
        innocentPlayer = findPlayerWithCharacter(
            GameCore.CharacterType.Innocent
        );

        // Advance timestamp past the cooldown period
        vm.warp(block.timestamp + 20 * 60 + 1);
    }

    function testArtistForgeAndGift() public {
        // Log initial states
        console.log("Artist address:", artistPlayer);
        console.log("Hero address:", heroPlayer);

        // Step 1: Artist creates a key
        vm.prank(artistPlayer);
        GameMoves.MoveParams memory params = GameMoves.MoveParams({
            moveType: GameCore.MoveType.ForgeKey,
            actor: artistPlayer,
            targetPlayer: address(0),
            useItem: false
        });
        game.executeMove(params);

        // Verify key was created
        assertTrue(
            playerHasKeys(artistPlayer, 1),
            "Artist should have 1 key after ForgeKey"
        );

        // Log pre-gift state
        console.log("Before Gift - Artist keys:", getPlayerKeys(artistPlayer));
        console.log("Before Gift - Hero keys:", getPlayerKeys(heroPlayer));

        // Step 2: Artist gifts the key to Hero
        vm.prank(artistPlayer);
        params.moveType = GameCore.MoveType.Gift;
        params.targetPlayer = heroPlayer;
        game.executeMove(params);

        // Log post-gift state
        console.log("After Gift - Artist keys:", getPlayerKeys(artistPlayer));
        console.log("After Gift - Hero keys:", getPlayerKeys(heroPlayer));

        // Verify key transfer
        assertTrue(
            playerHasKeys(heroPlayer, 1),
            "Hero should have 1 key after gift"
        );
        assertTrue(
            playerHasKeys(artistPlayer, 0),
            "Artist should have 0 keys after gift"
        );
    }

    function testHeroUnlock() public {
        testArtistForgeAndGift();

        // Hero uses key to unlock padlock
        vm.prank(heroPlayer);
        GameMoves.MoveParams memory params = GameMoves.MoveParams({
            moveType: GameCore.MoveType.UnlockChest,
            actor: heroPlayer,
            targetPlayer: address(0),
            useItem: false
        });
        game.executeMove(params);

        assertEq(game.padlocks(), 0, "Padlock should be unlocked");
        assertEq(game.seals(), 1, "Seal should remain");
    }

    // Helper function to get player's key count
    function getPlayerKeys(address player) internal view returns (uint8) {
        (, , uint8 keys, , , , bool joined, , ) = game.playerData(player);
        require(joined, "Player not joined");
        return keys;
    }
}
