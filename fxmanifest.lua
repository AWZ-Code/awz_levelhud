fx_version 'cerulean'
game 'rdr3'
rdr3_warning 'I acknowledge that this is a prerelease build of RedM, and I am aware my resources *will* become incompatible once RedM ships.'
lua54 'yes'

ui_page 'html/index.html'

shared_scripts {
  'config.lua'
}

files {
  'html/index.html',
  'html/style.css',
  'html/app.js',
  'html/img/*.png'
}

client_scripts {
  'client.lua'
}

server_scripts {
  '@oxmysql/lib/MySQL.lua',
  'server.lua'
}

dependencies {
  'oxmysql',
  'vorp_core'
}