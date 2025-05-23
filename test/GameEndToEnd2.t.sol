// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./GameBase.t.sol";

contract GameEndToEnd2Test is GameBaseTest {
    address rulerPlayer;
    address commonManPlayer;
    address wizardPlayer;
    address sagePlayer;

    function setUp() public override {
        super.setUp();

        // Have all players join the game
        joinAllPlayers();

        // Find the players with the required character types
        rulerPlayer = findPlayerWithCharacter(GameCore.CharacterType.Ruler);
        commonManPlayer = findPlayerWithCharacter(
            GameCore.CharacterType.CommonMan
        );
        wizardPlayer = findPlayerWithCharacter(GameCore.CharacterType.Wizard);
        sagePlayer = findPlayerWithCharacter(GameCore.CharacterType.Sage);

        // After setting up the game but before calling any moves
        vm.warp(block.timestamp + 10 * 60 + 1); // Advance timestamp past the cooldown period
    }

    function testEndToEndGameplayBlockVictory() public {
        // Record initial balances
        uint256 initialSageBalance = address(sagePlayer).balance;

        // Initial state checks
        assertTrue(game.gameStarted());
        assertEq(game.padlocks(), 1);
        assertEq(game.seals(), 1);
        assertFalse(game.gameOver());

        // Step 1: Ruler calls Secure Chest to add a padlock
        GameMoves.MoveParams memory params = GameMoves.MoveParams({
            moveType: GameCore.MoveType.SecureChest,
            actor: rulerPlayer,
            targetPlayer: address(0),
            useEnchantedItem: false,
            additionalParam: 0
        });
        game.executeMove(params);

        // Verify chest state has changed
        assertEq(game.padlocks(), 2);
        assertEq(game.seals(), 1);

        // Step 2: CommonMan calls Secure Chest to add another padlock
        vm.prank(commonManPlayer);
        params = GameMoves.MoveParams({
            moveType: GameCore.MoveType.SecureChest,
            actor: commonManPlayer,
            targetPlayer: address(0),
            useEnchantedItem: false,
            additionalParam: 0
        });
        game.executeMove(params);

        // Verify chest state has changed
        assertEq(game.padlocks(), 3);
        assertEq(game.seals(), 1);
        assertFalse(game.gameOver()); // Game should not be over yet (need 3 seals too)

        // Step 3: Wizard calls Arcane Seal to add a seal
        vm.prank(wizardPlayer);
        params = GameMoves.MoveParams({
            moveType: GameCore.MoveType.ArcaneSeal,
            actor: wizardPlayer,
            targetPlayer: address(0),
            useEnchantedItem: false,
            additionalParam: 0
        });
        game.executeMove(params);

        // Verify chest state has changed
        assertEq(game.padlocks(), 3);
        assertEq(game.seals(), 2);
        assertFalse(game.gameOver()); // Game should not be over yet (need 3 seals)

        // Step 4: Sage calls Arcane Seal to add another seal
        vm.prank(sagePlayer);
        params = GameMoves.MoveParams({
            moveType: GameCore.MoveType.ArcaneSeal,
            actor: sagePlayer,
            targetPlayer: address(0),
            useEnchantedItem: false,
            additionalParam: 0
        });
        game.executeMove(params);

        // Verify chest state has changed (should be 3 padlocks, 3 seals)
        assertEq(game.padlocks(), 3);
        assertEq(game.seals(), 3);

        // Game should be over now
        assertTrue(game.gameOver());

        // Check that there's a winner
        uint256 winnerCount = 0;
        bool sageIsWinner = false;
        bool sageIsOnlyWinner = true;

        // We need to count the winners and check if Sage is the only winner
        for (uint i = 0; i < game.NUM_PLAYERS(); i++) {
            try game.winners(i) returns (address winner) {
                winnerCount++;
                if (winner == sagePlayer) {
                    sageIsWinner = true;
                } else {
                    sageIsOnlyWinner = false;
                }
            } catch {
                break;
            }
        }

        // Verify Sage is the winner and received prize money
        assertTrue(winnerCount > 0, "There should be at least one winner");
        assertTrue(sageIsWinner, "Sage should be a winner");
        assertTrue(sageIsOnlyWinner, "Sage should be the only winner");

        // Check that Sage's balance increased
        uint256 finalSageBalance = address(sagePlayer).balance;
        assertTrue(
            finalSageBalance > initialSageBalance,
            "Sage should have received prize money"
        );

        // Check that Sage received all the prize money
        uint256 expectedPrize = address(game).balance +
            (finalSageBalance - initialSageBalance);
        assertEq(
            finalSageBalance - initialSageBalance,
            expectedPrize,
            "Sage should have received all the prize money"
        );
    }
}
