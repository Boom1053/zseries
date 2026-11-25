-- Self-contained towing client: no external helper script is required.
-- Only the target vehicle's current network owner manipulates its constraint.
-- Visual props remain rigidly attached; the vehicle body must remain dynamic.
local TowPhysics = {}
local owned={}
local M=TowMath
local function dot(a,b) return a.x*b.x+a.y*b.y+a.z*b.z end
local function relativeRotation(vehicle,truck)
    -- Native order 2 (ZXY). Preserve current body pitch/yaw/roll when a
    -- hydraulic change re-seats the axle; do not reset it to a level body.
    local cf,cr,cu=GetEntityMatrix(vehicle)
    local pf,pr,pu=GetEntityMatrix(truck)
    local sx=M.clamp(dot(pu,cf),-1,1)
    local x=math.asin(sx)
    local y,z
    if math.abs(sx)<.999999 then
        y=math.atan(-dot(pu,cr),dot(pu,cu))
        z=math.atan(-dot(pr,cf),dot(pf,cf))
    else
        y=0;z=math.atan(dot(pf,cr),dot(pr,cr))
    end
    return math.deg(x),math.deg(y),math.deg(z)
end
local function prepare(vehicle)
    FreezeEntityPosition(vehicle,false)
    SetEntityDynamic(vehicle,true)
    SetEntityHasGravity(vehicle,true)
    SetEntityCollision(vehicle,true,true) -- retain road/world collision
    SetVehicleHandbrake(vehicle,false)
    SetVehicleBrake(vehicle,false)
    ActivatePhysics(vehicle)
end
local function strapped(tow)
    return tow.straps and tow.straps.left==true and tow.straps.right==true or false
end
local function restrainAxle(vehicle,truck,state,previous)
    -- Both straps add a bounded force couple, never a new joint or a direct
    -- angular-velocity write. Equal opposite forces cannot launch the body.
    local rear=state.tow.yaw==180
    local left=GetEntityBoneIndexByName(vehicle,rear and 'wheel_lr' or 'wheel_lf')
    local right=GetEntityBoneIndexByName(vehicle,rear and 'wheel_rr' or 'wheel_rf')
    if left<0 or right<0 then return end
    local l=GetWorldPositionOfEntityBone(vehicle,left)
    local r=GetWorldPositionOfEntityBone(vehicle,right)
    local actual=M.v((r.x-l.x)*.5,(r.y-l.y)*.5,(r.z-l.z)*.5)
    local width=M.len(actual)
    if not M.finite(width) or width<.3 or width>1.8 then previous.strapError=nil;return end
    local head=M.rotate(M.v(width*(rear and -1 or 1),0,0),state.headRotation)
    local pf,pr,pu=GetEntityMatrix(truck)
    local target=M.v(pr.x*head.x+pf.x*head.y+pu.x*head.z,pr.y*head.x+pf.y*head.y+pu.y*head.z,pr.z*head.x+pf.z*head.y+pu.z*head.z)
    local error=M.sub(target,actual)
    if not M.finite(M.len(error)) then previous.strapError=nil;return end
    local dt=M.clamp(GetFrameTime(),.008,.05)
    local rate=previous.strapError and M.sub(error,previous.strapError) or M.v(0,0,0)
    rate=M.v(rate.x/dt,rate.y/dt,rate.z/dt)
    previous.strapError=error
    -- Drop the radial component: the restraint should turn the axle into the
    -- cradle, not stretch its track width or squeeze suspension components.
    local radial=dot(error,actual)/(width*width)
    error=M.sub(error,M.v(actual.x*radial,actual.y*radial,actual.z*radial))
    radial=dot(rate,actual)/(width*width)
    rate=M.sub(rate,M.v(actual.x*radial,actual.y*radial,actual.z*radial))
    local force=M.v(8*error.x+3*rate.x,8*error.y+3*rate.y,8*error.z+3*rate.z)
    local length=M.len(force)
    if not M.finite(length) then previous.strapError=nil;return end
    if length>4 then force=M.v(force.x*4/length,force.y*4/length,force.z*4/length) end
    local lp=GetOffsetFromEntityGivenWorldCoords(vehicle,l.x,l.y,l.z)
    local rp=GetOffsetFromEntityGivenWorldCoords(vehicle,r.x,r.y,r.z)
    -- Continuous forces, world direction, local application points; the game
    -- scales by body mass and time. No impulses or centre-of-mass net force.
    ApplyForceToEntity(vehicle,0,force.x,force.y,force.z,rp.x,rp.y,rp.z,0,false,true,true,false,true)
    ApplyForceToEntity(vehicle,0,-force.x,-force.y,-force.z,lp.x,lp.y,lp.z,0,false,true,true,false,true)
end
function TowPhysics.forget(vehicle)
    -- Ownership loss must not detach or otherwise write another owner's body.
    owned[vehicle]=nil
end
function TowPhysics.update(vehicle,truck,state)
    if not NetworkHasControlOfEntity(vehicle) then TowPhysics.forget(vehicle);return end
    local tow=state.tow
    local anchor,child=M.towJoint(state)
    local secured=strapped(tow)
    local now=GetGameTimer()
    local previous=owned[vehicle]
    local fresh=not previous or previous.truck~=truck or previous.version~=tow.version
    if fresh then
        local engine=tow.engineRunning
        if engine==nil then engine=GetIsVehicleEngineRunning(vehicle) end
        previous={truck=truck,version=tow.version,engine=engine,maintenance=-100000,lastBind=-100000}
        owned[vehicle]=previous
        if IsEntityAttached(vehicle) then DetachEntity(vehicle,true,true) end
        prepare(vehicle)
        SetVehicleEngineOn(vehicle,false,true,false)
    end
    -- Match the displayed cradle every moving frame. A coarse refresh interval
    -- seats the axle in visible steps; stationary anchors retain their joint.
    -- Keep the same kingpin connection when straps are fitted or removed.
    -- Only actual hydraulic anchor movement rebuilds the attachment.
    if fresh or (now-previous.lastBind>=(Config.TowJointRefreshMs or 0) and M.len(M.sub(anchor,previous.anchor))>(Config.TowAnchorEpsilon or .0001)) then
        if not fresh then DetachEntity(vehicle,true,true) end
        local a=child
        -- This native takes SECOND entity's offset FIRST, followed by the
        -- FIRST entity's offset. Both vectors are entity-root coordinates,
        -- so use matrix/root attachment indices -1 rather than bone index 0.
        -- Rotation stays unconstrained and world/road collision stays active.
        -- doInitialWarp=true seats the CAR at the cradle. The later flag is
        -- addInitialSeparation, not "teleport": keep it false to forbid slack.
        local rx,ry,rz=relativeRotation(vehicle,truck)
        previous.bindCount=(previous.bindCount or 0)+1
        AttachEntityToEntityPhysically(vehicle,truck,-1,-1,
            anchor.x,anchor.y,anchor.z,a.x,a.y,a.z,
            rx,ry,rz,Config.TowBreakForce or 1000000.0,
            false,true,false,false,2)
        previous.anchor=anchor;previous.lastBind=now;previous.secured=secured
    end
    if secured then restrainAxle(vehicle,truck,state,previous) else previous.strapError=nil end
    previous.secured=secured
    -- Empty-vehicle controllers can reapply parking/service brakes. Release
    -- them on the owner every frame without changing the body's transform.
    SetVehicleHandbrake(vehicle,false)
    SetVehicleBrake(vehicle,false)
    if now-previous.maintenance>=(Config.TowMaintenanceMs or 200) then
        ActivatePhysics(vehicle)
        previous.maintenance=now
    end
    return previous
end
function TowPhysics.status(vehicle,truck)
    local p=owned[vehicle]
    if not p then return 'restraint owner remote' end
    local pitch,roll=relativeRotation(vehicle,truck)
    return ('restraint %s | binds %d | pitch %.1f | roll %.1f | strap error %.3f m'):format(
        p.secured and 'couple' or 'ordinary',p.bindCount or 0,pitch,roll,p.strapError and M.len(p.strapError) or 0)
end
function TowPhysics.release(vehicle,truck)
    if not DoesEntityExist(vehicle) or not NetworkHasControlOfEntity(vehicle) then return false end
    local previous=owned[vehicle]
    if (previous and (not truck or previous.truck==truck)) or (truck and IsEntityAttachedToEntity(vehicle,truck)) then
        DetachEntity(vehicle,true,true)
        prepare(vehicle)
        if previous and previous.engine~=nil then SetVehicleEngineOn(vehicle,previous.engine,true,false) end
    elseif IsEntityAttached(vehicle) then
        -- Never detach an unrelated attachment based on an old release record.
        return false
    end
    owned[vehicle]=nil
    return true
end

-- Visuals, controls and replication.
local rigs, released, visuals, attached = {}, {}, {}, {}
local revision=-1
local remote, selected, debugMode=false,nil,Config.Debug
local held={}
local consumedRelease={}
local M=TowMath
local function notice(msg)
    BeginTextCommandThefeedPost('STRING'); AddTextComponentSubstringPlayerName(msg); EndTextCommandThefeedPostTicker(false,false)
end
RegisterNetEvent('zseries:notice',notice)
local function netEntity(id)
    id=tonumber(id)
    if not id or not NetworkDoesEntityExistWithNetworkId(id) then return 0 end
    return NetworkGetEntityFromNetworkId(id)
end
local function displayState(r,display,truck,target)
    display=display or r
    local state={lift=display.lift,extend=display.extend,close=display.close,fold=display.fold,mount=r.mount,tow=r.tow,profile=r.profile,pickupDrop=display.pickupDrop or 0}
    if r.tow and target and target~=0 then
        local cf,cr,cu=GetEntityMatrix(target)
        local pf,pr,pu=GetEntityMatrix(truck)
        -- The T-bar swivels in yaw; vehicle body pitch/roll do not tip it.
        state.targetRotation=M.relativeHead(cf,cr,cu,pf,pr,pu,0)
        local head=M.relativeHead(cf,cr,cu,pf,pr,pu,r.tow.yaw)
        state.headRotation={rx=0,ry=0,rz=strapped(r.tow) and M.clamp(head.rz,-90,90) or head.rz}
    end
    return state
end
if ZSeriesStraps then ZSeriesStraps.setup(function() return rigs end,netEntity,notice) end
local function cleanVisual(id)
    if ZSeriesStraps then ZSeriesStraps.clear(id) end
    local v=visuals[id]
    if not v then return end
    for _,e in pairs(v.parts) do if DoesEntityExist(e) then DeleteEntity(e) end end
    visuals[id]=nil
end
RegisterNetEvent('zseries:snapshot',function(rev,new,rel)
    if rev<revision then return end
    revision=rev
    local normalized={}
    for id,r in pairs(new) do normalized[tonumber(id)]=r end
    rigs=normalized; released={}
    for id,parent in pairs(rel) do released[tonumber(id)]=parent end
    for id,parent in pairs(consumedRelease) do if released[id]~=parent then consumedRelease[id]=nil end end
    for id in pairs(visuals) do if not rigs[id] then cleanVisual(id) end end
end)
local function interactRange(truck)
    if Config.ProfileNamesByHash then
        local fit=Config.ProfileNamesByHash[GetEntityModel(truck)%4294967296]
        return fit and fit.profile.interactDistance or Config.InteractDistance
    end
    for name,profile in pairs(Config.Profiles) do
        if GetEntityModel(truck)==joaat(name) then return profile.interactDistance or Config.InteractDistance end
    end
    return Config.InteractDistance
end
local function nearestTruck(preferRig)
    local ped=PlayerPedId()
    local car=GetVehiclePedIsIn(ped,false)
    if car~=0 then return car end
    local best,dist,priority=0,Config.InteractDistance,math.huge
    for _,v in ipairs(GetGamePool('CVehicle')) do
        local hash=GetEntityModel(v)
        local configured=Config.ProfileNamesByHash and Config.ProfileNamesByHash[hash%4294967296]~=nil or false
        if not Config.ProfileNamesByHash then
            for name in pairs(Config.Profiles) do
                if hash==joaat(name) then configured=true;break end
            end
        end
        if configured or Config.Placement.AllowUnlisted then
            local d=#(GetEntityCoords(ped)-GetEntityCoords(v))
            local rank=preferRig~=false and rigs[NetworkGetNetworkIdFromEntity(v)] and 0 or 1
            if d<interactRange(v) and (rank<priority or (rank==priority and (best==0 or d<dist))) then best,dist,priority=v,d,rank end
        end
    end
    return best
end
local function targetProfile(v)
    for name,profile in pairs(Config.TargetProfiles or {}) do
        if joaat(name)==GetEntityModel(v) then return profile end
    end
    return {}
end
local function axleFor(v,mode,profile)
    local configured=profile and profile[mode]
    if configured and M.finite(configured.x) and M.finite(configured.y) and M.finite(configured.z) then
        return {x=configured.x,y=configured.y,z=configured.z},GetOffsetFromEntityInWorldCoords(v,configured.x,configured.y,configured.z)
    end
    local a=GetEntityBoneIndexByName(v,mode=='rear' and 'wheel_lr' or 'wheel_lf')
    local b=GetEntityBoneIndexByName(v,mode=='rear' and 'wheel_rr' or 'wheel_rf')
    if a<0 or b<0 then return end
    local p=(GetWorldPositionOfEntityBone(v,a)+GetWorldPositionOfEntityBone(v,b))*0.5
    local localP=GetOffsetFromEntityGivenWorldCoords(v,p.x,p.y,p.z)
    return {x=localP.x,y=localP.y,z=localP.z},p
end
local function hookCandidate(truck,r,mode)
    if mode=='auto' then
        local front,fr,fd=hookCandidate(truck,r,'front')
        local rear,rr,rd=hookCandidate(truck,r,'rear')
        if front and rear then return front.distance<=rear.distance and front or rear end
        if front or rear then return front or rear end
        if (fd or math.huge)<=(rd or math.huge) then return nil,fr,fd end
        return nil,rr,rd
    end
    local best,dist=nil,Config.MaxCaptureDistance
    local failure,failDistance=nil,math.huge
    for _,v in ipairs(GetGamePool('CVehicle')) do
        if v~=truck then
            local profile=targetProfile(v)
            local axle,p=axleFor(v,mode,profile)
            local lo,hi=GetModelDimensions(GetEntityModel(v))
            local radius=math.max(.18,math.min(.75,axle and (axle.z-lo.z) or Config.DefaultTyreRadius))
            if type(GetVehicleWheelTireColliderSize)=='function' then
                local wheel=mode=='rear' and 2 or 0
                local size=(GetVehicleWheelTireColliderSize(v,wheel)+GetVehicleWheelTireColliderSize(v,wheel+1))*.5
                if M.finite(size) and size>=.18 and size<=.75 then radius=size end
            end
            if M.finite(profile.radius) then radius=profile.radius end
            local anchor=M.pickupAnchor(r,radius)
            local world=GetOffsetFromEntityInWorldCoords(truck,anchor.x,anchor.y,anchor.z)
            local d=#((p or GetEntityCoords(v))-world)
            local height=p and (p.z-world.z) or math.huge
            local automatic=M.canAutoPickup(r)
            if automatic and p then d=math.sqrt((p.x-world.x)^2+(p.y-world.y)^2) end
            local class=GetVehicleClass(v)
            local mass=GetVehicleHandlingFloat(v,'CHandlingData','fMass')
            local length=hi.y-lo.y
            local yaw=mode=='rear' and 180 or 0
            local delta=(GetEntityHeading(v)-GetEntityHeading(truck)-yaw+180)%360-180
            local reason
            if not NetworkGetEntityIsNetworked(v) then reason='vehicle is not networked'
            elseif class==8 or class==13 or (class>=14 and class<=16) or class==21 then reason='unsupported vehicle class '..class
            elseif not axle then reason='missing '..mode..' wheel bones; configure TargetProfiles axle offsets'
            elseif mass>(profile.maxMass or Config.MaxTargetMass) then reason=('handling mass %.0f exceeds %.0f; check TargetProfiles'):format(mass,profile.maxMass or Config.MaxTargetMass)
            elseif length>(profile.maxLength or Config.MaxTargetLength) then reason=('model length %.2f exceeds %.2f; check TargetProfiles'):format(length,profile.maxLength or Config.MaxTargetLength)
            elseif math.abs(height)>(automatic and Config.MaxPickupAdjustment or (Config.MaxCaptureHeight or .08)) then reason=('cradle height differs by %.2f m; lower/position it beneath the tyre'):format(height)
            elseif d>=Config.MaxCaptureDistance then reason=('axle is %.2f m from cradle (limit %.2f); reposition/lower/extend'):format(d,Config.MaxCaptureDistance)
            elseif math.abs(delta)>Config.MaxCaptureAngle then reason=('alignment is %.1f degrees (limit %.1f); turn vehicle'):format(math.abs(delta),Config.MaxCaptureAngle)
            end
            if reason then
                if d<failDistance and d<8 then
                    failure=('%s pickup: %s. Model %s, class %d.'):format(mode,reason,tostring(GetEntityModel(v)),class)
                    failDistance=d
                end
            elseif d<dist then
                best,dist={id=NetworkGetNetworkIdFromEntity(v),axle=axle,yaw=yaw,mode=mode,distance=d,
                    radius=radius,engineRunning=GetIsVehicleEngineRunning(v)},d
            end
        end
    end
    return best,failure,failDistance
end
local captureNoticeAt=-10000
local function act(action,args)
    if action=='attach' then action='hook' elseif action=='detach' then action='release' end
    local truck=selected and netEntity(selected) or 0
    if action=='install' or action=='place' then truck=nearestTruck(false) end
    if truck==0 or #(GetEntityCoords(PlayerPedId())-GetEntityCoords(truck))>interactRange(truck) then truck=nearestTruck() end
    if truck==0 or not NetworkGetEntityIsNetworked(truck) then return notice('Move beside a configured truck.') end
    local id=NetworkGetNetworkIdFromEntity(truck)
    selected=id
    if action=='status' then
        local r=rigs[id]
        return notice(r and ('Lift %.2f | Extend %.2f | Close %.2f | Fold %.2f | mount %.3f %.3f %.3f'):format(r.lift,r.extend,r.close,r.fold,r.mount.x,r.mount.y,r.mount.z) or 'No boom fitted.')
    end
    if action=='towstatus' then
        local r=rigs[id]
        if not r or not r.tow then return notice('No vehicle is secured to this boom.') end
        local vehicle=netEntity(r.tow.id)
        if vehicle==0 then return notice('Towed vehicle is not streamed here.') end
        local rear=r.tow.yaw==180
        local index=rear and 0 or 2
        local a,b=0,0
        if type(GetVehicleWheelSpeed)=='function' then
            a=math.abs(GetVehicleWheelSpeed(vehicle,index));b=math.abs(GetVehicleWheelSpeed(vehicle,index+1))
        end
        local anchor=M.towAnchor(displayState(r,visuals[id] and visuals[id].display,truck,vehicle))
        local truckPoint=GetOffsetFromEntityInWorldCoords(truck,anchor.x,anchor.y,anchor.z)
        local p=r.tow.axle
        local targetPoint=GetOffsetFromEntityInWorldCoords(vehicle,p.x,p.y,p.z)
        local gap=M.len(M.sub(truckPoint,targetPoint))
        local owner=NetworkHasControlOfEntity(vehicle) and 'local' or 'remote'
        local lifted,road=rear and 'rear' or 'front',rear and 'front' or 'rear'
        local speed=GetEntitySpeed(vehicle)
        print(('[zseries] %s axle lifted; %s axle on road | body %.2f m/s | road wheels %.2f / %.2f m/s | owner %s | anchor gap %.3f m'):format(lifted,road,speed,a,b,owner,gap))
        print('[zseries] '..TowPhysics.status(vehicle,truck))
        return notice(('%s pickup; free %s axle. Body %.1f, wheels %.1f / %.1f m/s. Details in F8.'):format(lifted,road,speed,a,b))
    end
    local data
    if action=='hook' or action=='inspect' then
        if not rigs[id] then return notice('Fit the boom first.') end
        local mode=args and args[1] or 'auto'
        if mode~='auto' and mode~='front' and mode~='rear' then return notice('/zboom hook [auto|front|rear]') end
        local reason
        data,reason=hookCandidate(truck,rigs[id],mode)
        if not data then
            reason=reason or 'No nearby axle found. Move the target beside the cradle.'
            print('[zseries] '..reason);return notice(reason)
        end
        if action=='inspect' then
            local a=data.axle
            local msg=('Ready: %s axle, gap %.3f m, root %.3f %.3f %.3f, tyre %.3f m'):format(data.mode,data.distance,a.x,a.y,a.z,data.radius)
            print('[zseries] '..msg);return notice(msg)
        end
    elseif (action=='close' or (action=='up' and Config.AutoHook~=false and rigs[id] )) and rigs[id] and not rigs[id].tow then
        local reason,distance
        data,reason,distance=hookCandidate(truck,rigs[id],'auto')
        if not data and reason and distance and distance<2.0 then
            local now=GetGameTimer()
            if now-captureNoticeAt>=2000 then
                local message='Not secured: '..reason
                notice(message);print('[zseries] '..message)
                captureNoticeAt=now
            end
        end
    elseif action=='mount' then
        data={x=tonumber(args[1]),y=tonumber(args[2]),z=tonumber(args[3])}
        if not M.finite(data.x) or not M.finite(data.y) or not M.finite(data.z) then return notice('/zboom mount x y z') end
    end
    if (action=='open' or action=='close') and args and args.full then
        data=data or {};data.full=true
    end
    TriggerServerEvent('zseries:action',id,action,data)
end
RegisterCommand('zboom',function(_,args)
    local action=table.remove(args,1)
    if action=='debug' then debugMode=not debugMode; return end
    if action=='version' then return notice('Z-Series 0.2.9-truckfit.1: automatic axle capture / moving boom controls') end
    if action=='open' or action=='close' then args.full=true end
    if not action then return notice('/zboom install | place | up/down | in/out | open/close | fold/deploy/stow | hook front/rear | release | remove | status | debug') end
    act(action,args)
end,false)
RegisterCommand('zremote',function() remote=not remote; selected=nil; held={} end,false)
RegisterKeyMapping('zremote','Toggle Z-Series remote','keyboard','F7')
for _,binding in ipairs({{'up','NUMPAD8'},{'down','NUMPAD2'},{'in','NUMPAD4'},{'out','NUMPAD6'},{'open','NUMPAD7'},{'close','NUMPAD9'}}) do
    local action,key=binding[1],binding[2]
    RegisterCommand('+zs_'..action,function() if remote then held[action]=true end end,false)
    RegisterCommand('-zs_'..action,function() held[action]=nil end,false)
    RegisterKeyMapping('+zs_'..action,'Z-Series '..action,'keyboard',key)
end
CreateThread(function()
    while true do
        Wait(150)
        if remote then
            -- One hydraulic action at a time also respects the server rate limit.
            for _,action in ipairs({'up','down','in','out','open','close'}) do
                if held[action] then act(action,{}); break end
            end
        end
    end
end)
local failed={}
local function createVisual(id,truck)
    local parts={}
    local profile=rigs[id] and Config.Profiles[rigs[id].profile]
    for _,name in ipairs(Config.Parts) do
        local model=joaat(profile and profile.parts and profile.parts[name] or Config.ModelPrefix..name)
        if not IsModelInCdimage(model) or not IsModelValid(model) then
            for _,e in pairs(parts) do DeleteEntity(e) end
            if not failed[id] then notice('Missing streamed model: '..Config.ModelPrefix..name..'. Check stream files and YTYP.'); failed[id]=true end
            return
        end
        RequestModel(model)
        local deadline=GetGameTimer()+5000
        while not HasModelLoaded(model) and GetGameTimer()<deadline do Wait(10) end
        if not HasModelLoaded(model) or not rigs[id] or not DoesEntityExist(truck) then
            for _,e in pairs(parts) do DeleteEntity(e) end
            return
        end
        local p=GetEntityCoords(truck)
        local obj=CreateObjectNoOffset(model,p.x,p.y,p.z,false,false,false)
        SetModelAsNoLongerNeeded(model)
        if obj==0 then for _,e in pairs(parts) do DeleteEntity(e) end; return end
        SetEntityCollision(obj,false,false); SetEntityInvincible(obj,true)
        parts[name]=obj
    end
    local r=rigs[id]
    if not r then for _,e in pairs(parts) do DeleteEntity(e) end; return end
    visuals[id]={truck=truck,parts=parts,display={lift=r.lift,extend=r.extend,close=r.close,fold=r.fold,pickupDrop=r.pickupDrop or 0}}
end
CreateThread(function()
    while true do
        Wait(500)
        local pos=GetEntityCoords(PlayerPedId())
        for id in pairs(visuals) do
            local truck=netEntity(id)
            if truck==0 or #(GetEntityCoords(truck)-pos)>Config.StreamDistance then cleanVisual(id) end
        end
        for id in pairs(rigs) do
            local truck=netEntity(id)
            if truck~=0 and #(GetEntityCoords(truck)-pos)<Config.StreamDistance and not visuals[id] then createVisual(id,truck) end
        end
    end
end)
local function attach(e,parent,p,rx,ry,rz)
    AttachEntityToEntity(e,parent,0,p.x,p.y,p.z,rx,ry,rz,false,false,false,false,2,true)
    SetEntityCollision(e,false,false)
end
local function detachOwned(id,parent)
    local e=netEntity(id)
    if e~=0 and NetworkHasControlOfEntity(e) then
        local truck=parent and netEntity(parent) or (attached[id] and attached[id].truck or 0)
        if truck==0 and IsEntityAttached(e) then return false end
        if TowPhysics.release(e,truck~=0 and truck or nil) then
            SetVehicleOnGroundProperly(e)
            attached[id]=nil
            return true
        end
    end
    return false
end
local function text(x,y,s)
    SetTextFont(0); SetTextScale(0.0,0.31); SetTextColour(255,255,255,230)
    SetTextOutline(); BeginTextCommandDisplayText('STRING'); AddTextComponentSubstringPlayerName(s); EndTextCommandDisplayText(x,y)
end
CreateThread(function()
    TriggerServerEvent('zseries:sync')
    while true do
        Wait(0)
        local dt=math.min(GetFrameTime()*1000/Config.TransitionMs,1)
        for id,v in pairs(visuals) do
            local r=rigs[id]
            if r and DoesEntityExist(v.truck) then
                for _,axis in ipairs({'lift','extend','close','fold','pickupDrop'}) do v.display[axis]=v.display[axis]+((r[axis] or 0)-v.display[axis])*dt end
                local state=displayState(r,v.display,v.truck,r.tow and netEntity(r.tow.id))
                local poses=M.solve(state)
                for name,e in pairs(v.parts) do
                    SetEntityVisible(e,not (ZSeriesPlacement and ZSeriesPlacement.editing(id)),false)
                    local p=poses[name]
                    local profile=Config.Profiles[r.profile]
                    if name=='pump' and profile and profile.pump then
                        p=M.pose(profile.pump)
                    end
                    attach(e,v.truck,M.mountPoint(r,p.p),p.rx,p.ry,p.rz)
                end
                if ZSeriesStraps then ZSeriesStraps.update(r,v.truck,state) end
                if debugMode then
                    local p=r.tow and M.towAnchor(state) or M.mountPoint(r,poses.capture)
                    local w=GetOffsetFromEntityInWorldCoords(v.truck,p.x,p.y,p.z)
                    DrawMarker(28,w.x,w.y,w.z,0,0,0,0,0,0,0.2,0.2,0.2,40,220,150,180,false,false,2,false,nil,nil,false)
                end
            end
        end
        local ped=PlayerPedId()
        local playerVehicle=GetVehiclePedIsIn(ped,false)
        for _,r in pairs(rigs) do
            if r.tow then
                local target,truck=netEntity(r.tow.id),netEntity(r.id)
                if target~=0 and truck~=0 and target~=truck then
                    -- Each client suppresses contacts with its own player and vehicle.
                    -- Frame-only pairs expire on release and preserve road collision.
                    SetEntityNoCollisionEntity(target,truck,true)
                    SetEntityNoCollisionEntity(target,ped,true)
                    if playerVehicle~=0 and playerVehicle~=target and playerVehicle~=truck then
                        SetEntityNoCollisionEntity(target,playerVehicle,true)
                    end
                end
                -- Only the current network owner writes vehicle physics. Peers render local parts.
                if target~=0 and truck~=0 and NetworkHasControlOfEntity(target) then
                    local display=visuals[r.id] and visuals[r.id].display or r
                    local state=displayState(r,display,truck,target)
                    TowPhysics.update(target,truck,state)
                    attached[r.tow.id]={truck=truck,target=target}
                elseif target~=0 then
                    TowPhysics.forget(target)
                    attached[r.tow.id]=nil
                end
            end
        end
        for id,parent in pairs(released) do
            if consumedRelease[id]~=parent and detachOwned(id,parent) then consumedRelease[id]=parent end
        end
        if remote then
            DrawRect(0.14,0.17,0.25,0.24,25,29,33,220)
            text(0.025,0.06,'LIFT AND TOW  |  Z-SERIES')
            text(0.025,0.095,'NUM 8 UP      NUM 2 DOWN')
            text(0.025,0.125,'NUM 4 IN        NUM 6 OUT')
            text(0.025,0.155,'NUM 7 OPEN  NUM 9 CLOSE')
            text(0.025,0.19,'UP: auto grip/lift | Lower + OPEN: release')
            text(0.025,0.225,'F7 closes remote. /zboom for all commands.')
            local rig=selected and rigs[selected]
            if rig and rig.tow then
                local straps=rig.tow.straps or {}
                text(0.025,0.255,'STRAPS: LEFT '..(straps.left and 'SECURED' or 'LOOSE')..' | RIGHT '..(straps.right and 'SECURED' or 'LOOSE'))
            end
        end
    end
end)
-- A target may be owned by another player at hook time. Request control with a
-- bounded cadence; server approval remains mandatory and migration stays enabled.
CreateThread(function()
    while true do
        Wait(500)
        for _,r in pairs(rigs) do
            if r.tow then
                local truck,target=netEntity(r.id),netEntity(r.tow.id)
                if truck~=0 and target~=0 and NetworkHasControlOfEntity(truck) and not NetworkHasControlOfEntity(target) then NetworkRequestControlOfEntity(target) end
            end
        end
    end
end)
local function shutdown(ids)
    for id,parent in pairs(ids or {}) do detachOwned(tonumber(id),parent) end
    for id in pairs(attached) do detachOwned(id) end
    for id in pairs(visuals) do cleanVisual(id) end
    rigs={}
end
RegisterNetEvent('zseries:shutdown',shutdown)
AddEventHandler('onResourceStop',function(name) if name==GetCurrentResourceName() then shutdown(released) end end)

local springHandling={}
local springFields={
    fSuspensionForce=Config.LeafSprings.Force,
    fSuspensionCompDamp=Config.LeafSprings.Compression,
    fSuspensionReboundDamp=Config.LeafSprings.Rebound,
}
local function restoreSprings(id)
    local saved=springHandling[id]
    if not saved then return end
    springHandling[id]=nil
    if netEntity(id)~=saved.vehicle then return end
    for field,value in pairs(saved.values) do
        local current=GetVehicleHandlingFloat(saved.vehicle,'CHandlingData',field)
        if math.abs(current-value.applied)<.001 then
            SetVehicleHandlingFloat(saved.vehicle,'CHandlingData',field,value.original)
        end
    end
end
CreateThread(function()
    while true do
        Wait(500)
        for id,saved in pairs(springHandling) do
            if not rigs[id] or not rigs[id].leafSprings or netEntity(id)~=saved.vehicle then restoreSprings(id) end
        end
        for id,rig in pairs(rigs) do
            local truck=rig.leafSprings and netEntity(id) or 0
            if truck~=0 and not springHandling[id] then
                local saved={vehicle=truck,values={}}
                for field,multiplier in pairs(springFields) do
                    local original=GetVehicleHandlingFloat(truck,'CHandlingData',field)
                    if original>0 then
                        local applied=original*multiplier
                        SetVehicleHandlingFloat(truck,'CHandlingData',field,applied)
                        saved.values[field]={original=original,applied=applied}
                    end
                end
                springHandling[id]=saved
            end
        end
    end
end)
AddEventHandler('onResourceStop',function(name)
    if name==GetCurrentResourceName() then
        for id in pairs(springHandling) do restoreSprings(id) end
    end
end)
exports('useLeafSprings',function(data)
    local ped=PlayerPedId()
    if IsPedInAnyVehicle(ped,false) then return notice('Step out beside the truck first.') end
    local best,nearest
    for id,rig in pairs(rigs) do
        local truck=netEntity(id)
        if truck~=0 then
            local distance=#(GetEntityCoords(ped)-GetEntityCoords(truck))
            if distance<=Config.LeafSprings.Distance and (not nearest or distance<nearest) then
                best,nearest=rig,distance
            end
        end
    end
    if not best then return notice('Stand beside a truck with a fitted Z-Series boom.') end
    if best.leafSprings then return notice('This truck already has leaf springs.') end
    exports.ox_inventory:useItem(data,function(item)
        if item then TriggerServerEvent('zseries:installLeafSprings',best.id,item.slot) end
    end)
end)
