local UndoStack  = require("undo_stack")
local grid_utils = require("grid_utils")

local SIZES = { 5, 10, 15 }

local function computeClues(grid, n)
    local row_clues, col_clues = {}, {}
    for r = 1, n do
        local clue, run = {}, 0
        for c = 1, n do
            if grid[r][c] then run = run + 1
            elseif run > 0 then clue[#clue + 1] = run; run = 0 end
        end
        if run > 0 then clue[#clue + 1] = run end
        row_clues[r] = #clue > 0 and clue or { 0 }
    end
    for c = 1, n do
        local clue, run = {}, 0
        for r = 1, n do
            if grid[r][c] then run = run + 1
            elseif run > 0 then clue[#clue + 1] = run; run = 0 end
        end
        if run > 0 then clue[#clue + 1] = run end
        col_clues[c] = #clue > 0 and clue or { 0 }
    end
    return row_clues, col_clues
end

local NonogramBoard = {}
NonogramBoard.__index = NonogramBoard

function NonogramBoard:new(opts)
    opts = opts or {}
    local n = opts.n or 10
    local obj = {
        n           = n,
        difficulty  = opts.difficulty or "medium",
        solution    = {},
        user        = grid_utils.emptyGrid(n, n, 0),
        row_clues   = {},
        col_clues   = {},
        wrong_marks = grid_utils.emptyBoolGrid(n, n),
        undo        = UndoStack:new{ max_size = 500 },
    }
    for r = 1, n do
        obj.solution[r] = {}
        for c = 1, n do
            obj.solution[r][c] = false
        end
    end
    setmetatable(obj, self)
    return obj
end

function NonogramBoard:_hasNoEmptyLines()
    local n = self.n
    for r = 1, n do
        local has = false
        for c = 1, n do
            if self.solution[r][c] then has = true; break end
        end
        if not has then return false end
    end
    for c = 1, n do
        local has = false
        for r = 1, n do
            if self.solution[r][c] then has = true; break end
        end
        if not has then return false end
    end
    return true
end

function NonogramBoard:generate(difficulty)
    self.difficulty = difficulty or self.difficulty
    local n = self.n
    local density = self.difficulty == "easy" and 0.45
                 or self.difficulty == "medium" and 0.55
                 or 0.65

    repeat
        for r = 1, n do
            for c = 1, n do
                self.solution[r][c] = math.random() < density
            end
        end
        self.row_clues, self.col_clues = computeClues(self.solution, n)
    until n < 10 or self:_hasNoEmptyLines()

    self.user        = grid_utils.emptyGrid(n, n, 0)
    self.wrong_marks = grid_utils.emptyBoolGrid(n, n)
    self.undo:clear()
end

function NonogramBoard:setCellState(r, c, state)
    if self:isSolved() then
        return false, "Puzzle already solved."
    end
    local prev = self.user[r][c]
    if prev == state then return true end
    self.undo:push({ r, c, prev })
    self.user[r][c] = state
    return true
end

function NonogramBoard:toggleCell(r, c)
    local cur = self.user[r][c]
    local next_state
    if cur == 0 then next_state = 1
    elseif cur == 1 then next_state = -1
    else next_state = 0
    end
    self:setCellState(r, c, next_state)
end

function NonogramBoard:undo()
    if not self.undo:canUndo() then
        return false, UndoStack.NOTHING_TO_UNDO
    end
    local entry = self.undo:pop()
    self.user[entry[1]][entry[2]] = entry[3]
    return true
end

function NonogramBoard:canUndo()
    return self.undo:canUndo()
end

function NonogramBoard:checkProgress()
    local n = self.n
    for r = 1, n do
        for c = 1, n do
            local u = self.user[r][c]
            local s = self.solution[r][c]
            self.wrong_marks[r][c] = (u == 1 and not s) or (u == -1 and s)
        end
    end
end

function NonogramBoard:isSolved()
    local n = self.n
    for r = 1, n do
        for c = 1, n do
            if self.solution[r][c] then
                if self.user[r][c] ~= 1 then return false end
            else
                if self.user[r][c] == 1 then return false end
            end
        end
    end
    return true
end

function NonogramBoard:getRemainingCells()
    local n, count = self.n, 0
    for r = 1, n do
        for c = 1, n do
            if self.solution[r][c] and self.user[r][c] ~= 1 then
                count = count + 1
            end
        end
    end
    return count
end

function NonogramBoard:serialize()
    local n = self.n
    local sol, usr = {}, {}
    for r = 1, n do
        sol[r] = {}
        usr[r] = {}
        for c = 1, n do
            sol[r][c] = self.solution[r][c]
            usr[r][c] = self.user[r][c]
        end
    end
    local rc, cc = {}, {}
    for r = 1, n do
        rc[r] = {}
        for i, v in ipairs(self.row_clues[r]) do rc[r][i] = v end
    end
    for c = 1, n do
        cc[c] = {}
        for i, v in ipairs(self.col_clues[c]) do cc[c][i] = v end
    end
    return {
        n          = n,
        difficulty = self.difficulty,
        solution   = sol,
        user       = usr,
        row_clues  = rc,
        col_clues  = cc,
        undo       = self.undo:serialize(),
    }
end

function NonogramBoard:load(data)
    if not data or not data.solution or not data.user or not data.n then
        return false
    end
    local n = data.n
    if n ~= 5 and n ~= 10 and n ~= 15 then return false end
    self.n          = n
    self.difficulty = data.difficulty or "medium"
    self.solution   = {}
    self.user       = {}
    for r = 1, n do
        self.solution[r] = {}
        self.user[r]     = {}
        for c = 1, n do
            self.solution[r][c] = data.solution[r] and data.solution[r][c] or false
            self.user[r][c]     = data.user[r] and data.user[r][c] or 0
        end
    end
    if data.row_clues and data.col_clues then
        self.row_clues = {}
        self.col_clues = {}
        for r = 1, n do
            self.row_clues[r] = data.row_clues[r] or { 0 }
        end
        for c = 1, n do
            self.col_clues[c] = data.col_clues[c] or { 0 }
        end
    else
        self.row_clues, self.col_clues = computeClues(self.solution, n)
    end
    self.wrong_marks = grid_utils.emptyBoolGrid(n, n)
    self.undo        = UndoStack:new{ max_size = 500 }
    if data.undo then self.undo:load(data.undo) end
    return true
end

return {
    NonogramBoard = NonogramBoard,
    SIZES         = SIZES,
}
