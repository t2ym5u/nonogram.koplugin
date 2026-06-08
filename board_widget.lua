local Blitbuffer    = require("ffi/blitbuffer")
local Font          = require("ui/font")
local Geom          = require("ui/geometry")
local GestureRange  = require("ui/gesturerange")
local RenderText    = require("ui/rendertext")
local UIManager     = require("ui/uimanager")

local gw_module        = require("grid_widget_base")
local GridWidgetBase   = gw_module.GridWidgetBase
local drawLine         = gw_module.drawLine
local drawDiagonalLine = gw_module.drawDiagonalLine

local NonogramBoardWidget = GridWidgetBase:extend{
    board      = nil,
    size_ratio = 0.70,
}

function NonogramBoardWidget:init()
    local n = self.board.n
    self.cols = n
    self.rows = n
    GridWidgetBase.init(self)

    local max_row_clue_len = 0
    for r = 1, n do
        local l = #self.board.row_clues[r]
        if l > max_row_clue_len then max_row_clue_len = l end
    end
    local max_col_clue_len = 0
    for c = 1, n do
        local l = #self.board.col_clues[c]
        if l > max_col_clue_len then max_col_clue_len = l end
    end

    self.clue_w = math.ceil(max_row_clue_len * self.cell_w)
    self.clue_h = math.ceil(max_col_clue_len * self.cell_h)

    local total_w = self.clue_w + self.size
    local total_h = self.clue_h + self.size
    self.dimen      = Geom:new{ w = total_w, h = total_h }
    self.paint_rect = Geom:new{ x = 0, y = 0, w = total_w, h = total_h }

    self.grid_ox = self.clue_w
    self.grid_oy = self.clue_h

    local cell_min = math.min(self.cell_w, self.cell_h)
    local clue_size = math.max(8, math.floor(cell_min * 0.55))
    self.clue_face = Font:getFace("cfont", clue_size)

    self.ges_events = {
        Tap = {
            GestureRange:new{
                ges   = "tap",
                range = function() return self.paint_rect end,
            }
        },
        HoldRelease = {
            GestureRange:new{
                ges   = "hold_release",
                range = function() return self.paint_rect end,
            }
        },
    }
end

function NonogramBoardWidget:getCellFromPoint(x, y)
    local local_x = x - self.paint_rect.x - self.grid_ox
    local local_y = y - self.paint_rect.y - self.grid_oy
    if local_x < 0 or local_y < 0 then return nil end
    local col = math.min(self.cols, math.floor(local_x / self.cell_w) + 1)
    local row = math.min(self.rows, math.floor(local_y / self.cell_h) + 1)
    if row < 1 or col < 1 then return nil end
    return row, col
end

function NonogramBoardWidget:onTap(_, ges)
    if not (ges and ges.pos) then return false end
    local row, col = self:getCellFromPoint(ges.pos.x, ges.pos.y)
    if not row then return false end
    if self.onCellAction then self.onCellAction(row, col, false) end
    return true
end

function NonogramBoardWidget:onHoldRelease(_, ges)
    if not (ges and ges.pos) then return false end
    local row, col = self:getCellFromPoint(ges.pos.x, ges.pos.y)
    if not row then return false end
    if self.onCellAction then self.onCellAction(row, col, true) end
    return true
end

function NonogramBoardWidget:refresh()
    local rect = self.paint_rect
    UIManager:setDirty(self, function()
        return "ui", Geom:new{ x = rect.x, y = rect.y, w = rect.w, h = rect.h }
    end)
end

function NonogramBoardWidget:paintTo(bb, x, y)
    if not self.board then return end

    self.paint_rect = Geom:new{ x = x, y = y, w = self.dimen.w, h = self.dimen.h }

    local n      = self.board.n
    local cw     = self.cell_w
    local ch     = self.cell_h
    local ox     = x + self.grid_ox
    local oy     = y + self.grid_oy
    local gsize  = self.size

    bb:paintRect(x, y, self.dimen.w, self.dimen.h, Blitbuffer.COLOR_WHITE)

    local clue_bg = Blitbuffer.COLOR_GRAY_E
    bb:paintRect(x, y, self.clue_w, self.clue_h, clue_bg)
    bb:paintRect(x, y + self.clue_h, self.clue_w, gsize, clue_bg)
    bb:paintRect(x + self.clue_w, y, gsize, self.clue_h, clue_bg)

    local face      = self.clue_face
    local text_color = Blitbuffer.COLOR_BLACK

    for c = 1, n do
        local clue = self.board.col_clues[c]
        local num  = #clue
        local col_x = ox + math.floor((c - 1) * cw)
        for i = 1, num do
            local slot_from_bottom = num - i
            local slot_y = y + self.clue_h - math.floor((slot_from_bottom + 1) * ch)
            if slot_y < y then slot_y = y end
            local cell_cx = col_x + math.floor(cw / 2)
            local cell_cy = slot_y + math.floor(ch / 2)
            local txt = tostring(clue[i])
            local m = RenderText:sizeUtf8Text(0, math.floor(cw), face, txt, true, false)
            local tx = cell_cx - math.floor(m.x / 2)
            local ty = cell_cy - math.floor((m.y_bottom - m.y_top) / 2) - m.y_top
            RenderText:renderUtf8Text(bb, tx, ty, face, txt, true, false, text_color)
        end
    end

    for r = 1, n do
        local clue = self.board.row_clues[r]
        local num  = #clue
        local row_y = oy + math.floor((r - 1) * ch)
        for i = 1, num do
            local slot_from_right = num - i
            local slot_x = x + self.clue_w - math.floor((slot_from_right + 1) * cw)
            if slot_x < x then slot_x = x end
            local cell_cx = slot_x + math.floor(cw / 2)
            local cell_cy = row_y + math.floor(ch / 2)
            local txt = tostring(clue[i])
            local m = RenderText:sizeUtf8Text(0, math.floor(cw), face, txt, true, false)
            local tx = cell_cx - math.floor(m.x / 2)
            local ty = cell_cy - math.floor((m.y_bottom - m.y_top) / 2) - m.y_top
            RenderText:renderUtf8Text(bb, tx, ty, face, txt, true, false, text_color)
        end
    end

    for r = 1, n do
        for c = 1, n do
            local cx = ox + math.floor((c - 1) * cw)
            local cy = oy + math.floor((r - 1) * ch)
            local cew = math.ceil(cw)
            local ceh = math.ceil(ch)
            local state = self.board.user[r][c]

            if state == 1 then
                bb:paintRect(cx, cy, cew, ceh, Blitbuffer.COLOR_BLACK)
            else
                bb:paintRect(cx, cy, cew, ceh, Blitbuffer.COLOR_WHITE)
                if state == -1 then
                    local pad = math.max(2, math.floor(math.min(cew, ceh) / 8))
                    local dlen = math.max(0, math.floor(math.min(cew, ceh) - pad * 2))
                    local thick = math.max(1, math.floor(math.min(cew, ceh) / 12))
                    drawDiagonalLine(bb, cx + pad, cy + pad,        dlen, 1,  1, Blitbuffer.COLOR_BLACK, thick)
                    drawDiagonalLine(bb, cx + pad, cy + ceh - pad,  dlen, 1, -1, Blitbuffer.COLOR_BLACK, thick)
                end
            end

            if self.board.wrong_marks[r][c] then
                local dot = math.max(2, math.floor(math.min(cew, ceh) / 6))
                local pad = math.max(1, math.floor(math.min(cew, ceh) / 10))
                bb:paintRect(cx + cew - pad - dot, cy + pad, dot, dot, Blitbuffer.COLOR_GRAY_4)
            end
        end
    end

    local thin_line = 1
    local thick_line = math.max(2, math.floor(math.min(cw, ch) / 10))

    for i = 0, n do
        local px = ox + math.floor(i * cw)
        local py = oy + math.floor(i * ch)
        local lw = (i == 0 or i == n) and thick_line or thin_line
        drawLine(bb, px, oy, lw, gsize, Blitbuffer.COLOR_BLACK)
        drawLine(bb, ox, py, gsize, lw, Blitbuffer.COLOR_BLACK)
    end

    local bthick = thick_line
    drawLine(bb, x,                   y,                    bthick, self.dimen.h, Blitbuffer.COLOR_BLACK)
    drawLine(bb, x + self.dimen.w - bthick, y,              bthick, self.dimen.h, Blitbuffer.COLOR_BLACK)
    drawLine(bb, x,                   y,                    self.dimen.w, bthick, Blitbuffer.COLOR_BLACK)
    drawLine(bb, x,                   y + self.dimen.h - bthick, self.dimen.w, bthick, Blitbuffer.COLOR_BLACK)
end

return NonogramBoardWidget
