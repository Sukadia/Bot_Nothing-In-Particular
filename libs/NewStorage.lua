package.path = package.path .. ";../?.lua"
local Json = require("deps/json")

local Storage = {}

function Storage:getData()
    local file = io.open("newsavedata", "r")

    if file then
        -- read all contents of file into a string
        local contents = file:read("*a")
        local table = Json.decode(contents)
        
        io.close(file)
        return table
    end
    return nil
end

function Storage:save(data)
    local file = io.open("newsavedata", "w")
    if file then
        file:write(Json.encode(data))
        io.close(file)
        return true
    else
        return false
    end
end




return Storage
