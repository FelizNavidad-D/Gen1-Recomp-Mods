return function(mod)
  -- =====================================================================
  -- DexNav Grid UI Mod (Full Color & 3D Voxel World Repair)
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

  -- Detects if Unique Menu Icons is in GBC RED or UNIQUE COLORS mode
local function isTrueColorIcon(game, species)
  local ok, PartyMenuCheck = pcall(require, "src.ui.PartyMenu")
  if ok and PartyMenuCheck and PartyMenuCheck._uniqueMenuIconsTrueColorWrapped then
    return true
  end
  -- PokePCFollowers also patches icons with literal-color art; treat
  -- those as trueColor too so the grid (and Voxel mode) don't run them
  -- through the OBP0 bake meant for 4-shade grayscale contract art.
  local pcfHandle = mod.find and mod.find("PokePCFollowers_VoxelMerge")
  if pcfHandle then
    return true
  end
  return false
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

    local trueColor = isTrueColorIcon(game, mon.species)
    local key = trueColor and (path .. "#raw") or (name and (path .. "#obp") or path)

    if iconCache[key] == nil then
      local ok, img
      if trueColor then
        ok, img = pcall(love.graphics.newImage, Assets.resolve(path))
      elseif name then
        ok, img = pcall(getObpIcon, path)
      else
        ok, img = pcall(love.graphics.newImage, Assets.resolve(path))
      end
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

    -- Mark screen rect for PaletteFX if trueColor is enabled
    if isSeen and trueColor then
      local okFX, PaletteFX = pcall(require, "src.render.PaletteFX")
      if okFX and PaletteFX and PaletteFX.markTrueColor then
        PaletteFX.markTrueColor(x, y, 16, 16)
      end
    end
  end

  local function getIconPath(game, species)
    local icons = game.data.icons
    if not icons then return nil, nil end
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
    return Sprites.iconPath(game.data, {species=species}, path, { name = name }), name
  end

  -- ---------------------------------------------------------------------
  -- PART 2: Encounter Data & Map Scanner (The Engine Simulator)
  -- ---------------------------------------------------------------------
  local function checkMapCapabilities(game, mapId)
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

    local field = game.data.field or {}
    local fishing = field.fishing or {}
    for _, rodDef in pairs(fishing) do
      if type(rodDef) == "table" and rodDef.perMap and field[rodDef.perMap] and field[rodDef.perMap][mapId] then
        hasWater = true
        break
      end
    end
    
    return (hasGrass or isIndoor), hasWater
  end

  local function getMapEncounters(game)
    local mapId = game.overworld and game.overworld.map and game.overworld.map.id
    if not mapId then return {} end
    
    local canEncounterGrass, canEncounterWater = checkMapCapabilities(game, mapId)
    local uniqueSpecies = {}
    local list = {}

    local function addSlot(species, level, method, rate)
      if species then
        if not uniqueSpecies[species] then
          local entry = { species = species, methods = {}, level = level or 5 }
          uniqueSpecies[species] = entry
          table.insert(list, entry)
        end
        uniqueSpecies[species].methods[method] = (uniqueSpecies[species].methods[method] or 0) + (rate or 100)
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
        
        for i = 1, #activeBuckets do
          local prevVal = (i == 1) and 0 or activeBuckets[i-1]
          local weight = activeBuckets[i] - prevVal
          local ratePct = (weight / 256) * 100
          
          local callCount = 0
          local fakeRng = function(min, max)
            callCount = callCount + 1
            if callCount == 1 then return 0 end 
            return prevVal 
          end
          
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
             if Runtime and Runtime.wantsHook and Runtime.wantsHook("encounter.species") then
                enc = Runtime.call("encounter.species", function(e) return e end, enc, ctx)
             end
             if enc then
                addSlot(enc.species, enc.level, method, ratePct)
             end
          end
        end
      end

      if canEncounterGrass then simulateTerrain("grass", "GRASS") end
      if canEncounterWater then simulateTerrain("water", "SURF") end
    end

    if canEncounterWater then
      local field, fishing = game.data.field or {}, (game.data.field and game.data.field.fishing) or {}
      for rodName, rodDef in pairs(fishing) do
        
        local methodStr = "SUPER" 
        local rNameUpper = string.upper(tostring(rodName))
        
        if rNameUpper:find("OLD") then methodStr = "OLD" 
        elseif rNameUpper:find("GOOD") then methodStr = "GOOD" 
        elseif rNameUpper:find("SUPER") then methodStr = "SUPER" end
        
        local function addStatic(slot, defaultRate)
           if slot and slot.species then 
               addSlot(slot.species, slot.level, methodStr, slot.rate or defaultRate or 100) 
           end
        end
        local function addStaticSlots(slots)
           if type(slots) == "table" and #slots > 0 then 
               local defaultR = 100 / #slots
               for _, s in ipairs(slots) do addStatic(s, defaultR) end 
           end
        end

        if rodDef.always then addStatic(rodDef.always, 100) end
        if rodDef.pool then addStaticSlots(rodDef.pool) end
        
        if rodDef.perMap and field[rodDef.perMap] then
          local mapGroup = field[rodDef.perMap][mapId]
          if mapGroup and type(mapGroup) == "table" then
            local ver = game.version or (game.save and game.save.version) or game.data.version or game.data.gameVersion
            if ver and type(ver) == "string" then
               local vL, vU = string.lower(ver), string.upper(ver)
               local vCaps = vL:gsub("^%l", string.upper)
               local verGroup = mapGroup[vL] or mapGroup[vU] or mapGroup[vCaps]
               if verGroup then mapGroup = verGroup end
            end

            if mapGroup.species then 
                addStatic(mapGroup, 100) 
            elseif mapGroup.slots then 
                addStaticSlots(mapGroup.slots)
            else
              local speciesCount = 0
              for _, item in pairs(mapGroup) do
                  if type(item) == "table" and item.species then speciesCount = speciesCount + 1 end
              end
              
              local splitRate = speciesCount > 0 and (100 / speciesCount) or 100
              
              for _, item in pairs(mapGroup) do
                if type(item) == "table" then
                  if item.species then 
                      addStatic(item, splitRate) 
                  else 
                      addStaticSlots(item.slots or item) 
                  end
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
        if enc.methods["SURF"] or enc.methods["OLD"] or enc.methods["GOOD"] or enc.methods["SUPER"] then
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
    
    if hasWater and not hasGrass then return isWaterTile
    elseif hasGrass and not hasWater then return isGrassTile or (isIndoor and not isWaterTile)
    else return isGrassTile or isWaterTile or (isIndoor and not isWaterTile) end
  end

  -- ---------------------------------------------------------------------
  -- PART 3: Native Target Spawner (The Hybrid Renderer)
  -- ---------------------------------------------------------------------
  local function getPlayerCell(Game)
    local ow = Game.overworld
    if ow and ow.player and ow.player.cellX and ow.player.cellY then return ow.player.cellX, ow.player.cellY end
    return Game.save.x or 0, Game.save.y or 0
  end

  local function safeDespawnDexNavTarget(Game)
    local ow = Game.overworld
    local targetId = Game._dexNavTargetId
    if not targetId or not ow then return end
    if ow.interacting and ow.interacting.id == targetId then ow.interacting = nil end
    if ow.removeRuntimeObject then pcall(function() ow:removeRuntimeObject(targetId, "DexNav") end) end
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
      local objDef = { sprite = "SPRITE_POKE_BALL", x = chosen.x, y = chosen.y, movement = "WALK" }
      local npcId = ow:addRuntimeObject(ow.map.id, objDef, "DexNav")
      local iconPath, iconName = getIconPath(Game, species)

      -- PokePCFollowers compatibility: if installed, use its real animated
      -- overworld walker sheet (6 frames, true color) instead of stretching
      -- the 16x32 menu icon into a fake 2-frame walker.
      local pcfHandle = mod.find and mod.find("PokePCFollowers_VoxelMerge")
      local pcfAssetPath = pcfHandle and pcfHandle.exports and pcfHandle.exports.assetPath
      local pcfSpritePath = pcfAssetPath and pcfAssetPath(species)

      for _, n in ipairs(ow.npcs) do
        if n.id == npcId then
          n.dexNavSpecies = species
          n.dexNavLevel = level
          n.dexNavHasWater = hasW
          n.dexNavHasGrass = hasG

          if pcfSpritePath then
            -- Full rebuild, not just n.sprite.def = {...}: self.frames
            -- (the per-pose quads) are only built once, inside
            -- SpriteRenderer.new(), from the image/frame-count present
            -- at construction time. n.sprite currently still holds the
            -- placeholder SPRITE_POKE_BALL's quads; just swapping .def
            -- leaves those stale and mismatched against the new 6-frame
            -- sheet, breaking the WALK/STAND animation. PokePCFollowers
            -- does the same full rebuild in syncLiveFollowerDef whenever
            -- the species/image changes -- this mirrors that.
            local SpriteRenderer = require("src.render.SpriteRenderer")
            local def = { image = pcfSpritePath, frames = 6, walker = true, trueColor = true }
            n.sprite = SpriteRenderer.new(def, n.id)
          elseif iconPath then
            local isCustomTrueColor = isTrueColorIcon(Game, species)

            n.sprite.def = { image = iconPath, frames = 2, walker = true, trueColor = isCustomTrueColor }
            n.sprite.resolveImage = function()
               local key = isCustomTrueColor and (iconPath .. "#raw") or (iconName and (iconPath .. "#obp") or iconPath)
               if iconCache[key] == nil then
                 -- ... (rest of your existing code here, unchanged)
                   local ok, img
                   if isCustomTrueColor then
                       ok, img = pcall(love.graphics.newImage, Assets.resolve(iconPath))
                   elseif iconName then
                       ok, img = pcall(getObpIcon, iconPath)
                   else
                       ok, img = pcall(love.graphics.newImage, Assets.resolve(iconPath))
                   end
                   iconCache[key] = ok and img or false
               end
               return iconCache[key] or nil
            end
          end
          
local hasWalkerSprite = (pcfSpritePath ~= nil)

n.draw = function(n_self, camX, camY)
  if hasWalkerSprite and n_self.sprite then
    -- caminho normal de qualquer NPC: pose() já calcula facing/phase certos
    local sprite, px, py, facing, phase, flip = n_self:pose()
    sprite:draw(px, py, camX, camY, facing, phase, flip)
  else
    -- sem PokePCFollowers: sem arte direcional, mantém o ícone estático de bounce
    n_self.animCounter = (n_self.animCounter or 0) + 1
    local bob = (n_self.moving or n_self.marching) and (math.floor((n_self.progress or 0) / 4) % 2 == 0 and 1 or 0) or 0
    local screenX = n_self.px - camX
    local screenY = n_self.py - camY - 4 - bob
    drawBoxIcon(Game, {species=n_self.dexNavSpecies}, screenX, screenY, true, n_self.animCounter, true)
  end
end
          
          local orig_pose = n.pose
          n.pose = function(self)
            local sprite, pos_x, pos_y = orig_pose(self)
            self.animCounter = (self.animCounter or 0) + 1
            local phase = math.floor(self.animCounter / 20) % 2
            -- was hardcoded to "down", which forced every frame to draw the
            -- default-facing pose regardless of the direction scriptMove()
            -- set on self.facing; report the NPC's real facing instead.
            return sprite, pos_x, pos_y, self.facing or "down", phase, false
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
    if ow.interacting and ow.interacting.id == targetNpc.id then ow.interacting = nil end
    require("src.core.Sound").play(Game.data, "Collision")
    
    local battle = BattleState.newWild(Game, species, level)
    local ghost = Map.ghostBattles(ow.map.def)
    if ghost and not (ghost.unlessItem and Game.save.inventory[ghost.unlessItem]) then battle:makeGhost() end
    if Game.save.safari and Map.inRegion(ow.map.def, "SAFARI", "SAFARI_ZONE") then battle:makeSafari(Game.save.safari) end
    
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
              while self.game.stack:top() and not self.game.stack:top().isOverworld do self.game.stack:pop() end
              spawnDexNavEncounter(self.game, mon.species, mon.level)
          end },
          { label = "REGISTER", onSelect = function()
              self.game.save.dexNavReg = { species = mon.species, level = mon.level }
              local def = self.game.data.pokemon[mon.species]
              require("src.core.Sound").play(self.game.data, "Save")
              self.game.stack:pop() 
              self.game.stack:push(TextBox.new(self.game, Strings("%s registered\nto SELECT!\f", def.name)))
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
    if target then love.graphics.clear(0, 0, 0, 0) end
    
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
    
    local hoveredMon = self.boxData[self.index]
    
    love.graphics.setColor(0, 0, 0, 1)
    Font.draw(mapName, mapNameX, 96)
    
    if hoveredMon then
      local def = self.game.data.pokemon[hoveredMon.species]
      local isSeen = dex.seen[hoveredMon.species]
      local isOwned = dex.owned[hoveredMon.species]
      
      if isSeen then
        Font.draw(Strings("%s", def.name), 8, 112)
        if isOwned then
          local icons = self.game.data.icons
          local ballPath = icons and icons.icons and (icons.icons["BALL"] or icons.icons["ball"])
          if ballPath then
              local key = ballPath .. "#obp"
              if iconCache[key] == nil then
                  local ok, img = pcall(getObpIcon, ballPath)
                  iconCache[key] = ok and img or false
              end
              local img = iconCache[key]
              if img then
                  love.graphics.setColor(1, 1, 1, 1)
                  local iw, ih = img:getDimensions()
                  local frame = ih > 16 and PartyMenu.frameFor("BALL", false, ih) or 0
                  if ih > 16 then
                    love.graphics.draw(img, love.graphics.newQuad(0, frame * 16, 16, 16, iw, ih), 8, 124)
                  else
                    love.graphics.draw(img, 8, 124)
                  end
                  love.graphics.setColor(0, 0, 0, 1)
              end
          end
        end
      else
        Font.draw(Strings("?????"), 8, 112)
      end

      local m = hoveredMon.methods
      local displayData = {}
      
      local function formatRate(r)
          local val = math.floor(r + 0.5)
          if val > 100 then val = 100 end 
          if val == 0 and r > 0 then return "<1%" end
          return val .. "%"
      end

      if m["GRASS"] then table.insert(displayData, { method = "Grass", rate = formatRate(m["GRASS"]) }) end
      if m["SURF"]  then table.insert(displayData, { method = "Surf", rate = formatRate(m["SURF"]) }) end
      if m["OLD"]   then table.insert(displayData, { method = "Old", rate = formatRate(m["OLD"]) }) end
      if m["GOOD"]  then table.insert(displayData, { method = "Good", rate = formatRate(m["GOOD"]) }) end
      if m["SUPER"] then table.insert(displayData, { method = "Super", rate = formatRate(m["SUPER"]) }) end

      if #displayData > 0 then
        local currentIndex = 1
        if #displayData > 1 then
          local cycleFrames = 100 
          currentIndex = (math.floor(self.blink / cycleFrames) % #displayData) + 1
        end
        
        local activeData = displayData[currentIndex]
        
        Font.draw(activeData.method, 152 - Font.width(activeData.method), 112)
        Font.draw(activeData.rate, 152 - Font.width(activeData.rate), 128)
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
      if Game.input:wasPressed("select") and Game.save.dexNavReg then
        if not Game._dexNavTargetId and Game.stack:top() == ow then
          local reg = Game.save.dexNavReg
          local encs = getMapEncounters(Game)
          local isValid = false
          for _, enc in ipairs(encs) do
            if enc.species == reg.species then isValid = true break end
          end
          if isValid then spawnDexNavEncounter(Game, reg.species, reg.level)
          else
            require("src.core.Sound").play(Game.data, "Denied")
            Game.stack:push(TextBox.new(Game, Strings("This POKéMON isn't\nin this area!\f")))
          end
          return true 
        end
      end
      return false
    end

    if not OverworldController.__orig_update_dexnav then OverworldController.__orig_update_dexnav = OverworldController.update end
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
        if not targetNpc then pcall(function() safeDespawnDexNavTarget(Game) end); return end

        if self.player.bumpFrames and self.player.bumpFrames > 0 then
          local tx, ty = Collision.target(self.player.cellX, self.player.cellY, self.player.facing)
          local npc = self:npcAtCell(tx, ty)
          if npc and npc.id == targetId then
            self.player.bumpFrames = nil 
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
        if ow and Game.stack:top() == ow and not ow.engaging and not ow.runner:isRunning() and not ow.transitioning then
           startDexNavBattle(Game, ow, event.target)
        end
      end
    end)

    if not OverworldController.__orig_afterBattle_dexnav then OverworldController.__orig_afterBattle_dexnav = OverworldController.afterBattle end
    OverworldController.afterBattle = function(self, result, battle)
      local Game = require("src.core.Game")
      if Game._dexNavTargetId then
        if Game.save.defeatedTrainers then Game.save.defeatedTrainers[Game._dexNavTargetId] = nil end
        if Game.save.itemsTaken then Game.save.itemsTaken[Game._dexNavTargetId] = nil end
        pcall(function() safeDespawnDexNavTarget(Game) end)
      end
      if OverworldController.__orig_afterBattle_dexnav then OverworldController.__orig_afterBattle_dexnav(self, result, battle) end
    end
  end
  mod.log:info("DexNav Grid UI Mod: Unique Menu Icons Enabled!")
end