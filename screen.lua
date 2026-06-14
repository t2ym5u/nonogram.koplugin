local _dir = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"
local function lrequire(name)
    local key = _dir .. name
    if not package.loaded[key] then
        package.loaded[key] = assert(loadfile(_dir .. name .. ".lua"))()
    end
    return package.loaded[key]
end

local ButtonTable     = require("ui/widget/buttontable")
local Device          = require("device")
local FrameContainer  = require("ui/widget/container/framecontainer")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan  = require("ui/widget/horizontalspan")
local Size            = require("ui/size")
local UIManager       = require("ui/uimanager")
local VerticalGroup   = require("ui/widget/verticalgroup")
local VerticalSpan    = require("ui/widget/verticalspan")
local _               = require("gettext")
local T               = require("ffi/util").template

local ScreenBase             = require("screen_base")
local MenuHelper             = require("menu_helper")
local board_module           = lrequire("board")
local NonogramBoardWidget    = lrequire("board_widget")

local NonogramBoard = board_module.NonogramBoard
local SIZES         = board_module.SIZES

local DeviceScreen = Device.screen

local GAME_RULES_EN = _([[
Nonogram (Picross) — Rules

Fill in cells to match the clue numbers for each row and column.

Each clue number represents one consecutive run of filled cells.
Multiple numbers in a clue mean multiple separate runs, in order from top/left to bottom/right, with at least one empty cell between each run.

Tap a cell to fill it. Long-press (or tap in cross mode) to mark a cell as definitely empty.
Solve the puzzle by satisfying all row and column clues simultaneously.
]])

local GAME_RULES_FR = [[
Nonogramme (Picross) — Règles

Remplissez les cases pour correspondre aux indices de chaque ligne et colonne.

Chaque nombre d'indice représente une séquence consécutive de cases remplies.
Plusieurs nombres dans un indice signifient plusieurs séquences séparées, dans l'ordre de haut en bas ou de gauche à droite, avec au moins une case vide entre chaque séquence.

Appuyez sur une case pour la remplir. Appui long (ou en mode croix) pour marquer une case comme définitivement vide.
Résolvez le puzzle en satisfaisant simultanément tous les indices de lignes et de colonnes.
]]

local NonogramScreen = ScreenBase:extend{}

function NonogramScreen:init()
    local state = self.plugin:loadState()
    local n     = self.plugin:getSetting("grid_n", 10)
    local diff  = self.plugin:getSetting("difficulty", "medium")
    self.board  = NonogramBoard:new{ n = n, difficulty = diff }
    if not self.board:load(state) then
        self.board:generate(diff)
    end
    self.mode = "fill"
    ScreenBase.init(self)
end

function NonogramScreen:serializeState()
    return self.board:serialize()
end

function NonogramScreen:buildLayout()
    self.mode = self.mode or "fill"

    self.board_widget = NonogramBoardWidget:new{
        board         = self.board,
        onCellAction  = function(r, c, is_hold)
            self:onCellAction(r, c, is_hold)
        end,
    }

    local is_landscape = self:isLandscape()
    local sw           = DeviceScreen:getWidth()

    local board_frame = FrameContainer:new{
        padding = Size.padding.large,
        margin  = Size.margin.default,
        self.board_widget,
    }

    local board_total   = self.board_widget.dimen.w + (Size.padding.large + Size.margin.default) * 2
    local right_panel_width = sw - board_total - Size.span.horizontal_default
    local button_width = is_landscape
        and math.max(right_panel_width - Size.span.horizontal_default, 100)
        or  math.floor(sw * 0.9)

    local top_buttons = ButtonTable:new{
        shrink_unneeded_width = true,
        width   = button_width,
        buttons = {
            {
                { text = _("New game"), callback = function() self:onNewGame() end },
                { id = "grid_button",  text = self:getGridButtonText(),
                  callback = function() self:openGridMenu() end },
                { id = "diff_button",  text = self:getDiffButtonText(),
                  callback = function() self:openDifficultyMenu() end },
                { text = _("Reveal"),  callback = function() self:onReveal() end },
                self:makeRulesButtonConfig(GAME_RULES_EN, GAME_RULES_FR),
            self:makeCloseButtonConfig(),
            },
        },
    }
    self.grid_button = top_buttons:getButtonById("grid_button")
    self.diff_button = top_buttons:getButtonById("diff_button")

    local control_buttons = ButtonTable:new{
        shrink_unneeded_width = true,
        width   = button_width,
        buttons = {
            {
                { id = "mode_button", text = self:getModeButtonText(),
                  callback = function() self:toggleMode() end },
                { text = _("Erase"),  callback = function() self:onErase() end },
                { text = _("Check"),  callback = function() self:onCheck() end },
                { id = "undo_button", text = _("Undo"),
                  callback = function() self:onUndo() end },
            },
        },
    }
    self.mode_button = control_buttons:getButtonById("mode_button")
    self.undo_button = control_buttons:getButtonById("undo_button")

    self:updateUndoButton()

    if is_landscape then
        local right_panel = VerticalGroup:new{
            align = "center",
            top_buttons,
            VerticalSpan:new{ width = Size.span.vertical_large },
            self.status_text,
            VerticalSpan:new{ width = Size.span.vertical_large },
            control_buttons,
        }
        self.layout = HorizontalGroup:new{
            align = "center",
            board_frame,
            HorizontalSpan:new{ width = Size.span.horizontal_default },
            right_panel,
        }
    else
        self.layout = VerticalGroup:new{
            align = "center",
            VerticalSpan:new{ width = Size.span.vertical_large },
            top_buttons,
            VerticalSpan:new{ width = Size.span.vertical_large },
            board_frame,
            VerticalSpan:new{ width = Size.span.vertical_large },
            self.status_text,
            VerticalSpan:new{ width = Size.span.vertical_large },
            control_buttons,
            VerticalSpan:new{ width = Size.span.vertical_large },
        }
    end
    self[1] = self.layout
    self:updateStatus()
end

function NonogramScreen:onCellAction(r, c, is_hold)
    if is_hold then
        self.board:setCellState(r, c, 0)
    elseif self.mode == "fill" then
        local cur = self.board.user[r][c]
        local next_state = (cur == 1) and 0 or 1
        self.board:setCellState(r, c, next_state)
    else
        local cur = self.board.user[r][c]
        local next_state = (cur == -1) and 0 or -1
        self.board:setCellState(r, c, next_state)
    end
    self.board_widget:refresh()
    self.plugin:saveState(self.board:serialize())
    self:updateUndoButton()
    if self.board:isSolved() then
        self:updateStatus()
        self:showMessage(_("Puzzle complete!"), 3)
    else
        self:updateStatus()
    end
end

function NonogramScreen:onNewGame()
    local diff = self.plugin:getSetting("difficulty", "medium")
    local n    = self.plugin:getSetting("grid_n", 10)
    self.board = NonogramBoard:new{ n = n, difficulty = diff }
    self.board:generate(diff)
    self.plugin:saveState(self.board:serialize())
    self.board_widget.board = self.board
    self.board_widget:refresh()
    self:updateUndoButton()
    self:updateStatus(_("New game started."))
end

function NonogramScreen:onGridChange(n)
    self.plugin:saveSetting("grid_n", n)
    local diff = self.plugin:getSetting("difficulty", "medium")
    self.board = NonogramBoard:new{ n = n, difficulty = diff }
    self.board:generate(diff)
    self.plugin:saveState(self.board:serialize())
    self:buildLayout()
    UIManager:setDirty(self, function() return "ui", self.dimen end)
end

function NonogramScreen:onUndo()
    local ok, err = self.board:undo()
    if not ok then
        self:showMessage(err or _("Nothing to undo."), 2)
        return
    end
    self.board_widget:refresh()
    self.plugin:saveState(self.board:serialize())
    self:updateUndoButton()
    self:updateStatus()
end

function NonogramScreen:onCheck()
    self.board:checkProgress()
    self.board_widget:refresh()
    self:updateStatus(_("Wrong cells marked."))
end

function NonogramScreen:onReveal()
    local n = self.board.n
    for r = 1, n do
        for c = 1, n do
            if self.board.solution[r][c] then
                self.board.user[r][c] = 1
            end
        end
    end
    self.board_widget:refresh()
    self.plugin:saveState(self.board:serialize())
    self:updateStatus(_("Solution revealed."))
end

function NonogramScreen:onErase()
    local n = self.board.n
    for r = 1, n do
        for c = 1, n do
            if self.board.user[r][c] ~= 0 then
                self.board:setCellState(r, c, 0)
            end
        end
    end
    self.board_widget:refresh()
    self.plugin:saveState(self.board:serialize())
    self:updateUndoButton()
    self:updateStatus(_("Board cleared."))
end

function NonogramScreen:toggleMode()
    self.mode = (self.mode == "fill") and "cross" or "fill"
    if self.mode_button then
        self.mode_button:setText(self:getModeButtonText(), self.mode_button.width)
    end
    self:updateStatus()
end

function NonogramScreen:getModeButtonText()
    if self.mode == "fill" then
        return _("Fill mode")
    else
        return _("Cross mode")
    end
end

function NonogramScreen:getDiffButtonText()
    local diff  = self.plugin:getSetting("difficulty", "medium")
    local label = MenuHelper.DIFFICULTY_LABELS[diff] or diff
    return T(_("Diff: %1"), label)
end

function NonogramScreen:getGridButtonText()
    local n = self.board.n
    return T(_("Grid: %1"), n .. "x" .. n)
end

function NonogramScreen:openDifficultyMenu()
    MenuHelper.openDifficultyMenu{
        current   = self.plugin:getSetting("difficulty", "medium"),
        parent    = self,
        on_select = function(id)
            self.plugin:saveSetting("difficulty", id)
            if self.diff_button then
                self.diff_button:setText(self:getDiffButtonText(), self.diff_button.width)
            end
            self:onNewGame()
        end,
    }
end

function NonogramScreen:openGridMenu()
    local sizes = {}
    for _, n in ipairs(SIZES) do
        sizes[#sizes + 1] = { id = n, text = n .. "x" .. n }
    end
    MenuHelper.openSizeMenu{
        title     = _("Select grid size"),
        sizes     = sizes,
        current   = self.board.n,
        parent    = self,
        on_select = function(n)
            self:onGridChange(n)
        end,
    }
end

function NonogramScreen:updateUndoButton()
    if not self.undo_button then return end
    self.undo_button:enableDisable(self.board:canUndo())
end

function NonogramScreen:updateStatus(msg)
    local status
    if msg then
        status = msg
    elseif self.board:isSolved() then
        status = _("Puzzle complete!")
    else
        local remaining = self.board:getRemainingCells()
        local mode_label = (self.mode == "fill") and _("Fill") or _("Cross")
        status = T(_("Remaining: %1  |  Mode: %2"), remaining, mode_label)
    end
    ScreenBase.updateStatus(self, status)
end

return NonogramScreen
