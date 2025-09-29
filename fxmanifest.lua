fx_version 'cerulean'
lua54 'yes'
games { 'gta5' }

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/script.js',
    'data/recipes.json',
    'data/stations.json'
}

shared_scripts {
    '@es_extended/imports.lua',
    'config.lua',
    'shared/*.lua',
    'locales/*.lua'
}

client_scripts {
    'client/main.lua'
}

server_scripts {
    '@mysql-async/lib/MySQL.lua',
    'server/main.lua'
}

escrow_ignore {
    'config.lua',
    'locales/*.lua',
    'data/*.json'
}

provide 'rp_crafting'
