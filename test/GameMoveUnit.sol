// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./GameBase.t.sol";

contract GameMoveUnitTests is GameBaseTest {
    address heroPlayer;
    address explorerPlayer;
    address innocentPlayer;
    address artistPlayer;
    address rulerPlayer;
    address caregiverPlayer;
    address commonManPlayer;
    address jokerPlayer;
    address wizardPlayer;
    address outlawPlayer;
    address loverPlayer;
    address sagePlayer;

    function setUp() public override {
        super.setUp();
        joinAllPlayers();

        // Find the players with the required character types
        heroPlayer = findPlayerWithCharacter(GameCore.CharacterType.Hero);
        explorerPlayer = findPlayerWithCharacter(
            GameCore.CharacterType.Explorer
        );
        innocentPlayer = findPlayerWithCharacter(
            GameCore.CharacterType.Innocent
        );
        artistPlayer = findPlayerWithCharacter(GameCore.CharacterType.Artist);
        rulerPlayer = findPlayerWithCharacter(GameCore.CharacterType.Ruler);
        caregiverPlayer = findPlayerWithCharacter(
            GameCore.CharacterType.Caregiver
        );
        commonManPlayer = findPlayerWithCharacter(
            GameCore.CharacterType.CommonMan
        );
        jokerPlayer = findPlayerWithCharacter(GameCore.CharacterType.Joker);
        wizardPlayer = findPlayerWithCharacter(GameCore.CharacterType.Wizard);
        outlawPlayer = findPlayerWithCharacter(GameCore.CharacterType.Outlaw);
        loverPlayer = findPlayerWithCharacter(GameCore.CharacterType.Lover);
        sagePlayer = findPlayerWithCharacter(GameCore.CharacterType.Sage);

        // Advance timestamp past the cooldown period
        vm.warp(block.timestamp + 20 * 60 + 1);
    }

    function testInspireAlliance() public {
        // Step 1: Hero successfully uses Inspire Alliance
        vm.prank(heroPlayer);
        GameMoves.MoveParams memory params = GameMoves.MoveParams({
            moveType: GameCore.MoveType.InspireAlliance,
            actor: heroPlayer,
            targetPlayer: explorerPlayer,
            useEnchantedItem: false,
            additionalParam: 0
        });
        game.executeMove(params);

        // Verify alliance is formed by checking if both players have the same root
        address heroRoot = game.getDsuParent(heroPlayer);
        address explorerRoot = game.getDsuParent(explorerPlayer);
        assertEq(
            heroRoot,
            explorerRoot,
            "Hero and Explorer should be in the same alliance"
        );

        // Step 2: 2 min later, attempt Inspire Alliance during cooldown
        vm.warp(block.timestamp + 2 * 60);
        vm.prank(heroPlayer);
        vm.expectRevert(GameCore.MoveOnCooldown.selector);
        game.executeMove(params);

        // Step 3: 3 min later, try again after cooldown
        vm.warp(block.timestamp + 3 * 60);
        vm.prank(heroPlayer);
        game.executeMove(params);

        // Step 4: 2 min later, Explorer attempts Inspire Alliance and fails
        vm.warp(block.timestamp + 2 * 60);
        vm.prank(explorerPlayer);
        vm.expectRevert(GameCore.PlayerNotInactive.selector);
        game.executeMove(params);

        // Step 5: 6 min later, Explorer attempts Inspire Alliance and passes due to Hero inactivity
        vm.warp(block.timestamp + 6 * 60);
        vm.prank(explorerPlayer);
        game.executeMove(params);

        // Verify alliance is formed by checking if both players have the same root
        heroRoot = game.getDsuParent(heroPlayer);
        explorerRoot = game.getDsuParent(explorerPlayer);
        assertEq(
            heroRoot,
            explorerRoot,
            "Hero and Explorer should be in the same alliance after inactivity"
        );
    }

    function testDiscover() public {
        // Step 1: Explorer calls move and it passes
        vm.prank(explorerPlayer);
        GameMoves.MoveParams memory params = GameMoves.MoveParams({
            moveType: GameCore.MoveType.Discover,
            actor: explorerPlayer,
            targetPlayer: address(0),
            useEnchantedItem: false,
            additionalParam: 0
        });
        game.executeMove(params);

        // Step 2: Explorer now has 1 object (log what object it is)
        uint8 firstItem = game.getPlayerKeys(explorerPlayer);
        console.log("Explorer's first item:", firstItem);

        // Step 3: 4 min later Explorer calls move and it fails (due to cooldown period)
        vm.warp(block.timestamp + 4 * 60);
        vm.prank(explorerPlayer);
        vm.expectRevert(GameCore.MoveOnCooldown.selector);
        game.executeMove(params);

        // Step 4: 2 min later Explorer calls move and it passes (cooldown period passed)
        vm.warp(block.timestamp + 2 * 60);
        vm.prank(explorerPlayer);
        game.executeMove(params);

        // Step 5: Explorer now has two objects (log what objects they are)
        uint8 secondItem = game.getPlayerKeys(explorerPlayer);
        console.log("Explorer's second item:", secondItem);

        // Step 6: 6 min later Innocent calls move and it fails (only the Explorer can call Discover)
        vm.warp(block.timestamp + 6 * 60);
        vm.prank(innocentPlayer);
        vm.expectRevert(GameCore.InvalidMoveType.selector);
        game.executeMove(params);

        // Step 7: 2 min later Innocent calls move and it passes (Explorer considered idle since last move occurred 8 min ago and IDLE_PLAYER_LIMIT is 7 min)
        vm.warp(block.timestamp + 2 * 60);
        vm.prank(innocentPlayer);
        game.executeMove(params);

        // Step 8: Innocent now has 1 object (log what object it is)
        uint8 innocentItem = game.getPlayerKeys(innocentPlayer);
        console.log("Innocent's item:", innocentItem);
    }
}
