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

    function testEndToEndGameplayOpenVictory() public {
        // Record initial balances
        uint256 initialWizardBalance = address(wizardPlayer).balance;
        uint256 initialInnocentBalance = address(innocentPlayer).balance;

        // 1. Chest has 1 padlock and 1 seal
        assertEq(game.padlocks(), 1, "Chest should initially have 1 padlock");
        assertEq(game.seals(), 1, "Chest should initially have 1 seal");

        // 2. Artist has 0 keys and Hero has 0 keys
        assertTrue(
            playerHasKeys(artistPlayer, 0),
            "Artist should have 0 keys initially"
        );
        assertTrue(
            playerHasKeys(heroPlayer, 0),
            "Hero should have 0 keys initially"
        );

        // 3. Artist calls Forge Key successfully
        vm.prank(artistPlayer);
        GameMoves.MoveParams memory params = GameMoves.MoveParams({
            moveType: GameCore.MoveType.ForgeKey,
            actor: artistPlayer,
            targetPlayer: address(0),
            useItem: false
        });
        game.executeMove(params);

        // 4. Artist has 1 key and Hero has 0 keys
        assertTrue(
            playerHasKeys(artistPlayer, 1),
            "Artist should have 1 key after ForgeKey"
        );
        assertTrue(
            playerHasKeys(heroPlayer, 0),
            "Hero should still have 0 keys"
        );

        // 5. Artist gifts key to Hero
        vm.prank(artistPlayer);
        params = GameMoves.MoveParams({
            moveType: GameCore.MoveType.Gift,
            actor: artistPlayer,
            targetPlayer: heroPlayer,
            useItem: false
        });
        game.executeMove(params);

        // 6. Artist and Hero are now allied
        address artistRoot = game.getDsuParent(artistPlayer);
        address heroRoot = game.getDsuParent(heroPlayer);
        assertEq(
            artistRoot,
            heroRoot,
            "Artist and Hero should be in the same alliance"
        );

        // 7. Artist has 0 keys and Hero has 1 key
        assertTrue(
            playerHasKeys(artistPlayer, 0),
            "Artist should have 0 keys after gift"
        );
        assertTrue(
            playerHasKeys(heroPlayer, 1),
            "Hero should have 1 key after gift"
        );

        // 8. Hero calls Unlock Chest successfully
        vm.prank(heroPlayer);
        params = GameMoves.MoveParams({
            moveType: GameCore.MoveType.UnlockChest,
            actor: heroPlayer,
            targetPlayer: address(0),
            useItem: false
        });
        game.executeMove(params);

        // 9. Chest has 0 padlocks and 1 seal
        assertEq(
            game.padlocks(),
            0,
            "Chest should have 0 padlocks after unlock"
        );
        assertEq(game.seals(), 1, "Chest should still have 1 seal");

        // 10. Wizard has 0 staffs and Innocent has 0 staffs
        assertTrue(
            playerHasStaffs(wizardPlayer, 0),
            "Wizard should have 0 staffs initially"
        );
        assertTrue(
            playerHasStaffs(innocentPlayer, 0),
            "Innocent should have 0 staffs initially"
        );

        // 11. Wizard calls Conjure Staff successfully
        vm.prank(wizardPlayer);
        params = GameMoves.MoveParams({
            moveType: GameCore.MoveType.ConjureStaff,
            actor: wizardPlayer,
            targetPlayer: address(0),
            useItem: false
        });
        game.executeMove(params);

        // 12. Wizard has 1 staff and Innocent has 0 staffs
        assertTrue(
            playerHasStaffs(wizardPlayer, 1),
            "Wizard should have 1 staff after ConjureStaff"
        );
        assertTrue(
            playerHasStaffs(innocentPlayer, 0),
            "Innocent should still have 0 staffs"
        );

        // 13. Wizard gifts staff to Innocent
        vm.prank(wizardPlayer);
        params = GameMoves.MoveParams({
            moveType: GameCore.MoveType.Gift,
            actor: wizardPlayer,
            targetPlayer: innocentPlayer,
            useItem: false
        });
        game.executeMove(params);

        // 14. Wizard and Innocent are now allied
        address wizardRoot = game.getDsuParent(wizardPlayer);
        address innocentRoot = game.getDsuParent(innocentPlayer);
        assertEq(
            wizardRoot,
            innocentRoot,
            "Wizard and Innocent should be in the same alliance"
        );

        // 15. Wizard has 0 staffs and Innocent has 1 staff
        assertTrue(
            playerHasStaffs(wizardPlayer, 0),
            "Wizard should have 0 staffs after gift"
        );
        assertTrue(
            playerHasStaffs(innocentPlayer, 1),
            "Innocent should have 1 staff after gift"
        );

        // 16. Innocent successfully calls Unseal Chest
        vm.prank(innocentPlayer);
        params = GameMoves.MoveParams({
            moveType: GameCore.MoveType.UnsealChest,
            actor: innocentPlayer,
            targetPlayer: address(0),
            useItem: false
        });
        game.executeMove(params);

        // 17. Winning condition is triggered, the entire chest funds are split evenly between Wizard and Innocent
        assertTrue(game.gameOver(), "Game should be over");

        // Check winners and prize distribution
        uint256 winnerCount = 0;
        bool wizardIsWinner = false;
        bool innocentIsWinner = false;

        for (uint256 i = 0; i < game.NUM_PLAYERS(); i++) {
            try game.winners(i) returns (address winner) {
                winnerCount++;
                if (winner == wizardPlayer) {
                    wizardIsWinner = true;
                }
                if (winner == innocentPlayer) {
                    innocentIsWinner = true;
                }
            } catch {
                break;
            }
        }

        assertTrue(winnerCount == 2, "There should be exactly 2 winners");
        assertTrue(wizardIsWinner, "Wizard should be a winner");
        assertTrue(innocentIsWinner, "Innocent should be a winner");

        // Verify prize distribution
        uint256 finalWizardBalance = address(wizardPlayer).balance;
        uint256 finalInnocentBalance = address(innocentPlayer).balance;

        assertTrue(
            finalWizardBalance > initialWizardBalance,
            "Wizard should have received prize money"
        );
        assertTrue(
            finalInnocentBalance > initialInnocentBalance,
            "Innocent should have received prize money"
        );

        // Check that prize was split evenly
        uint256 wizardPrize = finalWizardBalance - initialWizardBalance;
        uint256 innocentPrize = finalInnocentBalance - initialInnocentBalance;

        assertEq(wizardPrize, innocentPrize, "Prizes should be equal");
    }

    // Helper function to get player's key count
    function getPlayerKeys(address player) internal view returns (uint8) {
        (, , uint8 keys, , , , bool joined, , ) = game.playerData(player);
        require(joined, "Player not joined");
        return keys;
    }
}
