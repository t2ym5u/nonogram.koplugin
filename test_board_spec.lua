local DIR = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"

package.preload["gettext"] = function()
    return setmetatable({}, { __call = function(_, s) return s end })
end
package.path = DIR .. "common/?.lua;" .. DIR .. "?.lua;" .. package.path

describe("NonogramBoard", function()
    local Mod

    setup(function()
        Mod = require("board")
    end)


    local Board = nil
    local function newBoard(n)
        Board = Mod.NonogramBoard
        math.randomseed(42)
        local b = Board:new({ n = n or 5 })
        b:generate()
        return b
    end

    describe("generate", function()
        it("populates row and column clues", function()
            local b = newBoard(5)
            assert.are.equal(5, #b.row_clues)
            assert.are.equal(5, #b.col_clues)
        end)

        it("clues are consistent with the solution", function()
            local b = newBoard(5)
            local n = b.n
            -- Re-compute clues from solution and compare
            for r = 1, n do
                local run, clue = 0, {}
                for c = 1, n do
                    if b.solution[r][c] then
                        run = run + 1
                    elseif run > 0 then
                        clue[#clue + 1] = run; run = 0
                    end
                end
                if run > 0 then clue[#clue + 1] = run end
                if #clue == 0 then clue = {0} end
                assert.are.same(clue, b.row_clues[r],
                    "row " .. r .. " clue mismatch")
            end
        end)

        it("resets user grid to all zeros", function()
            local b = newBoard(10)
            local n = b.n
            for r = 1, n do
                for c = 1, n do
                    assert.are.equal(0, b.user[r][c])
                end
            end
        end)
    end)

    -- 1.5.0: line sets became bit masks (same algorithm, same order, same
    -- puzzles; 15x15 Easy took up to 0.4 s on a desktop). Keep the old
    -- counter here and check the two agree, and that generation stays
    -- unique and quick.
    describe("counter", function()
        -- The pre-1.5.0 counter, verbatim (renamed old_*).
        local function old_enumerateLines(clue, n)
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

        local function old_achievableAt(lines, pos)
            local t, f = false, false
            for _, line in ipairs(lines) do
                if line[pos] then t = true else f = true end
                if t and f then break end
            end
            return t, f
        end

        local function old_filterByAchievable(lines, achievable, n)
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
        local function old_propagate(row_live, col_live, n)
            local changed = true
            while changed do
                changed = false
                for r = 1, n do
                    local achievable = {}
                    for c = 1, n do
                        local t, f = old_achievableAt(col_live[c], r)
                        achievable[c] = { t = t, f = f }
                    end
                    local filtered = old_filterByAchievable(row_live[r], achievable, n)
                    if #filtered == 0 then return false end
                    if #filtered < #row_live[r] then changed = true end
                    row_live[r] = filtered
                end
                for c = 1, n do
                    local achievable = {}
                    for r = 1, n do
                        local t, f = old_achievableAt(row_live[r], c)
                        achievable[r] = { t = t, f = f }
                    end
                    local filtered = old_filterByAchievable(col_live[c], achievable, n)
                    if #filtered == 0 then return false end
                    if #filtered < #col_live[c] then changed = true end
                    col_live[c] = filtered
                end
            end
            return true
        end

        local function old_copyLiveState(row_live, col_live, n)
            local r2, c2 = {}, {}
            for r = 1, n do r2[r] = row_live[r] end
            for c = 1, n do c2[c] = col_live[c] end
            return r2, c2
        end

        local function old_countSolutions(row_clues, col_clues, n, limit, node_budget)
            local row_live, col_live = {}, {}
            for r = 1, n do row_live[r] = old_enumerateLines(row_clues[r], n) end
            for c = 1, n do col_live[c] = old_enumerateLines(col_clues[c], n) end

            local solutions, nodes, exhausted = 0, 0, false

            local function search(row_live, col_live)
                if solutions >= limit or exhausted then return end
                nodes = nodes + 1
                if nodes > node_budget then exhausted = true; return end

                if not old_propagate(row_live, col_live, n) then return end

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
                    local r2, c2 = old_copyLiveState(row_live, col_live, n)
                    if best_is_row then r2[best_idx] = { candidate } else c2[best_idx] = { candidate } end
                    search(r2, c2)
                    if solutions >= limit or exhausted then return end
                end
            end

            search(row_live, col_live)
            return solutions, exhausted, nodes
        end
        it("counts the same solutions as the old counter on random grids", function()
            local cache = { [5] = {}, [10] = {}, [15] = {} }
            for _, n in ipairs({ 5, 10, 15 }) do
                for seed = 1, (n == 15 and 12 or 40) do
                    math.randomseed(seed * 4049 + n)
                    local dens = ({ 0.3, 0.45, 0.55, 0.65, 0.8 })[seed % 5 + 1]
                    local g = {}
                    for r = 1, n do
                        g[r] = {}
                        for c = 1, n do g[r][c] = math.random() < dens end
                    end
                    local rc, cc = Mod._computeClues(g, n)
                    local so, eo, no = old_countSolutions(rc, cc, n, 3, 300000)
                    local sn, en, nn = Mod._countSolutions(rc, cc, n, 3, 300000)
                    assert.are.equal(eo, en)
                    assert.are.equal(so, sn, ("n=%d seed %d"):format(n, seed))
                    -- 1.6.0 propagation only revisits changed lines: same
                    -- search tree, so the same node count
                    assert.are.equal(no, nn, ("n=%d seed %d nodes"):format(n, seed))
                    -- and with the generator's clue -> lines cache
                    local sc, ec, nc = Mod._countSolutions(rc, cc, n, 3, 300000, cache[n])
                    assert.are.same({ so, eo, no }, { sc, ec, nc })
                end
            end
        end)
    end)

    -- 1.6.0: no guessing -- the line solver the generator grades with is
    -- checked against an independent one here; the per-level guarantees
    -- live in test_difficulty_spec.lua.
    describe("line logic", function()
        -- An independent, cell-by-cell line solver (not the bit-mask one in
        -- board.lua): for each row then each column, list every placement
        -- of its clue that agrees with the known cells and settle the cells
        -- they all agree on; repeat until nothing changes. No search.
        local function placements(clue, n, known)
            local res, line = {}, {}
            if clue[1] == 0 then clue = {} end
            local function rec(k, pos)
                if k > #clue then
                    for i = pos, n do line[i] = false end
                    for i = 1, n do
                        if known[i] ~= nil and known[i] ~= line[i] then return end
                    end
                    local cp = {}
                    for i = 1, n do cp[i] = line[i] end
                    res[#res + 1] = cp
                    return
                end
                local rest = 0
                for j = k + 1, #clue do rest = rest + clue[j] + 1 end
                for st = pos, n - clue[k] + 1 - rest do
                    for i = pos, st - 1 do line[i] = false end
                    for i = st, st + clue[k] - 1 do line[i] = true end
                    local nx = st + clue[k]
                    if nx <= n then line[nx] = false end
                    -- prune as soon as the placed prefix contradicts
                    local ok = true
                    for i = pos, math.min(nx, n) do
                        if known[i] ~= nil and known[i] ~= line[i] then ok = false; break end
                    end
                    if ok then rec(k + 1, nx + 1) end
                end
            end
            rec(1, 1)
            return res
        end
        local function naiveLineSolve(rc, cc, n)
            local g = {}
            for r = 1, n do g[r] = {} end
            local changed = true
            while changed do
                changed = false
                for pass = 1, 2 do
                    for i = 1, n do
                        local known = {}
                        for j = 1, n do
                            if pass == 1 then known[j] = g[i][j] else known[j] = g[j][i] end
                        end
                        local P = placements(pass == 1 and rc[i] or cc[i], n, known)
                        if #P == 0 then return nil end
                        for j = 1, n do
                            if known[j] == nil then
                                local v, all = P[1][j], true
                                for k = 2, #P do
                                    if P[k][j] ~= v then all = false; break end
                                end
                                if all then
                                    changed = true
                                    if pass == 1 then g[i][j] = v else g[j][i] = v end
                                end
                            end
                        end
                    end
                end
            end
            for r = 1, n do
                for c = 1, n do
                    if g[r][c] == nil then return nil end
                end
            end
            return g
        end

        it("agrees with an independent line solver on random grids", function()
            for _, n in ipairs({ 5, 10, 15 }) do
                for seed = 1, (n == 15 and 20 or 60) do
                    math.randomseed(seed * 31 + n)
                    local dens = ({ 0.4, 0.5, 0.6, 0.7 })[seed % 4 + 1]
                    local g = {}
                    for r = 1, n do
                        g[r] = {}
                        for c = 1, n do g[r][c] = math.random() < dens end
                    end
                    local rc, cc = Mod._computeClues(g, n)
                    local solved = Mod._lineSolve(rc, cc, n)
                    assert.are.equal(naiveLineSolve(rc, cc, n) ~= nil, solved,
                        ("n=%d seed %d"):format(n, seed))
                end
            end
        end)
    end)

    describe("setCellState / toggleCell", function()
        it("setCellState stores the given state", function()
            local b = newBoard(5)
            local ok = b:setCellState(1, 1, 1)
            assert.is_true(ok)
            assert.are.equal(1, b.user[1][1])
        end)

        it("toggleCell cycles 0 → 1 → -1 → 0", function()
            local b = newBoard(5)
            assert.are.equal(0, b.user[3][3])
            b:toggleCell(3, 3)
            assert.are.equal(1, b.user[3][3])
            b:toggleCell(3, 3)
            assert.are.equal(-1, b.user[3][3])
            b:toggleCell(3, 3)
            assert.are.equal(0, b.user[3][3])
        end)

        it("setCellState is a no-op when state unchanged", function()
            local b = newBoard(5)
            b.user[1][1] = 1
            local ok = b:setCellState(1, 1, 1)
            assert.is_true(ok)
            assert.is_false(b:canUndo(), "no-op should not push undo")
        end)
    end)

    describe("undo", function()
        it("canUndo is false on a fresh board", function()
            local b = newBoard(5)
            assert.is_false(b:canUndo())
        end)

        it("restores previous state after toggleCell", function()
            local b = newBoard(5)
            b:toggleCell(2, 2)
            assert.are.equal(1, b.user[2][2])
            local ok = Board.undo(b)  -- b.undo field (UndoStack) shadows the :undo() method
            assert.is_true(ok)
            assert.are.equal(0, b.user[2][2])
        end)

        it("undo returns false when nothing to undo", function()
            local b = newBoard(5)
            local ok, msg = Board.undo(b)
            assert.is_false(ok)
            assert.is_not_nil(msg)
        end)
    end)

    describe("isSolved", function()
        it("returns false for a fresh board", function()
            local b = newBoard(5)
            assert.is_false(b:isSolved())
        end)

        it("returns true when user matches solution exactly", function()
            local b = newBoard(5)
            local n = b.n
            for r = 1, n do
                for c = 1, n do
                    b.user[r][c] = b.solution[r][c] and 1 or 0
                end
            end
            assert.is_true(b:isSolved())
        end)

        it("returns false when a filled cell is wrong", function()
            local b = newBoard(5)
            local n = b.n
            for r = 1, n do
                for c = 1, n do
                    b.user[r][c] = b.solution[r][c] and 1 or 0
                end
            end
            -- Flip one cell
            b.user[1][1] = b.solution[1][1] and 0 or 1
            assert.is_false(b:isSolved())
        end)
    end)

    describe("checkProgress", function()
        it("marks a wrongly-filled cell", function()
            local b = newBoard(5)
            -- Find an empty solution cell and mark it filled
            local r, c
            for rr = 1, b.n do
                for cc = 1, b.n do
                    if not b.solution[rr][cc] then r, c = rr, cc; goto done end
                end
            end
            ::done::
            b.user[r][c] = 1  -- filled, but solution says empty
            b:checkProgress()
            assert.is_true(b.wrong_marks[r][c])
        end)

        it("marks a wrongly-crossed cell", function()
            local b = newBoard(5)
            -- Find a filled solution cell and mark it crossed
            local r, c
            for rr = 1, b.n do
                for cc = 1, b.n do
                    if b.solution[rr][cc] then r, c = rr, cc; goto done end
                end
            end
            ::done::
            b.user[r][c] = -1  -- crossed, but solution says filled
            b:checkProgress()
            assert.is_true(b.wrong_marks[r][c])
        end)
    end)

    describe("getRemainingCells", function()
        it("counts unfilled solution cells", function()
            local b = newBoard(5)
            local n = b.n
            local expected = 0
            for r = 1, n do
                for c = 1, n do
                    if b.solution[r][c] then expected = expected + 1 end
                end
            end
            assert.are.equal(expected, b:getRemainingCells())
        end)

        it("decreases when a solution cell is filled", function()
            local b = newBoard(5)
            local before = b:getRemainingCells()
            local r, c
            for rr = 1, b.n do
                for cc = 1, b.n do
                    if b.solution[rr][cc] then r, c = rr, cc; goto done end
                end
            end
            ::done::
            b.user[r][c] = 1
            assert.are.equal(before - 1, b:getRemainingCells())
        end)
    end)

    describe("serialize / load", function()
        it("round-trips board state", function()
            local b = newBoard(5)
            b:toggleCell(1, 1)
            local data = b:serialize()

            local b2 = Board:new({ n = 5 })
            b2:generate()
            local ok = b2:load(data)
            assert.is_true(ok)
            assert.are.equal(b.n, b2.n)
            assert.are.equal(b.user[1][1], b2.user[1][1])
            assert.are.same(b.row_clues, b2.row_clues)
            assert.are.same(b.col_clues, b2.col_clues)
        end)

        it("load rejects boards with invalid n", function()
            local b = newBoard(5)
            local data = b:serialize()
            data.n = 7  -- not a valid size
            local b2 = Board:new({ n = 5 })
            local ok = b2:load(data)
            assert.is_false(ok)
        end)

        it("load returns false for nil data", function()
            local b = newBoard(5)
            assert.is_false(b:load(nil))
        end)
    end)
end)
