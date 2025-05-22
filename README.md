# Archetypes: On-Chain Game Mechanics

Smart contracts powering **Archetypes of the Collective Unconscious** - a multiplayer strategy RPG on Mantle Network where players embody archetypes competing for crypto rewards.

## Overview

- **Game.sol**: Core contract managing 12 unique character archetypes, each with special abilities
- **Mechanics**: Padlocks, magical seals, keys, alliances, and 24 distinct moves
- **Economy**: Entry fee of 0.01 MNT with prize pool distribution to winners

## Character Types

| Openers  | Blockers   | Double Agents |
| -------- | ---------- | ------------- |
| Hero     | Ruler      | Wizard        |
| Explorer | Caregiver  | Outlaw        |
| Innocent | Common Man | Lover         |
| Artist   | Joker      | Sage          |

## Development

```shell
# Build
forge build

# Test
forge test

# Deploy
forge script script/Deploy.s.sol --rpc-url <rpc_url> --private-key <key>
```

## Frontend

Integrates with [Archetypes frontend](https://github.com/deca12x/Archetypes)
