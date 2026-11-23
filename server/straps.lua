-- One inventory item is held on each fitted tyre until recovered.
ZSeriesStrapsServer = {}
local S=ZSeriesStrapsServer
local context,pending,locks,bindings,wheelBindings,sequence=nil,{},{},{},{},0
local C=Config.Straps
local ledgerKey='zseries_strap_escrow_v1'
local ledgerLoaded=false
local lastBegin={}
local function tell(src,message) TriggerClientEvent('zseries:notice',src,message) end
local function inventory(method,...)
    if GetResourceState(C.Inventory)~='started' then return nil end
    local args={...}
    local ok,result=pcall(function() return exports[C.Inventory][method](nil,table.unpack(args)) end)
    if ok then return result end
    print('[zseries] strap inventory call failed: '..method)
end
local function slot(src,index) return inventory('GetSlot',src,index) end
local function copy(t) local out={} for k,v in pairs(t or {}) do out[k]=v end return out end
local function owner(src)
    local inv=inventory('GetInventory',src)
    return inv and inv.owner
end
local function key(r,side) return ('%s:%s:%s'):format(r.id,r.tow.version,side) end
local function valid(src,id,side,version)
    if not context or (side~='left' and side~='right') or type(id)~='number' then return nil,'Invalid wheel.' end
    local r=context.rigs[id]
    if not r or not r.tow or (version and r.tow.version~=version) then return nil,'That vehicle is no longer on this lift.' end
    local truck,target=context.resolve(id),context.resolve(r.tow.id)
    if truck==0 or target==0 then return nil,'Vehicle unavailable.' end
    local allowed,reason=context.permitted(src,truck)
    if not allowed then return nil,reason end
    if GetEntityRoutingBucket(target)~=GetPlayerRoutingBucket(src) then return nil,'Different routing bucket.' end
    local ped=GetPlayerPed(src)
    if GetVehiclePedIsIn(ped,false)~=0 then return nil,'Step out and stand beside the tyre.' end
    if GetEntitySpeed(truck)>C.MaxSpeed or GetEntitySpeed(target)>C.MaxSpeed then return nil,'Stop before fitting or removing straps.' end
    local p,t=GetEntityCoords(ped),GetEntityCoords(target)
    local rot=GetEntityRotation(target)
    local localP=TowMath.inverseRotate(TowMath.sub(p,t),{rx=rot.x,ry=rot.y,rz=rot.z})
    local sign=side=='left' and -1 or 1
    if localP.x*sign<.20 then
        return nil,'Stand beside the selected lifted tyre.'
    end
    -- Validate a wheel-side region rather than a narrow rectangular axle box.
    -- Wheel bones are client-only; this bounded half-track accommodates normal
    -- cars/add-ons without trusting a client-provided world position. The
    -- client still selects the actual wheel within C.Distance. Allow 25 cm for
    -- replicated suspension/body movement between selection and this check.
    local wheel=TowMath.v(r.tow.axle.x+sign*TowMath.clamp(math.abs(localP.x-r.tow.axle.x),.65,1.65),r.tow.axle.y,r.tow.axle.z)
    local distance=TowMath.len(TowMath.sub(localP,wheel))
    if distance>C.Distance+.25 then
        return nil,('Move closer to the selected lifted tyre (%.2f m; limit %.2f m).'):format(distance,C.Distance+.25)
    end
    return r
end
local function saveLedger()
    SetResourceKvp(ledgerKey,json.encode(bindings))
end
local function returnItem(token,src)
    local b=bindings[token]
    if not b then return false end
    if not inventory('AddItem',src,C.Item,1,copy(b.metadata)) then return false end
    bindings[token]=nil;saveLedger()
    return true
end
local function originalOwner(b)
    -- Use the inventory's persistent character owner, never a reused player ID.
    if b.source and GetPlayerPed(b.source)~=0 and owner(b.source)==b.owner then return b.source end
    for _,id in ipairs(GetPlayers()) do
        local src=tonumber(id)
        if owner(src)==b.owner then return src end
    end
end
local function removeSide(r,side,recipient)
    local token=r.tow and wheelBindings[key(r,side)]
    local b=token and bindings[token]
    if b then
        if recipient then
            -- A full inventory leaves the strap fitted, so it can be retried.
            if not returnItem(token,recipient) then return false end
        else
            b.queued=true;saveLedger()
            local src=originalOwner(b)
            if src then returnItem(token,src) end
        end
        wheelBindings[key(r,side)]=nil
    end
    if r.tow and r.tow.straps then r.tow.straps[side]=nil end
    return true
end
local function cancel(src)
    local p=pending[src]
    if p then locks[p.key]=nil;pending[src]=nil end
end
function S.has(r) return r and r.tow and r.tow.straps and next(r.tow.straps)~=nil end
function S.clear(r)
    if not r or not r.tow then return end
    removeSide(r,'left');removeSide(r,'right')
    for src,p in pairs(pending) do if p.id==r.id then cancel(src) end end
end
function S.playerDropped(src)
    lastBegin[src]=nil
    cancel(src)
    if not context then return end
    local changed=false
    for _,r in pairs(context.rigs) do
        for _,side in ipairs({'left','right'}) do
            local token=r.tow and wheelBindings[key(r,side)]
            if token and bindings[token] and bindings[token].source==src then removeSide(r,side);changed=true end
        end
    end
    if changed then context.publish() end
end
local function chooseItem(src,index)
    if index then return slot(src,index) end
    for _,item in pairs(inventory('GetInventoryItems',src) or {}) do
        if item.name==C.Item then return item end
    end
end
function S.setup(value)
    context=value
    if not ledgerLoaded then
        ledgerLoaded=true
        local saved=GetResourceKvpString(ledgerKey)
        if saved then
            local ok,data=pcall(json.decode,saved)
            if ok and type(data)=='table' then
                for token,b in pairs(data) do
                    if type(b)=='table' and b.owner and type(b.metadata)=='table' then
                        b.queued=true;bindings[token]=b
                    end
                end
            end
        end
        saveLedger()
    end
    if not inventory('Items',C.Item) then print('[zseries] Missing inventory item '..C.Item..'. Merge the supplied ox_inventory item entry before using straps.') end
end
RegisterNetEvent('zseries:strapBegin',function(id,side,mode,index)
    local src=source
    local now=GetGameTimer()
    if now-(lastBegin[src] or -10000)<250 then return end
    lastBegin[src]=now
    if pending[src] then return tell(src,'Finish or cancel the current strap first.') end
    local r,reason=valid(src,id,side)
    if not r then return tell(src,reason) end
    if mode~='fit' and mode~='remove' then return end
    local fitted=r.tow.straps and r.tow.straps[side]
    if (mode=='fit' and fitted) or (mode=='remove' and not fitted) then return tell(src,mode=='fit' and 'This tyre is already strapped.' or 'There is no strap on this tyre.') end
    local lock=key(r,side)
    if locks[lock] then return tell(src,'Someone is already working on this strap.') end
    local item
    if mode=='fit' then
        if GetResourceState(C.Inventory)~='started' or not owner(src) then return tell(src,'Strap inventory service is unavailable.') end
        if index~=nil and (type(index)~='number' or index%1~=0) then return end
        item=chooseItem(src,index)
        if not item or item.name~=C.Item or item.count~=1 then return tell(src,'You need an unused wheel-lift strap.') end
    end
    sequence=sequence+1
    local token=('%d:%d:%d:%d'):format(os.time(),GetGameTimer(),src,sequence)
    local duration=mode=='fit' and C.AttachMs or C.RemoveMs
    pending[src]={token=token,id=id,side=side,mode=mode,slot=item and item.slot,version=r.tow.version,key=lock,start=GetGameTimer(),duration=duration,owner=owner(src)}
    locks[lock]=src
    TriggerClientEvent('zseries:strapProgress',src,token,mode,duration)
end)
RegisterNetEvent('zseries:strapComplete',function(token,success)
    local src=source;local p=pending[src]
    if not p or p.token~=token then return end
    if success~=true then return cancel(src) end
    if GetGameTimer()-p.start<p.duration-150 then cancel(src);return tell(src,'Strap action finished too early.') end
    local r,reason=valid(src,p.id,p.side,p.version)
    if not r then cancel(src);return tell(src,reason) end
    if p.mode=='fit' then
        local item=slot(src,p.slot)
        if not item or item.name~=C.Item or item.count~=1 or owner(src)~=p.owner  then
            cancel(src);return tell(src,'The strap is no longer available in that slot.')
        end
        local metadata=copy(item.metadata);metadata.zseries_token=nil
        if not inventory('RemoveItem',src,C.Item,1,item.metadata,p.slot,false,true) then
            cancel(src);return tell(src,'Could not take the strap from inventory. Nothing was fitted.')
        end
        bindings[p.token]={source=src,owner=p.owner,id=p.id,side=p.side,version=p.version,key=p.key,metadata=metadata}
        saveLedger()
        r.tow.straps=r.tow.straps or {}
        r.tow.straps[p.side]=true;wheelBindings[p.key]=p.token
        if r.tow.straps.left and r.tow.straps.right then tell(src,'Both tyres strapped. Ready to tow.') else tell(src,'Tyre strapped. Fit the other side before towing.') end
    else
        if not removeSide(r,p.side,src) then
            cancel(src);return tell(src,'Make room in your inventory. The strap is still fitted.')
        end
        tell(src,'Strap removed and returned to your inventory.')
    end
    cancel(src);context.publish()
end)
CreateThread(function()
    while true do
        Wait(1000)
        for src,p in pairs(pending) do if GetGameTimer()-p.start>p.duration+15000 then cancel(src) end end
        for token,b in pairs(bindings) do
            if b.queued then
                local src=originalOwner(b)
                if src then returnItem(token,src) end
            end
        end
    end
end)
AddEventHandler('onResourceStop',function(name)
    if name==GetCurrentResourceName() or name==C.Inventory then
        if context then for _,r in pairs(context.rigs) do S.clear(r) end end
        if name==C.Inventory and context then context.publish() end
    end
end)

RegisterCommand('zstrapcheck',function(src)
    if src~=0 and not IsPlayerAceAllowed(src,Config.Ace) then return end
    local message='Strap item '..C.Item..': '..(inventory('Items',C.Item) and 'registered' or 'MISSING')..' | fitted straps leave inventory; removal returns one item'
    if src==0 then print('[zseries] '..message) else tell(src,message) end
end,false)

-- Console-only setup helper; gameplay clients cannot mint inventory items.
RegisterCommand('zstrapgive',function(src,args)
    if src~=0 then return end
    local player=tonumber(args[1]);local count=args[2] and tonumber(args[2]) or 2
    if not count or not player or player%1~=0 or player<1 or GetPlayerPed(player)==0 or count%1~=0 or count<1 or count>10 then
        return print('[zseries] Usage: zstrapgive playerId count (1-10)')
    end
    local ok=inventory('AddItem',player,C.Item,count)
    print(ok and ('[zseries] Added %d wheel straps to player %d.'):format(count,player) or '[zseries] Could not give straps. Check item registration and inventory space.')
end,false)
