// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./GameBase.t.sol";

contract GameGasTest is GameBaseTest {
    function setUp() public override {
        super.setUp();
        joinAllPlayers();
    }

    // Test gas usage for contract deployment
    function testDeploymentGas() public {
        uint256 startGas = gasleft();
        new Game();
        uint256 gasUsed = startGas - gasleft();

        console.log("Gas used for deployment:", gasUsed);
        // Optional: assert gas usage is within expected range
        assert(gasUsed < 10000000); // Example threshold
    }

    // Test critical path operations
    function testJoinGameGas() public {
        // Reset to before players joined
        setUp();

        uint256 startGas = gasleft();
        vm.prank(player2);
        game.joinGame{value: ENTRY_FEE}();
        uint256 gasUsed = startGas - gasleft();

        console.log("Gas used for joining game:", gasUsed);
    }

    // Alliance formation gas usage
    function testAllianceFormationGas() public {
        address heroPlayer = findPlayerWithCharacter(Game.CharacterType.Hero);

        uint256 startGas = gasleft();
        vm.prank(heroPlayer);
        game.inspireAlliance(heroPlayer, players[0]);
        uint256 gasUsed = startGas - gasleft();

        console.log("Gas used for alliance formation:", gasUsed);
    }

    // Item creation and transfer gas usage
    function testItemOperationsGas() public {
        address artistPlayer = findPlayerWithCharacter(
            Game.CharacterType.Artist
        );

        uint256 startGas = gasleft();
        vm.prank(artistPlayer);
        game.createEnchantedKey(artistPlayer);
        uint256 gasUsed = startGas - gasleft();

        console.log("Gas used for creating item:", gasUsed);
    }

    // Victory conditions gas usage
    function testVictoryConditionGas() public {
        address heroPlayer = findPlayerWithCharacter(Game.CharacterType.Hero);

        // Mock hero having enchanted keys
        vm.mockCall(
            address(game),
            abi.encodeWithSignature("playerData(address)"),
            abi.encode(heroPlayer, Game.CharacterType.Hero, 0, 2, 0, 0, true)
        );

        uint256 startGas = gasleft();
        vm.prank(heroPlayer);
        game.unlockChest(heroPlayer, true);
        uint256 gasUsed = startGas - gasleft();

        console.log("Gas used for unlock operation:", gasUsed);
    }

    // Test complex alliance merging
    function testComplexAllianceMergeGas() public {
        // Set up two separate alliances
        address hero = findPlayerWithCharacter(Game.CharacterType.Hero);
        address caregiver = findPlayerWithCharacter(
            Game.CharacterType.Caregiver
        );
        address lover = findPlayerWithCharacter(Game.CharacterType.Lover);

        // Create initial alliances
        vm.prank(hero);
        game.inspireAlliance(hero, players[2]);

        vm.prank(lover);
        game.soulBond(lover, players[3]);

        vm.warp(block.timestamp + 5 * 60);

        // Measure gas for merging alliances
        uint256 startGas = gasleft();
        vm.prank(caregiver);
        game.guardianBond(caregiver, hero);
        uint256 gasUsed = startGas - gasleft();

        console.log("Gas used for merging first alliance:", gasUsed);

        vm.warp(block.timestamp + 5 * 60);

        startGas = gasleft();
        vm.prank(caregiver);
        game.guardianBond(caregiver, lover);
        gasUsed = startGas - gasleft();

        console.log("Gas used for merging second alliance:", gasUsed);
    }
}
