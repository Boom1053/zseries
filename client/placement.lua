ZSeriesPlacement = {}
local S=ZSeriesPlacement
local active
local function destroy()
    if not active then return end
    for _,e in pairs(active.parts) do if DoesEntityExist(e) then DeleteEntity(e) end end
    active=nil
end
function S.editing(id) return active and active.rig.id==id or false end
local function cancel()
    if not active then return end
    TriggerServerEvent('zseries:placementCancel',active.token);destroy()
end
RegisterNetEvent('zseries:placementClose',function(token,message)
    if active and active.token==token then destroy() end
    if message then TriggerEvent('zseries:notice',message) end
end)
RegisterNetEvent('zseries:placementOpen',function(token,rig)
    if active then cancel() end
    local truck=NetworkGetEntityFromNetworkId(rig.id)
    if truck==0 or not DoesEntityExist(truck) then return TriggerServerEvent('zseries:placementCancel',token) end
    local p={token=token,rig=rig,truck=truck,parts={},start=GetGameTimer(),initial={x=rig.mount.x,y=rig.mount.y,z=rig.mount.z}}
    active=p
    CreateThread(function()
        for _,name in ipairs(Config.Parts) do
            local profile=Config.Profiles[rig.profile]
            local hash=joaat(profile and profile.parts and profile.parts[name] or Config.ModelPrefix..name)
            RequestModel(hash)
            local deadline=GetGameTimer()+10000
            while not HasModelLoaded(hash) and active==p and GetGameTimer()<deadline do Wait(0) end
            if active~=p then return end
            if not HasModelLoaded(hash) then cancel();return TriggerEvent('zseries:notice','Boom preview model failed to load.') end
            local pos=GetEntityCoords(truck)
            local e=CreateObjectNoOffset(hash,pos.x,pos.y,pos.z,false,false,false)
            if e==0 then cancel();return end
            p.parts[name]=e
            SetEntityCollision(e,false,false);SetEntityAlpha(e,185,false)
            SetEntityInvincible(e,true)
        end
        p.ready=true
    end)
end)
local function text(y,message)
    SetTextFont(0);SetTextScale(0,.32);SetTextColour(255,255,255,240);SetTextOutline()
    BeginTextCommandDisplayText('STRING');AddTextComponentSubstringPlayerName(message);EndTextCommandDisplayText(.025,y)
end
CreateThread(function()
    while true do
        Wait(0)
        local p=active
        if p then
            local profile=Config.Profiles[p.rig.profile] or {}
            if not DoesEntityExist(p.truck) or GetEntitySpeed(p.truck)>.5 or #(GetEntityCoords(PlayerPedId())-GetEntityCoords(p.truck))>(profile.interactDistance or Config.InteractDistance) or GetGameTimer()-p.start>180000 then
                cancel()
            else
                for _,control in ipairs({172,173,174,175,10,11,21,36,191,194,45,37,71,72,59,60}) do DisableControlAction(0,control,true) end
                local function down(c) return IsDisabledControlPressed(0,c) end
                local function pressed(c) return IsDisabledControlJustPressed(0,c) end
                local rate=down(36) and .04 or down(21) and 1.0 or .25
                local step=math.min(GetFrameTime(),.05)*rate
                local mount=p.rig.mount
                mount.x=TowMath.clamp(mount.x+((down(175) and 1 or 0)-(down(174) and 1 or 0))*step,-6,6)
                mount.y=TowMath.clamp(mount.y+((down(172) and 1 or 0)-(down(173) and 1 or 0))*step,-6,6)
                mount.z=TowMath.clamp(mount.z+((down(10) and 1 or 0)-(down(11) and 1 or 0))*step,-6,6)
                if pressed(45) then p.rig.mount={x=p.initial.x,y=p.initial.y,z=p.initial.z} end
                if pressed(37) then p.deployed=not p.deployed end
                if pressed(194) then cancel()
                elseif pressed(191) and p.ready and not p.saving then
                    p.saving=true;TriggerServerEvent('zseries:placementSave',p.token,p.rig.mount)
                    SetTimeout(1500,function() if active==p then p.saving=false end end)
                end
                if active==p then
                    local r=p.rig
                    local profile=Config.Profiles[r.profile] or {}
                    local state={mount=r.mount,profile=r.profile,lift=p.deployed and (profile.minLift or 0) or r.lift,extend=p.deployed and 1 or 0,close=p.deployed and 0 or 1,fold=p.deployed and 0 or 1}
                    local poses=TowMath.solve(state)
                    for name,e in pairs(p.parts) do
                        local pose=name=='pump' and profile.pump and TowMath.pose(profile.pump) or poses[name]
                        local point=TowMath.mountPoint(state,pose.p)
                        AttachEntityToEntity(e,p.truck,0,point.x,point.y,point.z,pose.rx,pose.ry,pose.rz,false,false,false,false,2,true)
                        SetEntityCollision(e,false,false)
                    end
                    DrawRect(.19,.16,.36,.24,25,29,33,225)
                    text(.055,'PLACE Z-SERIES BOOM')
                    text(.09,'Arrows: move along truck | Page Up/Down: height')
                    text(.125,'Shift: faster | Ctrl: fine | R: reset')
                    text(.16,'Tab: preview stored / deployed')
                    text(.195,'Enter: fit and save | Backspace: cancel')
                    text(.23,('Position: %.3f  %.3f  %.3f'):format(r.mount.x,r.mount.y,r.mount.z))
                end
            end
        end
    end
end)
AddEventHandler('onResourceStop',function(name) if name==GetCurrentResourceName() then destroy() end end)
