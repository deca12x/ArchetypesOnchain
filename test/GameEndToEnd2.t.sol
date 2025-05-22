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
        rulerPlayer = findPlayerWithCharacter(Game.CharacterType.Ruler);
        commonManPlayer = findPlayerWithCharacter(Game.CharacterType.CommonMan);
        wizardPlayer = findPlayerWithCharacter(Game.CharacterType.Wizard);
        sagePlayer = findPlayerWithCharacter(Game.CharacterType.Sage);

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
        vm.prank(rulerPlayer);
        game.secureChest(rulerPlayer);

        // Verify chest state has changed
        assertEq(game.padlocks(), 2);
        assertEq(game.seals(), 1);

        // Step 2: CommonMan calls Secure Chest to add another padlock
        vm.prank(commonManPlayer);
        game.secureChest(commonManPlayer);

        // Verify chest state has changed
        assertEq(game.padlocks(), 3);
        assertEq(game.seals(), 1);
        assertFalse(game.gameOver()); // Game should not be over yet (need 3 seals too)

        // Step 3: Wizard calls Arcane Seal to add a seal
        vm.prank(wizardPlayer);
        game.arcaneSeal(wizardPlayer);

        // Verify chest state has changed
        assertEq(game.padlocks(), 3);
        assertEq(game.seals(), 2);
        assertFalse(game.gameOver()); // Game should not be over yet (need 3 seals)

        // Step 4: Sage calls Arcane Seal to add another seal
        vm.prank(sagePlayer);
        game.arcaneSeal(sagePlayer);

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
    }
}
