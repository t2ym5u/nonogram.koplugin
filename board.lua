local UndoStack  = require("undo_stack")
local grid_utils = require("grid_utils")
local Hint      = require("hint")

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

-- 1.5.0: a line is an integer bit mask (bit i - 1 set = cell i filled) and
-- a set of lines is summed up by two masks, the cells some line fills and
-- the cells some line leaves empty. Same algorithm and same order as the
-- table-of-booleans version it replaces -- same propagation, same branch
-- choices, same counts and node counts, so the same puzzles -- but a 15x15
-- Easy puzzle no longer takes up to 0.4 s on a desktop (10 s on a Kobo).
local bit = require("bit")
local band, bor, bnot, bxor, lshift = bit.band, bit.bor, bit.bnot, bit.bxor, bit.lshift

local function enumerateLines(clue, n)
    if #clue == 1 and clue[1] == 0 then
        return { 0 }
    end
    local m = #clue
    local minlen = 0
    for _, k in ipairs(clue) do minlen = minlen + k end
    minlen = minlen + (m - 1)
    if minlen > n then return {} end
    local slack = n - minlen

    local results = {}
    local function place(i, pos, gaps_left, line)
        if i > m then
            results[#results + 1] = line
            return
        end
        for extra = 0, gaps_left do
            local start = pos + extra
            local finish = start + clue[i] - 1
            if finish > n then break end
            -- cells start..finish: bits start - 1 .. finish - 1
            local block = lshift(lshift(1, clue[i]) - 1, start - 1)
            place(i + 1, finish + 2, gaps_left - extra, bor(line, block))
        end
    end
    place(1, 1, slack, 0)
    return results
end

-- The cells some line of `lines` fills, and the cells some line leaves
-- empty, as masks over the n cells. Line sets are never modified (filtering
-- makes a new one), so the masks are cached per set.
local ach_t = setmetatable({}, { __mode = "k" })
local ach_f = setmetatable({}, { __mode = "k" })
local function achievable(lines, full)
    local t = ach_t[lines]
    if t then return t, ach_f[lines] end
    local f = 0
    t = 0
    for i = 1, #lines do
        local line = lines[i]
        t = bor(t, line)
        f = bor(f, band(bnot(line), full))
        if t == full and f == full then break end
    end
    ach_t[lines], ach_f[lines] = t, f
    return t, f
end

-- Keeps the lines that fill only cells allowed filled and leave empty only
-- cells allowed empty (the same set when they all do).
local function filterByAchievable(lines, can_fill, can_empty, full)
    local no_fill, no_empty = band(bnot(can_fill), full), band(bnot(can_empty), full)
    local t, f = achievable(lines, full)
    if band(t, no_fill) == 0 and band(f, no_empty) == 0 then return lines end
    -- the kept lines' masks are worked out on the way (achievable() would
    -- go over them again)
    local out, k, ot, of = {}, 0, 0, 0
    for i = 1, #lines do
        local line = lines[i]
        local empty = band(bnot(line), full)
        if band(line, no_fill) == 0 and band(empty, no_empty) == 0 then
            k = k + 1
            out[k] = line
            ot, of = bor(ot, line), bor(of, empty)
        end
    end
    ach_t[out], ach_f[out] = ot, of
    return out
end

-- Propagate to a fixed point. Returns false if any line set collapses to
-- empty (infeasible), true otherwise.
--
-- 1.6.0: only the lines whose crossing lines changed what they allow are
-- filtered again (a row is "dirty" when some column's fillable/emptiable
-- cells in that row changed, and the other way round), instead of every
-- row and every column on every sweep. Filtering only ever removes lines,
-- so the order doesn't matter: the same fixed point is reached (same line
-- sets, in the same order), hence the same branch choices, counts and node
-- counts as before -- the same puzzles. A search branch starts from its
-- parent's fixed point with one line narrowed down to a single candidate:
-- it passes that line (is_row, idx), and only the lines crossing it start
-- dirty; otherwise every line does.
local function propagate(row_live, col_live, n, is_row, idx)
    local full = lshift(1, n) - 1
    local rt, rf, ct, cf = {}, {}, {}, {}
    local rdirty, cdirty = {}, {}
    for i = 1, n do
        rt[i], rf[i] = achievable(row_live[i], full)
        ct[i], cf[i] = achievable(col_live[i], full)
        if idx then
            rdirty[i], cdirty[i] = not is_row, is_row
        else
            rdirty[i], cdirty[i] = true, true
        end
    end
    local pending, passes = true, 0
    while pending do
        pending = false
        passes = passes + 1
        -- Rows against what the columns allow.
        for r = 1, n do
            if rdirty[r] then
                rdirty[r] = false
                local bitr = lshift(1, r - 1)
                local can_fill, can_empty = 0, 0
                for c = 1, n do
                    local bitc = lshift(1, c - 1)
                    if band(ct[c], bitr) ~= 0 then can_fill = bor(can_fill, bitc) end
                    if band(cf[c], bitr) ~= 0 then can_empty = bor(can_empty, bitc) end
                end
                local lines = row_live[r]
                local filtered = filterByAchievable(lines, can_fill, can_empty, full)
                if #filtered == 0 then return false end
                if filtered ~= lines then
                    row_live[r] = filtered
                    local t, f = achievable(filtered, full)
                    local diff = bor(bxor(t, rt[r]), bxor(f, rf[r]))
                    rt[r], rf[r] = t, f
                    for c = 1, n do
                        if band(diff, lshift(1, c - 1)) ~= 0 then
                            cdirty[c] = true
                            pending = true
                        end
                    end
                end
            end
        end
        -- Columns against what the rows allow.
        for c = 1, n do
            if cdirty[c] then
                cdirty[c] = false
                local bitc = lshift(1, c - 1)
                local can_fill, can_empty = 0, 0
                for r = 1, n do
                    local bitr = lshift(1, r - 1)
                    if band(rt[r], bitc) ~= 0 then can_fill = bor(can_fill, bitr) end
                    if band(rf[r], bitc) ~= 0 then can_empty = bor(can_empty, bitr) end
                end
                local lines = col_live[c]
                local filtered = filterByAchievable(lines, can_fill, can_empty, full)
                if #filtered == 0 then return false end
                if filtered ~= lines then
                    col_live[c] = filtered
                    local t, f = achievable(filtered, full)
                    local diff = bor(bxor(t, ct[c]), bxor(f, cf[c]))
                    ct[c], cf[c] = t, f
                    for r = 1, n do
                        if band(diff, lshift(1, r - 1)) ~= 0 then
                            rdirty[r] = true
                            pending = true
                        end
                    end
                end
            end
        end
    end
    return true, passes
end

local function copyLiveState(row_live, col_live, n)
    local r2, c2 = {}, {}
    for r = 1, n do r2[r] = row_live[r] end
    for c = 1, n do c2[c] = col_live[c] end
    return r2, c2
end

-- line_cache (optional): clue -> its lines, shared across calls (the
-- generator's attempts keep meeting the same clues).
local function initialLive(row_clues, col_clues, n, line_cache)
    local function lines(clue)
        if not line_cache then return enumerateLines(clue, n) end
        local key = table.concat(clue, ",")
        local l = line_cache[key]
        if not l then
            l = enumerateLines(clue, n)
            line_cache[key] = l
        end
        return l
    end
    local row_live, col_live = {}, {}
    for r = 1, n do row_live[r] = lines(row_clues[r]) end
    for c = 1, n do col_live[c] = lines(col_clues[c]) end
    return row_live, col_live
end

-- 1.6.0: pure line logic, the way a player solves it without guessing:
-- each row or column, given its clue and the cells already known, settles
-- every cell that all its possible placements agree on; repeat until
-- nothing changes. Returns whether that alone finishes the grid (which
-- also proves the solution unique) and how many passes it took (one pass
-- = every row that learned something, then every column that did).
local function lineSolve(row_clues, col_clues, n, line_cache)
    local row_live, col_live = initialLive(row_clues, col_clues, n, line_cache)
    local ok, passes = propagate(row_live, col_live, n)
    if not ok then return false, passes end
    for r = 1, n do
        if #row_live[r] ~= 1 then return false, passes end
    end
    return true, passes
end

local function countSolutions(row_clues, col_clues, n, limit, node_budget, line_cache)
    local row_live, col_live = initialLive(row_clues, col_clues, n, line_cache)

    local solutions, nodes, exhausted = 0, 0, false

    local function search(row_live, col_live, is_row, idx)
        if solutions >= limit or exhausted then return end
        nodes = nodes + 1
        if nodes > node_budget then exhausted = true; return end

        if not propagate(row_live, col_live, n, is_row, idx) then return end

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
            search(r2, c2, best_is_row, best_idx)
            if solutions >= limit or exhausted then return end
        end
    end

    search(row_live, col_live)
    return solutions, exhausted, nodes
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
-- entire puzzle, deduced from nothing else -- so this generates+verifies
-- whole candidate solutions (same shape as hitori/nurikabe): build a random
-- solution, derive its clues, keep it only if it passes the check below.
--
-- 1.6.0: no guessing. A grid is kept only if lineSolve() finishes it --
-- pure line-by-line logic, never "assume this cell, see if it breaks" --
-- which also proves the solution unique (the search-based uniqueness check
-- used to accept grids that only trial and error could solve: about 1
-- 15x15 Easy puzzle in 3, 1 10x10 Easy in 9). Difficulty is how long the
-- chain of deductions is: the number of passes lineSolve() needs (a pass =
-- the rows that learned something, then the columns), which must fall in
-- the level's band below, on a grid drawn at the level's fill density
-- (fuller grids give long runs that settle many cells at once). Easy used
-- to be the emptiest grid and Hard the fullest -- the opposite of how hard
-- they are to reason out -- so the densities are swapped round.
local DENSITY = { easy = 0.65, medium = 0.55, hard = 0.45 }
-- [n][difficulty] = { fewest passes, most passes }
local PASS_BAND = {
    [5]  = { easy = { 1, 2 }, medium = { 3, 3 }, hard = { 4, math.huge } },
    [10] = { easy = { 1, 3 }, medium = { 4, 5 }, hard = { 6, math.huge } },
    [15] = { easy = { 1, 4 }, medium = { 5, 7 }, hard = { 8, math.huge } },
}
local MAX_ATTEMPTS      = 400   -- in-band draws; see the fallbacks below
local FALLBACK_DENSITY  = 0.75  -- ~99% of these grids solve line by line
local FALLBACK_ATTEMPTS = 100

local function randomGrid(n, density)
    local g = {}
    for r = 1, n do
        g[r] = {}
        for c = 1, n do g[r][c] = math.random() < density end
    end
    return g
end

local function hasEmptyLine(row_clues, col_clues, n)
    for i = 1, n do
        if row_clues[i][1] == 0 or col_clues[i][1] == 0 then return true end
    end
    return false
end

-- How far `passes` falls outside `band` (0 = inside).
local function bandDistance(passes, band)
    if passes < band[1] then return band[1] - passes end
    if passes > band[2] then return passes - band[2] end
    return 0
end

-- on_progress (optional): called with a 0..1 fraction as it goes.
-- Returns how the grid was found, for the specs: "band" (the usual case),
-- "near" (line-solvable but outside the level's band), "dense" (the denser
-- fallback) or "full" (the every-cell-filled last resort) -- see the
-- specs for how often each happens.
function NonogramBoard:generate(difficulty, on_progress)
    self.difficulty = difficulty or self.difficulty
    local n = self.n
    local density = DENSITY[self.difficulty] or DENSITY.medium
    local bands = PASS_BAND[n] or PASS_BAND[15]
    local band = bands[self.difficulty] or bands.medium

    local line_cache = {}   -- for this n only
    local best, best_rc, best_cc, best_dist, how

    -- Draws are counted, never timed, so a seed always gives the same grid.
    for attempt = 1, MAX_ATTEMPTS do
        -- 15x15 Hard takes ~20 attempts, the others a handful
        if on_progress then on_progress(attempt / (attempt + 20)) end
        local candidate = randomGrid(n, density)
        local row_clues, col_clues = computeClues(candidate, n)
        if not hasEmptyLine(row_clues, col_clues, n) then
            local solved, passes = lineSolve(row_clues, col_clues, n, line_cache)
            if solved then
                local dist = bandDistance(passes, band)
                if not best or dist < best_dist then
                    best, best_rc, best_cc, best_dist = candidate, row_clues, col_clues, dist
                    if dist == 0 then break end
                end
            end
        end
    end
    how = best and (best_dist == 0 and "band" or "near")

    -- Nothing line-solvable at all (not seen in tens of thousands of seeds):
    -- a fuller grid, then the full grid (every clue is the whole line).
    if not best then
        for _ = 1, FALLBACK_ATTEMPTS do
            local candidate = randomGrid(n, FALLBACK_DENSITY)
            local row_clues, col_clues = computeClues(candidate, n)
            if not hasEmptyLine(row_clues, col_clues, n)
               and lineSolve(row_clues, col_clues, n, line_cache) then
                best, best_rc, best_cc, how = candidate, row_clues, col_clues, "dense"
                break
            end
        end
    end
    if not best then
        best = randomGrid(n, 2)   -- every cell filled
        best_rc, best_cc = computeClues(best, n)
        how = "full"
    end

    self.solution, self.row_clues, self.col_clues = best, best_rc, best_cc

    self.user        = grid_utils.emptyGrid(n, n, 0)
    self.wrong_marks = grid_utils.emptyBoolGrid(n, n)
    self.undo:clear()
    return how
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

-- Only filled cells matter: an X is an optional annotation, so a cell the
-- solution leaves blank is reported as "empty" and never offered as a hint,
-- and equals() compares filled-ness rather than the exact state.
Hint.install(NonogramBoard, {
    getUser     = function(b, r, c) return b.user[r][c] end,
    getSolution = function(b, r, c) return b.solution[r][c] and 1 or 0 end,
    isEmpty     = function(v) return v == 0 end,
    equals      = function(u, s) return (u == 1) == (s == 1) end,
    setCell     = function(b, r, c, v) return b:setCellState(r, c, v) end,
    blank       = 0,
})

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
    -- for the specs
    _countSolutions = countSolutions,
    _lineSolve      = lineSolve,
    _PASS_BAND      = PASS_BAND,
    _computeClues   = computeClues,
}
