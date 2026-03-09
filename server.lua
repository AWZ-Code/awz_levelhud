local RESOURCE = GetCurrentResourceName()
local TABLE = Config.Database.TableName

local VorpCore = exports.vorp_core:GetCore()

local Players = {}
local DBReady = false

local function dbg(...)
  if not (Config and Config.Debug) then return end
  local parts = { ('^2[%s]^7'):format(RESOURCE) }
  for i = 1, select('#', ...) do
    parts[#parts + 1] = tostring(select(i, ...))
  end
  print(table.concat(parts, ' '))
end

local function floor(n)
  return math.floor(tonumber(n) or 0)
end

local function clamp(n, min, max)
  n = tonumber(n) or min
  if n < min then return min end
  if n > max then return max end
  return n
end

local function shallowCopyLevelData(p)
  if not p then return nil end
  return {
    charid = p.charid,
    identifier = p.identifier,
    level = p.level,
    totalXp = p.totalXp,
    currentXp = p.currentXp,
    nextXp = p.nextXp,
    progress = p.progress,
    isMax = p.isMax,
  }
end

local function reply(src, msg)
  msg = tostring(msg or '')
  if src == 0 then
    print(('[%s] %s'):format(RESOURCE, msg))
    return
  end

  TriggerClientEvent('chat:addMessage', src, {
    args = { RESOURCE, msg }
  })
end

local function hasAdminAccess(src)
  if src == 0 then return true end
  if not Config.Admin.Enabled then return false end
  return IsPlayerAceAllowed(src, Config.Admin.AcePermission or 'awz.levelhud.admin')
end

local function getVorpCharacter(src)
  local user = VorpCore.getUser(src)
  if not user then return nil end

  local character = user.getUsedCharacter
  if not character then return nil end

  return character
end

local function getCharacterKey(src)
  local character = getVorpCharacter(src)
  if not character then
    return nil
  end

  local charid = tonumber(character.charIdentifier)
  if not charid or charid <= 0 then
    return nil
  end

  return {
    charid = charid,
    identifier = character.identifier
  }
end

local function xpNeededForLevel(level)
  level = math.max(1, floor(level))
  local idx = level - 1

  local base = Config.Leveling.BaseXP or 100
  local linear = Config.Leveling.LinearGrowth or 25
  local curve = Config.Leveling.CurveGrowth or 10
  local exponent = Config.Leveling.Exponent or 1.20

  local value = base + (idx * linear) + ((idx ^ exponent) * curve)
  return math.max(1, floor(value))
end

local function totalXpToReachLevel(targetLevel)
  targetLevel = math.max(1, floor(targetLevel))
  local total = 0

  for lvl = 1, targetLevel - 1 do
    total = total + xpNeededForLevel(lvl)
  end

  return total
end

local function maxTotalXp()
  return totalXpToReachLevel(Config.Leveling.MaxLevel or 100)
end

local function computeFromTotalXp(totalXp)
  totalXp = math.max(0, floor(totalXp))
  local maxLevel = Config.Leveling.MaxLevel or 100

  if Config.Leveling.ClampAtMax then
    local maxXp = maxTotalXp()
    if totalXp > maxXp then
      totalXp = maxXp
    end
  end

  local level = 1
  local remaining = totalXp

  while level < maxLevel do
    local need = xpNeededForLevel(level)
    if remaining < need then
      local progress = 0
      if need > 0 then
        progress = (remaining / need) * 100.0
      end

      return {
        totalXp = totalXp,
        level = level,
        currentXp = remaining,
        nextXp = need,
        progress = clamp(progress, 0, 100),
        isMax = false,
      }
    end

    remaining = remaining - need
    level = level + 1
  end

  local displayNeed = xpNeededForLevel(math.max(1, maxLevel - 1))
  if maxLevel <= 1 then
    displayNeed = 1
  end

  return {
    totalXp = totalXp,
    level = maxLevel,
    currentXp = displayNeed,
    nextXp = displayNeed,
    progress = 100,
    isMax = true,
  }
end

local function applyComputedData(player, computed)
  player.totalXp = computed.totalXp
  player.level = computed.level
  player.currentXp = computed.currentXp
  player.nextXp = computed.nextXp
  player.progress = computed.progress
  player.isMax = computed.isMax
end

local function syncPlayer(src)
  local p = Players[src]
  if not p then return end
  TriggerClientEvent('awz_levelhud:update', src, p.level, p.progress, p.currentXp, p.nextXp)
end

local function savePlayer(src, force)
  local p = Players[src]
  if not p then return false end
  if not force and not p.dirty then return true end

  MySQL.update.await(([[ 
    INSERT INTO `%s` (`charid`, `identifier`, `level`, `total_xp`)
    VALUES (?, ?, ?, ?)
    ON DUPLICATE KEY UPDATE
      `identifier` = VALUES(`identifier`),
      `level` = VALUES(`level`),
      `total_xp` = VALUES(`total_xp`),
      `updated_at` = CURRENT_TIMESTAMP
  ]]):format(TABLE), {
    p.charid,
    p.identifier,
    p.level,
    p.totalXp,
  })

  p.dirty = false
  dbg('Saved', src, ('charid=%s'):format(p.charid), ('L%s XP%s'):format(p.level, p.totalXp))
  return true
end

local function loadPlayer(src)
  if not DBReady then
    dbg('DB not ready yet for source', src)
    return nil
  end

  if Players[src] then
    local currentKey = getCharacterKey(src)
    if currentKey and Players[src].charid == currentKey.charid then
      return Players[src]
    end

    savePlayer(src, true)
    Players[src] = nil
  end

  local key = getCharacterKey(src)
  if not key then
    dbg('No VORP char selected yet for source', src)
    return nil
  end

  local row = MySQL.single.await(('SELECT `identifier`, `level`, `total_xp` FROM `%s` WHERE `charid` = ? LIMIT 1'):format(TABLE), {
    key.charid
  })

  if not row then
    local startXp = math.max(0, floor(Config.Leveling.StartTotalXP or 0))
    local computed = computeFromTotalXp(startXp)

    MySQL.insert.await(('INSERT INTO `%s` (`charid`, `identifier`, `level`, `total_xp`) VALUES (?, ?, ?, ?)'):format(TABLE), {
      key.charid,
      key.identifier,
      computed.level,
      computed.totalXp
    })

    row = {
      identifier = key.identifier,
      level = computed.level,
      total_xp = computed.totalXp
    }
  end

  local computed = computeFromTotalXp(row.total_xp or 0)

  local player = {
    charid = key.charid,
    identifier = key.identifier,
    dirty = false,
  }

  applyComputedData(player, computed)
  Players[src] = player

  local dbLevel = floor(row.level or 1)
  if dbLevel ~= player.level
    or floor(row.total_xp or 0) ~= player.totalXp
    or tostring(row.identifier or '') ~= tostring(key.identifier or '')
  then
    player.dirty = true
    savePlayer(src, true)
  end

  dbg('Loaded', src, ('charid=%s'):format(player.charid), ('L%s XP%s'):format(player.level, player.totalXp))
  return player
end

local function applyTotalXp(src, totalXp, reason, force)
  src = tonumber(src)
  if not src or src <= 0 then
    return false, 'invalid source'
  end

  local player = loadPlayer(src)
  if not player then
    return false, 'player not loaded'
  end

  local oldLevel = player.level
  local oldTotal = player.totalXp

  local newTotal = math.max(0, floor(totalXp))

  if not force and newTotal < oldTotal and not Config.Leveling.AllowLevelDown then
    local minForCurrentLevel = totalXpToReachLevel(oldLevel)
    if newTotal < minForCurrentLevel then
      newTotal = minForCurrentLevel
    end
  end

  if Config.Leveling.ClampAtMax then
    local maxXp = maxTotalXp()
    if newTotal > maxXp then
      newTotal = maxXp
    end
  end

  local computed = computeFromTotalXp(newTotal)
  applyComputedData(player, computed)
  player.dirty = true

  syncPlayer(src)

  if player.level ~= oldLevel then
    local toastType = (player.level > oldLevel) and 'up' or 'down'
    TriggerClientEvent('awz_levelhud:toast', src, toastType, oldLevel, player.level, Config.Toast.DurationMs)
    TriggerEvent('awz_levelhud:levelChanged', src, oldLevel, player.level, reason or 'unknown')
  end

  dbg(('XP APPLY src=%s charid=%s oldTotal=%s newTotal=%s reason=%s -> L%s XP%s'):format(
    src,
    player.charid,
    oldTotal,
    player.totalXp,
    tostring(reason or 'unknown'),
    player.level,
    player.totalXp
  ))

  return true, shallowCopyLevelData(player)
end

local function changeXp(src, delta, reason)
  src = tonumber(src)
  delta = floor(delta)

  if not src or src <= 0 then
    return false, 'invalid source'
  end

  local player = loadPlayer(src)
  if not player then
    return false, 'player not loaded'
  end

  return applyTotalXp(src, player.totalXp + delta, reason, false)
end

local function setLevel(src, targetLevel, reason)
  local maxLevel = Config.Leveling.MaxLevel or 100
  targetLevel = clamp(targetLevel, 1, maxLevel)
  local totalXp = totalXpToReachLevel(targetLevel)
  return applyTotalXp(src, totalXp, reason or 'set_level', true)
end

local function setXP(src, totalXp, reason)
  return applyTotalXp(src, totalXp, reason or 'set_xp', true)
end

MySQL.ready(function()
  CreateThread(function()
    if Config.Database.AutoCreateTable then
      MySQL.query.await(([[ 
        CREATE TABLE IF NOT EXISTS `%s` (
          `id` INT NOT NULL AUTO_INCREMENT,
          `charid` INT NOT NULL,
          `identifier` VARCHAR(80) NULL,
          `level` INT NOT NULL DEFAULT 1,
          `total_xp` INT NOT NULL DEFAULT 0,
          `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
          `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
          PRIMARY KEY (`id`),
          UNIQUE KEY `uniq_charid` (`charid`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
      ]]):format(TABLE))
    end

    DBReady = true
    dbg('Database ready on table', TABLE)
  end)
end)

RegisterNetEvent('awz_levelhud:requestSync', function()
  local src = source
  local player = loadPlayer(src)
  if not player then return end
  syncPlayer(src)
end)

AddEventHandler('vorp:SelectedCharacter', function(src, character)
  src = tonumber(src) or source
  if not src then return end

  Players[src] = nil

  CreateThread(function()
    Wait(500)
    local player = loadPlayer(src)
    if not player then return end
    syncPlayer(src)
    TriggerClientEvent('awz_levelhud:forceSyncClient', src)
  end)
end)

AddEventHandler('playerDropped', function()
  local src = source
  savePlayer(src, true)
  Players[src] = nil
end)

AddEventHandler('onResourceStop', function(res)
  if res ~= RESOURCE then return end
  for src in pairs(Players) do
    savePlayer(src, true)
  end
end)

CreateThread(function()
  while true do
    Wait(Config.Database.SaveIntervalMs or 60000)
    for src in pairs(Players) do
      savePlayer(src, false)
    end
  end
end)

AddEventHandler('awz_levelhud:addXP', function(targetSrc, amount, reason)
  changeXp(targetSrc, math.abs(floor(amount)), reason or 'event_add')
end)

AddEventHandler('awz_levelhud:removeXP', function(targetSrc, amount, reason)
  changeXp(targetSrc, -math.abs(floor(amount)), reason or 'event_remove')
end)

AddEventHandler('awz_levelhud:setLevel', function(targetSrc, level, reason)
  setLevel(targetSrc, level, reason or 'event_setlevel')
end)

AddEventHandler('awz_levelhud:setXP', function(targetSrc, xp, reason)
  setXP(targetSrc, xp, reason or 'event_setxp')
end)

AddEventHandler('awz_levelhud:getLevel', function(targetSrc, cb)
  if type(cb) ~= 'function' then return end
  local player = loadPlayer(targetSrc)
  cb(player and player.level or nil)
end)

AddEventHandler('awz_levelhud:getXP', function(targetSrc, cb)
  if type(cb) ~= 'function' then return end
  local player = loadPlayer(targetSrc)
  cb(player and player.totalXp or nil)
end)

AddEventHandler('awz_levelhud:getLevelData', function(targetSrc, cb)
  if type(cb) ~= 'function' then return end
  local player = loadPlayer(targetSrc)
  cb(shallowCopyLevelData(player))
end)

exports('AddXP', function(src, amount, reason)
  return changeXp(src, math.abs(floor(amount)), reason or 'export_add')
end)

exports('RemoveXP', function(src, amount, reason)
  return changeXp(src, -math.abs(floor(amount)), reason or 'export_remove')
end)

exports('SetLevel', function(src, level, reason)
  return setLevel(src, level, reason or 'export_setlevel')
end)

exports('SetXP', function(src, totalXp, reason)
  return setXP(src, totalXp, reason or 'export_setxp')
end)

exports('GetLevel', function(src)
  src = tonumber(src)
  if not src then return nil end
  local player = loadPlayer(src)
  return player and player.level or nil
end)

exports('GetXP', function(src)
  src = tonumber(src)
  if not src then return nil end
  local player = loadPlayer(src)
  return player and player.totalXp or nil
end)

exports('GetLevelData', function(src)
  src = tonumber(src)
  if not src then return nil end
  local player = loadPlayer(src)
  return shallowCopyLevelData(player)
end)

exports('SyncPlayer', function(src)
  src = tonumber(src)
  if not src then return false end
  local player = loadPlayer(src)
  if not player then return false end
  syncPlayer(src)
  return true
end)

exports('GetXPNeededForLevel', function(level)
  return xpNeededForLevel(level)
end)

exports('GetXPToReachLevel', function(level)
  return totalXpToReachLevel(level)
end)

if Config.Admin.Enabled then
  RegisterCommand(Config.Admin.Commands.AddXP, function(src, args)
    if not hasAdminAccess(src) then
      reply(src, 'Non hai i permessi.')
      return
    end

    local target = tonumber(args[1])
    local amount = tonumber(args[2])
    local reason = table.concat(args, ' ', 3)

    if not target or not amount then
      reply(src, ('Uso: /%s [id] [xp] [motivo opzionale]'):format(Config.Admin.Commands.AddXP))
      return
    end

    local ok, data = changeXp(target, math.abs(floor(amount)), reason ~= '' and reason or 'admin_addxp')
    if not ok then
      reply(src, ('Errore: %s'):format(tostring(data)))
      return
    end

    reply(src, ('Aggiunti %s XP a %s -> livello %s (%s XP totali, charid %s)'):format(
      math.abs(floor(amount)), target, data.level, data.totalXp, data.charid
    ))
  end, false)

  RegisterCommand(Config.Admin.Commands.RemoveXP, function(src, args)
    if not hasAdminAccess(src) then
      reply(src, 'Non hai i permessi.')
      return
    end

    local target = tonumber(args[1])
    local amount = tonumber(args[2])
    local reason = table.concat(args, ' ', 3)

    if not target or not amount then
      reply(src, ('Uso: /%s [id] [xp] [motivo opzionale]'):format(Config.Admin.Commands.RemoveXP))
      return
    end

    local ok, data = changeXp(target, -math.abs(floor(amount)), reason ~= '' and reason or 'admin_removexp')
    if not ok then
      reply(src, ('Errore: %s'):format(tostring(data)))
      return
    end

    reply(src, ('Rimossi %s XP a %s -> livello %s (%s XP totali, charid %s)'):format(
      math.abs(floor(amount)), target, data.level, data.totalXp, data.charid
    ))
  end, false)

  RegisterCommand(Config.Admin.Commands.SetLevel, function(src, args)
    if not hasAdminAccess(src) then
      reply(src, 'Non hai i permessi.')
      return
    end

    local target = tonumber(args[1])
    local level = tonumber(args[2])
    local reason = table.concat(args, ' ', 3)

    if not target or not level then
      reply(src, ('Uso: /%s [id] [livello] [motivo opzionale]'):format(Config.Admin.Commands.SetLevel))
      return
    end

    local ok, data = setLevel(target, level, reason ~= '' and reason or 'admin_setlevel')
    if not ok then
      reply(src, ('Errore: %s'):format(tostring(data)))
      return
    end

    reply(src, ('Impostato livello %s a %s -> XP totali %s (charid %s)'):format(
      data.level, target, data.totalXp, data.charid
    ))
  end, false)

  RegisterCommand(Config.Admin.Commands.SetXP, function(src, args)
    if not hasAdminAccess(src) then
      reply(src, 'Non hai i permessi.')
      return
    end

    local target = tonumber(args[1])
    local xp = tonumber(args[2])
    local reason = table.concat(args, ' ', 3)

    if not target or xp == nil then
      reply(src, ('Uso: /%s [id] [xp_totali] [motivo opzionale]'):format(Config.Admin.Commands.SetXP))
      return
    end

    local ok, data = setXP(target, xp, reason ~= '' and reason or 'admin_setxp')
    if not ok then
      reply(src, ('Errore: %s'):format(tostring(data)))
      return
    end

    reply(src, ('Impostati %s XP totali a %s -> livello %s (charid %s)'):format(
      data.totalXp, target, data.level, data.charid
    ))
  end, false)
end