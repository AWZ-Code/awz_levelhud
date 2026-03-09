# awz_levelhud — API Reference

> Developer reference for the **awz_levelhud** RedM resource.
>
> This document covers the public API exposed by the resource: **client exports**, **server exports**, **events**, **commands**, **data model**, and **integration examples**.

**Resource name must be:** `awz_levelhud`

---

## Overview

`awz_levelhud` is a VORP-compatible RedM level / XP system with:

- persistent XP and level storage by **`charid`**,
- automatic HUD synchronization to the client,
- level up / level down toast notifications,
- admin commands for XP and level management,
- exports and events for integration with other resources.

The system is built around **total XP**. Level, progress inside the current level, and XP-to-next-level are always derived from the stored total XP.

---

## Runtime architecture

### Client responsibilities
The client script:

- keeps a cached copy of the latest level state,
- shows the HUD only while the configured peek key is held,
- displays toast notifications for level changes,
- requests sync from the server when needed.

### Server responsibilities
The server script:

- loads and saves player progression from MySQL,
- identifies characters through VORP **`charIdentifier`**,
- computes level data from total XP,
- exposes events and exports to modify XP / level,
- syncs the computed state back to the player client.

---

## Data model

### Stored database fields
The database table stores:

- `charid` — VORP character identifier
- `identifier` — player identifier string from VORP
- `level` — cached level value
- `total_xp` — authoritative XP value used for all computations
- timestamps

### Runtime player state
When loaded on the server, each player is represented as:

```lua
{
  charid = number,
  identifier = string,
  level = number,
  totalXp = number,
  currentXp = number,
  nextXp = number,
  progress = number,
  isMax = boolean,
  dirty = boolean,
}
```

### Level data object
Several exports and callbacks return a level-data object with this shape:

```lua
{
  charid = number,
  identifier = string,
  level = number,
  totalXp = number,
  currentXp = number,
  nextXp = number,
  progress = number,
  isMax = boolean,
}
```

#### Field meanings
- `level`: current computed level
- `totalXp`: total stored XP
- `currentXp`: XP accumulated inside the current level
- `nextXp`: XP required to complete the current level step
- `progress`: percentage from `0` to `100`
- `isMax`: whether the character has reached the configured maximum level

---

## Client API

## Client exports

### `ShowLevelHud(level, progress, currentXp, nextXp)`
Forces the client-side HUD state to update and show **when the peek key is held**.

```lua
exports['awz_levelhud']:ShowLevelHud(level, progress, currentXp, nextXp)
```

#### Parameters
- `level` (`number`)
- `progress` (`number`) — percent between `0` and `100`
- `currentXp` (`number`)
- `nextXp` (`number`)

#### Notes
- This is a **client export**.
- It only updates the local cached HUD state.
- It does **not** persist anything to the server.

---

### `UpdateLevelHud(level, progress, currentXp, nextXp)`
Updates the cached client HUD state.

```lua
exports['awz_levelhud']:UpdateLevelHud(level, progress, currentXp, nextXp)
```

#### Parameters
Same as `ShowLevelHud`.

#### Notes
- Intended for local UI refresh behavior.
- Does not save or change server data.

---

### `HideLevelHud()`
Forces the local HUD to close.

```lua
exports['awz_levelhud']:HideLevelHud()
```

---

### `ShowLevelToast(kind, oldLevel, newLevel, duration)`
Shows a level-change toast on the client.

```lua
exports['awz_levelhud']:ShowLevelToast(kind, oldLevel, newLevel, duration)
```

#### Parameters
- `kind` (`string`) — usually `"up"` or `"down"`
- `oldLevel` (`number`)
- `newLevel` (`number`)
- `duration` (`number`) — milliseconds

#### Notes
This only affects the NUI. It does not change XP or level data.

---

### `RequestSync()`
Asks the server to resend the current level state for the local player.

```lua
exports['awz_levelhud']:RequestSync()
```

#### Notes
Use this when your client wants to force-refresh its HUD data from the authoritative server state.

---

### `GetCachedLevelData()`
Returns the client-side cached state.

```lua
local data = exports['awz_levelhud']:GetCachedLevelData()
```

#### Returns
```lua
{
  level = number,
  progress = number,
  currentXp = number,
  nextXp = number,
}
```

#### Notes
- This is only the client cache.
- It may be outdated if a sync has not happened yet.

---

### `IsPeekHeld()`
Returns whether the configured HUD peek key is currently held.

```lua
local isHeld = exports['awz_levelhud']:IsPeekHeld()
```

#### Returns
- `boolean`

---

## Client events

### `awz_levelhud:show`
```lua
TriggerEvent('awz_levelhud:show', level, progress, currentXp, nextXp)
```
Shows / updates the local HUD state.

---

### `awz_levelhud:update`
```lua
TriggerEvent('awz_levelhud:update', level, progress, currentXp, nextXp)
```
Updates the local HUD state.

---

### `awz_levelhud:hide`
```lua
TriggerEvent('awz_levelhud:hide')
```
Hides the local HUD.

---

### `awz_levelhud:toast`
```lua
TriggerEvent('awz_levelhud:toast', kind, oldLevel, newLevel, duration)
```
Shows a level-change toast.

---

### `awz_levelhud:forceSyncClient`
```lua
TriggerEvent('awz_levelhud:forceSyncClient')
```
Requests a fresh sync from the server.

This is primarily used internally after character selection.

---

## Client -> server network event

### `awz_levelhud:requestSync`
Sent by the client to request the current authoritative state.

```lua
TriggerServerEvent('awz_levelhud:requestSync')
```

#### Behavior
The server loads the player data if needed and responds by sending:

```lua
TriggerClientEvent('awz_levelhud:update', src, level, progress, currentXp, nextXp)
```

---

## Client debug commands

These commands exist in `client.lua` for testing the HUD and toasts.

### `/levelsync`
Requests a full sync from the server.

```text
/levelsync
```

### `/leveltest`
Injects a local test state into the HUD cache.

```text
/leveltest [level] [progress] [currentXp] [nextXp]
```

Example:
```text
/leveltest 12 67 670 1000
```

### `/levelupdate`
Updates the local cached HUD state.

```text
/levelupdate [level] [progress] [currentXp] [nextXp]
```

### `/levelhide`
Hides the HUD.

```text
/levelhide
```

### `/leveltoast`
Shows a local toast.

```text
/leveltoast [up|down] [oldLevel] [newLevel]
```

Example:
```text
/leveltoast up 4 5
```

---

## Server API

## Server exports

### `AddXP(src, amount, reason)`
Adds XP to a target player.

```lua
local ok, data = exports['awz_levelhud']:AddXP(src, amount, reason)
```

#### Parameters
- `src` (`number`) — player source
- `amount` (`number`) — XP amount to add
- `reason` (`string`, optional)

#### Returns
- `ok` (`boolean`)
- `data` (`table|string`)
  - on success: level data object
  - on failure: error string

#### Notes
- Negative values are converted to positive internally.
- This modifies **total XP**, recomputes level data, syncs the client, and may trigger a toast.

---

### `RemoveXP(src, amount, reason)`
Removes XP from a target player.

```lua
local ok, data = exports['awz_levelhud']:RemoveXP(src, amount, reason)
```

#### Notes
- The amount is internally treated as a positive number and then subtracted.
- If `Config.Leveling.AllowLevelDown = false`, XP removal cannot lower the player below the start of the current level.

---

### `SetLevel(src, level, reason)`
Sets the player to the exact beginning of a target level.

```lua
local ok, data = exports['awz_levelhud']:SetLevel(src, level, reason)
```

#### Behavior
The system converts the requested level to the corresponding total XP using:

```lua
totalXpToReachLevel(level)
```

This means the resulting state will be:
- target level reached,
- `currentXp = 0` for that level step,
- progress at the start of that level.

---

### `SetXP(src, totalXp, reason)`
Sets the exact total XP value.

```lua
local ok, data = exports['awz_levelhud']:SetXP(src, totalXp, reason)
```

---

### `GetLevel(src)`
Returns the current computed level.

```lua
local level = exports['awz_levelhud']:GetLevel(src)
```

#### Returns
- `number|nil`

---

### `GetXP(src)`
Returns the stored total XP.

```lua
local totalXp = exports['awz_levelhud']:GetXP(src)
```

#### Returns
- `number|nil`

---

### `GetLevelData(src)`
Returns the full computed level-data object.

```lua
local data = exports['awz_levelhud']:GetLevelData(src)
```

#### Returns
- `table|nil`

---

### `SyncPlayer(src)`
Forces a resync to the target client.

```lua
local ok = exports['awz_levelhud']:SyncPlayer(src)
```

#### Returns
- `boolean`

---

### `GetXPNeededForLevel(level)`
Returns the XP required to complete the specified level step.

```lua
local xpNeeded = exports['awz_levelhud']:GetXPNeededForLevel(level)
```

#### Returns
- `number`

#### Notes
This uses the configured formula from `Config.Leveling`.

---

### `GetXPToReachLevel(level)`
Returns the total cumulative XP needed to reach the specified level.

```lua
local totalRequired = exports['awz_levelhud']:GetXPToReachLevel(level)
```

#### Returns
- `number`

---

## Server-side events

These handlers are registered with `AddEventHandler`, so they are intended to be triggered **server-side** with `TriggerEvent(...)` from other server scripts.

### `awz_levelhud:addXP`
```lua
TriggerEvent('awz_levelhud:addXP', targetSrc, amount, reason)
```
Adds XP to a player.

---

### `awz_levelhud:removeXP`
```lua
TriggerEvent('awz_levelhud:removeXP', targetSrc, amount, reason)
```
Removes XP from a player.

---

### `awz_levelhud:setLevel`
```lua
TriggerEvent('awz_levelhud:setLevel', targetSrc, level, reason)
```
Sets a player level.

---

### `awz_levelhud:setXP`
```lua
TriggerEvent('awz_levelhud:setXP', targetSrc, xp, reason)
```
Sets total XP.

---

### `awz_levelhud:getLevel`
```lua
TriggerEvent('awz_levelhud:getLevel', targetSrc, function(level)
  print(level)
end)
```
Returns the level via callback.

---

### `awz_levelhud:getXP`
```lua
TriggerEvent('awz_levelhud:getXP', targetSrc, function(totalXp)
  print(totalXp)
end)
```
Returns total XP via callback.

---

### `awz_levelhud:getLevelData`
```lua
TriggerEvent('awz_levelhud:getLevelData', targetSrc, function(data)
  print(json.encode(data))
end)
```
Returns the full level-data object via callback.

---

## Server emitted event

### `awz_levelhud:levelChanged`
This event is triggered by the server whenever a player changes level.

```lua
AddEventHandler('awz_levelhud:levelChanged', function(src, oldLevel, newLevel, reason)
  -- your logic here
end)
```

#### Parameters
- `src` (`number`) — player source
- `oldLevel` (`number`)
- `newLevel` (`number`)
- `reason` (`string`)

#### Example
```lua
AddEventHandler('awz_levelhud:levelChanged', function(src, oldLevel, newLevel, reason)
  print(('[LEVEL] %s: %s -> %s (%s)'):format(src, oldLevel, newLevel, reason))
end)
```

---

## Level computation helpers

The resource exposes and internally uses two important concepts:

### XP needed for one level step
```lua
xpNeededForLevel(level)
```
This returns how much XP is required to go from `level` to `level + 1`.

### Total XP to reach a level
```lua
totalXpToReachLevel(level)
```
This returns the cumulative XP required to arrive at the requested level.

---

## Level formula

The configured formula is based on:

```lua
BaseXP
LinearGrowth
CurveGrowth
Exponent
```

The internal step formula is:

```lua
value = base + (idx * linear) + ((idx ^ exponent) * curve)
```

Where:
- `idx = level - 1`
- result is floored and clamped to a minimum of `1`

This means each next level generally requires more XP than the previous one.

---

## Sync lifecycle

A typical flow looks like this:

1. Resource starts on the client.
2. Client sends `level:init` to the NUI.
3. Client waits `SyncDelayMs`.
4. Client triggers `awz_levelhud:requestSync`.
5. Server loads or creates the character row using `charid`.
6. Server computes level data from `total_xp`.
7. Server sends `awz_levelhud:update` to the client.
8. Client stores the state and shows the HUD only while the peek key is pressed.

The same resync also happens:
- after `playerSpawned`,
- after `vorp:SelectedCharacter`.

---

## Character handling (VORP)

This resource is designed for VORP multicharacter usage.

### Character identity
The server identifies each record using:

```lua
character.charIdentifier
```

This is stored as:

```lua
charid
```

### Important behavior
- progression is saved **per character**, not per license,
- switching character causes the server cache for that source to be reloaded,
- a fresh sync is triggered after character selection.

---

## Admin commands

If `Config.Admin.Enabled = true`, the following commands are available.

Access is controlled through ACE permission:

```lua
awz.levelhud.admin
```

### `/addxp`
```text
/addxp [id] [xp] [optional reason]
```

Example:
```text
/addxp 12 250 quest_reward
```

---

### `/removexp`
```text
/removexp [id] [xp] [optional reason]
```

Example:
```text
/removexp 12 100 penalty
```

---

### `/setlevel`
```text
/setlevel [id] [level] [optional reason]
```

Example:
```text
/setlevel 12 20 admin_adjust
```

---

### `/setxp`
```text
/setxp [id] [total_xp] [optional reason]
```

Example:
```text
/setxp 12 15000 migration_fix
```

---

## Integration examples

## 1) Reward XP from another server resource

```lua
exports['awz_levelhud']:AddXP(source, 150, 'job_delivery')
```

---

## 2) Remove XP as a penalty

```lua
exports['awz_levelhud']:RemoveXP(source, 50, 'crime_penalty')
```

---

## 3) Read full level data before giving a reward

```lua
local data = exports['awz_levelhud']:GetLevelData(source)
if data then
  print(('Player level: %s, total XP: %s'):format(data.level, data.totalXp))
end
```

---

## 4) React to level changes

```lua
AddEventHandler('awz_levelhud:levelChanged', function(src, oldLevel, newLevel, reason)
  if newLevel > oldLevel then
    print(('Player %s leveled up from %s to %s (%s)'):format(src, oldLevel, newLevel, reason))
  end
end)
```

---

## 5) Force a player HUD resync

```lua
exports['awz_levelhud']:SyncPlayer(source)
```

---

## 6) Use server-side event style instead of exports

```lua
TriggerEvent('awz_levelhud:addXP', source, 75, 'crafting_bonus')
```

---

## 7) Read XP needed for a specific level

```lua
local xpNeeded = exports['awz_levelhud']:GetXPNeededForLevel(10)
print(('XP needed for level 10 step: %s'):format(xpNeeded))
```

---

## Return value patterns

Mutating server exports generally return:

```lua
local ok, data = exports['awz_levelhud']:AddXP(src, amount, reason)
```

### On success
```lua
ok == true
data == {
  charid = ...,
  identifier = ...,
  level = ...,
  totalXp = ...,
  currentXp = ...,
  nextXp = ...,
  progress = ...,
  isMax = ...,
}
```

### On failure
```lua
ok == false
data == 'error message'
```

Common failure reasons include:
- `invalid source`
- `player not loaded`

---

## Persistence behavior

The resource saves progression:

- when the player disconnects,
- when the resource stops,
- periodically using `Config.Database.SaveIntervalMs`,
- immediately when a loaded row needs correction after validation.

The `dirty` flag is used to avoid unnecessary database writes.

---

## Notes and best practices

### Prefer server exports for gameplay logic
For authoritative progression changes, use:

- `AddXP`
- `RemoveXP`
- `SetXP`
- `SetLevel`

Do **not** use client HUD exports to represent real progression changes.

### Use reasons consistently
Always pass a meaningful `reason` string when changing XP or level. This makes debugging much easier.

Example:

```lua
exports['awz_levelhud']:AddXP(source, 200, 'weekly_challenge')
```

### Sync after unusual flows
If your framework or custom login flow delays character readiness, call:

```lua
exports['awz_levelhud']:SyncPlayer(source)
```

or from the client:

```lua
exports['awz_levelhud']:RequestSync()
```

---

## Troubleshooting

### `GetLevel()` or `GetXP()` returns `nil`
Possible causes:
- invalid source id,
- character not fully selected yet,
- VORP character not available yet.

### HUD does not appear
Check:
- the resource name is exactly `awz_levelhud`,
- the NUI is loading correctly,
- the configured peek key is being pressed,
- the client has already received a sync from the server.

### XP changes but HUD does not refresh
Use:

```lua
exports['awz_levelhud']:SyncPlayer(source)
```

### Character data seems mixed between characters
Make sure the active VORP character exposes a valid:

```lua
character.charIdentifier
```

This resource is designed to store progression by `charid`.

---

## Minimal server integration snippet

```lua
local function rewardPlayer(src, amount)
  local ok, data = exports['awz_levelhud']:AddXP(src, amount, 'custom_reward')
  if not ok then
    print(('Failed to reward XP: %s'):format(data))
    return
  end

  print(('Rewarded %s XP -> level %s (%s total XP)'):format(amount, data.level, data.totalXp))
end
```

---

## Minimal client integration snippet

```lua
RegisterCommand('mylevel', function()
  local data = exports['awz_levelhud']:GetCachedLevelData()
  if data then
    print(('Level: %s | Progress: %s%% | %s/%s'):format(
      data.level,
      data.progress,
      data.currentXp,
      data.nextXp
    ))
  end
end, false)
```

---

## Compatibility summary

- **Framework:** VORP
- **Database:** MySQL / oxmysql-style async API
- **Character support:** per-character persistence using `charid`
- **HUD behavior:** client-side NUI, visible while peek key is held

---

## File naming recommendation

If you ship this documentation with the resource, use:

```text
awz_levelhud/
  README.md
  API.md
```

This file is intended to be the technical companion to the general README.
