--A boss battle channel where it's all the users in the server against the channel, perhaps win an ability at the end, win gear or moves?
--A channel where you can inflict something either on the person above or below

--Do not load songs while paused so there's no required delay between skips (if you pause, that is)
--Expand playlist feature with a queue overview, loop playlist, perhaps save default settings per-user
--Make code look neater and not so spread out, specifically with edits
----Make a function that edits a singular part of an embed for the controller update, reads given message to keep values
--Implement way to play audio through direct link? (May have to wait for Discordia 3.0)
--Maybe don't download highest quality of youtube audio to reduce load time?



-- Dependencies


local Discordia = require("discordia")
local Client = Discordia.Client()
local Enum = Discordia.enums
local Permissions = Discordia.Permissions()
local Json = require("json")
local Coro = require("coro-http")
local Storage = require("NewStorage")


-- Config


local DevMode = false
local BotToken = io.open("token","r"):read("*a")
local ServerId = "669338665956409374"
local OwnerId = "143172810221551616"
local SaveInterval = 5 --Minutes between bot data being saved, excluding newword selection
local SpamM, SpamS = 3, 5 --Messages/Second for Spam filter
local NewW, NewU = 3, 2 --New Random / User Suggested Words
local CountUpdate = 2 --Minutes between count message updating
local ChannelPerms = {["type"]=Permissions.fromMany(Enum.permission.readMessageHistory,Enum.permission.readMessages,Enum.permission.sendMessages),
    ["fuck-vowels"]=Permissions.fromMany(Enum.permission.readMessageHistory,Enum.permission.readMessages,Enum.permission.sendMessages),
    ["fuck-everything"]=Permissions.fromMany(Enum.permission.readMessageHistory,Enum.permission.readMessages,Enum.permission.sendMessages),
    ["message-counting"]=Permissions.fromMany(Enum.permission.readMessageHistory,Enum.permission.readMessages,Enum.permission.sendMessages),
    ["images"]=Permissions.fromMany(Enum.permission.readMessageHistory,Enum.permission.readMessages,Enum.permission.sendMessages,Enum.permission.attachFiles),
    ["speak"]=Permissions.fromMany(Enum.permission.readMessages,Enum.permission.connect,Enum.permission.speak,Enum.permission.useVoiceActivity)}
local StartingData = {["CheckUses"]=0,["Inventory"]={},["State"]="Normal"}


-- Variables


local storagedata = Storage:getData()
if storagedata == nil then -- If no data was loaded, populate storagedata with default values
    storagedata = {
        ["WhitelistedWords"]={}, --{ "word1", ... }
        ["SuggestedWords"]={},   --{ {"userid", "word"}, ... }
        ["CountChannel"]={},     --{ ["Prestige"]=level, ["CountMessage"]=messageid ["Count"]=nextlength, ["LastUser"]=userid, ["Counters"]={ {UserId, Count}, ... }, ["FailedUser"]=userid, ["LastMessage"]=messageid }
        ["PlayerData"]={},       --{ ["UserId"]=StartingDataConfig, ... }
        ["WordCount"]={},        --{ {word, #ofuses}, ...}
        ["LastSaved"]={},        --{ timesaved, closedproperly?, silentrestart? }
        ["CheckUsers"]={},       --{ "userid", ... }
    }
end

local spamdata = {}                          --{ ["UserId"]={messagetime, ... }, ... }  --Spam Detection
local commanduse = {}                        --{ ["UserId"]="command", ... }            --Bypass ability
local lastmessage = {}                       --{ ["UserId"]="lastmessage", ... }        --Multiple message bypass filter
local suggestbuffer = {}                     --{ "userid", ... }                        --Suggestion 60 second change
local images = {}                            --{ "artlink", ... }                       --Indexed art links


-- Global Functions


local function dump(o) --Debug function for printing tables
   if type(o) == 'table' then
      local s = '{ '
      for k,v in pairs(o) do
         if type(k) ~= 'number' then k = '"'..k..'"' end
         s = s .. '['..k..'] = ' .. dump(v) .. ','
      end
      print(s .. '} ')
   else
      return tostring(o)
   end
end

local function round(num, numDecimalPlaces) --Number rounding
    local mult = 10^(numDecimalPlaces or 0)
    return math.floor(num * mult + 0.5) / mult
end

local timer = require("timer") --Wait a certain amount of seconds
local function wait(seconds)
    timer.sleep(seconds*1000)
end

local function split(text) --Split all words (separated by spaces) into a table of words
    local words = {}
    for word in text:gmatch("%S+") do table.insert(words, word) end
    return words
end

local function listItems(table,andbool) --Turns a table of strings into one string with commas and "and"s
    local string = ""
    if #table == 1 then
        return table[1]
    elseif andbool and #table == 2 then
        return table[1].." and "..table[2]
    end
    for i, item in pairs(table) do
        if andbool and i == #table then
            string = string.."and "..item.."--"
        else
            string = string..item..", "
        end
    end
    return string.sub(string,1,-3)
end

local function inTable(table,item) --Check if an item is in a table
    for i, thing in pairs(table) do
        if item == thing then
            return i
        end
    end
    return false
end

local function isEmoji(string) --Check if a string would be formatted as an emoji in Discord
    for i, emoji in pairs(Server.emojis) do
        if "<:"..emoji.hash..">" == string or "<a:"..emoji.hash..">" == string then
            return true
        end
    end
    return false
end


-- Bot Functions


local function send(reciever,text,embedinfo) --Send a formatted DM/message, embedinfo formatted ["Title"] ["Color"] ["Text"] ["Image"] ["FooterImage"] ["FooterText"]
    local channel = reciever
    if type(reciever) == "string" then --if given userid, get DM
        channel = Client:getUser(reciever):getPrivateChannel()
    end
    if embedinfo == nil then
        return channel:send(text)
    else
        embedinfo["Color"] = embedinfo["Color"] or {0,255,255}
        return channel:send{content=text,embed={title=embedinfo["Title"],color=Discordia.Color.fromRGB(embedinfo["Color"][1],embedinfo["Color"][2],embedinfo["Color"][3]).value,description=embedinfo["Text"],image={url=embedinfo["ImageUrl"]},footer={icon_url=embedinfo["FooterImage"],text=embedinfo["FooterText"]}}}
    end
end

local function edit(message,text,embedinfo) --Edit a sent message, same embedinfo
    if embedinfo == nil then
        message:update(message)
    else
        embedinfo["Color"] = embedinfo["Color"] or {0,255,255}
        message:update{content=text,embed={title=embedinfo["Title"],color=Discordia.Color.fromRGB(embedinfo["Color"][1],embedinfo["Color"][2],embedinfo["Color"][3]).value,description=embedinfo["Text"],image={url=embedinfo["ImageUrl"]},footer={icon_url=embedinfo["FooterImage"],text=embedinfo["FooterText"]}}}
    end
end

local function getResponse(channel,timeout) --Wait (timeout) seconds for a response in (channel)
    local response = false
    if channel.type == Enum.channelType.private then
        storagedata["PlayerData"][channel.recipient.id]["State"] = "Command"
    end
    if timeout ~= nil then
        timeout = timeout*1000
    end
    Client:waitFor("messageCreate",timeout,function(message)
        if message.channel == channel and not message.author.bot then
            response = message.content
            return true
        end
    end)
    if channel.type == Enum.channelType.private then
        storagedata["PlayerData"][channel.recipient.id]["State"] = "Normal"
    end
    return response
end

local function updatePerms(userid,channels,permtype) --Update a user/everyone's perms for channels
    local role
    if userid == "everyone" then --get @everyone role if string is "everyone"
        role = Server.defaultRole
    else
        role = Server:getMember(userid)
    end
    
    local function setRolePerms(channel)
        local RolePerms = channel:getPermissionOverwriteFor(role)
        local PermObject
        if permtype == "on" then
            if userid ~= "everyone" then
                RolePerms:delete()
                return
            else
                PermObject = ChannelPerms[channel.name]
            end
        elseif permtype == "off" then
            PermObject = Permissions.fromMany(Enum.permission.readMessageHistory,Enum.permission.readMessages)
            if userid ~= "everyone" then
                RolePerms:denyPermissions(Enum.permission.sendMessages)
                return
            end
        elseif permtype == "noaccess" then
            RolePerms:denyPermissions(Enum.permission.readMessages)
            return
        elseif permtype == "read" then
            PermObject = Permissions.fromMany(Enum.permission.readMessageHistory,Enum.permission.readMessages)
        elseif permtype == "clear" then
            RolePerms:delete()
            return
        end
        RolePerms:setAllowedPermissions(PermObject)
    end
    
    if type(channels) == "table" then --if given a table of channels, change perms for all of them
        for i, channel in pairs(channels) do
            setRolePerms(Channels[channel])
        end
    else
        setRolePerms(Channels[channels])
    end
end

local function ping(pingtype) --Ghost ping those who have opted into (pingtype) through the reactions
    local PingReactions = Channels["help"]:getMessage("719779244586172458").reactions
    local ReactionName, pingstring, PingUsers
    if pingtype == "important" then
        ReactionName, pingstring = "1️⃣", "[Important]"
    elseif pingtype == "majorupdate" then
        ReactionName, pingstring = "2️⃣", "[Major Update]"
    elseif pingtype == "majorpoll" then
        ReactionName, pingstring = "3️⃣", "[Major Poll]"
    elseif pingtype == "minorupdate" then
        ReactionName, pingstring = "4️⃣", "[Minor Update]"
    elseif pingtype == "minorpoll" then
        ReactionName, pingstring = "5️⃣", "[Minor Poll]"
    elseif pingtype == "testing" then
        ReactionName, pingstring = "🛠️", "[Testing]"
    end
    local OnlineOnlyUsers
    for i, reaction in pairs(PingReactions) do
        if reaction.emojiName == ReactionName then
            PingUsers = reaction:getUsers() --"You must call this method again to guarantee that the objects are up to date."
            PingUsers = reaction:getUsers()
            break
        end
        if reaction.emojiName == "🟢" then --green circle reaction
            OnlineOnlyUsers = reaction:getUsers()
            OnlineOnlyUsers = reaction:getUsers()
        end
    end
    for i, user in pairs(PingUsers) do
        local onlineonly = false
        for v, onlineuser in pairs(OnlineOnlyUsers) do
            if onlineuser == user then
                onlineonly = true
                if Server:getMember(user.id) ~= nil then
                    if Server:getMember(user.id).status == "online" then
                        pingstring = pingstring.." <@"..user.id..">"
                    end
                end
                break
            end
        end
        if not onlineonly then
            pingstring = pingstring.." <@"..user.id..">"
        end
    end
    local message = send(Channels["important"],pingstring)
    wait(2)
    message:delete()
end

local function spamSensor(userid) --Log that a user has talked, mute if talking too fast
    if spamdata[userid] == nil then
        spamdata[userid] = {os.time()}
        return
    end
    if spamdata[userid] == "MuteProcess" then
        return
    end
    
    local temp = {}
    for i, time in pairs(spamdata[userid]) do
        if (time + SpamS) > os.time() then
            table.insert(temp,time)
        end
    end
    spamdata[userid] = temp
    table.insert(spamdata[userid],os.time())
    if #spamdata[userid] > SpamM then
        spamdata[userid] = "MuteProcess"
        updatePerms(userid,{"type","fuck-vowels","fuck-everything","message-counting","images","speak"},"off")
        spamdata[userid] = "Muted"
        send(userid,"Yikes, just got a complaint from the higher-ups:",{["Title"]="Muted for 60 seconds",["Color"]={255,0,0},["Text"]="You've sent more than "..SpamM.." messages in the past "..SpamS.." seconds.\n\nYou have exceeded the message limit. You are now muted for **60 seconds**."})
        wait(60)
        spamdata[userid] = {}
        updatePerms(userid,{"type","fuck-vowels","fuck-everything","message-counting","images","speak"},"on")
        send(userid,"Okay, those 60 seconds are up. Be more careful next time.",{["Title"]="Unmuted",["Color"]={0,255,0},["Text"]="You have been unmuted and are allowed to type again."})
        do return end
    end
end

local function newWords() --Whitelist new words
    local wordsneeded = NewW
    local newwordtext = ""
    while wordsneeded ~= 0 do
        local result, body, randomwords
        local success, err = pcall(function()
            local result, body = Coro.request("GET","https://random-word-api2.herokuapp.com/word?number=20")
            randomwords = Json.decode(body)
        end)
        if success then
            local newrandomwords = {}
            for i, word in pairs(randomwords) do
                if wordsneeded == 0 then
                    break
                end
                if not inTable(storagedata["WhitelistedWords"],word) then
                    wordsneeded = wordsneeded - 1
                    table.insert(storagedata["WhitelistedWords"],word)
                    table.insert(newrandomwords,"**"..word.."**")
                end
            end
            newwordtext = listItems(newrandomwords,true).." were randomly selected and whitelisted."
        else
            wordsneeded = 0
            newwordtext = "Random words couldn't be selected due to an API error."
        end
    end
    local totalsubmissions = #storagedata["SuggestedWords"]
    if totalsubmissions == 0 then
        send(Channels["type"],"Damn, no suggestions?",{["Title"]="New Words",["Color"]={0,255,255},["Text"]="New words have been added to the whitelist.\n\n"..newwordtext.."\nNo user suggestions were collected, so none were whitelisted."})
    elseif totalsubmissions == 1 then
        table.insert(storagedata["WhitelistedWords"],storagedata["SuggestedWords"][1][2])
        print(storagedata["SuggestedWords"][1][1].." whitelisted "..storagedata["SuggestedWords"][1][2])
        send(Channels["type"],"Huh, only one submission.",{["Title"]="New Words",["Color"]={0,255,255},["Text"]="New words have been added to the whitelist.\n\n"..newwordtext.."\n**"..storagedata["SuggestedWords"][1][2].."** was the only submission."})
    else
        local num1 = math.random(1,totalsubmissions) -- Select the first word to be whitelisted
        local word1 = storagedata["SuggestedWords"][num1][2]
        print(storagedata["SuggestedWords"][num1][1].." whitelisted "..word1)
        table.insert(storagedata["WhitelistedWords"],word1)
        for i = #storagedata["SuggestedWords"], 1, -1 do -- Remove word from list of suggested words
            if storagedata["SuggestedWords"][i][2] == word1 then
                table.remove(storagedata["SuggestedWords"],i)
            end
        end

        if NewU == 1 then
            send(Channels["type"],"Here's the new words:",{["Title"]="New Words",["Color"]={0,255,255},["Text"]="New words have been added to the whitelist.\n\n"..newwordtext.."\n**"..word1.."** was selected from "..totalsubmissions.." submissions."})
        elseif #storagedata["SuggestedWords"] == 0 then
            send(Channels["type"],"Dang, a unanimous decision? That never happens.",{["Title"]="New Words",["Color"]={0,255,255},["Text"]="New words have been added to the whitelist.\n\n"..newwordtext.."\n**"..word1.."** was unanimously selected from "..totalsubmissions.." submissions."})
        else
            local newwhitelistedwords = {"**"..word1.."**"} -- Array of new whitelisted words, used for message
            
            while #storagedata["SuggestedWords"] > 0 and #newwhitelistedwords ~= NewU do -- Whitelist remaining words and add them to the array
                local num2 = math.random(1,#storagedata["SuggestedWords"])
                local word2 = storagedata["SuggestedWords"][num2][2] -- Find a new word to be whitelisted
                print(storagedata["SuggestedWords"][num2][1].." whitelisted "..word2)
                table.insert(storagedata["WhitelistedWords"],word2) -- Adds word to whitelisted words and the new whitelisted words array
                table.insert(newwhitelistedwords,"**"..word2.."**")
                for i = #storagedata["SuggestedWords"], 1, -1 do -- Prevents word from being whitelisted multiple times
                    if storagedata["SuggestedWords"][i][2] == word2 then
                        table.remove(storagedata["SuggestedWords"],i)
                    end
                end
            end
            
            if #newwhitelistedwords < NewU then -- Less than max amount was whitelisted
                local missedplural = "s"
                if (NewU-#newwhitelistedwords) == 1 then
                    missedplural = ""
                end
                if #newwhitelistedwords ~= totalsubmissions then -- Less than max whitelisted, but some words were the same
                    send(Channels["type"],"Huh, looks like there were some identical submissions.",{["Title"]="New Words",["Color"]={0,255,255},["Text"]="New words have been added to the whitelist.\n\n"..newwordtext.."\n"..listItems(newwhitelistedwords,true).." were selected from "..totalsubmissions.." submissions."})
                else
                    send(Channels["type"],"Darn, missed the chance for "..(NewU-#newwhitelistedwords).." word"..missedplural.." being whitelisted.",{["Title"]="New Words",["Color"]={0,255,255},["Text"]="New words have been added to the whitelist.\n\n"..newwordtext.."\n"..listItems(newwhitelistedwords,true).." were the only submissions."})
                end
            else -- Max amount of words whitelisted
                send(Channels["type"],"Here's the new words:",{["Title"]="New Words",["Color"]={0,255,255},["Text"]="New words have been added to the whitelist.\n\n"..newwordtext.."\n"..listItems(newwhitelistedwords,true).." were selected from "..totalsubmissions.." submissions."})
            end
        end
    end
    table.sort(storagedata["WhitelistedWords"])
    storagedata["SuggestedWords"] = {}
end

local function randomEvent() --Calulate chance/perform a random event
    local chance = math.random(1,1000)/10
    local randomword = storagedata["WhitelistedWords"][math.random(1,#storagedata["WhitelistedWords"])]
    
    if chance <= 1 then
        send(Channels["type"],"Oooh, this one is a spicy ability.",{["Title"]="[1%] Event",["Color"]={0,255,255},["Text"]="A random event has appeared- these have a chance to appear every hour, according to their likelihood percentage.\n\nThe next person to say **"..randomword.."** will receive one message bypass."})
        local collected = Client:waitFor("messageCreate",600*1000,function(message)
            if message.channel == Channels["type"] and not message.author.bot then
                if string.lower(message.content) == randomword then
                    table.insert(storagedata["PlayerData"][message.author.id]["Inventory"],"bypass")
                    send(Channels["type"],"The power is in your hands now.",{["Title"]="Event Ended",["Color"]={0,255,255},["Text"]="**"..message.author.username.."** collected the bypass ability.\n\nCheck your `inventory` to use it."})
                    return true
                end
            end
        end)
        if not collected then
            send(Channels["type"],"Damn, there goes that bypass.",{["Title"]="Event Ended",["Color"]={0,255,255},["Text"]="No one collected the ability within 10 minutes."})
        end
    elseif chance <= 5 then
        send(Channels["type"],"An automatically whitelisted word? Nice.",{["Title"]="[4%] Event",["Color"]={0,255,255},["Text"]="A random event has appeared- these have a chance to appear every hour, according to their likelihood percentage.\n\nThe next person to say **"..randomword.."** will be able to automatically whitelist a word."})
        local collected = Client:waitFor("messageCreate",600*1000,function(message)
            if message.channel == Channels["type"] and not message.author.bot then
                if string.lower(message.content) == randomword then
                    table.insert(storagedata["PlayerData"][message.author.id]["Inventory"],"suggest")
                    send(Channels["type"],"Use that thing wisely.",{["Title"]="Event Ended",["Color"]={0,255,255},["Text"]="**"..message.author.username.."** collected the whitelist ability.\n\nCheck your `inventory` to use it."})
                    return true
                end
            end
        end)
        if not collected then
            send(Channels["type"],"No one claimed it? Tough luck.",{["Title"]="Event Ended",["Color"]={0,255,255},["Text"]="No one collected the ability within 10 minutes."})
        end
    end
end

local wordpicktime
local function timeUntilChoice() --Gives amount of time until word selection as readable string
    local minutesuntil = (wordpicktime - os.time())/60
    if minutesuntil > 60 then
        return round(minutesuntil/60,1).." hours"
    end
    return round(minutesuntil).." minutes"
end


-- Loops


coroutine.wrap(function() --Word selection loop, also resets check uses
    local hourspassed = 0
    while true do
        wordpicktime = os.time()+(21600-(os.time()%21600))
        local timeleft = wordpicktime - os.time()
        print(timeleft.." - "..timeUntilChoice())
        if timeleft > 10800 then
            wait(timeleft - 10800)
            send(Channels["type"],"Three more hours until new words are selected.")
            wait(7200)
            send(Channels["type"],"There is one hour left until the new words are selected, maybe `suggest` something if you haven't?")
            wait(3000)
            send(Channels["type"],"Ten more minutes are left until the new word selection, make sure you've suggested something.")
        elseif timeleft > 3600 then
            wait(timeleft - 3600)
            send(Channels["type"],"There is one hour left until the new words are selected, maybe `suggest` something if you haven't?")
            wait(3000)
            send(Channels["type"],"Ten more minutes are left until the new word selection, make sure you've suggested something.")
        elseif timeleft > 600 then
            wait(timeleft - 600)
            send(Channels["type"],"Ten more minutes are left until the new word selection, make sure you've suggested something.")
        end
        wait(3600-(os.time()%3600))
        newWords()
        hourspassed = hourspassed + 6
        if hourspassed == 24 then
            hourspassed = 0
            for i, userid in pairs(storagedata["CheckUsers"]) do
                storagedata["PlayerData"][userid]["CheckUses"] = 0
            end
            storagedata["CheckUsers"] = {}
        end
    end
end)()

coroutine.wrap(function() --Random selection loop
    wait(3600-(os.time()%3600))
    while true do
        local checktime = math.random(1,5)*10
        wait(checktime*60)
        coroutine.wrap(randomEvent)()
        wait(3600-(os.time()%3600))
    end
end)()

coroutine.wrap(function() --Save data loop, checks for internet outage
    if not DevMode then
    local internetwasdown = false
    while true do
        wait(SaveInterval*60)
        local internettest
        if Channels ~= nil then
            internettest = Channels["important"]:getLastMessage()
        else
            internettest = nil
        end
        if internettest == nil and internetwasdown then
            print("Internet connection is still compromised.")
        elseif internettest == nil then
            print("Internet connection compromised.")
            internetwasdown = true
            Storage:save(storagedata)
        else
            internetwasdown = false
            storagedata["LastSaved"][1] = os.time()
            Storage:save(storagedata)
        end
    end
    end
end)()

coroutine.wrap(function() --Count update message loop
    while true do
        wait((CountUpdate*60)-os.time()%(CountUpdate*60))
        if countingfilter and Channels ~= nil then
            local neednewmessage = false
            if storagedata["CountChannel"]["CountMessage"] ~= nil and Channels["message-counting"] ~= nil then
                local updatemessage = Channels["message-counting"]:getMessage(storagedata["CountChannel"]["CountMessage"])
                if updatemessage ~= nil then
                    if updatemessage ~= Channels["message-counting"]:getLastMessage() or not string.match(updatemessage.content,"**"..storagedata["CountChannel"]["Count"].."**") then
                        updatemessage:delete()
                        neednewmessage = true
                    end
                else
                    neednewmessage = true
                end
            else
                neednewmessage = true
            end
            if neednewmessage then
                if storagedata["CountChannel"]["Count"] == 1 then
                    storagedata["CountChannel"]["CountMessage"] = send(Channels["message-counting"],"_ _\nTo start the counting, the next message should be **1** character long.").id
                else
                    local progressbar = ""
                    for i=1, math.floor(storagedata["CountChannel"]["Count"]-1)/200 do
                        progressbar = progressbar.."▰"
                    end
                    for i=1, 10-math.floor(storagedata["CountChannel"]["Count"]-1)/200 do
                        progressbar = progressbar.."▱"
                    end

                    local deletenotice = ""
                    if storagedata["CountChannel"]["LastMessage"] ~= "0" then
                        if Channels["message-counting"]:getMessage(storagedata["CountChannel"]["LastMessage"]) == nil then
                            deletenotice = "\n\n**Notice:** The last counter deleted their message. Use the `count` command to verify your message length."
                        end
                    end
                    storagedata["CountChannel"]["CountMessage"] = send(Channels["message-counting"],"The next message should be **"..storagedata["CountChannel"]["Count"].."** characters long.\n\nProgress to 2000:\n"..progressbar.." "..round((storagedata["CountChannel"]["Count"]-1)/20,2).."%"..deletenotice).id
                end
            end
        end
    end
end)()


-- Listeners


Client:on("ready", function()
    
    Server = Client:getGuild(ServerId)
    
    --Gets all server channels in Channels[channelname] format
    Channels = {}
    for i, channel in pairs(Server.textChannels) do
        Channels[channel.name] = channel
    end
    for i, channel in pairs(Server.voiceChannels) do
        Channels[channel.name] = channel
    end
    
    if storagedata["LastSaved"][2] == false then
        if os.time()-storagedata["LastSaved"][1] > 600 then
            send(Channels["type"],"The bot lost internet connection sometime between "..os.date("%I:%M:%S %p", storagedata["LastSaved"][1]).." and "..os.date("%I:%M:%S %p", storagedata["LastSaved"][1]+(SaveInterval*60)).." PDT. Save data was not affected.\n\nIf you've performed any actions between then and now, the bot may not have responded.\n\n<@"..OwnerId..">")
        else
            send(Channels["type"],"The bot has crashed. Save data between "..os.date("%I:%M:%S %p", storagedata["LastSaved"][1]).." and "..os.date("%I:%M:%S %p").." PDT was lost.\n\nIf you've performed any actions between then, you will have to do them again.\n\n<@"..OwnerId..">")
        end
    else
        if storagedata["LastSaved"][3] == false then
            send(Channels["type"],"Restart successful.")
        end
        storagedata["LastSaved"][2] = false
        storagedata["LastSaved"][3] = false
    end
    
    
    local speakers = {}
    local status = "Nothing"
    local speakcontrols = Channels["voice-controls"]:getFirstMessage()
    if speakcontrols then
        speakcontrols:clearReactions()
        edit(speakcontrols,"",{["Title"]="Speak Channel",["Color"]={150,75,0},["Text"]="The voice channel is currently inactive.\n\nJoin to activate its functionality."})
    else
        speakcontrols = send(Channels["voice-controls"],"",{["Title"]="Speak Channel",["Color"]={0,100,100},["Text"]="The voice channel is currently inactive.\n\nJoin to activate its functionality."})
    end
    
        
    local playlists = {{"https://www.youtube.com/playlist?list=PLIF2opf2-1PpNtDL54NYzTflxwrpi_yfz","\"Happy Pokémon Music\" by Sukadia"},{"https://www.youtube.com/playlist?list=PLIF2opf2-1PrQE8OMQWDM3JFsMNumrucL","\"Pokémon Jamming Music\" by Sukadia"},{"https://www.youtube.com/playlist?list=PLkDIan7sXW2ilCdIvS22xX2FNAn_YuoDO","\"Best Future Funk\" by Sound Station"},{"https://www.youtube.com/playlist?list=PLOzDu-MXXLliO9fBNZOQTBDddoA3FzZUo","\"Lofi Hip Hop\" by the bootleg boy"},{"https://www.youtube.com/playlist?list=PLxRnoC2v5tvg_xHK_roMyAStXDF-TRh2K","\"The Best of Retro Video Game Music\" by Specter227"}}
    local musiccontrols = Channels["voice-controls"]:getLastMessage()
    local connection = Channels["music"]:join()
    local controller, page, song, videoqueue, playlistnum
    if musiccontrols and musiccontrols ~= speakcontrols then
        musiccontrols:clearReactions()
        edit(musiccontrols,"",{["Title"]="Music Channel",["Color"]={100,0,100},["Text"]="The music channel is currently inactive.\n\nJoin to activate its functionality."})
    else
        musiccontrols = send(Channels["voice-controls"],"",{["Title"]="Music Channel",["Color"]={100,0,100},["Text"]="The music channel is currently inactive.\n\nJoin to activate its functionality."})
    end
    
    Client:on("voiceChannelJoin",function(member,channel)
        if channel == Channels["speak"] then
            local voicemembers = Channels["speak"].connectedMembers
            member:mute()
            if #voicemembers == 1 then
                edit(speakcontrols,"",{["Title"]="Speak Channel",["Color"]={0,150,150},["Text"]="Voice channel started.\n\nWelcome! If you intend to talk, please react to this message."})
                speakcontrols:addReaction("🟦")
                local function speakReaction(reaction,id)
                    if not Client:getUser(id).bot and reaction.message == speakcontrols then
                        local thismember
                        for i, member in pairs(voicemembers) do
                            if member.user.id == id then
                                thismember = member
                                break
                            end
                        end
                        if not thismember then
                            reaction:delete(id)
                            return
                        end
                        
                        table.insert(speakers,thismember)
                        if status == "Nothing" then
                            if #voicemembers == 1 then
                                edit(speakcontrols,"",{["Title"]="Speak Channel",["Color"]={0,150,150},["Text"]="\n\nYou are the only one in the voice channel currently. The process will start once someone else joins."})
                            else
                                status = "Waiting"
                                edit(speakcontrols,"",{["Title"]="Speak Channel",["Color"]={200,100,0},["Text"]="Talking will begin at the start of a new minute.\n\n**"..#speakers.."** out of **"..#voicemembers.."** will have allocated speaking time.\n\nIf you'd like to speak, react to this message."})
                                wait(60-(os.time()%60))
                                while #speakers >= 1 and #Channels["speak"].connectedMembers >= 2 do
                                    status = "Talking"
                                    local currentspeakers = {table.unpack(speakers)}
                                    local timeperperson = 50/#currentspeakers
                                    local string = "Here's the order and timestamps in which everyone will talk:\n\n"
                                    for i, member in pairs(currentspeakers) do
                                        string = string..i..". [00:"..round((timeperperson*(i - 1)) + 10,1).."] "..member.name.."\n"
                                    end
                                    edit(speakcontrols,"",{["Title"]="Speak Channel",["Color"]={0,255,255},["Text"]=string})
                                    wait(10-(os.time()%10))
                                    for i, member in pairs(currentspeakers) do
                                        local waittime = os.time() + timeperperson
                                        if member.voiceChannel ~= nil then
                                            member:unmute()
                                        end
                                        local string = ""
                                        if inTable(Channels["speak"].connectedMembers,member) then
                                            string = "**"..member.name.."**, you have ~"..round(timeperperson).." seconds to speak.\n\n"
                                        else
                                            string = "**"..member.name.."** has left, so everyone will sit ~"..round(timeperperson).." seconds in silence.\n\n"
                                        end
                                        for v, member in pairs(currentspeakers) do
                                            local online = false
                                            for i, connected in pairs(Channels["speak"].connectedMembers) do
                                                if connected == member then
                                                    online = true
                                                    break
                                                end
                                            end
                                            if online and v == i then
                                                string = string..v..". **[00:"..round((timeperperson*(v - 1)) + 10,1).."] - "..member.name.."**\n"
                                            elseif v == i then
                                                string = string..v..". ~~**[00:"..round((timeperperson*(v - 1)) + 10,1).."] - "..member.name.."**~~\n"
                                            elseif online then
                                                string = string..v..". [00:"..round((timeperperson*(v - 1)) + 10,1).."] - "..member.name.."\n"
                                            else
                                                string = string..v..". ~~[00:"..round((timeperperson*(v - 1)) + 10,1).."] - "..member.name.."~~\n"
                                            end
                                        end
                                        edit(speakcontrols,"",{["Title"]="Speak Channel",["Color"]={0,255,255},["Text"]=string})
                                        wait(waittime - os.time())
                                        if member.voiceChannel ~= nil then
                                            member:mute()
                                        end
                                    end
                                end
                                status = "Nothing"
                                if #speakers == 0 and #Channels["speak"].connectedMembers >= 2 then
                                    edit(speakcontrols,"",{["Title"]="Speak Channel",["Color"]={0,150,150},["Text"]="\n\nNo one is current queued to speak. For the process to begin, there must be at least one speaker."})
                                elseif #Channels["speak"].connectedMembers == 1 then
                                    edit(speakcontrols,"",{["Title"]="Speak Channel",["Color"]={0,150,150},["Text"]="\n\nYou are the only one left in the voice channel. The process will start again if someone else joins."})
                                else
                                    speakcontrols:clearReactions()
                                    edit(speakcontrols,"",{["Title"]="Speak Channel",["Color"]={0,100,100},["Text"]="The voice channel is currently inactive.\n\nJoin to activate its functionality."})
                                end
                            end
                        elseif status == "Waiting" then
                            edit(speakcontrols,"",{["Title"]="Speak Channel",["Color"]={0,200,200},["Text"]="Talking will begin at the start of a new minute.\n\n**"..#speakers.."** out of **"..#voicemembers.."** will have allocated speaking time.\n\nIf you'd like to speak, react to this message."})
                        end
                    end
                end
                local function speakReactionRemove(reaction, id)
                    if reaction.message == speakcontrols then
                        for i, member in pairs(speakers) do
                            if member.user.id == id then
                                table.remove(speakers,i)
                                break
                            end
                        end
                        if #speakers == 0 then
                            edit(speakcontrols,"",{["Title"]="Speak Channel",["Color"]={0,150,150},["Text"]="\n\nNo one is current queued to speak. For the process to begin, there must be at least one speaker."})
                        elseif status == "Waiting" then
                            edit(speakcontrols,"",{["Title"]="Speak Channel",["Color"]={0,200,200},["Text"]="Talking will begin at the start of a new minute.\n\n**"..#speakers.."** out of **"..#voicemembers.."** will have allocated speaking time.\n\nIf you'd like to speak, react to this message."})
                        end
                    end
                end
                Client:removeListener("reactionAdd",speakReaction)
                Client:removeListener("reactionRemove",speakReactionRemove)
                Client:on("reactionAdd",speakReaction)
                Client:on("reactionRemove",speakReactionRemove)
            elseif #voicemembers > 1 and #speakers ~= 0 then
                edit(speakcontrols,"",{["Title"]="Speak Channel",["Color"]={0,200,200},["Text"]="Talking will begin at the start of a new minute.\n\n**"..#speakers.."** out of **"..#voicemembers.."** will have allocated speaking time.\n\nIf you'd like to speak, react to this message."})
            end
        end
        
        
        if channel == Channels["music"] then
            if #Channels["music"].connectedMembers == 2 then
                
                local function playlistSearch(pagenum)
                    page = pagenum
                    song = 0
                    local string = "`Page 1 / "..math.ceil(#playlists/5).."`\n\n"
                    for i=(pagenum*5)-4,pagenum*5 do
                        if playlists[i] then
                            string = string.."**"..i..".** "..playlists[i][2].."\n\n"
                        end
                    end
                    edit(musiccontrols,"",{["Title"]="Music Channel",["Color"]={150,0,150},["Text"]=string,["FooterImage"]=controller.user.avatarURL,["FooterText"]=controller.name.." is the controller."})
                end
                 
                local function playSong(video) -- Plays a song, and downloads the next song if one is given
                    local process = io.popen("youtube-dl -f \"bestaudio[ext=m4a]\" --restrict-filenames -o \"/tmp/currentsong.m4a\" https://www.youtube.com/watch?v="..video["url"].." 2>&1") -- Save audio of YouTube video to /tmp/currentsong.m4a, this is because /tmp is usually a ramdisk and we want to minimize SD card writes
                    process:read("*a") -- Output is read just to make sure the command has completed before progressing
                    io.close(process)
                    edit(musiccontrols,"",{["Title"]="Music Channel",["Color"]={255,0,255},["Text"]="Playlist: **"..playlists[playlistnum][2].."**\n\n`Song "..song.." / "..#videoqueue.."`\n**"..video["title"].."**\n\n\nPress ".."1️⃣".." to quit",["FooterImage"]=controller.user.avatarURL,["FooterText"]=controller.name.." is the controller."})
                    connection:playFFmpeg("/tmp/currentsong.m4a")
                    wait(0.1)
                    os.remove("/tmp/currentsong.m4a")
                end
                
                local function playPlaylist(num)
                    playlistnum = num
                    page = "Playing"
                    coroutine.wrap(function()
                        edit(musiccontrols,"",{["Title"]="Music Channel",["Color"]={200,0,200},["Text"]="Loading Playlist..\n_ _",["FooterImage"]=controller.user.avatarURL,["FooterText"]=controller.name.." is the controller."})
                        local waiting = true
                        coroutine.wrap(function()
                            wait(5)
                            if waiting then
                                edit(musiccontrols,"",{["Title"]="Music Channel",["Color"]={200,0,200},["Text"]="Loading Playlist..\n(There's a lot of songs...)",["FooterImage"]=controller.user.avatarURL,["FooterText"]=controller.name.." is the controller."})
                            end
                        end)()
                        local file = io.popen("youtube-dl -j -q --geo-bypass --restrict-filenames --playlist-random --flat-playlist \""..playlists[playlistnum][1].."\" 2>&1") --2>&1 brings output from stderr to stdout
                        waiting = false
                        videoqueue = Json.decode("["..string.gsub(file:read("*a"),"\n",",").."]")
                        for i=#videoqueue, 1, -1 do --Remove deleted videos
                            if videoqueue[i]["title"] == "[Deleted video]" then
                                table.remove(videoqueue,i)
                            end
                        end
                        song = 1
                        while song < #videoqueue and song ~= 0 do
                            local video = videoqueue[song]
                            edit(musiccontrols,"",{["Title"]="Music Channel",["Color"]={255,0,255},["Text"]="Playlist: **"..playlists[playlistnum][2].."**\n\n`Song "..song.." / "..#videoqueue.."`\n**"..video["title"].."**\nLoading Song..\n\nPress ".."1️⃣".." to quit",["FooterImage"]=controller.user.avatarURL,["FooterText"]=controller.name.." is the controller."})
                            playSong(video)
                            song = song + 1
                        end
                        if #Channels["music"].connectedMembers ~= 1 then
                            playlistSearch(1)
                        end
                    end)()
                end
                
                controller = member
                edit(musiccontrols,"",{["Title"]="Music Channel",["Color"]={150,0,150},["Text"]="Waiting for buttons..",["FooterImage"]=controller.user.avatarURL,["FooterText"]=controller.name.." is the controller."})
                musiccontrols:addReaction("1️⃣")
                musiccontrols:addReaction("2️⃣")
                musiccontrols:addReaction("3️⃣")
                musiccontrols:addReaction("4️⃣")
                musiccontrols:addReaction("5️⃣")
                musiccontrols:addReaction("⏪")
                musiccontrols:addReaction("⏯️")
                musiccontrols:addReaction("⏩")
                playlistSearch(1)
                local function musicReaction(reaction,id)
                    if not Client:getUser(id).bot and reaction.message == musiccontrols then
                        if controller.user.id ~= id then
                            reaction:delete(id)
                            return
                        end
                        if page ~= "Playing" and page ~= "Paused" then
                            if reaction.emojiName == "1️⃣" and playlists[1*page] then
                                playPlaylist(1*page)
                            elseif reaction.emojiName == "2️⃣" and playlists[2*page] then
                                playPlaylist(2*page)
                            elseif reaction.emojiName == "3️⃣" and playlists[3*page] then
                                playPlaylist(3*page)
                            elseif reaction.emojiName == "4️⃣" and playlists[4*page] then
                                playPlaylist(4*page)
                            elseif reaction.emojiName == "5️⃣" and playlists[5*page] then
                                playPlaylist(5*page)
                            elseif reaction.emojiName == "⏪" and page ~= 1 then
                                playlistSearch(page - 1)
                            elseif reaction.emojiName == "⏩" and page ~= math.ceil(#playlists/5) then
                                playlistSearch(page + 1)
                            end
                        end
                        if page == "Playing" or page == "Paused" then
                            if reaction.emojiName == "1️⃣" then
                                song = -1
                                connection:stopStream()
                            elseif reaction.emojiName == "⏪" then --Rewind
                                if song ~= 1 then
                                    song = song - 2
                                    connection:stopStream()
                                end
                            elseif reaction.emojiName == "⏯️" then --Pause
                                if page == "Playing" then
                                    connection:pauseStream()
                                    page = "Paused"
                                    edit(musiccontrols,"",{["Title"]="Music Channel",["Color"]={200,0,200},["Text"]="Playlist: **"..playlists[playlistnum][2].."**\n\n`Song "..song.." / "..#videoqueue.."`\n**"..videoqueue[song]["title"].."**\nPaused\n\nPress ".."1️⃣".." to quit",["FooterImage"]=controller.user.avatarURL,["FooterText"]=controller.name.." is the controller."})
                                else
                                    connection:resumeStream()
                                    page = "Playing"
                                    edit(musiccontrols,"",{["Title"]="Music Channel",["Color"]={200,0,200},["Text"]="Playlist: **"..playlists[playlistnum][2].."**\n\n`Song "..song.." / "..#videoqueue.."`\n**"..videoqueue[song]["title"].."**\n\n\nPress ".."1️⃣".." to quit",["FooterImage"]=controller.user.avatarURL,["FooterText"]=controller.name.." is the controller."})
                                end
                            elseif reaction.emojiName == "⏩" then --Skip
                                connection:stopStream()
                            end
                        end
                        reaction:delete(id)
                    end
                end
                Client:removeListener("reactionAdd",musicReaction)
                Client:on("reactionAdd",musicReaction)
            end
        end
    end)
    Client:on("voiceChannelLeave",function(member,channel)
        if channel == Channels["speak"] then
            for i, speaker in pairs(speakers) do
                if speaker == member then
                    table.remove(speakers,i)
                    break
                end
            end
            if #Channels["speak"].connectedMembers == 0 and status ~= "Talking" then
                speakcontrols:clearReactions()
                edit(speakcontrols,"",{["Title"]="Speak Channel",["Color"]={0,100,100},["Text"]="The voice channel is currently inactive.\n\nJoin to activate its functionality."})
            elseif #Channels["speak"].connectedMembers == 1 and status == "Nothing" then
                edit(speakcontrols,"",{["Title"]="Speak Channel",["Color"]={0,150,150},["Text"]="\n\nYou are the only one in the voice channel currently. The process will start once someone else joins."})
            end
            if speakcontrols.reactions ~= nil then
                for i, reaction in pairs(speakcontrols.reactions) do
                    for v, user in pairs(reaction:getUsers()) do
                        if user.id == member.user.id then
                            reaction:delete(member.user.id)
                        end
                    end
                end
            end
        end
        
        
        if channel == Channels["music"] then
            if #Channels["music"].connectedMembers == 1 then
                if page == "Playing" or page == "Paused" then
                    song = -1
                    connection:stopStream()
                end
                musiccontrols:clearReactions()
                edit(musiccontrols,"",{["Title"]="Music Channel",["Color"]={100,0,100},["Text"]="The music channel is currently inactive.\n\nJoin to activate its functionality."})
            elseif member == controller then
                for i, member in pairs(Channels["music"].connectedMembers) do
                    if not member.user.bot then
                        controller = member
                        if page == "Playing" then
                            edit(musiccontrols,"",{["Title"]="Music Channel",["Color"]={200,0,200},["Text"]="Playlist: **"..playlists[playlistnum][2].."**\n\n`Song "..song.." / "..#videoqueue.."`\n**"..videoqueue[song]["title"].."**\n\n\nPress ".."1️⃣".." to quit",["FooterImage"]=controller.user.avatarURL,["FooterText"]=controller.name.." is the controller."})
                        elseif page == "Paused" then
                            edit(musiccontrols,"",{["Title"]="Music Channel",["Color"]={200,0,200},["Text"]="Playlist: **"..playlists[playlistnum][2].."**\n\n`Song "..song.." / "..#videoqueue.."`\n**"..videoqueue[song]["title"].."** \nPaused\n\nPress ".."1️⃣".." to quit",["FooterImage"]=controller.user.avatarURL,["FooterText"]=controller.name.." is the controller."})
                        else
                            local string = "`Page 1 / "..math.ceil(#playlists/5).."`\n\n"
                            for i=(page*5)-4,page*5 do
                                if playlists[i] then
                                    string = string.."**"..i..".** "..playlists[i][2].."\n\n"
                                end
                            end
                            edit(musiccontrols,"",{["Title"]="Music Channel",["Color"]={150,0,150},["Text"]=string,["FooterImage"]=controller.user.avatarURL,["FooterText"]=controller.name.." is the controller."})
                        end
                        return
                    end
                end
            end
        end
    end)
end)

Client:on("memberJoin",function(member)
    if member.user.bot then
        return
    end
    updatePerms(member.user.id,"help","noaccess")
    local message = send(member.user.id,"Hi! Sorry, I'm just checking if your DMs are open or not. I'll properly welcome you in #type :)")
    if message == nil then
        send(Channels["type"],"Welcome <@"..member.user.id..">! Enjoy your stay :)\n\nP.S. You have server DMs disabled, please enable them so I can message you.")
        wait(10)
    else
        wait(10)
        send(Channels["type"],"Welcome <@"..member.user.id..">! Enjoy your stay :)")
    end
    wait(50)
    if Server:getMember(member.user.id) ~= nil then
        updatePerms(member.user.id,"help","clear")
    end
end)

local function NewMessage(message)
    if message.guild ~= Server and message.channel.type ~= Enum.channelType.private then
        return
    end
    local user = message.author
    if user.bot or user == nil then
        return
    end
    local channel = message.channel
    local originaltext, text = message.content, string.lower(message.content)
    if DevMode and user.id ~= OwnerId then
        print(user.username.." attempted to interact")
        send(user.id,"Get outta here, can't you see I'm working? This bot isn't going to code itself.",{["Title"]="Closed Testing",["Color"]={200,200,50},["Text"]="The bot is currently in closed testing.\n\nThis means the bot has been booted purely for the purpose of testing/fixing a new feature. You aren't allowed to interact with the bot during this time to make sure save data is preserved."})
        return
    end
    if spamdata[user.id] == "Muted" then
        return
    end
    if spamdata[user.id] == "MuteProcess" then
        message:delete()
        return
    end
    
    spamSensor(user.id)
    
    if storagedata["PlayerData"][user.id] == nil then
        storagedata["PlayerData"][user.id] = StartingData
    end
    string.gsub(text,"%c"," ")
    local arguments = split(string.gsub(string.gsub(text,"%p",""),"%c"," "))
    
    if channel.type == Enum.channelType.private then
        
        if arguments[1] == "suggest" then
            
            if arguments[2] ~= nil then
                
                local i = 0
                for letter in string.gmatch(arguments[2],".") do
                    i = i+1
                    if string.match(letter,"%W") and string.match(letter,"%C") and string.match(letter,"%P") and string.match(letter,"%S") then
                        local message = send(user.id,"Your word can't have any special characters.")
                        return
                    end
                end
                
                if inTable(storagedata["WhitelistedWords"],arguments[2]) then
                    send(user.id,"Surprisingly, that word is already in the whitelist. Perhaps suggest a different one?")
                    return
                elseif string.len(arguments[2]) >= 20 then
                    send(user.id,"Jeez, that's an awfully long word. I'm only allowed to take ones under 20 letters long.")
                    return
                end
                
                --Gives the option to either use the suggest ability or not
                for i, ability in pairs(storagedata["PlayerData"][user.id]["Inventory"]) do
                    if ability == "suggest" then
                        send(user.id,"It looks like you have an ability that allows you to immediately whitelist a word. Would you like to use it?")
                        local response = getResponse(channel,60)
                        if response ~= false then
                            response = string.lower(response)
                        end
                        if response == "y" or response == "yes" or response == "sure" or response == "yea" then
                            table.remove(storagedata["PlayerData"][user.id]["Inventory"],i)
                            table.insert(storagedata["WhitelistedWords"],arguments[2])
                            for i=#storagedata["SuggestedWords"], 1, -1 do
                                if storagedata["SuggestedWords"][i][2] == arguments[2] then
                                    table.remove(storagedata["SuggestedWords"],i)
                                end
                            end
                            send(Channels["type"],"A fresh new word came out of the press:",{["Title"]="New Word",["Color"]={0,255,255},["Text"]=user.username.." has used their ability to whitelist the word **"..arguments[2].."**."})
                            send(user.id,"Okay, I've whitelisted the word for you.",{["Title"]="Word Whitelisted",["Color"]={0,255,255},["Text"]="Your consumable ability has been used.\n\nThe word **"..arguments[2].."** is now whitelisted."})
                            return
                        else
                            for i, suggestedwordinfo in pairs(storagedata["SuggestedWords"]) do
                                if suggestedwordinfo[1] == user.id then
                                    if inTable(suggestbuffer,user.id) and suggestedwordinfo[2] ~= arguments[2] then
                                        send(user.id,"Ah okay, I assume you wanted to correct your word then. No worries, I got you.",{["Title"]="Suggestion Edited",["Color"]={100,255,255},["Text"]="The previous word **"..suggestedwordinfo[2].."** was replaced with **"..arguments[2].."** in the suggested words list.\n\nYou were allowed to do this because you changed your answer within one minute."})
                                        suggestedwordinfo[2] = arguments[2]
                                    else
                                        if response == "n" or response == "no" then
                                        send(user.id,"No? That's fine, but you've already suggested a word so I won't add your word to the suggestions. The word selection is in "..timeUntilChoice()..".")
                                        elseif response == false then
                                            send(user.id,"..You haven't responded for a minute. I'll take it as a no, which in that case means I won't do anything since you've already suggested a word.")
                                        else
                                            send(user.id,"I have no clue what you just said; It wasn't a hard \"yes\", so I'll take it as a no. You already suggested a word so I can't add your word to the suggestions.")
                                        end
                                    end
                                    return
                                end
                            end
                            if response == "n" or response == "no" then
                                send(user.id,"Gotcha, I suppose you're saving it for a good idea. Anyways, I added your word to the suggestions.",{["Title"]="Word Suggested",["Color"]={100,255,255},["Text"]="The word **"..arguments[2].."** has been added to the suggested words list.\n\nYour word has a random chance of being whitelisted in "..timeUntilChoice().." when the new words are chosen. Whether or not your word is whitelisted, the suggested words list is cleared after the new word selection, so if it isn't chosen you will have to re-submit it."})
                            elseif response == false then
                                send(user.id,"..You haven't responded for a minute. I'm going to assume you mean a no and add it to the suggestions. If I'm wrong you can suggest it again and use the ability.",{["Title"]="Word Suggested",["Color"]={100,255,255},["Text"]="The word **"..arguments[2].."** has been added to the suggested words list.\n\nYour word has a random chance of being whitelisted in "..timeUntilChoice().." when the new words are chosen. Whether or not your word is whitelisted, the suggested words list is cleared after the new word selection, so if it isn't chosen you will have to re-submit it."})
                            else
                                send(user.id,"I have no idea what you just said; I'm a bot and have limited brain capacity. I'll assume it was a no since it wasn't a \"yes\", so I added your word to the suggestions.",{["Title"]="Word Suggested",["Color"]={100,255,255},["Text"]="The word **"..arguments[2].."** has been added to the suggested words list.\n\nYour word has a random chance of being whitelisted in "..timeUntilChoice().." when the new words are chosen. Whether or not your word is whitelisted, the suggested words list is cleared after the new word selection, so if it isn't chosen you will have to re-submit it."})
                            end
                            table.insert(storagedata["SuggestedWords"],{user.id,arguments[2]})
                            table.insert(suggestbuffer,user.id)
                            wait(60)
                            table.remove(suggestbuffer,1)
                        end
                        return
                    end
                end
                
                for i, suggestedwordinfo in pairs(storagedata["SuggestedWords"]) do
                    if suggestedwordinfo[1] == user.id then
                        if inTable(suggestbuffer,user.id) and suggestedwordinfo[2] ~= arguments[2] then
                            send(user.id,"Ah, changed your mind? No worries, I got you.",{["Title"]="Suggestion Edited",["Color"]={100,255,255},["Text"]="The previous word **"..suggestedwordinfo[2].."** was replaced with **"..arguments[2].."** in the suggested words list.\n\nYou were allowed to do this because you changed your answer within one minute."})
                            suggestedwordinfo[2] = arguments[2]
                        else
                            send(user.id,"You already suggested a word for the next random selection. You'll have to wait "..timeUntilChoice().." until the new words are picked.")
                        end
                        return
                    end
                end
                
                table.insert(storagedata["SuggestedWords"],{user.id,arguments[2]})
                send(user.id,"Alrighty, whatever you say. I added your word to the suggestions.",{["Title"]="Word Suggested",["Color"]={100,255,255},["Text"]="The word **"..arguments[2].."** has been added to the suggested words list.\n\nYour word has a random chance of being whitelisted in "..timeUntilChoice().." when the new words are chosen. Whether or not your word is whitelisted, the suggested words list is cleared after the new word selection, so if it isn't chosen you will have to re-submit it."})
                table.insert(suggestbuffer,user.id)
                wait(60)
                table.remove(suggestbuffer,1)
            else
                send(user.id,"You need to include the word you want to suggest, use this format so I understand it: `suggest (word)`")
            end
            
            return
        end
        
        if arguments[1] == "check" then
            
            if arguments[2] ~= nil then
                
                if inTable(storagedata["WhitelistedWords"],arguments[2]) then
                    send(user.id,"Well I have some good news for you, that word is already whitelisted.")
                    return
                elseif storagedata["PlayerData"][user.id]["CheckUses"] >= 50 then
                    send(user.id,"Jeez, you've used this 50 times now. The bot has a total limit of 1000 uses per day, so I'm going to be cutting you off here.")
                    return
                end
                
                storagedata["PlayerData"][user.id]["CheckUses"] = storagedata["PlayerData"][user.id]["CheckUses"] + 1
                local checkedtoday = false
                for i, userid in pairs(storagedata["CheckUsers"]) do
                    if userid == user.id then
                        checkedtoday = true
                        break
                    end
                end
                if not checkedtoday then
                    table.insert(storagedata["CheckUsers"],user.id)
                end
                local result, body = Coro.request("GET","https://dictionaryapi.com/api/v3/references/thesaurus/json/"..arguments[2].."?key=58bec7b9-7505-489d-b781-0b16b7cb0744")
                local wordtable, synonyms = Json.decode(body), {}
                if wordtable ~= {} then
                    for v, wordlist in pairs(wordtable) do
                        if wordlist["meta"] ~= nil then
                            for i, word in pairs(wordlist["meta"]["syns"][1]) do
                                table.insert(synonyms,word)
                            end
                        end
                    end
                else
                    send(user.id,"Sorry, I can't find any information on that word. It's either misspelt, or too obscure for a 275,000 word thesaurus.")
                    return
                end
                
                local templist = {}
                for i, synonym in pairs(synonyms) do
                    local isdup = false
                    for v, checkdup in pairs(synonyms) do
                        if synonym == checkdup and i ~= v then
                            isdup = true
                            break
                        end
                    end
                    if not isdup then
                        table.insert(templist,synonym)
                    end
                end
                synonyms = templist
                
                local goodsynonyms = {}
                for i, synonym in pairs(synonyms) do
                    if inTable(storagedata["WhitelistedWords"],synonym) then
                        table.insert(goodsynonyms,"**"..synonym.."**")
                    end
                end
                
                
                if #goodsynonyms == 0 then
                    send(user.id,"Tough luck, out of the "..#storagedata["WhitelistedWords"].." whitelisted words not one is a synonym to "..arguments[2]..".\n\nI'd just recommend suggesting it to me with the `suggest` command.")
                elseif #goodsynonyms == 1 then
                    send(user.id,"Ah, I found a synonym that's whitelisted, it's "..goodsynonyms[1]..".")
                else
                    send(user.id,"I've actually found "..#goodsynonyms.." synonyms for that word in the whitelist:\n\n "..listItems(goodsynonyms,true)..".")
                end
            else
                send(user.id,"I need a word for me to check, use this format so I understand it: `check (word)`")
            end
            
            return
        end
        
        if arguments[1] == "wordlist" then
            if tonumber(arguments[2]) ~= nil or arguments[2] == nil then
                local page = tonumber(arguments[2]) or 1
                local string = "There are **"..#storagedata["WhitelistedWords"].."** whitelisted words you can say:\n\n`Page "..page.."`\nUse `wordlist [#]` to browse pages.\n\n"
                local currentpage = 1
                for i, word in pairs(storagedata["WhitelistedWords"]) do
                    string = string..word..", "
                    if storagedata["WhitelistedWords"][i+1] ~= nil then
                        if string.len(string)+string.len(storagedata["WhitelistedWords"][i+1]) > 2000 then
                            currentpage = currentpage + 1
                            if currentpage == page then
                                send(user.id,string.sub(string,1,-3))
                                return
                            end
                            string = "There are "..#storagedata["WhitelistedWords"].." whitelisted words you can say:\n\n`Page "..page.."`\nUse `wordlist [#]` to look through pages.\n\n"
                        end
                    else
                        if page == currentpage then
                            send(user.id,string)
                        else
                            send(user.id,"Sorry, that page doesn't exist. `Page "..currentpage.."` does, however.")
                        end
                        return
                    end
                end
            else
                local string = "Here's all of the words that start with **"..arguments[2].."**:\n\n"
                local wordfound = false
                for i, word in pairs(storagedata["WhitelistedWords"]) do
                    if string.sub(word,1,string.len(arguments[2])) == arguments[2] then
                        wordfound = true
                        string = string..word..", "
                    elseif wordfound then --table is sorted alphabetically, no need to check rest of table
                        break
                    end
                end
                string = string.sub(string,1,-3)
                if wordfound then
                    if string.len(string) > 2000 then
                        send(user.id,"Woah, your search came up with too many results. Maybe you can narrow it down by adding more letters, or just browse the whitelisted words with `wordlist [Page #]`.")
                    else
                        send(user.id,string)
                    end
                else
                    send(user.id,"Sorry, I couldn't find anything whitelisted that starts with **"..arguments[2].."**.")
                end
                return
            end
        end
        
        if arguments[1] == "inventory" then
            if storagedata["PlayerData"][user.id]["Inventory"] ~= nil then
                local abilities = {["suggest"]=0,["bypass"]=0}
                for i, ability in pairs(storagedata["PlayerData"][user.id]["Inventory"]) do
                    abilities[ability] = abilities[ability] + 1
                end
                send(user.id,"Here's your inventory right now:\n\n"..abilities["suggest"].."x - Suggest\n"..abilities["bypass"].."x - Bypass\n\nYou can use the command `use (ability)` to, uh, use your ability.")
            else
                send(user.id,"From what I see you don't have any abilities in your inventory. Hopefully you can grab one from one of the random events sometime. :)")
            end
            return
        end
        
        if arguments[1] == "use" then
            if arguments[2] == "bypass" then
                local pos = inTable(storagedata["PlayerData"][user.id]["Inventory"],"bypass")
                if user.id == OwnerId then
                    commanduse[user.id] = "adminbypass"
                    send(user.id,"",{["Title"]="Admin Bypass",["Color"]={255,255,0},["Text"]="The next message you send in the server will be unfiltered."})
                elseif pos then
                    commanduse[user.id] = "bypass"
                    table.remove(storagedata["PlayerData"][user.id]["Inventory"],pos)
                    send(user.id,"",{["Title"]="Bypass Used",["Color"]={255,255,0},["Text"]="The next message you send in the server will be unfiltered."})
                end
            elseif arguments[2] == "suggest" then
                local pos = inTable(storagedata["PlayerData"][user.id]["Inventory"],"suggest")
                if pos then
                    send(user.id,"What word would you like to add to the whitelist?")
                    local response = getResponse(channel,60)
                    if response ~= false then
                        local i = 0
                        for letter in string.gmatch(response,".") do
                            i = i+1
                            if string.match(letter,"%W") and string.match(letter,"%C") and string.match(letter,"%P") and string.match(letter,"%S") then
                                local message = send(user.id,"Your word can't have any special characters.")
                                return
                            end
                        end
                        response = split(string.gsub(string.lower(response),"[%p%c]",""))
                    end
                    if response == false then
                        send(user.id,"It's been a minute and you haven't responded, so I'll stop waiting. If you still want to use it, just DM the command again.")
                    else
                        if #response > 1 then
                            send(user.id,"Hmm, that's more than one word. You can go ahead and use the command again if you have another.")
                        elseif string.len(response[1]) >= 20 then
                            send(user.id,"Sorry, despite you having an automatic whitelist it still has to be under 20 letters.")
                        else
                            table.remove(storagedata["PlayerData"][user.id]["Inventory"],pos)
                            table.insert(storagedata["WhitelistedWords"],response[1])
                            for i=#storagedata["SuggestedWords"], 1, -1 do
                                if storagedata["SuggestedWords"][i][2] == response[1] then
                                    table.remove(storagedata["SuggestedWords"],i)
                                end
                            end
                            send(Channels["type"],"A fresh new word came out of the press:",{["Title"]="New Word",["Color"]={0,255,255},["Text"]=user.username.." has used their ability to whitelist the word **"..response[1].."**."})
                            send(user.id,"Okay, I've whitelisted the word for you.",{["Title"]="Word Whitelisted",["Color"]={0,255,255},["Text"]="Your consumable ability has been used.\n\nThe word **"..response[1].."** is now whitelisted."})
                        end
                    end
                else
                    send(user.id,"You don't have a suggest ability in your inventory. You can just use the `suggest` command to suggest a word normally.")
                end
            elseif arguments[2] == nil then
                send(user.id,"You need to specify an ability to use. You can find what abilities you have with the `inventory` command.")
            else
                send(user.id,"I'm not sure what ability that is. Check your `inventory` to see what you can use.")
            end
            return
        end
        
        if arguments[1] == "worduse" then
            if tonumber(arguments[2]) ~= nil or arguments[2] == nil then
                table.sort(storagedata["WordCount"], function(a,b)
                    return a[2] > b[2]
                end)
                local page = tonumber(arguments[2]) or 1
                if storagedata["WordCount"][(page*10)-9] == nil then
                    send(user.id,"Sorry, that page doesn't exist. `Page "..math.ceil(#storagedata["WordCount"]/10).."` does, however.")
                    return
                end
                local string = "Here's the top "..((page*10)-9).."-"..(page*10).." most used words:\n\n`Page "..page.." / "..math.ceil(#storagedata["WordCount"]/10).."`\nUse `worduse [#]` to browse pages.\n\n"
                for i=((page*10)-9), (page*10) do
                    if storagedata["WordCount"][i] ~= nil then
                        string = string..i..". "..storagedata["WordCount"][i][1].." - **"..storagedata["WordCount"][i][2].."** Uses\n"
                    else
                        string = string.."\nThere are no positions past "..i.."."
                        break
                    end
                end
                send(user.id,string)
            else
                if inTable(storagedata["WhitelistedWords"],arguments[2]) then
                    for i, wordinfo in pairs(storagedata["WordCount"]) do
                        if wordinfo[1] == arguments[2] then
                            if wordinfo[2] == 1 then
                                send(user.id,"**"..arguments[2].."** has only been used a singular time and is #"..i.." in the most used words.")
                            else
                                send(user.id,"**"..arguments[2].."** has been used "..wordinfo[2].." times and is #"..i.." in the most used words.")
                            end
                            return
                        end
                    end
                    send(user.id,"It looks like **"..arguments[2].."** has never been said before.")
                else
                    send(user.id,"**"..arguments[2].."** isn't in the whitelist, so I wouldn't have any word usage information on it.")
                end
            end
            return
        end
        
        if arguments[1] == "filesize" then
            local file = io.open("newsavedata")
            local kilobytes = file:seek("end")/1024
            send(user.id,"The savedata file right now is "..round(kilobytes,3).." kilobytes.")
            return
        end
        
        if arguments[1] == "count" then
            send(user.id,"Send me your message, I'll count the number of characters as if it were in #message-counting.")
            local response = getResponse(channel,60)
            if response == false then
                send(user.id,"It's been a minute, so I'm going to assume you've changed your mind. You can run the command again if you're still typing.")
            else
                for i, emoji in pairs(Server.emojis) do
                    response = string.gsub(response,"<:"..emoji.hash..">","")
                end
                local characters = string.len(string.gsub(response,"[%p%c%s]",""))
                local charplural = "s"
                if characters == 1 then
                    charplural = ""
                end
                local amountoff = characters - storagedata["CountChannel"]["Count"]
                local amountplural = "s"
                if amountoff == 1 then
                    amountplural = ""
                end
                if amountoff == 0 then
                    send(user.id,"Your message would be counted as **"..characters.."** character"..charplural..", that's the amount the next message should be. Looks like you're good to post. :)")
                elseif amountoff > 0 then
                    send(user.id,"Your message would be counted as **"..characters.."** character"..charplural..". You need to remove "..amountoff.." more character"..amountplural..".")
                else
                    send(user.id,"Your message would be counted as **"..characters.."** character"..charplural..". You need to add "..(-amountoff).." more character"..amountplural..".")
                end
            end
            return
        end
        
        if arguments[1] == "art" then
            if #images == 0 then
                send(user.id,"Give me a second to index all of Sukadia's saved art..")
                local artchannel = Client:getGuild("590344977197039629"):getChannel("593458173348806667")
                local reachedend, loop = false, 1
                local messagelist = artchannel:getMessagesAfter("593458324511653891",100)
                while not reachedend do
                    local lastmessageid
                    for i, message in pairs(messagelist) do
                        if message.attachment ~= nil then
                            table.insert(images,{message.attachment.url,message:getDate()[1]})
                        end
                        lastmessageid = message.id
                    end
                    if #messagelist ~= 100 then
                        reachedend = true
                    else
                        messagelist = artchannel:getMessagesAfter(lastmessageid,100)
                    end
                end
                local hash = {}
                local nonduplist = {}
                for _,v in ipairs(images) do
                    if (not hash[v[1]]) then
                        table.insert(nonduplist,v)
                        hash[v[1]] = true
                    end
                end
                images = nonduplist
                table.sort(images, function(a,b)
                    return a[2] < b[2]
                end)
            end
            local imagenum = math.random(1,#images)
            send(user.id,"Here's some art I stole out of Sukadia's folder:",{["Color"]={75,100,100},["ImageUrl"]=images[imagenum][1],["FooterText"]="Image #"..imagenum.."/"..#images.." | Saved "..os.date("%x at %I:%M %p",images[imagenum][2])})
            return
        end
        
        if arguments[1] == "github" then
            send(user.id,"Interested in the github? Here's the link:\nhttps://github.com/Sukadia/Bot_Nothing-In-Particular")
            return
        end
        
        if text == "sukadia is cute" then
            send(user.id,"shut the fuck up")
            return
        end
        
        if storagedata["PlayerData"][user.id]["State"] == "Normal" then
            channel:send{file = "pikachustare.png"}
            return
        end
        
    else
        
        --Commands
            if commanduse[user.id] then
                if commanduse[user.id] == "bypass" then
                    if channel == Channels["images"] then
                        if message.content ~= "" then
                            message:delete()
                            send(user.id,"Yea.. Not really a *true* bypass, but gotta keep the channels to their topics.",{["Title"]="Bypass Refunded",["Color"]={200,200,0},["Text"]="The bypass you have just used has been refunded.\n\nReason:\n**Text is not allowed in the images channel**"})
                        elseif message.attachment.height == nil then
                            message:delete()
                            send(user.id,"Yea, uhh.. non-image files aren't allowed. Good try though.",{["Title"]="Bypass Refunded",["Color"]={200,200,0},["Text"]="The bypass you have just used has been refunded.\n\nReason:\n**Message did not include an image**"})
                        else
                            commanduse[user.id] = nil
                            return
                        end
                    elseif channel == Channels["fuck-everything"] then
                        message:delete()
                        send(user.id,"It was a decent try.",{["Title"]="Bypass Refunded",["Color"]={200,200,0},["Text"]="The bypass you have just used has been refunded.\n\nReason:\n**Bypasses are unusable in #fuck-everything**"})
                    else
                        commanduse[user.id] = nil
                        return
                    end
                elseif commanduse[user.id] == "adminbypass" then
                    commanduse[user.id] = nil
                    return
                end
            end
            
            if user.id == OwnerId then
                if arguments[1] == "ping" and arguments[2] ~= nil then
                    message:delete()
                    ping(arguments[2])
                    return
                elseif arguments[1] == "openserver" then
                    storagedata["LastSaved"][2] = false
                    message:delete()
                    updatePerms("everyone",{"type","fuck-vowels","fuck-everything","message-counting","images","speak"},"on")
                    send(Channels["type"],"",{["Title"]="Server Opened",["Color"]={100,255,100},["Text"]="The server has been reopened, meaning the bot and all channels now allow interaction."})
                    return
                elseif arguments[1] == "closeserver" then
                    Storage:save(storagedata)
                    storagedata["LastSaved"] = {os.time(), true}
                    message:delete()
                    updatePerms("everyone",{"type","fuck-vowels","fuck-everything","message-counting","images","speak"},"off")
                    send(Channels["type"],"",{["Title"]="Server Closed",["Color"]={100,0,0},["Text"]="The server has been closed, meaning all channels are now temporarily read-only.\n\nDuring this time the bot will most likely be offline."})
                    return
                elseif arguments[1] == "mute" and arguments[3] ~= nil then
                    message:delete()
                    updatePerms(arguments[2],{"type","fuck-vowels","fuck-everything","message-counting","images","speak"},"off")
                    send(channel,"Big yikes. At least it wasn't a ban.",{["Title"]="Member Muted",["Color"]={255,0,0},["Text"]="**"..Client:getUser(arguments[2]).username.."** has been muted for **"..arguments[3].."** minutes.\n\nFor clarification, there are no rules for the server except those administered by the bot. However, Sukadia does have the power to take actions based off of common sense."})
                    wait(tonumber(arguments[3])*60)
                    updatePerms(arguments[2],{"type","fuck-vowels","fuck-everything","message-counting","images","speak"},"on")
                    send(channel,"Welcome back, cause no trouble.",{["Title"]="Member Unmuted",["Color"]={0,255,0},["Text"]="**"..Client:getUser(arguments[2]).username.."** has been unmuted after **"..arguments[3].."** minutes."})
                    return
                elseif arguments[1] == "newwords" then
                    message:delete()
                    newWords()
                    return
                elseif arguments[1] == "devmode" then
                    message:delete()
                    DevMode = not DevMode
                    return
                elseif arguments[1] == "giveitem" and arguments[3] ~= nil then
                    message:delete()
                    table.insert(storagedata["PlayerData"][arguments[2]]["Inventory"],arguments[3])
                    send(channel,"Given **"..arguments[3].."** ability to **"..Client:getUser(arguments[2]).username.."**.")
                    return
                elseif arguments[1] == "removeword" and arguments[2] ~= nil then
                    message:delete()
                    for i, word in pairs(storagedata["WhitelistedWords"]) do
                        if string.lower(arguments[2]) == word then
                            table.remove(storagedata["WhitelistedWords"],i)
                            send(channel,"Jeez, and this is a place with no rules.",{["Title"]="Removed Whitelisted Word",["Color"]={255,0,0},["Text"]="A word was manually removed from the whitelist."})
                            break
                        end
                    end
                    return
                elseif arguments[1] == "setcount" and arguments[2] ~= nil then
                    storagedata["CountChannel"]["Count"] = tonumber(arguments[2])
                    send(Channels["message-counting"],"_ _\nSukadia has manually set the message counter to **"..arguments[2].."**.\n_ _")
                elseif arguments[1] == "whitelistword" and arguments[2] ~= nil then
                    message:delete()
                    table.insert(storagedata["WhitelistedWords"],arguments[2])
                    send(channel,"**Sukadia** has manually whitelisted a word: **"..arguments[2].."**.")
                    return
                elseif arguments[1] == "restart" or arguments[1] == "silentrestart" then
                    message:delete()
                    if arguments[1] == "restart" then
                        storagedata["LastSaved"] = {os.time(), true, false}
                        send(channel,"Restarting ...")
                    else
                        storagedata["LastSaved"] = {os.time(), true, true}
                    end
                    if not DevMode then
                        Storage:save(storagedata)
                    end
                    os.exit()
                end
            end
        --
        
        if channel == Channels["important"] or channel == Channels["help"] or channel == Channels["test"] then
            return
        end
        
        
        --Delete messages containing special characters, morse code, or uses singular letters
            local i = 0
            for letter in string.gmatch(text,".") do
                i = i+1
                if string.match(letter,"%W") and string.match(letter,"%C") and string.match(letter,"%P") and string.match(letter,"%S") then
                    message:delete()
                    send(user.id,"Sorry, messages like that can contain too many possible bypasses.",{["Title"]="Message Deleted",["Color"]={255,0,0},["Text"]="The message you tried to send contains special characters that cannot be filtered. This may have been an emoji or non-keyboard symbol.\n\nYour message was deleted."})
                    return
                end
            end

            local morseletters = {".-","-...","-.-.","-..","..-.","--.",".---",".-..","-.",".--.","--.-","..-","...-",".--","-..-","-.--","--.."}
            for i, morse in pairs(morseletters) do
                if string.find(text,morse.." ",1,true) then
                    message:delete()
                    send(user.id,"Sneaky.. But has already been thought of.",{["Title"]="Message Deleted",["Color"]={255,0,0},["Text"]="The message you tried to send contains morse code. This is a bypass around implemented filters.\n\nYour message was deleted."})
                    return
                end
            end
            
            local nonemojimessage = text
            for i, emoji in pairs(Server.emojis) do
                nonemojimessage = string.gsub(nonemojimessage,"<:"..emoji.hash..">","")
                nonemojimessage = string.gsub(nonemojimessage,"<a:"..emoji.hash..">","")
            end
            local nonemojiwords = split(string.gsub(string.gsub(nonemojimessage,"%p",""),"%c"," "))
            for i, word in pairs(nonemojiwords) do
                if string.len(word) == 1 then
                    if nonemojiwords[i+1] ~= nil and nonemojiwords[i+2] ~= nil then
                        if string.len(nonemojiwords[i+1]) == 1 and string.len(nonemojiwords[i+2]) == 1 then
                            message:delete()
                            send(user.id,"Sorry, can't have you bypassing like that.",{["Title"]="Message Deleted",["Color"]={255,0,0},["Text"]="The message you tried to send uses singular letters to spell out words. This is a bypass around implemented filters.\n\nYour message was deleted."})
                            return
                        end
                    end
                end
            end
            
            if lastmessage[user.id] ~= nil then
                if #split(lastmessage[user.id]) == string.len(string.gsub(lastmessage[user.id],"%W","")) and #arguments == string.len(string.gsub(text,"%W","")) and string.len(lastmessage[user.id]) ~= 0 and string.len(text) ~= 0 then
                    message:delete()
                    send(user.id,"We serve *words* here sir.",{["Title"]="Message Deleted",["Color"]={255,0,0},["Text"]="The message you tried to send uses multiple messages to spell out a word. This is a bypass around implemented filters.\n\nYour message was deleted."})
                    return
                end
            end
            lastmessage[user.id] = text
        --
        
        
        if channel == Channels["type"] then
            local words, formattedwords = split(string.gsub(string.gsub(text,"%c"," "),"%p","")), split(string.gsub(originaltext,"%c"," "))
            
            local badwordcount = 0
            local checkedmessage = ""
            local symbolwordoffset = 0
            for i, word in pairs(words) do
                local lastword = false
                while string.gsub(string.lower(formattedwords[i+symbolwordoffset]),"%p","") ~= word do
                    checkedmessage = checkedmessage.." "..formattedwords[i+symbolwordoffset]
                    symbolwordoffset = symbolwordoffset + 1
                    if formattedwords[i+symbolwordoffset] == nil then
                        lastword = true
                        break
                    end
                end
                if lastword then
                    break
                end
                if not inTable(storagedata["WhitelistedWords"], word) then
                    if isEmoji(formattedwords[i+symbolwordoffset]) then
                        checkedmessage = checkedmessage.." "..formattedwords[i]
                    else
                        if badwordcount == 0 then
                            message:delete()
                        end
                        badwordcount = badwordcount + 1
                        checkedmessage = checkedmessage.." **"..formattedwords[i+symbolwordoffset].."**"
                    end
                else
                    checkedmessage = checkedmessage.." "..formattedwords[i+symbolwordoffset]
                end
            end
            
            checkedmessage = string.sub(checkedmessage,2,-1)
            
            if badwordcount > 0 then
                if string.len(checkedmessage) > 1800 then
                    send(user.id,"Jeez, that was a long message. Here's what the system has to say:",{["Title"]="Message Deleted",["Color"]={255,0,0},["Text"]="The message you tried to send contains **"..badwordcount.."** non-whitelisted words.\n\nYour message is too long to display the incorrect words. Send a shorter message in order to see it.\n\nYou may use the `check` command to find alternatives, or `suggest` your word to be added."})
                    return
                end
                
                if badwordcount == 1 and #words == 1 then
                    send(user.id,"Sorry, that word isn't whitelisted. Here's what the system has to say:",{["Title"]="Message Deleted",["Color"]={255,0,0},["Text"]="The message you tried to send contains **1** non-whitelisted word.\n\nThe following **bolded** words are not whitelisted:\n\""..checkedmessage.."\"\n\nYou may use the `check` command to find alternatives, or `suggest` your word to be added."})
                elseif badwordcount == 1 then
                    send(user.id,"Dang, one of your words aren't whitelisted. Here's what the system has to say:",{["Title"]="Message Deleted",["Color"]={255,0,0},["Text"]="The message you tried to send contains **1** non-whitelisted word.\n\nThe following **bolded** words are not whitelisted:\n\""..checkedmessage.."\"\n\nYou may use the `check` command to find alternatives, or `suggest` your word to be added."})
                elseif badwordcount == #words then
                    send(user.id,"Yikes, every single word you sent isn't whitelisted. Here's what the system has to say:",{["Title"]="Message Deleted",["Color"]={255,0,0},["Text"]="The message you tried to send contains **"..badwordcount.."** non-whitelisted words.\n\nThe following **bolded** words are not whitelisted:\n\""..checkedmessage.."\"\n\nYou may use the `check` command to find alternatives, or `suggest` your word to be added."})
                else
                    send(user.id,"A few of your words aren't whitelisted. Here's what the system has to say:",{["Title"]="Message Deleted",["Color"]={255,0,0},["Text"]="The message you tried to send contains **"..badwordcount.."** non-whitelisted words.\n\nThe following **bolded** words are not whitelisted:\n\""..checkedmessage.."\"\n\nYou may use the `check` command to find alternatives, or `suggest` your word to be added."})
                end
            else
                for i, word in pairs(words) do
                    local counted = false
                    for i, wordinfo in pairs(storagedata["WordCount"]) do
                        if wordinfo[1] == word then
                            counted = true
                            wordinfo[2] = wordinfo[2] + 1
                            break
                        end
                    end
                    if not counted then
                        table.insert(storagedata["WordCount"],{word,1})
                    end
                end
            end
            
            return
        end
        
        
        if channel == Channels["fuck-vowels"] then
            
            local vowels = {"a","e","i","o","u"}
            
            local novowelmessage = ""
            local formattedwords = split(originaltext)
            local deleted = false
            for i, word in pairs(formattedwords) do
                local novowelword = " "
                if i == 1 then
                    novowelword = ""
                end
                for letter in string.gmatch(word,".") do
                    local isvowel = false
                    for v, vowel in pairs(vowels) do
                        if string.lower(letter) == vowel then
                            isvowel = true
                            break
                        end
                    end
                    if isvowel then
                        if isEmoji(word) then
                            novowelword = " "..word
                            break
                        end
                        if not deleted then
                            message:delete()
                            deleted = true
                        end
                    else
                        novowelword = novowelword..letter
                    end
                end
                novowelmessage = novowelmessage..novowelword
            end
            
            if deleted then
                send(user.id,"I mean, I thought the channel's name was pretty self-explanatory.",{["Title"]="Message Deleted",["Color"]={255,0,0},["Text"]="The message you tried to send contains vowels.\n\nHere is a version of your message without vowels:\n\""..novowelmessage.."\""})
            end
            
            return
        end
        
        
        if channel == Channels["fuck-everything"] then
            wait(2)
            message:delete()
            return
        end
        
        
        if channel == Channels["message-counting"] then
            
            if storagedata["CountChannel"]["FailedUser"] == nil then
                storagedata["CountChannel"]["FailedUser"] = "0"
            end
            
            local function resetCount()
                storagedata["CountChannel"]["Count"] = 1
                storagedata["CountChannel"]["FailedUser"] = "0"
                storagedata["CountChannel"]["LastUser"] = "0"
                storagedata["CountChannel"]["LastMessage"] = "0"
                for i, counter in pairs(storagedata["CountChannel"]["Counters"]) do
                    counter[2] = 0
                end
            end
            
            if storagedata["CountChannel"]["FailedUser"] == user.id then
                message:delete()
                send(user.id,"Sorry, don't do the crime if you can't do the time.",{["Title"]="Message Deleted",["Color"]={255,0,0},["Text"]="You've broken the current on-going chain. You are not allowed to send messages until a new chain has started.\n\nThe counter was not reset."})
                return
            end
            
            local nonemojimessage = text
            for i, emoji in pairs(Server.emojis) do
                nonemojimessage = string.gsub(nonemojimessage,"<:"..emoji.hash..">","")
                nonemojimessage = string.gsub(nonemojimessage,"<a:"..emoji.hash..">","")
            end
            local messagelength = string.len(string.gsub(nonemojimessage,"[%p%c%s]",""))
            local playerdata, datapos
            for i, data in pairs(storagedata["CountChannel"]["Counters"]) do
                if data[1] == user.id then
                    playerdata = data
                    datapos = i
                end
            end
            local charplural = "s"
            if messagelength == 1 then
                charplural = ""
            end
            
            if messagelength == 0 then
                return
            end
            
            if playerdata == nil then
                if messagelength == storagedata["CountChannel"]["Count"] then
                    storagedata["CountChannel"]["Count"] = storagedata["CountChannel"]["Count"] + 1
                    table.insert(storagedata["CountChannel"]["Counters"],{user.id,1})
                    storagedata["CountChannel"]["LastUser"] = user.id
                    send(Channels["message-counting"],"Welcome **"..user.username.."**!\n\nEvery message in this channel must be one character longer than the last. When counting the characters in a message, I don't count spaces or punctuation. I also ignore zero length messages, like ones using only symbols.\n\nYou followed the channel's rules already, so this is just a message to welcome you. :)")
                else
                    message:delete()
                    table.insert(storagedata["CountChannel"]["Counters"],{user.id,0})
                    send(Channels["message-counting"],"Welcome **"..user.username.."**!\n\nEvery message in this channel must be one character longer than the last. When counting the characters in a message, I don't count spaces or punctuation. I also ignore zero length messages, like ones using only symbols.\n\nYour message was deleted because it was "..messagelength.." character"..charplural.." long instead of "..storagedata["CountChannel"]["Count"].." characters. However, the count was not reset since it's your first message. :)")
                    return
                end
            else
                if storagedata["CountChannel"]["LastUser"] == user.id then
                    message:delete()
                    send(user.id,"Sorry, you can't count by yourself.",{["Title"]="Message Deleted",["Color"]={255,0,0},["Text"]="You were the last person to count in #message-counting. Users must alternate counting in order for the message to be valid.\n\nThe counter was not reset."})
                elseif messagelength == storagedata["CountChannel"]["Count"] then
                    storagedata["CountChannel"]["Count"] = storagedata["CountChannel"]["Count"] + 1
                    storagedata["CountChannel"]["LastUser"] = user.id
                    storagedata["CountChannel"]["LastMessage"] = message.id
                    storagedata["CountChannel"]["Counters"][datapos][2] = playerdata[2]+1
                    if storagedata["CountChannel"]["Count"]-1 == 69 then
                        send(channel,"[ **69** ]\nFunny.")
                    elseif storagedata["CountChannel"]["Count"]-1 == 100 then
                        send(channel,"[ **100** ]\n5% of the way there. A good start. :)")
                    elseif storagedata["CountChannel"]["Count"]-1 == 200 then
                        send(channel,"[ **200** ]\n10% of the way there. Slowly but surely.")
                    elseif storagedata["CountChannel"]["Count"]-1 == 420 then
                        send(channel,"[ **420** ]\nAlright.")
                    elseif storagedata["CountChannel"]["Count"]-1 == 500 then
                        send(channel,"[ **500** ]\n25% of the way there! This is a *lot* of messages.")
                    elseif storagedata["CountChannel"]["Count"]-1 == 1000 then
                        send(channel,"[☆ **1000** ☆]\n50% of the way there! Never expected it to get this far. :)")
                    elseif storagedata["CountChannel"]["Count"]-1 == 1500 then
                        send(channel,"[☆ **1500** ☆]\n75% of the way there! Keep pushing, you're almost to the end!")
                    elseif storagedata["CountChannel"]["Count"]-1 == 2000 then
                        --[[
                        Censored until reached
                        ]]--
                    end
                elseif storagedata["CountChannel"]["Count"] == 1 then
                    message:delete()
                    send(user.id,"You broke the chain before it even started.. I won't send a message in the channel, but I *will* send a message here to express my concern.")
                else
                    message:delete()
                    if storagedata["CountChannel"]["FailedUser"] == "0" then
                        storagedata["CountChannel"]["FailedUser"] = user.id
                        send(Channels["message-counting"],"**"..user.username.."** broke the message chain by sending a "..messagelength.." character long message instead of a "..storagedata["CountChannel"]["Count"].." character long one.\n\n"..user.username.." has lost message permissions, however the next chain-break will result in the counter being reset.")
                        return
                    end
                    table.sort(storagedata["CountChannel"]["Counters"], function(a,b)
                        return a[2] > b[2]
                    end)
                    local contributionplural = "s"
                    if storagedata["CountChannel"]["Counters"][1][2] == 1 then
                        contributionplural = ""
                    end
                    send(Channels["message-counting"],"Ouch, **"..user.username.."** broke the message chain. Their message was "..messagelength.." character"..charplural.." long instead of "..storagedata["CountChannel"]["Count"]..".\n\n"..Client:getUser(storagedata["CountChannel"]["Counters"][1][1]).username.." contributed the most with "..storagedata["CountChannel"]["Counters"][1][2].." message"..contributionplural..".")
                    resetCount()
                end
            end
            return
        end
        
        
        if channel == Channels["images"] then
            if message.content ~= "" then
                message:delete()
                send(user.id,"Sorry, can't have any text in your message.",{["Title"]="Message Deleted",["Color"]={255,0,0},["Text"]="The message you tried to send contains text. #images only allows images."})
                return
            elseif #message.attachments > 1 then
                message:delete()
                send(user.id,"Sorry, it's just difficult to identify each attachment.",{["Title"]="Message Deleted",["Color"]={255,0,0},["Text"]="The message you tried to send contains more than one attachment. #images only allows one per message."})
                return
            elseif not message.attachment.height then
                message:delete()
                send(user.id,"Uhhh, yea, not an image.",{["Title"]="Message Deleted",["Color"]={255,0,0},["Text"]="The attachment you tried to send is not an image. #images only allows images."})
                return
            elseif message.attachment.size > 2048 then
                message:delete()
                local kilobytes = message.attachment.size/1024
                if kilobytes > 1024 then
                    send(user.id,"Jeez, that's a big image.",{["Title"]="Message Deleted",["Color"]={255,0,0},["Text"]="The image you tried to send was **"..round(kilobytes/1024,3).." megabytes**. #images only allows images under 2 kilobytes.\n\nThis website by Velleda can make it the right size: `image-compressor.glitch.me`"})
                elseif kilobytes > 50 then
                    send(user.id,"Yea, too big of an image.",{["Title"]="Message Deleted",["Color"]={255,0,0},["Text"]="The image you tried to send was **"..round(kilobytes,3).." kilobytes**. #images only allows images under 2 kilobytes.\n\nThis website by Velleda can make it the right size: `image-compressor.glitch.me`"})
                else
                    send(user.id,"I mean, you were close.",{["Title"]="Message Deleted",["Color"]={255,0,0},["Text"]="The image you tried to send was **"..round(kilobytes,3).." kilobytes**. #images only allows images under 2 kilobytes.\n\nThis website by Velleda can make it the right size: `image-compressor.glitch.me`"})
                end
            end
            return
        end
        
    end
end

Client:on("messageCreate",NewMessage)
Client:on("messageUpdate",NewMessage)


Client:run("Bot "..BotToken)
