// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

library GameLibrary {
    // Constants
    uint8 public constant NUM_PLAYERS = 12;

    // Structs for victory condition checking
    struct ChestState {
        uint8 padlocks;
        uint8 seals;
    }

    // Check if the game has met open victory condition (padlocks = 0 and seals = 0)
    function checkOpenVictory(ChestState memory state) internal pure returns (bool) {
        return state.padlocks == 0 && state.seals == 0;
    }

    // Check if the game has met block victory condition (padlocks >= 3 and seals >= 3)
    function checkBlockVictory(ChestState memory state) internal pure returns (bool) {
        return state.padlocks >= 3 && state.seals >= 3;
    }

    // Check if Plea of Peace is active
    function isPleaOfPeaceActive(uint256 pleaOfPeaceEndTime) internal view returns (bool) {
        return block.timestamp < pleaOfPeaceEndTime;
    }

    // DSU (Disjoint Set Union) operations for alliance management
    function findRoot(mapping(address => address) storage dsuParent, address player) internal view returns (address) {
        address root = player;
        while (root != dsuParent[root]) {
            root = dsuParent[root];
        }
        return root;
    }

    // Path compression version of find that updates storage
    function find(mapping(address => address) storage dsuParent, address player) internal returns (address) {
        if (dsuParent[player] == player) {
            return player;
        }
        // Path compression for efficiency
        dsuParent[player] = find(dsuParent, dsuParent[player]);
        return dsuParent[player];
    }

    // Union by size for alliance merging
    function union(
        mapping(address => address) storage dsuParent,
        mapping(address => uint8) storage dsuSetSize,
        address playerA,
        address playerB
    ) internal returns (bool) {
        address rootA = find(dsuParent, playerA);
        address rootB = find(dsuParent, playerB);

        if (rootA != rootB) {
            // Union by size
            if (dsuSetSize[rootA] < dsuSetSize[rootB]) {
                address temp = rootA;
                rootA = rootB;
                rootB = temp;
            }
            dsuParent[rootB] = rootA;
            dsuSetSize[rootA] += dsuSetSize[rootB];
            return true; // Alliance created
        }
        return false; // Already in the same alliance
    }

    // Reset a player's alliance and create a new one
    function resetAndUnion(
        mapping(address => address) storage dsuParent,
        mapping(address => uint8) storage dsuSetSize,
        address actor,
        address targetPlayer
    ) internal returns (bool) {
        address actorRoot = find(dsuParent, actor);
        address targetRoot = find(dsuParent, targetPlayer);

        if (actorRoot == targetRoot) {
            return false; // Already in the same alliance
        }

        // Update the old root's size by removing the actor
        if (actorRoot != actor) {
            dsuSetSize[actorRoot] -= 1;
        }

        // Reset actor's parent and size
        dsuParent[actor] = actor;
        dsuSetSize[actor] = 1;

        // Create new union
        return union(dsuParent, dsuSetSize, actor, targetPlayer);
    }
}
