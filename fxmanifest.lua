fx_version 'cerulean'
game 'gta5'
author 'Z-Series reference build'
description 'Z-Series wheel lift with fitted Nathan truck profiles with reusable tyre straps and mechanic-installed leaf springs and Wreck Chasers support'
version '0.2.9-truckfit.3'
dependency '/onesync'
files { 'geometry.json', 'truck_profiles.json', 'stream/*.ytyp' }
data_file 'DLC_ITYP_REQUEST' 'stream/zseries.ytyp'
data_file 'DLC_ITYP_REQUEST' 'stream/zseries_straps.ytyp'
data_file 'DLC_ITYP_REQUEST' 'stream/zseries_long_cylinders.ytyp'
dependencies { 'ox_lib', 'ox_inventory' }
shared_scripts { '@ox_lib/init.lua', 'config.lua', 'shared/truck_profiles.lua', 'shared/kinematics.lua', 'shared/straps.lua' }
server_scripts { 'server/straps.lua', 'server/placement.lua', 'server/main.lua' }
client_scripts { 'client/straps.lua', 'client/placement.lua', 'client/main.lua' }

-- Server owners can edit permissions, tuning, and truck fits.
escrow_ignore {
    'config.lua',
    'geometry.json',
    'truck_profiles.json',
    'stream/*.ytyp'
}
