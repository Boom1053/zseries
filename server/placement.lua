ZSeriesPlacementServer = {}
local S=ZSeriesPlacementServer
local context,sessions,locks,serial=nil,{},{},0
local storage='zseries_model_mounts_v1'
local saved={}
local function tell(src,msg) TriggerClientEvent('zseries:notice',src,msg) end
local function clear(src,message)
    local p=sessions[src]
    if not p then return end
    sessions[src]=nil;locks[p.id]=nil
    TriggerClientEvent('zseries:placementClose',src,p.token,message)
end
function S.setup(c)
    context=c
    local raw=GetResourceKvpString(storage)
    if raw then
        local ok,data=pcall(json.decode,raw)
        if ok and type(data)=='table' then saved=data end
    end
end
function S.locked(id) return locks[id]~=nil end
function S.begin(src,id,name,profile,rig)
    if rig and rig.tow then return tell(src,'Release the vehicle before placing the boom.') end
    for _,other in pairs(context.rigs) do if other.tow and other.tow.id==id then return tell(src,'This truck is being towed.') end end
    if sessions[src] then return tell(src,'Finish or cancel your current boom placement.') end
    if locks[id] then return tell(src,'Someone is already placing a boom on this truck.') end
    local truck=context.resolve(id)
    if GetEntitySpeed(truck)>.5 then return tell(src,'Park the truck before placing the boom.') end
    local model=GetEntityModel(truck)
    local remembered=saved[tostring(model)]
    local mount=rig and rig.mount or remembered or profile.mount
    -- Saved offsets are data, so validate them again before previewing.
    if type(mount)~='table' or not TowMath.finite(mount.x) or not TowMath.finite(mount.y) or not TowMath.finite(mount.z) then mount=profile.mount end
    serial=serial+1
    local token=('%d:%d:%d'):format(src,GetGameTimer(),serial)
    sessions[src]={id=id,token=token,truck=truck,model=model,name=name,profile=profile,rig=rig,expires=GetGameTimer()+180000}
    locks[id]=src
    TriggerClientEvent('zseries:placementOpen',src,token,{id=id,profile=name,mount={x=mount.x,y=mount.y,z=mount.z},
        lift=profile.stowLift or Config.StowLift,extend=0,close=1,fold=1})
end
RegisterNetEvent('zseries:placementSave',function(token,mount)
    local src=source;local p=sessions[src]
    if not p or p.token~=token then return end
    local truck=context.resolve(p.id)
    if truck==0 then return clear(src,'Truck unavailable. Placement cancelled.') end
    for _,other in pairs(context.rigs) do if other.tow and other.tow.id==p.id then return clear(src,'This truck is now being towed. Placement cancelled.') end end
    local ok,reason=context.permitted(src,truck)
    if truck==0 or truck~=p.truck or GetEntityModel(truck)~=p.model or not ok or GetGameTimer()>p.expires or GetEntitySpeed(truck)>.5 or context.rigs[p.id]~=p.rig then
        return clear(src,reason or 'Placement expired or truck changed. Try again while parked.')
    end
    if type(mount)~='table' then return end
    for _,axis in ipairs({'x','y','z'}) do
        if not TowMath.finite(mount[axis]) or math.abs(mount[axis])>6 then return tell(src,'Keep the boom mount within 6 metres of the truck centre.') end
    end
    local r=p.rig or {id=p.id,profile=p.name,lift=p.profile.stowLift or Config.StowLift,extend=0,close=1,fold=1,installedBy=src}
    r.mount={x=mount.x,y=mount.y,z=mount.z}
    r.pickupDrop=0;r.autoReadyAt=nil
    context.rigs[p.id]=r
    -- The Ford always keeps its original install default. Explicit adjustment
    -- affects this Ford only, rather than replacing the known-good profile.
    if p.name~='nathanownboss' then
        saved[tostring(p.model)]={x=mount.x,y=mount.y,z=mount.z}
        SetResourceKvp(storage,json.encode(saved))
    end
    context.publish();clear(src,p.name=='nathanownboss' and 'Boom fitted. Ford default fit preserved.' or 'Boom fitted. Position saved for this truck model.')
end)
RegisterNetEvent('zseries:placementCancel',function(token)
    if sessions[source] and sessions[source].token==token then clear(source,'Boom placement cancelled.') end
end)
AddEventHandler('playerDropped',function() clear(source) end)
CreateThread(function()
    while true do
        Wait(1000)
        for src,p in pairs(sessions) do if GetGameTimer()>p.expires or context.resolve(p.id)~=p.truck then clear(src,'Boom placement expired.') end end
    end
end)
