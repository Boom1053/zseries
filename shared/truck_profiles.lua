local profiles=json.decode(LoadResourceFile(GetCurrentResourceName(),'truck_profiles.json'))
assert(type(profiles)=='table','Missing truck_profiles.json')
for name,profile in pairs(profiles) do Config.Profiles[name]=profile end
Config.ProfileNamesByHash={}
for name,profile in pairs(Config.Profiles) do
    Config.ProfileNamesByHash[GetHashKey(name)%4294967296]={name=name,profile=profile}
end
