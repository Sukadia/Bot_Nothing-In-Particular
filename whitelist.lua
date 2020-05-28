--Monopoly idea: You start with one word randomly given to you, you can use it in the specific channel but only that word. Every time you use the word (with a 5 minute debounce) you get letter currency. This might be something low like 0.08 letters. With letters you can request a word for the # of letters in it. There is a market when you request to buy a word, and people can bid for it. A person can bid all their letters +10% (or something) so they'd go in debt if they get it. Once a person owns a word, they must set a price to it for rent. It must be rentable, and the higher the price the more tax there will be on it. Tax will be linear, but because of the higher price it'll actually exponentially get worse because less people will buy it too.

local token = "RealTokenHere"
local serverid = "669338665956409374"

local discordia = require("discordia")
local timer = require("timer")
local client = discordia.Client()
local Enum = discordia.enums
local Permissions = discordia.Permissions()

local Storage = require("libs/Storage")
local Json = require("json")
local Coro = require("coro-http")

-- Data

local messagecooldown = {}  --{[dmchannelid]={messagetime1, ...}}  --Logs each time the bot DMs the user, used to stop spam of >3 messages in 5 seconds

local whitelistedwords = {} --{"word1", ...}                       --List of all whitelisted words, used to compare all of a message's words
local usersuggested = {}    --{userid1, ...}                       --List of all users who've suggested for the timeframe, used to block more suggestions
local suggestedwords = {}   --{"suggested1", ...}                  --List of all user suggested words
local definitionlog = {}    --{[word]="loggeddefinition"}          --Logs all recieved definitions to minimize api usage limit (1000 a day)
local inventories = {}      --{[userid]="ability"}                 --Logs what singular ability the user has, given through random events
local wordcounter = {}      --{{"word",numberofuses}, ...}         --List of all singular uses of each whitelisted word, sorted high to low, worduse cmd
local ideabuffer = {}       --{[userid]=timesubmitted}             --Logs what time the user submitted an idea, used to block more ideas within an hour
local disablepika = {}      --{userid1, ...}                       --List of all userids that shouldn't get the stare, given when submitting an idea

-- Functions

function dump(o) --Decode tables into printable format, returns string
   if type(o) == 'table' then
      local s = '{ '
      for k,v in pairs(o) do
         if type(k) ~= 'number' then k = '"'..k..'"' end
         s = s .. '['..k..'] = ' .. dump(v) .. ','
      end
      return s .. '} '
   else
      return tostring(o)
   end
end

function round(num, numDecimalPlaces) --Round numbers to a decimal, returns number
    local mult = 10^(numDecimalPlaces or 0)
    return math.floor(num * mult + 0.5) / mult
end

function checkWhitelist(word) --Checks if word is in whitelist, returns true or false
    for i, whitelistword in pairs(whitelistedwords) do
        if whitelistword == word then
            return true
        end
    end
    return false
end

function makeChannel(name) --Creates a new channel
    return server:createTextChannel(name)
end

function wait(seconds) --Waits for # of seconds
   timer.sleep(seconds*1000)
end

function split(text) --Splits all the different text separated by spaces, returns list
    local words = {}
    for word in text:gmatch("%w+") do table.insert(words, word) end
    return words
end

function channelPermsEdit(channel,permtype,userid) --Changes channel perms for @everyone or a user
    local role
    if userid == nil then
        role = server:getRole(serverid)
    else
        role = server:getMember(userid)
    end
    local perms = channel:getPermissionOverwriteFor(role)
    if permtype == "readchannel" then
        local permobject = Permissions.fromMany(Enum.permission.readMessageHistory,Enum.permission.readMessages)
        perms:setAllowedPermissions(permobject)
    elseif permtype == "messagechannel" then
        if userid == nil then
            local permobject = Permissions.fromMany(Enum.permission.readMessageHistory,Enum.permission.readMessages,Enum.permission.sendMessages)
            perms:setAllowedPermissions(permobject)
        else
            perms:delete()
        end
    elseif permtype == "imagechannel" then
        local permobject = Permissions.fromMany(Enum.permission.readMessageHistory,Enum.permission.readMessages,Enum.permission.sendMessages,Enum.permission.attachFiles) 
        perms:setAllowedPermissions(permobject)
    elseif permtype == "speakchannel" then
        local permobject = Permissions.fromMany(Enum.permission.connect,Enum.permission.speak,Enum.permission.useVoiceActivity,Enum.permission.readMessages)
        perms:setAllowedPermissions(permobject)
    elseif permtype == "nospeakchannel" then
        local permobject = Permissions.fromMany(Enum.permission.readMessages)
        perms:setAllowedPermissions(permobject)
    elseif permtype == "clear" then
        perms:delete()
    end
end

function getRandomWords(num) --Calls the random word API, returns list
    local words
    print("Pinging word API..")
    result, words = Coro.request("GET","https://random-word-api.herokuapp.com/word?number="..num)
    print("Success")
    return Json.decode(words)
end

function defineWord(word) --Calls the Merriam-Webster dictionary API, returns string
    local definition = ""
    if definitionlog[word] == nil then
        result, body = Coro.request("GET","https://dictionaryapi.com/api/v3/references/collegiate/json/"..word.."?key=RealKeyHere")
        local table = Json.decode(body)
        if table[1]["shortdef"] ~= nil then
            for i, def in pairs(table[1]["shortdef"]) do
                definition = definition.."["..i.."]: "..def.."\n"
            end
        else
            local string = ""
            for i, similarword in pairs(table) do
                string = string..similarword..", "
            end
            string = string.sub(string,1,-3)
            definition = "This word is not a dictionary-worthy word, and thus has no definition.\nHowever, here's some random words that look kinda similar to it:\n("..string..")"
        end
        definitionlog[word] = definition
    else
        definition = definitionlog[word]
    end
    return definition
end

function send(channel,message,bypass) --Sends a message and checks for spam, returns message object
    bypass = bypass or false
    if not bypass then
        if channel.type == Enum.channelType.private then
            if messagecooldown[channel] == nil then
                messagecooldown[channel] = {os.time()}
            else
                if messagecooldown[channel] == "Muted" then
                    do return end
                end
                table.insert(messagecooldown[channel],os.time())
                local temp = {}
                for i, messagetime in pairs(messagecooldown[channel]) do
                    if messagetime+5 > os.time() then
                        table.insert(temp,messagetime)
                    end
                end
                messagecooldown[channel] = temp
                if #messagecooldown[channel] > 3 then
                    messagecooldown[channel] = "Muted"
                    channel:send("_ _\nWoah, sorry. I can't respond to more than 3 messages every five seconds.\nAs a procaution I have to mute/ignore you for a good 30 seconds. I'll tell you when you're good to go.")
                    channelPermsEdit(MessageChannel,"readchannel",channel.recipient)
                    channelPermsEdit(ImageChannel,"readchannel",channel.recipient)
                    channelPermsEdit(VowelChannel,"readchannel",channel.recipient)
                    wait(30)
                    channelPermsEdit(MessageChannel,"messagechannel",channel.recipient)
                    channelPermsEdit(ImageChannel,"imagechannel",channel.recipient)
                    channelPermsEdit(VowelChannel,"messagechannel",channel.recipient)
                    channel:send("_ _\nOkay, you're good now.")
                    messagecooldown[channel] = nil
                    do return end
                end
            end
        end
    end
    local newmessage
    pcall(function()
        newmessage = channel:send(message)
    end)
    return newmessage
end

local function addWords() --Runs through and picks random words and suggested words, adds them and announces their addition
        local wordsneeded = 3
        local wordtext = "The following words have been whitelisted: "
        while wordsneeded ~= 0 do
            local newwords = getRandomWords(20)
            for i, newword in pairs(newwords) do
                if wordsneeded == 0 then
                    break
                end
                local inwhitelist = checkWhitelist()
                if not inwhitelist then
                    wordsneeded = wordsneeded - 1
                    table.insert(whitelistedwords,newword)
                    if wordsneeded == 0 then
                        wordtext = wordtext.."and **"..newword.."**."
                    else
                        wordtext = wordtext.."**"..newword.."**, "
                    end
                end
            end
        end
        local usertext
        if #suggestedwords == 0 then
            usertext = "\nNo user submissions were collected."
        elseif #suggestedwords == 1 then
            table.insert(whitelistedwords,suggestedwords[1])
            usertext = "\n1 user submission was collected and whitelisted: **"..suggestedwords[1].."**."
        else
            local num = math.random(1,#suggestedwords)
            table.insert(whitelistedwords,suggestedwords[num])
            local word1,length = suggestedwords[num], #suggestedwords
            usertext = "\n"..#suggestedwords.." user submissions were collected. The following were whitelisted: **"..suggestedwords[num].."** and "
            local temptable = suggestedwords
            for i = #suggestedwords, 0, -1 do --incase of suggestion repeats
                if suggestedwords[i] == word1 then
                    table.remove(temptable,i)
                end
            end
            suggestedwords = temptable
            if #suggestedwords == 0 then
                usertext = "\n"..length.." user submissions were collected. It was unanimously decided the new whitelisted word is: **"..word1.."**."
            else
                num = math.random(1,#suggestedwords)
                table.insert(whitelistedwords,suggestedwords[num])
                usertext = usertext.."**"..suggestedwords[num].."**."
            end
        end
        suggestedwords = {}
        usersuggested = {}
        
        table.sort(whitelistedwords)
        data["SuggestedWords"] = {}
        data["SuggestedUsers"] = {}
        data["Words"] = whitelistedwords
        Storage:saveTable(data)
        send(MessageChannel,wordtext..usertext)
    end

--

client:on("ready", function()
    
    --Gathers info needed for running
    server = client:getGuild(serverid)
    data = Storage:getTable()
    MessageChannel = server:getChannel("702348672007929888")
    ImageChannel = server:getChannel("713449279548817560")
    VoiceStatusChannel = server:getChannel("713500391714717697")
    SpeakChannel = server:getChannel("713500471825793095")
    VowelChannel = server:getChannel("715371845070618674")
    
    local bypass = false
    local userbypass = {}
    local function checkMessage(message) --Main function that is run for every message and edit, filters words + accepts commands
        
        --Precursor message events, logs user DM channel, ignores bot messages
        if message.author.bot then
            return
        end
        local channel = message.channel
            
        --Handles DM commands
        if channel.type == Enum.channelType.private then
            
            --Removes all symbols, splits text into a list of strings for each word
            local text = string.gsub(string.lower(message.content),"[%p%c]","")
            local messagewords = split(text)
            
            --Suggest command, logs suggestions and accepts a whitelisted word ability for a free word
            if messagewords[1] == "suggest" and messagewords[2] ~= nil then
                local accepted = true
                for i, usedplayer in pairs(usersuggested) do
                    if usedplayer == message.author.id then
                        accepted = false
                        break
                    end
                end
                if accepted or inventories[message.author.id] == "suggest" then
                    local used = checkWhitelist(messagewords[2])
                    if used then
                        send(channel,"Surprisingly that word is already whitelisted. Perhaps suggest a different one?")
                    elseif string.len(messagewords[2]) > 20 then
                        send(channel,"That is a real long word. How about something *under* 20 letters?")
                    elseif inventories[message.author.id] == "suggest" then
                        local temp = {}
                        for i, suggestedword in pairs(suggestedwords) do
                            if suggestedword ~= messagewords[2] then
                                table.insert(temp,suggestedword)
                            end
                        end
                        suggestedwords = temp
                        send(channel,"Alright, whatever you say. The word \"**"..messagewords[2].."**\" is now whitelisted.")
                        table.insert(whitelistedwords,messagewords[2])
                        send(MessageChannel,message.author.username.." has whitelisted the following word: **"..messagewords[2].."**.")
                        inventories[message.author.id] = nil
                        local temp = {}
                        for i, suggestedword in pairs(suggestedwords) do
                            if suggestedword ~= messagewords[2] then
                                table.insert(temp,suggestedword)
                            end
                        end
                        suggestedwords = temp
                        for i, suggestedid in pairs(usersuggested) do
                            if suggestedid == message.author.id then
                                table.remove(usersuggested,i)
                                break
                            end
                        end
                        data["Inventory"] = inventories
                        Storage:saveTable(data)
                    else
                        table.insert(suggestedwords,messagewords[2])
                        table.insert(usersuggested,message.author.id)
                        send(channel,"Alright, whatever you say. I've got the word \"**"..messagewords[2].."**\" in the voting line.")
                        data["SuggestedUsers"] = usersuggested
                        data["SuggestedWords"] = suggestedwords
                        Storage:saveTable(data)
                    end
                else
                    send(channel,"Sorry, you can't vote more than once for each 3 hour period.\n_ _")
                end
            
            --Wordlist command, gives the user all the whitelisted words, can also search for words starting with letters
            elseif messagewords[1] == "wordlist" then
                if messagewords[2] == nil then
                local string = "There's **"..#whitelistedwords.."** words you can say:\n\n"
                    for i, word in pairs(whitelistedwords) do
                        string = string..word..", "
                        if string.len(string) > 2000 then
                            string = string.sub(string,1,-string.len(word)-3)
                            send(channel,string,true)
                            string = word..", "
                        end
                    end
                    string = string.sub(string,1,-3)
                    send(channel,string)
                else
                    local string = "Here's all the words that start with **"..messagewords[2].."**:\n\n"
                    local wordsmatch = 0
                    for i, word in pairs(whitelistedwords) do
                        if string.sub(word,1,string.len(messagewords[2])) == messagewords[2] then
                            wordsmatch = wordsmatch + 1
                            string = string..word..", "
                            if string.len(string) > 2000 then
                                string = string.sub(string,1,-string.len(word)-3)
                                send(channel,string)
                                string = word..", "
                            end
                        end
                    end
                    if wordsmatch > 0 then
                        string = string.sub(string,1,-3)
                        send(channel,string)
                    else
                        send(channel,"There's no whitelisted words that start with **"..messagewords[2].."**.")
                    end
                end
            
            --Define command, gives the user all the short Merriam-Webster dictionary definitions of the word
            elseif messagewords[1] == "define" and messagewords[2] ~= nil then
                local approved = checkWhitelist(messagewords[2])
                if approved then
                    send(channel,"You want to know what **"..messagewords[2].."** means? Here's what my sources say:\n\n"..defineWord(messagewords[2]))
                else
                    send(channel,"That word isn't in the whitelist, so it's worthless to me.")
                end  
            
            --Worduse command, gives the top 10 of how many times a word has been individually said. Can search specific words, and has pages
            elseif messagewords[1] == "worduse" then
                table.sort(wordcounter, function(a,b)
                    return a[2] > b[2]
                end)
                if messagewords[2] ~= nil then
                    local word = tonumber(messagewords[2])
                    if word ~= nil then
                        word = math.floor(word)
                        if word >= 1 and wordcounter[(word*10)-9] ~= nil then
                            local string = "Here's the top "..((word*10)-9).."-"..(word*10).." most used words:\n\n"
                            for i=((word*10)-9), (word*10) do
                                if wordcounter[i] ~= nil then
                                    string = string..i..". "..wordcounter[i][1].." - "..wordcounter[i][2].."\n"
                                    if i == (word*10) and wordcounter[(word*10)+1] ~= nil then
                                        string = string.."\nType `worduse "..(word+1).."` to see the next page."
                                    end
                                else
                                    string = string.."\nThere are no positions past "..i.."."
                                    break
                                end
                            end
                            send(channel,string)
                        else
                            send(channel,"That page doesn't exist.")
                        end
                    else
                        word = messagewords[2]
                        if checkWhitelist(word) then
                            for i, wordinfo in pairs(wordcounter) do
                                if wordinfo[1] == word then
                                    local s = "s"
                                    if wordinfo[2] == 1 then
                                        s = ""
                                    end
                                    send(channel,"The word **"..word.."** has been used **"..wordinfo[2].."** time"..s..".\nIt is position **"..i.."** in the most used words.")
                                    return
                                end
                            end
                            send(channel,"The word **"..word.."** has never been used.")
                        else
                            send(channel,"I only keep track of whitelisted words, that word isn't in the whitelist.")
                        end
                    end
                else
                    local string = "Here's the top 1-10 most used words:\n\n"
                    for i=1, 10 do
                        if wordcounter[i] ~= nil then
                            string = string..i..". "..wordcounter[i][1].." - "..wordcounter[i][2].."\n"
                            if i == 10 and wordcounter[11] ~= nil then
                                string = string.."\nType `worduse 2` to see the next page."
                            end
                        else
                            string = string.."\nThere are no positions past "..i.."."
                            break
                        end
                    end
                    send(channel,string)
                end
                
            --Help command, just gives the information about the bot very vaguely
            elseif messagewords[1] == "help" then
                send(channel,"Hello!\nYou've entered the help menu. What do you need help with?\n\n*What is this `server`?*\n*What are the `commands`?*\n*How does the `whitelist` channel work?*\n*How does the `vowel` channel work?*\n*How does the `image` channel work?*\n*Tell me about the `development`.*\n*What's the `code`?*\n\n**Type `exit` when you're done.**")
                local exitloop = false
                while not exitloop do
                    local timeout = client:waitFor("messageCreate",120*1000,function(message)
                        if message.channel == channel and not message.author.bot then
                            local command = string.lower(message.content)
                            if command == "server" then
                                send(channel,"Welcome to Sukadia's server!\n\nI'm the bot that runs everything, the server is effectively closed when I'm down during nighttime and testing.\n\nSukadia updates the bot pretty often, and pings @here for new bot features and certain polls. I'd recommend suppressing/muting these pings if you aren't interested.\n\nThe #important channel is basically the only way to get active information on stuff, other than DMing Sukadia himself. Speaking of which, if you have a bot idea you can anonymously send to to Sukadia via the `idea` command.\n\n**Type another keyword or `exit` to continue.**")
                            elseif command == "commands" then
                                send(channel,"Here's all the commands you can DM me:\n\n`wordlist [letters]` Gives you all the whitelisted words. If letters are provided, lists all words which start with them.\n`suggest (word)` Adds a word to the user-submission lineup to be randomly chosen every three hours.\n`worduse [word]` Lists the top 10 most used words. If a word is provided, lists how many times that word has been used.\n`define (word)` Gives you all of the definitions of the whitelisted word from the Merriam-Webster dictionary.\n\n`filesize` Gives you the size of the bot's savedata file.\n`idea` Allows you to send an anonymous message to Sukadia with an idea or anything similar.\n\n**Type another keyword or `exit` to continue.**")   
                            elseif command == "whitelist" then
                                send(channel,"The whitelist channel is somewhat basic, but is the main channel of the server.\n\nNow the obvious is that you can't say any word outside of the whitelist. However, you can suggest a word to be whitelisted if randomly chosen by using the `suggest (word)` command.\n\nThe channel works on a schedule, every 3 hours the bot picks three words and two user-suggested words randomly and adds them to the whitelist. Also, near the middle of each hour there's a chance for a special event to happen that'll give you an ability.\n\nThere isn't very much other than that, check the `commands` keyword to see what you can do with the whitelist.\n\n**Type another keyword or `exit` to continue.**")
                            elseif command == "vowel" then
                                send(channel,"The vowel channel is really basic.\n\nYou're not allowed to send any messages containing vowels. If you do, the bot will gladly send you a new version that excludes vowels.\n\n**Type another keyword or `exit` to continue.**")
                            elseif command == "image" then
                                send(channel,"In the image channel you can only send images, the messages themselves can't contain text or any sort of link. Another caveat, these images must be under 2KB in size.\n\nThat may seem really low, but this encompasses basic small images, and Pugduddly has created a tool (pinned in the channel) which compresses your image to the acceptable size! Very neat.\n\n**Type another keyword or `exit` to continue.**")
                            elseif command == "development" then
                                send(channel,"To kill time, Sukadia programs this bot and adds features to it.\n\nThe bot runs in the Lua programming language and the Lua discord api, Discordia.\n\nIt started out as just a funny joke to add to the empty server, but started to be something I could keep adding on to. I would run it 24/7, but I don't have a hosting service to use and don't want to leave my computer running overnight.\n\n**Type another keyword or `exit` to continue.**")
                            elseif command == "code" then
                                send(channel,"I have a public github that reflects the current features of the bot. It is not real-time, so it's only updated after a change is made (not during development of a change).\n\nhttps://github.com/Sukadia/-Public-Whitelist-Bot-\n\n**Type another keyword or `exit` to continue.**")
                            elseif command == "exit" or command == "cancel" then
                                send(channel,"Hope whatever I answered helped! DM Sukadia for further inquiries.\n\nAny message past here will be accepted as a command.")
                                exitloop = true
                            else
                                send(channel,"I'm not sure what you said. You can get help by saying the keywords above or saying `exit`.")
                            end
                            return true
                        end
                    end)
                    if timeout == false then
                        exitloop = true
                        send(channel,"_ _\nIt's been two minutes since your last message, I'm going to close the help menu for you.\n\nAny message past here will be accepted as a command.")
                    end
                end
                
            --Idea command, allows 1 anonymous message DMed to me per hour per user
            elseif messagewords[1] == "idea" then
                if ideabuffer[message.author.id] ~= nil then
                    if ideabuffer[message.author.id]+3600 > os.time() then
                        send(channel,"Sorry, you've already sent an idea in the past hour. Wait for a while or message Sukadia directly.")
                        return
                    else
                        ideabugger[message.author.id] = nil
                    end
                end
                if messagewords[2] ~= nil then
                    send(channel,"Sorry, I'm pretty sure you put your idea in the command itself. Follow the instructions below- this is so I can format the message properly when it's sent to Sukadia.\n_ _")
                end
                table.insert(disablepika,message.author.id)
                send(channel,"Please send me your idea in a new message. This will be sent anonymously and directly to Sukadia (so there will be no response). Make sure to include everything necessary- you're allowed one message every hour.\n\nType `cancel` to cancel this process.")
                local timeout = client:waitFor("messageCreate",600*1000,function(message)
                    if message.channel == channel and not message.author.bot then
                        if string.lower(message.content) == "cancel" then
                            send(channel,"Idea process cancelled. Any message past here will be accepted as a command.")
                            return true
                        else
                            local SukadiaDM = client:getUser("143172810221551616"):getPrivateChannel()
                            send(SukadiaDM,"**New idea submission:**\n\n"..message.content)
                            send(channel,"Your message has been sent to Sukadia. Any message past here will be accepted as a command.")
                            ideabuffer[message.author.id] = math.floor(os.time())
                            return true
                        end
                    end
                end)
                if timeout == false then
                    send(channel,"Sorry, you took more than 10 minutes to respond. Try the command again if you're still typing.\n\nAny message past here will be accepted as a command.")
                end
                for i, user in pairs(disablepika) do
                    if user == message.author.id then
                        table.remove(disablepika,i)
                        break
                    end
                end
            
            elseif messagewords[1] == "filesize" then
                local savedata = io.open("savedata", "r")
                local size = savedata:seek("end")
                local datatype = " B"
                if size > 1000 then
                    size = size/1000
                    datatype = " KB"
                end
                size = round(size,3)
                send(channel,"It looks like the savedata file size right now is "..size..datatype..".")
                io.close(savedata)
                
            --Unknown command, sends a staring pikachu instead- unless you're in the idea submission or muted
            else
                for i, user in pairs(disablepika) do
                    if user == message.author.id then
                        return
                    end
                end
                if not messagecooldown[channel] == "Muted" then
                    channel:send{file = "pikachustare.png"}
                end
            end
                
                
                
        --Handles filtering Whitelist channel messages, can also accept commands
        elseif channel == MessageChannel then
            
            --Prepares word, uses an event-given bypass if 'bypass' is said
            local text = string.lower(message.content)
            local messagewords = split(text)
            if messagewords[1] == "bypass" and inventories[message.author.id] == "bypass" then
                table.insert(userbypass,message.author.id)
                inventories[message.author.id] = nil
                data["Inventory"] = inventories
                Storage:saveTable(data)
                message:delete()
                return
            end
            
            --Uses filter bypass if the user used one, ignores filtering the message
            if #userbypass > 0 then
                for i, user in pairs(userbypass) do
                    if user == message.author.id then
                        table.remove(userbypass,i)
                        local usemessage = send(MessageChannel,"Bypass used.")
                        wait(3)
                        usemessage:delete()
                        return
                    end
                end
            end
            
            --Ignore filtering if Sukadia used the bypass command
            if bypass and message.author.id == "143172810221551616" then
                bypass = false
                return
            else
                
                --Check for non-alphanumeric and punctuation symbols, delete message and DM what wasn't allowed.
                local i = 0
                for letter in string.gmatch(text,".") do
                    i = i+1
                    if (string.match(letter,"%W") and string.match(letter,"%C") and string.match(letter,"%P") and string.match(letter,"%S")) or letter == "-" or letter == "_" then
                        text = string.sub(text,1,i-1).."**[** "..letter.." **]**"..string.sub(text,i+1)
                        message:delete()
                        local DM = message.author:getPrivateChannel()
                        local message = send(DM,"_ _\nHi.\nThe last message you sent was deleted. I've bracketed a symbol that isn't allowed: \n\n\""..text.."\"")
                        if message == nil then
                            print("ERROR RESOLVED")
                            send(DM,"_ _\nHi.\nThe last message you sent was deleted. You sent an emoji that isn't whitelisted.")
                        end
                        return
                    end
                end
                text = string.gsub(text,"[%p%c]","")
            end
            messagewords = split(text)
            
            --Sukadia-specific commands, self-explanatory
            if message.author.id == "143172810221551616" then
                if messagewords[1] == "bypass" then
                    bypass = true
                    message:delete()
                    return
                elseif messagewords[1] == "newwords" then
                    addWords()
                    message:delete()
                    return
                elseif messagewords[1] == "additem" and messagewords[3] ~= nil then
                    inventories[messagewords[2]] = messagewords[3]
                    data["Inventory"] = inventories
                    Storage:saveTable(data)
                    message:delete()
                    return
                elseif messagewords[1] == "whitelist" then
                    if messagewords[2] ~= nil then
                        table.insert(whitelistedwords,messagewords[2])
                    end
                    data["Words"] = whitelistedwords
                    Storage:saveTable(data)
                    message:delete()
                    send(channel,"A word has been manually whitelisted: **"..messagewords[2].."**.")
                    return
                elseif messagewords[1] == "openserver" then
                    message:delete()
                    channelPermsEdit(MessageChannel,"messagechannel")
                    channelPermsEdit(VowelChannel,"messagechannel")
                    channelPermsEdit(ImageChannel,"imagechannel")
                    channelPermsEdit(SpeakChannel,"speakchannel")
                    send(channel,"Server Reopened")
                    return
                elseif messagewords[1] == "closeserver" then
                    message:delete()
                    channelPermsEdit(MessageChannel,"readchannel")
                    channelPermsEdit(VowelChannel,"readchannel")
                    channelPermsEdit(ImageChannel,"readchannel")
                    channelPermsEdit(SpeakChannel,"nospeakchannel")
                    send(channel,"Server Closing")
                    return
                elseif messagewords[1] == "restart" then
                    message:delete()
                    send(channel,"A restart has been requested.\n\nRestarting...")
                    channelPermsEdit(MessageChannel,"readchannel")
                    channelPermsEdit(VowelChannel,"readchannel")
                    channelPermsEdit(ImageChannel,"readchannel")
                    channelPermsEdit(SpeakChannel,"nospeakchannel")
                    os.execute("luvit restart")
                    os.exit()
                end
            end
            
            --Logs each word in the message if they're not whitelisted
            local badwords = {}
            for i, word in pairs(messagewords) do
                if checkWhitelist(word) == false then
                    table.insert(badwords,word)
                end
            end
            
            if #badwords > 0 then
                
                --Deletes message and DMs the words in bold that weren't whitelisted
                message:delete()
                local attemptedsentence = ""
                for i, word in pairs(messagewords) do
                    local approved = true
                    for v, badword in pairs(badwords) do
                        if word == badword then
                            approved = false
                            attemptedsentence = attemptedsentence.."**"..word.."** "
                            break
                        end
                    end
                    if approved then
                        attemptedsentence = attemptedsentence..word.." "
                    end
                end
                attemptedsentence = string.sub(attemptedsentence,1,-2)
                local DM = message.author:getPrivateChannel()
                send(DM,"_ _\nHi.\nThe last message you sent was deleted. I bolded the words that weren't on the whitelist:\n\n\""..attemptedsentence.."\"")
            else
                
                --Adds how many uses of the word into the word counter
                for i, word in pairs(messagewords) do
                    local incounter = false
                    for v, wordinfo in pairs(wordcounter) do
                        if wordinfo[1] == word then
                            incounter = true
                            wordcounter[v][2] = wordcounter[v][2] + 1
                            break
                        end
                    end
                    if not incounter then
                        table.insert(wordcounter,{word,1})
                    end
                end
                data["WordCount"] = wordcounter
                Storage:saveTable(data)
            end
        
        --Handles filtering Image channel messages, removes any image over 2KB or isn't an image
        elseif channel == ImageChannel then
            if bypass and message.author.id == "143172810221551616" then
                bypass = false
                return
            end
            if message.content ~= "" then
                message:delete()
                local DM = message.author:getPrivateChannel()
                if message.embed ~= nil then
                    send(DM,"_ _\nHi.\nYou're not allowed to post links to images. ~~Links give you too much freedom.~~")
                else
                    send(DM,"_ _\nHi.\nYou're not allowed to type any text in the image channel. It is an image channel, afterall.")
                end
                return
            elseif #message.attachments > 1 then
                message:delete()
                local DM = message.author:getPrivateChannel()
                send(DM,"_ _\nHi.\nYou can't send more than 1 image in a message. I would allow it, but it'd be too difficult to point to which one I'm talking about.")
                return
            elseif message.attachment.height == nil then
                message:delete()
                local DM = message.author:getPrivateChannel()
                send(DM,"_ _\nHi.\nYou sent a file.. but it isn't an image. Your file needs to be in an image format for me to accept it.")
                return
            elseif message.attachment.size > 2048 then
                message:delete()
                local size = message.attachment.size/1024
                local datatype = " kilobytes"
                if size > 1024 then
                    size = size/1024
                    datatype = " megabytes"
                end
                local DM = message.author:getPrivateChannel()
                send(DM,"_ _\nHi.\nYour image is "..round(size,3)..datatype..". You may only post images under 2 kilobytes.")
            end
            
        --Handles filtering Vowel channel messages, removes any message that contains vowels
        elseif channel == VowelChannel then
            local text = string.lower(message.content)
            local messagewords = split(text)
            
            --Ignore filtering if the bypass command was used in the other channel
            if bypass and message.author.id == "143172810221551616" then
                bypass = false
                return
            else
                local i = 0
                for letter in string.gmatch(text,".") do
                    i = i+1
                    if (string.match(letter,"%W") and string.match(letter,"%C") and string.match(letter,"%P") and string.match(letter,"%S")) or letter == "-" or letter == "_" then
                        text = string.sub(text,1,i-1).."**[** "..letter.." **]**"..string.sub(text,i+1)
                        message:delete()
                        local DM = message.author:getPrivateChannel()
                        local message = send(DM,"_ _\nHi.\nThe last message you sent was deleted. I've bracketed a symbol that isn't allowed: \n\n\""..text.."\"")
                        if message == nil then
                            print("ERROR RESOLVED")
                            send(DM,"_ _\nHi.\nThe last message you sent was deleted. Emojis are blacklisted by default.")
                        end
                        return
                    end
                end
            end
            
            local vowels = {"a","e","i","o","u"}
            local nonvowel = ""
            local v = 0
            local letterlist = {}
            local deleted = false
            string.gsub(text,".",function(c) table.insert(letterlist,c) end)
            for letter in string.gmatch(string.lower(text),".") do
                v = v+1
                local hasvowel = false
                for i, vowel in pairs(vowels) do
                    if vowel == letter then
                        if not deleted then
                            deleted = true
                            message:delete()
                        end
                        hasvowel = true
                        break
                    end
                end
                if not hasvowel then
                    nonvowel = nonvowel..letterlist[v]
                end
            end
            if nonvowel ~= text then
                local DM = message.author:getPrivateChannel()
                local message = send(DM,"_ _\nHi.\nThe last message you sent was deleted. It contained vowels. However, here's a version of your message that you can send:\n\n`"..nonvowel.."`")
            end
        end
    end
    
    local voicestatus = "Nothing"
    local voiceconnection = SpeakChannel:join()
    local songs = {{["filename"] = "EmotionalPrism",["text"] = "Emotional Prism by BIGWAVE"},{["filename"] = "Lovesong",["text"] = "Lovesong by BIGWAVE"},{["filename"] = "Aquamarine",["text"] = "Aquamarine by BIGWAVE"},{["filename"] = "Weekend",["text"] = "Weekend by BIGWAVE"},{["filename"] = "Yume",["text"] = "Yume by BIGWAVE"}}
    VoiceStatusChannel:getLastMessage():delete()
    local status = VoiceStatusChannel:send{embed = {color = discordia.Color.fromRGB(100,100,100).value,description = "The voice channel is currently inactive."}}
    local speakers = {}
    local function manageVoice(member,channel)
        if not member.user.bot then
            local voiceusers = SpeakChannel.connectedMembers
            if (#voiceusers - 1) < #speakers then
                for i, speaker in pairs(speakers) do
                    if speaker == member then
                        table.remove(speakers,i)
                        break
                    end
                end
                if #speakers == 0 and voicestatus ~= "Talking" then
                    status:clearReactions()
                    status:update{embed = {color = discordia.Color.fromRGB(100,100,100).value,description = "The voice channel is currently inactive."}}
                    return
                end
            else
                table.insert(speakers,member)
                if #speakers > 1 then
                    member:mute()
                end
            end
            if #speakers == 1 and voicestatus ~= "Talking" then
                client:removeAllListeners("reactionAdd")
                member:unmute()
                status:update{embed = {color = discordia.Color.fromRGB(0,150,150).value,description = "**"..speakers[1].user.username.."**, you're the only one here so I can play some music until someone else joins.\n\nClick the checkmark if you want that, otherwise I'll stay quiet."}}
                local statusreaction = status:addReaction("✅")
                local reactionfunction = client:on("reactionAdd",function(reaction,id)
                    if reaction.message == status then
                        if id == speakers[1].user.id then --something in here throws me an uncached reaction warning after subsequent runs
                            reaction:delete(status.author.id)
                            reaction:delete(id)
                            voicestatus = "Music"
                            local function abort(member,channel)
                                if voicestatus == "Music" and channel == SpeakChannel and not member.user.bot then
                                    if member.voiceChannel ~= nil then
                                        member:mute()
                                    end
                                    voicestatus = "Nothing"
                                    voiceconnection:stopStream()
                                end
                            end
                            client:on("voiceChannelLeave",abort)
                            client:on("voiceChannelJoin",abort)

                            local songnum = 1
                            math.randomseed(os.time())
                            for i = #songs, 2, -1 do
                                local j = math.random(i)
                                songs[i], songs[j] = songs[j], songs[i]
                            end
                            while voicestatus == "Music" do
                                if songs[songnum] == nil then
                                    songnum = 1
                                end
                                local songinfo = songs[songnum]
                                status:update{embed = {color = discordia.Color.fromRGB(0,255,255).value,description = "You got it!\n\n**Currently Playing:** "..songinfo["text"].."\nYou're not obligated to stay, just leave and rejoin if you're sick of it."}}
                                voiceconnection:playFFmpeg("music/"..songinfo["filename"]..".mp3")
                                songnum = songnum + 1
                            end
                            return
                        elseif not client:getUser(id).bot then
                            reaction:delete(id)
                        end
                    end
                end)
            elseif #speakers > 1 and voicestatus ~= "Talking" then
                status:clearReactions()
                if voicestatus == "Music" then
                    status:update{embed = {color = discordia.Color.fromRGB(100,100,100).value,description = "I see there's "..#speakers.." people in the voice channel. I'll start my process once we hit a new minute.\n\n**"..speakers[1].name.."**, you were listening to music before "..speakers[2].name.." joined, so you may scream at them for interrupting it."}}
                else
                    status:update{embed = {color = discordia.Color.fromRGB(100,100,100).value,description = "I see there's "..#speakers.." people in the voice channel. I'll start my process once we hit a new minute."}}
                    if #speakers == 2 then
                        speakers[1]:mute()
                    end
                end
                voicestatus = "Waiting"
            end
        end
    end
    coroutine.wrap(function()
        while true do
            wait(60-(os.time()%60))
            while #speakers > 1 do
                voicestatus = "Talking"
                local currentlist = {table.unpack(speakers)}
                local string = "To make sure everyone gets their turn, here's the times you get to speak:\n\n"
                local timeallocated = 50/#currentlist
                for i, member in pairs(currentlist) do
                    string = string.."[00:"..round(((timeallocated*i)-timeallocated+10),1).." - 00:"..round(((timeallocated*i)+10),1).."] "..member.name.."\n"
                end
                status:update{embed = {color = discordia.Color.fromRGB(0,255,255).value,description = string}}
                wait(10-(os.time()%10))
                for i, member in pairs(currentlist) do
                    local waituntil = os.time() + timeallocated
                    if member.voiceChannel ~= nil then
                        member:unmute()
                    end
                    local string = "**"..member.name.."**, you have ~"..round(timeallocated).." seconds to speak.\n\n"
                    for v, member in pairs(currentlist) do
                        local memberstatus = "Left"
                        for i, online in pairs(speakers) do
                            if online == member then
                                memberstatus = "Online"
                                break
                            end
                        end
                        if memberstatus == "Left" and v == i then
                            string = "**"..member.name.."** ditched so you can sit ~"..round(timeallocated).." seconds in silence.\n\n"
                            string = string.."~~**[00:"..round(((timeallocated*v)-timeallocated+10),1).." - 00:"..round(((timeallocated*v)+10),1).."] "..member.name.."**~~\n"
                        elseif memberstatus == "Left" then
                            string = string.."~~[00:"..round(((timeallocated*v)-timeallocated+10),1).." - 00:"..round(((timeallocated*v)+10),1).."] "..member.name.."~~\n"
                        elseif v == i then
                            string = string.."**[00:"..round(((timeallocated*v)-timeallocated+10),1).." - 00:"..round(((timeallocated*v)+10),1).."] "..member.name.."**\n"
                        else
                            string = string.."[00:"..round(((timeallocated*v)-timeallocated+10),1).." - 00:"..round(((timeallocated*v)+10),1).."] "..member.name.."\n"
                        end
                    end
                    status:update{embed = {color = discordia.Color.fromRGB(0,255,255).value,description = string}}
                    wait(waituntil - os.time())
                    if member.voiceChannel ~= nil then
                        member:mute()
                    end
                end
                if #speakers == 1 then
                    voicestatus = "Waiting"
                    status:update{embed = {color = discordia.Color.fromRGB(0,150,150).value,description = "**"..speakers[1].user.username.."**, looks like you're the last one remaining. If you want to listen to music you can leave and rejoin, otherwise you can wait here."}}
                elseif #speakers == 0 then
                    voicestatus = "Nothing"
                    status:update{embed = {color = discordia.Color.fromRGB(100,100,100).value,description = "The voice channel is currently inactive."}}
                end
            end
        end
    end)()
    client:on("voiceChannelLeave",manageVoice)
    client:on("voiceChannelJoin",manageVoice)
    client:on("messageUpdate",checkMessage)
    client:on("messageCreate",checkMessage)
    
    --Waits for an hour, within the 15-45th minutes a random event can occur. At the last hour it waits 10 minutes less so the message can notify users
    local function randomEvent(minsatend)
        minsatend = minsatend or 0
        local eventwait = math.random(15,45)*60
        wait(eventwait)
        
        coroutine.wrap(function()
            local chance = math.random(1,100)

            if chance <= 2 then
                send(MessageChannel,"[2%] **Event**\n\nThe next person to send a message within **10 minutes** will receive a single-use message bypass.\n\nTo use the bypass, say `bypass` in chat before sending a message that you want to be unfiltered.")
                local claimed = false
                client:waitFor("messageCreate",600*1000,function(message)
                    if message.channel == MessageChannel and not message.author.bot then
                        claimed = true
                        inventories[message.author.id] = "bypass"
                        send(MessageChannel,"_ _\n[2%] **Event**\n\n"..message.author.username.." claimed the bypass.")
                        return true
                    end
                end)
                if not claimed then
                    send(MessageChannel,"[2%] **Event**\n\nNo one claimed the bypass.")
                end
            elseif chance <= 7 then
                send(MessageChannel,"[5%] **Event**\n\nThe next person to send a message within **10 minutes** can add a new whitelisted word.\n\nTo add the word, DM the bot `suggest (word)` and that word will immediately be whitelisted.")
                local claimed = false
                client:waitFor("messageCreate",600*1000,function(message)
                    if message.channel == MessageChannel and not message.author.bot then
                        claimed = true
                        inventories[message.author.id] = "suggest"
                        send(MessageChannel,"_ _\n[5%] **Event**\n\n"..message.author.username.." claimed the whitelisted word.")
                        return true
                    end
                end)
                if not claimed then
                    send(MessageChannel,"[5%] **Event**\n\nNo one claimed the whitelisted word.")
                end
            end
            if data["Inventory"] ~= inventories then
                data["Inventory"] = inventories
                Storage:saveTable(data)
            end
        end)()
        
        wait(3600-eventwait-(minsatend*60))
    end
    
    --Loads all of the savedata
    whitelistedwords = data["Words"]
    suggestedwords = data["SuggestedWords"]
    usersuggested = data["SuggestedUsers"]
    inventories = data["Inventory"]
    wordcounter = data["WordCount"]
    
    --Waits until the start of an hour, then begins the word acception loop
    local timeuntilhour = 3600-(os.time()%3600)
    wait(timeuntilhour)
    randomEvent()
    while true do
        send(MessageChannel,"One hour is left until new words are picked. Remember to `suggest` some!")
        randomEvent(10)
        send(MessageChannel,"Ten minutes are left until the new words are picked. Last chance to `suggest` some.")
        wait(600)
        addWords()
        randomEvent()
        randomEvent()
    end
end)


client:run("Bot "..token)
