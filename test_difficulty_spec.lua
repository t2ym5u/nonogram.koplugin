-- Difficulty guarantees for Nonogram (see docs/dev/TESTING.md, "Difficulty
-- specs"): every size x level has one solution, solves by line logic alone
-- (checked with an independent cell-by-cell line solver: no guessing), lands
-- in its level's band of line-logic passes, the bands and the averages are
-- ordered, a seed gives the same puzzle, and generation is quick and never
-- reads the clock. Moved here from test_board_spec.lua.
local DIR = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"

package.preload["gettext"] = function()
    return setmetatable({}, { __call = function(_, s) return s end })
end
package.path = DIR .. "common/?.lua;" .. DIR .. "?.lua;" .. package.path

-- Runs fn with os.clock/os.time/os.date counted; returns how many times
-- they were read. The play timer (game-common timer.lua, started when a new
-- round begins) is not part of the generator and is left out.
local function clockReads(fn)
    local oc, ot, od = os.clock, os.time, os.date
    local reads = 0
    local function count()
        local src = debug.getinfo(3, "S").source
        if not src:find("timer%.lua$") then reads = reads + 1 end
    end
    os.clock = function(...) count(); return oc(...) end
    os.time  = function(...) count(); return ot(...) end
    os.date  = function(...) count(); return od(...) end
    local ok, err = pcall(fn)
    os.clock, os.time, os.date = oc, ot, od
    if not ok then error(err, 0) end
    return reads
end

describe("Nonogram difficulty", function()
    local Mod

    setup(function()
        Mod = require("board")
    end)

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

    -- moved from test_board_spec.lua
    it("generates uniquely solvable puzzles quickly at every size and difficulty", function()
        local B = Mod.NonogramBoard
        for _, n in ipairs(Mod.SIZES) do
            for _, diff in ipairs({ "easy", "medium", "hard" }) do
                local worst = 0
                for seed = 1, 6 do
                    math.randomseed(seed * 7919 + n)
                    local b = B:new{ n = n, difficulty = diff }
                    local t0 = os.clock()
                    b:generate(diff)
                    worst = math.max(worst, os.clock() - t0)
                    local count, exhausted = Mod._countSolutions(b.row_clues, b.col_clues, n, 2, 3000000)
                    assert.is_false(exhausted)
                    assert.are.equal(1, count, ("n=%d %s seed %d not unique"):format(n, diff, seed))
                end
                -- generous: under 0.02 s on a desktop under LuaJIT (plain
                -- Lua runs `bit` through a slow shim, so only time LuaJIT)
                if rawget(_G, "jit") then
                    assert.is_true(worst < 0.5, ("n=%d %s took %.2f s"):format(n, diff, worst))
                end
            end
        end
    end)

    -- moved from test_board_spec.lua
    it("every puzzle solves by line logic alone, at every size and difficulty", function()
        local B = Mod.NonogramBoard
        for _, n in ipairs(Mod.SIZES) do
            for _, diff in ipairs({ "easy", "medium", "hard" }) do
                for seed = 1, (n == 15 and 15 or 30) do
                    math.randomseed(seed * 104729 + n)
                    local b = B:new{ n = n, difficulty = diff }
                    local how = b:generate(diff)
                    local tag = ("n=%d %s seed %d"):format(n, diff, seed)
                    assert.are.equal("band", how, tag)
                    local g = naiveLineSolve(b.row_clues, b.col_clues, n)
                    assert.is_truthy(g, tag .. " needs guessing")
                    for r = 1, n do
                        for c = 1, n do
                            assert.are.equal(b.solution[r][c], g[r][c], tag)
                        end
                    end
                end
            end
        end
    end)

    -- moved from test_board_spec.lua
    it("orders the levels by how many passes line logic needs", function()
        local B = Mod.NonogramBoard
        for _, n in ipairs(Mod.SIZES) do
            local prev_max, prev_mean = 0, 0
            for _, diff in ipairs({ "easy", "medium", "hard" }) do
                local band = Mod._PASS_BAND[n][diff]
                assert.is_true(band[1] > prev_max, ("n=%d %s band overlaps"):format(n, diff))
                prev_max = band[2]
                local sum, count = 0, (n == 15 and 15 or 30)
                for seed = 1, count do
                    math.randomseed(seed * 7919 + n)
                    local b = B:new{ n = n, difficulty = diff }
                    b:generate(diff)
                    local solved, passes = Mod._lineSolve(b.row_clues, b.col_clues, n)
                    assert.is_true(solved)
                    assert.is_true(passes >= band[1] and passes <= band[2],
                        ("n=%d %s seed %d: %d passes"):format(n, diff, seed, passes))
                    sum = sum + passes
                end
                assert.is_true(sum / count > prev_mean)
                prev_mean = sum / count
            end
        end
    end)

    -- moved from test_board_spec.lua
    it("gives the same puzzle for the same seed", function()
        local B = Mod.NonogramBoard
        for _, n in ipairs(Mod.SIZES) do
            for _, diff in ipairs({ "easy", "medium", "hard" }) do
                local grids = {}
                for k = 1, 2 do
                    math.randomseed(20261104 + n)
                    local b = B:new{ n = n, difficulty = diff }
                    b:generate(diff)
                    grids[k] = b.solution
                end
                assert.are.same(grids[1], grids[2])
            end
        end
    end)

    it("generation never reads the clock", function()
        local B = Mod.NonogramBoard
        for _, n in ipairs(Mod.SIZES) do
            for _, diff in ipairs({ "easy", "medium", "hard" }) do
                local reads = clockReads(function()
                    math.randomseed(808 + n)
                    B:new{ n = n, difficulty = diff }:generate(diff)
                end)
                assert.are.equal(0, reads, ("n=%d %s read the clock"):format(n, diff))
            end
        end
    end)
end)
