return function(mod)
  -- =====================================================================
  -- Translucent UI Mod (Compatibility Patch)
  -- Fixes Voxel Mod integration by preventing global alpha bleeding
  -- into SGB Battle shaders and adding Widescreen fill support!
  --
  -- Fix (#1): the vanilla sgbPalettes hijack added an sgbPalettes
  -- returning nil to screens that never had one (TextBox, Menu,
  -- ChoiceBox, BoxMenu, BagMenu, ShopMenu).  Game:draw walks the state
  -- stack top-down and stops at the FIRST state that exposes
  -- sgbPalettes, so those hijacked screens claimed the SGB zone pass and
  -- handed endFrame an empty zone list -- the shade-remap shader never
  -- ran, and sprites that rely on it for colour (party icons, HP bars,
  -- battle pics, overworld NPCs) rendered as raw DMG grays: "whited
  -- out" / "inverted".  Native zone ownership is restored: screens that
  -- define sgbPalettes keep theirs, screens that never did fall through
  -- to the overworld/battle beneath, exactly as vanilla.
  --
  -- The translucent regions are instead marked trueColor via
  -- PaletteFX.markTrueColor, the engine's own mechanism for regions
  -- that must not reach the shade-remap shader (DexEntryMenu uses it
  -- for its full-colour sprite art), so boxes stay translucent without
  -- erasing the world behind them.
  -- =====================================================================

  local Font = require("src.render.Font")
  local BattleState = require("src.battle.BattleState")

  -- Helper function to detect if the player is currently in a Battle
  local function isInBattle(game)
    if not game or not game.stack then return false end
    for _, state in ipairs(game.stack.states) do
      if state.__index == BattleState then
        return true
      end
    end
    return false
  end

  -- 1. Intercept Font.drawBox to make all UI boxes consistently translucent
  if not Font.__translucent_wrapped_final then
    Font.__translucent_wrapped_final = true

    local origDrawBox = Font.drawBox

    Font.drawBox = function(x, y, w, h)
      -- ONLY apply translucency if the targeted flag is active!
      if Font.__translucent_active then
        -- love is nil headlessly (modkit validate); nothing draws then,
        -- so capture the graphics seams lazily inside the wrapper
        local loveGraphics = love and love.graphics
        if not loveGraphics then return origDrawBox(x, y, w, h) end
        local origSetColor = loveGraphics.setColor

        -- mark the box region trueColor so the SGB shade-remap pass
        -- re-blits it unshaded (PaletteFX.markTrueColor); without this a
        -- translucent white box is remapped by the keyed shader's
        -- red-channel buckets into solid zone colours or worse
        local PaletteFX = require("src.render.PaletteFX")
        PaletteFX.markTrueColor(x * 8, y * 8, w * 8, h * 8)

        loveGraphics.setColor = function(r, g, b, a)
          -- Safely handle both table colors and argument colors!
          if type(r) == "table" then
            local tr, tg, tb, ta = r[1], r[2], r[3], r[4]
            origSetColor(tr, tg, tb, (ta or 1) * 0.85)
          else
            origSetColor(r, g, b, (a or 1) * 0.85)
          end
        end

        local ok, err = pcall(origDrawBox, x, y, w, h)
        loveGraphics.setColor = origSetColor
        if not ok then error(err) end
      else
        origDrawBox(x, y, w, h)
      end
    end
  end

  -- 2. Modify Native Menus: Neutralize Palettes & Fix Layering
  local screens = {
    "src.ui.ListMenu", "src.ui.PartyMenu", "src.ui.Menu",
    "src.render.TextBox", "src.ui.BoxMenu", "src.ui.ChoiceBox",
    "src.ui.SummaryMenu", "src.ui.DexEntryMenu", "src.ui.BagMenu",
    "src.ui.ShopMenu", "src.ui.TownMap"
  }

  for _, path in ipairs(screens) do
    local ok, screen = pcall(require, path)
    if ok and screen then

      screen.isOpaque = false

      -- NOTE: sgbPalettes is deliberately NOT touched.  Screens that
      -- define their own zones (PartyMenu's HP bars + icon column,
      -- SummaryMenu, DexEntryMenu) keep them; screens that never had a
      -- zone list do not get one grafted on, so the zone-owner walk in
      -- Game:draw falls through to the overworld/battle beneath.

      -- Hide inactive menus to prevent bleeding
      if not screen.__translucent_wrapped_final then
        screen.__translucent_wrapped_final = true
        if screen.draw then
          local origDraw = screen.draw
          screen.draw = function(self)
            local top = self.game.stack:top()

            -- If covered by custom PC/DexNav grids, hide completely!
            if top ~= self and top.boxData then return end

            -- If Start Menu is covered by another menu, hide it!
            if top ~= self and self.items and (top.__index == require("src.ui.PartyMenu") or top.__index == require("src.ui.BagMenu")) then
              return
            end

            local in_battle = isInBattle(self.game)

            -- Safely enable global translucency ONLY outside of battles.
            -- This strictly protects the Battle Text Box from SGB shader corruption.
            if not in_battle then
              Font.__translucent_active = true
            end

            -- Clear hardcoded full-screen backgrounds
            local origSetColor = love.graphics.setColor
            local origRect = love.graphics.rectangle

            love.graphics.rectangle = function(mode, rx, ry, rw, rh)
              -- Widescreen support: rw >= 160 allows Voxel Mod's WIDE layout to work natively!
              if mode == "fill" and rw >= 160 and rh >= 144 then
                if not in_battle then
                  -- mark the full-screen fill trueColor too, so the zone
                  -- pass re-blits it unshaded instead of remapping it
                  local PaletteFX = require("src.render.PaletteFX")
                  PaletteFX.markTrueColor(rx, ry, rw, rh)

                  local r, g, b, a = love.graphics.getColor()
                  if type(r) == "table" then
                    origSetColor(r[1], r[2], r[3], (r[4] or 1) * 0.85)
                  else
                    origSetColor(r, g, b, (a or 1) * 0.85)
                  end

                  local ok_rect, err_rect = pcall(origRect, mode, rx, ry, rw, rh)
                  origSetColor(r, g, b, a)
                  if not ok_rect then error(err_rect) end
                else
                  origRect(mode, rx, ry, rw, rh)
                end
              else
                origRect(mode, rx, ry, rw, rh)
              end
            end

            local ok, err = pcall(origDraw, self)

            Font.__translucent_active = false
            love.graphics.rectangle = origRect

            if not ok then error(err) end
          end
        end
      end
    end
  end

  mod.log:info("Translucent UI Mod Compatibility Patch: Loaded Successfully!")
end
