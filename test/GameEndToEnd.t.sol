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

        // Have all players join the game
        joinAllPlayers();

        // Find the players with the required character types
        artistPlayer = findPlayerWithCharacter(GameCore.CharacterType.Artist);
        heroPlayer = findPlayerWithCharacter(GameCore.CharacterType.Hero);
        wizardPlayer = findPlayerWithCharacter(GameCore.CharacterType.Wizard);
        innocentPlayer = findPlayerWithCharacter(
            GameCore.CharacterType.Innocent
        );

        // After setting up the game but before calling any moves
        vm.warp(block.timestamp + 10 * 60 + 1); // Advance timestamp past the cooldown period
    }

    function testEndToEndGameplayVictory() public {
        // Record initial balances
        uint256 initialInnocentBalance = address(innocentPlayer).balance;
        uint256 initialWizardBalance = address(wizardPlayer).balance;

        // Initial state checks
        assertTrue(game.gameStarted());
        assertEq(game.padlocks(), 1);
        assertEq(game.seals(), 1);
        assertFalse(game.gameOver());

        // Step 1: Artist creates a key
        vm.prank(artistPlayer);
        GameMoves.MoveParams memory params = GameMoves.MoveParams({
            moveType: GameCore.MoveType.ForgeKey,
            actor: artistPlayer,
            targetPlayer: address(0),
            useEnchantedItem: false,
            additionalParam: 0
        });
        game.executeMove(params);

        // Verify Artist has a key
        assertTrue(playerHasKeys(artistPlayer, 1));

        // Step 2: Artist gifts the key to Hero
        vm.prank(artistPlayer);
        params = GameMoves.MoveParams({
            moveType: GameCore.MoveType.Gift,
            actor: artistPlayer,
            targetPlayer: heroPlayer,
            useEnchantedItem: false,
            additionalParam: 0
        });
        game.executeMove(params);

        // Verify Hero has a key and Artist doesn't
        assertTrue(playerHasKeys(heroPlayer, 1));
        assertTrue(playerHasKeys(artistPlayer, 0));

        // Step 3: Hero uses the key to unlock one padlock
        vm.prank(heroPlayer);
        params = GameMoves.MoveParams({
            moveType: GameCore.MoveType.UnlockChest,
            actor: heroPlayer,
            targetPlayer: address(0),
            useEnchantedItem: false,
            additionalParam: 0
        });
        game.executeMove(params);

        // Verify chest state has changed
        assertEq(game.padlocks(), 0);
        assertEq(game.seals(), 1);

        // Step 4: Wizard conjures a staff
        vm.prank(wizardPlayer);
        params = GameMoves.MoveParams({
            moveType: GameCore.MoveType.ConjureStaff,
            actor: wizardPlayer,
            targetPlayer: address(0),
            useEnchantedItem: false,
            additionalParam: 0
        });
        game.executeMove(params);

        // Verify Wizard has a staff
        assertTrue(playerHasStaffs(wizardPlayer, 1));

        // Step 5: Wizard gifts the staff to Innocent
        vm.prank(wizardPlayer);
        params = GameMoves.MoveParams({
            moveType: GameCore.MoveType.Gift,
            actor: wizardPlayer,
            targetPlayer: innocentPlayer,
            useEnchantedItem: false,
            additionalParam: 0
        });
        game.executeMove(params);

        // Verify Innocent has a staff and Wizard doesn't
        assertTrue(playerHasStaffs(innocentPlayer, 1));
        assertTrue(playerHasStaffs(wizardPlayer, 0));

        // Step 6: Innocent uses the staff to unseal the chest
        vm.prank(innocentPlayer);
        params = GameMoves.MoveParams({
            moveType: GameCore.MoveType.UnsealChest,
            actor: innocentPlayer,
            targetPlayer: address(0),
            useEnchantedItem: false,
            additionalParam: 0
        });
        game.executeMove(params);

        // Verify chest state has changed (should be 1 padlock, 0 seals)
        assertEq(game.padlocks(), 0);
        assertEq(game.seals(), 0);

        // Game should be over now
        assertTrue(game.gameOver());

        // Check that Innocent and Wizard are the winners
        uint256 winnerCount = 0;
        bool innocentIsWinner = false;
        bool wizardIsWinner = false;

        // We need to count the winners and check if Innocent and Wizard are among them
        for (uint i = 0; i < game.NUM_PLAYERS(); i++) {
            try game.winners(i) returns (address winner) {
                winnerCount++;
                if (winner == innocentPlayer) {
                    innocentIsWinner = true;
                }
                if (winner == wizardPlayer) {
                    wizardIsWinner = true;
                }
            } catch {
                break;
            }
        }

        // Verify Innocent and Wizard are the only winners
        assertEq(winnerCount, 2, "There should be exactly two winners");
        assertTrue(innocentIsWinner, "Innocent should be a winner");
        assertTrue(wizardIsWinner, "Wizard should be a winner");

        // Check that Innocent and Wizard each received half of the prize money
        uint256 finalInnocentBalance = address(innocentPlayer).balance;
        uint256 finalWizardBalance = address(wizardPlayer).balance;

        uint256 innocentPrize = finalInnocentBalance - initialInnocentBalance;
        uint256 wizardPrize = finalWizardBalance - initialWizardBalance;

        assertEq(
            innocentPrize,
            wizardPrize,
            "Innocent and Wizard should receive equal prize money"
        );
        assertTrue(
            innocentPrize > 0,
            "Prize money should be greater than zero"
        );
    }
}
