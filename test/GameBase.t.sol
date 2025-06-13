// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../src/GameMoves.sol";
import "../src/GameCore.sol";
import "../src/GameLibrary.sol";

contract GameBaseTest is Test {
    GameMoves game;
    address[] players;

    // Set up test addresses using vm.addr instead of precompiled addresses
    address player1 = vm.addr(1);
    address player2 = vm.addr(2);
    address player3 = vm.addr(3);
    address player4 = vm.addr(4);
    address player5 = vm.addr(5);
    address player6 = vm.addr(6);
    address player7 = vm.addr(7);
    address player8 = vm.addr(8);
    address player9 = vm.addr(9);
    address player10 = vm.addr(10);
    address player11 = vm.addr(11);
    address player12 = vm.addr(12);

    uint256 constant ENTRY_FEE = 0.01 ether;

    function setUp() public virtual {
        // Deploy game contract as player1
        vm.startPrank(player1);
        vm.deal(player1, 1 ether);
        game = new GameMoves();
        vm.stopPrank();

        // Create player array
        players = new address[](12);
        players[0] = player1;
        players[1] = player2;
        players[2] = player3;
        players[3] = player4;
        players[4] = player5;
        players[5] = player6;
        players[6] = player7;
        players[7] = player8;
        players[8] = player9;
        players[9] = player10;
        players[10] = player11;
        players[11] = player12;

        // Fund all players
        for (uint256 i = 1; i < 12; i++) {
            // Skip player1 as already funded
            vm.deal(players[i], 1 ether);
        }

        // Verify player 1 joined during contract creation
        assertEq(game.numPlayersJoined(), 1);
    }

    // Helper function to have all players join the game
    function joinAllPlayers() internal {
        // Skip player1 as they join during contract creation
        for (uint256 i = 1; i < 12; i++) {
            vm.prank(players[i]);
            game.joinGame{value: ENTRY_FEE}();
        }
    }

    // Helper to find a player with a specific character type
    function findPlayerWithCharacter(GameCore.CharacterType charType) internal view returns (address) {
        for (uint8 i = 0; i < game.numPlayersJoined(); i++) {
            address playerAddr = game.gamePlayerAddresses(i);
            (, GameCore.CharacterType character,,,,, bool hasJoined,,) = game.playerData(playerAddr);

            if (hasJoined && character == charType) {
                return playerAddr;
            }
        }
        revert("Character type not found");
    }

    // Helper to get character type of a player
    function getCharacterType(address playerAddr) internal view returns (GameCore.CharacterType) {
        (, GameCore.CharacterType character,,,,, bool hasJoined,,) = game.playerData(playerAddr);
        require(hasJoined, "Player has not joined");
        return character;
    }

    // Helper to check if a player has a specific number of keys
    function playerHasKeys(address playerAddr, uint8 keyCount) internal view returns (bool) {
        (,, uint8 keys,,,,,,) = game.playerData(playerAddr);
        return keys == keyCount;
    }

    // Helper to check if a player has a specific number of enchanted keys
    function playerHasEnchantedKeys(address playerAddr, uint8 keyCount) internal view returns (bool) {
        (,,, uint8 enchantedKeys,,,,,) = game.playerData(playerAddr);
        return enchantedKeys == keyCount;
    }

    // Helper to check if a player has a specific number of staffs
    function playerHasStaffs(address playerAddr, uint8 staffCount) internal view returns (bool) {
        (,,,, uint8 staffs,,,,) = game.playerData(playerAddr);
        return staffs == staffCount;
    }

    // Helper to check if a player has a specific number of protections
    function playerHasProtections(address playerAddr, uint8 protectionCount) internal view returns (bool) {
        (,,,,, uint8 protections,,,) = game.playerData(playerAddr);
        return protections == protectionCount;
    }
}
