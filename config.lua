Config = {}
Config.Geometry = json.decode(LoadResourceFile(GetCurrentResourceName(), 'geometry.json'))
Config.Ace = 'zseries.use'
Config.ControlJob = 'wreckamended'
Config.LeafSprings = {
    Item = 'zseries_leaf_springs',
    Distance = 4.0,
    Force = 1.45,
    Compression = 1.25,
    Rebound = 1.15,
}
Config.InteractDistance = 6.0
Config.StreamDistance = 160.0
Config.MaxOperateSpeed = 1.5 -- used only when OperateWhileMoving is false
Config.OperateWhileMoving = true
Config.AutoHook = true -- close on an axle, or press UP while low to grip and lift
Config.AutoPickupHeight = true -- seat custom mounts automatically at the lowered stop
Config.AutoPickupHeightTolerance = .025 -- align the seat before grip rather than warping tyres through the road
Config.MaxPickupAdjustment = .75 -- metres; avoid stretching an extreme mount placement
Config.AutoReleaseOnOpen = true -- lower the boom, then open to release
Config.MaxCaptureDistance = 0.30 -- axle midpoint to cradle, metres
Config.MaxCaptureHeight = 0.10 -- axle must already be at tyre support height
Config.GripCloseMs = 400 -- close arms before UP starts lifting
Config.MaxCaptureAngle = 18.0 -- degrees relative to truck heading
Config.MaxTargetMass = 3500.0 -- client-side convenience check, not server security
Config.MaxTargetLength = 6.0
Config.Step = 0.08
Config.TransitionMs = 350
-- Actual towing uses a free-rotation physics joint, not a fixed vehicle pitch.
Config.TowBreakForce = 1000000.0
Config.TowJointRefreshMs = 0 -- follow hydraulic motion each rendered frame; idle joints stay intact
Config.TowAnchorEpsilon = 0.0001
Config.TowMaintenanceMs = 200
Config.DefaultTyreRadius = 0.30
Config.CradleRollerRadius = 0.035
Config.StowLift = 0.5 -- raised level carriage storage pose
Config.Debug = false
-- Example ONLY. Calibrate in-game or replace with your actual truck model.
-- Offsets are relative to vehicle ROOT, +X right, +Y forward, +Z up.
-- Use /zboom mount x y z for a temporary per-rig calibration.
Config.Profiles = {
    bison = { mount = { x=0.0, y=-1.65, z=0.15 }, calibrated=false },
    nathanownboss = { mount = { x=0.0, y=-2.35, z=-0.14 }, minLift=0.0, maxLift=0.65, loadedMaxLift=0.90, pickupPitch=2.114304693, pickupBlendLift=0.15, releaseLift=0.02, calibrated=false },
    -- Fitted against supplied body/chassis geometry; verify suspension clearance in game.
    nathan22nali = { mount = { x=0.0, y=-2.25, z=-0.82 }, pump={x=0.0,y=-0.05,z=1.17}, minLift=0.0, maxLift=0.50, stowLift=0.5, releaseLift=0.02, calibrated=false }
}
-- Other automobiles can be fitted through the placement preview. The Ford
-- retains its exact configured one-step installation and hydraulic profile.
Config.Placement = {AllowUnlisted=false} -- skip cars/non-trucks outside fitted profiles
Config.Profiles.zseries_custom = {mount={x=0,y=-2.35,z=-.14},minLift=0,maxLift=.65,loadedMaxLift=.90,releaseLift=.02}
Config.Parts = {
    'frame', 'main', 'mid', 'tip', 'crossbar',
    'shoulder_l', 'shoulder_r', 'finger_l', 'finger_r',
    'lift_barrel', 'lift_rod', 'extend_barrel', 'extend_rod',
    'extend2_barrel', 'extend2_rod',
    'left_barrel', 'left_rod', 'right_barrel', 'right_rod', 'pump'
}
Config.ModelPrefix = 'zs_'

-- Optional per-model addon calibration. Root coordinates in GTA metres.
-- Standard wheel bones are used unless front/rear offsets are supplied.
-- Handling mass is frequently custom on addons; limits here only affect pickup.
Config.TargetProfiles = {
    -- Supplied addon: handling fMass=6400, inspected root-space length about 6.43 m.
    -- Standard wheel bones exist; keep live wheel positions/suspension offsets.
    nathan22nali = {maxMass=6500, maxLength=7.0},
    -- spawnname = {maxMass=5000, maxLength=6.5, radius=0.32,
    --     front={x=0,y=1.4,z=-0.2}, rear={x=0,y=-1.4,z=-0.2}},
}




-- One reusable ox_inventory item secures one lifted tyre. Two straps per axle.
Config.Straps = {Item='zseries_towstrap', Inventory='ox_inventory', AttachMs=4500, RemoveMs=2500,
    Distance=2.2, MaxSpeed=0.5, VisualDistance=45.0, ArcPoints=12, BlockRelease=true}
