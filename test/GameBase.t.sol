// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../src/Game.sol";

contract GameBaseTest is Test {
    Game game;
    address[] players;

    // Set up test addresses
    address player1 = address(0x1);
    address player2 = address(0x2);
    address player3 = address(0x3);
    address player4 = address(0x4);
    address player5 = address(0x5);
    address player6 = address(0x6);
    address player7 = address(0x7);
    address player8 = address(0x8);
    address player9 = address(0x9);
    address player10 = address(0x10);
    address player11 = address(0x11);
    address player12 = address(0x12);

    uint256 constant ENTRY_FEE = 0.01 ether;

    function setUp() public virtual {
        // Deploy game contract as player1
        vm.startPrank(player1);
        vm.deal(player1, 1 ether);
        game = new Game();
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
        for (uint i = 1; i < 12; i++) {
            // Skip player1 as already funded
            vm.deal(players[i], 1 ether);
        }

        // Verify player 1 joined during contract creation
        assertEq(game.numPlayersJoined(), 1);
    }

    // Helper function to have all players join the game
    function joinAllPlayers() internal {
        // Skip player1 as they join during contract creation
        for (uint i = 1; i < 12; i++) {
            vm.prank(players[i]);
            game.joinGame{value: ENTRY_FEE}();
        }
    }

    // Helper to find a player with a specific character type
    function findPlayerWithCharacter(
        Game.CharacterType charType
    ) internal view returns (address) {
        for (uint8 i = 0; i < game.numPlayersJoined(); i++) {
            address playerAddr = game.gamePlayerAddresses(i);
            (, Game.CharacterType character, , , , , bool hasJoined, ) = game
                .playerData(playerAddr);

            if (hasJoined && character == charType) {
                return playerAddr;
            }
        }
        revert("Character type not found");
    }

    // Helper to get character type of a player
    function getCharacterType(
        address playerAddr
    ) internal view returns (Game.CharacterType) {
        (, Game.CharacterType character, , , , , bool hasJoined, ) = game
            .playerData(playerAddr);
        require(hasJoined, "Player has not joined");
        return character;
    }

    // Helper to check if a player has a specific number of keys
    function playerHasKeys(
        address playerAddr,
        uint8 keyCount
    ) internal view returns (bool) {
        (, , uint8 keys, , , , , ) = game.playerData(playerAddr);
        return keys == keyCount;
    }

    // Helper to check if a player has a specific number of enchanted keys
    function playerHasEnchantedKeys(
        address playerAddr,
        uint8 keyCount
    ) internal view returns (bool) {
        (, , , uint8 enchantedKeys, , , , ) = game.playerData(playerAddr);
        return enchantedKeys == keyCount;
    }

    // Helper to check if a player has a specific number of staffs
    function playerHasStaffs(
        address playerAddr,
        uint8 staffCount
    ) internal view returns (bool) {
        (, , , , uint8 staffs, , , ) = game.playerData(playerAddr);
        return staffs == staffCount;
    }

    // Helper to check if a player has a specific number of protections
    function playerHasProtections(
        address playerAddr,
        uint8 protectionCount
    ) internal view returns (bool) {
        (, , , , , uint8 protections, , ) = game.playerData(playerAddr);
        return protections == protectionCount;
    }
}
