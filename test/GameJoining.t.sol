// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./GameBase.t.sol";

contract GameJoiningTest is GameBaseTest {
    function testContractDeployment() public view {
        assertEq(game.NUM_PLAYERS(), 12);
        assertEq(game.ENTRY_FEE_MNT(), 0.01 ether);
        assertFalse(game.gameStarted());
        assertFalse(game.gameOver());
        assertEq(game.totalPrizePool(), 0);
    }

    function testJoinWithCorrectFee() public {
        // Test with wrong fee
        vm.prank(player2);
        vm.expectRevert();
        game.joinGame{value: 0.005 ether}();

        // Test with correct fee
        vm.prank(player2);
        game.joinGame{value: ENTRY_FEE}();

        assertEq(game.numPlayersJoined(), 2);
        assertEq(game.totalPrizePool(), ENTRY_FEE);
    }

    function testCharacterAssignment() public {
        joinAllPlayers();

        // Verify each player has a different character type
        bool[12] memory characterAssigned;

        for (uint i = 0; i < 12; i++) {
            Game.CharacterType charType = getCharacterType(players[i]);
            uint8 charIndex = uint8(charType);

            // Ensure character hasn't been assigned already
            assertFalse(
                characterAssigned[charIndex],
                "Character assigned twice"
            );
            characterAssigned[charIndex] = true;
        }

        // Verify all characters were assigned
        for (uint i = 0; i < 12; i++) {
            assertTrue(characterAssigned[i], "Character not assigned");
        }
    }

    function testGameStart() public {
        joinAllPlayers();

        // Game should have started
        assertTrue(game.gameStarted());
        assertEq(game.numPlayersJoined(), 12);
        assertEq(game.padlocks(), 2);
        assertEq(game.seals(), 1);
        assertEq(game.totalPrizePool(), 0.11 ether); // 11 players * 0.01 ether (player1 didn't pay)

        // Game start time should be set
        assertTrue(game.gameStartTime() > 0);
    }

    function testJoinGameFull() public {
        joinAllPlayers();

        // Attempt to join when game is full
        address extraPlayer = address(0x999);
        vm.deal(extraPlayer, 1 ether);
        vm.prank(extraPlayer);
        vm.expectRevert();
        game.joinGame{value: ENTRY_FEE}();
    }

    function testEntryFeeHandling() public {
        // Test contract handles entry fee correctly
        vm.prank(player2);
        game.joinGame{value: ENTRY_FEE}();

        assertEq(address(game).balance, ENTRY_FEE);
        assertEq(game.totalPrizePool(), ENTRY_FEE);
    }
}
