-- Duplicated launcher press (src/import/RomImporter.lua + main.lua): one tap
-- reached the launcher twice, because love.touchpressed fires AND SDL
-- synthesizes a mouse press from the same touch, and main.lua forwarded both.
-- Every control acts on the press, so one tap on "+ New save slot" created two
-- slots and a mod toggle flipped straight back to where it started.
--
-- LÖVE flags the synthesized press `istouch`, so the twin identifies itself.
-- Nothing else works: SDL queues the mouse press BEFORE the finger event, so a
-- guard that waited to see the touch first would never fire (measured on a
-- device -- one tap still opened two file pickers).  Keying on the flag also
-- leaves a physical mouse on a tablet working and covers iOS without naming a
-- platform.
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local T = require("tests.modkit")
local RomImporter = require("src.import.RomImporter")

local function newLauncher()
  local imp = setmetatable({}, { __index = RomImporter })
  imp.android = true
  imp._s = 1
  imp._pageMax = 0               -- page fits: nothing is deferred to a release
  imp.pageScroll = 0
  imp._frame = 1
  imp.tabRects = {}
  imp.slotRects = {}
  imp.slotDeleteRects = {}
  imp.slotEditRects = {}
  imp.modRects = {}
  imp.modDeleteRects = {}
  imp.newSlotRect = { x = 0, y = 500, width = 200, height = 40 }
  imp.panelVersion = "red"
  imp.created = 0
  imp._newSlot = function(self) self.created = self.created + 1 end
  return imp
end

-- One tap: the touch, plus the press SDL synthesized from it (istouch), in
-- whichever order they arrive.
local imp = newLauncher()
imp:mousepressed(10, 510, 1, true)     -- SDL queues this one first
imp:mousepressed(10, 510, 1)           -- love.touchpressed's forward
T.eq(imp.created, 1, "one tap creates one slot, not two")

-- Order must not matter: the same pair the other way round is still one tap.
imp = newLauncher()
imp:mousepressed(10, 510, 1)
imp:mousepressed(10, 510, 1, true)
T.eq(imp.created, 1, "the twin is dropped whichever order it arrives in")

-- Deliberate taps all count: the guard drops the flagged twin, never the tap.
imp = newLauncher()
for _ = 1, 5 do
  imp:mousepressed(10, 510, 1, true)
  imp:mousepressed(10, 510, 1)
end
T.eq(imp.created, 5, "five taps create five slots")

-- Position is irrelevant: a twin whose coordinates drifted under highdpi
-- scaling is still dropped, which is why the flag beats comparing positions.
imp = newLauncher()
imp:mousepressed(120, 505, 1, true)
imp:mousepressed(10, 510, 1)
T.eq(imp.created, 1, "the flag decides, not how close the coordinates are")

-- ------------------------------------------------------------ a physical mouse
-- A real click carries no flag, so a mouse or trackpad on a tablet, in DeX or
-- on ChromeOS keeps working.
imp = newLauncher()
imp:mousepressed(10, 510, 1, false)
T.eq(imp.created, 1, "an unflagged press fires")
imp:mousepressed(10, 510, 1)
T.eq(imp.created, 2, "and so does one with the flag absent entirely")

-- ------------------------------------------------------------------- desktop
-- Desktop never sets the flag, so nothing there can be suppressed; the guard
-- needs no platform test of its own.
imp = newLauncher()
imp.android = false
imp:mousepressed(10, 510, 1)
imp:mousepressed(10, 510, 1)
T.eq(imp.created, 2, "desktop clicks are never suppressed")

T.finish("launcher echo press")
