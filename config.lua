Config = {}

Config.Debug = true

Config.Database = {
  TableName = 'awz_levelhud_players',
  AutoCreateTable = true,
  SaveIntervalMs = 60000,
}

Config.IdentifierPriority = {
  'license',
  'license2',
  'fivem',
  'discord',
  'steam',
}

Config.Leveling = {
  StartTotalXP = 0,
  MaxLevel = 250,

  BaseXP = 1000,
  LinearGrowth = 25,
  CurveGrowth = 10,
  Exponent = 1.20,

  AllowLevelDown = true,
  ClampAtMax = true,
}

Config.HUD = {
  PeekControlHash = 0xAC4BD4F1, -- TAB / weapon wheel
  PollActiveMs = 0,
  PollIdleMs = 100,
  SyncDelayMs = 1500,
  RespawnSyncDelayMs = 2500,
}

Config.Toast = {
  DurationMs = 2600,
}

Config.Admin = {
  Enabled = true,
  AcePermission = 'awz.levelhud.admin',

  Commands = {
    AddXP = 'addxp',
    RemoveXP = 'removexp',
    SetLevel = 'setlevel',
    SetXP = 'setxp',
  }
}