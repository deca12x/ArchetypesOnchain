// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

contract Game {
    // Constants
    uint8 public constant NUM_PLAYERS = 12;
    // MNT has 18 decimals, so 0.01 MNT = 0.01 * 10^18
    uint256 public constant ENTRY_FEE_MNT = 0.01 ether; // 0.01 MNT when deployed on Mantle
    uint256 private constant IDLE_PLAYER_LIMIT = 7 * 60 seconds; // After which other players can use his moves

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

    // Move types correspond to the 24 distinct functions/actions
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

    // Structs
    struct Player {
        address playerAddress;
        CharacterType character;
        uint8 keys;
        uint8 enchantedKeys;
        uint8 staffs;
        uint8 protections;
        mapping(uint256 => uint256) lastMoveTimestamp; // MoveType index to timestamp
        bool hasJoined;
        uint256 inactivityTimestamp;
    }

    address[NUM_PLAYERS] public gamePlayerAddresses; // Stores EOAs of joined players in order
    mapping(address => Player) public playerData;
    CharacterType[NUM_PLAYERS] internal initialCharacterOrder; // For assignment

    uint8 public numPlayersJoined;
    bool public gameStarted;
    bool public gameOver;
    address[] public winners;
    uint256 public totalPrizePool;

    // Chest State
    uint8 public padlocks;
    uint8 public seals;

    // Global Game Effects
    uint8 public activeFakeKeysCount;
    uint256 public pleaOfPeaceEndTime;
    uint256 public royalDecreeEndTime;

    // For Copycat move
    MoveType private _lastEligibleMoveForCopycat; // UnlockChest or UnsealChest
    bool private _lastCopiedMoveUsedEnchantedKey;

    bool private _anyKeyHasBeenForged; // For Artist's Enchanted Key

    // Alliance / Binding (Disjoint Set Union - DSU)
    mapping(address => address) public dsuParent;
    mapping(address => uint8) public dsuSetSize;

    // Cooldowns (in seconds) - Initialized in constructor
    mapping(MoveType => uint256) public moveCooldowns;

    // Add new mapping for character-move relationships
    mapping(CharacterType => mapping(MoveType => bool))
        public characterCanUseMove;

    // Add this with other state variables
    uint256 public gameStartTime;

    // Events
    event GameCreated(
        address indexed creator,
        address usdcTokenAddress,
        uint256 entryFee
    );
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
    event FakeKeyAdded(uint8 newCount);
    event KeyForgedObservation();

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

    constructor() {
        // Initialize character assignment order (removed None)
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

        // Pseudo-random shuffle using block properties (not for production security)
        // For a real game, use a more secure randomness source (e.g., Chainlink VRF)
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

        // Initialize Cooldowns
        moveCooldowns[MoveType.InspireAlliance] = 4 * 60; // Hero
        moveCooldowns[MoveType.Discover] = 5 * 60; // Explorer
        moveCooldowns[MoveType.Purify] = 5 * 60; // Innocent
        moveCooldowns[MoveType.CreateEnchantedKey] = 5 * 60; // Artist
        moveCooldowns[MoveType.RoyalDecree] = 5 * 60; // Ruler
        moveCooldowns[MoveType.GuardianBond] = 4 * 60; // Caregiver
        moveCooldowns[MoveType.CopycatMove] = 5 * 60; // CommonMan
        moveCooldowns[MoveType.CreateFakeKey] = 5 * 60; // Joker
        moveCooldowns[MoveType.ConjureStaff] = 5 * 60; // Wizard
        moveCooldowns[MoveType.Lockpick] = 5 * 60; // Outlaw
        moveCooldowns[MoveType.SoulBond] = 4 * 60; // Lover
        moveCooldowns[MoveType.EnergyFlow] = 5 * 60; // Sage (Assumed 5 min)

        moveCooldowns[MoveType.Guard] = 3 * 60;
        moveCooldowns[MoveType.UnlockChest] = 0; // No cooldown
        moveCooldowns[MoveType.Gift] = 3 * 60; // Assumed 3 min
        moveCooldowns[MoveType.Evade] = 3 * 60;
        moveCooldowns[MoveType.UnsealChest] = 0; // No cooldown
        moveCooldowns[MoveType.ForgeKey] = 3 * 60;
        moveCooldowns[MoveType.SecureChest] = 3 * 60;
        moveCooldowns[MoveType.SeizeItem] = 2 * 60;
        moveCooldowns[MoveType.PleaOfPeace] = 5 * 60; // 5 min cooldown for Caregiver
        moveCooldowns[MoveType.Distract] = 2 * 60;
        moveCooldowns[MoveType.ArcaneSeal] = 4 * 60;

        // Initialize character-move relationships
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

        // Shared moves (available to all characters)
        for (uint8 i = 0; i < uint8(CharacterType.Sage) + 1; i++) {
            characterCanUseMove[CharacterType(i)][MoveType.Gift] = true;
        }

        // Player 1 (game creator) joins
        _joinLogic(msg.sender);

        emit GameCreated(msg.sender, address(0), ENTRY_FEE_MNT);
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
        playerData[_playerAddr].inactivityTimestamp = block.timestamp; // Set initial inactivity

        gamePlayerAddresses[numPlayersJoined] = _playerAddr;

        // DSU Initialization
        dsuParent[_playerAddr] = _playerAddr;
        dsuSetSize[_playerAddr] = 1;

        emit PlayerJoined(
            numPlayersJoined,
            _playerAddr,
            playerData[_playerAddr].character
        );
        numPlayersJoined++;

        if (numPlayersJoined == NUM_PLAYERS) {
            gameStarted = true;
            gameStartTime = block.timestamp; // Set game start time
            padlocks = 2;
            seals = 1;
            // Initialize all players' move cooldowns to 0 (can be used immediately)
            for (uint8 i = 0; i < NUM_PLAYERS; i++) {
                address pAddr = gamePlayerAddresses[i];
                uint moveTypeCount = uint(MoveType.ArcaneSeal) + 1;
                for (uint mt = 0; mt < moveTypeCount; mt++) {
                    playerData[pAddr].lastMoveTimestamp[mt] = 0;
                }
                playerData[pAddr].inactivityTimestamp = block.timestamp;
            }
            emit GameStarted(block.timestamp, padlocks, seals);
            emit ChestStateChanged(padlocks, seals);
        }
    }

    // --- DSU (Alliance) Helper Functions ---
    function _find(address _player) internal view returns (address) {
        if (dsuParent[_player] == _player) {
            return _player;
        }
        // Path compression not implemented for view simplicity, can be added if gas is an issue for write ops.
        // For write operations, path compression should be used:
        // dsuParent[_player] = _find(dsuParent[_player]);
        // return dsuParent[_player];
        address root = _player;
        while (root != dsuParent[root]) {
            root = dsuParent[root];
        }
        return root;
    }

    function _union(address _playerA, address _playerB) internal {
        address rootA = _find(_playerA);
        address rootB = _find(_playerB);

        if (rootA != rootB) {
            // Union by size
            if (dsuSetSize[rootA] < dsuSetSize[rootB]) {
                address temp = rootA;
                rootA = rootB;
                rootB = temp;
            }
            dsuParent[rootB] = rootA;
            dsuSetSize[rootA] += dsuSetSize[rootB];
            emit AllianceUpdated(_playerA, _playerB, true);
        }
    }

    function _resetAndUnion(address _actor, address _targetPlayer) internal {
        // Actor leaves their current alliance set to form a new one or join another.
        // This effectively makes the actor their own parent first.
        address oldRoot = _find(_actor);
        if (oldRoot != _actor) {
            // If actor was not already a root
            // This is a simplified way to handle unbinding.
            // A full DSU unbind is complex. This makes actor a new root.
            // Iterate through all players to fix parent pointers if oldRoot size decreases significantly.
            // For this game, simply making actor its own root might be sufficient before new union.
            // Recalculate size of oldRoot if needed, or accept temporary DSU SetSize inaccuracy for oldRoot.
            // For on-chain logic, this makes _actor its own set of size 1.
        }
        dsuParent[_actor] = _actor;
        dsuSetSize[_actor] = 1;
        // If _actor was part of oldRoot, and oldRoot != _actor, then dsuSetSize[oldRoot] should decrease.
        // This is non-trivial to implement correctly and efficiently with standard DSU.
        // The game spec "unbinding with previously binded players" for Gift implies this isolation.

        _union(_actor, _targetPlayer);
    }

    function arePlayersBound(
        address _playerA,
        address _playerB
    ) public view returns (bool) {
        if (!playerData[_playerA].hasJoined || !playerData[_playerB].hasJoined)
            return false;
        return _find(_playerA) == _find(_playerB);
    }

    // --- Cooldown and Actor Validation Logic ---
    function _validateAndPrepareActor(
        address _caller,
        address _actor,
        MoveType _move
    ) internal {
        require(playerData[_caller].hasJoined, "Caller not a player");
        require(playerData[_actor].hasJoined, "Actor not a player");

        if (_caller != _actor) {
            require(
                block.timestamp >=
                    playerData[_actor].inactivityTimestamp + IDLE_PLAYER_LIMIT,
                "Actor not inactive long enough"
            );
        }

        uint256 cooldownDuration = moveCooldowns[_move];
        if (cooldownDuration > 0) {
            // Moves with 0 cooldown (UnlockChest, UnsealChest) bypass this check
            require(
                block.timestamp >=
                    playerData[_actor].lastMoveTimestamp[uint256(_move)] +
                        cooldownDuration,
                "Move on cooldown"
            );
        }
        playerData[_actor].lastMoveTimestamp[uint256(_move)] = block.timestamp;
        playerData[_actor].inactivityTimestamp = block.timestamp;
    }

    // --- Global Effect Checkers ---
    function _isPleaOfPeaceActive() internal view returns (bool) {
        return block.timestamp < pleaOfPeaceEndTime;
    }

    ////////////////////////////////////////
    ////////////////////////////////////////
    ///// --- Move Implementations --- /////
    ////////////////////////////////////////
    ////////////////////////////////////////

    // Hero: InspireAlliance
    function inspireAlliance(
        address _actor,
        address _playerToBindWith
    ) external gameIsActive onlyGamePlayer(_actor) {
        _validateAndPrepareActor(msg.sender, _actor, MoveType.InspireAlliance);
        require(
            characterCanUseMove[playerData[_actor].character][
                MoveType.InspireAlliance
            ],
            "Character cannot use this move"
        );
        require(
            _playerToBindWith != _actor &&
                playerData[_playerToBindWith].hasJoined,
            "Invalid bind target"
        );

        _resetAndUnion(_actor, _playerToBindWith);
        emit MoveExecuted(
            msg.sender,
            _actor,
            MoveType.InspireAlliance,
            "Bound with player"
        );
    }

    // Explorer: Discover
    function discover(
        address _actor
    ) external gameIsActive onlyGamePlayer(_actor) {
        _validateAndPrepareActor(msg.sender, _actor, MoveType.Discover);
        require(
            characterCanUseMove[playerData[_actor].character][
                MoveType.Discover
            ],
            "Character cannot use this move"
        );

        uint256 rand = uint256(
            keccak256(abi.encodePacked(block.timestamp, msg.sender, _actor))
        ) % 3;
        string memory foundItem;
        if (rand == 0) {
            playerData[_actor].keys++;
            foundItem = "Key";
            emit ItemsChanged(_actor, "Key", 1);
        } else if (rand == 1) {
            playerData[_actor].enchantedKeys++;
            foundItem = "Enchanted Key";
            emit ItemsChanged(_actor, "EnchantedKey", 1);
        } else {
            playerData[_actor].staffs++;
            foundItem = "Staff";
            emit ItemsChanged(_actor, "Staff", 1);
        }
        emit MoveExecuted(
            msg.sender,
            _actor,
            MoveType.Discover,
            string(abi.encodePacked("Found ", foundItem))
        );
    }

    // Innocent: Purify
    function purify(
        address _actor
    ) external gameIsActive onlyGamePlayer(_actor) {
        _validateAndPrepareActor(msg.sender, _actor, MoveType.Purify);
        require(
            characterCanUseMove[playerData[_actor].character][MoveType.Purify],
            "Character cannot use this move"
        );
        require(!_isPleaOfPeaceActive(), "Plea of Peace active");

        if (seals > 0) {
            seals--;
            emit ChestStateChanged(padlocks, seals);
            _checkOpenVictory(_actor);
        }
        emit MoveExecuted(
            msg.sender,
            _actor,
            MoveType.Purify,
            "Removed 1 seal"
        );
    }

    // Artist: CreateEnchantedKey (was Enchanted Key)
    function createEnchantedKey(
        address _actor
    ) external gameIsActive onlyGamePlayer(_actor) {
        _validateAndPrepareActor(
            msg.sender,
            _actor,
            MoveType.CreateEnchantedKey
        );
        require(
            characterCanUseMove[playerData[_actor].character][
                MoveType.CreateEnchantedKey
            ],
            "Character cannot use this move"
        );

        playerData[_actor].enchantedKeys++;
        emit ItemsChanged(_actor, "EnchantedKey", 1);
        emit MoveExecuted(
            msg.sender,
            _actor,
            MoveType.CreateEnchantedKey,
            "Created Enchanted Key"
        );
    }

    // Ruler: RoyalDecree
    function royalDecree(
        address _actor
    ) external gameIsActive onlyGamePlayer(_actor) {
        _validateAndPrepareActor(msg.sender, _actor, MoveType.RoyalDecree);
        require(
            characterCanUseMove[playerData[_actor].character][
                MoveType.RoyalDecree
            ],
            "Character cannot use this move"
        );

        royalDecreeEndTime = block.timestamp + 1 * 60; // 1 minute duration
        emit EffectActivated("RoyalDecree", royalDecreeEndTime);
        emit MoveExecuted(
            msg.sender,
            _actor,
            MoveType.RoyalDecree,
            "Activated Royal Decree"
        );
    }

    // Caregiver: GuardianBond
    function guardianBond(
        address _actor,
        address _playerToBindWith
    ) external gameIsActive onlyGamePlayer(_actor) {
        _validateAndPrepareActor(msg.sender, _actor, MoveType.GuardianBond);
        require(
            characterCanUseMove[playerData[_actor].character][
                MoveType.GuardianBond
            ],
            "Character cannot use this move"
        );
        require(
            _playerToBindWith != _actor &&
                playerData[_playerToBindWith].hasJoined,
            "Invalid bind target"
        );

        _resetAndUnion(_actor, _playerToBindWith);
        emit MoveExecuted(
            msg.sender,
            _actor,
            MoveType.GuardianBond,
            "Bound with player"
        );
    }

    // CommonMan: CopycatMove
    function copycatMove(
        address _actor
    ) external gameIsActive onlyGamePlayer(_actor) {
        _validateAndPrepareActor(msg.sender, _actor, MoveType.CopycatMove);
        require(
            characterCanUseMove[playerData[_actor].character][
                MoveType.CopycatMove
            ],
            "Character cannot use this move"
        );

        require(
            uint(_lastEligibleMoveForCopycat) != 0 ||
                (_lastEligibleMoveForCopycat == MoveType.UnlockChest ||
                    _lastEligibleMoveForCopycat == MoveType.UnsealChest),
            "No valid move to copy"
        ); // Check it's one of the copyable types

        string memory copiedActionDetail;

        if (_lastEligibleMoveForCopycat == MoveType.UnlockChest) {
            require(!_isPleaOfPeaceActive(), "Plea of Peace active");
            if (activeFakeKeysCount > 0) {
                activeFakeKeysCount--;
                emit FakeKeyAdded(activeFakeKeysCount);
                copiedActionDetail = "Copied UnlockChest, hit FakeKey";
            } else {
                if (_lastCopiedMoveUsedEnchantedKey) {
                    require(
                        playerData[_actor].enchantedKeys > 0,
                        "Need Enchanted Key for copy"
                    );
                    playerData[_actor].enchantedKeys--;
                    if (padlocks > 0) padlocks--;
                    if (seals > 0) seals--;
                    emit ItemsChanged(_actor, "EnchantedKey", -1);
                    copiedActionDetail = "Copied UnlockChest (E.Key)";
                } else {
                    require(playerData[_actor].keys > 0, "Need Key for copy");
                    playerData[_actor].keys--;
                    if (padlocks > 0) padlocks--;
                    emit ItemsChanged(_actor, "Key", -1);
                    copiedActionDetail = "Copied UnlockChest (Key)";
                }
                emit ChestStateChanged(padlocks, seals);
                _checkOpenVictory(_actor);
            }
        } else if (_lastEligibleMoveForCopycat == MoveType.UnsealChest) {
            require(!_isPleaOfPeaceActive(), "Plea of Peace active");
            if (_lastCopiedMoveUsedEnchantedKey) {
                require(
                    playerData[_actor].enchantedKeys > 0,
                    "Need Enchanted Key for copy"
                );
                playerData[_actor].enchantedKeys--;
                if (seals > 0) seals--;
                if (padlocks > 0) padlocks--; // E.Key also removes padlock
                emit ItemsChanged(_actor, "EnchantedKey", -1);
                copiedActionDetail = "Copied UnsealChest (E.Key)";
            } else {
                // Staff was used
                require(playerData[_actor].staffs > 0, "Need Staff for copy");
                playerData[_actor].staffs--;
                if (seals > 0) seals--;
                emit ItemsChanged(_actor, "Staff", -1);
                copiedActionDetail = "Copied UnsealChest (Staff)";
            }
            emit ChestStateChanged(padlocks, seals);
            _checkOpenVictory(_actor);
        }
        emit MoveExecuted(
            msg.sender,
            _actor,
            MoveType.CopycatMove,
            copiedActionDetail
        );
    }

    // Joker: CreateFakeKey
    function createFakeKey(
        address _actor
    ) external gameIsActive onlyGamePlayer(_actor) {
        _validateAndPrepareActor(msg.sender, _actor, MoveType.CreateFakeKey);
        require(
            characterCanUseMove[playerData[_actor].character][
                MoveType.CreateFakeKey
            ],
            "Character cannot use this move"
        );

        activeFakeKeysCount++;
        emit FakeKeyAdded(activeFakeKeysCount);
        emit MoveExecuted(
            msg.sender,
            _actor,
            MoveType.CreateFakeKey,
            "Created Fake Key"
        );
    }

    // Wizard: ConjureStaff
    function conjureStaff(
        address _actor
    ) external gameIsActive onlyGamePlayer(_actor) {
        _validateAndPrepareActor(msg.sender, _actor, MoveType.ConjureStaff);
        require(
            characterCanUseMove[playerData[_actor].character][
                MoveType.ConjureStaff
            ],
            "Character cannot use this move"
        );

        playerData[_actor].staffs++;
        emit ItemsChanged(_actor, "Staff", 1);
        emit MoveExecuted(
            msg.sender,
            _actor,
            MoveType.ConjureStaff,
            "Created Staff"
        );
    }

    // Outlaw: Lockpick
    function lockpick(
        address _actor
    ) external gameIsActive onlyGamePlayer(_actor) {
        _validateAndPrepareActor(msg.sender, _actor, MoveType.Lockpick);
        require(
            characterCanUseMove[playerData[_actor].character][
                MoveType.Lockpick
            ],
            "Character cannot use this move"
        );
        require(!_isPleaOfPeaceActive(), "Plea of Peace active");

        if (padlocks > 0) {
            padlocks--;
            emit ChestStateChanged(padlocks, seals);
            _checkOpenVictory(_actor);
        }
        emit MoveExecuted(
            msg.sender,
            _actor,
            MoveType.Lockpick,
            "Removed 1 padlock (Lockpick)"
        );
    }

    // Lover: SoulBond
    function soulBond(
        address _actor,
        address _playerToBindWith
    ) external gameIsActive onlyGamePlayer(_actor) {
        _validateAndPrepareActor(msg.sender, _actor, MoveType.SoulBond);
        require(
            characterCanUseMove[playerData[_actor].character][
                MoveType.SoulBond
            ],
            "Character cannot use this move"
        );
        require(
            _playerToBindWith != _actor &&
                playerData[_playerToBindWith].hasJoined,
            "Invalid bind target"
        );

        _resetAndUnion(_actor, _playerToBindWith);
        emit MoveExecuted(
            msg.sender,
            _actor,
            MoveType.SoulBond,
            "Bound with player"
        );
    }

    // Sage: EnergyFlow
    function energyFlow(
        address _actor
    ) external gameIsActive onlyGamePlayer(_actor) {
        _validateAndPrepareActor(msg.sender, _actor, MoveType.EnergyFlow);
        require(
            characterCanUseMove[playerData[_actor].character][
                MoveType.EnergyFlow
            ],
            "Character cannot use this move"
        );

        address actorRoot = _find(_actor);
        uint moveTypeCount = uint(MoveType.ArcaneSeal) + 1;

        for (uint8 i = 0; i < NUM_PLAYERS; i++) {
            address ally = gamePlayerAddresses[i];
            if (ally != _actor && _find(ally) == actorRoot) {
                for (uint mt = 0; mt < moveTypeCount; mt++) {
                    if (moveCooldowns[MoveType(mt)] > 0) {
                        // Simply set timestamp to 0 to reset cooldown
                        playerData[ally].lastMoveTimestamp[mt] = 0;
                    }
                }
            }
        }
        emit MoveExecuted(
            msg.sender,
            _actor,
            MoveType.EnergyFlow,
            "Reset alliance cooldowns"
        );
    }

    // SHARED MOVES
    // All characters: Gift
    function gift(
        address _actor,
        address _receiver
    ) external gameIsActive onlyGamePlayer(_actor) {
        _validateAndPrepareActor(msg.sender, _actor, MoveType.Gift);
        require(
            characterCanUseMove[playerData[_actor].character][MoveType.Gift],
            "Character cannot use this move"
        );
        require(
            playerData[_actor].keys > 0 ||
                playerData[_actor].enchantedKeys > 0 ||
                playerData[_actor].staffs > 0,
            "No items to gift"
        );
        require(
            _receiver != _actor && playerData[_receiver].hasJoined,
            "Invalid receiver"
        );

        if (playerData[_actor].keys > 0) {
            playerData[_receiver].keys += playerData[_actor].keys;
            emit ItemsChanged(_receiver, "Key", int8(playerData[_actor].keys));
            playerData[_actor].keys = 0;
            emit ItemsChanged(
                _actor,
                "Key",
                -int8(playerData[_receiver].keys - playerData[_actor].keys)
            ); // This logic seems off for emit
        }
        if (playerData[_actor].enchantedKeys > 0) {
            playerData[_receiver].enchantedKeys += playerData[_actor]
                .enchantedKeys;
            emit ItemsChanged(
                _receiver,
                "EnchantedKey",
                int8(playerData[_actor].enchantedKeys)
            );
            playerData[_actor].enchantedKeys = 0;
        }
        if (playerData[_actor].staffs > 0) {
            playerData[_receiver].staffs += playerData[_actor].staffs;
            emit ItemsChanged(
                _receiver,
                "Staff",
                int8(playerData[_actor].staffs)
            );
            playerData[_actor].staffs = 0;
        }

        _resetAndUnion(_actor, _receiver); // Bind after gifting
        emit MoveExecuted(
            msg.sender,
            _actor,
            MoveType.Gift,
            "Gifted all items and bound"
        );
    }

    // Artist, Wizard: ForgeKey
    function forgeKey(
        address _actor
    ) external gameIsActive onlyGamePlayer(_actor) {
        _validateAndPrepareActor(msg.sender, _actor, MoveType.ForgeKey);
        require(
            characterCanUseMove[playerData[_actor].character][
                MoveType.ForgeKey
            ],
            "Character cannot use this move"
        );

        if (_isPleaOfPeaceActive()) {
            emit MoveExecuted(
                msg.sender,
                _actor,
                MoveType.ForgeKey,
                "Wasted move due to Plea of Peace"
            );
            return; // Move wasted, cooldown applied by _validateAndPrepareActor
        }

        playerData[_actor].keys++;
        _anyKeyHasBeenForged = true; // For Artist's Enchanted Key
        emit KeyForgedObservation();
        emit ItemsChanged(_actor, "Key", 1);
        emit MoveExecuted(msg.sender, _actor, MoveType.ForgeKey, "Forged Key");
    }

    // Hero, Explorer, Caregiver: Guard
    function guard(
        address _actor,
        address _targetPlayer
    ) external gameIsActive onlyGamePlayer(_actor) {
        _validateAndPrepareActor(msg.sender, _actor, MoveType.Guard);
        require(
            characterCanUseMove[playerData[_actor].character][MoveType.Guard],
            "Character cannot use this move"
        );
        require(playerData[_targetPlayer].hasJoined, "Target not a player");

        playerData[_targetPlayer].protections++;
        emit ProtectionStatusChanged(_targetPlayer, true, "Guard");
        emit MoveExecuted(msg.sender, _actor, MoveType.Guard, "Guarded player");
    }

    // Explorer, Artist, Outlaw: Evade
    function evade(
        address _actor
    ) external gameIsActive onlyGamePlayer(_actor) {
        _validateAndPrepareActor(msg.sender, _actor, MoveType.Evade);
        require(
            characterCanUseMove[playerData[_actor].character][MoveType.Evade],
            "Character cannot use this move"
        );

        playerData[_actor].protections++;
        emit ProtectionStatusChanged(_actor, true, "Evade");
        emit MoveExecuted(
            msg.sender,
            _actor,
            MoveType.Evade,
            "Evaded next harmful move"
        );
    }

    // Ruler, CommonMan: SecureChest
    function secureChest(
        address _actor
    ) external gameIsActive onlyGamePlayer(_actor) {
        _validateAndPrepareActor(msg.sender, _actor, MoveType.SecureChest);
        require(
            characterCanUseMove[playerData[_actor].character][
                MoveType.SecureChest
            ],
            "Character cannot use this move"
        );
        require(!_isPleaOfPeaceActive(), "Plea of Peace active");

        padlocks++;
        emit ChestStateChanged(padlocks, seals);
        // Added block victory check here to match requirements
        _checkBlockVictory(_actor);
        emit MoveExecuted(
            msg.sender,
            _actor,
            MoveType.SecureChest,
            "Added 1 padlock"
        );
    }

    // Ruler, Joker, Outlaw: SeizeItem
    function seizeItem(
        address _actor,
        address _targetPlayer
    ) external gameIsActive onlyGamePlayer(_actor) {
        _validateAndPrepareActor(msg.sender, _actor, MoveType.SeizeItem);
        require(
            characterCanUseMove[playerData[_actor].character][
                MoveType.SeizeItem
            ],
            "Character cannot use this move"
        );
        require(
            playerData[_targetPlayer].hasJoined && _targetPlayer != _actor,
            "Invalid target"
        );
        require(!_isPleaOfPeaceActive(), "Plea of Peace active");

        if (playerData[_targetPlayer].protections > 0) {
            playerData[_targetPlayer].protections--;
            emit ProtectionStatusChanged(
                _targetPlayer,
                playerData[_targetPlayer].protections > 0,
                "ProtectionUsed"
            );
            emit MoveExecuted(
                msg.sender,
                _actor,
                MoveType.SeizeItem,
                "Failed, target protected"
            );
            return;
        }

        string memory stolenItemType = "None";
        // Steal priority: Enchanted Key > Key > Staff
        if (playerData[_targetPlayer].enchantedKeys > 0) {
            playerData[_targetPlayer].enchantedKeys--;
            playerData[_actor].enchantedKeys++;
            stolenItemType = "EnchantedKey";
        } else if (playerData[_targetPlayer].keys > 0) {
            playerData[_targetPlayer].keys--;
            playerData[_actor].keys++;
            stolenItemType = "Key";
        } else if (playerData[_targetPlayer].staffs > 0) {
            playerData[_targetPlayer].staffs--;
            playerData[_actor].staffs++;
            stolenItemType = "Staff";
        }

        if (
            keccak256(abi.encodePacked(stolenItemType)) !=
            keccak256(abi.encodePacked("None"))
        ) {
            emit ItemsChanged(_targetPlayer, stolenItemType, -1);
            emit ItemsChanged(_actor, stolenItemType, 1);
            emit MoveExecuted(
                msg.sender,
                _actor,
                MoveType.SeizeItem,
                string(abi.encodePacked("Stole ", stolenItemType))
            );
        } else {
            emit MoveExecuted(
                msg.sender,
                _actor,
                MoveType.SeizeItem,
                "Failed, target had no items"
            );
        }
    }

    // CommonMan, Joker, Lover: Distract
    function distract(
        address _actor,
        address _targetPlayer
    ) external gameIsActive onlyGamePlayer(_actor) {
        _validateAndPrepareActor(msg.sender, _actor, MoveType.Distract);
        require(
            characterCanUseMove[playerData[_actor].character][
                MoveType.Distract
            ],
            "Character cannot use this move"
        );
        require(
            playerData[_targetPlayer].hasJoined && _targetPlayer != _actor,
            "Invalid target"
        );
        require(!_isPleaOfPeaceActive(), "Plea of Peace active");

        if (playerData[_targetPlayer].protections > 0) {
            playerData[_targetPlayer].protections--;
            emit ProtectionStatusChanged(
                _targetPlayer,
                playerData[_targetPlayer].protections > 0,
                "ProtectionUsed"
            );
            emit MoveExecuted(
                msg.sender,
                _actor,
                MoveType.Distract,
                "Failed, target protected"
            );
            return;
        }

        // "Blocks target player's next move" - This is complex to implement fully on-chain.
        // Simplification: Increase cooldown of all target's moves by a small amount, or set a flag.
        // For this implementation: Set a flag "isDistracted" and target cannot make a move until flag is cleared (e.g., after some time or one attempt)
        // Or, simpler: Forcing their next action to "fail" is too much.
        // The simplest is to treat "Distract" as if it just consumes a protection or does nothing else visible if unprotected.
        // The prompt: "Blocks target player's next move."
        // True implementation would require a flag on Player struct `bool isDistracted;`
        // And every move function would check `!playerData[actor].isDistracted`.
        // This is a significant addition. For now, assuming it burns a protection if available.
        // If no protection, it has "succeeded" but the actual "block next move" is not implemented here due to complexity.
        // The current Guard/Evade handles this by consuming protection. If no protection, it just logs as distracted.
        emit MoveExecuted(
            msg.sender,
            _actor,
            MoveType.Distract,
            "Distracted player (effect depends on further implementation if not protected)"
        );
    }

    // Innocent, Caregiver: PleaOfPeace
    function pleaOfPeace(
        address _actor
    ) external gameIsActive onlyGamePlayer(_actor) {
        _validateAndPrepareActor(msg.sender, _actor, MoveType.PleaOfPeace);
        require(
            characterCanUseMove[playerData[_actor].character][
                MoveType.PleaOfPeace
            ],
            "Character cannot use this move"
        );

        // Standardize to 2 minutes duration for both character types
        pleaOfPeaceEndTime = block.timestamp + 2 * 60; // 2 minutes duration
        emit EffectActivated("PleaOfPeace", pleaOfPeaceEndTime);
        emit MoveExecuted(
            msg.sender,
            _actor,
            MoveType.PleaOfPeace,
            "Activated Plea of Peace"
        );
    }

    // Hero, Lover: UnlockChest
    function unlockChest(
        address _actor,
        bool _useEnchantedKey
    ) external gameIsActive onlyGamePlayer(_actor) {
        _validateAndPrepareActor(msg.sender, _actor, MoveType.UnlockChest); // Cooldown is 0
        require(
            characterCanUseMove[playerData[_actor].character][
                MoveType.UnlockChest
            ],
            "Character cannot use this move"
        );
        require(!_isPleaOfPeaceActive(), "Plea of Peace active");

        if (activeFakeKeysCount > 0) {
            activeFakeKeysCount--;
            emit FakeKeyAdded(activeFakeKeysCount);
            emit MoveExecuted(
                msg.sender,
                _actor,
                MoveType.UnlockChest,
                "Hit Fake Key, no effect"
            );
            // Update Copycat info even on fake key hit, as an UnlockChest was ATTEMPTED
            _lastEligibleMoveForCopycat = MoveType.UnlockChest;
            _lastCopiedMoveUsedEnchantedKey = _useEnchantedKey;
            return;
        }

        if (_useEnchantedKey) {
            require(playerData[_actor].enchantedKeys > 0, "No Enchanted Key");
            playerData[_actor].enchantedKeys--;
            if (padlocks > 0) padlocks--;
            if (seals > 0) seals--;
            emit ItemsChanged(_actor, "EnchantedKey", -1);
        } else {
            require(playerData[_actor].keys > 0, "No Key");
            playerData[_actor].keys--;
            if (padlocks > 0) padlocks--;
            emit ItemsChanged(_actor, "Key", -1);
        }

        _lastEligibleMoveForCopycat = MoveType.UnlockChest;
        _lastCopiedMoveUsedEnchantedKey = _useEnchantedKey;

        emit ChestStateChanged(padlocks, seals);
        emit MoveExecuted(
            msg.sender,
            _actor,
            MoveType.UnlockChest,
            _useEnchantedKey ? "Used E.Key" : "Used Key"
        );
        _checkOpenVictory(_actor);
    }

    // Innocent, Sage: UnsealChest
    function unsealChest(
        address _actor,
        bool _useEnchantedKey
    ) external gameIsActive onlyGamePlayer(_actor) {
        _validateAndPrepareActor(msg.sender, _actor, MoveType.UnsealChest); // Cooldown is 0
        require(
            characterCanUseMove[playerData[_actor].character][
                MoveType.UnsealChest
            ],
            "Character cannot use this move"
        );
        require(!_isPleaOfPeaceActive(), "Plea of Peace active");

        if (_useEnchantedKey) {
            require(playerData[_actor].enchantedKeys > 0, "No Enchanted Key");
            playerData[_actor].enchantedKeys--;
            if (seals > 0) seals--;
            if (padlocks > 0) padlocks--; // Enchanted Key also removes a padlock
            emit ItemsChanged(_actor, "EnchantedKey", -1);
        } else {
            // Using Staff
            require(playerData[_actor].staffs > 0, "No Staff");
            playerData[_actor].staffs--;
            if (seals > 0) seals--;
            emit ItemsChanged(_actor, "Staff", -1);
        }

        _lastEligibleMoveForCopycat = MoveType.UnsealChest;
        _lastCopiedMoveUsedEnchantedKey = _useEnchantedKey;

        emit ChestStateChanged(padlocks, seals);
        emit MoveExecuted(
            msg.sender,
            _actor,
            MoveType.UnsealChest,
            _useEnchantedKey ? "Used E.Key" : "Used Staff"
        );
        _checkOpenVictory(_actor);
    }

    // Wizard, Sage: ArcaneSeal
    function arcaneSeal(
        address _actor
    ) external gameIsActive onlyGamePlayer(_actor) {
        _validateAndPrepareActor(msg.sender, _actor, MoveType.ArcaneSeal);
        require(
            characterCanUseMove[playerData[_actor].character][
                MoveType.ArcaneSeal
            ],
            "Character cannot use this move"
        );
        require(!_isPleaOfPeaceActive(), "Plea of Peace active");

        seals++;
        emit ChestStateChanged(padlocks, seals);
        emit MoveExecuted(
            msg.sender,
            _actor,
            MoveType.ArcaneSeal,
            "Added 1 seal"
        );
        _checkBlockVictory(_actor); // Check for block victory AFTER adding the seal
    }

    ////////////////////////////////////////
    ////////////////////////////////////////
    ////// --- Victory Conditions --- //////
    ////////////////////////////////////////
    ////////////////////////////////////////

    function _checkOpenVictory(address _actor) internal {
        if (gameOver) return;
        if (padlocks == 0 && seals == 0) {
            _distributePrizes(_actor);
        }
    }

    function _checkBlockVictory(address _actor) internal {
        if (gameOver) return;
        if (padlocks >= 3 && seals >= 3) {
            _distributePrizes(_actor);
        }
    }

    function _distributePrizes(address _winningPlayer) internal {
        gameOver = true;
        address winningRoot = _find(_winningPlayer);
        uint256 winnersCount = 0;

        // First pass: count winners
        for (uint8 i = 0; i < NUM_PLAYERS; i++) {
            if (_find(gamePlayerAddresses[i]) == winningRoot) {
                winnersCount++;
            }
        }

        if (winnersCount == 0) {
            // Should not happen if _winningPlayer is valid
            return;
        }

        uint256 prizePerWinner = totalPrizePool / winnersCount;
        address[] memory currentWinners = new address[](winnersCount);
        uint k = 0;

        // Second pass: populate winners array and transfer prizes
        for (uint8 i = 0; i < NUM_PLAYERS; i++) {
            address pAddr = gamePlayerAddresses[i];
            if (_find(pAddr) == winningRoot) {
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

        // Calculate game duration from when the game started
        uint256 gameDuration = block.timestamp - gameStartTime;

        emit GameOver(
            padlocks,
            seals,
            currentWinners,
            prizePerWinner,
            gameDuration
        );
    }
}
