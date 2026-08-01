-- Battle Move Info: matchup markers on the move-select TYPE box.
-- Classic Left/Right pages; wide shows details at once.
-- Gen 1 font has no +/=/<> tiles -- markers use ! . - x only.

local mod = ...

local MOD_ID = "BATTLE_MOVE_INFO"
local PAGE_COUNT = 3

local GLYPH_X = 0xF1
local GLYPH_BANG = 0xE7
local GLYPH_DASH = 0xE3
local GLYPH_DOT = 0xE8

local Font = require("src.render.Font")
local Strings = require("src.core.Strings")
local TypeChart = require("src.battle.TypeChart")
local BattleState = require("src.battle.BattleState")
local SummaryMenu = require("src.ui.SummaryMenu")

local function readOpt(key, default)
  local ok, got = pcall(mod.options.get, mod.options, key)
  if ok and got ~= nil then return got end
  return default
end

local function persist(key, value, game)
  local opts = game and game.save and game.save.options
  if opts then
    opts.modOptions = opts.modOptions or {}
    opts.modOptions[MOD_ID] = opts.modOptions[MOD_ID] or {}
    opts.modOptions[MOD_ID][key] = value
  end
  local loader = game and game.mods
  if loader then
    loader.modOptions = loader.modOptions or {}
    loader.modOptions[MOD_ID] = loader.modOptions[MOD_ID] or {}
    loader.modOptions[MOD_ID][key] = value
  end
  if game and game.writeOptions then pcall(game.writeOptions, game) end
end

local cache = {}

local function optBool(key, default)
  if cache[key] ~= nil then return cache[key] end
  cache[key] = readOpt(key, default) and true or false
  return cache[key]
end

local function enabled()
  return optBool("enabled", true)
end

mod.options:define({
  {
    key = "enabled", type = "toggle", label = "MOVE INFO",
    default = true,
    help = "Matchup markers and TYPE-box info pages on move select.",
  },
})

local page = 0
local lastPhase = nil
local lastFoeTypes = nil

local function resetPage()
  page = 0
end

-- TypeChart x10: 0 / 2 / 5 / 10 / 20 / 40 -> ! . - x
local function matchupCodes(mult)
  if mult <= 0 then return { GLYPH_X, GLYPH_X } end
  if mult <= 2 then return { GLYPH_DASH, GLYPH_DASH } end
  if mult <= 5 then return { GLYPH_DASH } end
  if mult <= 10 then return { GLYPH_DOT } end
  if mult <= 20 then return { GLYPH_BANG } end
  return { GLYPH_BANG, GLYPH_BANG }
end

local function drawMatchupMarker(mult, x, y)
  local codes = matchupCodes(mult)
  local pen = x
  for i = 1, #codes do
    Font.drawCode(codes[i], pen, y)
    pen = pen + Font.advanceOf(codes[i])
  end
  return pen - x
end

local function markerWidth(mult)
  return 8 * #matchupCodes(mult)
end

local function matchupWord(mult)
  if mult <= 0 then return "NO EFF X0" end
  if mult <= 2 then return "WEAK X1/4" end
  if mult <= 5 then return "WEAK X1/2" end
  if mult <= 10 then return "OK X1" end
  if mult <= 20 then return "SUPER X2" end
  return "SUPER X4"
end

local function shortMult(mult)
  if mult <= 0 then return "X0" end
  if mult <= 2 then return "X1/4" end
  if mult <= 5 then return "X1/2" end
  if mult <= 10 then return "X1" end
  if mult <= 20 then return "X2" end
  return "X4"
end

local function selectedMove(battle)
  local moves = battle.player and battle.player.curMoves
  if not moves then return nil, nil end
  local mv = moves[battle.moveIndex]
  if not mv then return nil, nil end
  local def = battle.data and battle.data.moves and battle.data.moves[mv.id]
  return mv, def
end

local function effectivenessOf(def, foeTypes)
  if not def or not def.type or not foeTypes then return 10 end
  local ok, mult = pcall(TypeChart.effectiveness, def.type, foeTypes)
  if not ok or type(mult) ~= "number" then return 10 end
  return mult
end

local function foeTypesOf(battle)
  local t = battle and battle.enemy and battle.enemy.curTypes
  if t and #t > 0 then
    lastFoeTypes = t
    return t
  end
  return lastFoeTypes
end

local function findBattle(game)
  local states = game and game.stack and game.stack.states
  if not states then return nil end
  for i = #states, 1, -1 do
    local s = states[i]
    if s and s.battle and s.battle.enemy and s.battle.player then
      return s.battle
    end
    if s and s.enemy and s.player and s.phase ~= nil then
      return s
    end
  end
  return nil
end

local function fitName(text, pixels, ellipsis)
  text = text or ""
  local spans = Font.split(text)
  local n = Font.spansFitting(spans, pixels)
  if n >= #spans then return text end
  if n <= 0 then return "" end
  local out = {}
  local keep = ellipsis and math.max(0, n - 1) or n
  for i = 1, keep do
    out[#out + 1] = text:sub(spans[i].from, spans[i].to)
  end
  if ellipsis then out[#out + 1] = "." end
  return table.concat(out)
end

local function restoreGfx()
  love.graphics.setColor(1, 1, 1, 1)
end

local function drawClassicMoveSelect(battle)
  Font.drawBox(0, 8, 11, 5)
  Font.drawBox(4, 12, 16, 6)
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.rectangle("fill", 32, 96, 8, 8)
  love.graphics.rectangle("fill", 80, 96, 8, 8)
  Font.drawCode(Font.BORDER.h, 32, 96)
  Font.drawCode(Font.BORDER.br, 80, 96)
  love.graphics.setColor(0, 0, 0, 1)

  for i, mv in ipairs(battle.player.curMoves) do
    local def = battle.data.moves[mv.id]
    Font.draw(def and def.name or tostring(mv.id), 48, 96 + i * 8)
  end
  Font.drawCode((battle.moveSwapIndex == battle.moveIndex) and 0xEC or 0xED,
                40, 96 + battle.moveIndex * 8)
  if battle.moveSwapIndex and battle.moveSwapIndex ~= battle.moveIndex then
    Font.drawCode(0xEC, 40, 96 + battle.moveSwapIndex * 8)
  end

  local mv, def = selectedMove(battle)
  if not mv then return end
  if battle.player.disabledSlot == battle.moveIndex then
    Font.draw(Strings("disabled!"), 8, 80)
    return
  end
  if not def then return end

  local mult = effectivenessOf(def, foeTypesOf(battle))
  local maxPP = def.pp + (mv.ppUps or 0) * math.floor(def.pp / 5)

  if page == 0 then
    local typeLabel = Strings("TYPE/")
    Font.draw(typeLabel, 8, 72)
    drawMatchupMarker(mult, 8 + Font.width(typeLabel), 72)
    Font.draw(def.type and TypeChart.displayName(def.type) or "", 16, 80)
    Font.draw(("%2d/%2d"):format(mv.pp, maxPP), 40, 88)
  elseif page == 1 then
    Font.draw("EFF/", 8, 72)
    Font.draw(matchupWord(mult), 16, 80)
    Font.draw(("%2d/%2d"):format(mv.pp, maxPP), 40, 88)
  else
    Font.draw("POW/", 8, 72)
    local pow = def.power or 0
    local acc = def.accuracy
    Font.draw((pow <= 0) and "--" or tostring(pow), 16, 80)
    Font.draw((acc == nil) and "ACC --" or ("ACC " .. tostring(acc)), 16, 88)
  end
end

local function drawWideDetails(battle)
  local mv, def = selectedMove(battle)
  Font.drawBox(28, 13, 10, 5)
  if not mv or not def then return end

  love.graphics.setColor(0, 0, 0, 1)
  if battle.player.disabledSlot == battle.moveIndex then
    Font.draw(Strings("disabled!"), 232, 120)
    return
  end

  local mult = effectivenessOf(def, foeTypesOf(battle))
  local maxPP = def.pp + (mv.ppUps or 0) * math.floor(def.pp / 5)
  Font.draw(("PP %2d/%2d"):format(mv.pp or 0, maxPP), 232, 112)

  local typeName = def.type and TypeChart.displayName(def.type) or ""
  local glyphW = markerWidth(mult)
  local fitted = fitName(typeName, math.max(8, 64 - glyphW - 8), true)
  local pen = 232 + Font.draw(fitted, 232, 120)
  drawMatchupMarker(mult, math.min(pen + 8, 232 + 64 - glyphW), 120)

  local pow = def.power or 0
  local acc = def.accuracy
  local powText = (pow <= 0) and "--" or tostring(pow)
  local accText = (acc == nil) and "--" or tostring(acc)
  local stats = powText .. "/" .. accText
  local withMult = shortMult(mult) .. " " .. stats
  local line = (Font.width(withMult) <= 64) and withMult or stats
  Font.draw(fitName(line, 64, false), 232, 128)
end

local prevDrawTextArea = BattleState.drawTextArea
function BattleState:drawTextArea()
  if enabled() and self.phase == "moveSelect" and not self:wideLayout() then
    foeTypesOf(self)
    drawClassicMoveSelect(self)
    restoreGfx()
    return
  end
  prevDrawTextArea(self)
  restoreGfx()
end

mod.hooks:wrap("battle.overlay", function(next, battle)
  next(battle)
  if not enabled() then return end
  if battle and battle.phase == "moveSelect" and battle:wideLayout() then
    foeTypesOf(battle)
    drawWideDetails(battle)
  end
  restoreGfx()
end)

local prevUpdate = BattleState.update
function BattleState:update(dt)
  if enabled() and self.phase == "moveSelect" and not self:wideLayout() then
    local input = self.game and self.game.input
    if input and input.pressed then
      if input.pressed.left then
        input.pressed.left = nil
        page = (page - 1) % PAGE_COUNT
      elseif input.pressed.right then
        input.pressed.right = nil
        page = (page + 1) % PAGE_COUNT
      end
    end
  end

  prevUpdate(self, dt)

  if enabled() and self.enemy and self.enemy.curTypes then
    lastFoeTypes = self.enemy.curTypes
  end

  if not enabled() then return end
  if self.phase ~= "moveSelect" then
    if lastPhase == "moveSelect" then resetPage() end
    lastPhase = self.phase
    return
  end
  lastPhase = self.phase
end

local prevSummaryDraw = SummaryMenu.draw
function SummaryMenu:draw()
  prevSummaryDraw(self)
  if not enabled() or self.page ~= 2 then return end

  local foe = lastFoeTypes
  local battle = findBattle(self.game)
  if battle then foe = foeTypesOf(battle) or foe end
  if not foe then return end

  local data = self.game.data
  local mon = self.mon
  if not (data and mon and mon.moves) then return end

  love.graphics.setColor(0, 0, 0, 1)
  for i = 1, 4 do
    local mv = mon.moves[i]
    if mv and mv.id then
      local mdef = data.moves[mv.id]
      if mdef and mdef.type then
        local mult = effectivenessOf(mdef, foe)
        local y = 72 + (i - 1) * 16
        local after = 16 + Font.width(mdef.name or "") + 8
        if after + markerWidth(mult) <= 88 then
          drawMatchupMarker(mult, after, y)
        else
          drawMatchupMarker(mult, 64, y + 8)
        end
      end
    end
  end
  restoreGfx()
end

mod.hooks:wrap("ui.options.rows", function(next, game, rows)
  rows = next(game, rows) or rows or {}
  rows[#rows + 1] = {
    id = MOD_ID .. ":enabled",
    label = "MOVE INFO",
    value = function() return optBool("enabled", true) and "ON" or "OFF" end,
    step = function(g)
      cache.enabled = not optBool("enabled", true)
      persist("enabled", cache.enabled, g)
      if not cache.enabled then resetPage() end
      return true
    end,
  }
  return rows
end)

mod.events:on("mod.options_changed", function(payload)
  if not payload or payload.mod ~= MOD_ID then return end
  cache[payload.key] = payload.value
  if payload.key == "enabled" and not payload.value then resetPage() end
end)

mod.events:on("battle.ended", function()
  resetPage()
  lastFoeTypes = nil
end)

mod.log:info("battle move info ready")
