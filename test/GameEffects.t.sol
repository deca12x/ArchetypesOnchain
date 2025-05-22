// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./GameBase.t.sol";

contract GameEffectsTest is GameBaseTest {
    function setUp() public override {
        super.setUp();
        joinAllPlayers();
    }

    function testProtectionTracking() public {
        // Find a character that can use Guard
        address guardPlayer = findPlayerWithCharacter(Game.CharacterType.Hero);
        address targetPlayer = players[0];

        // Guard another player
        vm.prank(guardPlayer);
        game.guard(guardPlayer, targetPlayer);

        // The player should now have protection
        (, , , , , uint8 protections, , ) = game.playerData(targetPlayer);
        assertEq(protections, 1);

        // Find a character that can use Seize
        address seizePlayer = findPlayerWithCharacter(Game.CharacterType.Ruler);

        // Give the target player an item to seize
        vm.mockCall(
            address(game),
            abi.encodeWithSignature("playerData(address)"),
            abi.encode(targetPlayer, Game.CharacterType.Hero, 1, 0, 0, 1, true)
        );

        // Try seizing an item (should consume protection)
        vm.prank(seizePlayer);
        game.seizeItem(seizePlayer, targetPlayer);

        // Protection should be used up
        (, , , , , protections, , ) = game.playerData(targetPlayer);
        assertEq(protections, 0);
    }

    function testPleaOfPeace() public {
        // Find Innocent or Caregiver
        address peacefulPlayer = findPlayerWithCharacter(
            Game.CharacterType.Innocent
        );
        address outlawPlayer = findPlayerWithCharacter(
            Game.CharacterType.Outlaw
        );

        // Activate Plea of Peace
        vm.prank(peacefulPlayer);
        game.pleaOfPeace(peacefulPlayer);

        // Try to use a harmful move (should fail)
        vm.prank(outlawPlayer);
        vm.expectRevert("Plea of Peace active");
        game.lockpick(outlawPlayer);

        // Wait for effect to expire (2 minutes)
        vm.warp(block.timestamp + 2 * 60 + 1);

        // Try again (should succeed)
        vm.prank(outlawPlayer);
        game.lockpick(outlawPlayer);
    }

    function testRoyalDecree() public {
        // Find Ruler
        address rulerPlayer = findPlayerWithCharacter(Game.CharacterType.Ruler);

        // Activate Royal Decree
        vm.prank(rulerPlayer);
        game.royalDecree(rulerPlayer);

        // Check that decree end time is set
        assertTrue(game.royalDecreeEndTime() > block.timestamp);

        // Wait for effect to expire
        vm.warp(block.timestamp + 1 * 60 + 1);

        // Verify effect has expired
        assertTrue(block.timestamp > game.royalDecreeEndTime());
    }

    function testFakeKeys() public {
        // Find Joker to create fake key
        address jokerPlayer = findPlayerWithCharacter(Game.CharacterType.Joker);
        address heroPlayer = findPlayerWithCharacter(Game.CharacterType.Hero);

        // Create fake key
        vm.prank(jokerPlayer);
        game.createFakeKey(jokerPlayer);

        // Give hero a real key
        vm.mockCall(
            address(game),
            abi.encodeWithSignature("playerData(address)"),
            abi.encode(heroPlayer, Game.CharacterType.Hero, 1, 0, 0, 0, true)
        );

        // Try to unlock chest (should hit fake key)
        vm.prank(heroPlayer);
        game.unlockChest(heroPlayer, false);

        // Fake key should be used up and no change to padlocks
        assertEq(game.padlocks(), 2);
    }
}
