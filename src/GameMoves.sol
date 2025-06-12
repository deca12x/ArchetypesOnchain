// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./GameCore.sol";
import "./PlayerLibrary.sol";

contract GameMoves is GameCore {
    // --- Packed Constants ---
    uint8 constant ITEM_KEY = 0;
    uint8 constant ITEM_ENCHANTED_KEY = 1;
    uint8 constant ITEM_STAFF = 2;

    // --- Move Categories ---
    enum MoveCategory {
        ALLIANCE, // 0
        ITEM_CREATE, // 1
        CHEST_LOCK, // 2
        CHEST_UNLOCK, // 3
        PROTECTION, // 4
        GLOBAL, // 5
        COPY, // 6
        COOLDOWN, // 7
        HARMFUL // 8
    }

    // Mapping of moves to their categories
    mapping(MoveType => MoveCategory) private moveToCategoryMap;

    MoveType public lastMoveExecuted;

    // Consolidated single event
    event GameAction(
        address indexed actor,
        address indexed target,
        uint8 indexed actionType,
        uint8 result,
        uint256 data
    );

    // --- Packed Move Parameters ---
    struct MoveParams {
        MoveType moveType;
        address actor;
        address targetPlayer;
        bool useItem;
        uint8 additionalParam;
    }

    // Initialize this in the constructor
    constructor() {
        // Alliance moves
        moveToCategoryMap[MoveType.InspireAlliance] = MoveCategory.ALLIANCE;
        moveToCategoryMap[MoveType.GuardianBond] = MoveCategory.ALLIANCE;
        moveToCategoryMap[MoveType.SoulBond] = MoveCategory.ALLIANCE;
        moveToCategoryMap[MoveType.Gift] = MoveCategory.ALLIANCE;

        // Item creation moves
        moveToCategoryMap[MoveType.CreateEnchantedKey] = MoveCategory
            .ITEM_CREATE;
        moveToCategoryMap[MoveType.ConjureStaff] = MoveCategory.ITEM_CREATE;
        moveToCategoryMap[MoveType.ForgeKey] = MoveCategory.ITEM_CREATE;
        moveToCategoryMap[MoveType.Discover] = MoveCategory.ITEM_CREATE;

        // Chest locking moves
        moveToCategoryMap[MoveType.SecureChest] = MoveCategory.CHEST_LOCK;
        moveToCategoryMap[MoveType.ArcaneSeal] = MoveCategory.CHEST_LOCK;

        // Chest unlocking moves
        moveToCategoryMap[MoveType.Lockpick] = MoveCategory.CHEST_UNLOCK;
        moveToCategoryMap[MoveType.Purify] = MoveCategory.CHEST_UNLOCK;
        moveToCategoryMap[MoveType.UnlockChest] = MoveCategory.CHEST_UNLOCK;
        moveToCategoryMap[MoveType.UnsealChest] = MoveCategory.CHEST_UNLOCK;

        // Protection moves
        moveToCategoryMap[MoveType.Guard] = MoveCategory.PROTECTION;
        moveToCategoryMap[MoveType.Evade] = MoveCategory.PROTECTION;

        // Global effect moves
        moveToCategoryMap[MoveType.RoyalDecree] = MoveCategory.GLOBAL;
        moveToCategoryMap[MoveType.PleaOfPeace] = MoveCategory.GLOBAL;

        // Copy moves
        moveToCategoryMap[MoveType.CopycatMove] = MoveCategory.COPY;

        // Cooldown moves
        moveToCategoryMap[MoveType.EnergyFlow] = MoveCategory.COOLDOWN;

        // Harmful moves
        moveToCategoryMap[MoveType.SeizeItem] = MoveCategory.HARMFUL;
        moveToCategoryMap[MoveType.Distract] = MoveCategory.HARMFUL;
        moveToCategoryMap[MoveType.CreateFakeKey] = MoveCategory.HARMFUL;
    }

    // --- Main Execute Function ---
    function executeMove(
        MoveParams calldata p
    ) external gameIsActive onlyGamePlayer(p.actor) {
        _validateAndPrepareActor(msg.sender, p.actor, p.moveType);

        MoveCategory category = moveToCategoryMap[p.moveType];
        uint8 result;

        if (category == MoveCategory.ALLIANCE) {
            result = _execAlliance(p.actor, p.moveType, p.targetPlayer);
        } else if (category == MoveCategory.ITEM_CREATE) {
            result = _execItemCreate(p.actor, p.moveType);
        } else if (category == MoveCategory.CHEST_LOCK) {
            result = _execChestLock(p.actor, p.moveType);
        } else if (category == MoveCategory.CHEST_UNLOCK) {
            result = _execChestUnlock(p.actor, p.moveType, p.useItem);
        } else if (category == MoveCategory.PROTECTION) {
            result = _execProtection(p.actor, p.moveType, p.targetPlayer);
        } else if (category == MoveCategory.GLOBAL) {
            result = _execGlobal(p.actor, p.moveType);
        } else if (category == MoveCategory.COPY) {
            result = _execCopy(p.actor, p.moveType);
        } else if (category == MoveCategory.COOLDOWN) {
            result = _execCooldown(p.actor, p.moveType);
        } else if (category == MoveCategory.HARMFUL) {
            result = _execHarmful(p.actor, p.moveType, p.targetPlayer);
        } else {
            revert InvalidMoveType();
        }

        if (p.moveType != MoveType.CopycatMove) {
            lastMoveExecuted = p.moveType;
        }

        emit GameAction(
            p.actor,
            p.targetPlayer,
            uint8(category),
            result,
            uint256(p.moveType)
        );
    }

    // --- Optimized Category Implementations ---
    function _execAlliance(
        address actor,
        MoveType moveType,
        address target
    ) internal returns (uint8) {
        if (target == actor || !playerData[target].hasJoined)
            revert InvalidTarget();
        if (moveType == MoveType.Gift) {
            if (
                playerData[actor].keys +
                    playerData[actor].enchantedKeys +
                    playerData[actor].staffs ==
                0
            ) revert NoItems();
            uint8 totalGifted;
            if (playerData[actor].keys > 0) {
                uint8 amount = playerData[actor].keys;
                _modifyItem(target, ITEM_KEY, int8(amount));
                _modifyItem(actor, ITEM_KEY, -int8(amount));
                totalGifted += amount;
            }
            if (playerData[actor].enchantedKeys > 0) {
                uint8 amount = playerData[actor].enchantedKeys;
                _modifyItem(target, ITEM_ENCHANTED_KEY, int8(amount));
                _modifyItem(actor, ITEM_ENCHANTED_KEY, -int8(amount));
                totalGifted += amount;
            }
            if (playerData[actor].staffs > 0) {
                uint8 amount = playerData[actor].staffs;
                _modifyItem(target, ITEM_STAFF, int8(amount));
                _modifyItem(actor, ITEM_STAFF, -int8(amount));
                totalGifted += amount;
            }

            GameLibrary.resetAndUnion(dsuParent, dsuSetSize, actor, target);
            emit AllianceUpdated(actor, target, true);
            return totalGifted;
        } else {
            bool success = GameLibrary.resetAndUnion(
                dsuParent,
                dsuSetSize,
                actor,
                target
            );
            if (success) {
                emit AllianceUpdated(actor, target, true);
                return 1;
            }
            return 0;
        }
    }

    function _execItemCreate(
        address actor,
        MoveType moveType
    ) internal returns (uint8) {
        uint8 itemType;
        uint8 result;
        bool isFakeKey = false;

        if (moveType == MoveType.CreateEnchantedKey) {
            itemType = ITEM_ENCHANTED_KEY;
            result = 1;
        } else if (moveType == MoveType.ConjureStaff) {
            itemType = ITEM_STAFF;
            result = 2;
        } else if (moveType == MoveType.ForgeKey) {
            if (GameLibrary.isPleaOfPeaceActive(pleaOfPeaceEndTime)) {
                emit GameAction(actor, address(0), 8, 0, uint256(moveType));
                return 0;
            }
            itemType = ITEM_KEY;
            result = 1;
        } else {
            // Must be CreateFakeKey due to validation above
            isFakeKey = true;
            result = 1;
        }

        if (isFakeKey) {
            activeFakeKeysCount++;
            emit GameAction(actor, address(0), 98, activeFakeKeysCount, 0);
        } else {
            _modifyItem(actor, itemType, 1);
        }

        return result;
    }

    function _execChestLock(
        address actor,
        MoveType moveType
    ) internal returns (uint8) {
        if (GameLibrary.isPleaOfPeaceActive(pleaOfPeaceEndTime)) {
            revert PeaceActive();
        }

        if (moveType == MoveType.SecureChest) {
            padlocks++;
        } else {
            seals++;
        }

        emit GameAction(
            actor,
            address(0),
            uint8(MoveCategory.CHEST_LOCK),
            1,
            (uint256(padlocks) << 8) | seals
        );

        _checkBlockVictory(actor);
        return 1;
    }

    function _execChestUnlock(
        address actor,
        MoveType moveType,
        bool useEnchanted
    ) internal returns (uint8) {
        if (GameLibrary.isPleaOfPeaceActive(pleaOfPeaceEndTime))
            revert PeaceActive();

        bool changed;

        if (moveType == MoveType.Lockpick && padlocks > 0) {
            padlocks--;
            changed = true;
        } else if (moveType == MoveType.Purify && seals > 0) {
            seals--;
            changed = true;
        } else if (
            moveType == MoveType.UnlockChest || moveType == MoveType.UnsealChest
        ) {
            if (useEnchanted) {
                if (playerData[actor].enchantedKeys == 0) revert NoEKey();
                _modifyItem(actor, ITEM_ENCHANTED_KEY, -1);
                if (activeFakeKeysCount > 0) {
                    activeFakeKeysCount--;
                } else {
                    if (padlocks > 0) padlocks--;
                    if (seals > 0) seals--;
                    changed = true;
                }
            } else {
                bool isUnlock = moveType == MoveType.UnlockChest;
                if (isUnlock) {
                    if (playerData[actor].keys == 0) revert NoKey();
                    _modifyItem(actor, ITEM_KEY, -1);
                    if (activeFakeKeysCount > 0) {
                        activeFakeKeysCount--;
                    } else {
                        if (padlocks > 0) padlocks--;
                    }
                } else {
                    if (playerData[actor].staffs == 0) revert NoStaff();
                    _modifyItem(actor, ITEM_STAFF, -1);
                    if (seals > 0) seals--;
                }
                changed = true;
            }
        }

        if (changed) {
            emit GameAction(
                actor,
                address(0),
                8,
                1,
                (uint256(padlocks) << 8) | seals
            );
            _checkOpenVictory(actor);
            return 1;
        }
        return 0;
    }

    function _execProtection(
        address actor,
        MoveType moveType,
        address target
    ) internal returns (uint8) {
        if (target != address(0) && !playerData[target].hasJoined)
            revert TargetNotPlayer();
        playerData[target].protections++;
        emit GameAction(target, address(0), 16, 1, uint256(moveType));
        return 1;
    }

    function _execGlobal(
        address actor,
        MoveType moveType
    ) internal returns (uint8) {
        uint256 endTime = block.timestamp +
            (moveType == MoveType.RoyalDecree ? 60 : 120);

        if (moveType == MoveType.RoyalDecree) {
            royalDecreeEndTime = endTime;
        } else {
            pleaOfPeaceEndTime = endTime;
        }

        emit GameAction(
            actor,
            address(0),
            uint8(MoveCategory.GLOBAL),
            1,
            endTime
        );
        return 1;
    }

    function _execCopy(
        address actor,
        address target,
        MoveType moveType
    ) internal returns (uint8) {
        if (moveType == MoveType.Discover) {
            uint8 itemType = uint8(
                uint256(
                    keccak256(
                        abi.encodePacked(block.timestamp, msg.sender, actor)
                    )
                ) % 3
            );
            _modifyItem(actor, itemType, 1);
            return itemType + 1;
        }

        if (moveType == MoveType.CopycatMove) return _execCopycatMove(actor);
        if (moveType == MoveType.EnergyFlow) return _execEnergyFlow(actor);
        if (moveType == MoveType.SeizeItem)
            return _execSeizeItem(actor, target);
        if (moveType == MoveType.Distract) return _execDistract(actor, target);
        if (moveType == MoveType.Gift) return _execGift(actor, target);

        return 0;
    }

    function _execCooldown(
        address actor,
        MoveType moveType
    ) internal returns (uint8) {
        // TODO: Implement cooldown logic
    }

    function _execHarmful(
        address actor,
        MoveType moveType,
        address target
    ) internal returns (uint8) {
        // TODO: Implement harmful logic
    }

    // --- Optimized Helper Functions ---
    function _modifyItem(address player, uint8 itemType, int8 amount) internal {
        if (amount == 0) return;

        Player storage playerData_ = playerData[player];

        if (amount > 0) {
            if (itemType == ITEM_KEY) {
                playerData_.keys += uint8(amount);
            } else if (itemType == ITEM_ENCHANTED_KEY) {
                playerData_.enchantedKeys += uint8(amount);
            } else if (itemType == ITEM_STAFF) {
                playerData_.staffs += uint8(amount);
            } else {
                revert InvalidMoveType();
            }
        } else {
            uint8 absAmount = uint8(-amount);
            if (itemType == ITEM_KEY) {
                if (playerData_.keys < absAmount) revert InsufficientKeys();
                playerData_.keys -= absAmount;
            } else if (itemType == ITEM_ENCHANTED_KEY) {
                if (playerData_.enchantedKeys < absAmount)
                    revert InsufficientEnchantedKeys();
                playerData_.enchantedKeys -= absAmount;
            } else if (itemType == ITEM_STAFF) {
                if (playerData_.staffs < absAmount) revert InsufficientStaffs();
                playerData_.staffs -= absAmount;
            } else {
                revert InvalidMoveType();
            }
        }

        emit GameAction(
            player,
            address(0),
            97, // Action type for item modification
            itemType,
            uint256(uint8(amount))
        );
    }

    function _consumeProtection(address target) internal returns (bool) {
        if (playerData[target].protections > 0) {
            playerData[target].protections--;
            emit GameAction(
                target,
                address(0),
                96,
                playerData[target].protections > 0 ? 1 : 0,
                0
            );
            return true;
        }
        return false;
    }

    // --- Inlined Special Functions ---
    function _execEnergyFlow(address actor) internal returns (uint8) {
        address actorRoot = GameLibrary.find(dsuParent, actor);
        uint moveTypeCount = uint(MoveType.Gift) + 1;

        for (uint8 i = 0; i < NUM_PLAYERS; i++) {
            address ally = gamePlayerAddresses[i];
            if (
                ally != actor && GameLibrary.find(dsuParent, ally) == actorRoot
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
        address actor,
        address target
    ) internal returns (uint8) {
        if (!playerData[target].hasJoined || target == actor)
            revert InvalidTarget();
        if (GameLibrary.isPleaOfPeaceActive(pleaOfPeaceEndTime))
            revert PeaceActive();
        if (_consumeProtection(target)) return 0;

        // Priority: EnchantedKey > Key > Staff
        uint8 itemType = playerData[target].enchantedKeys > 0
            ? ITEM_ENCHANTED_KEY
            : playerData[target].keys > 0
            ? ITEM_KEY
            : playerData[target].staffs > 0
            ? ITEM_STAFF
            : 255;

        if (itemType == 255) revert NoItems();

        _modifyItem(target, itemType, -1);
        _modifyItem(actor, itemType, 1);
        return itemType + 1;
    }

    function _execDistract(
        address actor,
        address target
    ) internal returns (uint8) {
        if (!playerData[target].hasJoined || target == actor)
            revert InvalidTarget();
        if (GameLibrary.isPleaOfPeaceActive(pleaOfPeaceEndTime))
            revert PeaceActive();
        return _consumeProtection(target) ? 0 : 1;
    }

    function _execGift(
        address actor,
        address receiver
    ) internal returns (uint8) {
        if (
            playerData[actor].keys +
                playerData[actor].enchantedKeys +
                playerData[actor].staffs ==
            0
        ) revert NoItems();
        if (receiver == actor || !playerData[receiver].hasJoined)
            revert InvalidTarget();

        uint8 totalGifted;

        // Transfer all items at once
        if (playerData[actor].keys > 0) {
            uint8 amount = playerData[actor].keys;
            _modifyItem(receiver, ITEM_KEY, int8(amount));
            _modifyItem(actor, ITEM_KEY, -int8(amount));
            totalGifted += amount;
        }

        if (playerData[actor].enchantedKeys > 0) {
            uint8 amount = playerData[actor].enchantedKeys;
            _modifyItem(receiver, ITEM_ENCHANTED_KEY, int8(amount));
            _modifyItem(actor, ITEM_ENCHANTED_KEY, -int8(amount));
            totalGifted += amount;
        }

        if (playerData[actor].staffs > 0) {
            uint8 amount = playerData[actor].staffs;
            _modifyItem(receiver, ITEM_STAFF, int8(amount));
            _modifyItem(actor, ITEM_STAFF, -int8(amount));
            totalGifted += amount;
        }

        GameLibrary.resetAndUnion(dsuParent, dsuSetSize, actor, receiver);
        emit AllianceUpdated(actor, receiver, true);
        return totalGifted;
    }

    // --- Victory Checks (inlined) ---
    function _checkOpenVictory(address actor) internal {
        if (!gameOver && padlocks == 0 && seals == 0) {
            _distributePrizes(actor);
        }
    }

    function _checkBlockVictory(address actor) internal {
        if (!gameOver && padlocks >= 3 && seals >= 3) {
            _distributePrizes(actor);
        }
    }

    function _execCopycatMove(
        address /* actor */ // Parameter commented out but kept for consistency in function signature
    ) internal view returns (uint8) {
        if (
            uint(lastMoveExecuted) == 0 ||
            lastMoveExecuted == MoveType.CopycatMove
        ) {
            revert NoValidMove();
        }

        // Return 1 to indicate success
        // The actual copied move's effect will be handled by the next move
        return 1;
    }

    function getPlayerKeys(address player) public view returns (uint8) {
        // Logic to return the number of keys a player has
        return playerData[player].keys;
    }
}
