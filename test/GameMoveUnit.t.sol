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
            useItem: false
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
            useItem: false
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
        vm.expectRevert(GameCore.PlayerNotInactive.selector);
        game.executeMove(params);

        // Step 7: 2 min later Innocent calls move and it passes (Explorer considered idle since last move occurred 8 min ago and IDLE_PLAYER_LIMIT is 7 min)
        vm.warp(block.timestamp + 2 * 60);
        vm.prank(innocentPlayer);
        game.executeMove(params);

        // Step 8: Innocent now has 1 object (log what object it is)
        uint8 innocentItem = game.getPlayerKeys(innocentPlayer);
        console.log("Innocent's item:", innocentItem);
    }

    function testPurify() public {
        // Step 1: Verify initial chest state
        assertEq(game.seals(), 1, "Chest should initially have 1 seal");

        // Step 2: Innocent calls Purify move successfully
        vm.prank(innocentPlayer);
        GameMoves.MoveParams memory purifyParams = GameMoves.MoveParams({
            moveType: GameCore.MoveType.Purify,
            actor: innocentPlayer,
            targetPlayer: address(0),
            useItem: false
        });
        game.executeMove(purifyParams);
        assertEq(game.seals(), 0, "Chest should have 0 seals after Purify");

        // Step 3: Wizard calls Arcane Seal successfully
        vm.prank(wizardPlayer);
        GameMoves.MoveParams memory arcaneSealParams = GameMoves.MoveParams({
            moveType: GameCore.MoveType.ArcaneSeal,
            actor: wizardPlayer,
            targetPlayer: address(0),
            useItem: false
        });
        game.executeMove(arcaneSealParams);
        assertEq(game.seals(), 1, "Chest should have 1 seal after Arcane Seal");

        // Step 4: Innocent calls Purify move unsuccessfully due to cooldown
        vm.warp(block.timestamp + 1 * 60);
        vm.prank(innocentPlayer);
        vm.recordLogs(); // Start recording logs
        vm.expectRevert(GameCore.MoveOnCooldown.selector);
        game.executeMove(purifyParams);

        // Retrieve and log the recorded events
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint i = 0; i < logs.length; i++) {
            if (
                logs[i].topics[0] ==
                keccak256(
                    "CooldownCheck(address,MoveType,uint256,uint256,uint256)"
                )
            ) {
                (
                    address actor,
                    GameCore.MoveType move,
                    uint256 lastMoveTimestamp,
                    uint256 cooldownDuration,
                    uint256 currentTime
                ) = abi.decode(
                        logs[i].data,
                        (address, GameCore.MoveType, uint256, uint256, uint256)
                    );
                console.log("CooldownCheck Event - Actor:", actor);
                console.log("Move:", uint256(move));
                console.log("Last Move Timestamp:", lastMoveTimestamp);
                console.log("Cooldown Duration:", cooldownDuration);
                console.log("Current Time:", currentTime);
            }
        }

        // Step 5: Caregiver calls Plea of Peace
        vm.warp(block.timestamp + 6 * 60);
        vm.prank(caregiverPlayer);
        GameMoves.MoveParams memory pleaOfPeaceParams = GameMoves.MoveParams({
            moveType: GameCore.MoveType.PleaOfPeace,
            actor: caregiverPlayer,
            targetPlayer: address(0),
            useItem: false
        });
        game.executeMove(pleaOfPeaceParams);

        // Step 6: Wait 6 minutes, Innocent calls Purify move unsuccessfully due to Plea of Peace
        vm.prank(innocentPlayer);
        vm.expectRevert(GameCore.PeaceActive.selector);
        game.executeMove(purifyParams);

        // Step 7: Wait 6 more minutes, Innocent calls Purify move successfully
        vm.warp(block.timestamp + 6 * 60);
        vm.prank(innocentPlayer);
        game.executeMove(purifyParams);
        assertEq(game.seals(), 0, "Chest should have 0 seals after Purify");

        // Step 8: Wait 6 more minutes, Innocent calls Purify move unsuccessfully because chest already has 0 seals
        vm.warp(block.timestamp + 6 * 60);
        vm.prank(innocentPlayer);
        vm.expectRevert(GameCore.InvalidChestUnlockMove.selector);
        game.executeMove(purifyParams);
    }
}
