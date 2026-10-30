local _dir = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"
local function lrequire(name)
    local key = _dir .. name
    if not package.loaded[key] then
        package.loaded[key] = assert(loadfile(_dir .. name .. ".lua"))()
    end
    return package.loaded[key]
end

local Device          = require("device")
local FrameContainer  = require("ui/widget/container/framecontainer")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan  = require("ui/widget/horizontalspan")
local Size            = require("ui/size")
local UIManager       = require("ui/uimanager")
local VerticalGroup   = require("ui/widget/verticalgroup")
local VerticalSpan    = require("ui/widget/verticalspan")
local _               = require("i18n")
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
    local is_landscape = self:isLandscape()

    local title_bar = self:buildTitleBar(_("Nonogram"), function()
        return {
            { text = _("New game"),            callback = function() self:onNewGame() end },
            self:makeDailyButtonConfig(),
            { text = self:getGridButtonText(), callback = function() self:openGridMenu() end },
            { text = self:getDiffButtonText(), callback = function() self:openDifficultyMenu() end },
            { text = _("Show solution"),       callback = function() self:onReveal() end },
            self:makeRulesButtonConfig(GAME_RULES_EN, GAME_RULES_FR),
        }
    end)

    self.status_text:setMaxWidth(self:getControlsWidth())
    local buttons = {
        { id = "mode_button", text = self:getModeButtonText(),
          callback = function() self:toggleMode() end },
        { text = _("Erase"), callback = function() self:onErase() end },
        { text = _("Check"), callback = function() self:onCheck() end },
        { text = _("Hint"),  callback = function() self:onHint() end },
        { id = "undo_button", text = _("Undo"),
          callback = function() self:onUndo() end },
    }
    -- Five buttons do not fit the narrow landscape side panel on one row.
    local action_bar = self:buildActionBar(is_landscape
        and { { buttons[1], buttons[2], buttons[3] }, { buttons[4], buttons[5] } }
        or  buttons)
    self.mode_button = action_bar:getButtonById("mode_button")
    self.undo_button = action_bar:getButtonById("undo_button")
    self:updateUndoButton()
    local controls = VerticalGroup:new{
        align = "center",
        self.status_text,
        VerticalSpan:new{ width = Size.span.vertical_large },
        action_bar,
    }

    -- The widget draws its own thick outer border around clues and grid, so
    -- the frame stays borderless: one visible edge around the board, not two.
    -- Clues make the board wider and taller than the grid alone, so it is
    -- fitted to both budget dimensions rather than to a square.
    local frame_pad   = Size.padding.large
    local frame_extra = 2 * frame_pad
    local budget_w, budget_h = self:getBoardBudget(title_bar, controls)
    self.board_widget = NonogramBoardWidget:new{
        board        = self.board,
        max_width    = budget_w - frame_extra,
        max_height   = budget_h - frame_extra,
        onCellAction = function(r, c, is_hold)
            self:onCellAction(r, c, is_hold)
        end,
    }
    local board_frame = FrameContainer:new{
        padding    = frame_pad,
        margin     = 0,
        bordersize = 0,
        self.board_widget,
    }

    if is_landscape then
        local content = HorizontalGroup:new{
            align = "center",
            board_frame,
            HorizontalSpan:new{ width = self:getGutter() },
            controls,
        }
        self:buildLandscapeLayout(title_bar, content)
    else
        self:buildPortraitLayout(title_bar, board_frame,
            VerticalGroup:new{ align = "center", controls, VerticalSpan:new{ width = self:getGutter() } })
    end
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
    self:buildLayout()
    UIManager:setDirty(self, function() return "ui", self.dimen end)
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
            elseif self.board.user[r][c] == 1 then
                -- A wrong fill left in place would keep the revealed board
                -- unsolved, and the round would never read as over.
                self.board.user[r][c] = 0
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
    return T(_("Difficulty: %1"), label)
end

function NonogramScreen:getGridButtonText()
    local n = self.board.n
    return T(_("Size: %1"), n .. "\xC3\x97" .. n)
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
        sizes[#sizes + 1] = { id = n, text = n .. "\xC3\x97" .. n }
    end
    MenuHelper.openSizeMenu{
        title     = _("Select size"),
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
        -- The mode is not repeated here: the mode button already says it.
        local diff  = self.plugin:getSetting("difficulty", "medium")
        status = self:joinStatus(
            T("%1×%1", self.board.n),
            MenuHelper.DIFFICULTY_LABELS[diff] or diff,
            T(_("Remaining: %1"), self.board:getRemainingCells()))
    end
    ScreenBase.updateStatus(self, status)
    -- Every move, hint, undo and reveal ends here, so the bar follows the board.
    self:refreshActionBar()
end

-- Show solution fills in the exact solution, so it ends the round too.
function NonogramScreen:isRoundOver()
    return self.board:isSolved()
end

return NonogramScreen
