# Fælles WoW-attrap til testene (en lille udgave af spillets API, nok til at addonet kan køre)
MOCK = r'''
NOW = 1800000000
CLOCK = 1000
SENT = {}
PRINTS = {}
TIMERS = {}
TICKERS = {}
FRAMES = {}
EMOTES = {}
function time() return NOW end
date = os.date
function GetTime() return CLOCK end
function GetBuildInfo() return "2.5.5", "1", "", 20506 end
local real_print = print
function print(...) local t = {} for i = 1, select("#", ...) do t[#t+1] = tostring((select(i, ...))) end PRINTS[#PRINTS+1] = table.concat(t, " ") end
PLAYER = "Mathiasx"
function UnitName(u) if u == "player" then return PLAYER end if u == "target" then return TARGET_NAME end end
function UnitClass(u) return "Warrior", "WARRIOR" end
function UnitLevel(u) if u == "target" then return TARGET_LEVEL end return 40 end
function UnitExists(u) if u == "target" then return TARGET_NAME ~= nil end return false end
function UnitGUID() return "guid" end
function UnitXP() return 10 end
function UnitXPMax() return 100 end
function UnitIsAFK() return false end
function UnitAffectingCombat() return false end
MONEY = 12345
function GetMoney() return MONEY end
-- Guild bank, tasker og repair
BAGS = { [0] = { { id = 13446, count = 5 }, {} } }
C_Container = {
  GetContainerNumSlots = function(b) return BAGS[b] and #BAGS[b] or 0 end,
  GetContainerItemInfo = function(b, s) local x = BAGS[b] and BAGS[b][s] if x and x.id and x.count > 0 then return { itemID = x.id, stackCount = x.count } end end,
}
function GetInventoryItemID() return nil end
function hooksecurefunc(name, f) local orig = _G[name] _G[name] = function(...) local r = { orig(...) } f(...) return unpack(r) end end
function DepositGuildBankMoney() end
function WithdrawGuildBankMoney() end
REPAIR_COST = 0
function GetRepairAllCost() return REPAIR_COST, REPAIR_COST > 0 end
REPAIR_GUILD_OK = true
function RepairAllItems(guild) if guild and not REPAIR_GUILD_OK then return end if not guild then MONEY = MONEY - REPAIR_COST end REPAIR_COST = 0 end
function GetZoneText() return "Westfall" end
function IsInRaid() return false end
function IsInGroup() return true end
function IsInGuild() return true end
function GetChannelName() return 0 end
function ChatFrame_AddMessageEventFilter() end
function GetNumGroupMembers() return 0 end
function IsInInstance() return false, "none" end
function strsplit(sep, s, n)
  local res, i = {}, 1
  if n then
    local a, b = s:find(sep, 1, true)
    if a then return s:sub(1, a-1), s:sub(b+1) end
    return s
  end
  for part in (s .. sep):gmatch("(.-)" .. sep:gsub("%p", "%%%0")) do res[#res+1] = part end
  return unpack(res)
end
function strtrim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
C_ChatInfo = {
  SendAddonMessage = function(prefix, msg, ch, target) SENT[#SENT+1] = { msg = msg, ch = ch, target = target } end,
  RegisterAddonMessagePrefix = function() return true end,
}
C_Timer = {
  After = function(d, f) TIMERS[#TIMERS+1] = f end,
  NewTicker = function(d, f) TICKERS[#TICKERS+1] = { d = d, f = f } return {} end,
}
function RunTimers() local n = 0 while #TIMERS > 0 and n < 200 do local f = table.remove(TIMERS, 1) f() n = n + 1 end end
ITEMS = {}  -- id -> { equip = bool, count = n, equipped = bool }
function GetItemInfo(x) local id = tonumber(tostring(x):match("(%d+)")) if ITEMS[id] then return "Item" .. id, nil, 3 end end
function IsEquippableItem(id) return ITEMS[id] and ITEMS[id].equip end
function IsEquippedItem(id) return ITEMS[id] and ITEMS[id].equipped end
function GetItemCount(id) return ITEMS[id] and ITEMS[id].count or 0 end
function GetItemIcon() return "icon" end
function DoEmote(token, unit) EMOTES[#EMOTES+1] = token .. ">" .. tostring(unit) end
function PlaySound() end
function PlaySoundFile() return true end
SOUNDKIT = { RAID_WARNING = 1, LEVELUP = 2 }
RAID_CLASS_COLORS = { WARRIOR = { r = 0.78, g = 0.61, b = 0.43 } }
CLASS_ICON_TCOORDS = { WARRIOR = { 0, 0.25, 0, 0.25 } }
LOCALIZED_CLASS_NAMES_MALE = {}
UISpecialFrames = {}
SlashCmdList = {}
YOU = "You"
RANDOM_ROLL_RESULT = "%s rolls %d (%d-%d)"
DUEL_WINNER_KNOCKOUT = "%1$s has defeated %2$s in a duel"
DUEL_WINNER_RETREAT = "%2$s has fled from %1$s in a duel"
LOOT_ROLL_YOU_WON = "You won: %s"
LOOT_ROLL_NEED_SELF = "You have selected Need for: %s"
LOOT_ROLL_ROLLED_NEED = "Need Roll - %d for %s by %s"
LOOT_ITEM_SELF = "You receive loot: %s."

local frameMT
local function newObj()
  local o = { scripts = {}, shown = true, events = {} }
  return setmetatable(o, frameMT)
end
frameMT = { __index = function(t, k)
  if k == "SetScript" then return function(self, name, f) self.scripts[name] = f end end
  if k == "GetScript" then return function(self, name) return self.scripts[name] end end
  if k == "RegisterEvent" then return function(self, e) self.events[e] = true end end
  if k == "CreateTexture" or k == "CreateFontString" then return function() return newObj() end end
  if k == "SetText" then return function(self, s) self.text_ = s end end
  if k == "GetText" then return function(self) return self.text_ end end
  if k == "Show" then return function(self) self.shown = true end end
  if k == "Hide" then return function(self) self.shown = false end end
  if k == "SetShown" then return function(self, v) self.shown = v and true or false end end
  if k == "IsShown" then return function(self) return self.shown end end
  if k == "GetPoint" then return function() return "CENTER", nil, "CENTER", 0, 0 end end
  if k == "GetChecked" then return function() return false end end
  return function() end
end }
function CreateFrame(kind, name, parent)
  local f = newObj()
  FRAMES[#FRAMES+1] = f
  if name then _G[name] = f end
  return f
end
UIParent = newObj()
Minimap = newObj()
Minimap.GetCenter = function() return 0, 0 end
Minimap.GetEffectiveScale = function() return 1 end
function GetCursorPosition() return 10, 20 end
GameTooltip = newObj()
function Fire(event, ...)
  for _, f in ipairs(FRAMES) do
    if f.events[event] and f.scripts.OnEvent then f.scripts.OnEvent(f, event, ...) end
  end
end
'''

FILES = ["Locale.lua", "Locale_en.lua", "Sounds.lua", "WastedCoast.lua", "Groups.lua", "Drilleri.lua", "Dueller.lua", "Bank.lua", "Played.lua", "Gossip.lua", "Rares.lua"]


def load_addon(lua, addon_dir, ns):
    """Indlæser addonets filer i samme rækkefølge som .toc-filen."""
    loader = lua.eval("function(code, name) local f, err = loadstring(code, name) if not f then error(err) end return f end")
    for f in FILES:
        code = open(f"{addon_dir}/{f}", encoding="utf-8").read()
        loader(code, "@" + f)("WastedCoast", ns)
