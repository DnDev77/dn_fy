fx_version "cerulean"

lua54 'yes'

games {
  "gta5"
}

data_file 'DLC_ITYP_REQUEST' 'stream/rojo_jblboombox.ytyp'

ui_page 'web/build/index.html'

client_scripts {
  'config/config.lua',
  'client/main.lua'
}

shared_scripts {
  'locales/*'
}

server_scripts {
  '@oxmysql/lib/MySQL.lua',
  '@vrp/lib/Utils.lua',
  'config/config.lua',
  'config/api.lua',
  'server/adapter.lua',
  'server/locale.lua',
  'server/server.lua'
}

files {
  'web/build/index.html',
  'web/build/**/*',
  'stream/**/*'
}

export 'hasPermission'
export 'getUserId'