-- Headless: the Translucent UI mod must load clean and must NOT graft an
-- sgbPalettes method onto screens that never had one (issue #1) -- that
-- hijack claimed the SGB zone pass for the whole frame and left sprites
-- uncolored ("whited out / inverted").
-- Run with:
--   POKEPORT_DATA_DIR=tests/fixture_data luajit mods/Translucent_UI/tests/Translucent_UI_test.lua
package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.modkit")
local Data = require("src.core.Data")
Data:load()
local run = T.sdk.loadMod("mods/Translucent_UI", { data = Data })
T.eq(#run.errors, 0, "loads clean")

local ok, TextBox = pcall(require, "src.render.TextBox")
T.check(ok and TextBox, "src.render.TextBox resolves")
T.check(TextBox.sgbPalettes == nil,
  "TextBox never had sgbPalettes; the mod must not graft one on")
T.check(TextBox.isOpaque == false,
  "TextBox is transparent (world shows through)")
T.check(TextBox.__translucent_wrapped_final == true,
  "TextBox draw wrapper installed")

local ok2, BoxMenu = pcall(require, "src.ui.BoxMenu")
T.check(ok2 and BoxMenu, "src.ui.BoxMenu resolves")
T.check(BoxMenu.sgbPalettes == nil,
  "BoxMenu never had sgbPalettes; the mod must not graft one on")

-- screens that DO own zones keep them
local ok3, PartyMenu = pcall(require, "src.ui.PartyMenu")
T.check(ok3 and PartyMenu and type(PartyMenu.sgbPalettes) == "function",
  "PartyMenu keeps its native sgbPalettes (HP bars + icon column)")

local ok4, DexEntryMenu = pcall(require, "src.ui.DexEntryMenu")
T.check(ok4 and DexEntryMenu and type(DexEntryMenu.sgbPalettes) == "function",
  "DexEntryMenu keeps its native sgbPalettes")

run.release()
T.finish("Translucent UI")
