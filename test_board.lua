-- test_board.lua for nonogram.koplugin
-- Run: cd nonogram.koplugin && /opt/homebrew/bin/lua test_board.lua
package.path = "./?.lua;./common/?.lua;" .. package.path

-- Stub gettext
package.loaded["gettext"] = setmetatable({}, {
    __call  = function(_, s) return s end,
    __index = function(_, _) return function(s) return s end end,
})

local ok, err = pcall(function()
    local m = loadfile("board.lua")()
    local NonogramBoard = m.NonogramBoard
    local SIZES         = m.SIZES

    assert(NonogramBoard, "NonogramBoard found")
    assert(type(SIZES) == "table" and #SIZES >= 1, "SIZES table non-empty")

    -- Test 1: Construction
    local b = NonogramBoard:new{ n = 5 }
    assert(b ~= nil, "Board created")
    assert(b.n == 5, "n=5")
    assert(type(b.solution) == "table", "solution table exists")
    assert(type(b.user) == "table", "user table exists")

    -- Test 2: Generate
    b:generate("easy")
    assert(type(b.row_clues) == "table" and #b.row_clues == 5, "row_clues computed")
    assert(type(b.col_clues) == "table" and #b.col_clues == 5, "col_clues computed")
    for r = 1, 5 do
        assert(type(b.row_clues[r]) == "table" and #b.row_clues[r] >= 1,
            "row_clue[" .. r .. "] non-empty")
    end

    -- Test 3: Clue consistency — clues must match solution
    local function computeClues(grid, n)
        local rc, cc = {}, {}
        for r = 1, n do
            local clue, run = {}, 0
            for c = 1, n do
                if grid[r][c] then run = run + 1
                elseif run > 0 then clue[#clue+1] = run; run = 0 end
            end
            if run > 0 then clue[#clue+1] = run end
            rc[r] = #clue > 0 and clue or {0}
        end
        for c = 1, n do
            local clue, run = {}, 0
            for r = 1, n do
                if grid[r][c] then run = run + 1
                elseif run > 0 then clue[#clue+1] = run; run = 0 end
            end
            if run > 0 then clue[#clue+1] = run end
            cc[c] = #clue > 0 and clue or {0}
        end
        return rc, cc
    end

    local rc2, cc2 = computeClues(b.solution, 5)
    for r = 1, 5 do
        assert(#b.row_clues[r] == #rc2[r], "row_clue length matches solution r=" .. r)
        for i = 1, #rc2[r] do
            assert(b.row_clues[r][i] == rc2[r][i],
                "row_clue value matches solution r=" .. r .. " i=" .. i)
        end
    end
    for c = 1, 5 do
        assert(#b.col_clues[c] == #cc2[c], "col_clue length matches solution c=" .. c)
        for i = 1, #cc2[c] do
            assert(b.col_clues[c][i] == cc2[c][i],
                "col_clue value matches solution c=" .. c .. " i=" .. i)
        end
    end

    -- Test 4: toggleCell and user state
    assert(b.user[1][1] == 0, "cell starts at 0")
    b:toggleCell(1, 1)
    assert(b.user[1][1] == 1, "after first toggle: filled")
    b:toggleCell(1, 1)
    assert(b.user[1][1] == -1, "after second toggle: crossed")
    b:toggleCell(1, 1)
    assert(b.user[1][1] == 0, "after third toggle: empty again")

    -- Test 5: setCellState
    b:setCellState(1, 1, 1)
    assert(b.user[1][1] == 1, "setCellState fills")
    b:setCellState(1, 1, -1)
    assert(b.user[1][1] == -1, "setCellState crosses")
    b:setCellState(1, 1, 0)
    assert(b.user[1][1] == 0, "setCellState clears")

    -- Test 6: Win condition — fill solution correctly
    local b2 = NonogramBoard:new{ n = 5 }
    b2:generate("easy")
    for r = 1, 5 do
        for c = 1, 5 do
            if b2.solution[r][c] then
                b2.user[r][c] = 1
            end
        end
    end
    assert(b2:isSolved(), "isSolved when all filled cells match solution")

    -- Test 7: Not solved when a filled cell is missing
    local b3 = NonogramBoard:new{ n = 5 }
    b3:generate("easy")
    -- Find a filled solution cell and don't mark it
    local found = false
    for r = 1, 5 do
        for c = 1, 5 do
            if b3.solution[r][c] then
                -- Only fill all except this one
                for r2 = 1, 5 do
                    for c2 = 1, 5 do
                        if b3.solution[r2][c2] and not (r2 == r and c2 == c) then
                            b3.user[r2][c2] = 1
                        end
                    end
                end
                assert(not b3:isSolved(), "Not solved when a filled cell is missing")
                found = true
                goto done
            end
        end
    end
    ::done::
    -- If no filled cells, isSolved would be true even without marking anything
    -- (all-empty solution is solved by default). Skip assertion if all empty.

    -- Test 8: checkProgress marks wrong cells
    local b4 = NonogramBoard:new{ n = 5 }
    b4:generate("easy")
    -- Mark a cell wrong: mark as filled a solution-empty cell (if any)
    local wrong_r, wrong_c
    for r = 1, 5 do
        for c = 1, 5 do
            if not b4.solution[r][c] then
                wrong_r, wrong_c = r, c; goto found_empty
            end
        end
    end
    ::found_empty::
    if wrong_r then
        b4.user[wrong_r][wrong_c] = 1  -- mark as filled when solution says empty
        b4:checkProgress()
        assert(b4.wrong_marks[wrong_r][wrong_c], "wrong_mark set for incorrectly filled cell")
    end

    -- Test 9: Serialize / load round-trip
    local b5 = NonogramBoard:new{ n = 5 }
    b5:generate("medium")
    b5.user[1][1] = 1
    local data = b5:serialize()
    assert(type(data) == "table", "serialize returns table")
    assert(data.n == 5, "n preserved")
    assert(type(data.row_clues) == "table", "row_clues in serialized data")
    local b6 = NonogramBoard:new{ n = 5 }
    assert(b6:load(data) == true, "load succeeds")
    assert(b6.n == 5, "n preserved after load")
    assert(b6.user[1][1] == 1, "user state preserved after load")

    -- Test 10: Undo
    local b7 = NonogramBoard:new{ n = 5 }
    b7:generate("easy")
    assert(not b7:canUndo(), "canUndo false initially")
    b7:setCellState(1, 1, 1)
    assert(b7:canUndo(), "canUndo true after move")
    b7:undo()
    assert(b7.user[1][1] == 0, "cell restored after undo")
    assert(not b7:canUndo(), "canUndo false after undoing all")

    -- Test 11: getRemainingCells
    local b8 = NonogramBoard:new{ n = 5 }
    b8:generate("easy")
    local total_filled = 0
    for r = 1, 5 do
        for c = 1, 5 do
            if b8.solution[r][c] then total_filled = total_filled + 1 end
        end
    end
    assert(b8:getRemainingCells() == total_filled, "getRemainingCells == total filled initially")

    -- Test 12: 10x10 generation
    local b9 = NonogramBoard:new{ n = 10 }
    b9:generate("hard")
    assert(b9.n == 10, "10x10 generated")
    assert(#b9.row_clues == 10, "10 row clues")
    assert(#b9.col_clues == 10, "10 col clues")

    print("All nonogram tests passed!")
end)
if not ok then
    io.stderr:write("FAIL: " .. tostring(err) .. "\n")
    os.exit(1)
end
