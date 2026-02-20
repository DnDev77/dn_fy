local xSound = exports.xsound
local boomboxInstances = {}
local YOUTUBE_API_KEY = "AIzaSyBKG_cbDisBLWG7vgkd6aJZoIQlskHlvA4"
local MAX_RESULTS = 25

function HasMusicPermission(source)
    if not Config.Permissions.RequirePermission then
        return true
    end

    local resource = GetCurrentResourceName()

    local hasRequiredItem = true
    if Config.RequireItem then
        hasRequiredItem = exports[resource]:hasItem(source, Config.ItemRequired, 1)
    end

    for _, group in pairs(Config.Permissions.AllowedGroups) do
        local hasGroupPermission = exports[resource]:hasPermission(source, group)

        Debug(
            'server.permissionCheck',
            tostring(source),
            tostring(group),
            tostring(hasGroupPermission),
            tostring(hasRequiredItem)
        )

        if hasGroupPermission or hasRequiredItem then
            Debug('server.permissionGranted', tostring(source))
            return true
        end
    end

    Debug('server.permissionDenied', tostring(source))
    return false
end


RegisterCommand(Config.CommandVehicle, function(source, args, rawCommand)
    Debug('server.commandTriggered', tostring(Config.CommandVehicle), tostring(source))
    if HasMusicPermission(source) then
        TriggerClientEvent("Music:ShowNui", source)
    else
        TriggerClientEvent("Notify", source, "negado", Locale("notifications.noPermission"), 5000)
    end
end)

function urlencode(str)
    if str then
        str = string.gsub(str, "\n", "\r\n")
        str = string.gsub(str, "([^%w ])",
            function(c) return string.format("%%%02X", string.byte(c)) end)
        str = string.gsub(str, " ", "+")
    end
    return str
end

function ExtractYouTubeId(input)
    if not input or type(input) ~= "string" then return nil end
    if input:match("^[%w%-_]+$") and #input >= 10 then return input end
    local id = input:match("[?&]v=([%w%-_]+)")
    if id then return id end
    id = input:match("youtu%.be/([%w%-_]+)")
    if id then return id end
    id = input:match("embed/([%w%-_]+)")
    if id then return id end
    return nil
end

function IsUrl(value)
    if not value or type(value) ~= "string" then return false end
    return value:match("^https?://") ~= nil
end

function isYouTube(input)
    if not input then return false end
    input = tostring(input)
    if string.match(input, "^[%w_-]+$") and #input == 11 then return true end
    if string.find(input, "youtube.com", 1, true) or string.find(input, "youtu.be", 1, true) then return true end
    return false
end

function GetYoutubeThumbnail(youtubeUrl)
    if not youtubeUrl or youtubeUrl == "" then return nil end
    local videoId = youtubeUrl:match("v=([^&]+)")
    if not videoId then videoId = youtubeUrl:match("youtu%.be/([^?&]+)") end
    if not videoId then videoId = youtubeUrl:match("embed/([^?&]+)") end
    if not videoId then return nil end
    return "https://img.youtube.com/vi/" .. videoId .. "/hqdefault.jpg"
end

GetMusicUrlById = function(playerId, musicId)
    if not playerId or not musicId then
        Debug('server.musicUrlFromDbFailed', tostring(playerId), tostring(musicId))
        return nil
    end
    Debug('server.musicUrlFromDb', tostring(playerId), tostring(musicId))
    local ok, result = pcall(function()
        return exports.oxmysql:singleSync(
            'SELECT like_music_list FROM music_like_list WHERE player_id = ?',
            { playerId }
        )
    end)
    if not ok then
        Debug('server.dbQueryError', 'GetMusicUrlById', tostring(result))
        return nil
    end
    if not result or type(result) ~= 'table' or not result.like_music_list then
        Debug('server.musicUrlFromDbFailed', tostring(playerId), tostring(musicId))
        return nil
    end
    local decOk, list = pcall(json.decode, result.like_music_list)
    if not decOk or type(list) ~= 'table' then
        Debug('server.dbDecodeError', 'GetMusicUrlById', tostring(list))
        return nil
    end
    for _, music in ipairs(list) do
        if type(music) == 'table' and music.id and music.url_id then
            if tostring(music.id) == tostring(musicId) then
                Debug('server.musicUrlFromDbResult', tostring(music.url_id))
                return music.url_id
            end
        end
    end
    Debug('server.musicUrlFromDbFailed', tostring(playerId), tostring(musicId))
    return nil
end

function SearchYouTube(query, cb)
    Debug('server.youtubeSearch', tostring(query))
    local url = "https://www.googleapis.com/youtube/v3/search?part=snippet&type=video&videoCategoryId=10"
        .. "&maxResults=" .. tostring(math.ceil(MAX_RESULTS / 2))
        .. "&key=" .. YOUTUBE_API_KEY
        .. "&q=" .. urlencode(query)

    PerformHttpRequest(url, function(statusCode, responseData, headers)
        Debug('server.youtubeSearchStatus', tostring(statusCode), tostring(responseData and #responseData or 0))
        if statusCode ~= 200 or not responseData then
            Debug('server.youtubeSearchFailed', tostring(statusCode), tostring(responseData))
            cb({})
            return
        end
        local ok, data = pcall(json.decode, responseData)
        if not ok or not data or not data.items then
            Debug('server.youtubeSearchDecodeError', tostring(data))
            cb({})
            return
        end
        local results = {}
        for _, item in ipairs(data.items) do
            local videoId = item.id and item.id.videoId
            if videoId then
                local thumb = (item.snippet.thumbnails.high and item.snippet.thumbnails.high.url)
                    or (item.snippet.thumbnails.default and item.snippet.thumbnails.default.url)
                    or "https://picsum.photos/200"
                table.insert(results, {
                    _id = videoId,
                    image_url = thumb,
                    name = item.snippet.title,
                    author = item.snippet.channelTitle,
                    youtube_id = videoId,
                    external_url = "https://www.youtube.com/watch?v=" .. videoId,
                    published_at = item.snippet.publishedAt
                })
            end
        end
        Debug('server.youtubeSearchStatus', tostring(statusCode), tostring(#results))
        cb(results)
    end, "GET")
end

function GetTrackDetails(id, cb)
    Debug('server.trackDetailsRequest', tostring(id))

    local trackId = id


    local url = "https://www.googleapis.com/youtube/v3/videos?part=snippet"
        .. "&id=" .. trackId
        .. "&key=" .. YOUTUBE_API_KEY

    PerformHttpRequest(url, function(statusCode, responseData, headers)
        Debug('server.trackDetailsStatus', tostring(statusCode))
        if statusCode ~= 200 or not responseData then
            Debug('server.trackDetailsFailed', tostring(id), tostring(statusCode))
            cb(nil)
            return
        end
        local ok, data = pcall(json.decode, responseData)
        if not ok or not data or not data.items or #data.items == 0 then
            Debug('server.trackDetailsDecodeError', tostring(id), tostring(data))
            cb(nil)
            return
        end
        local video = data.items[1]
        local thumb = (video.snippet.thumbnails.high and video.snippet.thumbnails.high.url)
            or (video.snippet.thumbnails.default and video.snippet.thumbnails.default.url)
            or "https://picsum.photos/200"
        cb({
            _id = id,
            image_url = thumb,
            name = video.snippet.title,
            author = video.snippet.channelTitle,
            youtube_id = trackId,
            external_url = "https://www.youtube.com/watch?v=" .. trackId,
            published_at = video.snippet.publishedAt
        })
    end, "GET")
end

RegisterNetEvent("central_music/requestMusicUrl")
AddEventHandler("central_music/requestMusicUrl", function(musicId, name, imageUrl, author)
    local source = source
    Debug('server.musicUrlReceived', tostring(source), tostring(musicId))

    local user_id = exports[GetCurrentResourceName()]:getUserId(source)
    Debug('server.getUserId', tostring(source), tostring(user_id))

    if not user_id then
        Debug('server.getUserIdFailed', tostring(source))
    end

    if not isYouTube(musicId) then
        local url = GetMusicUrlById(user_id, musicId)
        local youtubeId = ExtractYouTubeId(url)
        if not youtubeId then
            Debug('server.youtubeIdInvalid', tostring(musicId))
            TriggerClientEvent("Notify", source, "error", Locale("notifications.invalidYoutubeId"), 5000)
            return
        end
        musicId = youtubeId
    end

    local lookupId = isYouTube(musicId) and ((ExtractYouTubeId(musicId) or musicId)) or musicId

    GetTrackDetails(lookupId, function(track)
        if not track then
            Debug('server.trackDetailsNotFound', tostring(lookupId))
            TriggerClientEvent("Notify", source, "error", Locale("notifications.musicNotFound"), 5000)
            return
        end
        Debug('server.musicUrlResolved', tostring(source), tostring(track.external_url))
        TriggerClientEvent("central_music/musicUrlReceived", source, {
            url = track.external_url,
            name = track.name or name,
            imageUrl = imageUrl,
            author = author,
            musicId = musicId
        })
    end)
end)

RegisterNetEvent("central_music/searchMusic")
AddEventHandler("central_music/searchMusic", function(musicQuery)
    local source = source
    Debug('server.searchMusicEvent', tostring(source), tostring(musicQuery))
    SearchYouTube(musicQuery, function(results)
        local limited = {}
        for i = 1, math.min(MAX_RESULTS, #results) do
            table.insert(limited, {
                _id = results[i]._id,
                image_url = results[i].image_url,
                name = results[i].name,
                author = results[i].author
            })
        end
        Debug('server.searchMusicResult', tostring(#limited), tostring(source))
        TriggerClientEvent("central_music/searchMusicResult", source, limited)
    end)
end)

RegisterNetEvent("central_music/deletePlaylist")
AddEventHandler("central_music/deletePlaylist", function(id)
    local user_id = exports[GetCurrentResourceName()]:getUserId(source)
    Debug('server.deletePlaylist', tostring(user_id), tostring(id))
    local ok, err = pcall(function()
        exports["oxmysql"]:query_async("DELETE FROM music_playlist WHERE id = @id AND player_id = @playerId", {
            ["@id"] = id,
            ["@playerId"] = user_id
        })
    end)
    if not ok then
        Debug('server.dbQueryError', 'deletePlaylist', tostring(err))
    end
end)

RegisterNetEvent("central_music/editPlaylist")
AddEventHandler("central_music/editPlaylist", function(id, name, url_img)
    local user_id = exports[GetCurrentResourceName()]:getUserId(source)
    Debug('server.editPlaylist', tostring(user_id), tostring(id), tostring(name))
    local ok, err = pcall(function()
        exports["oxmysql"]:query_async("UPDATE music_playlist SET name = @name, url_img = @url_img WHERE id = @id AND player_id = @playerId", {
            ["@name"] = name,
            ["@url_img"] = url_img,
            ["@id"] = id,
            ["@playerId"] = user_id
        })
    end)
    if not ok then
        Debug('server.dbQueryError', 'editPlaylist', tostring(err))
    end
end)

RegisterNetEvent("central_music/updatePlaylistMusicList")
AddEventHandler("central_music/updatePlaylistMusicList", function(playlist_id, updatedMusicList)
    local user_id = exports[GetCurrentResourceName()]:getUserId(source)
    Debug('server.updatePlaylist', tostring(user_id), tostring(playlist_id))
    local ok, querySelect = pcall(function()
        return exports["oxmysql"]:query_async("SELECT player_id FROM music_playlist WHERE id = @playlistId", {
            ["@playlistId"] = playlist_id
        })
    end)
    if not ok then
        Debug('server.dbQueryError', 'updatePlaylistMusicList/select', tostring(querySelect))
        return
    end
    if querySelect and #querySelect > 0 then
        Debug('server.dbQueryResult', 'updatePlaylistMusicList', tostring(#querySelect))
        local playlistOwnerId = querySelect[1].player_id
        if user_id == playlistOwnerId then
            local ok2, err2 = pcall(function()
                exports["oxmysql"]:query_async("UPDATE music_playlist SET music_playlist = @updatedMusicData WHERE id = @playlistId", {
                    ["@updatedMusicData"] = updatedMusicList,
                    ["@playlistId"] = playlist_id
                })
            end)
            if not ok2 then
                Debug('server.dbQueryError', 'updatePlaylistMusicList/update', tostring(err2))
            end
        else
            Debug('server.updatePlaylistOwnerMismatch', tostring(user_id), tostring(playlist_id))
        end
    end
end)

RegisterNetEvent("central_music/removeMusicFromPlaylist")
AddEventHandler("central_music/removeMusicFromPlaylist", function(music_id, playlist_id)
    Debug('server.removeMusicFromPlaylist', tostring(music_id), tostring(playlist_id))
    local ok, querySelect = pcall(function()
        return exports["oxmysql"]:query_async("SELECT music_playlist FROM music_playlist WHERE id = @playlistId", {
            ["@playlistId"] = playlist_id
        })
    end)
    if not ok then
        Debug('server.dbQueryError', 'removeMusicFromPlaylist/select', tostring(querySelect))
        return
    end
    if querySelect and #querySelect > 0 then
        local playlistData = querySelect[1]
        local decOk, music_playlist = pcall(json.decode, playlistData.music_playlist)
        if not decOk or type(music_playlist) ~= 'table' then
            Debug('server.dbDecodeError', 'removeMusicFromPlaylist', tostring(music_playlist))
            return
        end
        for i, music in ipairs(music_playlist) do
            if music.id == music_id then
                table.remove(music_playlist, i)
                break
            end
        end
        local updatedMusicData = json.encode(music_playlist)
        local ok2, err2 = pcall(function()
            exports["oxmysql"]:query_async("UPDATE music_playlist SET music_playlist = @updatedMusicData WHERE id = @playlistId", {
                ["@updatedMusicData"] = updatedMusicData,
                ["@playlistId"] = playlist_id
            })
        end)
        if not ok2 then
            Debug('server.dbQueryError', 'removeMusicFromPlaylist/update', tostring(err2))
        end
    end
end)

RegisterNetEvent("central_music/addToPlaylist")
AddEventHandler("central_music/addToPlaylist", function(playlistId, url_id, name, id, image_url)
    local user_id = exports[GetCurrentResourceName()]:getUserId(source)
    Debug('server.addToPlaylist', tostring(user_id), tostring(playlistId), tostring(url_id))
    local ok, querySelect = pcall(function()
        return exports["oxmysql"]:query_async("SELECT music_playlist FROM music_playlist WHERE id = @playlistId AND player_id = @playerId", {
            ["@playlistId"] = playlistId,
            ["@playerId"] = user_id
        })
    end)
    if not ok then
        Debug('server.dbQueryError', 'addToPlaylist/select', tostring(querySelect))
        return
    end
    if querySelect and #querySelect > 0 then
        local decOk, currentMusicData = pcall(json.decode, querySelect[1].music_playlist)
        if not decOk or type(currentMusicData) ~= 'table' then
            Debug('server.dbDecodeError', 'addToPlaylist', tostring(currentMusicData))
            return
        end
        local newMusicItem = {
            id = id,
            url_id = url_id,
            name = name,
            image_url = image_url or "https://via.placeholder.com/40"
        }
        table.insert(currentMusicData, 1, newMusicItem)
        local ok2, err2 = pcall(function()
            exports["oxmysql"]:query_async("UPDATE music_playlist SET music_playlist = @newMusicData WHERE id = @playlistId AND player_id = @playerId", {
                ["@newMusicData"] = json.encode(currentMusicData),
                ["@playlistId"] = playlistId,
                ["@playerId"] = user_id
            })
        end)
        if not ok2 then
            Debug('server.dbQueryError', 'addToPlaylist/update', tostring(err2))
        end
    end
end)

RegisterNetEvent("central_music/reqPlaylists")
AddEventHandler("central_music/reqPlaylists", function()
    local source = source
    local user_id = exports[GetCurrentResourceName()]:getUserId(source)
    local ok, querySelect = pcall(function()
        return exports["oxmysql"]:query_async("SELECT * FROM music_playlist WHERE player_id = @playerId", {
            ["@playerId"] = user_id
        })
    end)
    if not ok then
        Debug('server.dbQueryError', 'reqPlaylists', tostring(querySelect))
        return
    end
    local playlists = {}
    for _, playlistData in ipairs(querySelect) do
        local decOk, decoded = pcall(json.decode, playlistData.music_playlist)
        if not decOk then
            Debug('server.dbDecodeError', 'reqPlaylists/musicList', tostring(decoded))
        else
            table.insert(playlists, {
                id = playlistData.id,
                name = playlistData.name,
                url_img = playlistData.url_img,
                music_playlist = decoded
            })
        end
    end
    Debug('server.reqPlaylists', tostring(user_id), tostring(#playlists))
    TriggerClientEvent("central_music/receiveAllPlaylists", source, json.encode(playlists))
end)

RegisterNetEvent("central_music/createNewPlaylist")
AddEventHandler("central_music/createNewPlaylist", function(name, url_img)
    local source = source
    local user_id = exports[GetCurrentResourceName()]:getUserId(source)
    local playlistName = name or "Playlist"
    local playlistImage = url_img or "https://images.unsplash.com/photo-1494232410401-ad00d5433cfa?ixlib=rb-4.0.3&auto=format&fit=crop&w=1170&q=80"
    Debug('server.createPlaylist', tostring(user_id), tostring(playlistName))
    local ok, err = pcall(function()
        exports["oxmysql"]:query_async("INSERT INTO music_playlist (player_id, name, url_img, music_playlist) VALUES (@playerId, @name, @urlImg, @musicData)", {
            ["@playerId"] = user_id,
            ["@name"] = playlistName,
            ["@urlImg"] = playlistImage,
            ["@musicData"] = json.encode({})
        })
    end)
    if not ok then
        Debug('server.dbQueryError', 'createNewPlaylist', tostring(err))
        return
    end
    TriggerEvent("central_music/reqPlaylists")
end)

RegisterNetEvent("central_music/reqHistory")
AddEventHandler("central_music/reqHistory", function()
    local source = source
    local user_id = exports[GetCurrentResourceName()]:getUserId(source)
    Debug('server.reqHistory', tostring(user_id))
    local ok, queryForHistory = pcall(function()
        return exports["oxmysql"]:query_async('SELECT music_history_list FROM music_history WHERE player_id = ?', {user_id})
    end)
    if not ok then
        Debug('server.dbQueryError', 'reqHistory', tostring(queryForHistory))
        return
    end
    if queryForHistory and #queryForHistory > 0 then
        local decOk, currentHistory = pcall(json.decode, queryForHistory[1].music_history_list)
        if not decOk or type(currentHistory) ~= 'table' then
            Debug('server.dbDecodeError', 'reqHistory', tostring(currentHistory))
            return
        end
        TriggerClientEvent("central_music/showHistory", source, json.encode(currentHistory))
    end
end)

RegisterNetEvent("central_music/addToHistory")
AddEventHandler("central_music/addToHistory", function(url_id, name, id, image_url, author)
    local user_id = exports[GetCurrentResourceName()]:getUserId(source)
    Debug('server.addToHistory', tostring(user_id), tostring(url_id))
    local ok, queryForSave = pcall(function()
        return exports["oxmysql"]:query_async('SELECT music_history_list FROM music_history WHERE player_id = ?', {user_id})
    end)
    if not ok then
        Debug('server.dbQueryError', 'addToHistory/select', tostring(queryForSave))
        return
    end
    if queryForSave and #queryForSave > 0 then
        local decOk, currentHistory = pcall(json.decode, queryForSave[1].music_history_list)
        if not decOk or type(currentHistory) ~= 'table' then
            Debug('server.dbDecodeError', 'addToHistory', tostring(currentHistory))
            return
        end
        for i, historyItem in ipairs(currentHistory) do
            if historyItem.url_id == url_id then
                table.remove(currentHistory, i)
                break
            end
        end
        local newHistoryItem = {
            id = id,
            url_id = url_id,
            name = name,
            image_url = image_url or "https://via.placeholder.com/40",
            author = author
        }
        table.insert(currentHistory, 1, newHistoryItem)
        if #currentHistory > 20 then
            table.remove(currentHistory, 21)
        end
        local ok2, err2 = pcall(function()
            exports["oxmysql"]:query_async('UPDATE music_history SET music_history_list = ? WHERE player_id = ?', {json.encode(currentHistory), user_id})
        end)
        if not ok2 then
            Debug('server.dbQueryError', 'addToHistory/update', tostring(err2))
        end
    else
        local newHistoryItem = {
            id = id,
            url_id = url_id,
            name = name,
            image_url = image_url or "https://via.placeholder.com/40",
            author = author
        }
        local ok2, err2 = pcall(function()
            exports["oxmysql"]:query_async('INSERT INTO music_history (player_id, music_history_list) VALUES (?, ?)', {user_id, json.encode({newHistoryItem})})
        end)
        if not ok2 then
            Debug('server.dbQueryError', 'addToHistory/insert', tostring(err2))
        end
    end
end)

RegisterNetEvent("central_music/showLike")
AddEventHandler("central_music/showLike", function(url_id)
    local source = source
    local user_id = exports[GetCurrentResourceName()]:getUserId(source)
    local ok, queryForCheck = pcall(function()
        return exports["oxmysql"]:query_async('SELECT like_music_list FROM music_like_list WHERE player_id = ?', {user_id})
    end)
    if not ok then
        Debug('server.dbQueryError', 'showLike', tostring(queryForCheck))
        return
    end
    local found = false
    if queryForCheck and #queryForCheck > 0 then
        local decOk, currentLikes = pcall(json.decode, queryForCheck[1].like_music_list)
        if not decOk or type(currentLikes) ~= 'table' then
            Debug('server.dbDecodeError', 'showLike', tostring(currentLikes))
            return
        end
        for _, like in ipairs(currentLikes) do
            if like.url_id == url_id then
                found = true
                break
            end
        end
    end
    Debug('server.showLike', tostring(user_id), tostring(url_id), tostring(found))
    if found then
        TriggerClientEvent("central_music/showLike", source, url_id)
    end
end)

RegisterNetEvent("central_music/liked")
AddEventHandler("central_music/liked", function(url_id, name, id, image_url)
    local source = source
    local user_id = exports[GetCurrentResourceName()]:getUserId(source)
    Debug('server.liked', tostring(user_id), tostring(url_id))
    local ok, queryForSave = pcall(function()
        return exports["oxmysql"]:query_async('SELECT like_music_list FROM music_like_list WHERE player_id = ?', {user_id})
    end)
    if not ok then
        Debug('server.dbQueryError', 'liked/select', tostring(queryForSave))
        return
    end
    local newLike = {
        id = id,
        url_id = url_id,
        name = name,
        image_url = image_url or "https://via.placeholder.com/40"
    }
    if queryForSave and #queryForSave > 0 then
        local decOk, currentLikes = pcall(json.decode, queryForSave[1].like_music_list)
        if not decOk or type(currentLikes) ~= 'table' then
            Debug('server.dbDecodeError', 'liked', tostring(currentLikes))
            return
        end
        table.insert(currentLikes, 1, newLike)
        local ok2, err2 = pcall(function()
            exports["oxmysql"]:query_async('UPDATE music_like_list SET like_music_list = ? WHERE player_id = ?', {json.encode(currentLikes), user_id})
        end)
        if not ok2 then
            Debug('server.dbQueryError', 'liked/update', tostring(err2))
        end
    else
        local ok2, err2 = pcall(function()
            exports["oxmysql"]:query_async('INSERT INTO music_like_list (player_id, like_music_list) VALUES (?, ?)', {user_id, json.encode({newLike})})
        end)
        if not ok2 then
            Debug('server.dbQueryError', 'liked/insert', tostring(err2))
        end
    end
    TriggerClientEvent("central_music/showLike", source, url_id)
end)

RegisterNetEvent("central_music/remLike")
AddEventHandler("central_music/remLike", function(url_id)
    local source = source
    local user_id = exports[GetCurrentResourceName()]:getUserId(source)
    Debug('server.remLike', tostring(user_id), tostring(url_id))
    local ok, queryForSave = pcall(function()
        return exports["oxmysql"]:query_async('SELECT like_music_list FROM music_like_list WHERE player_id = ?', {user_id})
    end)
    if not ok then
        Debug('server.dbQueryError', 'remLike/select', tostring(queryForSave))
        return
    end
    if queryForSave and #queryForSave > 0 then
        local decOk, currentLikes = pcall(json.decode, queryForSave[1].like_music_list)
        if not decOk or type(currentLikes) ~= 'table' then
            Debug('server.dbDecodeError', 'remLike', tostring(currentLikes))
            return
        end
        for i, like in ipairs(currentLikes) do
            if like.url_id == url_id then
                table.remove(currentLikes, i)
                break
            end
        end
        local ok2, err2 = pcall(function()
            exports["oxmysql"]:query_async('UPDATE music_like_list SET like_music_list = ? WHERE player_id = ?', {json.encode(currentLikes), user_id})
        end)
        if not ok2 then
            Debug('server.dbQueryError', 'remLike/update', tostring(err2))
        end
        TriggerClientEvent("central_music/showRemLike", source, url_id)
    end
end)

RegisterNetEvent("central_music/footerLike")
AddEventHandler("central_music/footerLike", function(url_id)
    local source = source
    local user_id = exports[GetCurrentResourceName()]:getUserId(source)
    local ok, queryForSave = pcall(function()
        return exports["oxmysql"]:query_async('SELECT like_music_list FROM music_like_list WHERE player_id = ?', {user_id})
    end)
    if not ok then
        Debug('server.dbQueryError', 'footerLike', tostring(queryForSave))
        return
    end
    local found = false
    if queryForSave and #queryForSave > 0 then
        local decOk, currentLikes = pcall(json.decode, queryForSave[1].like_music_list)
        if not decOk or type(currentLikes) ~= 'table' then
            Debug('server.dbDecodeError', 'footerLike', tostring(currentLikes))
        else
            for _, like in ipairs(currentLikes) do
                if like.url_id == url_id then
                    found = true
                    break
                end
            end
        end
    end
    Debug('server.footerLike', tostring(user_id), tostring(url_id), tostring(found))
    TriggerClientEvent("central_music/showFooterLike", source, found)
end)

RegisterNetEvent("central_music/reqLikeList")
AddEventHandler("central_music/reqLikeList", function()
    local source = source
    local user_id = exports[GetCurrentResourceName()]:getUserId(source)
    local ok, queryForSave = pcall(function()
        return exports["oxmysql"]:query_async(
            'SELECT like_music_list FROM music_like_list WHERE player_id = ?',
            { user_id }
        )
    end)
    if not ok then
        Debug('server.dbQueryError', 'reqLikeList', tostring(queryForSave))
        return
    end
    if queryForSave and #queryForSave > 0 then
        local decOk, currentLikes = pcall(json.decode, queryForSave[1].like_music_list)
        if not decOk or type(currentLikes) ~= 'table' then
            Debug('server.dbDecodeError', 'reqLikeList', tostring(currentLikes))
            return
        end
        for _, music in ipairs(currentLikes) do
            if music.url_id then
                music.image_url = GetYoutubeThumbnail(music.url_id)
            end
        end
        Debug('server.reqLikeList', tostring(user_id), tostring(#currentLikes))
        TriggerClientEvent("central_music/showLikeList", source, json.encode(currentLikes))
    end
end)

RegisterNetEvent("central_music/reqBannerInfo")
AddEventHandler("central_music/reqBannerInfo", function()
    local source = source
    TriggerClientEvent("central_music/showBannerInfo", source, banner)
end)

RegisterNetEvent("central_music/ChangeVolume")
AddEventHandler("central_music/ChangeVolume", function(vol, nome)
    local somAfter = false
    local rangeAfter = false
    for i = 1, #Config.Zones do
        local v = Config.Zones[i]
        if nome == v.name then
            local volume = vol
            if volume <= 1.01 and volume >= 0 then
                if volume < 0.005 then volume = 0.0 end
                if v.popo then
                    v.range = (volume * Config.DistanceToVolume)
                else
                    if volume >= 0.05 then
                        v.range = (volume * v.range) / v.volume
                    end
                end
                v.volume = volume
                somAfter = v.volume
                rangeAfter = v.range
            end
        end
    end
    if somAfter and rangeAfter then
        Debug('server.changeVolume', tostring(nome), tostring(somAfter), tostring(rangeAfter))
        TriggerClientEventForAllPlayers("central_music/ChangeVolume", somAfter, rangeAfter, nome)
    end
end)

RegisterNetEvent("central_music/ChangeLoop")
AddEventHandler("central_music/ChangeLoop", function(nome, tip)
    local loopState
    for i = 1, #Config.Zones do
        local v = Config.Zones[i]
        if nome == v.name then
            v.loop = tip
            loopState = v.loop
        end
    end
    if loopState ~= nil then
        Debug('server.changeLoop', tostring(nome), tostring(loopState))
        TriggerClientEventForAllPlayers("central_music/ChangeLoop", loopState, nome)
    end
end)

RegisterNetEvent("central_music/ChangeState")
AddEventHandler("central_music/ChangeState", function(type, nome)
    Debug('server.changeState', tostring(nome), tostring(type))
    for i = 1, #Config.Zones do
        local v = Config.Zones[i]
        if nome == v.name then
            v.isplaying = type
        end
    end
    TriggerClientEventForAllPlayers("central_music/ChangeState", type, nome)
end)

RegisterNetEvent("central_music/ChangePosition")
AddEventHandler("central_music/ChangePosition", function(time, nome)
    Debug('server.changePosition', tostring(nome), tostring(time))
    for i = 1, #Config.Zones do
        local v = Config.Zones[i]
        if nome == v.name then
            v.deftime = time
            if v.deftime < 0 then v.deftime = 0 end
        end
    end
    TriggerClientEventForAllPlayers("central_music/NewTimeMusic", time, nome)
end)

RegisterNetEvent("central_music/ModifyURL")
AddEventHandler("central_music/ModifyURL", function(data)
    local _data = data
    local zone = false
    for i = 1, #Config.Zones do
        local v = Config.Zones[i]
        if _data.name == v.name then
            v.deflink = _data.link
            if _data.popo then v.popo = _data.popo end
            v.deftime = 0
            v.isplaying = true
            v.loop = _data.loop
            zone = v
        end
    end
    if zone then
        Debug('server.zoneModified', tostring(_data.name), tostring(_data.link))
        TriggerClientEventForAllPlayers("central_music/ModifyURL", zone)
    else
        Debug('server.zoneNotFound', tostring(_data.name))
    end
end)

RegisterNetEvent('central_music/AddVehicle')
AddEventHandler("central_music/AddVehicle", function(vehData)
    local data = {
        name = vehData.plate,
        coords = vehData.coords,
        range = vehData.volume * Config.DistanceToVolume,
        volume = vehData.volume,
        deflink = vehData.link,
        isplaying = true,
        loop = vehData.loop,
        deftime = 0,
        popo = vehData.popo
    }
    Debug('server.vehicleAdded', tostring(data.name), tostring(data.deflink))
    table.insert(Config.Zones, data)
    TriggerClientEventForAllPlayers('central_music/AddVehicle', Config.Zones[#Config.Zones])
end)

function CreateBoomboxInstance(uniqueId, coords, volume, range, loop)
    if not boomboxInstances[uniqueId] then
        boomboxInstances[uniqueId] = {
            id = uniqueId,
            coords = coords,
            volume = volume or 0.5,
            range = range or Config.Boombox.Range,
            loop = loop or false,
            isPlaying = false,
            currentUrl = nil,
            currentTime = 0
        }
        Debug('server.boomboxCreated', tostring(uniqueId), tostring(coords))
    else
        Debug('server.boomboxAlreadyExists', tostring(uniqueId))
    end
    return boomboxInstances[uniqueId]
end

function GetBoomboxInstance(uniqueId)
    local inst = boomboxInstances[uniqueId]
    if not inst then
        Debug('server.boomboxNotFound', tostring(uniqueId))
    end
    return inst
end

function RemoveBoomboxInstance(uniqueId)
    if boomboxInstances[uniqueId] then
        Debug('server.boomboxRemoved', tostring(uniqueId))
        TriggerClientEventForAllPlayers("central_music/StopBoombox", uniqueId)
        boomboxInstances[uniqueId] = nil
    else
        Debug('server.boomboxNotFound', tostring(uniqueId))
    end
end

RegisterNetEvent("central_music/SetBoomboxUrl")
AddEventHandler("central_music/SetBoomboxUrl", function(uniqueId, url, coords, volume, loop, range)
    Debug('server.boomboxSetUrl', tostring(uniqueId), tostring(url), tostring(volume), tostring(range), tostring(loop))
    local instance = CreateBoomboxInstance(uniqueId, coords, volume, range, loop)
    instance.currentUrl = url
    instance.coords = coords
    instance.volume = volume
    instance.loop = loop
    instance.range = range
    instance.isPlaying = true
    instance.currentTime = 0
    TriggerClientEventForAllPlayers("central_music/PlayBoombox", uniqueId, url, volume, range, loop, coords)
end)

RegisterNetEvent("central_music/PlayBoomboxMusic")
AddEventHandler("central_music/PlayBoomboxMusic", function(uniqueId)
    local instance = GetBoomboxInstance(uniqueId)
    Debug('server.boomboxPlay', tostring(uniqueId), tostring(instance ~= nil and instance.currentUrl ~= nil))
    if instance and instance.currentUrl then
        instance.isPlaying = true
        TriggerClientEventForAllPlayers("central_music/ResumeBoombox", uniqueId)
    end
end)

RegisterNetEvent("central_music/PauseBoomboxMusic")
AddEventHandler("central_music/PauseBoomboxMusic", function(uniqueId)
    Debug('server.boomboxPause', tostring(uniqueId))
    local instance = GetBoomboxInstance(uniqueId)
    if instance then
        instance.isPlaying = false
        TriggerClientEventForAllPlayers("central_music/PauseBoombox", uniqueId)
    end
end)

RegisterNetEvent("central_music/SetBoomboxVolume")
AddEventHandler("central_music/SetBoomboxVolume", function(uniqueId, volume)
    local instance = GetBoomboxInstance(uniqueId)
    if instance then
        instance.volume = volume / 100
        Debug('server.boomboxSetVolume', tostring(uniqueId), tostring(instance.volume))
        TriggerClientEventForAllPlayers("central_music/UpdateBoomboxVolume", uniqueId, instance.volume)
    end
end)

RegisterNetEvent("central_music/SetBoomboxLoop")
AddEventHandler("central_music/SetBoomboxLoop", function(uniqueId, loop)
    Debug('server.boomboxSetLoop', tostring(uniqueId), tostring(loop))
    local instance = GetBoomboxInstance(uniqueId)
    if instance then
        instance.loop = loop
        TriggerClientEventForAllPlayers("central_music/UpdateBoomboxLoop", uniqueId, loop)
    end
end)

RegisterNetEvent("central_music/SetBoomboxTime")
AddEventHandler("central_music/SetBoomboxTime", function(uniqueId, time)
    Debug('server.boomboxSetTime', tostring(uniqueId), tostring(time))
    local instance = GetBoomboxInstance(uniqueId)
    if instance then
        instance.currentTime = time
        TriggerClientEventForAllPlayers("central_music/UpdateBoomboxTime", uniqueId, time)
    end
end)

RegisterNetEvent("central_music/UpdateBoomboxPosition")
AddEventHandler("central_music/UpdateBoomboxPosition", function(uniqueId, coords)
    Debug('server.boomboxUpdatePos', tostring(uniqueId))
    local instance = GetBoomboxInstance(uniqueId)
    if instance then
        instance.coords = coords
        TriggerClientEventForAllPlayers("central_music/UpdateBoomboxPosition", uniqueId, coords)
    end
end)

RegisterNetEvent("central_music/CheckBoomboxExists")
AddEventHandler("central_music/CheckBoomboxExists", function(uniqueId)
    local instance = GetBoomboxInstance(uniqueId)
    Debug('server.boomboxCheckExists', tostring(uniqueId), tostring(instance ~= nil))
    if not instance then
        TriggerClientEventForAllPlayers("central_music/StopBoombox", uniqueId)
    end
end)

RegisterNetEvent("central_music/AddBoombox")
AddEventHandler("central_music/AddBoombox", function(data)
    local boomboxData = {
        name = data.name,
        coords = data.coords,
        range = data.range,
        volume = data.volume,
        deflink = data.link,
        isplaying = true,
        loop = data.loop,
        deftime = 0,
        isBoombox = true
    }
    table.insert(Config.Zones, boomboxData)
    TriggerClientEventForAllPlayers("central_music/AddVehicle", boomboxData)
end)

function TriggerClientEventForAllPlayers(event, ...)
    local players = GetPlayers()
    for _, player in pairs(players) do
        TriggerClientEvent(event, player, ...)
    end
end

function verifyEntitiesLoop()
    SetTimeout(5000, verifyEntitiesLoop)
    for uniqueId, instance in pairs(boomboxInstances) do
        TriggerClientEventForAllPlayers("central_music/VerifyBoombox", uniqueId)
    end
end

RegisterNetEvent('central_music/CheckVehicleExists')
AddEventHandler('central_music/CheckVehicleExists', function(netId, zoneName)
    for i = #Config.Zones, 1, -1 do
        local zone = Config.Zones[i]
        if zone.popo == netId and zone.name == zoneName then
            Debug('server.vehicleCheckRemoved', tostring(zoneName), tostring(netId))
            table.remove(Config.Zones, i)
            TriggerClientEventForAllPlayers('central_music/StopMusic', zoneName)
            break
        end
    end
end)

RegisterNetEvent("central_music:requestL")
AddEventHandler("central_music:requestL", function()
    local source = source
    Debug('server.localeRequest', tostring(source))
    TriggerClientEvent("central_music:receiveLocale", source, GetLocaleTable())
end)

function countTime()
    SetTimeout(1000, countTime)
    for i = 1, #Config.Zones do
        local v = Config.Zones[i]
        if v.isplaying then
            v.deftime = v.deftime + 1
        end
    end
    for uniqueId, instance in pairs(boomboxInstances) do
        if instance.isPlaying then
            instance.currentTime = instance.currentTime + 1
        end
    end
end

SetTimeout(1000, countTime)
SetTimeout(5000, verifyEntitiesLoop)

RegisterNetEvent('central_music/GetDate')
AddEventHandler('central_music/GetDate', function()
    TriggerClientEventForAllPlayers('central_music/SendData', Config.Zones)
end)

exports('CreateBoomboxInstance', CreateBoomboxInstance)
exports('GetBoomboxInstance', GetBoomboxInstance)
exports('RemoveBoomboxInstance', RemoveBoomboxInstance)

AddEventHandler('onResourceStart', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end
    SetTimeout(3000, function()
        Debug('server.resourceStart', tostring(resourceName))
        if Config.Locale == "pt-br" then
            print("^2✓ Sistema inicializado")
            print("^6► ^7Locale: ^5" .. (Config.Locale or "pt-br") .. "^7")
            print("^6► ^7Developed by: ^5Core Solutions^7")
        elseif Config.Locale == "en-us" then
            print("^2✓ System initialized")
            print("^6► ^7Locale: ^5" .. (Config.Locale or "en") .. "^7")
            print("^6► ^7Developed by: ^5Core Solutions^7")
        elseif Config.Locale == "es-mx" then
            print("^2✓ Sistema inicializado")
            print("^6► ^7Locale: ^5" .. (Config.Locale or "es") .. "^7")
            print("^6► ^7Developed by: ^5Core Solutions^7")
        end
    end)
end)