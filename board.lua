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

-- ---------------------------------------------------------------------------
-- Uniqueness counter: standard nonogram line-solving technique. Enumerate
-- every valid full line for each row/column clue, then iteratively filter
-- row and column candidate-line sets against each other (a cell's value is
-- only achievable if some remaining row candidate AND some remaining column
-- candidate agree on it) until reaching a fixed point, branching only on
-- whichever row/column still has more than one candidate when propagation
-- alone can't finish. This is deliberately order-independent (rows/columns
-- get resolved in whatever order propagation naturally determines them,
-- not top-to-bottom) -- an earlier attempt tried MRV over a left-to-right
-- incremental per-column state machine, which silently breaks (a column's
-- run-length clue depends on the true top-to-bottom sequence, not
-- whatever order rows get branched on), caught via the standard sanity
-- check of testing against the generator's own known-good clues.
-- ---------------------------------------------------------------------------

local function enumerateLines(clue, n)
    if #clue == 1 and clue[1] == 0 then
        local empty = {}
        for i = 1, n do empty[i] = false end
        return { empty }
    end
    local m = #clue
    local minlen = 0
    for _, k in ipairs(clue) do minlen = minlen + k end
    minlen = minlen + (m - 1)
    if minlen > n then return {} end
    local slack = n - minlen

    local results = {}
    local line = {}
    for i = 1, n do line[i] = false end

    local function place(i, pos, gaps_left)
        if i > m then
            local copy = {}
            for j = 1, n do copy[j] = line[j] end
            results[#results + 1] = copy
            return
        end
        for extra = 0, gaps_left do
            local start = pos + extra
            local finish = start + clue[i] - 1
            if finish > n then break end
            for j = start, finish do line[j] = true end
            place(i + 1, finish + 2, gaps_left - extra)
            for j = start, finish do line[j] = false end
        end
    end
    place(1, 1, slack)
    return results
end

local function achievableAt(lines, pos)
    local t, f = false, false
    for _, line in ipairs(lines) do
        if line[pos] then t = true else f = true end
        if t and f then break end
    end
    return t, f
end

local function filterByAchievable(lines, achievable, n)
    local out = {}
    for _, line in ipairs(lines) do
        local ok = true
        for pos = 1, n do
            local v = line[pos]
            local a = achievable[pos]
            if (v and not a.t) or ((not v) and not a.f) then ok = false; break end
        end
        if ok then out[#out + 1] = line end
    end
    return out
end

-- Propagate to a fixed point. Returns false if any line set collapses to
-- empty (infeasible), true otherwise.
local function propagate(row_live, col_live, n)
    local changed = true
    while changed do
        changed = false
        for r = 1, n do
            local achievable = {}
            for c = 1, n do
                local t, f = achievableAt(col_live[c], r)
                achievable[c] = { t = t, f = f }
            end
            local filtered = filterByAchievable(row_live[r], achievable, n)
            if #filtered == 0 then return false end
            if #filtered < #row_live[r] then changed = true end
            row_live[r] = filtered
        end
        for c = 1, n do
            local achievable = {}
            for r = 1, n do
                local t, f = achievableAt(row_live[r], c)
                achievable[r] = { t = t, f = f }
            end
            local filtered = filterByAchievable(col_live[c], achievable, n)
            if #filtered == 0 then return false end
            if #filtered < #col_live[c] then changed = true end
            col_live[c] = filtered
        end
    end
    return true
end

local function copyLiveState(row_live, col_live, n)
    local r2, c2 = {}, {}
    for r = 1, n do r2[r] = row_live[r] end
    for c = 1, n do c2[c] = col_live[c] end
    return r2, c2
end

local function countSolutions(row_clues, col_clues, n, limit, node_budget)
    local row_live, col_live = {}, {}
    for r = 1, n do row_live[r] = enumerateLines(row_clues[r], n) end
    for c = 1, n do col_live[c] = enumerateLines(col_clues[c], n) end

    local solutions, nodes, exhausted = 0, 0, false

    local function search(row_live, col_live)
        if solutions >= limit or exhausted then return end
        nodes = nodes + 1
        if nodes > node_budget then exhausted = true; return end

        if not propagate(row_live, col_live, n) then return end

        local all_singletons = true
        for r = 1, n do
            if #row_live[r] ~= 1 then all_singletons = false; break end
        end
        if all_singletons then
            solutions = solutions + 1
            return
        end

        local best_is_row, best_idx, best_len = true, nil, math.huge
        for r = 1, n do
            if #row_live[r] >= 2 and #row_live[r] < best_len then
                best_len, best_idx, best_is_row = #row_live[r], r, true
            end
        end
        for c = 1, n do
            if #col_live[c] >= 2 and #col_live[c] < best_len then
                best_len, best_idx, best_is_row = #col_live[c], c, false
            end
        end

        local live = best_is_row and row_live[best_idx] or col_live[best_idx]
        for _, candidate in ipairs(live) do
            local r2, c2 = copyLiveState(row_live, col_live, n)
            if best_is_row then r2[best_idx] = { candidate } else c2[best_idx] = { candidate } end
            search(r2, c2)
            if solutions >= limit or exhausted then return end
        end
    end

    search(row_live, col_live)
    return solutions, exhausted
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

-- There's no "reveal a subset" mechanic here -- the row/col clues ARE the
-- entire puzzle, deduced from nothing else -- so unlike most of this
-- fleet's dig-with-verification retrofits, this generates+verifies whole
-- candidate solutions instead (same shape as hitori/nurikabe): build a
-- random solution, derive its clues, and keep it only if countSolutions
-- proves it's the unique grid matching those clues; otherwise retry.
local function uniquenessNodeBudget(n)
    if n <= 5 then return 20000 end
    if n <= 10 then return 60000 end
    return 150000
end

function NonogramBoard:generate(difficulty)
    self.difficulty = difficulty or self.difficulty
    local n = self.n
    local density = self.difficulty == "easy" and 0.45
                 or self.difficulty == "medium" and 0.55
                 or 0.65

    local budget = uniquenessNodeBudget(n)
    local best_solution, best_row_clues, best_col_clues

    for attempt = 1, 400 do
        local candidate = {}
        for r = 1, n do
            candidate[r] = {}
            for c = 1, n do
                candidate[r][c] = math.random() < density
            end
        end
        local row_clues, col_clues = computeClues(candidate, n)

        local has_no_empty_lines = true
        for r = 1, n do
            local has = false
            for c = 1, n do if candidate[r][c] then has = true; break end end
            if not has then has_no_empty_lines = false; break end
        end
        if has_no_empty_lines then
            for c = 1, n do
                local has = false
                for r = 1, n do if candidate[r][c] then has = true; break end end
                if not has then has_no_empty_lines = false; break end
            end
        end

        if has_no_empty_lines then
            if not best_solution then
                best_solution, best_row_clues, best_col_clues = candidate, row_clues, col_clues
            end
            local solutions, exhausted = countSolutions(row_clues, col_clues, n, 2, budget)
            if solutions == 1 and not exhausted then
                best_solution, best_row_clues, best_col_clues = candidate, row_clues, col_clues
                break
            end
        end
    end

    self.solution, self.row_clues, self.col_clues = best_solution, best_row_clues, best_col_clues

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
