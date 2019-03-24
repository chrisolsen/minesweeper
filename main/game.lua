local Game = {}
Game.__index = Game

function Game.new(context)
    local self = setmetatable({}, Game)
    self.context = context

    -- grid sizes
    self.grid_offset = 10
    self.tile_size = 20

    -- tilemap indices
    self.tile_mine = 11
    self.tile_flag = 11
    self.tile_blank = 12
    self.tile_bomb = 13
    self.tile_boom = 14

    -- tilemap keys
    self.tilemap_id = "#tilemap"
    self.tilemap_layer = "tiles"

    -- state
    self.game_over = false
    self.mine_count = 10
    self.dims = {rows=9, cols=9}
    self.mines_found = 0

    self.tiles = self:generate_mines(self.mine_count, self.dims.rows * self.dims.cols)

    self.remaining = self.dims.rows * self.dims.cols - self.mine_count
    self.timerhandle = timer.delay(1, true, self.update_timer)
    if self.timerhandle == timer.INVALID_TIMER_HANDLE then
        print("invalid timer handle")
    end
    
    msg.post("/ui", "game:reset", { minecount=self.mine_count })

    return self
end


function Game:end_game(win)
    if win then
        msg.post("/ui", "stop:win")
    else
        msg.post("/ui", "stop:lose")
    end
    self.game_over = true
    self:stop_timer()
end 


function Game:tilecoords(x, y)
    local xi = self:get_offset_index(x)
    local yi = self:get_offset_index(y)
    local inbounds = xi>0 and yi>0 and xi<=self.dims.cols and yi<=self.dims.rows
    return xi, yi, inbounds
end


function Game:set_tile_by_index(x, y, index)
    tilemap.set_tile(self.tilemap_id, self.tilemap_layer, x, y, index)
end


function Game:set_tile_by_count(x, y, count)
    self:set_tile_by_index(x, y, count + 1)
end


function Game:get_tile(x, y)
    return tilemap.get_tile(self.tilemap_id, self.tilemap_layer, x, y)
end


function Game:generate_mines(mine_count, tile_count)
    local mines = {}
    local count = mine_count
    local total_count = 0
    math.randomseed(os.time())
    while true do
        local index = math.random(1, tile_count)
        if mines[index] == nil then
            total_count = total_count + 1
            mines[index] = self.tile_mine
            if total_count >= mine_count then
                return mines
            end
        end
    end
end


function Game:tileindex(x, y)
    local index = self.dims.cols*(y-1) + x
    if x < 1 or y < 1 or x > self.dims.cols or y > self.dims.rows then
        return -1
    end
    return index
end


function Game:isbomb(x, y)
    local index = self:tileindex(x, y)
    if index < 1 then
        return false
    end
    return self.tiles[index] == self.tile_mine
end


function Game:get_surrounding_mine_count(x, y)
    local count = 0
    for i=-1,1 do
        for j=-1,1 do
            if not (i==0 and j==0) then
                if self:isbomb(x+i, y+j) then
                    count = count + 1
                end
            end
        end
    end
    return count
end


-- spiders out to all surrounding tiles until tiles with surrounding mines are found
function Game:find_surrounding_tiles(x, y)
    for i=-1,1 do
        for j=-1,1 do
            if not (i==0 and j==0) then
                local xp, yp = x+i, y+j
                local index = self:tileindex(xp, yp)
                local inbounds = xp > 0 and yp > 0 and xp <= self.dims.cols and yp <= self.dims.rows
                local unselected = self.tiles[index] == nil
                if inbounds and unselected then
                    local mine_count = self:get_surrounding_mine_count(xp, yp)
                    self.remaining = self.remaining - 1
                    self:set_tile_by_count(xp, yp, mine_count)
                    self.tiles[index] = mine_count
                    if mine_count == 0 then
                        self:find_surrounding_tiles(xp, yp)
                    end
                end
            end
        end
    end
end


function Game:select_tile(x, y)
    local xt, yt, inbounds = self:tilecoords(x, y)
    if not inbounds then return end 
    if self.game_over then return end

    if self:isbomb(xt, yt) then
        self.game_over = true
        self:set_tile_by_index(xt, yt, self.tile_boom)
        msg.post("/ui", "show:sad")
        msg.post(".", "timer:stop")
    else
        local index = self:tileindex(xt, yt)
        local count = self:get_surrounding_mine_count(xt, yt)

        if self.tiles[index] ~= nil then return end

        self.tiles[index] = count
        self:set_tile_by_count(xt, yt, count)
        if count == 0 then
            self:find_surrounding_tiles(xt, yt)
        end

        self.remaining = self.remaining - 1
        if self.remaining == 0 then
            self:end_game(true)
        end
    end
end


function Game:setflag(x, y)
    local xt, yt, inbounds = self:tilecoords(x, y)
    if not inbounds then return end
    local tile = self:get_tile(xt, yt)
    if tile == self.tile_flag then
        self:set_tile_by_index(xt, yt, self.tile_blank)
        self.mines_found = self.mines_found - 1
        msg.post("/ui", "mine:flag", {value=1})
    elseif tile == self.tile_blank then
        self:set_tile_by_index(xt, yt, self.tile_flag)
        self.mines_found = self.mines_found + 1
        msg.post("/ui", "mine:flag", {value=-1})		
    end

    if self.remaining == 0 and self.mines_found == self.mine_count then
        self.game_over = true
    end
end


function Game:update_timer()
    msg.post("/ui", "time:update")
end


function Game:stop_timer()
    timer.cancel(self.timerhandle)
end


function Game:get_offset_index(offset)
    return math.floor((offset - self.grid_offset) / self.tile_size) + 1
end


return Game