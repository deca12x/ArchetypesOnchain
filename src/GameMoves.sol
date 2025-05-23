// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./GameCore.sol";

contract GameMoves is GameCore {
    // --- Optimized Constants (use uint8 instead of strings where possible) ---
    uint8 constant ITEM_KEY = 0;
    uint8 constant ITEM_ENCHANTED_KEY = 1;
    uint8 constant ITEM_STAFF = 2;

    uint8 constant PROTECTION_GUARD = 0;
    uint8 constant PROTECTION_EVADE = 1;

    // Move categories using bit flags
    uint8 constant MOVE_CAT_ALLIANCE = 1;
    uint8 constant MOVE_CAT_ITEM_CREATE = 2;
    uint8 constant MOVE_CAT_CHEST_LOCK = 4;
    uint8 constant MOVE_CAT_CHEST_UNLOCK = 8;
    uint8 constant MOVE_CAT_PROTECTION = 16;
    uint8 constant MOVE_CAT_GLOBAL = 32;

    // Simplified category mapping
    mapping(MoveType => uint8) private moveCategory;
    MoveType public lastMoveExecuted;

    // Events specific to GameMoves
    event MoveResult(
        address indexed caller,
        address indexed actor,
        MoveType indexed moveType,
        uint8 result
    );
    event FakeKeyAdded(uint8 newCount);
    event KeyForgedObservation();

    constructor() {
        _initCategories();
    }

    function _initCategories() internal {
        // Alliance moves
        moveCategory[MoveType.InspireAlliance] = MOVE_CAT_ALLIANCE;
        moveCategory[MoveType.GuardianBond] = MOVE_CAT_ALLIANCE;
        moveCategory[MoveType.SoulBond] = MOVE_CAT_ALLIANCE;

        // Item creation
        moveCategory[MoveType.CreateEnchantedKey] = MOVE_CAT_ITEM_CREATE;
        moveCategory[MoveType.ConjureStaff] = MOVE_CAT_ITEM_CREATE;
        moveCategory[MoveType.ForgeKey] = MOVE_CAT_ITEM_CREATE;
        moveCategory[MoveType.CreateFakeKey] = MOVE_CAT_ITEM_CREATE;

        // Chest locking
        moveCategory[MoveType.SecureChest] = MOVE_CAT_CHEST_LOCK;
        moveCategory[MoveType.ArcaneSeal] = MOVE_CAT_CHEST_LOCK;

        // Chest unlocking
        moveCategory[MoveType.Lockpick] = MOVE_CAT_CHEST_UNLOCK;
        moveCategory[MoveType.Purify] = MOVE_CAT_CHEST_UNLOCK;
        moveCategory[MoveType.UnlockChest] = MOVE_CAT_CHEST_UNLOCK;
        moveCategory[MoveType.UnsealChest] = MOVE_CAT_CHEST_UNLOCK;

        // Protection
        moveCategory[MoveType.Guard] = MOVE_CAT_PROTECTION;
        moveCategory[MoveType.Evade] = MOVE_CAT_PROTECTION;

        // Global effects
        moveCategory[MoveType.RoyalDecree] = MOVE_CAT_GLOBAL;
        moveCategory[MoveType.PleaOfPeace] = MOVE_CAT_GLOBAL;
    }

    // --- Main Execute Move Function ---
    function executeMove(
        MoveType _moveType,
        address _actor,
        address _targetPlayer,
        bool _useEnchantedItem,
        uint8 _additionalParam
    ) public gameIsActive onlyGamePlayer(_actor) {
        _validateAndPrepareActor(msg.sender, _actor, _moveType);
        require(canUseMove(_actor, _moveType), "Cannot use move");

        uint8 category = moveCategory[_moveType];
        uint8 result = 0;

        if (category & MOVE_CAT_ALLIANCE != 0) {
            result = _execAlliance(_actor, _targetPlayer);
        } else if (category & MOVE_CAT_ITEM_CREATE != 0) {
            result = _execItemCreate(_actor, _moveType);
        } else if (category & MOVE_CAT_CHEST_LOCK != 0) {
            result = _execChestLock(_actor, _moveType);
        } else if (category & MOVE_CAT_CHEST_UNLOCK != 0) {
            result = _execChestUnlock(_actor, _moveType, _useEnchantedItem);
        } else if (category & MOVE_CAT_PROTECTION != 0) {
            result = _execProtection(_actor, _targetPlayer, _moveType);
        } else if (category & MOVE_CAT_GLOBAL != 0) {
            result = _execGlobal(_actor, _moveType);
        } else {
            result = _execSpecial(
                _actor,
                _targetPlayer,
                _moveType,
                _additionalParam
            );
        }

        if (_moveType != MoveType.CopycatMove) {
            lastMoveExecuted = _moveType;
        }

        emit MoveResult(msg.sender, _actor, _moveType, result);
    }

    // --- Optimized Category Implementations ---
    function _execAlliance(
        address _actor,
        address _target
    ) internal returns (uint8) {
        require(
            _target != _actor && playerData[_target].hasJoined,
            "Invalid target"
        );

        bool success = GameLibrary.resetAndUnion(
            dsuParent,
            dsuSetSize,
            _actor,
            _target
        );
        if (success) {
            emit AllianceUpdated(_actor, _target, true);
            return 1; // Success
        }
        return 0; // Failed
    }

    function _execItemCreate(
        address _actor,
        MoveType _moveType
    ) internal returns (uint8) {
        if (_moveType == MoveType.CreateEnchantedKey) {
            _modifyPlayerItem(_actor, ITEM_ENCHANTED_KEY, 1);
            return 1;
        } else if (_moveType == MoveType.ConjureStaff) {
            _modifyPlayerItem(_actor, ITEM_STAFF, 1);
            return 2;
        } else if (_moveType == MoveType.ForgeKey) {
            if (GameLibrary.isPleaOfPeaceActive(pleaOfPeaceEndTime)) {
                return 0; // Wasted
            }
            _modifyPlayerItem(_actor, ITEM_KEY, 1);
            emit KeyForgedObservation();
            return 3;
        } else if (_moveType == MoveType.CreateFakeKey) {
            activeFakeKeysCount++;
            emit FakeKeyAdded(activeFakeKeysCount);
            return 4;
        }
        return 0;
    }

    function _execChestLock(
        address _actor,
        MoveType _moveType
    ) internal returns (uint8) {
        require(
            !GameLibrary.isPleaOfPeaceActive(pleaOfPeaceEndTime),
            "Peace active"
        );

        if (_moveType == MoveType.SecureChest) {
            padlocks++;
        } else {
            seals++;
        }

        emit ChestStateChanged(padlocks, seals);
        _checkBlockVictory(_actor);
        return 1;
    }

    function _execChestUnlock(
        address _actor,
        MoveType _moveType,
        bool _useEnchantedItem
    ) internal returns (uint8) {
        require(
            !GameLibrary.isPleaOfPeaceActive(pleaOfPeaceEndTime),
            "Peace active"
        );

        // Check fake keys first
        if (
            (_moveType == MoveType.UnlockChest ||
                _moveType == MoveType.UnsealChest) && activeFakeKeysCount > 0
        ) {
            activeFakeKeysCount--;
            emit FakeKeyAdded(activeFakeKeysCount);
            return 0; // Hit fake key
        }

        bool changed = false;

        if (_moveType == MoveType.Lockpick && padlocks > 0) {
            padlocks--;
            changed = true;
        } else if (_moveType == MoveType.Purify && seals > 0) {
            seals--;
            changed = true;
        } else if (
            _moveType == MoveType.UnlockChest ||
            _moveType == MoveType.UnsealChest
        ) {
            if (_useEnchantedItem) {
                require(playerData[_actor].enchantedKeys > 0, "No E.Key");
                _modifyPlayerItem(_actor, ITEM_ENCHANTED_KEY, -1);
                if (padlocks > 0) padlocks--;
                if (seals > 0) seals--;
                changed = true;
            } else {
                bool isUnlock = _moveType == MoveType.UnlockChest;
                if (isUnlock) {
                    require(playerData[_actor].keys > 0, "No Key");
                    _modifyPlayerItem(_actor, ITEM_KEY, -1);
                    if (padlocks > 0) padlocks--;
                } else {
                    require(playerData[_actor].staffs > 0, "No Staff");
                    _modifyPlayerItem(_actor, ITEM_STAFF, -1);
                    if (seals > 0) seals--;
                }
                changed = true;
            }
        }

        if (changed) {
            emit ChestStateChanged(padlocks, seals);
            _checkOpenVictory(_actor);
            return 1;
        }
        return 0;
    }

    function _execProtection(
        address _actor,
        address _target,
        MoveType _moveType
    ) internal returns (uint8) {
        address protectee = _target == address(0) ? _actor : _target;

        if (_target != address(0)) {
            require(playerData[_target].hasJoined, "Invalid target");
        }

        playerData[protectee].protections++;
        emit ProtectionStatusChanged(
            protectee,
            true,
            _moveType == MoveType.Evade ? "Evade" : "Guard"
        );
        return 1;
    }

    function _execGlobal(
        address _actor,
        MoveType _moveType
    ) internal returns (uint8) {
        if (_moveType == MoveType.RoyalDecree) {
            royalDecreeEndTime = block.timestamp + 60;
            emit EffectActivated("RoyalDecree", royalDecreeEndTime);
        } else {
            pleaOfPeaceEndTime = block.timestamp + 120;
            emit EffectActivated("PleaOfPeace", pleaOfPeaceEndTime);
        }
        return 1;
    }

    function _execSpecial(
        address _actor,
        address _target,
        MoveType _moveType,
        uint8 _param
    ) internal returns (uint8) {
        if (_moveType == MoveType.Discover) {
            uint256 rand = uint256(
                keccak256(abi.encodePacked(block.timestamp, msg.sender, _actor))
            ) % 3;
            _modifyPlayerItem(_actor, uint8(rand), 1);
            return uint8(rand + 1);
        } else if (_moveType == MoveType.CopycatMove) {
            require(
                uint(lastMoveExecuted) != 0 &&
                    lastMoveExecuted != MoveType.CopycatMove,
                "No valid move"
            );
            return 1;
        } else if (_moveType == MoveType.EnergyFlow) {
            return _execEnergyFlow(_actor);
        } else if (_moveType == MoveType.SeizeItem) {
            return _execSeizeItem(_actor, _target);
        } else if (_moveType == MoveType.Distract) {
            return _execDistract(_actor, _target);
        } else if (_moveType == MoveType.Gift) {
            return _execGift(_actor, _target);
        }
        return 0;
    }

    function _execEnergyFlow(address _actor) internal returns (uint8) {
        address actorRoot = GameLibrary.find(dsuParent, _actor);
        uint moveTypeCount = uint(MoveType.Gift) + 1;

        for (uint8 i = 0; i < NUM_PLAYERS; i++) {
            address ally = gamePlayerAddresses[i];
            if (
                ally != _actor && GameLibrary.find(dsuParent, ally) == actorRoot
            ) {
                for (uint mt = 0; mt < moveTypeCount; mt++) {
                    if (moveCooldowns[MoveType(mt)] > 0) {
                        playerData[ally].lastMoveTimestamp[mt] = 0;
                    }
                }
            }
        }
        return 1;
    }

    function _execSeizeItem(
        address _actor,
        address _target
    ) internal returns (uint8) {
        require(
            playerData[_target].hasJoined && _target != _actor,
            "Invalid target"
        );
        require(
            !GameLibrary.isPleaOfPeaceActive(pleaOfPeaceEndTime),
            "Peace active"
        );

        if (_consumeProtection(_target)) return 0;

        uint8 itemType = 255; // None
        if (playerData[_target].enchantedKeys > 0) {
            itemType = ITEM_ENCHANTED_KEY;
        } else if (playerData[_target].keys > 0) {
            itemType = ITEM_KEY;
        } else if (playerData[_target].staffs > 0) {
            itemType = ITEM_STAFF;
        }

        if (itemType != 255) {
            _modifyPlayerItem(_target, itemType, -1);
            _modifyPlayerItem(_actor, itemType, 1);
            return itemType + 1;
        }
        return 0;
    }

    function _execDistract(
        address _actor,
        address _target
    ) internal returns (uint8) {
        require(
            playerData[_target].hasJoined && _target != _actor,
            "Invalid target"
        );
        require(
            !GameLibrary.isPleaOfPeaceActive(pleaOfPeaceEndTime),
            "Peace active"
        );

        return _consumeProtection(_target) ? 0 : 1;
    }

    function _execGift(
        address _actor,
        address _receiver
    ) internal returns (uint8) {
        require(
            playerData[_actor].keys > 0 ||
                playerData[_actor].enchantedKeys > 0 ||
                playerData[_actor].staffs > 0,
            "No items"
        );
        require(
            _receiver != _actor && playerData[_receiver].hasJoined,
            "Invalid receiver"
        );

        uint8 totalGifted = 0;

        if (playerData[_actor].keys > 0) {
            uint8 amount = playerData[_actor].keys;
            _modifyPlayerItem(_receiver, ITEM_KEY, int8(amount));
            _modifyPlayerItem(_actor, ITEM_KEY, -int8(amount));
            totalGifted += amount;
        }

        if (playerData[_actor].enchantedKeys > 0) {
            uint8 amount = playerData[_actor].enchantedKeys;
            _modifyPlayerItem(_receiver, ITEM_ENCHANTED_KEY, int8(amount));
            _modifyPlayerItem(_actor, ITEM_ENCHANTED_KEY, -int8(amount));
            totalGifted += amount;
        }

        if (playerData[_actor].staffs > 0) {
            uint8 amount = playerData[_actor].staffs;
            _modifyPlayerItem(_receiver, ITEM_STAFF, int8(amount));
            _modifyPlayerItem(_actor, ITEM_STAFF, -int8(amount));
            totalGifted += amount;
        }

        GameLibrary.resetAndUnion(dsuParent, dsuSetSize, _actor, _receiver);
        emit AllianceUpdated(_actor, _receiver, true);

        return totalGifted;
    }

    // --- Optimized Helper Functions ---
    function _modifyPlayerItem(
        address _player,
        uint8 _itemType,
        int8 _amount
    ) internal {
        if (_itemType == ITEM_KEY) {
            playerData[_player].keys = uint8(
                int8(playerData[_player].keys) + _amount
            );
            if (_amount != 0) emit ItemsChanged(_player, "Key", _amount);
        } else if (_itemType == ITEM_ENCHANTED_KEY) {
            playerData[_player].enchantedKeys = uint8(
                int8(playerData[_player].enchantedKeys) + _amount
            );
            if (_amount != 0)
                emit ItemsChanged(_player, "EnchantedKey", _amount);
        } else if (_itemType == ITEM_STAFF) {
            playerData[_player].staffs = uint8(
                int8(playerData[_player].staffs) + _amount
            );
            if (_amount != 0) emit ItemsChanged(_player, "Staff", _amount);
        }
    }

    function _consumeProtection(address _target) internal returns (bool) {
        if (playerData[_target].protections > 0) {
            playerData[_target].protections--;
            emit ProtectionStatusChanged(
                _target,
                playerData[_target].protections > 0,
                "ProtectionUsed"
            );
            return true;
        }
        return false;
    }

    function _checkOpenVictory(address _actor) internal {
        if (gameOver) return;
        GameLibrary.ChestState memory state = GameLibrary.ChestState({
            padlocks: padlocks,
            seals: seals
        });
        if (GameLibrary.checkOpenVictory(state)) {
            _distributePrizes(_actor);
        }
    }

    function _checkBlockVictory(address _actor) internal {
        if (gameOver) return;
        GameLibrary.ChestState memory state = GameLibrary.ChestState({
            padlocks: padlocks,
            seals: seals
        });
        if (GameLibrary.checkBlockVictory(state)) {
            _distributePrizes(_actor);
        }
    }
}
