package.path = package.path .. ";../?.lua"
local Json = require("deps/json")

local Storage = {}

function Storage:saveTable(table)
    local file = io.open("savedata", "w")

    if file then
        local contents = Json.encode(table)
        file:write(contents)
        io.close(file)
        return true
    else
        return false
    end
end

function Storage:getTable()
    local file = io.open("savedata", "r")

    if file then
        -- read all contents of file into a string
        local contents = file:read( "*a" )
        local table = Json.decode(contents)
        
        io.close(file)
        return table
    end
    return nil
end

function Storage:addValue(key,value)
    local storagetable = Storage:getTable()
    table.insert(storagetable[key],value)
    Storage:saveTable(storagetable)
end

if Storage:getTable() == nil then
    Storage:saveTable({ ["Channel"] = "0",["Words"] = {},["SuggestedWords"] = {},["SuggestedUsers"] = {} })
end

        
return Storage