-- Pure local-space math, also exercised outside FiveM in tests.
TowMath = {}
local M, G = TowMath, Config.Geometry
function M.clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end
function M.finite(v) return type(v)=='number' and v==v and math.abs(v)<1e6 end
function M.v(x,y,z) return {x=x,y=y,z=z} end
function M.add(a,b) return M.v(a.x+b.x,a.y+b.y,a.z+b.z) end
function M.sub(a,b) return M.v(a.x-b.x,a.y-b.y,a.z-b.z) end
function M.len(a) return math.sqrt(a.x*a.x+a.y*a.y+a.z*a.z) end
function M.rx(p,d)
    local c,s=math.cos(math.rad(d)),math.sin(math.rad(d))
    return M.v(p.x,c*p.y-s*p.z,s*p.y+c*p.z)
end
function M.rz(p,d)
    local c,s=math.cos(math.rad(d)),math.sin(math.rad(d))
    return M.v(c*p.x-s*p.y,s*p.x+c*p.y,p.z)
end
-- Rotation order 2: Rz * Rx * Ry. Keep the full relative basis so rear
-- pickup and changes of road pitch do not reverse or detach the head.
function M.rotate(p,r)
    if not r then return M.v(p.x,p.y,p.z) end
    local c,s=math.cos(math.rad(r.ry or 0)),math.sin(math.rad(r.ry or 0))
    return M.rz(M.rx(M.v(c*p.x+s*p.z,p.y,-s*p.x+c*p.z),r.rx or 0),r.rz or 0)
end
function M.fromBasis(right,forward,up)
    local sx=M.clamp(forward.z,-1,1)
    local x=math.asin(sx)
    local y,z
    if math.abs(sx)<.999999 then
        y=math.atan(-right.z,up.z);z=math.atan(-forward.x,forward.y)
    else y=0;z=math.atan(right.y,right.x) end
    return {rx=math.deg(x),ry=math.deg(y),rz=math.deg(z)}
end
function M.composeRotation(a,b)
    return M.fromBasis(M.rotate(M.rotate(M.v(1,0,0),b),a),
        M.rotate(M.rotate(M.v(0,1,0),b),a),M.rotate(M.rotate(M.v(0,0,1),b),a))
end
local function dot(a,b) return a.x*b.x+a.y*b.y+a.z*b.z end
function M.relativeHead(cf,cr,cu,pf,pr,pu,pickupYaw)
    local function localVector(p) return M.v(dot(pr,p),dot(pf,p),dot(pu,p)) end
    local right,forward,up=localVector(cr),localVector(cf),localVector(cu)
    local c,s=math.cos(math.rad(pickupYaw or 0)),math.sin(math.rad(pickupYaw or 0))
    local function combine(a,b,ca,cb) return M.v(a.x*ca+b.x*cb,a.y*ca+b.y*cb,a.z*ca+b.z*cb) end
    return M.fromBasis(combine(right,forward,c,-s),combine(right,forward,s,c),up)
end
function M.pose(p,rx,rz) return {p=p,rx=rx or 0,ry=0,rz=rz or 0} end
function M.pickupOffset(state)
    if state.profile=='nathanownboss' then return 0 end
    -- Keep a constant calibrated zero through the whole hydraulic stroke.
    -- Fading a positive correction with lift can make UP lower the car.
    -- Explicit STOW resets this offset after the car has been released.
    return state.pickupDrop or 0
end
function M.canAutoPickup(state)
    local p=Config.Profiles[state.profile] or {}
    return Config.AutoPickupHeight and state.profile~='nathanownboss' and not state.tow and state.lift<=(p.minLift or 0)+.025
end
local function arr(a) return M.v(a[1],a[2],a[3]) end
local function cylinder(out,name,a,b,body,rod)
    local d=M.sub(b,a)
    local length=M.len(d)
    -- Cylinders are modelled along local +Z. Euler Rz * Rx maps +Z to d.
    local rx=math.deg(math.acos(M.clamp(d.z/length,-1,1)))
    local rz=math.deg(math.atan(d.x,-d.y))
    out[name..'_barrel']=M.pose(a,rx,rz)
    local start=M.add(a,M.v(d.x*(length-rod)/length,d.y*(length-rod)/length,d.z*(length-rod)/length))
    out[name..'_rod']=M.pose(start,rx,rz)
end
function M.solve(state)
    local level=M.clamp(state.lift,0,1)
    local profile=Config.Profiles and Config.Profiles[state.profile]
    local height=G.lift_low+(profile and profile.liftTravel or G.lift_travel)*level+M.pickupOffset(state)
    -- The Ford needs a shallow ground approach below its former .15 stop.
    -- The approach angle is gone at .15; every raised pose stays level.
    local rx=profile and (profile.pickupPitch or 0)*M.clamp(1-level/(profile.pickupBlendLift or .15),0,1) or 0
    local ext=M.clamp(state.extend,0,1)
    local opened=1-M.clamp(state.close,0,1)
    local main=M.v(0,0,height)
    local mid=M.add(main,M.rx(M.v(0,-G.mid_base-G.stage_travel*ext,0),rx))
    local tip=M.add(mid,M.rx(M.v(0,-G.tip_base-G.stage_travel*ext,0),rx))
    local cross=M.add(M.add(tip,M.rx(M.v(0,-G.tip_length,0),rx)),M.v(0,-G.head_pin_y,0))
    local out={frame=M.pose(M.v(0,0,0)),main=M.pose(main,rx),mid=M.pose(mid,rx),
        tip=M.pose(tip,rx),crossbar=M.pose(cross),pump=M.pose(M.v(0.4,0.5,0.25))}
    cylinder(out,'lift',arr(G.lift_base),M.add(main,M.rx(arr(G.lift_eye),rx)),profile and profile.liftBarrelLength or G.barrel_length,profile and profile.liftRodLength or G.rod_length)
    cylinder(out,'extend',M.add(main,M.rx(M.v(-.035,G.extend_base_y,G.extend_z),rx)),M.add(mid,M.rx(M.v(-.035,G.extend_eye_y,G.extend_z),rx)),G.extend_barrel_length,G.extend_rod_length)
    cylinder(out,'extend2',M.add(mid,M.rx(M.v(.035,G.extend_base_y,G.extend_z),rx)),M.add(tip,M.rx(M.v(.035,G.extend_eye_y,G.extend_z),rx)),G.extend_barrel_length,G.extend_rod_length)
    for _,side in ipairs({{'l',-1,'left'},{'r',1,'right'}}) do
        local suffix,s,name=side[1],side[2],side[3]
        local root=M.add(cross,M.v(s*G.shoulder_x,0,0))
        local fold=M.clamp(state.fold or 0,0,1)
        local angle=s*(opened*G.arm_open_angle*(1-fold)+G.arm_fold_angle*fold)
        local elbow=M.add(root,M.rz(M.v(s*G.elbow_x,G.elbow_y,0),angle))
        out['shoulder_'..suffix]=M.pose(root,0,angle)
        -- End bars counter-rotate at the elbow and remain transverse in both
        -- reference endpoints; unloaded storage is distinct from tire gripping.
        out['finger_'..suffix]=M.pose(elbow,0,0)
        local a=M.add(cross,M.v(s*0.14,0.08,0.12))
        local b=M.add(root,M.rz(M.v(s*-0.07,-0.12,0.12),angle))
        cylinder(out,name,a,b,G.arm_barrel_length,G.arm_rod_length)
    end
    out.capture=M.add(cross,arr(G.capture))
    local pin=M.add(cross,M.v(0,G.head_pin_y,0))
    out.kingpin=pin
    if state.headRotation then
        for _,name in ipairs({'crossbar','shoulder_l','shoulder_r','finger_l','finger_r','left_barrel','left_rod','right_barrel','right_rod'}) do
            local p=out[name]
            local rot=M.composeRotation(state.headRotation,p)
            out[name]={p=M.add(pin,M.rotate(M.sub(p.p,pin),state.headRotation)),rx=rot.rx,ry=rot.ry,rz=rot.rz}
        end
        out.capture=M.add(pin,M.rotate(M.sub(out.capture,pin),state.headRotation))
    end
    return out
end
function M.mountPoint(state,p) return M.add(state.mount,p) end
-- Tyres stop the hydraulic arms before the unloaded flat-fold end stop.
-- Estimate contact in the wheel's Y/Z cross-section using its collider radius.
function M.gripGeometry(radius)
    radius=M.clamp(radius or Config.DefaultTyreRadius or .30,.18,.75)
    local seat=arr(G.capture)
    -- Inner tread and end-bar top edges, in the tyre's Y/Z section.
    -- Seat above both edges; the old roller-centre approximation intersected them.
    local edgeZ,frontY,rearInset=.04,-.12,.043
    local function above(y)
        local dy=seat.y-y
        return edgeZ+math.sqrt(math.max(0,radius*radius-dy*dy))
    end
    seat.z=math.max(above(frontY),above(G.elbow_y+rearInset))
    local reach=radius
    local function distance(fold)
        local elbow=M.rz(M.v(G.elbow_x,G.elbow_y,0),G.arm_fold_angle*fold)
        return math.sqrt((elbow.y+rearInset-seat.y)^2+(edgeZ-seat.z)^2)
    end
    if distance(0)<=reach+1e-7 then return seat,0 end
    local previous=0
    for i=1,50 do
        local nextFold=i/50
        if distance(nextFold)<=reach then
            local lo,hi=previous,nextFold
            for _=1,20 do
                local mid=(lo+hi)/2
                if distance(mid)>reach then lo=mid else hi=mid end
            end
            return seat,lo
        end
        previous=nextFold
    end
    return seat,1
end
function M.pickupAnchor(state,radius)
    local seat=M.gripGeometry(radius)
    return M.mountPoint(state,M.add(M.solve(state).crossbar.p,M.rotate(seat,state.headRotation)))
end
function M.towAnchor(state)
    return M.pickupAnchor(state,state.tow and state.tow.radius or nil)
end
-- Express the level cradle-to-axle vector in the target's body coordinates.
-- During hydraulic movement, the existing owner binding uses this seat offset
-- so levelling the head does not leave the tyres inside or below the bars.
function M.inverseRotate(p,r)
    local right=M.rotate(M.v(1,0,0),r)
    local forward=M.rotate(M.v(0,1,0),r)
    local up=M.rotate(M.v(0,0,1),r)
    return M.v(dot(p,right),dot(p,forward),dot(p,up))
end
function M.towJoint(state)
    local seat=M.gripGeometry(state.tow.radius)
    local fromPin=M.sub(seat,M.v(0,G.head_pin_y,0))
    local localSeat
    if state.targetRotation then
        localSeat=M.inverseRotate(M.rotate(fromPin,state.headRotation),state.targetRotation)
    else
        localSeat=M.rz(fromPin,-state.tow.yaw)
    end
    local child=M.sub(state.tow.axle,localSeat)
    return M.mountPoint(state,M.solve(state).kingpin),child
end
function M.cargo(state)
    local anchor=M.mountPoint(state,M.solve(state).capture)
    local pitch=(Config.TowPitch or 0)*M.clamp((state.lift-0.15)/0.85,0,1)*(state.tow.yaw==180 and -1 or 1)
    local rotated=M.rz(M.rx(state.tow.axle,pitch),state.tow.yaw)
    return M.sub(anchor,rotated),state.tow.yaw,pitch
end

