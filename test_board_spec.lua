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
