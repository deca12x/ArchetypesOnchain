// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./GameCore.sol";

contract GameMoves is GameCore {
    // --- Custom Errors (major size reduction) ---
    error InvalidTarget();
    error PeaceActive();
    error NoItems();
    error NoKey();
    error NoEKey();
    error NoStaff();
    error NoValidMove();
    error CannotUseMove();

    // --- Packed Constants ---
    uint8 constant ITEM_KEY = 0;
    uint8 constant ITEM_ENCHANTED_KEY = 1;
    uint8 constant ITEM_STAFF = 2;

    // Move categories packed into single uint256
    uint256 constant MOVE_CATEGORIES =
        (1 << 0) | // InspireAlliance - ALLIANCE
            (1 << 8) | // GuardianBond - ALLIANCE
            (1 << 16) | // SoulBond - ALLIANCE
            (2 << 24) | // CreateEnchantedKey - ITEM_CREATE
            (2 << 32) | // ConjureStaff - ITEM_CREATE
            (2 << 40) | // ForgeKey - ITEM_CREATE
            (2 << 48) | // CreateFakeKey - ITEM_CREATE
            (4 << 56) | // SecureChest - CHEST_LOCK
            (4 << 64) | // ArcaneSeal - CHEST_LOCK
            (8 << 72) | // Lockpick - CHEST_UNLOCK
            (8 << 80) | // Purify - CHEST_UNLOCK
            (8 << 88) | // UnlockChest - CHEST_UNLOCK
            (8 << 96) | // UnsealChest - CHEST_UNLOCK
            (16 << 104) | // Guard - PROTECTION
            (16 << 112) | // Evade - PROTECTION
            (32 << 120) | // RoyalDecree - GLOBAL
            (32 << 128); // PleaOfPeace - GLOBAL

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
        bool useEnchantedItem;
        uint8 additionalParam;
    }

    // --- Main Execute Function ---
    function executeMove(
        MoveParams calldata p
    ) external gameIsActive onlyGamePlayer(p.actor) {
        _validateAndPrepareActor(msg.sender, p.actor, p.moveType);
        if (!canUseMove(p.actor, p.moveType)) revert CannotUseMove();

        uint8 category = uint8(MOVE_CATEGORIES >> (uint256(p.moveType) * 8));
        uint8 result;

        if (category == 1) result = _execAlliance(p.actor, p.targetPlayer);
        else if (category == 2) result = _execItemCreate(p.actor, p.moveType);
        else if (category == 4) result = _execChestLock(p.actor, p.moveType);
        else if (category == 8)
            result = _execChestUnlock(p.actor, p.moveType, p.useEnchantedItem);
        else if (category == 16)
            result = _execProtection(p.actor, p.targetPlayer, p.moveType);
        else if (category == 32) result = _execGlobal(p.actor, p.moveType);
        else result = _execSpecial(p.actor, p.targetPlayer, p.moveType);

        if (p.moveType != MoveType.CopycatMove) lastMoveExecuted = p.moveType;

        emit GameAction(
            p.actor,
            p.targetPlayer,
            category,
            result,
            uint256(p.moveType)
        );
    }

    // --- Optimized Category Implementations ---
    function _execAlliance(
        address actor,
        address target
    ) internal returns (uint8) {
        if (target == actor || !playerData[target].hasJoined)
            revert InvalidTarget();

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

    function _execItemCreate(
        address actor,
        MoveType moveType
    ) internal returns (uint8) {
        // Optimized lookup arrays
        uint8[4] memory items = [ITEM_ENCHANTED_KEY, ITEM_STAFF, ITEM_KEY, 255];
        uint8[4] memory results = [1, 2, 3, 4];

        uint8 idx = uint8(moveType) - uint8(MoveType.CreateEnchantedKey);

        if (idx == 2 && GameLibrary.isPleaOfPeaceActive(pleaOfPeaceEndTime))
            return 0;

        if (idx < 3) {
            _modifyItem(actor, items[idx], 1);
            if (idx == 2) emit GameAction(actor, address(0), 99, 0, 0); // KeyForged marker
        } else {
            activeFakeKeysCount++;
            emit GameAction(actor, address(0), 98, activeFakeKeysCount, 0); // FakeKey marker
        }

        return results[idx];
    }

    function _execChestLock(
        address actor,
        MoveType moveType
    ) internal returns (uint8) {
        if (GameLibrary.isPleaOfPeaceActive(pleaOfPeaceEndTime))
            revert PeaceActive();

        assembly {
            let slot := add(padlocks.slot, mul(eq(moveType, 0x0A), 1)) // SecureChest = 0x0A
            let val := sload(slot)
            sstore(slot, add(val, 1))
        }

        emit GameAction(
            actor,
            address(0),
            4,
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

        // Fake key check (inlined)
        if (
            (moveType == MoveType.UnlockChest ||
                moveType == MoveType.UnsealChest) && activeFakeKeysCount > 0
        ) {
            activeFakeKeysCount--;
            emit GameAction(actor, address(0), 98, activeFakeKeysCount, 0);
            return 0;
        }

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
                if (padlocks > 0) padlocks--;
                if (seals > 0) seals--;
                changed = true;
            } else {
                bool isUnlock = moveType == MoveType.UnlockChest;
                if (isUnlock) {
                    if (playerData[actor].keys == 0) revert NoKey();
                    _modifyItem(actor, ITEM_KEY, -1);
                    if (padlocks > 0) padlocks--;
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
        address target,
        MoveType moveType
    ) internal returns (uint8) {
        address protectee = target == address(0) ? actor : target;
        if (target != address(0) && !playerData[target].hasJoined)
            revert InvalidTarget();

        playerData[protectee].protections++;
        emit GameAction(protectee, address(0), 16, 1, uint256(moveType));
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

        emit GameAction(actor, address(0), 32, 1, endTime);
        return 1;
    }

    function _execSpecial(
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

        if (moveType == MoveType.CopycatMove) {
            if (
                uint(lastMoveExecuted) == 0 ||
                lastMoveExecuted == MoveType.CopycatMove
            ) revert NoValidMove();
            return 1;
        }

        if (moveType == MoveType.EnergyFlow) return _execEnergyFlow(actor);
        if (moveType == MoveType.SeizeItem)
            return _execSeizeItem(actor, target);
        if (moveType == MoveType.Distract) return _execDistract(actor, target);
        if (moveType == MoveType.Gift) return _execGift(actor, target);

        return 0;
    }

    // --- Optimized Helper Functions ---
    function _modifyItem(address player, uint8 itemType, int8 amount) internal {
        assembly {
            let playerSlot := playerData.slot
            let key := player
            mstore(0x0, key)
            mstore(0x20, playerSlot)
            let baseSlot := keccak256(0x0, 0x40)

            // Calculate item offset (keys=0, enchantedKeys=1, staffs=2)
            let itemSlot := add(baseSlot, add(2, itemType)) // +2 for hasJoined(0) and protections(1)
            let currentVal := sload(itemSlot)
            let newVal := add(currentVal, amount)
            sstore(itemSlot, newVal)
        }

        if (amount != 0) {
            emit GameAction(
                player,
                address(0),
                97,
                uint8(itemType),
                uint256(uint8(amount))
            );
        }
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

        if (itemType != 255) {
            _modifyItem(target, itemType, -1);
            _modifyItem(actor, itemType, 1);
            return itemType + 1;
        }
        return 0;
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
        if (!gameOver && padlocks >= 10 && seals >= 10) {
            _distributePrizes(actor);
        }
    }
}
