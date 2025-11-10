# jlee-aimedic

Lightweight AI medic for QBCore servers — spawns an NPC medic to perform CPR and revive downed players on-demand.

### Features
- `/medic` command to spawn an AI medic NPC that performs CPR and revives.
- Server-side validation, cooldowns, global rate limits, and billing hooks.
- Robust animations with caching and fallbacks, AI pathing fallbacks, and cleanup on disconnect/resource stop.
- Handles resource stop gracefully (suppresses false "caller disconnected" notifications).
- Optional integration: `wasabi_ambulance:revivePlayer` hook to trigger the same safe revive flow.
- Debugging gated by `Config.Debug` and webhook/receipt hooks available.

### Installation
1. Place the `jlee-aimedic` resource folder in your server `resources` directory.
2. Add `ensure jlee-aimedic` to your `server.cfg` (or start manually).
3. Restart the server or start the resource.

### Requirements
- QBCore (exported as `qb-core`) — the script uses `exports['qb-core']:GetCoreObject()`.

### Configuration
Edit `config.lua` to tune behavior:
- `Config.Cost` — revive cost (number).
- `Config.Cooldown` — per-player cooldown in seconds.
- `Config.MaxActiveMedics` — global maximum concurrent AI medics.
- `Config.MedicModel`, `Config.AnimDict`, `Config.AnimName` — NPC model and animation keys.
- `Config.Debug` — enable debug logs (`true`/`false`).
- `Config.WebhookURL` — optional webhook for receipts/logs.

### Commands
- `/medic` (client) — request an AI medic when downed.

### Server Events (validated)
- `jlee-aimedic:requestMedic` — validated server-side; clients should not call directly without being a player request.
- `jlee-aimedic:reviveServer` — internal server revive flow; validates state and applies billing.
- `wasabi_ambulance:revivePlayer` — compatibility hook which triggers the same validated revive flow (accepts optional `targetSrc`).


### Troubleshooting
- If the NPC or animation stalls, set `Config.Debug = true` and watch server/client console for `[jlee-aimedic][DEBUG]` logs.
- Common fixes: ensure model names and anim dicts match your server, increase spawn radius or fallback models in `config.lua`.
- If billing fails, confirm QBCore is present and player objects are valid on the server when charging.


### Support

https://discord.gg/tEGXGzpVRv
---
