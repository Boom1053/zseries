ZSeriesStraps = {}
local S,M,V=ZSeriesStraps,TowMath,StrapMath
local C=Config.Straps
local getRigs,resolve,notify
local props,ready,busy={},false,false
local models={webbing='zs_strap_webbing',ratchet='zs_strap_ratchet',hook='zs_strap_hook',dring='zs_strap_dring'}
local function destroy(list) for _,e in pairs(list or {}) do if DoesEntityExist(e) then DeleteEntity(e) end end end
function S.clear(id)
    local v=props[id]
    if not v then return end
    for _,side in pairs(v) do destroy(side) end
    props[id]=nil
end
local function context(entity)
    if not getRigs or not entity or entity==0 then return end
    local ped=PlayerPedId();local position=GetEntityCoords(ped)
    local best,nearest=nil,C.Distance
    for _,r in pairs(getRigs()) do
        if r.tow and resolve(r.tow.id)==entity then
            for _,side in ipairs({'left','right'}) do
                local bone='wheel_'..(side=='left' and 'l' or 'r')..(r.tow.yaw==180 and 'r' or 'f')
                local index=GetEntityBoneIndexByName(entity,bone)
                if index>=0 then
                    local point=GetWorldPositionOfEntityBone(entity,index)
                    local distance=#(point-position)
                    if distance<nearest then nearest=distance;best={r=r,side=side,entity=entity,point=point} end
                end
            end
        end
    end
    return best
end
local function nearestContext()
    if not getRigs then return end
    local best,distance
    for _,r in pairs(getRigs()) do
        if r.tow then
            local c=context(resolve(r.tow.id))
            if c then
                local d=#(c.point-GetEntityCoords(PlayerPedId()))
                if not distance or d<distance then best,distance=c,d end
            end
        end
    end
    return best
end
local function request(c,mode,slot)
    if busy then return end
    if not c then return notify('Stand beside a tyre secured in the wheel lift.') end
    TriggerServerEvent('zseries:strapBegin',c.r.id,c.side,mode,slot)
end
function S.setup(provider,entityResolver,notice)
    getRigs,resolve,notify=provider,entityResolver,notice
end
exports('useTowStrap',function(data,slot)
    local c=nearestContext()
    if not c then return notify('Stand beside a lifted tyre before using the strap.') end
    if busy then return end
    exports.ox_inventory:useItem(data,function(item)
        if item then
            local fitted=c.r.tow.straps and c.r.tow.straps[c.side]
            request(c,fitted and 'remove' or 'fit',item.slot or (slot and slot.slot))
        end
    end)
end)
RegisterNetEvent('zseries:strapProgress',function(token,mode,duration)
    if busy then return TriggerServerEvent('zseries:strapComplete',token,false) end
    busy=true
    local success=lib.progressCircle({duration=duration,label=mode=='fit' and 'Securing wheel-lift strap' or 'Removing wheel-lift strap',
        position='bottom',useWhileDead=false,canCancel=true,disable={move=true,car=true,combat=true},
        anim={scenario='WORLD_HUMAN_VEHICLE_MECHANIC'},
        prop=mode=='fit' and {model='zs_strap_roll',bone=57005,pos=vec3(.10,.02,0),rot=vec3(90,0,90)} or nil})
    TriggerServerEvent('zseries:strapComplete',token,success==true)
    busy=false
end)
RegisterCommand('zstrap',function(_,args)
    local c=nearestContext()
    if not c then return notify('Stand beside a lifted tyre.') end
    request(c,args[1]=='remove' and 'remove' or 'fit')
end,false)
local targetNames={'zs_fit_wheel_strap','zs_remove_wheel_strap'}
local function registerTarget()
    if GetResourceState('ox_target')~='started' then return end
    exports.ox_target:removeGlobalVehicle(targetNames)
    exports.ox_target:addGlobalVehicle({
        {name=targetNames[1],label='Fit wheel-lift strap',icon='fa-solid fa-link',distance=C.Distance,
            bones={'wheel_lf','wheel_rf','wheel_lr','wheel_rr'},items=C.Item,
            canInteract=function(entity)
                local c=context(entity)
                return not busy and c and not (c.r.tow.straps and c.r.tow.straps[c.side])
            end,
            onSelect=function(data) request(context(data.entity),'fit') end},
        {name=targetNames[2],label='Remove wheel-lift strap',icon='fa-solid fa-link-slash',distance=C.Distance,
            bones={'wheel_lf','wheel_rf','wheel_lr','wheel_rr'},
            canInteract=function(entity)
                local c=context(entity)
                return not busy and c and c.r.tow.straps and c.r.tow.straps[c.side] or false
            end,
            onSelect=function(data) request(context(data.entity),'remove') end}
    })
end
AddEventHandler('onClientResourceStart',function(name) if name=='ox_target' then registerTarget() end end)
CreateThread(function()
    Wait(0);registerTarget()
    local hashes={}
    for key,name in pairs(models) do
        local hash=joaat(name)
        if not IsModelInCdimage(hash) or not IsModelValid(hash) then print('[zseries] Missing strap model: '..name);return end
        hashes[key]=hash;RequestModel(hash)
    end
    local deadline=GetGameTimer()+10000
    repeat
        ready=true
        for _,hash in pairs(hashes) do if not HasModelLoaded(hash) then ready=false end end
        if not ready then Wait(50) end
    until ready or GetGameTimer()>deadline
    if not ready then print('[zseries] Strap models timed out. Check zseries_straps.ytyp and stream files.') end
end)
local function object(model)
    local p=GetEntityCoords(PlayerPedId())
    local e=CreateObjectNoOffset(joaat(models[model]),p.x,p.y,p.z,false,false,false)
    if e==0 then return end
    SetEntityCollision(e,false,false);SetEntityInvincible(e,true);FreezeEntityPosition(e,true)
    return e
end
local function place(e,p,up,normal,length)
    if not e then return end
    up=V.unit(up)
    local right=V.unit(V.cross(normal,up))
    local forward=V.unit(V.cross(up,right))
    local stretch=V.scale(up,length or 1)
    -- Webbing is authored one metre along local Z. Only its length is scaled.
    SetEntityMatrix(e,forward.x,forward.y,forward.z,right.x,right.y,right.z,stretch.x,stretch.y,stretch.z,p.x,p.y,p.z)
end
local function placeTriangle(e,a,b,c)
    if not e then return end
    local right,up=M.sub(b,a),M.sub(c,a)
    local forward=V.unit(V.cross(up,right))
    SetEntityMatrix(e,forward.x,forward.y,forward.z,right.x,right.y,right.z,up.x,up.y,up.z,a.x,a.y,a.z)
end
local function world(truck,p)
    local v=GetOffsetFromEntityInWorldCoords(truck,p.x,p.y,p.z)
    return M.v(v.x,v.y,v.z)
end
function S.update(r,truck,state)
    local target=r.tow and resolve(r.tow.id) or 0
    if not ready or target==0 or not r.tow.straps or next(r.tow.straps)==nil or #(GetEntityCoords(PlayerPedId())-GetEntityCoords(truck))>C.VisualDistance then return S.clear(r.id) end
    local poses=M.solve(state)
    local rawForward,rawRight,rawUp=GetEntityMatrix(target)
    local forward=V.scale(rawForward,r.tow.yaw==180 and -1 or 1)
    local up,right=rawUp,rawRight
    local headR=M.rotate(M.v(1,0,0),state.headRotation)
    local headOrigin=world(truck,M.mountPoint(r,poses.crossbar.p))
    local headRight=V.unit(M.sub(world(truck,M.add(M.mountPoint(r,poses.crossbar.p),headR)),headOrigin))
    props[r.id]=props[r.id] or {}
    for _,side in ipairs({'left','right'}) do
        if r.tow.straps[side] then
            local sign=side=='left' and -1 or 1
            local bone='wheel_'..(sign<0 and 'l' or 'r')..(r.tow.yaw==180 and 'r' or 'f')
            local index=GetEntityBoneIndexByName(target,bone)
            if index>=0 then
                local wheel=GetWorldPositionOfEntityBone(target,index)
                local headX=V.dot(M.sub(wheel,headOrigin),headRight)
                local headSign=headX<0 and -1 or 1
                local width=.25
                if type(GetVehicleWheelTireColliderWidth)=='function' then
                    local wi=(r.tow.yaw==180 and 2 or 0)+(side=='right' and 1 or 0)
                    local value=GetVehicleWheelTireColliderWidth(target,wi)
                    if M.finite(value) and value>.12 and value<.65 then width=value end
                end
                local finger=poses[headSign<0 and 'finger_l' or 'finger_r']
                local function headPoint(x,y,z)
                    return world(truck,M.mountPoint(r,M.add(poses.kingpin,M.rotate(M.v(x,y-Config.Geometry.head_pin_y,z),state.headRotation))))
                end
                local fingerLocal=M.inverseRotate(M.sub(finger.p,poses.kingpin),state.headRotation)
                local frontX=M.clamp(headX-headSign*(width*.5+.03),-Config.Geometry.cross_half_width+.03,Config.Geometry.cross_half_width-.03)
                local front=headPoint(frontX,0,.065)
                local outer=fingerLocal.x+headSign*Config.Geometry.finger_length
                local rearX=M.clamp(headX+headSign*(width*.48+.018),math.min(fingerLocal.x,outer)+.025,math.max(fingerLocal.x,outer)-.025)
                local rear=headPoint(rearX,fingerLocal.y+Config.Geometry.head_pin_y,.04)
                local route=V.route(wheel,front,rear,forward,up,right,r.tow.radius,width,sign)
                local list=props[r.id][side] or {};props[r.id][side]=list
                for i,segment in ipairs(route.segments) do
                    local first,second='band'..i..'a','band'..i..'b'
                    list[first]=list[first] or object('webbing');list[second]=list[second] or object('webbing')
                    placeTriangle(list[first],segment.leftA,segment.rightA,segment.leftB)
                    placeTriangle(list[second],segment.rightB,segment.leftB,segment.rightA)
                end
                for key,model in pairs({ratchet='ratchet',hook='hook',dring='dring'}) do list[key]=list[key] or object(model) end
                place(list.ratchet,route.ratchet,route.ratchetDirection,route.sideNormal)
                place(list.hook,route.rear,up,route.sideNormal)
                place(list.dring,route.front,up,route.sideNormal)
            elseif props[r.id][side] then destroy(props[r.id][side]);props[r.id][side]=nil end
        elseif props[r.id][side] then destroy(props[r.id][side]);props[r.id][side]=nil end
    end
end
AddEventHandler('onResourceStop',function(name)
    if name~=GetCurrentResourceName() then return end
    for id in pairs(props) do S.clear(id) end
    if GetResourceState('ox_target')=='started' then exports.ox_target:removeGlobalVehicle(targetNames) end
    if busy and lib.progressActive() then lib.cancelProgress() end
end)
