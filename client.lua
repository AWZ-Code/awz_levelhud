local RESOURCE = GetCurrentResourceName()

local hudVisible = false
local peekHeld = false

local OPEN_WHEEL_CONTROL = (Config and Config.HUD and Config.HUD.PeekControlHash) or 0xAC4BD4F1
local POLL_ACTIVE_MS     = (Config and Config.HUD and Config.HUD.PollActiveMs) or 0
local POLL_IDLE_MS       = (Config and Config.HUD and Config.HUD.PollIdleMs) or 100
local SYNC_DELAY_MS      = (Config and Config.HUD and Config.HUD.SyncDelayMs) or 1500
local RESPAWN_SYNC_MS    = (Config and Config.HUD and Config.HUD.RespawnSyncDelayMs) or 2500
local TOAST_DURATION_MS  = (Config and Config.Toast and Config.Toast.DurationMs) or 2600

local state = {
  level = 1,
  progress = 0,
  currentXp = 0,
  nextXp = 100,
}

local function dbg(...)
  if not (Config and Config.Debug) then return end
  local parts = { ('^3[%s]^7'):format(RESOURCE) }
  for i = 1, select('#', ...) do
    parts[#parts + 1] = tostring(select(i, ...))
  end
  print(table.concat(parts, ' '))
end

local function clamp(v, min, max)
  v = tonumber(v) or min
  if v < min then return min end
  if v > max then return max end
  return v
end

local function copyState()
  return {
    level = state.level,
    progress = state.progress,
    currentXp = state.currentXp,
    nextXp = state.nextXp,
  }
end

local function normalizeState(level, progress, currentXp, nextXp)
  state.level     = clamp(level or state.level or 1, 1, 999)
  state.progress  = clamp(progress or state.progress or 0, 0, 100)
  state.currentXp = math.floor(tonumber(currentXp) or state.currentXp or 0)
  state.nextXp    = math.max(1, math.floor(tonumber(nextXp) or state.nextXp or 100))
end

local function buildPayload(action, visible)
  return {
    action = action or 'level:update',
    visible = visible == true,
    level = state.level,
    progress = state.progress,
    currentXp = state.currentXp,
    nextXp = state.nextXp,
  }
end

local function sendShow()
  local payload = buildPayload('level:show', true)
  SendNUIMessage(payload)
  hudVisible = true
  dbg('SHOW', json.encode(payload))
end

local function sendUpdate()
  local payload = buildPayload('level:update', true)
  SendNUIMessage(payload)
  dbg('UPDATE', json.encode(payload))
end

local function pushHud()
  if not peekHeld then return end

  if hudVisible then
    sendUpdate()
  else
    sendShow()
  end
end

local function hideHud()
  if not hudVisible then return end
  hudVisible = false
  SendNUIMessage({ action = 'level:hide' })
  dbg('HIDE')
end

local function showLevelHud(level, progress, currentXp, nextXp)
  normalizeState(level, progress, currentXp, nextXp)

  if peekHeld then
    pushHud()
  else
    dbg('STATE STORED (hidden)', json.encode(buildPayload('level:update', false)))
  end
end

local function updateLevelHud(level, progress, currentXp, nextXp)
  normalizeState(level, progress, currentXp, nextXp)

  if peekHeld then
    pushHud()
  else
    dbg('STATE UPDATED (hidden)', json.encode(buildPayload('level:update', false)))
  end
end

local function hideLevelHud()
  hideHud()
end

local function showLevelToast(kind, oldLevel, newLevel, duration)
  SendNUIMessage({
    action = 'level:toast',
    toastType = kind or 'up',
    oldLevel = math.floor(tonumber(oldLevel) or 1),
    newLevel = math.floor(tonumber(newLevel) or 1),
    duration = math.max(500, math.floor(tonumber(duration) or TOAST_DURATION_MS))
  })

  dbg('TOAST', tostring(kind), tostring(oldLevel), tostring(newLevel))
end

local function requestSync()
  TriggerServerEvent('awz_levelhud:requestSync')
  dbg('REQUEST SYNC')
end

AddEventHandler('onResourceStart', function(res)
  if res ~= RESOURCE then return end

  Wait(500)
  SendNUIMessage({ action = 'level:init' })
  dbg('NUI INIT SENT')

  Wait(SYNC_DELAY_MS)
  requestSync()
end)

AddEventHandler('onResourceStop', function(res)
  if res ~= RESOURCE then return end
  hideHud()
end)

AddEventHandler('playerSpawned', function()
  CreateThread(function()
    Wait(RESPAWN_SYNC_MS)
    requestSync()
  end)
end)

CreateThread(function()
  while true do
    local pressed = IsControlPressed(0, OPEN_WHEEL_CONTROL)

    if pressed then
      if not peekHeld then
        peekHeld = true
        pushHud()
      elseif hudVisible then
        sendUpdate()
      end

      Wait(POLL_ACTIVE_MS)
    else
      if peekHeld then
        peekHeld = false
        hideHud()
      end

      Wait(POLL_IDLE_MS)
    end
  end
end)

RegisterNetEvent('vorp:SelectedCharacter', function(charid)
  CreateThread(function()
    Wait(1000)
    TriggerServerEvent('awz_levelhud:requestSync')
  end)
end)

RegisterCommand('levelsync', function()
  requestSync()
end, false)

RegisterCommand('leveltest', function(_, args)
  local level    = tonumber(args[1]) or 12
  local progress = tonumber(args[2]) or 67
  local current  = tonumber(args[3]) or 670
  local nextXp   = tonumber(args[4]) or 1000
  showLevelHud(level, progress, current, nextXp)
end, false)

RegisterCommand('levelupdate', function(_, args)
  local level    = tonumber(args[1]) or state.level
  local progress = tonumber(args[2]) or 25
  local current  = tonumber(args[3]) or 250
  local nextXp   = tonumber(args[4]) or state.nextXp
  updateLevelHud(level, progress, current, nextXp)
end, false)

RegisterCommand('levelhide', function()
  hideLevelHud()
end, false)

RegisterCommand('leveltoast', function(_, args)
  local kind = args[1] or 'up'
  local oldLevel = tonumber(args[2]) or 4
  local newLevel = tonumber(args[3]) or 5
  showLevelToast(kind, oldLevel, newLevel)
end, false)

RegisterNetEvent('awz_levelhud:show', function(level, progress, currentXp, nextXp)
  showLevelHud(level, progress, currentXp, nextXp)
end)

RegisterNetEvent('awz_levelhud:update', function(level, progress, currentXp, nextXp)
  updateLevelHud(level, progress, currentXp, nextXp)
end)

RegisterNetEvent('awz_levelhud:hide', function()
  hideLevelHud()
end)

RegisterNetEvent('awz_levelhud:toast', function(kind, oldLevel, newLevel, duration)
  showLevelToast(kind, oldLevel, newLevel, duration)
end)

RegisterNetEvent('awz_levelhud:forceSyncClient', function()
  requestSync()
end)

exports('ShowLevelHud', showLevelHud)
exports('UpdateLevelHud', updateLevelHud)
exports('HideLevelHud', hideLevelHud)
exports('ShowLevelToast', showLevelToast)
exports('RequestSync', requestSync)
exports('GetCachedLevelData', copyState)
exports('IsPeekHeld', function()
  return peekHeld
end)