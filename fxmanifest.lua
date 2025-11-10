fx_version 'cerulean'
games { 'gta5' }

author 'BLDR Team'
description 'Rob any NPC - QBCore (qb-target + qb-inventory compatible)'
version '1.0.0'

lua54 'yes'

shared_script 'config.lua'

client_scripts {
    'client.lua'
}

server_scripts {
    'server.lua'
}

dependencies {
    'qb-core',
    'qb-target',
    'qb-inventory'
}