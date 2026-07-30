-- Launcher drag (src/import/RomImporter.lua): a press ARMS a target, a move past
-- the threshold turns it into a scroll, and a release that never moved commits
-- the click.  This used to be sampled once per frame from inside draw(), because
-- main.lua forwarded no move or release events to the launcher at all; it now
-- runs off real events (pointermoved / pointerreleased), which is what this pins.
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local T = require("tests.modkit")
local RomImporter = require("src.import.RomImporter")

local ROW = { x = 0, y = 300, width = 400, height = 60, id = "slot2" }
-- The mod toggle's own hit rect.  opts.mods swaps it in for the slot row, since
-- mousepressed checks the slot rects first and both sit at the same y.
local MODROW = { x = 0, y = 300, width = 400, height = 60, id = "tweak" }

local function newLauncher(opts)
  opts = opts or {}
  local imp = setmetatable({}, { __index = RomImporter })
  imp.android = opts.android or false
  imp._s = 1
  imp._pageMax = opts.pageMax or 0
  imp.pageScroll = 0
  imp.panelVersion = "red"
  imp.slotScroll = { red = 0 }
  imp._slotMax = { red = 500 }
  imp.modScroll = 0
  imp._modMax = 400
  imp.tabRects = {}
  imp.slotRects = { ROW }
  imp.slotDeleteRects = {}
  imp.slotEditRects = {}
  imp.modRects = {}
  imp.modDeleteRects = {}
  imp.selected = nil
  imp._selectSlot = function(self, version, id) self.selected = version .. ":" .. id end
  imp.toggles = 0
  imp.toggled = nil
  imp._toggleMod = function(self, id)
    self.toggles = self.toggles + 1
    self.toggled = id
  end
  if opts.mods then
    imp.tab = "mods"
    imp.slotRects = {}
    imp.modRects = { MODROW }
  end
  imp._padCursor = { x = 10, y = 320 }
  imp._activatePadCursor = function() end
  imp._padDir = {}
  return imp
end

-- Every event carries the pointer doing it: "mouse" here, a touch id where a
-- second finger is in play.
local MOUSE = "mouse"

-- ------------------------------------------------------------------- a click
local imp = newLauncher()
imp:mousepressed(10, 320, 1, nil, MOUSE)
T.eq(imp.selected, nil, "the press only arms the row, it does not select it")
imp:pointerreleased(10, 320, 1, nil, MOUSE)
T.eq(imp.selected, "red:slot2", "the release selects it")
T.eq(imp.slotScroll.red, 0, "and nothing scrolled")

-- A second release has nothing left to commit.
imp.selected = nil
imp:pointerreleased(10, 320, 1, nil, MOUSE)
T.eq(imp.selected, nil, "the armed press is consumed by its release")

-- -------------------------------------------------------------------- a drag
imp = newLauncher()
imp:mousepressed(10, 320, 1, nil, MOUSE)
imp:pointermoved(10, 220, nil, MOUSE)                  -- 100px up, past the 4px threshold
T.eq(imp.slotScroll.red, 100, "the move scrolls the list by the distance dragged")
imp:pointerreleased(10, 220, 1, nil, MOUSE)
T.eq(imp.selected, nil, "a drag never selects the row it started on")

-- Under the threshold is still a click: a couple of pixels of tremor must not
-- swallow the selection.
imp = newLauncher()
imp:mousepressed(10, 320, 1, nil, MOUSE)
imp:pointermoved(10, 318, nil, MOUSE)
imp:pointerreleased(10, 318, 1, nil, MOUSE)
T.eq(imp.selected, "red:slot2", "a 2px wobble is a click, not a drag")

-- The list scroll clamps to its own extent.
imp = newLauncher()
imp:mousepressed(10, 320, 1, nil, MOUSE)
imp:pointermoved(10, -900, nil, MOUSE)
T.eq(imp.slotScroll.red, 500, "the list scroll clamps to _slotMax")
imp:pointermoved(10, 1200, nil, MOUSE)
T.eq(imp.slotScroll.red, 0, "and clamps at the top going back")

-- ------------------------------------------------------- a page that scrolls
-- Paged, the lists have no scroll of their own: the same drag pans the page, so
-- a swipe starting on a row behaves like one starting beside it.
imp = newLauncher({ pageMax = 300 })
imp:mousepressed(10, 320, 1, nil, MOUSE)
imp:pointermoved(10, 220, nil, MOUSE)
T.eq(imp.pageScroll, 100, "paged, the drag pans the page")
T.eq(imp.slotScroll.red, 0, "and leaves the list alone")
imp:pointermoved(10, -900, nil, MOUSE)
T.eq(imp.pageScroll, 300, "the pan clamps to maxPage")

-- ------------------------------------------------------- synthesized twins
-- SDL makes a mouse move and a mouse release out of every touch; touchmoved and
-- touchreleased already delivered those, so the flagged copies must be ignored
-- or a phone would apply every drag twice.
imp = newLauncher({ android = true })
imp:mousepressed(10, 320, 1, nil, MOUSE)
imp:pointermoved(10, 220, true, MOUSE)            -- the twin of a touchmoved
T.eq(imp.slotScroll.red, 0, "a flagged move is ignored")
imp:pointermoved(10, 220, nil, MOUSE)
T.eq(imp.slotScroll.red, 100, "the touch event itself scrolls")
imp:pointerreleased(10, 220, 1, true, MOUSE)
T.eq(imp._slotPress ~= nil, true, "a flagged release leaves the press armed")
imp:pointerreleased(10, 220, 1, nil, MOUSE)
T.eq(imp._slotPress, nil, "and the touch release resolves it")

-- ---------------------------------------------------------------- other buttons
-- A right-click release is not the end of a left-button drag.
imp = newLauncher()
imp:mousepressed(10, 320, 1, nil, MOUSE)
imp:pointerreleased(10, 320, 2, nil, MOUSE)
T.eq(imp.selected, nil, "button 2 does not commit a left-button press")
imp:pointerreleased(10, 320, 1, nil, MOUSE)
T.eq(imp.selected, "red:slot2", "button 1 does")

-- ------------------------------------------------------- one drag, many fingers
-- A drag belongs to the pointer that armed it.  A second finger elsewhere on the
-- screen must not be able to finish, or spoil, someone else's press: main.lua
-- hands the SDL touch id down for exactly this.
local A, B = 11, 22   -- two SDL touch ids

-- A foreign release must not commit the click A is still holding.
imp = newLauncher()
imp:mousepressed(10, 320, 1, nil, A)
imp:pointerreleased(10, 900, 1, nil, B)      -- finger B lifts somewhere else
T.eq(imp.selected, nil, "another finger lifting does not commit A's click")
T.eq(imp._slotPress ~= nil, true, "and leaves A's press armed")
imp:pointerreleased(10, 320, 1, nil, A)
T.eq(imp.selected, "red:slot2", "A's own release still commits it")

-- A foreign move must neither scroll nor turn A's press into a drag.
imp = newLauncher()
imp:mousepressed(10, 320, 1, nil, A)
imp:pointermoved(10, 200, nil, B)            -- finger B swipes 120px
T.eq(imp.slotScroll.red, 0, "another finger's move does not scroll A's list")
T.eq(imp._slotPress.moved, false, "nor mark A's press as moved")
imp:pointerreleased(10, 320, 1, nil, A)
T.eq(imp.selected, "red:slot2", "so A's still release commits, as a click")

-- And the owner keeps dragging normally with a foreign pointer in play.
imp = newLauncher()
imp:mousepressed(10, 320, 1, nil, A)
imp:pointermoved(10, 900, nil, B)            -- ignored
imp:pointermoved(10, 220, nil, A)            -- A's own 100px drag
T.eq(imp.slotScroll.red, 100, "the owning pointer still drags")
imp:pointerreleased(10, 220, 1, nil, A)
T.eq(imp.selected, nil, "and its drag still suppresses the click")

-- The page pan is owned the same way.
imp = newLauncher({ pageMax = 300 })
imp:mousepressed(10, 900, 1, nil, A)         -- empty background: arms a page pan
imp:pointermoved(10, 700, nil, B)
T.eq(imp.pageScroll, 0, "another finger does not pan a page someone else grabbed")
imp:pointermoved(10, 700, nil, A)
T.eq(imp.pageScroll, 200, "the grabbing finger pans it")

-- ------------------------------------------------------------ the pad cursor
-- The gamepad's A button clicks through the same arm-and-resolve path, under its
-- own identity, so gamepadreleased has to resolve it -- otherwise a handheld
-- could arm a slot row and never select it.
imp = newLauncher()
imp:gamepadpressed(nil, "a")
T.eq(imp.selected, nil, "pressing A arms the row under the pad")
imp:gamepadreleased(nil, "a")
T.eq(imp.selected, "red:slot2", "releasing A commits it")

-- A finger lifting cannot resolve the pad's press either.
imp = newLauncher()
imp:gamepadpressed(nil, "a")
imp:pointerreleased(10, 320, 1, nil, A)
T.eq(imp.selected, nil, "a finger does not commit the pad's press")
imp:gamepadreleased(nil, "a")
T.eq(imp.selected, "red:slot2", "the pad's own release does")

-- ------------------------------------------------------------ the mod toggle
-- The control whose symptom started all of this: it "flipped and flipped straight
-- back", so a toggle that fires once, on release, is the whole point.  The press
-- side is covered in launcher_echo_press.lua; this is the drag side.
imp = newLauncher({ mods = true })
imp:mousepressed(10, 320, 1, nil, MOUSE)
T.eq(imp.toggles, 0, "the press arms the mod row without toggling it")
imp:pointerreleased(10, 320, 1, nil, MOUSE)
T.eq(imp.toggles, 1, "the release toggles it exactly once")
T.eq(imp.toggled, "tweak", "and on the row that was pressed")

-- Nothing armed, nothing to commit.
imp = newLauncher({ mods = true })
imp:pointerreleased(10, 320, 1, nil, MOUSE)
T.eq(imp.toggles, 0, "a release with no armed press toggles nothing")

-- A drag scrolls the mod list and cancels the toggle.
imp = newLauncher({ mods = true })
imp:mousepressed(10, 320, 1, nil, MOUSE)
imp:pointermoved(10, 220, nil, MOUSE)
T.eq(imp.modScroll, 100, "the move scrolls the mod list by the distance dragged")
imp:pointerreleased(10, 220, 1, nil, MOUSE)
T.eq(imp.toggles, 0, "a drag never toggles the row it started on")

-- Under the threshold it is still a toggle.
imp = newLauncher({ mods = true })
imp:mousepressed(10, 320, 1, nil, MOUSE)
imp:pointermoved(10, 318, nil, MOUSE)
imp:pointerreleased(10, 318, 1, nil, MOUSE)
T.eq(imp.toggles, 1, "a 2px wobble is a toggle, not a drag")

-- Paged, the mod list has no scroll of its own either: the drag pans the page.
imp = newLauncher({ mods = true, pageMax = 300 })
imp:mousepressed(10, 320, 1, nil, MOUSE)
imp:pointermoved(10, 220, nil, MOUSE)
T.eq(imp.pageScroll, 100, "paged, a mod-row drag pans the page")
T.eq(imp.modScroll, 0, "and leaves the mod list alone")

-- The mod scroll clamps to its own extent, both ends.
imp = newLauncher({ mods = true })
imp:mousepressed(10, 320, 1, nil, MOUSE)
imp:pointermoved(10, -900, nil, MOUSE)
T.eq(imp.modScroll, 400, "the mod scroll clamps to _modMax")
imp:pointermoved(10, 1200, nil, MOUSE)
T.eq(imp.modScroll, 0, "and clamps at the top going back")

-- The synthesized twins are dropped here too, or a phone would scroll twice and
-- resolve the toggle before the touch release arrived.
imp = newLauncher({ mods = true, android = true })
imp:mousepressed(10, 320, 1, nil, A)
imp:pointermoved(10, 220, true, MOUSE)
T.eq(imp.modScroll, 0, "a flagged move does not scroll the mod list")
imp:pointerreleased(10, 320, 1, true, MOUSE)
T.eq(imp._modPress ~= nil, true, "a flagged release leaves the mod press armed")
imp:pointerreleased(10, 320, 1, nil, A)
T.eq(imp.toggles, 1, "and the touch release resolves it, once")

-- ------------------------------------------------------------- the mouse wheel
-- main.lua forwards love.wheelmoved here now; it used to be a function the
-- launcher installed over the global one from inside new().  The forwarding is
-- what changed, so pin where the event lands: an overflowing page takes it and
-- returns, and only a page that fits lets a list have it.
imp = newLauncher({ pageMax = 300 })
imp:wheelmoved(0, -1)
T.eq(imp.pageScroll, 48, "paged, the wheel scrolls the page one step")
T.eq(imp.slotScroll.red, 0, "and the list underneath is left alone")
imp:wheelmoved(0, 1)
T.eq(imp.pageScroll, 0, "scrolling back up returns it")

-- Page fits: the game tab's own save-slot list takes the wheel.
imp = newLauncher()
imp.tab = "red"
imp:wheelmoved(0, -1)
T.eq(imp.slotScroll.red, 48, "unpaged, the wheel scrolls the save-slot list")
imp:wheelmoved(0, 20)
T.eq(imp.slotScroll.red, 0, "clamped at the top")
imp:wheelmoved(0, -100)
T.eq(imp.slotScroll.red, 500, "and at _slotMax going down")

-- The mods tab's list takes it on that tab.
imp = newLauncher({ mods = true })
imp:wheelmoved(0, -1)
T.eq(imp.modScroll, 48, "on the mods tab the wheel scrolls the mod list")
T.eq(imp.slotScroll.red, 0, "and not the save-slot list")

-- A tab whose panel did not draw has no extent to scroll against.
imp = newLauncher()
imp.tab = "blue"          -- panelVersion is still "red"
imp:wheelmoved(0, -1)
T.eq(imp.slotScroll.red, 0, "a wheel on a tab that is not the drawn one does nothing")

-- ------------------------------------------------- a tab change under a press
-- Cycling tabs with the shoulder buttons drops every half-started press, the
-- page pan included, exactly as clicking a tab chip does.  The column it was
-- armed against is no longer on screen and its scroll0 belongs to a list of a
-- different length.
imp = newLauncher({ pageMax = 300 })
imp.tab = "red"
imp:mousepressed(10, 900, 1, nil, MOUSE)   -- empty background: arms a page pan
T.eq(imp._pagePress ~= nil, true, "a background press arms a page pan")
imp:_cycleTab(1)
T.eq(imp._pagePress, nil, "cycling tabs drops it")
imp:pointermoved(10, 700, nil, MOUSE)
T.eq(imp.pageScroll, 0, "so a move afterwards pans nothing")

T.finish("launcher pointer drag")
