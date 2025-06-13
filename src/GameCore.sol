// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./GameLibrary.sol";

contract GameCore {
    // --- Custom Errors ---
    error InvalidTarget();
    error PeaceActive();
    error NoItems();
    error NoKey();
    error NoEKey();
    error NoStaff();
    error NoValidMove();

    error InvalidMoveType();
    error InvalidAllianceMove();
    error InvalidItemCreateMove();
    error InvalidChestLockMove();
    error InvalidChestUnlockMove();
    error InvalidProtectionMove();
    error InvalidGlobalMove();
    error InvalidCopyMove();
    error InvalidCooldownMove();
    error InvalidHarmfulMove();

    error InsufficientKeys();
    error InsufficientEnchantedKeys();
    error InsufficientStaffs();

    error NotAPlayer(address player);
    error PlayerNotInactive();
    error MoveOnCooldown();
    error TargetNotPlayer();

    // Constants
    uint8 public constant NUM_PLAYERS = 12;
    uint256 public constant ENTRY_FEE_MNT = 0.01 ether; // 0.01 MNT
    uint256 internal constant IDLE_PLAYER_LIMIT = 7 * 60 seconds;

    // Enums
    enum CharacterType {
        Hero,
        Explorer,
        Innocent,
        Artist,
        Ruler,
        Caregiver,
        CommonMan,
        Joker,
        Wizard,
        Outlaw,
        Lover,
        Sage
    }

    enum MoveType {
        InspireAlliance, // Hero's unique move
        Discover, // Explorer's unique move
        Purify, // Innocent's unique move
        CreateEnchantedKey, // Artist's unique move
        RoyalDecree, // Ruler's unique move
        GuardianBond, // Caregiver's unique move
        CopycatMove, // CommonMan's unique move
        CreateFakeKey, // Joker's unique move
        ConjureStaff, // Wizard's unique move
        Lockpick, // Outlaw's unique move
        SoulBond, // Lover's unique move
        EnergyFlow, // Sage's unique move
        ForgeKey, // Artist and Wizard can use this move
        SecureChest, // Ruler and Common Man can use this move
        ArcaneSeal, // Wizard and Sage can use this move
        SeizeItem, // Ruler, Joker and Outlaw can use this move
        Distract, // CommonMan, Joker and Lover can use this move
        Guard, // Hero, Explorer and Caregiver can use this move
        Evade, // Explorer, Artist and Outlaw can use this move
        PleaOfPeace, // All characters can use this move
        UnlockChest, // Hero and Lover can use this move
        UnsealChest, // Innocent and Sage can use this move
        Gift // All characters can use this move
    }

    // Player struct
    struct Player {
        address playerAddress;
        CharacterType character;
        uint8 keys;
        uint8 enchantedKeys;
        uint8 staffs;
        uint8 protections;
        mapping(uint256 => uint256) lastMoveTimestamp;
        bool hasJoined;
        uint256 inactivityTimestamp;
        bool distracted;
    }

    // Game state variables
    address[NUM_PLAYERS] public gamePlayerAddresses;
    mapping(address => Player) public playerData;
    CharacterType[NUM_PLAYERS] internal initialCharacterOrder;

    uint8 public numPlayersJoined;
    bool public gameStarted;
    bool public gameOver;
    address[] public winners;
    uint256 public totalPrizePool;
    uint256 public gameStartTime;

    // Chest state
    uint8 public padlocks;
    uint8 public seals;

    // Global game effects
    uint8 public activeFakeKeysCount;
    uint256 public pleaOfPeaceEndTime;
    uint256 public royalDecreeEndTime;

    // For Copycat move
    MoveType private _lastMoveExecuted;

    // Alliance tracking (DSU)
    mapping(address => address) public dsuParent;
    mapping(address => uint8) public dsuSetSize;

    // Cooldowns
    mapping(MoveType => uint256) public moveCooldowns;

    // Character-move relationships
    mapping(CharacterType => mapping(MoveType => bool))
        public characterCanUseMove;

    // Events
    event GameCreated(address indexed creator, uint256 entryFee);
    event PlayerJoined(
        uint8 playerIndex,
        address indexed playerAddress,
        CharacterType character
    );
    event GameStarted(
        uint256 startTime,
        uint8 initialPadlocks,
        uint8 initialSeals
    );
    event MoveExecuted(
        address indexed caller,
        address indexed actor,
        MoveType move,
        string details
    );
    event ChestStateChanged(uint8 newPadlocks, uint8 newSeals);
    event AllianceUpdated(
        address indexed player1,
        address indexed player2,
        bool bound
    );
    event ItemsChanged(address indexed player, string itemType, int8 change);
    event ProtectionStatusChanged(
        address indexed player,
        bool protected,
        string byMove
    );
    event GameOver(
        uint8 finalPadlocks,
        uint8 finalSeals,
        address[] winners,
        uint256 prizePerWinner,
        uint256 gameDuration
    );
    event EffectActivated(string effectName, uint256 endTime);

    // Modifiers
    modifier onlyGamePlayer(address _player) {
        require(playerData[_player].hasJoined, "Not a game player");
        _;
    }

    modifier gameIsActive() {
        require(gameStarted, "Game not started");
        require(!gameOver, "Game is over");
        _;
    }

    // Initialize character move mappings
    function _initializeCharacterMoves() internal {
        // Hero moves
        characterCanUseMove[CharacterType.Hero][
            MoveType.InspireAlliance
        ] = true;
        characterCanUseMove[CharacterType.Hero][MoveType.Guard] = true;
        characterCanUseMove[CharacterType.Hero][MoveType.UnlockChest] = true;

        // Explorer moves
        characterCanUseMove[CharacterType.Explorer][MoveType.Discover] = true;
        characterCanUseMove[CharacterType.Explorer][MoveType.Guard] = true;
        characterCanUseMove[CharacterType.Explorer][MoveType.Evade] = true;

        // Innocent moves
        characterCanUseMove[CharacterType.Innocent][MoveType.Purify] = true;
        characterCanUseMove[CharacterType.Innocent][
            MoveType.UnsealChest
        ] = true;
        characterCanUseMove[CharacterType.Innocent][
            MoveType.PleaOfPeace
        ] = true;

        // Artist moves
        characterCanUseMove[CharacterType.Artist][
            MoveType.CreateEnchantedKey
        ] = true;
        characterCanUseMove[CharacterType.Artist][MoveType.ForgeKey] = true;
        characterCanUseMove[CharacterType.Artist][MoveType.Evade] = true;

        // Ruler moves
        characterCanUseMove[CharacterType.Ruler][MoveType.RoyalDecree] = true;
        characterCanUseMove[CharacterType.Ruler][MoveType.SecureChest] = true;
        characterCanUseMove[CharacterType.Ruler][MoveType.SeizeItem] = true;

        // Caregiver moves
        characterCanUseMove[CharacterType.Caregiver][
            MoveType.GuardianBond
        ] = true;
        characterCanUseMove[CharacterType.Caregiver][MoveType.Guard] = true;
        characterCanUseMove[CharacterType.Caregiver][
            MoveType.PleaOfPeace
        ] = true;

        // CommonMan moves
        characterCanUseMove[CharacterType.CommonMan][
            MoveType.CopycatMove
        ] = true;
        characterCanUseMove[CharacterType.CommonMan][
            MoveType.SecureChest
        ] = true;
        characterCanUseMove[CharacterType.CommonMan][MoveType.Distract] = true;

        // Joker moves
        characterCanUseMove[CharacterType.Joker][MoveType.CreateFakeKey] = true;
        characterCanUseMove[CharacterType.Joker][MoveType.SeizeItem] = true;
        characterCanUseMove[CharacterType.Joker][MoveType.Distract] = true;

        // Wizard moves
        characterCanUseMove[CharacterType.Wizard][MoveType.ConjureStaff] = true;
        characterCanUseMove[CharacterType.Wizard][MoveType.ForgeKey] = true;
        characterCanUseMove[CharacterType.Wizard][MoveType.ArcaneSeal] = true;

        // Outlaw moves
        characterCanUseMove[CharacterType.Outlaw][MoveType.Lockpick] = true;
        characterCanUseMove[CharacterType.Outlaw][MoveType.Evade] = true;
        characterCanUseMove[CharacterType.Outlaw][MoveType.SeizeItem] = true;

        // Lover moves
        characterCanUseMove[CharacterType.Lover][MoveType.SoulBond] = true;
        characterCanUseMove[CharacterType.Lover][MoveType.UnlockChest] = true;
        characterCanUseMove[CharacterType.Lover][MoveType.Distract] = true;

        // Sage moves
        characterCanUseMove[CharacterType.Sage][MoveType.EnergyFlow] = true;
        characterCanUseMove[CharacterType.Sage][MoveType.UnsealChest] = true;
        characterCanUseMove[CharacterType.Sage][MoveType.ArcaneSeal] = true;

        // Add shared moves (Gift only)
        for (uint8 i = 0; i < uint8(CharacterType.Sage) + 1; i++) {
            characterCanUseMove[CharacterType(i)][MoveType.Gift] = true;
        }
    }

    // Initialize cooldowns
    function _initializeCooldowns() internal {
        // Hero moves
        moveCooldowns[MoveType.InspireAlliance] = 4 * 60; // 4 min
        moveCooldowns[MoveType.Guard] = 3 * 60; // 3 min
        moveCooldowns[MoveType.UnlockChest] = 2 * 60; // 2 min
        moveCooldowns[MoveType.Gift] = 0; // No cooldown

        // Explorer moves
        moveCooldowns[MoveType.Discover] = 5 * 60; // 5 min
        moveCooldowns[MoveType.Evade] = 3 * 60; // 3 min
        moveCooldowns[MoveType.Guard] = 3 * 60; // 3 min
        moveCooldowns[MoveType.Gift] = 0; // No cooldown

        // Innocent moves
        moveCooldowns[MoveType.Purify] = 5 * 60; // 5 min
        moveCooldowns[MoveType.PleaOfPeace] = 5 * 60; // 5 min
        moveCooldowns[MoveType.UnsealChest] = 2 * 60; // 2 min
        moveCooldowns[MoveType.Gift] = 0; // No cooldown

        // Artist moves
        moveCooldowns[MoveType.CreateEnchantedKey] = 5 * 60; // 5 min
        moveCooldowns[MoveType.ForgeKey] = 3 * 60; // 3 min
        moveCooldowns[MoveType.Evade] = 3 * 60; // 3 min
        moveCooldowns[MoveType.Gift] = 0; // No cooldown

        // Ruler moves
        moveCooldowns[MoveType.RoyalDecree] = 5 * 60; // 5 min
        moveCooldowns[MoveType.SecureChest] = 3 * 60; // 3 min
        moveCooldowns[MoveType.SeizeItem] = 2 * 60; // 2 min
        moveCooldowns[MoveType.Gift] = 0; // No cooldown

        // Caregiver moves
        moveCooldowns[MoveType.GuardianBond] = 4 * 60; // 4 min
        moveCooldowns[MoveType.Guard] = 3 * 60; // 3 min
        moveCooldowns[MoveType.PleaOfPeace] = 5 * 60; // 5 min
        moveCooldowns[MoveType.Gift] = 0; // No cooldown

        // Common Man moves
        moveCooldowns[MoveType.CopycatMove] = 5 * 60; // 5 min
        moveCooldowns[MoveType.SecureChest] = 3 * 60; // 3 min
        moveCooldowns[MoveType.Distract] = 2 * 60; // 2 min
        moveCooldowns[MoveType.Gift] = 0; // No cooldown

        // Joker moves
        moveCooldowns[MoveType.CreateFakeKey] = 5 * 60; // 5 min
        moveCooldowns[MoveType.SeizeItem] = 2 * 60; // 2 min
        moveCooldowns[MoveType.Distract] = 2 * 60; // 2 min
        moveCooldowns[MoveType.Gift] = 0; // No cooldown

        // Wizard moves
        moveCooldowns[MoveType.ConjureStaff] = 5 * 60; // 5 min
        moveCooldowns[MoveType.ArcaneSeal] = 4 * 60; // 4 min
        moveCooldowns[MoveType.ForgeKey] = 3 * 60; // 3 min
        moveCooldowns[MoveType.Gift] = 0; // No cooldown

        // Outlaw moves
        moveCooldowns[MoveType.Lockpick] = 5 * 60; // 5 min
        moveCooldowns[MoveType.SeizeItem] = 2 * 60; // 2 min
        moveCooldowns[MoveType.Evade] = 3 * 60; // 3 min
        moveCooldowns[MoveType.Gift] = 0; // No cooldown

        // Lover moves
        moveCooldowns[MoveType.SoulBond] = 4 * 60; // 4 min
        moveCooldowns[MoveType.Distract] = 2 * 60; // 2 min
        moveCooldowns[MoveType.UnlockChest] = 2 * 60; // 2 min
        moveCooldowns[MoveType.Gift] = 0; // No cooldown

        // Sage moves
        moveCooldowns[MoveType.EnergyFlow] = 5 * 60; // 5 min
        moveCooldowns[MoveType.UnsealChest] = 2 * 60; // 2 min
        moveCooldowns[MoveType.ArcaneSeal] = 4 * 60; // 4 min
        moveCooldowns[MoveType.Gift] = 0; // No cooldown
    }

    // Initialize character assignments with pseudo-random shuffle
    function _initializeCharacterAssignments() internal {
        CharacterType[NUM_PLAYERS] memory charactersToAssign = [
            CharacterType.Hero,
            CharacterType.Explorer,
            CharacterType.Innocent,
            CharacterType.Artist,
            CharacterType.Ruler,
            CharacterType.Caregiver,
            CharacterType.CommonMan,
            CharacterType.Joker,
            CharacterType.Wizard,
            CharacterType.Outlaw,
            CharacterType.Lover,
            CharacterType.Sage
        ];

        // Pseudo-random shuffle
        uint256 seed = uint256(
            keccak256(
                abi.encodePacked(
                    block.timestamp,
                    block.prevrandao,
                    address(this)
                )
            )
        );

        for (uint8 i = 0; i < NUM_PLAYERS; i++) {
            initialCharacterOrder[i] = charactersToAssign[i];
        }

        for (uint8 i = NUM_PLAYERS - 1; i > 0; i--) {
            uint8 j = uint8(seed % (i + 1));
            seed /= (i + 1);
            CharacterType temp = initialCharacterOrder[i];
            initialCharacterOrder[i] = initialCharacterOrder[j];
            initialCharacterOrder[j] = temp;
        }
    }

    constructor() {
        _initializeCharacterAssignments();
        _initializeCooldowns();
        _initializeCharacterMoves();

        // First player (creator) joins
        _joinLogic(msg.sender);

        emit GameCreated(msg.sender, ENTRY_FEE_MNT);
    }

    function joinGame() external payable {
        require(!playerData[msg.sender].hasJoined, "Already joined");
        require(numPlayersJoined < NUM_PLAYERS, "Game full");
        require(msg.value == ENTRY_FEE_MNT, "Incorrect entry fee");

        totalPrizePool += msg.value;
        _joinLogic(msg.sender);
    }

    function _joinLogic(address _playerAddr) internal {
        playerData[_playerAddr].playerAddress = _playerAddr;
        playerData[_playerAddr].character = initialCharacterOrder[
            numPlayersJoined
        ];
        playerData[_playerAddr].hasJoined = true;
        playerData[_playerAddr].inactivityTimestamp = block.timestamp;

        gamePlayerAddresses[numPlayersJoined] = _playerAddr;

        // DSU initialization
        dsuParent[_playerAddr] = _playerAddr;
        dsuSetSize[_playerAddr] = 1;

        emit PlayerJoined(
            numPlayersJoined,
            _playerAddr,
            playerData[_playerAddr].character
        );

        numPlayersJoined++;

        if (numPlayersJoined == NUM_PLAYERS) {
            _startGame();
        }
    }

    function _startGame() internal {
        gameStarted = true;
        gameStartTime = block.timestamp;
        padlocks = 1;
        seals = 1;

        // Initialize all players' move timestamps
        for (uint8 i = 0; i < NUM_PLAYERS; i++) {
            address playerAddr = gamePlayerAddresses[i];
            uint moveTypeCount = uint(MoveType.Gift) + 1;

            for (uint mt = 0; mt < moveTypeCount; mt++) {
                playerData[playerAddr].lastMoveTimestamp[mt] = 0;
            }

            playerData[playerAddr].inactivityTimestamp = block.timestamp;
        }

        // Explicitly initialize global effect timers
        pleaOfPeaceEndTime = 0;
        royalDecreeEndTime = 0;

        emit GameStarted(block.timestamp, padlocks, seals);
        emit ChestStateChanged(padlocks, seals);
    }

    // Check if a player can use a specific move
    function canUseMove(
        address _player,
        MoveType _move
    ) public view returns (bool) {
        if (!playerData[_player].hasJoined) return false;

        CharacterType character = playerData[_player].character;
        return characterCanUseMove[character][_move];
    }

    // Base function to validate an actor for a move
    function _validateAndPrepareActor(
        address _caller,
        address _actor,
        MoveType _move
    ) internal {
        if (!playerData[_caller].hasJoined) revert NotAPlayer(_caller);
        if (!playerData[_actor].hasJoined) revert NotAPlayer(_actor);

        if (_caller != _actor) {
            if (
                block.timestamp <
                playerData[_actor].inactivityTimestamp + IDLE_PLAYER_LIMIT
            ) {
                revert PlayerNotInactive();
            }
        }

        uint256 cooldownDuration = moveCooldowns[_move];
        if (cooldownDuration > 0) {
            if (
                block.timestamp <
                playerData[_actor].lastMoveTimestamp[uint256(_move)] +
                    cooldownDuration
            ) {
                revert MoveOnCooldown();
            }
        }

        playerData[_actor].lastMoveTimestamp[uint256(_move)] = block.timestamp;
        playerData[_actor].inactivityTimestamp = block.timestamp;

        if (_move != MoveType.CopycatMove) {
            _lastMoveExecuted = _move;
        }
    }

    // Distribute prizes when game ends
    function _distributePrizes(address _winningPlayer) internal {
        gameOver = true;

        // Use GameLibrary to find the root
        address winningRoot = GameLibrary.find(dsuParent, _winningPlayer);
        uint256 winnersCount = 0;

        // Count winners
        for (uint8 i = 0; i < NUM_PLAYERS; i++) {
            if (
                GameLibrary.find(dsuParent, gamePlayerAddresses[i]) ==
                winningRoot
            ) {
                winnersCount++;
            }
        }

        if (winnersCount == 0) return;

        uint256 prizePerWinner = totalPrizePool / winnersCount;
        address[] memory currentWinners = new address[](winnersCount);
        uint k = 0;

        // Collect winners
        for (uint8 i = 0; i < NUM_PLAYERS; i++) {
            address pAddr = gamePlayerAddresses[i];
            if (GameLibrary.find(dsuParent, pAddr) == winningRoot) {
                currentWinners[k++] = pAddr;
            }
        }

        // Transfer prizes
        for (uint8 i = 0; i < winnersCount; i++) {
            (bool success, ) = currentWinners[i].call{value: prizePerWinner}(
                ""
            );
            require(success, "Transfer failed");
        }

        winners = currentWinners;
        uint256 gameDuration = block.timestamp - gameStartTime;

        emit GameOver(
            padlocks,
            seals,
            currentWinners,
            prizePerWinner,
            gameDuration
        );
    }

    function getDsuParent(address player) external view returns (address) {
        return dsuParent[player];
    }
}
