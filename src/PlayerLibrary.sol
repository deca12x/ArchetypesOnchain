// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

library PlayerLibrary {
    // Structs
    struct PlayerItems {
        uint8 keys;
        uint8 enchantedKeys;
        uint8 staffs;
        uint8 protections;
    }

    // Validate move cooldown and prepare actor for move
    function validateCooldown(
        uint256 lastMoveTimestamp,
        uint256 cooldownDuration
    ) internal view returns (bool) {
        if (cooldownDuration == 0) return true; // No cooldown

        return block.timestamp >= lastMoveTimestamp + cooldownDuration;
    }

    // Check if a player is inactive for too long
    function isPlayerInactive(
        uint256 inactivityTimestamp,
        uint256 idlePlayerLimit
    ) internal view returns (bool) {
        return block.timestamp >= inactivityTimestamp + idlePlayerLimit;
    }

    // Add an item to player inventory
    function addItem(PlayerItems storage items, uint8 itemType) internal {
        if (itemType == 0) {
            // Key
            items.keys++;
        } else if (itemType == 1) {
            // Enchanted Key
            items.enchantedKeys++;
        } else if (itemType == 2) {
            // Staff
            items.staffs++;
        }
    }

    // Remove an item from player inventory if available
    function removeItem(
        PlayerItems storage items,
        uint8 itemType
    ) internal returns (bool) {
        if (itemType == 0 && items.keys > 0) {
            // Key
            items.keys--;
            return true;
        } else if (itemType == 1 && items.enchantedKeys > 0) {
            // Enchanted Key
            items.enchantedKeys--;
            return true;
        } else if (itemType == 2 && items.staffs > 0) {
            // Staff
            items.staffs--;
            return true;
        }
        return false;
    }

    // Add protection to a player
    function addProtection(PlayerItems storage items) internal {
        items.protections++;
    }

    // Try to consume a protection, returns true if protection was available
    function useProtection(PlayerItems storage items) internal returns (bool) {
        if (items.protections > 0) {
            items.protections--;
            return true;
        }
        return false;
    }
}
