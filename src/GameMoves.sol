// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./GameCore.sol";

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

    // Add this state variable at the top of the contract with other state variables
    bool private copyOngoing;

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
    function executeMove(MoveParams calldata p) external gameIsActive {
        // If copyOngoing is true, allow any player to call the move
        if (!copyOngoing) {
            onlyGamePlayer(p.actor);
        }

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
            result = _execCopy(p.actor, p.moveType, p.targetPlayer, p.useItem);
        } else if (category == MoveCategory.COOLDOWN) {
            result = _execCooldown(p.actor, p.moveType);
        } else if (category == MoveCategory.HARMFUL) {
            result = _execHarmful(p.actor, p.moveType, p.targetPlayer);
        } else {
            revert InvalidMoveType();
        }

        // Update lastMoveExecuted for all moves except CopycatMove
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

            // Create array of available items
            uint8[] memory availableItems = new uint8[](3);
            uint8 itemCount = 0;

            if (playerData[actor].keys > 0) {
                availableItems[itemCount++] = ITEM_KEY;
            }
            if (playerData[actor].enchantedKeys > 0) {
                availableItems[itemCount++] = ITEM_ENCHANTED_KEY;
            }
            if (playerData[actor].staffs > 0) {
                availableItems[itemCount++] = ITEM_STAFF;
            }

            // Select one random item to gift
            uint8 selectedItem = _selectRandomItem(availableItems);

            // Transfer the selected item
            _modifyItem(actor, selectedItem, -1);
            _modifyItem(target, selectedItem, 1);

            GameLibrary.resetAndUnion(dsuParent, dsuSetSize, actor, target);
            return selectedItem + 1;
        } else if (moveType == MoveType.InspireAlliance) {
            // Bind actor and target
            GameLibrary.resetAndUnion(dsuParent, dsuSetSize, actor, target);
            return 1;
        } else if (moveType == MoveType.GuardianBond) {
            // Bind actor and target
            GameLibrary.resetAndUnion(dsuParent, dsuSetSize, actor, target);

            // Get a random item from the target
            uint8[] memory availableItems = new uint8[](3);
            uint8 itemCount = 0;

            if (playerData[target].keys > 0) {
                availableItems[itemCount++] = ITEM_KEY;
            }
            if (playerData[target].enchantedKeys > 0) {
                availableItems[itemCount++] = ITEM_ENCHANTED_KEY;
            }
            if (playerData[target].staffs > 0) {
                availableItems[itemCount++] = ITEM_STAFF;
            }

            if (itemCount == 0) revert NoItems();

            uint8 selectedItem = _selectRandomItem(availableItems);

            // Transfer the selected item to the actor
            _modifyItem(target, selectedItem, -1);
            _modifyItem(actor, selectedItem, 1);

            return selectedItem + 1;
        } else if (moveType == MoveType.SoulBond) {
            // Bind actor and target
            GameLibrary.resetAndUnion(dsuParent, dsuSetSize, actor, target);

            // Give a random item to the target
            uint8[] memory availableItems = new uint8[](3);
            uint8 itemCount = 0;

            if (playerData[actor].keys > 0) {
                availableItems[itemCount++] = ITEM_KEY;
            }
            if (playerData[actor].enchantedKeys > 0) {
                availableItems[itemCount++] = ITEM_ENCHANTED_KEY;
            }
            if (playerData[actor].staffs > 0) {
                availableItems[itemCount++] = ITEM_STAFF;
            }

            if (itemCount == 0) revert NoItems();

            uint8 selectedItem = _selectRandomItem(availableItems);

            // Transfer the selected item to the target
            _modifyItem(actor, selectedItem, -1);
            _modifyItem(target, selectedItem, 1);

            return selectedItem + 1;
        } else {
            // Default binding logic
            bool success = GameLibrary.resetAndUnion(
                dsuParent,
                dsuSetSize,
                actor,
                target
            );
            return success ? 1 : 0;
        }
    }

    function _execItemCreate(
        address actor,
        MoveType moveType
    ) internal returns (uint8) {
        uint8 itemType;
        uint8 result;

        if (moveType == MoveType.CreateEnchantedKey) {
            itemType = ITEM_ENCHANTED_KEY;
            result = 1;
        } else if (moveType == MoveType.ConjureStaff) {
            itemType = ITEM_STAFF;
            result = 2;
        } else if (moveType == MoveType.ForgeKey) {
            if (GameLibrary.isPleaOfPeaceActive(pleaOfPeaceEndTime)) {
                return 0;
            }
            itemType = ITEM_KEY;
            result = 1;
        } else if (moveType == MoveType.Discover) {
            // For Discover, randomly select one of the three items
            uint8[] memory items = new uint8[](3);
            items[0] = ITEM_KEY;
            items[1] = ITEM_ENCHANTED_KEY;
            items[2] = ITEM_STAFF;
            itemType = _selectRandomItem(items);
            result = itemType + 1;
        }

        _modifyItem(actor, itemType, 1);
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
        return 1;
    }

    function _execGlobal(
        address actor,
        MoveType moveType
    ) internal returns (uint8) {
        if (moveType == MoveType.RoyalDecree) {
            royalDecreeEndTime = block.timestamp + 60;
        } else {
            pleaOfPeaceEndTime = block.timestamp + 120;
        }

        return 1;
    }

    function _execCopy(
        address actor,
        address target,
        MoveType moveType,
        bool useItem
    ) internal returns (uint8) {
        if (
            uint(lastMoveExecuted) == 0 ||
            lastMoveExecuted == MoveType.CopycatMove
        ) {
            revert NoValidMove();
        }

        // Set copyOngoing to true
        copyOngoing = true;

        // Get the category of the move to copy
        MoveCategory category = moveToCategoryMap[lastMoveExecuted];
        uint8 result;

        // Execute the copied move
        if (category == MoveCategory.ALLIANCE) {
            result = _execAlliance(actor, lastMoveExecuted, target);
        } else if (category == MoveCategory.ITEM_CREATE) {
            result = _execItemCreate(actor, lastMoveExecuted);
        } else if (category == MoveCategory.CHEST_LOCK) {
            result = _execChestLock(actor, lastMoveExecuted);
        } else if (category == MoveCategory.CHEST_UNLOCK) {
            result = _execChestUnlock(actor, lastMoveExecuted, useItem);
        } else if (category == MoveCategory.PROTECTION) {
            result = _execProtection(actor, lastMoveExecuted, target);
        } else if (category == MoveCategory.GLOBAL) {
            result = _execGlobal(actor, lastMoveExecuted);
        } else if (category == MoveCategory.COOLDOWN) {
            result = _execCooldown(actor, lastMoveExecuted);
        } else if (category == MoveCategory.HARMFUL) {
            result = _execHarmful(actor, lastMoveExecuted, target);
        } else {
            revert InvalidMoveType();
        }

        // Set copyOngoing back to false
        copyOngoing = false;

        return result;
    }

    function _execCooldown(
        address actor,
        MoveType moveType
    ) internal returns (uint8) {
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

    function _execHarmful(
        address actor,
        MoveType moveType,
        address target
    ) internal returns (uint8) {
        if (!playerData[target].hasJoined || target == actor)
            revert InvalidTarget();
        if (GameLibrary.isPleaOfPeaceActive(pleaOfPeaceEndTime))
            revert PeaceActive();
        if (_consumeProtection(target)) return 0;

        if (moveType == MoveType.SeizeItem) {
            // Create array of available items
            uint8[] memory availableItems = new uint8[](3);
            uint8 itemCount = 0;

            if (playerData[target].enchantedKeys > 0) {
                availableItems[itemCount++] = ITEM_ENCHANTED_KEY;
            }
            if (playerData[target].keys > 0) {
                availableItems[itemCount++] = ITEM_KEY;
            }
            if (playerData[target].staffs > 0) {
                availableItems[itemCount++] = ITEM_STAFF;
            }

            if (itemCount == 0) revert NoItems();

            // Select one random item to seize
            uint8 selectedItem = _selectRandomItem(availableItems);

            // Transfer the selected item
            _modifyItem(target, selectedItem, -1);
            _modifyItem(actor, selectedItem, 1);

            return selectedItem + 1;
        } else if (moveType == MoveType.Distract) {
            // Set distracted state for target
            playerData[target].distracted = true;
            // Set cooldown for the actor (caller) of Distract
            playerData[actor].lastMoveTimestamp[
                uint256(MoveType.Distract)
            ] = block.timestamp;
            return 1;
        } else if (moveType == MoveType.CreateFakeKey) {
            // Increment the global fake keys counter
            activeFakeKeysCount++;
            // Set cooldown for the actor (caller) of CreateFakeKey
            playerData[actor].lastMoveTimestamp[
                uint256(MoveType.CreateFakeKey)
            ] = block.timestamp;
            return 1;
        }

        revert InvalidMoveType();
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
    }

    function _consumeProtection(address target) internal returns (bool) {
        if (playerData[target].protections > 0) {
            playerData[target].protections--;
            return true;
        }
        return false;
    }

    // --- Inlined Special Functions ---
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

    function getPlayerKeys(address player) public view returns (uint8) {
        // Logic to return the number of keys a player has
        return playerData[player].keys;
    }

    function _selectRandomItem(
        uint8[] memory availableItems
    ) internal view returns (uint8) {
        require(availableItems.length > 0, "No items available");
        uint256 randomIndex = uint256(
            keccak256(
                abi.encodePacked(blockhash(block.number - 1), block.timestamp)
            )
        ) % availableItems.length;
        return availableItems[randomIndex];
    }
}
