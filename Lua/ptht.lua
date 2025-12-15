local WEBHOOK_URL = "https://discord.com/api/webhooks/1448592081131143168/6EeJODVjRAbiCNpEHEmZvY8R0lknMJRcPKZTC9BbNvz7jI-rHACDu-7FeCkbVxNb1k7X"
local DISCORD_NOTIFY_USER_ID = "350997207723278336"

delaypt = 5
delayht = 5
yTop = 0
yBottom = 112
seedID = 5640
platID = 8682
mode = "Vertical"

SCAN_X_MIN, SCAN_X_MAX = 0, 100
CHUNK_STEP, MOVE_SLEEP = 6, 1
ARRIVE_TO, HARVEST_RETRY = 1, 2
HARVEST_DELAY, SCAN_STEP = 1, 6

local running = false
local threadLoop = nil
local requestUWS = false
local showMenu = true
useCount = false
maxCount = 1
currentCount = 0

MAGSpot = {}
MAGSpotEmpty = {}
local useMagSpot = false
local maxMAGSpots = 10
local newMAGSpotX, newMAGSpotY = 0, 0
local currentMAGIndex = 1
local waitingForMagplant = false
local reqStartPTHT = false
local reqBindMAG = false
local reqBindMAGIndex = 1
local pendingMAGBind = nil
local pending_stop_webhook = nil
local stop_notified = false
local stopping = false
credit = "`6@Lent"

-- delay (ms) to wait before binding next MAG spot (2-3s recommended)
local mag_switch_delay_ms = 2500

local function safe_getenv(key)
  if type(key) ~= "string" then
    return nil
  end
  if type(os) == "table" and type(os.getenv) == "function" then
    local ok, v = pcall(os.getenv, key)
    if ok then
      return v
    end
  end
  if _G and type(_G.env) == "table" then
    return _G.env[key]
  end
  return nil
end

local function safe_date(fmt)
  if type(os) == "table" and type(os.date) == "function" then
    local ok, v = pcall(os.date, fmt)
    if ok and v then
      return v
    end
  end
  return ""
end

local startTime = nil
local stopTime = nil

local function format_elapsed_time(start_time, end_time)
  local elapsed_seconds = end_time - start_time
  local hours = math.floor(elapsed_seconds / 3600)
  local minutes = math.floor((elapsed_seconds % 3600) / 60)
  local seconds = elapsed_seconds % 60
  return string.format("%d Hours %d Minutes %d Seconds", hours, minutes, seconds)
end

local function StopAll(reason)
  if stopping then
    return
  end
  stopping = true
  if stop_notified then
    stopping = false
    return
  end
  stop_notified = true
  current_activity = "STOP"
  if not stopTime and startTime then
    stopTime = os.time()
  end
  running = false
  waitingForMagplant = false
  pendingMAGBind = nil
  Overlay("`4PTHT Stopped!")
  ChangeValue("[C] Noclip", false)
  ghost()
  local pc, pm = (useCount and currentCount or nil), (useCount and maxCount or nil)
  local user_mention = (CustomizeWebhook and CustomizeWebhook.DiscordID and "<@" .. CustomizeWebhook.DiscordID .. ">") or "Unknown"
  if type(send_fixed_embed) == "function" then
    local ok, err = send_fixed_embed("PTHT Information!", "STOP", mode, user_mention, currentMAGIndex, #MAGSpot, pc, pm, false, reason)
    if not ok then
      Log("`4Webhook STOP gagal: " .. tostring(err))
    else
      Log("`2Webhook STOP terkirim.")
    end
  else
    pending_stop_webhook = {
      user = user_mention,
      pc = pc,
      pm = pm,
      reason = reason
    }
  end
  stopping = false
end

local CustomizeWebhook = {
  WebHooks = safe_getenv("DISCORD_WEBHOOK_URL") or WEBHOOK_URL,
  DiscordID = safe_getenv("DISCORD_NOTIFY_USER_ID") or DISCORD_NOTIFY_USER_ID,
  BotName = "PTHT Bot",
  AuthorName = "𝙇𝙀𝙉𝙏 𝙎𝙏𝙊𝙍𝙀",
  AuthorIcon = "https://cdn.discordapp.com/attachments/1186222399872573522/1447748048217313402/LOGO.png?ex=6938bff0&is=69376e70&hm=c7b1623051eefeb2511d7fd50d4eeb28a08addd13b243e66115410027a53e881",
  Thumbnail = "",
  FooterText = "𝙇𝙀𝙉𝙏 𝙎𝙏𝙊𝙍𝙀 • PTHT Webhook",
  MagplantEmoji = safe_getenv("MAGPLANT_EMOJI") or "<:magplant:1447714455059173571>"
}

local env_enable_webhook = safe_getenv("ENABLE_WEBHOOK")
local enableWebhook = true
if type(env_enable_webhook) == "string" then
  local le = env_enable_webhook:lower()
  if le == "0" or le == "false" or le == "no" then
    enableWebhook = false
  end
end

local emoji_map = {
  START = "<:online:1447747481176768713>",
  PLANT = "<:seed:1447738172363767898>",
  HARVEST = "<:tree:1447739511617490975>",
  UWS = "<:uws:1447740786077728829>",
  STOP = "<:dnd:1447747548113670204>",
  PROGRESS = "🔁",
  DEFAULT = "ℹ️"
}

local function resolve_magplant_emoji(raw)
  if not raw or raw == "" then
    return "📍", nil
  end
  local anim, name, id = raw:match("^<(a?):([%w_]+):(%d+)>$")
  if id then
    local ext = (anim == "a") and "gif" or "png"
    local url = "https://cdn.discordapp.com/emojis/" .. id .. "." .. ext
    return raw, url
  end
  local onlyid = raw:match("^(%d+)$")
  if onlyid then
    local url = "https://cdn.discordapp.com/emojis/" .. onlyid .. ".png"
    return "📍", url
  end
  if raw:match("^https?://") then
    return "📍", raw
  end
  return raw, nil
end

local function SendWebhook(url, data)
  if not url or url == "" then
    return false, "No webhook url"
  end
  if type(MakeRequest) == "function" then
    local ok, err = pcall(function()
      MakeRequest(url, "POST", { ["Content-Type"] = "application/json" }, data)
    end)
    if ok then
      return true
    end
    return false, tostring(err)
  end
  local ok_ssl, https = pcall(require, "ssl.https")
  local ok_ltn, ltn12 = pcall(require, "ltn12")
  if ok_ssl and ok_ltn and https and ltn12 then
    local response_chunks = {}
    local res, code = https.request({
      url = url,
      method = "POST",
      headers = {
        ["Content-Type"] = "application/json",
        ["Content-Length"] = tostring(#data)
      },
      source = ltn12.source.string(data),
      sink = ltn12.sink.table(response_chunks)
    })
    code = tonumber(code) or 0
    local body = table.concat(response_chunks or {})
    if code >= 200 and code < 300 then
      return true
    end
    return false, "HTTP " .. tostring(code) .. " " .. tostring(body)
  end
  return false, "No supported HTTP method"
end

local function esc(s)
  if s == nil then
    return ""
  end
  s = tostring(s)
  s = s:gsub("\\", "\\\\"):gsub('"', '\\"'):gsub("\n", "\\n")
  return s
end

local function choose_color_for_status(activity)
  local map = {
    START = 0x1ABC9C,
    PLANT = 0x2ECC71,
    HARVEST = 0xF1C40F,
    UWS = 0x3498DB,
    STOP = 0xE74C3C,
    PROGRESS = 0x9B59B6,
    DEFAULT = 0x95A5A6
  }
  return map[activity] or map.DEFAULT
end

local function make_progress_bar_capsule_exact(cur, max, length)
  if not cur or not max or max <= 0 then
    return ""
  end
  length = math.max(8, length or 24)
  local ratio = math.min(1, math.max(0, cur / max))
  local knob_index = math.floor(ratio * length) + 1
  if knob_index < 1 then
    knob_index = 1
  end
  if knob_index > length then
    knob_index = length
  end
  local inner = {}
  for i = 1, length do
    if i < knob_index then
      inner[i] = "━"
    elseif i == knob_index then
      inner[i] = "◉"
    else
      if ((i - knob_index) % 2 == 1) then
        inner[i] = "╱"
      else
        inner[i] = "░"
      end
    end
  end
  local left_cap = "◜"
  local right_cap = "◝"
  local bar = left_cap .. table.concat(inner) .. right_cap
  local pct = math.floor(ratio * 100)
  return string.format("`%s` %d%% (`%d/%d`)", bar, pct, cur, max)
end

make_progress_bar = make_progress_bar_capsule_exact

if type(make_progress_bars_bar) ~= "function" then
  if type(make_progress_bar) == "function" then
    make_progress_bars_bar = make_progress_bar
  elseif type(make_progress_bar_capsule) == "function" then
    make_progress_bars_bar = make_progress_bar_capsule
  elseif type(make_progress_bar_neon) == "function" then
    make_progress_bars_bar = make_progress_bar_neon
  else
    make_progress_bars_bar = function(cur, max, length)
      if not cur or not max or max <= 0 then
        return ""
      end
      length = length or 12
      local ratio = math.min(1, math.max(0, cur / max))
      local filled = math.floor(ratio * length)
      local empty = length - filled
      local bar = string.rep("█", filled) .. string.rep("░", empty)
      local pct = math.floor(ratio * 100)
      return string.format("`%s` %d%% (`%d/%d`)", bar, pct, cur, max)
    end
  end
end

local function build_fixed_embed(title, activity, mode, user_mention, mag_index, mag_count, progress_cur, progress_max, is_running, thumbnail_url)
  local color = choose_color_for_status(activity)
  local safe = function(s)
    if s == nil then
      return ""
    end
    return tostring(s):gsub('"', '\\"')
  end
  local activity_desc_map = {
    START = "Started",
    PLANT = "Planting",
    HARVEST = "Harvesting",
    UWS = "UWS",
    STOP = "Stopped",
    PROGRESS = "In Progress"
  }
  local activity_desc = activity_desc_map[activity] or activity or "Unknown"
  local activity_emoji = emoji_map[activity] or emoji_map.DEFAULT
  local mag_print, _mag_thumb = resolve_magplant_emoji(CustomizeWebhook.MagplantEmoji)
  local mag_emoji = mag_print or "📍"
  local thumb = thumbnail_url or (CustomizeWebhook and CustomizeWebhook.Thumbnail or "")
  local thumb_part = ""
  if thumb and thumb ~= "" then
    thumb_part = string.format(', "thumbnail": { "url": "%s" }', safe(thumb))
  end
  local mag_label = mag_emoji .. " MAG Spot"
  local mag_text = "-"
  if type(mag_index) == "number" and type(mag_count) == "number" then
    mag_text = string.format("#%d", mag_index, mag_count)
  elseif type(mag_index) == "number" then
    mag_text = string.format("#%d", mag_index)
  elseif type(mag_count) == "number" then
    mag_text = string.format('#? / %d', mag_count)
  end
  if type(mag_text) == "string" and mag_text:find("#") then
    mag_text = "Spot " .. mag_text
  end
  local mag_table = (type(MAGSpot) == "table" and MAGSpot) or (_G and type(_G.MAGSpot) == "table" and _G.MAGSpot) or nil
  local coord_text = ""
  if type(mag_index) == "number" and mag_table and mag_table[mag_index] then
    local spot = mag_table[mag_index]
    if spot and (type(spot.x) == "number" or type(spot.x) == "string") and (type(spot.y) == "number" or type(spot.y) == "string") then
      coord_text = string.format(" (`%s,%s`)", tostring(spot.x), tostring(spot.y))
    end
  end
  mag_text = mag_text .. coord_text
  local progress_field = ""
  if type(progress_cur) == "number" and type(progress_max) == "number" and progress_max > 0 then
    progress_field = make_progress_bar(progress_cur, progress_max, 14)
  elseif useCount and (type(currentCount) == "number" and type(maxCount) == "number") then
    progress_field = make_progress_bar(currentCount, maxCount, 14)
  end
  local state_text = "Terminated"
  if is_running and startTime then
    state_text = "Running in " .. format_elapsed_time(startTime, os.time())
  elseif (not is_running) and startTime and stopTime then
    state_text = "Terminated, Total Time: " .. format_elapsed_time(startTime, stopTime)
  elseif (not is_running) and startTime and not stopTime then
    state_text = "Stopped (time tracking paused)"
  end
  local author_part = ""
  if CustomizeWebhook and CustomizeWebhook.AuthorName and CustomizeWebhook.AuthorName ~= "" then
    if CustomizeWebhook.AuthorIcon and CustomizeWebhook.AuthorIcon ~= "" then
      author_part = string.format(', "author": { "name": "%s", "icon_url": "%s" }', safe(CustomizeWebhook.AuthorName), safe(CustomizeWebhook.AuthorIcon))
    else
      author_part = string.format(', "author": { "name": "%s" }', safe(CustomizeWebhook.AuthorName))
    end
  end
  local footer_part = ""
  if CustomizeWebhook and CustomizeWebhook.FooterText and CustomizeWebhook.FooterText ~= "" then
    footer_part = string.format(', "footer": { "text": "%s" }', safe(CustomizeWebhook.FooterText))
  end
  local fields_tbl = {
    string.format('{ "name": "User", "value": "%s", "inline": true }', safe(user_mention)),
    string.format('{ "name": "Status", "value": "%s %s", "inline": true }', safe(activity_emoji), safe(activity_desc)),
    string.format('{ "name": "Mode", "value": "%s", "inline": true }', safe(mode)),
    string.format('{ "name": "%s", "value": "%s", "inline": true }', safe(mag_label), safe(mag_text))
  }
  if progress_field ~= "" then
    table.insert(fields_tbl, string.format('{ "name": "Progress PTHT", "value": "%s", "inline": false }', safe(progress_field)))
  end
  table.insert(fields_tbl, string.format('{ "name": "Script State", "value": "%s", "inline": false }', safe(state_text)))
  local fields = table.concat(fields_tbl, ",")
  fields = fields:gsub(",%s*,", ",")
  local embed_title = safe(title or "PTHT Information!")
  local embed = string.format([[
    {
      "title": "%s",
      "color": %d,
      "fields": [ %s ]%s%s%s,
      "timestamp": "%s"
    }
  ]], embed_title, color, fields, author_part, thumb_part, footer_part, safe_date("!%Y-%m-%dT%H:%M:%SZ"))
  return embed
end

local function send_fixed_embed(title, activity, mode, user_mention, mag_index, mag_count, progress_cur, progress_max, is_running, content, thumbnail_url)
  if not enableWebhook then
    return true, "webhook disabled"
  end
  local webhook_url = CustomizeWebhook and CustomizeWebhook.WebHooks or ""
  if webhook_url == "" then
    return false, "no webhook configured"
  end
  local embed_json = build_fixed_embed(title, activity, mode, user_mention, mag_index, mag_count, progress_cur, progress_max, is_running, thumbnail_url)
  local body
  if content and content ~= "" then
    body = string.format('{ "content": "%s", "username": "%s", "embeds": [ %s ] }', esc(content), esc(CustomizeWebhook.BotName or "PTHT"), embed_json)
  else
    body = string.format('{ "username": "%s", "embeds": [ %s ] }', esc(CustomizeWebhook.BotName or "PTHT"), embed_json)
  end
  return SendWebhook(webhook_url, body)
end

if pending_stop_webhook and type(send_fixed_embed) == "function" then
  local p = pending_stop_webhook
  local ok, err = send_fixed_embed("PTHT Information!", "STOP", mode, p.user or ((CustomizeWebhook and CustomizeWebhook.DiscordID and "<@" .. CustomizeWebhook.DiscordID .. ">") or "Unknown"), currentMAGIndex, #MAGSpot, p.pc, p.pm, false, p.reason)
  if not ok then
    Log("`4Webhook STOP gagal: " .. tostring(err))
  else
    pending_stop_webhook = nil
  end
end

function Overlay(txt)
  SendVariantList({ [0] = "OnTextOverlay", [1] = "`w[`6@Lent`w] `9" .. txt })
end

function Log(txt)
  LogToConsole("`w[`6" .. credit .. "`w]: " .. txt)
end

function warn(txt)
  SendVariantList({
    [0] = "OnAddNotification",
    [1] = "interface/atomic_button.rttex",
    [2] = txt,
    [3] = "audio/hub_open.wav"
  })
end

function ghost()
  SendPacket(2, "action|input\n|text|/ghost")
end

local function ThreadSleep(ms)
  local step, elapsed = 8, 0
  while elapsed < ms and running do
    Sleep(step)
    elapsed = elapsed + step
  end
end

function IsReady(tile)
  return tile and tile.extra and tile.extra.progress == 1.0
end

function checkseed()
  local Ready, opCounter = 0, 0
  for y = yBottom, yTop, -1 do
    for x = 0, 100 do
      if not running then
        return 0
      end
      local t = GetTile(x, y)
      if t and t.extra and t.extra.progress == 1.0 then
        Ready = Ready + 1
      end
      opCounter = opCounter + 1
      if opCounter >= 500 then
        Sleep(1)
        opCounter = 0
      end
    end
  end
  return Ready
end

local function wh_user_mention()
  if CustomizeWebhook and CustomizeWebhook.DiscordID and CustomizeWebhook.DiscordID ~= "" then
    return "<@" .. CustomizeWebhook.DiscordID .. ">"
  end
  return "Unknown"
end

local function progress_params_or_nil()
  if useCount then
    return currentCount, maxCount
  end
  return nil, nil
end

local current_activity = nil

local function resend_current_activity()
  if not current_activity then
    return
  end
  local user = wh_user_mention()
  local pc, pm = progress_params_or_nil()
  if current_activity == "START" then
    send_fixed_embed("PTHT Information!", "START", mode, user, currentMAGIndex, #MAGSpot, pc, pm, running)
  elseif current_activity == "HARVEST" then
    send_fixed_embed("PTHT Information!", "HARVEST", mode, user, currentMAGIndex, #MAGSpot, pc, pm, running)
  elseif current_activity == "PLANT" then
    send_fixed_embed("PTHT Information!", "PLANT", mode, user, currentMAGIndex, #MAGSpot, pc, pm, running)
  elseif current_activity == "UWS" then
    send_fixed_embed("PTHT Information!", "UWS", mode, user, currentMAGIndex, #MAGSpot, pc, pm, running)
  elseif current_activity == "PROGRESS" then
    if useCount then
      send_fixed_embed("PTHT Information!", "PROGRESS", mode, user, currentMAGIndex, #MAGSpot, currentCount, maxCount, running)
    end
  elseif current_activity == "STOP" then
    send_fixed_embed("PTHT Information!", "STOP", mode, user, currentMAGIndex, #MAGSpot, (useCount and currentCount or nil), (useCount and maxCount or nil), false)
  else
    send_fixed_embed("PTHT Information!", current_activity, mode, user, currentMAGIndex, #MAGSpot, pc, pm, running)
  end
end

local function notify_stop_once(reason)
  if stop_notified then
    return
  end
  stop_notified = true
  current_activity = "STOP"
  if not stopTime and startTime then
    stopTime = os.time()
  end
  local pc, pm = (useCount and currentCount or nil), (useCount and maxCount or nil)
  pcall(function()
    send_fixed_embed("PTHT Information!", "STOP", mode, wh_user_mention(), currentMAGIndex, #MAGSpot, pc, pm, false)
  end)
end

local function set_activity(activity, manual_note)
  current_activity = activity
  local user = wh_user_mention()
  local pc, pm = progress_params_or_nil()
  if activity == "START" then
    send_fixed_embed("PTHT Information!", "START", mode, user, currentMAGIndex, #MAGSpot, pc, pm, true)
  elseif activity == "HARVEST" then
    send_fixed_embed("PTHT Information!", "HARVEST", mode, user, currentMAGIndex, #MAGSpot, pc, pm, running)
  elseif activity == "PLANT" then
    send_fixed_embed("PTHT Information!", "PLANT", mode, user, currentMAGIndex, #MAGSpot, pc, pm, running)
  elseif activity == "UWS" then
    send_fixed_embed("PTHT Information!", "UWS", mode, user, currentMAGIndex, #MAGSpot, pc, pm, running, manual_note or "")
  elseif activity == "PROGRESS" then
    if useCount then
      send_fixed_embed("PTHT Information!", "PROGRESS", mode, user, currentMAGIndex, #MAGSpot, currentCount, maxCount, running)
    end
  elseif activity == "STOP" then
    StopAll(manual_note)
  else
    send_fixed_embed("PTHT Information!", activity, mode, user, currentMAGIndex, #MAGSpot, pc, pm, running)
  end
end

function punchAbs(x, y)
  local pkt = { type = 3, value = 18, x = x * 32, y = y * 32, px = x, py = y }
  SendPacketRaw(false, pkt)
end

function placeAbs(id, x, y)
  local pkt = { type = 3, value = id, x = x * 32, y = y * 32, px = x, py = y }
  SendPacketRaw(false, pkt)
end

function punchRel()
  local me = GetLocal()
  if not me then
    return
  end
  local pkt = { type = 3, value = 18, x = me.pos.x, y = me.pos.y, px = math.floor(me.pos.x / 32), py = math.floor(me.pos.y / 32) }
  SendPacketRaw(false, pkt)
end

function placeRel(id, rx, ry)
  local me = GetLocal()
  if not me then
    return
  end
  local pkt = { type = 3, value = id, x = me.pos.x, y = me.pos.y, px = math.floor(me.pos.x / 32 + rx), py = math.floor(me.pos.y / 32 + ry) }
  SendPacketRaw(false, pkt)
end

local function localTilePos()
  local me = GetLocal()
  if not me then
    return 0, 0
  end
  return math.floor(me.pos.x / 32), math.floor(me.pos.y / 32)
end

local function WaitForArrive(x, y, timeout)
  local waited, step = 0, 8
  while waited < timeout and running do
    local lx, ly = localTilePos()
    if lx == x and ly == y then
      return true
    end
    Sleep(step)
    waited = waited + step
  end
  local lx, ly = localTilePos()
  return lx == x and ly == y
end

function findPathBothax(x, y)
  if not running then
    return
  end
  local lx, ly = localTilePos()
  local jarax, jaray = x - lx, y - ly
  if jaray > CHUNK_STEP then
    for i = 1, math.floor(jaray / CHUNK_STEP) do
      if not running then
        return
      end
      ly = ly + CHUNK_STEP
      FindPath(lx, ly)
      Sleep(MOVE_SLEEP)
    end
  elseif jaray < -CHUNK_STEP then
    for i = 1, math.floor(-jaray / CHUNK_STEP) do
      if not running then
        return
      end
      ly = ly - CHUNK_STEP
      FindPath(lx, ly)
      Sleep(MOVE_SLEEP)
    end
  end
  lx, ly = localTilePos()
  jarax = x - lx
  if jarax > CHUNK_STEP then
    for i = 1, math.floor(jarax / CHUNK_STEP) do
      if not running then
        return
      end
      lx = lx + CHUNK_STEP
      FindPath(lx, ly)
      Sleep(MOVE_SLEEP)
    end
  elseif jarax < -CHUNK_STEP then
    for i = 1, math.floor(-jarax / CHUNK_STEP) do
      if not running then
        return
      end
      lx = lx - CHUNK_STEP
      FindPath(lx, ly)
      Sleep(MOVE_SLEEP)
    end
  end
  if running then
    FindPath(x, y)
    Sleep(MOVE_SLEEP)
  end
end

-- Updated BindCurrentMAGSpot: only set current/pending at bind time
local function BindCurrentMAGSpot(idx)
  if not useMagSpot or #MAGSpot == 0 then
    Overlay("`4MAG Spot kosong!")
    return
  end
  idx = idx or currentMAGIndex or 1
  -- set currentMAGIndex and pending bind only when actually binding
  currentMAGIndex = idx
  MAGSpotEmpty[currentMAGIndex] = false
  pendingMAGBind = currentMAGIndex
  local spot = MAGSpot[currentMAGIndex] or MAGSpot[1]
  Overlay("`2Take Remote MAG Spot `9(" .. spot.x .. "," .. spot.y .. ")")
  ThreadSleep(800)
  SendPacket(
    2,
    table.concat({
      "action|dialog_return",
      "dialog_name|itemsucker_block",
      "tilex|" .. spot.x .. "|",
      "tiley|" .. spot.y .. "|",
      "buttonClicked|getplantationdevice",
      "chk_enablesucking|1"
    }, "\n")
  )
  ThreadSleep(500)
end

local function ensureAlignment(targetX, targetY)
  local me = GetLocal()
  if not me then
    return
  end
  local lx, ly = math.floor(me.pos.x / 32), math.floor(me.pos.y / 32)
  local dx, dy = math.abs(lx - targetX), math.abs(ly - targetY)
  if dx > 1 or dy > 0 then
    findPathBothax(targetX, targetY)
    WaitForArrive(targetX, targetY, ARRIVE_TO)
    Sleep(5)
  end
end

local function FastGetTile(x, y)
  local t = GetTile(x, y)
  return t or {}
end

-- New function: scan the world area (yTop..yBottom, x 0..200) to detect if platID exists
-- Returns true if found, false otherwise
local function IsPlatIDPresent()
  -- If platID is invalid or nil treat as not present
  if not platID or type(platID) ~= "number" or platID == 0 then
    return false
  end
  local opCounter = 0
  -- Try scanning within configured Y range first (faster)
  for y = yTop, yBottom do
    for x = 0, 200 do
      local t = GetTile(x, y)
      if t and t.fg == platID then
        return true
      end
      opCounter = opCounter + 1
      if opCounter >= 300 then
        Sleep(1)
        opCounter = 0
      end
    end
  end
  -- if not found, do a wider scan across some typical world rows (fallback)
  for y = math.max(0, yTop - 10), (yBottom + 10) do
    for x = 0, 200 do
      local t = GetTile(x, y)
      if t and t.fg == platID then
        return true
      end
      opCounter = opCounter + 1
      if opCounter >= 300 then
        Sleep(1)
        opCounter = 0
      end
    end
  end
  return false
end

function harvestVertical()
  if not running then
    return
  end
  set_activity("HARVEST")
  Overlay("`6Harvest Vertical")
  local opCounter = 0
  for x = 0, 100 do
    if not running then
      return
    end
    local y, step = (x % 2 == 0) and yBottom or yTop, (x % 2 == 0) and -1 or 1
    while y >= yTop and y <= yBottom do
      if not running then
        return
      end
      local t = FastGetTile(x, y)
      if t and t.fg ~= 0 and t.extra and t.extra.progress == 1.0 then
        ensureAlignment(x, y)
        HarvestTileBothax(x, y)
        Sleep(150)
        punchAbs(x + 5, y)
        Sleep(150)
        punchAbs(x + 10, y)
        Sleep(150)
        punchAbs(x + 15, y)
        Sleep(150)
        punchAbs(x + 20, y)
        Sleep(150)
        punchAbs(x + 25, y)
        Sleep(delayht)
      end
      y = y + step
      opCounter = opCounter + 1
      if opCounter >= 300 then
        Sleep(1)
        opCounter = 0
      end
    end
  end
end

function harvestHorizontal()
  if not running then
    return
  end
  set_activity("HARVEST")
  Overlay("`6Harvest Horizontal")
  local opCounter = 0
  for y = yBottom, yTop, -1 do
    if not running then
      return
    end
    for x = 0, 199 do
      if not running then
        return
      end
      local t = FastGetTile(x, y)
      if t and t.fg ~= 0 and t.extra and t.extra.progress == 1.0 then
        ensureAlignment(x, y)
        HarvestTileBothax(x, y)
        Sleep(delayht)
      end
      opCounter = opCounter + 1
      if opCounter >= 300 then
        Sleep(1)
        opCounter = 0
      end
    end
  end
end

function plantVertical()
  if not running then
    return
  end
  set_activity("PLANT")
  Overlay("`9Plant Vertical")
  local opCounter = 0
  for x = 0, 100, 3 do
    if not running then
      return
    end
    local y, step = (math.floor(x / 3) % 2 == 0) and yBottom or yTop, (math.floor(x / 3) % 2 == 0) and -1 or 1
    while y >= yTop and y <= yBottom do
      if not running then
        return
      end
      for i = 0, 2 do
        local xx = x + i
        if xx <= 200 then
          local tile = GetTile(xx, y)
          if tile and tile.fg == 0 then
            local under = GetTile(xx, y + 1)
            if under and under.fg == platID then
              if useMagSpot then
                while waitingForMagplant and running do
                  Sleep(50)
                end
              end
              placeAbs(seedID, xx, y)
              ThreadSleep(delaypt)
            end
          end
        end
      end
      y = y + step
      opCounter = opCounter + 1
      if opCounter >= 250 then
        Sleep(1)
        opCounter = 0
      end
    end
  end
end

function plantHorizontal()
  if not running then
    return
  end
  set_activity("PLANT")
  Overlay("`9Plant Horizontal")
  local opCounter = 0
  for y = yBottom, yTop, -1 do
    if not running then
      return
    end
    local startX, endX, stepX
    if ((yBottom - y) % 2 == 0) then
      startX, endX, stepX = 0, 200, 3
    else
      startX, endX, stepX = 200, 0, -3
    end
    for x = startX, endX, stepX do
      if not running then
        return
      end
      for i = 0, 2 do
        local xx = x + i * (stepX > 0 and 1 or -1)
        if xx >= 0 and xx <= 200 then
          local tile = GetTile(xx, y)
          if tile and tile.fg == 0 then
            local under = GetTile(xx, y + 1)
            if under and under.fg == platID then
              if useMagSpot then
                while waitingForMagplant and running do
                  Sleep(50)
                end
              end
              placeAbs(seedID, xx, y)
              ThreadSleep(delaypt)
            end
          end
        end
      end
      opCounter = opCounter + 1
      if opCounter >= 250 then
        Sleep(1)
        opCounter = 0
      end
    end
  end
end

function uws()
  if not running then
    return
  end
  set_activity("UWS")
  Overlay("`eUWS")
  FindPath(8, 10, 50)
  ThreadSleep(1000)
  local me = GetLocal()
  if not me then
    return
  end
  local px, py = math.floor(me.pos.x / 32), math.floor(me.pos.y / 32)
  local pkt = { type = 3, value = 5926, x = me.pos.x, y = me.pos.y, px = px, py = py }
  SendPacketRaw(false, pkt)
  ThreadSleep(1000)
  SendPacket(2, "action|dialog_return\ndialog_name|world_spray\n")
end

function uwsManual()
  if not running then
    return
  end
  set_activity("UWS", "Manual UWS")
  Overlay("`eUWS")
  FindPath(8, 10, 50)
  Sleep(1000)
  local me = GetLocal()
  if not me then
    return
  end
  local px, py = math.floor(me.pos.x / 32), math.floor(me.pos.y / 32)
  local pkt = { type = 3, value = 5926, x = me.pos.x, y = me.pos.y, px = px, py = py }
  SendPacketRaw(false, pkt)
  Sleep(1000)
  SendPacket(2, "action|dialog_return\ndialog_name|world_spray\n")
end

RunThread(function()
  while true do
    if requestUWS then
      requestUWS = false
      uwsManual()
    end
    Sleep(50)
  end
end)

function punchBothax(x, y)
  if not running then
    return
  end
  local t = GetTile(x, y)
  if not t or t.fg == 0 then
    return
  end
  local me = GetLocal()
  if not me then
    return
  end
  local pkt = { type = 3, value = 18, px = x, py = y, x = me.pos.x, y = me.pos.y }
  SendPacketRaw(false, pkt)
  Sleep(1)
  local states = { 4196896, 16779296 }
  for _, st in ipairs(states) do
    if not running then
      return
    end
    local hld = { type = 0, value = 0, px = x, py = y, x = me.pos.x, y = me.pos.y, state = st }
    SendPacketRaw(false, hld)
    Sleep(1)
  end
end

function HarvestTileBothax(x, y)
  if not running then
    return false
  end
  local t = GetTile(x, y)
  if not t or not (t.extra and t.extra.progress == 1.0) then
    return false
  end
  local lx, ly = localTilePos()
  if math.abs(lx - x) > 1 or math.abs(ly - y) > 1 then
    findPathBothax(x, y)
    WaitForArrive(x, y, ARRIVE_TO)
    Sleep(1)
  end
  local tries = 0
  while tries <= HARVEST_RETRY and running do
    punchBothax(x, y)
    Sleep(1)
    local nt = GetTile(x, y)
    if not nt or not (nt.extra and nt.extra.progress == 1.0) then
      return true
    end
    tries = tries + 1
    Sleep(1)
  end
  return false
end

function getTilesBothax()
  local results, opCounter = {}, 0
  for XS = SCAN_X_MAX, SCAN_X_MIN, -SCAN_STEP do
    local XE = XS - (SCAN_STEP - 1)
    if XE < SCAN_X_MIN then
      XE = SCAN_X_MIN
    end
    for px = SCAN_X_MIN, SCAN_X_MAX do
      for py = XE, XS do
        if not running then
          return results
        end
        local t = GetTile(px, py)
        if t and t.extra and t.extra.progress == 1.0 and (t.fg and (t.fg % 2 == 1)) then
          table.insert(results, { x = px, y = py })
        end
        opCounter = opCounter + 1
        if opCounter >= 250 then
          Sleep(1)
          opCounter = 0
        end
      end
    end
  end
  return results
end

local function allMagSpotsEmpty()
  if #MAGSpot == 0 then
    return false
  end
  for i = 1, #MAGSpot do
    if not MAGSpotEmpty[i] then
      return false
    end
  end
  return true
end

-- StartLoop: strict sequence per cycle
local function StartLoop()
  startTime = os.time()
  stopTime = nil
  ChangeValue("[C] Noclip", true)
  ghost()
  currentCount = 0
  stop_notified = false
  waitingForMagplant = false
  pendingMAGBind = nil
  if useMagSpot and #MAGSpot > 0 then
    -- bind initial spot using the safe bind function
    BindCurrentMAGSpot(currentMAGIndex)
  end

  threadLoop = RunThread(function()
    Overlay("`2PTHT Started! `9(" .. mode .. ")")
    set_activity("START")
    while running do
      -- 1) CHECK seed at start of cycle
      local readyTree = checkseed()

      -- If there are ready trees, HARVEST first (and re-harvest until stable or tries exhausted)
      if readyTree > 0 then
        Log("`9Ada `2" .. readyTree .. " `9pohon.. Harvest first!")
        if mode == "Vertical" then
          harvestVertical()
        else
          harvestHorizontal()
        end
        ThreadSleep(800)
        local pretries = 0
        readyTree = checkseed()
        while running and readyTree > 0 and pretries < 5 do
          Log("`9Masih ada `2" .. readyTree .. " `9pohon.. Re-harvest ke-" .. (pretries + 1))
          if mode == "Vertical" then
            harvestVertical()
          else
            harvestHorizontal()
          end
          ThreadSleep(500)
          pretries = pretries + 1
          readyTree = checkseed()
        end
      end

      -- 2) PLANT (this will respect waitingForMagplant inside plant* functions)
      if mode == "Vertical" then
        plantVertical()
      else
        plantHorizontal()
      end

      ThreadSleep(400)
      if not running then
        break
      end

      -- 3) UWS
      uws()
      ThreadSleep(2500)
      if not running then
        break
      end

      -- 4) HARVEST after UWS
      if mode == "Vertical" then
        harvestVertical()
      else
        harvestHorizontal()
      end

      ThreadSleep(400)
      if not running then
        break
      end

      -- 5) CHECK again and re-harvest if any leftover
      local tries = 0
      local sisa = checkseed()
      while running and sisa > 0 and tries < 5 do
        Log("`9Masih ada `2" .. sisa .. " `9pohon.. (Re-harvest ke-" .. (tries + 1) .. ")")
        if mode == "Vertical" then
          harvestVertical()
        else
          harvestHorizontal()
        end
        ThreadSleep(500)
        tries = tries + 1
        sisa = checkseed()
      end

      -- 6) End of one full PTHT cycle: increment counter, send progress, optionally auto-stop
      currentCount = currentCount + 1
      if useCount then
        Overlay("`9PTHT ke `2" .. currentCount .. "`w/`6" .. maxCount)
        if currentCount >= maxCount then
          Overlay("`4PTHT Selesai `2" .. currentCount .. "`w kali! `4Auto-Stop.")
          StopAll("Auto-stop: reached maxCount")
          break
        else
          pcall(function()
            set_activity("PROGRESS")
          end)
        end
      else
        Overlay("`9PTHT ke `2" .. currentCount .. "`w/`6" .. maxCount)
      end

      if useCount and currentCount >= maxCount then
        break
      end
    end

    StopAll("`2Done!")
    threadLoop = nil
  end)
end

AddHook("OnVariant", "PTHT_MAGEmptyHandler", function(v)
  if v[0] ~= "OnTalkBubble" then
    return
  end
  local msg = v[2] or ""
  if not (msg:find("MAGPLANT") and msg:find("empty")) then
    return
  end
  if not useMagSpot or #MAGSpot == 0 then
    return
  end
  if stop_notified then
    return
  end
  local idx = pendingMAGBind or currentMAGIndex
  if not idx or idx < 1 or idx > #MAGSpot then
    idx = currentMAGIndex
  end
  if MAGSpotEmpty[idx] then
    pendingMAGBind = nil
    return
  end
  -- mark current spot empty and pause planting loops
  MAGSpotEmpty[idx] = true
  pendingMAGBind = nil
  Log("`4MAGPLANT empty di spot #" .. tostring(idx) .. " (" .. tostring((MAGSpot[idx] and MAGSpot[idx].x) or "?") .. "," .. tostring((MAGSpot[idx] and MAGSpot[idx].y) or "?") .. ")")
  if allMagSpotsEmpty() then
    Log("`4All MAG Spots is empty! Script Stopped!.")
    StopAll("All MAG Spots empty")
  else
    -- pause planting loops by setting waitingForMagplant = true so plant* functions will wait
    waitingForMagplant = true
  end
end)

-- Rotating/bind loop: do NOT change currentMAGIndex/pendingMAGBind until actual bind time
RunThread(function()
  while true do
    if useMagSpot and waitingForMagplant then
      if #MAGSpot == 0 then
        Overlay("`4MAG Spot list kosong!")
        waitingForMagplant = false
      else
        local found = nil
        if #MAGSpot > 0 then
          local n = #MAGSpot
          for i = 1, n do
            local idx = ((currentMAGIndex - 1 + i) % n) + 1
            if not MAGSpotEmpty[idx] then
              found = idx
              break
            end
          end
        end
        if not found then
          if not stop_notified then
            Overlay("`4All MAG Spots is empty! Script Stopped!.")
            Log("`4All MAG Spots is empty! Script Stopped!.")
            StopAll("All MAG Spots empty")
          else
            waitingForMagplant = false
          end
        else
          -- selected next index but DON'T assign global vars yet
          local nextIndex = found

          -- wait a short delay before binding to avoid immediate/stale talkbubble being misinterpreted
          Log("`2MAG: waiting " .. tostring(mag_switch_delay_ms/1000) .. "s before binding MAG Spot #" .. tostring(nextIndex))
          ThreadSleep(mag_switch_delay_ms)

          if not running or stop_notified then
            waitingForMagplant = false
          else
            -- double-check spot wasn't marked empty during the delay
            if MAGSpotEmpty[nextIndex] then
              waitingForMagplant = false
              pendingMAGBind = nil
            else
              -- now perform bind using the chosen index (this sets currentMAGIndex/pendingMAGBind)
              BindCurrentMAGSpot(nextIndex)
              -- give 2 seconds after binding before resuming planting
              ThreadSleep(2000)
              waitingForMagplant = false
            end
          end
        end
      end
    end
    Sleep(300)
  end
end)

-- Main control thread (start/manual bind) - do not pre-assign currentMAGIndex before bind
RunThread(function()
  while true do
    if reqStartPTHT and not running then
      reqStartPTHT = false
      -- Before starting, validate that the configured platID exists in the world.
      -- If not present, do not start and notify the user.
      if not IsPlatIDPresent() then
        warn("`4Masukkan Plat ID yang sesuai!")
        Overlay("`4Masukkan Plat ID yang sesuai!")
      else
        running = true
        StartLoop()
      end
    end
    if reqBindMAG then
      reqBindMAG = false
      if MAGSpot[reqBindMAGIndex] then
        -- optional: mark as not-empty to avoid immediate skip; actual assignment happens inside BindCurrentMAGSpot
        MAGSpotEmpty[reqBindMAGIndex] = false
        Log("`2Manual bind requested: waiting " .. tostring(mag_switch_delay_ms/1000) .. "s before binding MAG Spot #" .. tostring(reqBindMAGIndex))
        ThreadSleep(mag_switch_delay_ms)

        BindCurrentMAGSpot(reqBindMAGIndex)
      end
    end
    Sleep(30)
  end
end)

RunThread(function()
  while true do
    if pending_stop_webhook and type(send_fixed_embed) == "function" then
      local p = pending_stop_webhook
      local user = wh_user_mention()
      local ok, err = send_fixed_embed(
        "PTHT Information!",
        "STOP",
        mode,
        user,
        currentMAGIndex,
        #MAGSpot,
        p.pc,
        p.pm,
        false,
        p.reason
      )
      if not ok then
        p.attempts = (p.attempts or 0) + 1
        if p.attempts >= 5 then
          pending_stop_webhook = nil
        else
          pending_stop_webhook = p
        end
      else
        pending_stop_webhook = nil
      end
    end
    Sleep(2000)
  end
end)

function imGui()
  ImGui.Begin("PTHT Controller @Lent")
  if ImGui.BeginTabBar("PTHT_TABS") then
    if ImGui.BeginTabItem("Config") then
      ImGui.TextColored(ImVec4(1, 1, 1, 1), "Script by")
      ImGui.SameLine()
      ImGui.TextColored(ImVec4(1, 0.7, 0, 1), "@Lent")
      ImGui.Separator()
      if running then
        ImGui.TextColored(ImVec4(0, 1, 0, 1), "Status : RUNNING")
      else
        ImGui.TextColored(ImVec4(1, 0, 0, 1), "Status : STOPPED")
      end
      ImGui.Separator()
      ImGui.Text("Settings :")
      local c1, new1 = ImGui.InputInt("Delay Plant (ms)", delaypt)
      if c1 then
        delaypt = new1
      end
      local c2, new2 = ImGui.InputInt("Delay Harvest (ms)", delayht)
      if c2 then
        delayht = new2
      end
      local c3, new3 = ImGui.InputInt("Y Top", yTop)
      if c3 then
        yTop = new3
      end
      local c4, new4 = ImGui.InputInt("Y Bottom", yBottom)
      if c4 then
        yBottom = new4
      end
      local c5, new5 = ImGui.InputInt("Seed ID", seedID)
      if c5 then
        seedID = new5
      end
      local c6, new6 = ImGui.InputInt("Plat ID Tanam", platID)
      if c6 then
        platID = new6
      end
      ImGui.Separator()
      ImGui.Text("Mode PTHT:")
      local selVertical = (mode == "Vertical")
      local selHorizontal = (mode == "Horizontal")
      if ImGui.RadioButton("Vertical", selVertical) then
        mode = "Vertical"
      end
      ImGui.SameLine()
      if ImGui.RadioButton("Horizontal", selHorizontal) then
        mode = "Horizontal"
      end
      ImGui.Spacing()
      local changedUse, newUse = ImGui.Checkbox("Use Counter?", useCount)
      if changedUse then
        useCount = newUse
        if useCount then
          currentCount = 0
        end
        pcall(function()
          resend_current_activity()
        end)
      end
      if useCount then
        local changedMax, newMax = ImGui.InputInt("Jumlah PTHT", maxCount)
        if changedMax then
          if newMax < 1 then
            newMax = 1
          end
          maxCount = newMax
        end
        ImGui.Text("Progress: " .. tostring(currentCount) .. " / " .. tostring(maxCount))
      end
      ImGui.Separator()
      local changedWebhook, newWebhook = ImGui.Checkbox("Enable Webhook", enableWebhook)
      if changedWebhook then
        enableWebhook = newWebhook
        if enableWebhook then
          Overlay("`2Webhook enabled")
        else
          Overlay("`4Webhook disabled")
        end
        pcall(function()
          resend_current_activity()
        end)
      end
      ImGui.Separator()
      if not running then
        if ImGui.Button("▶ Start PTHT", ImVec2(150, 30)) then
          reqStartPTHT = true
        end
      else
        if ImGui.Button("⏹ Stop PTHT", ImVec2(150, 30)) then
          StopAll()
        end
      end
      ImGui.Separator()
      ImGui.Text("Manual:")
      if ImGui.Button("UWS Now", ImVec2(150, 30)) then
        requestUWS = true
      end
      ImGui.Separator()
      if ImGui.Button("Test Webhook (Start)", ImVec2(150, 26)) then
        pcall(function()
          set_activity("START")
          resend_current_activity()
          Overlay("`2Webhook test sent (Start)")
        end)
      end
      ImGui.Separator()
      if ImGui.Button("Tutup Menu") then
        showMenu = false
      end
      ImGui.EndTabItem()
    end
    if ImGui.BeginTabItem("MAG Spot") then
      local chUse, nvUse = ImGui.Checkbox("Use MAG Spot", useMagSpot)
      if chUse then
        useMagSpot = nvUse
        waitingForMagplant = false
      end
      ImGui.Separator()
      ImGui.Text("MAG Spot:")
      local regionWidth = ImGui.GetContentRegionAvail().x
      ImGui.Spacing()
      ImGui.PushItemWidth(regionWidth / 4.5)
      ImGui.BeginGroup()
      ImGui.Text("MAGx")
      _, newMAGSpotX = ImGui.InputInt("##MAGX", newMAGSpotX)
      ImGui.EndGroup()
      ImGui.SameLine()
      ImGui.BeginGroup()
      ImGui.Text("MAGy")
      _, newMAGSpotY = ImGui.InputInt("##MAGY", newMAGSpotY)
      ImGui.EndGroup()
      ImGui.PopItemWidth()
      if ImGui.Button("➕ Add MAG Spot", ImVec2(150, 26)) then
        if #MAGSpot >= maxMAGSpots then
          warn("`4Max MAG Spot tercapai (" .. maxMAGSpots .. ")")
        else
          table.insert(MAGSpot, { x = newMAGSpotX, y = newMAGSpotY })
          table.insert(MAGSpotEmpty, false)
          Overlay("`2MAG Spot added: (" .. newMAGSpotX .. "," .. newMAGSpotY .. ")")
          if #MAGSpot == 1 then
            currentMAGIndex = 1
          end
        end
      end
      ImGui.Separator()
      ImGui.Text("List MAG Spots:")
      for i, s in ipairs(MAGSpot) do
        ImGui.Text(i .. ". (" .. s.x .. "," .. s.y .. ")")
        ImGui.SameLine()
        if ImGui.Button("Use##MAG" .. i, ImVec2(60, 22)) then
          reqBindMAG = true
          reqBindMAGIndex = i
        end
        ImGui.SameLine()
        if ImGui.Button("Hapus##MAG" .. i, ImVec2(70, 22)) then
          table.remove(MAGSpot, i)
          table.remove(MAGSpotEmpty, i)
          if currentMAGIndex > #MAGSpot then
            currentMAGIndex = #MAGSpot
            if currentMAGIndex < 1 then
              currentMAGIndex = 1
            end
          end
          Overlay("`4MAG Spot " .. i .. " deleted!")
        end
      end
      ImGui.EndTabItem()
    end
    ImGui.EndTabBar()
  end
  ImGui.End()
end

warn("`w[`2MADE by " .. credit .. "`w] `4DO NOT RESELL!!")
Sleep(2000)

AddHook("OnDraw", "ptht_ImGUI", function()
  if showMenu then
    imGui()
  end

end)
