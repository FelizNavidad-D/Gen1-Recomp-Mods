return function(mod)
  mod.log:info("Dynamic Level Scaling, Randomizer & Modular Difficulty Loaded")

  -- =====================================================================
  -- GLOBAL SETTINGS & OPTIONS MENU INTEGRATION
  -- =====================================================================
  local C = _G.__DYNAMIC_SCALING or {}
  _G.__DYNAMIC_SCALING = C
  C.randomize = C.randomize or "off"
  C.difficulty = C.difficulty or "normal"

  if mod.options and mod.options.define then
    mod.options:define({
      {
        key = "randomize", type = "choice", label = "Trainer Randomizer",
        choices = {
          { "Off (Vanilla Teams)", "off" },
          { "Chaos (Any Pokemon)", "chaos" },
          { "Themed (Class-based)", "themed" }
        },
        default = "off"
      },
      {
        key = "difficulty", type = "choice", label = "Difficulty Mode",
        choices = {
          { "Off (Vanilla)", "off" },
          { "Normal (+2 Lvs, 6 Mons)", "normal" },
          { "Medium (+5 Lvs, 6 Mons, Max DVs)", "medium" },
          { "Hard (+10 Lvs, 6 Mons, Max EVs)", "hard" }
        },
        default = "normal"
      }
    })
  end

  local function refreshOptions()
    if mod.options and mod.options.get then
      pcall(function() C.randomize = mod.options:get("randomize") or "off" end)
      pcall(function() C.difficulty = mod.options:get("difficulty") or "normal" end)
    end
  end
  refreshOptions()

  mod.events:on("mod.options_changed", function(p)
    if p and p.mod == mod.id then
      if p.key == "randomize" then C.randomize = p.value end
      if p.key == "difficulty" then C.difficulty = p.value end
    end
  end)

  local ROW_RNDM = { { "off", "OFF" }, { "chaos", "CHAOS" }, { "themed", "THEMED" } }
  local ROW_DIFF = { { "off", "OFF" }, { "normal", "NORMAL (+2)" }, { "medium", "MEDIUM (+5)" }, { "hard", "HARD (+10)" } }

  local function getModeIndex(val, list)
    for i, m in ipairs(list) do if m[1] == val then return i end end
    return 1
  end

  local function persistOpt(game, key, val)
    local id = mod.id
    local opts = game and game.save and game.save.options
    if opts then
      opts.modOptions = opts.modOptions or {}
      opts.modOptions[id] = opts.modOptions[id] or {}
      opts.modOptions[id][key] = val
    end
    local loader = game and game.mods
    if loader then
      loader.modOptions = loader.modOptions or {}
      loader.modOptions[id] = loader.modOptions[id] or {}
      loader.modOptions[id][key] = val
    end
    if game and game.writeOptions then pcall(game.writeOptions, game) end
  end

  mod.hooks:wrap("ui.options.rows", function(nextFn, game, rows)
    local out = nextFn(game, rows)
    if type(out) ~= "table" then return out end
    
    out[#out + 1] = {
      id = mod.id .. ":randomize",
      label = "TRAINERS",
      value = function() return ROW_RNDM[getModeIndex(C.randomize, ROW_RNDM)][2] end,
      step = function(g, dir) 
        local n = #ROW_RNDM
        local i = ((getModeIndex(C.randomize, ROW_RNDM) - 1 + dir) % n + n) % n + 1
        C.randomize = ROW_RNDM[i][1]
        persistOpt(g, "randomize", C.randomize)
        return true
      end,
    }

    out[#out + 1] = {
      id = mod.id .. ":difficulty",
      label = "DIFFICULTY",
      value = function() return ROW_DIFF[getModeIndex(C.difficulty, ROW_DIFF)][2] end,
      step = function(g, dir) 
        local n = #ROW_DIFF
        local i = ((getModeIndex(C.difficulty, ROW_DIFF) - 1 + dir) % n + n) % n + 1
        C.difficulty = ROW_DIFF[i][1]
        persistOpt(g, "difficulty", C.difficulty)
        return true
      end,
    }
    return out
  end)

  -- =====================================================================
  -- DICTIONARIES: THEMES, CLASSES & ULTIMATE MOVES
  -- =====================================================================
  local ULTIMATE_MOVES = {
    ARCANINE   = { "EXTREMESPEED", "FIRE_BLAST" },
    NINETALES  = { "FLAMETHROWER", "FLAME_WHEEL" },
    RAICHU     = { "THUNDERBOLT", "ZAP_CANNON", "IRON_TAIL" },
    CLEFABLE   = { "RETURN", "SHADOW_BALL" },
    WIGGLYTUFF = { "RETURN", "DYNAMICPUNCH" },
    NIDOKING   = { "SLUDGE_BOMB", "EARTHQUAKE", "MEGAHORN" },
    NIDOQUEEN  = { "SLUDGE_BOMB", "EARTHQUAKE", "SHADOW_BALL" },
    EXEGGUTOR  = { "GIGA_DRAIN", "SLUDGE_BOMB", "PSYCHIC" }, 
    STARMIE    = { "HYDRO_PUMP", "ICE_BEAM", "PSYCHIC" },
    POLIWRATH  = { "HYDRO_PUMP", "DYNAMICPUNCH", "EARTHQUAKE" },
    VILEPLUME  = { "SLUDGE_BOMB", "SOLARBEAM", "GIGA_DRAIN" },
    VICTREEBEL = { "SLUDGE_BOMB", "RAZOR_LEAF", "RETURN" },
    CLOYSTER   = { "SURF", "ICE_BEAM", "SPIKES" },
    VAPOREON   = { "HYDRO_PUMP", "ICE_BEAM", "SHADOW_BALL" },
    JOLTEON    = { "THUNDERBOLT", "SHADOW_BALL", "RETURN" },
    FLAREON    = { "FIRE_BLAST", "SHADOW_BALL", "RETURN" },

    BELLOSSOM  = { "SOLARBEAM", "GIGA_DRAIN", "RETURN" },
    SUNFLORA   = { "SOLARBEAM", "GIGA_DRAIN", "RETURN" },

    POLITOED   = { "HYDRO_PUMP", "EARTHQUAKE", "RETURN" },
    SLOWKING   = { "PSYCHIC", "SURF", "SHADOW_BALL" },
    STEELIX    = { "EARTHQUAKE", "IRON_TAIL", "ROCK_SLIDE" },
    SCIZOR     = { "STEEL_WING", "RETURN", "FURY_CUTTER" },
    KINGDRA    = { "HYDRO_PUMP", "DRAGONBREATH", "ICE_BEAM" },
    PORYGON2   = { "RETURN", "TRI_ATTACK", "ZAP_CANNON" },
    ESPEON     = { "PSYCHIC", "SHADOW_BALL", "ZAP_CANNON" },
    UMBREON    = { "FAINT_ATTACK", "SHADOW_BALL", "RETURN" }
  }

  local THEME_POOLS = {
    BUG_FOREST = {
      "CATERPIE","WEEDLE","ODDISH","PARAS","VENONAT","BELLSPROUT","SCYTHER","PINSIR","TANGELA","BULBASAUR","EXEGGCUTE",
      "CHIKORITA","LEDYBA","SPINARAK","HOPPIP","SUNKERN","YANMA","PINECO","HERACROSS","CELEBI"
    },
    WATER_ICE = {
      "SQUIRTLE","PSYDUCK","POLIWAG","TENTACOOL","SLOWPOKE","SEEL","SHELLDER","KRABBY","HORSEA","GOLDEEN","STARYU","MAGIKARP","LAPRAS","OMANYTE","KABUTO","ARTICUNO",
      "TOTODILE","CHINCHOU","MARILL","WOOPER","QWILFISH","CORSOLA","REMORAID","MANTINE","SWINUB","DELIBIRD","SUICUNE"
    },
    ROCK_FIGHT = {
      "MANKEY","MACHOP","GEODUDE","ONIX","CUBONE","HITMONLEE","HITMONCHAN","RHYHORN","AERODACTYL",
      "SUDOWOODO","GLIGAR","SCIZOR","SHUCKLE","SKARMORY","PHANPY","TYROGUE","HITMONTOP","LARVITAR","PUPITAR","TYRANITAR"
    },
    FIRE_POISON = {
      "CHARMANDER","VULPIX","GROWLITHE","PONYTA","MAGMAR","MOLTRES","EKANS","NIDORAN_F","NIDORAN_M","ZUBAT","GRIMER","KOFFING",
      "CYNDAQUIL","HOUNDOUR","HOUNDOOM","SLUGMA","MAGCARGO","MURKROW","SNEASEL","ENTEI","HO_OH","CROBAT"
    },
    ELEC_PSY_GHOST = {
      "PIKACHU","VOLTORB","ELECTABUZZ","ZAPDOS","MAGNEMITE","ABRA","DROWZEE","MR_MIME","JYNX","MEWTWO","MEW","GASTLY",
      "PICHU","MAREEP","FLAAFFY","AMPHAROS","ELEKID","RAIKOU","NATU","XATU","ESPEON","UNOWN","WOBBUFFET","GIRAFARIG","MISDREAVUS","LUGIA"
    },
    NORMAL_BIRD = {
      "PIDGEY","RATTATA","SPEAROW","CLEFAIRY","JIGGLYPUFF","MEOWTH","FARFETCHD","DODUO","LICKITUNG","CHANSEY","KANGASKHAN","TAUROS","DITTO","EEVEE","PORYGON","SNORLAX",
      "SENTRET","HOOTHOOT","CLEFFA","IGGLYBUFF","TOGEPI","AIPOM","DUNSPARCE","SNUBBULL","TEDDIURSA","PORYGON2","STANTLER","MILTANK","BLISSEY"
    },
    DRAGON_MASTERS = {
      "DRATINI","DRAGONAIR","DRAGONITE","KINGDRA","AERODACTYL","CHARIZARD","GYARADOS","LAPRAS"
    },
    CHAMPION_LEGENDS = {
      "VENUSAUR", "CHARIZARD", "BLASTOISE", "MEGANIUM", "TYPHLOSION", "FERALIGATR", 
      "JOLTEON", "VAPOREON", "FLAREON", "ESPEON", "UMBREON",
      "DRAGONITE", "TYRANITAR", "SNORLAX", "AERODACTYL", "GYARADOS", "LAPRAS", "KINGDRA",
      "ARTICUNO", "ZAPDOS", "MOLTRES", "MEWTWO", "MEW",
      "RAIKOU", "ENTEI", "SUICUNE", "LUGIA", "HO_OH", "CELEBI"
    }
  }

  local CLASS_THEMES = {
    BUGSY = "BUG_FOREST", ERIKA = "BUG_FOREST",
    BUG_CATCHER = "BUG_FOREST", PICNICKER = "BUG_FOREST", CAMPER = "BUG_FOREST",
    JR_TRAINER_F = "BUG_FOREST", 

    MISTY = "WATER_ICE", PRYCE = "WATER_ICE", LORELEI = "WATER_ICE",
    SAILOR = "WATER_ICE", FISHER = "WATER_ICE", FISHERMAN = "WATER_ICE", 
    SWIMMER = "WATER_ICE", SWIMMERM = "WATER_ICE", SWIMMERF = "WATER_ICE", 
    BOARDER = "WATER_ICE", SKIER = "WATER_ICE", BEAUTY = "WATER_ICE",

    BROCK = "ROCK_FIGHT", BRUNO = "ROCK_FIGHT", CHUCK = "ROCK_FIGHT", JASMINE = "ROCK_FIGHT",
    HIKER = "ROCK_FIGHT", BLACKBELT = "ROCK_FIGHT", BLACKBELT_T = "ROCK_FIGHT", 
    CUE_BALL = "ROCK_FIGHT", JR_TRAINER_M = "ROCK_FIGHT", GIOVANNI = "ROCK_FIGHT",

    BLAINE = "FIRE_POISON", KOGA = "FIRE_POISON", JANINE = "FIRE_POISON", KAREN = "FIRE_POISON",
    POKEMANIAC = "FIRE_POISON", SUPER_NERD = "FIRE_POISON", BIKER = "FIRE_POISON", 
    BURGLAR = "FIRE_POISON", FIREBREATHER = "FIRE_POISON", JUGGLER = "FIRE_POISON", TAMER = "FIRE_POISON",
    GRUNTM = "FIRE_POISON", GRUNTF = "FIRE_POISON", EXECUTIVEM = "FIRE_POISON", EXECUTIVEF = "FIRE_POISON",

    LT_SURGE = "ELEC_PSY_GHOST", SABRINA = "ELEC_PSY_GHOST", MORTY = "ELEC_PSY_GHOST", WILL = "ELEC_PSY_GHOST", AGATHA = "ELEC_PSY_GHOST",
    SCIENTIST = "ELEC_PSY_GHOST", GUITARIST = "ELEC_PSY_GHOST", ROCKER = "ELEC_PSY_GHOST",
    PSYCHIC_TR = "ELEC_PSY_GHOST", PSYCHIC_T = "ELEC_PSY_GHOST", CHANNELER = "ELEC_PSY_GHOST",
    SAGE = "ELEC_PSY_GHOST", MEDIUM = "ELEC_PSY_GHOST",

    FALKNER = "NORMAL_BIRD", WHITNEY = "NORMAL_BIRD",
    YOUNGSTER = "NORMAL_BIRD", SCHOOLBOY = "NORMAL_BIRD", BIRD_KEEPER = "NORMAL_BIRD", LASS = "NORMAL_BIRD",
    COOLTRAINERM = "NORMAL_BIRD", COOLTRAINERF = "NORMAL_BIRD", GENTLEMAN = "NORMAL_BIRD",
    TEACHER = "NORMAL_BIRD", POKEFANM = "NORMAL_BIRD", POKEFANF = "NORMAL_BIRD", KIMONO_GIRL = "NORMAL_BIRD",
    TWINS = "NORMAL_BIRD", OFFICER = "NORMAL_BIRD",

    CLAIR = "DRAGON_MASTERS", LANCE = "DRAGON_MASTERS",

    CHAMPION = "CHAMPION_LEGENDS", RED = "CHAMPION_LEGENDS", BLUE = "CHAMPION_LEGENDS", 
    RIVAL1 = "CHAMPION_LEGENDS", RIVAL2 = "CHAMPION_LEGENDS", RIVAL3 = "CHAMPION_LEGENDS", 
    CAL = "CHAMPION_LEGENDS", POKEMON_PROF = "CHAMPION_LEGENDS"
  }

  -- =====================================================================
  -- ENGINE LOGIC (EVOLUTION, CACHES, AND LEVEL CAPS)
  -- =====================================================================
  local fullPokedexCache = nil
  local parentMapCache = nil

  local function getDynamicCap(save)
      if save and save.events then
          if save.events["EVENT_BEAT_ELITE_4"] or 
             save.events["EVENT_BEAT_ELITE_4_RM"] or 
             save.events["EVENT_BEAT_CHAMPION_RIVAL"] then
              return 255
          end
      end

      local cap = 15
      local badges = { 
          "BOULDERBADGE", "CASCADEBADGE", "THUNDERBADGE", "RAINBOWBADGE", 
          "SOULBADGE", "MARSHBADGE", "VOLCANOBADGE", "EARTHBADGE",
          "ZEPHYRBADGE", "HIVEBADGE", "PLAINBADGE", "FOGBADGE",
          "STORMBADGE", "MINERALBADGE", "GLACIERBADGE", "RISINGBADGE"
      }
      for _, badge in ipairs(badges) do
          if save and save.inventory and save.inventory[badge] then 
              cap = cap + 7 
          end
      end

      if save and save.events then
          if save.events["EVENT_CLEARED_ROCKET_HIDEOUT"] then cap = cap + 5 end
          if save.events["EVENT_CLEARED_RADIO_TOWER"] then cap = cap + 5 end
          if save.events["EVENT_BEAT_ROCKET_HIDEOUT_GIOVANNI"] then cap = cap + 5 end
          if save.events["EVENT_BEAT_SILPH_CO_GIOVANNI"] then cap = cap + 5 end
      end

      return cap
  end

  local function getBaseSpecies(data, species)
      if not parentMapCache then
          parentMapCache = {}
          for key, def in pairs(data.pokemon) do
              if def.evolutions then
                  for _, evo in ipairs(def.evolutions) do
                      local req = 30
                      if evo.method == "LEVEL" then req = evo.level or 30 end
                      parentMapCache[evo.species] = { parent = key, reqLevel = req }
                  end
              end
          end
      end
      
      local curr = species
      while parentMapCache[curr] do
          curr = parentMapCache[curr].parent
      end
      return curr
  end

  local function getEvolvedSpecies(data, species, currentLevel)
    local def = data.pokemon[species]
    if not def or not def.evolutions then return species end
    for _, evo in ipairs(def.evolutions) do
      local req = 30 
      if evo.method == "LEVEL" then req = evo.level or 30 end
      
      if currentLevel >= req then 
          return getEvolvedSpecies(data, evo.species, currentLevel) 
      end
    end
    return species
  end

  -- =====================================================================
  -- INJECTION: PRE-INSTANTIATION OVERRIDES
  -- =====================================================================
  
  mod.hooks:wrap("trainer.party", function(origFn, classId, memberId, partyDef)
      local baseDef = origFn(classId, memberId, partyDef) or partyDef
      if C.difficulty == "off" and C.randomize == "off" then return baseDef end
      
      local data = mod.__activeData
      local save = mod.__activeSave
      local playerParty = mod.__activeParty
      if not data then return baseDef end
      
      -- Detect which engine is currently running the hook
      local isGen2 = false
      local Gen2Mon = nil
      pcall(function() 
          Gen2Mon = require("src.battle.gen2.Mon") 
          isGen2 = true
      end)
      
      local offset = 0
      if C.difficulty == "normal" then offset = 2 
      elseif C.difficulty == "medium" then offset = 5
      elseif C.difficulty == "hard" then offset = 10 end
      
      local totalLevel, count = 0, 0
      if playerParty then
          for _, mon in ipairs(playerParty) do
              totalLevel = totalLevel + mon.level
              count = count + 1
          end
      end
      local avgLevel = count > 0 and math.floor(totalLevel / count) or 5
      local cap = getDynamicCap(save)
      local baseLevel = math.min(avgLevel, cap)
      
      local origMax = 0
      for _, slot in ipairs(baseDef) do
          if slot.level and slot.level > origMax then origMax = slot.level end
      end
      
      if not fullPokedexCache then
          fullPokedexCache = {}
          for key, def in pairs(data.pokemon) do
              if type(def.dex) == "number" and def.dex >= 1 and def.dex <= 251 then
                  table.insert(fullPokedexCache, key)
              end
          end
      end
      
      local activePool = fullPokedexCache
      if C.randomize == "themed" and classId then
          -- Safely cast classId to string to prevent integer :gsub() crashes
          local cleanClassId = tostring(classId):gsub("^OPP_", "")
          local themeName = CLASS_THEMES[cleanClassId] or CLASS_THEMES[tostring(classId)]
          if themeName and THEME_POOLS[themeName] then
              activePool = THEME_POOLS[themeName]
          end
      end
      
      local targetSize = 6
      local newDef = {}
      
      for i = 1, targetSize do
          local refSlot = baseDef[i] or baseDef[#baseDef]
          local refLevel = refSlot.level or 5
          
          local newLevel = refLevel
          if C.difficulty ~= "off" then
              local curveOffset = refLevel - origMax
              newLevel = math.min(255, math.max(2, baseLevel + offset + curveOffset))
          end
          
          local chosenSpecies
          local isFiller = (i > #baseDef)
          if C.randomize == "chaos" or (isFiller and C.randomize ~= "themed") then
              chosenSpecies = fullPokedexCache[math.random(#fullPokedexCache)]
          elseif C.randomize == "themed" or isFiller then
              chosenSpecies = activePool[math.random(#activePool)]
          else
              chosenSpecies = refSlot.species
          end
          
          local safeBase = getBaseSpecies(data, chosenSpecies)
          local correctStage = getEvolvedSpecies(data, safeBase, newLevel)
          
          -- Extract moves safely from dictionaries or the vanilla definition
          local slotMoves = nil
          if ULTIMATE_MOVES[correctStage] then
              slotMoves = {}
              for _, mId in ipairs(ULTIMATE_MOVES[correctStage]) do table.insert(slotMoves, mId) end
          elseif refSlot.moves then
              slotMoves = {}
              for _, m in ipairs(refSlot.moves) do 
                  local mId = type(m) == "table" and m.id or m
                  table.insert(slotMoves, mId)
              end
          end
          
          -- Assemble the output dynamically based on the active engine
          if isGen2 and Gen2Mon then
              local finalMoves = nil
              if slotMoves and #slotMoves > 0 then
                  finalMoves = {}
                  for _, mId in ipairs(slotMoves) do
                      local mDef = data.moves[mId]
                      if mDef then
                          -- Gen 2 strictly requires instantiated move objects with PP data
                          table.insert(finalMoves, { id = mId, pp = mDef.pp or 0, maxPp = mDef.pp or 0 })
                      end
                  end
              end
              -- Let the Gen 2 module instantiate the Pokemon seamlessly
              local newMon = Gen2Mon.new(data, correctStage, newLevel, { moves = finalMoves })
              table.insert(newDef, newMon)
          else
              -- Gen 1 just expects string definition tables
              table.insert(newDef, {
                  species = correctStage,
                  level = newLevel,
                  moves = slotMoves
              })
          end
      end
      
      return newDef
  end)

  -- Post-Battle calculation to inject EVs, DVs, and Boss AI layers
  local function applyPostBattleStats(battle, data)
      if C.difficulty == "off" or C.difficulty == "normal" then return end
      if not battle or not battle.enemyParty then return end
      
      local Gen2Mon = nil
      pcall(function() Gen2Mon = require("src.battle.gen2.Mon") end)
      local Gen1Stats = require("src.pokemon.Stats")
      
      for _, mon in ipairs(battle.enemyParty) do
          local pDef = data.pokemon[mon.species]
          if pDef then
              if C.difficulty == "medium" then
                  mon.dvs = { attack = 15, defense = 15, speed = 15, special = 15, hp = 15 }
              elseif C.difficulty == "hard" then
                  mon.dvs = { attack = 15, defense = 15, speed = 15, special = 15, hp = 15 }
                  mon.statExp = { attack = 65535, defense = 65535, speed = 65535, special = 65535, hp = 65535 }
              end
              
              if Gen2Mon and Gen2Mon.refreshStats then
                  Gen2Mon.refreshStats(mon, data)
              else
                  mon.stats = Gen1Stats.calc(pDef, mon.level, mon.dvs, mon.statExp)
                  mon.hp = mon.stats.hp
              end
          end
      end
      
      -- Sync Gen 1 UI Wrappers
      if battle.enemy and battle.enemy.isPlayer == false then
          if battle.enemy.curStats then 
             battle.enemy.curStats = battle.enemyParty[1].stats
          end
          if battle.enemy.shownHP then 
             battle.enemy.shownHP = battle.enemyParty[1].hp
          end
      end
      
      if C.difficulty == "hard" then
          battle.enemyAIMods = {1, 2, 3} 
          if battle.trainer and battle.trainer.attributes then
              local newTrainer = {}
              for k,v in pairs(battle.trainer) do newTrainer[k] = v end
              local newAttr = {}
              for k,v in pairs(newTrainer.attributes) do newAttr[k] = v end
              
              -- Map boss AI scoring layers seamlessly to Gen 2 bit flags
              newAttr[4] = 223
              newAttr[5] = 3
              newAttr[6] = 4
              newAttr[7] = 0
              
              newTrainer.attributes = newAttr
              battle.trainer = newTrainer
          end
      end
  end

  -- Wrap Gen 1 Constructor
  local ok1, BS1 = pcall(require, "src.battle.BattleState")
  if ok1 and not BS1.__dynamic_scaling_intercepted then
      BS1.__dynamic_scaling_intercepted = true
      local orig_newTrainer = BS1.newTrainer
      BS1.newTrainer = function(game, trainerId, partyIndex, opts)
          mod.__activeData = game.data
          mod.__activeSave = game.save
          mod.__activeParty = game.save.party
          
          local battle = orig_newTrainer(game, trainerId, partyIndex, opts)
          applyPostBattleStats(battle, game.data)
          return battle
      end
  end

  -- Wrap Gen 2 Constructor
  local ok2, BS2 = pcall(require, "src.battle.gen2.Battle")
  if ok2 and not BS2.__dynamic_scaling_intercepted then
      BS2.__dynamic_scaling_intercepted = true
      local orig_new = BS2.new
      BS2.new = function(opts)
          mod.__activeData = opts and opts.data
          mod.__activeSave = opts and opts.save
          mod.__activeParty = opts and opts.party
          
          local battle = orig_new(opts)
          if battle and not battle.wild then
              applyPostBattleStats(battle, mod.__activeData)
          end
          return battle
      end
  end

end
