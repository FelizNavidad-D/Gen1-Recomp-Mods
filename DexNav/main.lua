return function(mod)
  -- =====================================================================
  -- DexNav Grid UI Mod
  -- Matches the 0.40 Opacity & Canvas Clear logic of the Translucent Mod
  -- while keeping SGB Palettes active for colored icons!
  -- Interaction Locks cleared to prevent freezes on shoreline battles!
  -- Engine Simulator completely bypasses static data to guarantee 
  -- 100% version-accurate encounters via mock RNG rolls!
  -- Protected calls (pcall) and global fallbacks prevent Runtime crashes.
  -- Dynamic Bucket sizing fully supports custom encounter tables!
  -- *NEW* Transition Safeguards and pcall cleanup to prevent double-
  -- battle stack corruption and overworld freezes!
  -- *NEW* The search trigger button is remappable via OPTIONS >
  -- DEXNAV TRIGGER (default SELECT); the engine's CONTROLS menu remaps
  -- the physical key / pad button underneath it.
  -- =====================================================================

  local Font = require("src.render.Font")
  local Strings = require("src.core.Strings")
  local TextBox = require("src.render.TextBox")
  
  local Assets = require("src.render.Assets")
  local Sprites = require("src.pokemon.Sprites")
  local PartyMenu = require("src.ui.PartyMenu")
  local Map = require("src.world.Map")
  local BattleState = require("src.battle.BattleState")
  local Menu = require("src.ui.Menu")
  local Collision = require("src.world.Collision")
  local NPC = require("src.world.NPC")

  -- ---------------------------------------------------------------------
  -- Configurable search trigger (OPTIONS > DEXNAV TRIGGER)
  -- The trigger must be a Game Boy button name because the engine's
  -- Input:wasPressed only answers GB buttons; physical key / pad
  -- remapping underneath it is handled by the engine's CONTROLS menu.
  -- ---------------------------------------------------------------------
  local DEXNAV_BUTTONS = { "select", "start", "a", "b" }

  local function dexNavButton(game)
    local saved = game.save and game.save.options and game.save.options.dexNavButton
    for _, btn in ipairs(DEXNAV_BUTTONS) do
      if btn == saved then return btn end
    end
    return "select"
  end

  mod.exports = {
    dexNavButton = dexNavButton,
    DEXNAV_BUTTONS = DEXNAV_BUTTONS,
  }

  -- ---------------------------------------------------------------------
  -- PART 1: Icon Rendering Helper Functions
  -- ---------------------------------------------------------------------
  local iconCache = {}

  local function getObpIcon(path)
    if not (love.image and love.image.newImageData) then
      return love.graphics.newImage(Assets.resolve(path))
    end
    local id = Assets.imageData(path)
    id:mapPixel(function(_, _, r, _, _, a)
      local v = 0
      if r > 0.5 then v = 1 elseif r > 0.17 then v = 170 / 255 end
      return v, v, v, a
    end)
    return love.graphics.newImage(id)
  end

  local function drawBoxIcon(game, mon, x, y, isSelected, blinkCounter, isSeen)
    local icons = game.data.icons
    if not icons then return end
    local def = game.data.pokemon[mon.species]

    local entry = (icons.bySpecies and icons.bySpecies[mon.species]) or (def and def.icon)
    local name, path
    if type(entry) == "string" then
      name = entry; path = icons.icons and icons.icons[entry]
    elseif type(entry) == "table" then
      path = entry.image
    end
    if not path then
      name = def and def.dex and icons.byDex and icons.byDex[def.dex]
      path = name and icons.icons and icons.icons[name]
    end
    path = Sprites.iconPath(game.data, mon, path, { name = name })
    if not path then return end

    local key = name and (path .. "#obp") or path
    if iconCache[key] == nil then
      local ok, img
      if name then ok, img = pcall(getObpIcon, path) else ok, img = pcall(love.graphics.newImage, Assets.resolve(path)) end
      iconCache[key] = ok and img or false
    end

    local img = iconCache[key]
    if not img then return end

    local alt = false
    if isSelected then alt = math.floor(blinkCounter / 16) % 2 == 1 end

    if alt and (name == "BALL" or name == "HELIX") then
      y = y + 1; alt = false
    end

    local iw, ih = img:getDimensions()
    local frame = ih > 16 and PartyMenu.frameFor(name, alt, ih) or 0

    if isSeen then love.graphics.setColor(1, 1, 1, 1) else love.graphics.setColor(0, 0, 0, 1) end

    if PartyMenu.mirrorsIcon(name) then
      local half = love.graphics.newQuad(0, frame * 16, 8, 16, iw, ih)
      love.graphics.draw(img, half, x, y)
      love.graphics.draw(img, half, x + 16, y, 0, -1, 1)
    elseif ih > 16 then
      love.graphics.draw(img, love.graphics.newQuad(0, frame * 16, 16, 16, iw, ih), x, y)
    else
      love.graphics.draw(img, x, y)
    end
  end

  local function getIconPath(game, species)
    local icons = game.data.icons
    if not icons then return nil end
    local def = game.data.pokemon[species]
    local entry = (icons.bySpecies and icons.bySpecies[species]) or (def and def.icon)
    local name, path
    if type(entry) == "string" then
      name = entry; path = icons.icons and icons.icons[entry]
    elseif type(entry) == "table" then
      path = entry.image
    end
    if not path then
      name = def and def.dex and icons.byDex and icons.byDex[def.dex]
      path = name and icons.icons and icons.icons[name]
    end
    return Sprites.iconPath(game.data, {species=species}, path, { name = name })
  end

  -- ---------------------------------------------------------------------
  -- PART 2: Encounter Data & Map Scanner (The Engine Simulator)
  -- ---------------------------------------------------------------------
  local function checkMapCapabilities(game)
    local map = game.overworld and game.overworld.map
    if not map then return false, false end
    
    local hasGrass, hasWater = false, false
    local cellsX, cellsY = (map.def.width or 0) * 2, (map.def.height or 0) * 2
    
    for y = 0, cellsY - 1 do
      for x = 0, cellsX - 1 do
        if not hasGrass and map:isGrassCell(x, y) then hasGrass = true end
        if not hasWater and map:isWaterCell(x, y) then hasWater = true end
        if hasGrass and hasWater then break end
      end
      if hasGrass and hasWater then break end
    end
    
    local indoor = game.data.field.indoorEncounters
    local isIndoor = false
    if indoor and map.def.index and map.def.index >= indoor.firstIndoorMap and map.def.tileset ~= indoor.excludedTileset then
      isIndoor = true
    end
    
    return (hasGrass or isIndoor), hasWater
  end

  local function getMapEncounters(game)
    local mapId = game.overworld and game.overworld.map and game.overworld.map.id
    if not mapId then return {} end
    
    local canEncounterGrass, canEncounterWater = checkMapCapabilities(game)
    local uniqueSpecies = {}
    local list = {}

    local function addSlot(species, level, method)
      if species then
        if not uniqueSpecies[species] then
          local entry = { species = species, methods = {}, level = level or 5 }
          uniqueSpecies[species] = entry
          table.insert(list, entry)
        end
        uniqueSpecies[species].methods[method] = true
        if level and level > uniqueSpecies[species].level then
          uniqueSpecies[species].level = level
        end
      end
    end

    local okRuntime, Runtime = pcall(require, "src.core.Runtime")
    if not okRuntime then Runtime = _G.Runtime end

    local okEncounter, Encounter = pcall(require, "src.world.Encounter")
    
    local encDef = game.data.encounters and game.data.encounters[mapId]

    if encDef and okEncounter and Encounter then
      local globalBuckets = (game.data.constants and game.data.constants.encounterBuckets) or { 51, 102, 141, 166, 191, 216, 229, 242, 253, 256 }

      local function simulateTerrain(terrainType, method)
        local sourceData = encDef[terrainType]
        if not sourceData or (sourceData.rate or 0) == 0 then return end
        
        local activeBuckets = sourceData.buckets or globalBuckets
        
        -- Force the engine to roll exactly one of every active rarity bucket!
        for i = 1, #activeBuckets do
          local targetVal = (i == 1) and 0 or activeBuckets[i-1]
          local callCount = 0
          
          -- Create a mock RNG to bypass the rate check and guarantee the specific slot
          local fakeRng = function(min, max)
            callCount = callCount + 1
            if callCount == 1 then return 0 end 
            return targetVal 
          end
          
          -- The engine expects water encounters to be passed under the "grass" key!
          local mockDef = { grass = sourceData }
          local ctx = { mapId = mapId, terrain = terrainType, rng = fakeRng }
          
          local baseRoll
          if Runtime and Runtime.wantsHook and Runtime.wantsHook("encounter.roll") then
             baseRoll = Runtime.call("encounter.roll", function(ed, c) return Encounter.roll(ed, c.rng) end, mockDef, ctx)
          else
             baseRoll = Encounter.roll(mockDef, fakeRng)
          end
          
          if baseRoll then
             local enc = baseRoll
             -- Run the simulated roll through the version-modification hooks!
             if Runtime and Runtime.wantsHook and Runtime.wantsHook("encounter.species") then
                enc = Runtime.call("encounter.species", function(e) return e end, enc, ctx)
             end
             if enc then
                addSlot(enc.species, enc.level, method)
             end
          end
        end
      end

      if canEncounterGrass then simulateTerrain("grass", "GRASS") end
      if canEncounterWater then simulateTerrain("water", "SURF") end
    end

    -- Static parsing for Fishing (fishing rarely differs by version, so static reading is safe here)
    if canEncounterWater then
      local field, fishing = game.data.field or {}, (game.data.field and game.data.field.fishing) or {}
      for rodName, rodDef in pairs(fishing) do
        local methodStr = "FISHING"
        if rodName == "oldRod" then methodStr = "OLD ROD" elseif rodName == "goodRod" then methodStr = "GOOD ROD" elseif rodName == "superRod" then methodStr = "SUPER ROD" end
        
        local function addStatic(slot)
           if slot and slot.species then addSlot(slot.species, slot.level, methodStr) end
        end
        local function addStaticSlots(slots)
           if type(slots) == "table" then for _, s in ipairs(slots) do addStatic(s) end end
        end

        if rodDef.always then addStatic(rodDef.always) end
        if rodDef.pool then addStaticSlots(rodDef.pool) end
        
        if rodDef.perMap and field[rodDef.perMap] then
          local mapGroup = field[rodDef.perMap][mapId]
          if mapGroup and type(mapGroup) == "table" then
            
            -- Aggressive string extraction for fishing pools just in case
            local ver = game.version or (game.save and game.save.version) or game.data.version or game.data.gameVersion
            if ver and type(ver) == "string" then
               local vL = string.lower(ver)
               local vU = string.upper(ver)
               local vCaps = vL:gsub("^%l", string.upper)
               local verGroup = mapGroup[vL] or mapGroup[vU] or mapGroup[vCaps]
               if verGroup then mapGroup = verGroup end
            end

            if mapGroup.species then addStatic(mapGroup) 
            elseif mapGroup.slots then addStaticSlots(mapGroup.slots)
            else
              for _, item in pairs(mapGroup) do
                if type(item) == "table" then
                  if item.species then addStatic(item) else addStaticSlots(item.slots or item) end
                end
              end
            end
          end
        end
      end
    end
    
    return list, mapId
  end

  local function getHabitatType(game, species)
    local encs = getMapEncounters(game)
    local hasWater, hasGrass = false, false
    for _, enc in ipairs(encs) do
      if enc.species == species then
        if enc.methods["SURF"] or enc.methods["OLD ROD"] or enc.methods["GOOD ROD"] or enc.methods["SUPER ROD"] or enc.methods["FISHING"] then
          hasWater = true
        end
        if enc.methods["GRASS"] then
          hasGrass = true
        end
        break
      end
    end
    if not hasWater and not hasGrass then hasGrass = true end
    return hasWater, hasGrass
  end

  local function isValidTile(game, map, tx, ty, hasWater, hasGrass)
    local indoor = game.data.field.indoorEncounters
    local isIndoor = indoor and map.def.index and map.def.index >= indoor.firstIndoorMap and map.def.tileset ~= indoor.excludedTileset
    
    local isWaterTile = map:isWaterCell(tx, ty)
    local isGrassTile = map:isGrassCell(tx, ty)
    
    if hasWater and not hasGrass then
      return isWaterTile
    elseif hasGrass and not hasWater then
      return isGrassTile or (isIndoor and not isWaterTile)
    else
      return isGrassTile or isWaterTile or (isIndoor and not isWaterTile)
    end
  end

  -- ---------------------------------------------------------------------
  -- PART 3: Native Target Spawner (The Hybrid Renderer)
  -- ---------------------------------------------------------------------
  local function getPlayerCell(Game)
    local ow = Game.overworld
    if ow and ow.player and ow.player.cellX and ow.player.cellY then
      return ow.player.cellX, ow.player.cellY
    end
    return Game.save.x or 0, Game.save.y or 0
  end

  local function safeDespawnDexNavTarget(Game)
    local ow = Game.overworld
    local targetId = Game._dexNavTargetId
    if not targetId or not ow then return end
    
    if ow.interacting and ow.interacting.id == targetId then
      ow.interacting = nil
    end
    
    if ow.removeRuntimeObject then
      pcall(function() ow:removeRuntimeObject(targetId, "DexNav") end)
    end
    Game._dexNavTargetId = nil
    Game._dexNavTargetMapId = nil
  end

  local function spawnDexNavEncounter(Game, species, level)
    local ow = Game.overworld
    if not ow or not ow.map then return end
    
    if Game._dexNavTargetId then safeDespawnDexNavTarget(Game) end
    
    local px, py = getPlayerCell(Game)
    local candidates = {}
    local hasW, hasG = getHabitatType(Game, species)
    
    for dy = -6, 6 do
      for dx = -6, 6 do
        local tx, ty = px + dx, py + dy
        
        if isValidTile(Game, ow.map, tx, ty, hasW, hasG) and (math.abs(dx) > 1 or math.abs(dy) > 1) then
          local canExistHere = ow.map:isWalkableCell(tx, ty) or ow.map:isWaterCell(tx, ty)
          
          if canExistHere and not Collision.occupied(ow.entities, tx, ty) then
            table.insert(candidates, {x = tx, y = ty})
          end
        end
      end
    end
    
    if #candidates > 0 then
      local chosen = candidates[math.random(#candidates)]
      
      local objDef = {
        sprite = "SPRITE_POKE_BALL", 
        x = chosen.x,
        y = chosen.y
      }
      
      local npcId = ow:addRuntimeObject(ow.map.id, objDef, "DexNav")
      local iconPath = getIconPath(Game, species)
      
      for _, n in ipairs(ow.npcs) do
        if n.id == npcId then
          n.dexNavSpecies = species
          n.dexNavLevel = level
          
          n.dexNavHasWater = hasW
          n.dexNavHasGrass = hasG
          
          if iconPath then
            n.sprite.def = {
              image = iconPath,
              frames = 2,
              walker = true,
              trueColor = true
            }
            n.sprite.resolveImage = function()
               local key = iconPath .. "#obp"
               if iconCache[key] == nil then
                   local ok, img = pcall(getObpIcon, iconPath)
                   iconCache[key] = ok and img or false
               end
               return iconCache[key] or nil
            end
          end
          
          n.draw = function(n_self, camX, camY)
            n_self.animCounter = (n_self.animCounter or 0) + 1
            local bob = (n_self.moving or n_self.marching) and (math.floor((n_self.progress or 0) / 4) % 2 == 0 and 1 or 0) or 0
            local screenX = n_self.px - camX
            local screenY = n_self.py - camY - 4 - bob
            
            drawBoxIcon(Game, {species=n_self.dexNavSpecies}, screenX, screenY, true, n_self.animCounter, true)
          end
          
          local orig_pose = n.pose
          n.pose = function(self)
            local sprite, pos_x, pos_y = orig_pose(self)
            self.animCounter = (self.animCounter or 0) + 1
            local phase = math.floor(self.animCounter / 20) % 2
            return sprite, pos_x, pos_y, "down", phase, false
          end
          
          break
        end
      end
      
      Game._dexNavTargetId = npcId
      Game._dexNavTargetMapId = ow.map.id 
      
      require("src.core.Sound").playCry(Game.data, species)
    else
      require("src.core.Sound").play(Game.data, "Denied")
      Game.stack:push(TextBox.new(Game, Strings("No suitable habitat\nnearby for this!\f")))
    end
  end

  local function startDexNavBattle(Game, ow, targetNpc)
    local species = targetNpc.dexNavSpecies
    local level = targetNpc.dexNavLevel
    
    targetNpc.frozen = true
    
    if ow.interacting and ow.interacting.id == targetNpc.id then
      ow.interacting = nil
    end
    
    require("src.core.Sound").play(Game.data, "Collision")
    
    local battle = BattleState.newWild(Game, species, level)
    local ghost = Map.ghostBattles(ow.map.def)
    if ghost and not (ghost.unlessItem and Game.save.inventory[ghost.unlessItem]) then
      battle:makeGhost()
    end
    if Game.save.safari and Map.inRegion(ow.map.def, "SAFARI", "SAFARI_ZONE") then
      battle:makeSafari(Game.save.safari)
    end
    
    battle.onFinish = function(result) 
      pcall(function() safeDespawnDexNavTarget(Game) end)
      if ow.afterBattle then ow:afterBattle(result, battle) end
    end
    
    ow:pushBattle(battle)
  end

  -- ---------------------------------------------------------------------
  -- PART 4: Custom DexNav Grid Class
  -- ---------------------------------------------------------------------
  local DexNavGrid = {}
  DexNavGrid.__index = DexNavGrid

  function DexNavGrid.new(game, encounterData, mapId)
    local self = setmetatable({}, DexNavGrid)
    self.game = game
    self.boxData = encounterData
    self.mapId = mapId
    self.index = 1
    self.blink = 0
    self.isOpaque = false 
    return self
  end

  function DexNavGrid:update(dt)
    self.blink = (self.blink + 1) % 320
    local input = self.game.input
    
    if input:wasPressed("b") then
      require("src.core.Sound").play(self.game.data, "Press_AB")
      self.game.stack:pop()
      return
    end
    
    if input:wasPressed("a") then
      local mon = self.boxData[self.index]
      local dex = self.game.save.pokedex
      
      if mon and dex and dex.seen[mon.species] then
        require("src.core.Sound").play(self.game.data, "Press_AB")
        
        local subMenu = Menu.new(self.game, {
          { label = "SEARCH", onSelect = function()
              while self.game.stack:top() and not self.game.stack:top().isOverworld do
                self.game.stack:pop()
              end
              spawnDexNavEncounter(self.game, mon.species, mon.level)
          end },
          { label = "REGISTER", onSelect = function()
              self.game.save.dexNavReg = { species = mon.species, level = mon.level }
              local def = self.game.data.pokemon[mon.species]
              require("src.core.Sound").play(self.game.data, "Save")
              self.game.stack:pop() 
              self.game.stack:push(TextBox.new(self.game, Strings("%s registered\nto %s!\f", def.name, string.upper(dexNavButton(self.game)))))
          end },
          { label = "DEX", keepOpen = true, onSelect = function()
              require("src.ui.Screens").push(self.game, "DexEntryMenu", mon.species)
          end },
          { label = "CANCEL" }
        }, { tx = 11, ty = 6, tw = 9, th = 10, noSound = true })
        
        subMenu.boxData = true 
        self.game.stack:push(subMenu)
      else
        require("src.core.Sound").play(self.game.data, "Collision")
      end
      return
    end

    if input:wasPressed("up") then
      self.index = self.index - 5
      if self.index < 1 then self.index = self.index + 20 end
    elseif input:wasPressed("down") then
      self.index = self.index + 5
      if self.index > 20 then self.index = self.index - 20 end
    elseif input:wasPressed("left") then
      if self.index % 5 == 1 then self.index = self.index + 4 else self.index = self.index - 1 end
    elseif input:wasPressed("right") then
      if self.index % 5 == 0 then self.index = self.index - 4 else self.index = self.index + 1 end
    end
  end

  function DexNavGrid:draw()
    local target = love.graphics.getCanvas()
    if target then
      love.graphics.clear(0, 0, 0, 0)
    end
    
    local cr, cg, cb, ca = love.graphics.getColor()
    love.graphics.setColor(1, 1, 1, 0.40)
    love.graphics.rectangle("fill", 0, 0, 160, 144)
    love.graphics.setColor(cr, cg, cb, ca)
    
    local prev_translucent = Font.__translucent_active
    Font.__translucent_active = true

    Font.drawBox(0, 0, 20, 18)
    local dex = self.game.save.pokedex or { seen = {}, owned = {} }

    for i = 1, 20 do
      local col = ((i - 1) % 5)
      local row = math.floor((i - 1) / 5)
      local x = col * 32
      local y = row * 24
      local mon = self.boxData[i]

      if i == self.index then
        love.graphics.setScissor(x, y, 32, 8)
        Font.drawBox(col * 4, row * 3, 4, 3)
        love.graphics.setScissor(x, y + 16, 32, 8)
        Font.drawBox(col * 4, row * 3, 4, 3)
        love.graphics.setScissor(x, y + 8, 8, 8)
        Font.drawBox(col * 4, row * 3, 4, 3)
        love.graphics.setScissor(x + 24, y + 8, 8, 8)
        Font.drawBox(col * 4, row * 3, 4, 3)
        love.graphics.setScissor()
      end

      if mon then
        local isSeen = dex.seen[mon.species]
        drawBoxIcon(self.game, mon, x + 8, y + 4, i == self.index, self.blink, isSeen)
      else
        love.graphics.setColor(0.6, 0.6, 0.6, 1)
        love.graphics.rectangle("fill", x + 12, y + 11, 8, 2)
      end
    end

    local mapName = self.mapId:gsub("_", " ")
    if Font.width(mapName) > 144 then
      while string.len(mapName) > 0 and Font.width(mapName .. "...") > 144 do mapName = string.sub(mapName, 1, -2) end
      mapName = mapName .. "..."
    end
    
    local mapNameWidth = Font.width(mapName)
    local mapNameX = math.floor((160 - mapNameWidth) / 2)
    
    love.graphics.setScissor(0, 96, mapNameX - 4, 8)
    Font.drawBox(0, 12, 20, 6)
    love.graphics.setScissor(mapNameX + mapNameWidth + 4, 96, 160, 8)
    Font.drawBox(0, 12, 20, 6)
    love.graphics.setScissor()
    
    love.graphics.setColor(0, 0, 0, 1)
    Font.draw(mapName, mapNameX, 96)
    
    local hoveredMon = self.boxData[self.index]
    
    if hoveredMon then
      local def = self.game.data.pokemon[hoveredMon.species]
      local isSeen = dex.seen[hoveredMon.species]
      local isOwned = dex.owned[hoveredMon.species]
      
      if isSeen then
        Font.draw(Strings("%s", def.name), 8, 112)
        if isOwned then Font.draw(Strings("CAUGHT"), 8, 128) else Font.draw(Strings("UNCAUGHT"), 8, 128) end
      else
        Font.draw(Strings("?????"), 8, 112)
        Font.draw(Strings("UNKNOWN"), 8, 128)
      end

      local m = hoveredMon.methods
      local lines = {}
      if m["GRASS"] then table.insert(lines, "GRASS") end
      if m["SURF"] then table.insert(lines, "SURF") end
      
      local rods = {}
      if m["OLD ROD"] then table.insert(rods, "O") end
      if m["GOOD ROD"] then table.insert(rods, "G") end
      if m["SUPER ROD"] then table.insert(rods, "S") end
      if #rods > 0 then table.insert(lines, table.concat(rods, "/") .. " ROD") end

      local yM = 112
      for i, line in ipairs(lines) do
        if i <= 2 then Font.draw(line, 152 - Font.width(line), yM); yM = yM + 16 end
      end
    else
      Font.draw(Strings("Empty Slot"), 8, 112)
    end
    love.graphics.setColor(1, 1, 1, 1)
    
    Font.__translucent_active = prev_translucent
  end

  mod.content.screens:register("DEXNAV_GRID_VIEW", {
    new = function(game, encounterData, mapId) return DexNavGrid.new(game, encounterData, mapId) end
  })

  mod.hooks:wrap("ui.options.rows", function(nextFn, game, rows)
    local out = nextFn(game, rows)
    if type(out) ~= "table" then return out end

    out[#out + 1] = {
      id = "dexNavTrigger",
      label = "DEXNAV TRIGGER",
      value = function(g) return string.upper(dexNavButton(g)) end,
      step = function(g, dir)
        local cur = dexNavButton(g)
        for i, btn in ipairs(DEXNAV_BUTTONS) do
          if btn == cur then
            g.save.options.dexNavButton = DEXNAV_BUTTONS[((i - 1 + dir) % #DEXNAV_BUTTONS) + 1]
            return true
          end
        end
        return false
      end,
    }
    return out
  end)

  mod.hooks:wrap("ui.start_menu.items", function(nextFn, game, items)
    local out = nextFn(game, items)
    if type(out) ~= "table" then return out end
    
    return mod.ui.insertBefore(out, "SAVE", {
      label = "DEXNAV",
      onSelect = function()
        local encs, mapId = getMapEncounters(game)
        if #encs == 0 then
          require("src.core.Sound").play(game.data, "Denied")
          game.stack:push(TextBox.new(game, Strings("There are no wild\nPOKéMON here!\f")))
        else
          require("src.core.Sound").play(game.data, "Press_AB")
          mod.ui.push(game, "DEXNAV_GRID_VIEW", encs, mapId)
        end
      end,
    })
  end)

  local okOW, OverworldController = pcall(require, "src.world.OverworldController")
  if okOW and OverworldController then
  
    local handlers = rawget(OverworldController, "__qolSelectHandlers")
    if not handlers then
      handlers = {}
      local origHandle = OverworldController.handleInput
      OverworldController.handleInput = function(self, ...)
        for _, handler in pairs(OverworldController.__qolSelectHandlers) do
          if handler(self) then return end
        end
        return origHandle(self, ...)
      end
      OverworldController.__qolSelectHandlers = handlers
    end
    
    handlers["dexnav_select"] = function(ow)
      local Game = require("src.core.Game")
      if Game.input:wasPressed(dexNavButton(Game)) and Game.save.dexNavReg then
        if not Game._dexNavTargetId and Game.stack:top() == ow then
          local reg = Game.save.dexNavReg
          
          local encs = getMapEncounters(Game)
          local isValid = false
          for _, enc in ipairs(encs) do
            if enc.species == reg.species then
              isValid = true
              break
            end
          end
          
          if isValid then
            spawnDexNavEncounter(Game, reg.species, reg.level)
          else
            require("src.core.Sound").play(Game.data, "Denied")
            Game.stack:push(TextBox.new(Game, Strings("This POKéMON isn't\nin this area!\f")))
          end
          return true 
        end
      end
      return false
    end

    if not OverworldController.__orig_update_dexnav then
      OverworldController.__orig_update_dexnav = OverworldController.update
    end
    OverworldController.update = function(self, dt)
      OverworldController.__orig_update_dexnav(self, dt)
      local Game = require("src.core.Game")
      
      if Game._dexNavTargetMapId and Game._dexNavTargetMapId ~= self.map.id then
         pcall(function() safeDespawnDexNavTarget(Game) end)
         return
      end
      
      local targetId = Game._dexNavTargetId
      if targetId then
        local targetNpc
        for _, n in ipairs(self.npcs) do
          if n.id == targetId then targetNpc = n; break end
        end
        
        if not targetNpc then
          pcall(function() safeDespawnDexNavTarget(Game) end)
          return
        end

        if self.player.bumpFrames and self.player.bumpFrames > 0 then
          local tx, ty = Collision.target(self.player.cellX, self.player.cellY, self.player.facing)
          local npc = self:npcAtCell(tx, ty)
          if npc and npc.id == targetId then
            self.player.bumpFrames = nil 
            -- THE FIX: Adding `not self.transitioning` ensures we don't push a DexNav battle during a wild battle fade-out!
            if Game.stack:top() == self and not npc.frozen and not self.engaging and not self.runner:isRunning() and not self.transitioning then
              startDexNavBattle(Game, self, npc)
            end
          end
        end

        if not targetNpc.moving and not targetNpc.frozen and not self.transitioning then
          targetNpc.dexNavTimer = (targetNpc.dexNavTimer or 0) + 1
          if targetNpc.dexNavTimer > 80 then
            targetNpc.dexNavTimer = 0
            local dirs = {"up", "down", "left", "right"}
            local d = dirs[math.random(4)]
            local nx, ny = Collision.target(targetNpc.cellX, targetNpc.cellY, d)
            
            if isValidTile(Game, self.map, nx, ny, targetNpc.dexNavHasWater, targetNpc.dexNavHasGrass) and (self.map:isWalkableCell(nx, ny) or self.map:isWaterCell(nx, ny)) and not Collision.occupied(self.entities, nx, ny, targetNpc) then
              self:scriptMove(targetNpc, d, 1)
            else
              self:marchInPlace(targetNpc)
            end
          end
        end
      end
    end
    
    mod.events:on("world.interacted", function(event)
      local Game = require("src.core.Game")
      if event.kind == "npc" and event.target and event.target.id == Game._dexNavTargetId then
        local ow = Game.overworld
        -- THE FIX: Strict `not ow.transitioning` lock on the event listener to prevent double-battle stack corruption!
        if ow and Game.stack:top() == ow and not ow.engaging and not ow.runner:isRunning() and not ow.transitioning then
           startDexNavBattle(Game, ow, event.target)
        end
      end
    end)

    if not OverworldController.__orig_afterBattle_dexnav then
      OverworldController.__orig_afterBattle_dexnav = OverworldController.afterBattle
    end
    OverworldController.afterBattle = function(self, result, battle)
      local Game = require("src.core.Game")
      if Game._dexNavTargetId then
        if Game.save.defeatedTrainers then
           Game.save.defeatedTrainers[Game._dexNavTargetId] = nil
        end
        if Game.save.itemsTaken then
           Game.save.itemsTaken[Game._dexNavTargetId] = nil 
        end
        
        -- THE FIX: Wrap the despawner in a pcall. Even if the removal crashes, orig_afterBattle will ALWAYS execute and unfreeze you!
        pcall(function() safeDespawnDexNavTarget(Game) end)
      end
      
      if OverworldController.__orig_afterBattle_dexnav then
         OverworldController.__orig_afterBattle_dexnav(self, result, battle)
      end
    end
    
  end
  
  mod.log:info("DexNav Grid UI Mod: Transition Safeguards Locked In!")
end