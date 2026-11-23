-- Pure strap routing. Points and axes may be in vehicle space or world space.
StrapMath = {}
local S, M = StrapMath, TowMath
function S.dot(a,b) return a.x*b.x+a.y*b.y+a.z*b.z end
function S.scale(a,n) return M.v(a.x*n,a.y*n,a.z*n) end
function S.cross(a,b) return M.v(a.y*b.z-a.z*b.y,a.z*b.x-a.x*b.z,a.x*b.y-a.y*b.x) end
function S.unit(a)
    local n=M.len(a)
    if n<1e-7 then return M.v(0,0,1) end
    return S.scale(a,1/n)
end
function S.lerp(a,b,t) return M.add(a,S.scale(M.sub(b,a),t)) end
function S.route(wheel,front,rear,forward,up,right,radius,width,side)
    radius=M.clamp(radius,.18,.75)+.009
    width=M.clamp(width,.14,.60)
    local points={front};local normals={S.scale(right,-side)}
    local count=Config.Straps.ArcPoints or 12
    for i=0,count do
        local t=i/count;local a=math.rad(55+70*t)
        local radial=M.add(S.scale(forward,math.cos(a)),S.scale(up,math.sin(a)))
        local across=side*(t-.5)*(width+.024)
        points[#points+1]=M.add(wheel,M.add(S.scale(radial,radius),S.scale(right,across)))
        normals[#normals+1]=S.unit(M.add(S.scale(radial,.35+math.sin(math.pi*t)),S.scale(right,side*(2*t-1))))
    end
    local clearance=width*.5+.02-side*S.dot(M.sub(rear,wheel),right)
    local ratchet=M.add(M.add(rear,S.scale(right,side*math.max(0,clearance))),S.scale(up,.085))
    points[#points+1]=ratchet;normals[#normals+1]=S.scale(right,side)
    local segments={}
    local function ribbon(path,surfaceNormals)
        local edges={};local previous
        for i,p in ipairs(path) do
            local tangent=S.unit(M.sub(path[math.min(i+1,#path)],path[math.max(1,i-1)]))
            local across=S.unit(S.cross(surfaceNormals[i],tangent))
            if previous and S.dot(across,previous)<0 then across=S.scale(across,-1) end
            previous=across;across=S.scale(across,.025)
            edges[i]={left=M.sub(p,across),right=M.add(p,across)}
        end
        for i=1,#path-1 do
            segments[#segments+1]={a=path[i],b=path[i+1],normal=surfaceNormals[i],
                leftA=edges[i].left,rightA=edges[i].right,leftB=edges[i+1].left,rightB=edges[i+1].right}
        end
    end
    ribbon(points,normals)
    ribbon({rear,ratchet},{forward,forward})
    -- Short loose end below the ratchet.
    local tail={ratchet,M.add(ratchet,S.scale(up,-.13)),M.add(ratchet,M.add(S.scale(up,-.17),S.scale(right,side*.045))),M.add(ratchet,M.add(S.scale(up,-.08),S.scale(right,side*.075)))}
    ribbon(tail,{forward,forward,forward,forward})
    return {segments=segments,front=front,rear=rear,ratchet=ratchet,ratchetDirection=S.unit(M.sub(points[#points-1],ratchet)),sideNormal=S.scale(right,side)}
end
