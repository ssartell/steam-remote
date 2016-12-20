local dev = require("device");
local server = require("server");
local kb = require("keyboard");
local http = require("http");
local data = require("data");
local tmr = require("timer");
local utf8 = require("utf8");
local fs = require("fs");

-- Native Windows Stuff
local ffi = require("ffi");
ffi.cdef[[
bool LockWorkStation();
int ExitWindowsEx(int uFlags, int dwReason);
bool SetSuspendState(bool hibernate, bool forceCritical, bool disableWakeEvent);
]]
local PowrProf = ffi.load("PowrProf");

local recent_games = {};
local recent_games_items = {};
local all_games = {};
local all_games_items = {};

--@help Start steam
actions.start_steam = function()
    os.start("F:/Program Files/Steam/steam.exe");
end

--@help Put system in sleep state
actions.sleep = function ()
	PowrProf.SetSuspendState(false, true, false);
end

--@help Play Rocket League
actions.rocket_league = function ()
    os.open("steam://rungameid/252950");
end

actions.play_recent_game = function(index)
    local appid = recent_games_items[index + 1].appid;
    os.open("steam://rungameid/" .. appid);
end

actions.play_all_game = function(index)
    local appid = all_games_items[index + 1].appid;
    os.open("steam://rungameid/" .. appid);
end

local chat_text = "";
actions.update_text = function(text)
    chat_text = text;
end

local chat_char = "t";
actions.update_char = function(text)
    chat_char = text;
end

actions.send_text = function()
    local local_chat_text = chat_text;
    layout.chat.text = "";

    kb.text(chat_char);

    tmr.timeout(function() 
        kb.text(local_chat_text);
    end, 250);

    tmr.timeout(function() 
        kb.press("return");
    end, 500);
end

actions.send_text_esc = function()
    actions.send_text();
    tmr.timeout(function() 
        kb.press("esc");
    end, 550);
end

local filter = "";
actions.update_filter = function(text)
    filter = utf8.trim(text);
    if (string.len(filter) >= 2) then
        update_all_games_list();
    end
end

actions.clear_filter = function()
    filter = "";
    layout.filter.text = "";
    update_all_games_list();
end

local sort = "by_playtime"
actions.sort_by_playtime = function()
    sort = "by_playtime"
    update_all_games_list();
end

actions.sort_by_name = function()
    sort = "by_name";
    update_all_games_list();
end

function load_recently_played() 
    local url = "http://api.steampowered.com/IPlayerService/GetRecentlyPlayedGames/v0001/?key=" .. settings["steam-api-key"] .. "&steamid=" .. settings["steam-id"] .. "&format=json";
    http.get(url, function (err, resp)
        if (err) then return; end
        local result = data.fromjson(resp);
        recent_games = result.response.games;
        update_recent_games_list();
    end);
end

function load_all_games() 
    local url = "http://api.steampowered.com/IPlayerService/GetOwnedGames/v0001/?key=" .. settings["steam-api-key"] .. "&steamid=" .. settings["steam-id"] .. "&format=json&include_appinfo=1";
    http.get(url, function (err, resp)
        if (err) then return; end
        local result = data.fromjson(resp);
        all_games = result.response.games;
        update_all_games_list();
    end);
end

function update_recent_games_list()
    local n = 1;
    recent_games_list = {};

    for i,game in ipairs(recent_games) do
        local item = { 
            type = "item", 
            img_icon_url = game.img_icon_url, 
            text = game.name, 
            appid = game.appid, 
            name = game.name, 
            playtime_forever = game.playtime_forever,
        };

        if (item.img_icon_url ~= "") then
            item.image = "images\\" .. game.img_icon_url .. ".jpg";
        end
        recent_games_list[n] = item;
        n = n + 1;
    end

    download_images(recent_games_list, 1, function() 
        server.update({ id = "recent_games", children = recent_games_list });
    end);
end

function update_all_games_list()
    local n = 1;
    all_games_items = {};

    for i,game in ipairs(all_games) do
        if (filter == "" or string.find(string.lower(game.name), string.lower(filter)) ~= nil) then
            local item = { 
                type = "item", 
                img_icon_url = game.img_icon_url, 
                text = game.name, 
                appid = game.appid, 
                name = game.name, 
                playtime_forever = game.playtime_forever 
            };

            if (item.img_icon_url ~= "") then
                item.image = "images\\" .. game.img_icon_url .. ".jpg";
            end
            all_games_items[n] = item;
            n = n + 1;
        end
    end

    if (sort == "by_name") then
        table.sort(all_games_items, by_name);
    else
        table.sort(all_games_items, by_playtime);
    end

    download_images(all_games_items, 1, function() 
        server.update({ id = "all_games", children = all_games_items });
    end);
end

function by_playtime(a, b)
    return a.playtime_forever > b.playtime_forever;
end

function by_name(a, b)
    return a.name < b.name;
end

function download_images(games, n, callback)
    local game = games[n];

    if (game == nil) then
        callback();
        return;
    end

    if (game.img_icon_url == "" or game.img_icon_url == nil) then
        download_images(games, n + 1, callback);
        return;
    end

    local path = fs.remotedir();
    local image_dir = fs.combine(path, "images");
    local image_filename = fs.combine(image_dir, game.img_icon_url .. ".jpg");

    local url = "http://media.steampowered.com/steamcommunity/public/images/apps/" .. game.appid .. "/" .. game.img_icon_url .. ".jpg";

    if (not fs.exists(image_dir)) then
        fs.createdir(image_dir);
    end

    if (not fs.exists(image_filename)) then
        http.get(url, function (err, resp)
            fs.createfile(image_filename);
            fs.write(image_filename, resp);
            download_images(games, n + 1, callback);
        end);
    else
        download_images(games, n + 1, callback);
    end
end

load_recently_played();
load_all_games();