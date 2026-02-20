-- pt-br: Funções padrão para compatibilidade com frameworks, se você estiver usando outro framework que não foi detectado, pode manipular essas funções para compatibilizar com o seu framework
-- en: Default functions for framework compatibility, if you are using another framework that was not detected, you can manipulate these functions to be compatible with your framework
-- es: Funciones predeterminadas para compatibilidad con frameworks, si está usando otro framework que no fue detectado, puede manipular estas funciones para ser compatible con su framework

local default = 'default'

_G.functions = {
    ---@return true or false
    hasPermission = function(source, permission) 
        return default
    end,
    ---@return number or nil
    getUserId = function(source)
        return default
    end,
    ---@return true or false
    hasItem = function(source, item)
        return default
    end,
    ---@return result
    registerUsableItem = function(item, cb)
        return default
    end
}
