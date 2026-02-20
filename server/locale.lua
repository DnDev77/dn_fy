local _loadedLocale = {}

function _deepGet(tbl, key)
    local parts = {}
    for part in key:gmatch('[^.]+') do
        table.insert(parts, part)
    end
    local value = tbl
    for _, part in ipairs(parts) do
        if type(value) == 'table' then
            value = value[part]
        else
            return nil
        end
    end
    return value
end

--- @param key string  ex: "notifications.boomboxPickedUp"
--- @param ...         argumentos opcionais para string.format
--- @return string
function Locale(key, ...)
    local value = _deepGet(_loadedLocale, key)
    if type(value) ~= 'string' then
        return key
    end
    if select('#', ...) > 0 then
        local ok, result = pcall(string.format, value, ...)
        return ok and result or value
    end
    return value
end

function Debug(key, ...)
    if not Config.Debug then return end
    local msg = _deepGet(_loadedLocale, 'debug.' .. key)
    if type(msg) ~= 'string' then
        print('^3[central_music:debug]^7 [missing key: ' .. tostring(key) .. ']')
        return
    end
    local prefix = _deepGet(_loadedLocale, 'debug.prefix') or '^3[central_music:debug]^7'
    if select('#', ...) > 0 then
        local ok, result = pcall(string.format, msg, ...)
        print(prefix .. ' ' .. (ok and result or msg))
    else
        print(prefix .. ' ' .. msg)
    end
end

--- Retorna a tabela de locale
--- @return table
function GetLocaleTable()
    return _loadedLocale
end

function LoadLocale(lang)
    lang = (lang or 'pt-br'):lower()
    local path = ('locales/%s.json'):format(lang)
    local content = LoadResourceFile(GetCurrentResourceName(), path)

    if not content then
        print(('^3[central_music] ^7Locale "^5%s^7" não encontrado. Usando ^5pt-br^7 como fallback.'):format(lang))
        content = LoadResourceFile(GetCurrentResourceName(), 'locales/pt-br.json')
    end

    if content then
        local ok, decoded = pcall(json.decode, content)
        if ok and type(decoded) == 'table' then
            _loadedLocale = decoded
            print(('^2[central_music] ^7Locale "^5%s^7" carregado com sucesso.'):format(lang))
        else
            print('^1[central_music] ^7ERRO ao parsear arquivo de locale!')
        end
    else
        print('^1[central_music] ^7ERRO CRÍTICO: Nenhum arquivo de locale encontrado!')
    end
end

CreateThread(function()
    while not Config do Wait(100) end
    LoadLocale(Config.Locale)
end)