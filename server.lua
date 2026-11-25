local rigs, released, lastRequest, lastSync = {}, {}, {}, {}
local releaseTimes={}
local revision=0
local sentRevision, lastSnapshot = {}, {}
local snapshotInterval, distantSnapshotInterval = 250, 2000
local function notify(src,msg) TriggerClientEvent('zseries:notice',src,msg) end
local function publish()
    revision=revision+1
end
local function sendSnapshot(src,now)
    TriggerClientEvent('zseries:snapshot',src,revision,rigs,released)
    sentRevision[src]=revision
    lastSnapshot[src]=now
end
local function resolve(id)
    if not TowMath.finite(id) or id%1~=0 or id<1 then return 0 end
    local e=NetworkGetEntityFromNetworkId(id)
    return e~=0 and DoesEntityExist(e) and GetEntityType(e)==2 and e or 0
end
local function rigPositionsByBucket()
    local buckets={}
    for id in pairs(rigs) do
        local truck=resolve(id)
        if truck~=0 then
            local bucket=GetEntityRoutingBucket(truck)
            local positions=buckets[bucket] or {}
            positions[#positions+1]=GetEntityCoords(truck)
            buckets[bucket]=positions
        end
    end
    return buckets
end
local function nearRig(src,buckets)
    local positions=buckets[GetPlayerRoutingBucket(src)]
    if not positions then return false end
    local ped=GetPlayerPed(src)
    if ped==0 or not DoesEntityExist(ped) then return false end
    local position=GetEntityCoords(ped)
    -- Give approaching clients time to catch up before their boom visuals stream in.
    for _,rigPosition in ipairs(positions) do
        if #(position-rigPosition)<=Config.StreamDistance+60 then return true end
    end
    return false
end
CreateThread(function()
    local flushedRevision=0
    while true do
        Wait(snapshotInterval)
        if flushedRevision~=revision then
            local now=GetGameTimer()
            local buckets
            local caughtUp=true
            for _,playerId in ipairs(GetPlayers()) do
                local src=tonumber(playerId)
                if sentRevision[src]~=revision then
                    local elapsed=now-(lastSnapshot[src] or -distantSnapshotInterval)
                    if elapsed>=snapshotInterval then
                        if elapsed>=distantSnapshotInterval then
                            sendSnapshot(src,now)
                        else
                            buckets=buckets or rigPositionsByBucket()
                            if nearRig(src,buckets) then sendSnapshot(src,now) end
                        end
                    end
                    if sentRevision[src]~=revision then caughtUp=false end
                end
            end
            if caughtUp then flushedRevision=revision end
        end
    end
end)
local function profileFor(e)
    local hash=GetEntityModel(e)
    if Config.ProfileNamesByHash then
        local fit=Config.ProfileNamesByHash[hash%4294967296]
        if fit then return fit.name,fit.profile end
    else
        for name,p in pairs(Config.Profiles) do if GetHashKey(name)==hash then return name,p end end
    end
    if Config.Placement.AllowUnlisted and GetEntityType(e)==2 then return 'zseries_custom',Config.Profiles.zseries_custom end
end
local function frameworkJob(src)
    local framework=Config.Framework or 'auto'
    if (framework=='auto' or framework=='ndcore') and GetResourceState('ND_Core')=='started' then
        local player=exports['ND_Core']:getPlayer(src)
        if player then
            if type(player.job)=='string' then return {name=player.job} end
            if type(player.job)=='table' then return player.job end
        end
        if framework=='ndcore' then return end
    end
    if (framework=='auto' or framework=='qbx') and GetResourceState('qbx_core')=='started' then
        local player=exports.qbx_core:GetPlayer(src)
        return player and player.PlayerData and player.PlayerData.job
    end
    if (framework=='auto' or framework=='qbcore') and GetResourceState('qb-core')=='started' then
        local core=exports['qb-core']:GetCoreObject()
        local player=core and core.Functions and core.Functions.GetPlayer(src)
        return player and player.PlayerData and player.PlayerData.job
    end
    if (framework=='auto' or framework=='esx') and GetResourceState('es_extended')=='started' then
        local ok,esx=pcall(function() return exports['es_extended']:getSharedObject() end)
        if not ok or not esx then
            TriggerEvent('esx:getSharedObject',function(object) esx=object end)
        end
        local player=esx and esx.GetPlayerFromId and esx.GetPlayerFromId(src)
        return player and player.job
    end
end
local function hasControlAccess(src)
    if IsPlayerAceAllowed(src,Config.Ace) then return true end
    if not Config.ControlJob then return false end
    local job=frameworkJob(src)
    return job~=nil and job.name==Config.ControlJob
end
local function permitted(src,e)
    if not hasControlAccess(src) then return false,'No tow permission.' end
    local ped=GetPlayerPed(src)
    if ped==0 or not DoesEntityExist(ped) then return false,'Player unavailable.' end
    if GetPlayerRoutingBucket(src)~=GetEntityRoutingBucket(e) then return false,'Different routing bucket.' end
    local _,fit=profileFor(e)
    if #(GetEntityCoords(ped)-GetEntityCoords(e))>(fit and fit.interactDistance or Config.InteractDistance) then return false,'Move closer to the truck.' end
    local seated=GetVehiclePedIsIn(ped,false)
    if seated~=0 and (seated~=e or GetPedInVehicleSeat(e,-1)~=ped) then return false,'Use the driver seat or stand beside the truck.' end
    if Config.OperateWhileMoving==false and GetEntitySpeed(e)>Config.MaxOperateSpeed then return false,'Stop the truck first.' end
    return true
end
local function release(r)
    if ZSeriesStrapsServer then ZSeriesStrapsServer.clear(r) end
    if r.tow then released[r.tow.id]=r.id; releaseTimes[r.tow.id]=GetGameTimer(); r.tow=nil end
end
-- Read-only server bridge for the NPC wreck-chaser resource.
exports('GetWreckChaserTow', function(truck, target)
    if truck == 0 and target == 0 then return true end
    if not DoesEntityExist(truck) or not DoesEntityExist(target) then return end
    local id = NetworkGetNetworkIdFromEntity(truck)
    local tow = rigs[id] and rigs[id].tow
    if tow and resolve(id) == truck and resolve(tow.id) == target then
        return tow.version, tow.operator
    end
end)
local function pickup(src,truck,r,data)
    if type(data)~='table' or type(data.axle)~='table' then return nil,'No axle selected.' end
    local target=resolve(data.id)
    if target==0 or target==truck or rigs[data.id] then return nil,'Invalid target vehicle.' end
    if GetResourceState('wreckchasers') == 'started' then
        local allowed = exports.wreckchasers:CanHookWreck(src, target)
        if not allowed then return nil,'This wreck requires your own dispatch contract.' end
    end
    if GetEntityRoutingBucket(target)~=GetEntityRoutingBucket(truck) then return nil,'Different routing bucket.' end
    if GetVehicleType(target)~='automobile' then return nil,'Only empty four-wheel road vehicles are supported.' end
    for _,other in pairs(rigs) do
        if other.tow and other.tow.id==data.id then return nil,'Vehicle is already claimed.' end
    end
    local fit=Config.Profiles[r.profile] or {}
    if #(GetEntityCoords(target)-GetEntityCoords(truck))>(fit.maxTargetDistance or 9) or GetEntitySpeed(target)>1.5 then return nil,'Stop and position the vehicle in the cradle.' end
    for seat=-1,15 do if GetPedInVehicleSeat(target,seat)~=0 then return nil,'Vehicle must be empty.' end end
    if data.yaw~=0 and data.yaw~=180 then return nil,'Invalid axle orientation.' end
    local a=data.axle
    if not TowMath.finite(a.x) or not TowMath.finite(a.y) or not TowMath.finite(a.z) or math.abs(a.x)>.25 or math.abs(a.y)>4 or math.abs(a.z)>1.5 then return nil,'Invalid axle point.' end
    local radius=data.radius or Config.DefaultTyreRadius
    if not TowMath.finite(radius) or radius<.18 or radius>.75 then return nil,'Unsupported tyre radius.' end
    local capture=TowMath.pickupAnchor(r,radius)
    -- Match the client's entity-root transform, including pitch and roll.
    -- Server GET_ENTITY_ROTATION returns the same ZXY/order-2 convention.
    local function worldPoint(entity,point)
        local position=GetEntityCoords(entity)
        local rotation=GetEntityRotation(entity)
        local offset=TowMath.rotate(point,{rx=rotation.x,ry=rotation.y,rz=rotation.z})
        return TowMath.add(TowMath.v(position.x,position.y,position.z),offset)
    end
    local expected=worldPoint(truck,capture)
    local actual=worldPoint(target,a)
    if TowMath.canAutoPickup(r) then
        local delta=(GetEntityHeading(target)-GetEntityHeading(truck)-data.yaw+180)%360-180
        local xy=math.sqrt((expected.x-actual.x)^2+(expected.y-actual.y)^2)
        if xy>Config.MaxCaptureDistance or math.abs(delta)>Config.MaxCaptureAngle then return nil,'Align the axle with the cradle before automatic height adjustment.' end
        if r.autoReadyAt and GetGameTimer()<r.autoReadyAt then return nil end
        local error=actual.z-expected.z
        if math.abs(error)>(Config.AutoPickupHeightTolerance or .025) then
            if GetEntitySpeed(truck)>.5 or GetEntitySpeed(target)>.5 then return nil,'Stop for automatic pickup height adjustment.' end
            local rotation=GetEntityRotation(truck)
            local up=TowMath.rotate(TowMath.v(0,0,1),{rx=rotation.x,ry=rotation.y,rz=rotation.z})
            if up.z<.8 then return nil,'Truck is too tilted for automatic pickup height adjustment.' end
            local offset=(r.pickupDrop or 0)+error/up.z
            if not TowMath.finite(offset) or math.abs(offset)>(Config.MaxPickupAdjustment or .75) then
                return nil,'Mount is outside automatic pickup travel. Adjust its placement closer to the bumper.'
            end
            r.pickupDrop=offset;r.autoReadyAt=GetGameTimer()+3*Config.TransitionMs+100
            publish()
            return nil,'Adjusting cradle height automatically. Keep holding UP or CLOSE.'
        end
    end
    if math.abs(expected.z-actual.z)>(Config.MaxCaptureHeight or .08) then return nil,('Cradle contact height differs by %.3f m (limit %.3f m). Lower/position beneath the tyre.'):format(actual.z-expected.z,Config.MaxCaptureHeight or .08) end
    if TowMath.len(TowMath.sub(expected,actual))>Config.MaxCaptureDistance then return nil,'Axle is too far from the cradle.' end
    local diff=(GetEntityHeading(target)-GetEntityHeading(truck)-data.yaw+180)%360-180
    if math.abs(diff)>Config.MaxCaptureAngle then return nil,'Align the vehicle with the truck.' end
    local seat,fold=TowMath.gripGeometry(radius)
    return {id=data.id,axle={x=a.x,y=a.y,z=a.z},yaw=data.yaw,
        mode=data.yaw==180 and 'rear' or 'front',radius=radius,gripFold=fold,
        engineRunning=type(data.engineRunning)=='boolean' and data.engineRunning or false}
end
-- Reuse the existing tow record and physics path; only capture initiation changes.
local function secure(src,r,tow,now)
    tow.operator=src
    tow.version=now
    tow.gripReadyAt=now+(Config.GripCloseMs or 400)
    r.tow=tow;r.close=1;r.fold=tow.gripFold
    released[tow.id]=nil;releaseTimes[tow.id]=nil
end
if ZSeriesStrapsServer then ZSeriesStrapsServer.setup({rigs=rigs,resolve=resolve,permitted=permitted,publish=publish}) end
if ZSeriesPlacementServer then ZSeriesPlacementServer.setup({rigs=rigs,resolve=resolve,permitted=permitted,publish=publish}) end
RegisterNetEvent('zseries:sync',function()
    local src=source
    local now=GetGameTimer()
    if lastSync[src] and now-lastSync[src]<2000 then return end
    lastSync[src]=now
    sendSnapshot(src,now)
end)
RegisterNetEvent('zseries:installLeafSprings',function(id,slot)
    local src=source
    local job=frameworkJob(src)
    local mechanicJob=Config.MechanicJob or 'mechanic'
    if not job or (job.name~=mechanicJob and job.type~=(Config.MechanicJobType or mechanicJob)) then
        return notify(src,'Only mechanics can install leaf springs.')
    end

    local truck=resolve(id)
    local rig=rigs[id]
    if truck==0 or not rig then return notify(src,'This truck needs a fitted Z-Series boom.') end
    if rig.leafSprings then return notify(src,'This truck already has leaf springs.') end
    local ped=GetPlayerPed(src)
    if ped==0 or GetPlayerRoutingBucket(src)~=GetEntityRoutingBucket(truck)
        or #(GetEntityCoords(ped)-GetEntityCoords(truck))>Config.LeafSprings.Distance then
        return notify(src,'Stand beside the truck to install leaf springs.')
    end
    if GetVehiclePedIsIn(ped,false)~=0 or GetEntitySpeed(truck)>.2 or rig.tow then
        return notify(src,'Park the truck, release the load and step out first.')
    end
    if not TowMath.finite(slot) or slot%1~=0 or slot<1 then return end
    local inventory=exports.ox_inventory
    local item=inventory:GetSlot(src,slot)
    if not item or item.name~=Config.LeafSprings.Item
        or not inventory:RemoveItem(src,item.name,1,item.metadata,slot,false,true) then
        return notify(src,'You need a Leaf Springs kit in your inventory.')
    end
    rig.leafSprings=true
    publish()
    notify(src,'Leaf springs installed.')
end)
RegisterNetEvent('zseries:action',function(id,action,data)
    local src=source
    local now=GetGameTimer()
    if lastRequest[src] and now-lastRequest[src]<100 then return end
    lastRequest[src]=now
    local truck=resolve(id)
    if truck==0 then return end
    local ok,why=permitted(src,truck)
    if not ok then return notify(src,why) end
    local profileName,profile=profileFor(truck)
    if not profile then return notify(src,'Truck model has no Config.Profiles entry.') end
    local r=rigs[id]
    if ZSeriesPlacementServer and ZSeriesPlacementServer.locked(id) then return notify(src,'Finish or cancel boom placement first.') end
    if action=='place' then
        if ZSeriesPlacementServer then return ZSeriesPlacementServer.begin(src,id,profileName,profile,r) end
        return
    end
    if action=='install' then
        if r then return notify(src,'A boom is already fitted.') end
        for _,other in pairs(rigs) do if other.tow and other.tow.id==id then return notify(src,'This truck is being towed.') end end
        if ZSeriesPlacementServer and profileName~='nathanownboss' and not profile.fitted then return ZSeriesPlacementServer.begin(src,id,profileName,profile) end
        rigs[id]={id=id,profile=profileName,mount={x=profile.mount.x,y=profile.mount.y,z=profile.mount.z},
            lift=profile.stowLift or Config.StowLift,extend=0,close=1,fold=1,installedBy=src}
        publish()
        return notify(src,profile.calibrated and 'Boom fitted.' or 'Boom fitted with example coordinates. Calibrate the mount before towing.')
    end
    if not r then return notify(src,'Fit the boom with /zboom install.') end
    if action=='remove' then
        if r.tow then return notify(src,'Lower and release the vehicle first.') end
        rigs[id]=nil
    elseif action=='mount' then
        if r.tow then return notify(src,'Release the vehicle before mount calibration.') end
        if type(data)~='table' then return end
        for _,axis in ipairs({'x','y','z'}) do if not TowMath.finite(data[axis]) or math.abs(data[axis])>6 then return end end
        r.mount={x=data.x,y=data.y,z=data.z}
        r.pickupDrop=0;r.autoReadyAt=nil
    elseif action=='hook' then
        if r.tow then return notify(src,'A vehicle is already attached.') end
        if r.close<.95 then return notify(src,'Lower the boom and close the arms first.') end
        local tow,reason=pickup(src,truck,r,data)
        if not tow then if reason then notify(src,reason) end;return end
        secure(src,r,tow,now)
        notify(src,'Vehicle secured to the wheel-lift.')
    elseif action=='release' then
        if Config.Straps.BlockRelease and ZSeriesStrapsServer and ZSeriesStrapsServer.has(r) then return notify(src,'Remove the wheel straps before releasing the vehicle.') end
        if r.lift>(profile.releaseLift or .25) then return notify(src,'Lower the vehicle before release.') end
        release(r)
        notify(src,'Vehicle released.')
    elseif action=='up' or action=='down' then
        local hooked=false
        if action=='up' and not r.tow and Config.AutoHook~=false and type(data)=='table' and data.id~=nil then
            local tow,reason=pickup(src,truck,r,data)
            if not tow then if reason then notify(src,reason) end;return end
            secure(src,r,tow,now)
            hooked=true
            notify(src,'Axle secured automatically.')
        end
        if action=='up' and r.tow and now<(r.tow.gripReadyAt or 0) then
            if hooked then publish() end
            return
        end
        local maxLift=(r.tow and profile.loadedMaxLift) or profile.maxLift or 1
        local step=Config.Step*Config.Geometry.lift_travel/(profile.liftTravel or Config.Geometry.lift_travel)
        local lift=TowMath.clamp(r.lift+(action=='up' and step or -step),profile.minLift or 0,maxLift)
        if not hooked and lift==r.lift then return end
        r.lift=lift
    elseif action=='in' or action=='out' then
        if r.tow then return notify(src,'Release the vehicle before telescoping.') end
        local extend=TowMath.clamp(r.extend+(action=='out' and Config.Step or -Config.Step),0,1)
        if extend==r.extend then return end
        r.extend=extend
    elseif action=='fold' or action=='deploy' then
        if r.tow then return notify(src,'Release the vehicle before folding the arms.') end
        r.fold=action=='fold' and 1 or 0
        r.close=action=='fold' and 1 or 0
    elseif action=='stow' then
        if r.tow then return notify(src,'Release the vehicle before storage.') end
        if r.fold<0.95 or r.extend>0.05 then return notify(src,'Use fold, then in, before stow.') end
        r.lift=profile.stowLift or Config.StowLift
        r.pickupDrop=0;r.autoReadyAt=nil
    elseif action=='open' or action=='close' then
        if action=='open' and r.tow and Config.AutoReleaseOnOpen~=false then
            if Config.Straps.BlockRelease and ZSeriesStrapsServer and ZSeriesStrapsServer.has(r) then return notify(src,'Remove the wheel straps before opening the arms.') end
            if r.lift>(profile.releaseLift or .25) then return notify(src,'Lower the boom before opening the arms.') end
            release(r)
            notify(src,'Vehicle released.')
        end
        if r.tow then
            if action=='open' then return notify(src,'Release the vehicle before opening the arms.') end
            r.close=1;r.fold=r.tow.gripFold
        elseif action=='open' then
            if type(data)=='table' and data.full==true then r.fold=0;r.close=0
            elseif r.fold>0 then r.fold=TowMath.clamp(r.fold-Config.Step,0,1)
            else r.close=TowMath.clamp(r.close-Config.Step,0,1) end
        else
            local limit=1
            local contact
            if type(data)=='table' and data.id~=nil then
                local reason
                contact,reason=pickup(src,truck,r,data)
                if not contact then if reason then notify(src,reason) end;return end
                limit=contact.gripFold
            end
            if type(data)=='table' and data.full==true then r.close=1;r.fold=limit
            elseif r.close>=1 then r.fold=math.min(TowMath.clamp(r.fold+Config.Step,0,1),limit)
            else r.close=TowMath.clamp(r.close+Config.Step,0,1) end
            if Config.AutoHook~=false and contact and r.close>=.95 then
                secure(src,r,contact,now)
                notify(src,'Axle secured automatically.')
            end
        end
    else return end
    publish()
end)
AddEventHandler('playerDropped',function()
    local src=source
    if ZSeriesStrapsServer then ZSeriesStrapsServer.playerDropped(src) end
    lastRequest[src]=nil; lastSync[src]=nil
    sentRevision[src]=nil; lastSnapshot[src]=nil
    -- Keep rigs across operator disconnects; network owners reapply cargo attachment.
end)
CreateThread(function()
    while true do
        Wait(1000)
        local changed=false
        for id,r in pairs(rigs) do
            local truck=resolve(id)
            if truck==0 then release(r); rigs[id]=nil; changed=true
            elseif r.tow then
                local target=resolve(r.tow.id)
                local invalid=target==0
                if target~=0 then
                    invalid=GetEntityRoutingBucket(target)~=GetEntityRoutingBucket(truck)
                    for seat=-1,15 do if GetPedInVehicleSeat(target,seat)~=0 then invalid=true end end
                end
                if invalid then release(r); changed=true end
            end
        end
        for id in pairs(released) do
            if resolve(id)==0 or GetGameTimer()-(releaseTimes[id] or 0)>15000 then
                released[id]=nil; releaseTimes[id]=nil; changed=true
            end
        end
        if changed then publish() end
    end
end)
AddEventHandler('onResourceStop',function(name)
    if name~=GetCurrentResourceName() then return end
    -- Client stop handler detaches controlled cargo; this also reaches running peers.
    for _,r in pairs(rigs) do release(r) end
    TriggerClientEvent('zseries:shutdown',-1,released)
end)

