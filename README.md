# Z-Series Wheel Lift

![Z-Series Views](https://hits.dwyl.com/Boom1053/zseries.svg)

A FiveM wheel-lift resource with animated Z-Series equipment, vehicle pickup and
release, optional reusable wheel straps, and optional mechanic-installed leaf
springs. Includes example carrier fits and support for calibrating additional
vehicles.

## Features

- Animated boom controls, remote controls, and synced wheel-lift visuals.
- Automatic axle alignment, pickup-height adjustment, and vehicle attachment.
- Placement preview for fitting the lift to unlisted carrier vehicles.
- Optional reusable straps for the lifted wheels.
- Optional leaf-spring handling upgrade for fitted carriers.
- ESX, QBCore, QBX, and ND_CORE job checks, plus ACE permissions.

## Requirements

- FiveM server with OneSync enabled.
- `ox_lib`.
- `ox_inventory` for the supplied strap and leaf-spring item flows.
- ESX, QBCore, QBX, or ND_CORE only if you want framework job-based
  permissions. ACE permissions can be used without a framework.

`ox_lib` and `ox_inventory` are required by the resource manifest. ESX,
QBCore, QBX, and ND_CORE are optional; they provide job lookup, not inventory
implementations. The supplied item-use exports are designed for ox_inventory.

## Installation

1. Download or clone this repository into your server resources folder, keeping
   the complete directory structure. Name the folder `zseries` if you want to
   use the item examples below without changing their export names.
2. Make sure the resource includes `fxmanifest.lua`, the Lua files, both JSON
   files, and the complete `stream/` folder. Do not omit the `.ydr` models or
   `.ytyp` archetype files.
3. Install and configure `ox_lib` and `ox_inventory` using their own
   installation instructions.
4. Register the two item definitions shown under
   [Inventory items](#inventory-items) in your ox_inventory item registry.
5. Add resources to `server.cfg` in dependency order:

   ```cfg
   ensure ox_lib
   ensure ox_inventory
   ensure zseries
   ```

6. Enable OneSync and grant the desired permissions (see
   [Permissions and frameworks](#permissions-and-frameworks)).
7. Restart the server or start the resources in the order above. Check the
   server console for missing item or resource errors.

## Inventory items

Add these entries to your ox_inventory item definitions (commonly
`ox_inventory/data/items.lua`). Set `consume = 0`: Z-Series validates and
removes the item server-side when it is actually installed or fitted.

```lua
['zseries_towstrap'] = {
    label = 'Z-Series Tow Strap',
    weight = 1000,
    stack = true,
    close = true,
    consume = 0,
    client = { export = 'zseries.useTowStrap' },
},

['zseries_leaf_springs'] = {
    label = 'Leaf Springs Kit',
    weight = 5000,
    stack = true,
    close = true,
    consume = 0,
    client = { export = 'zseries.useLeafSprings' },
},
```

Use the item-definition format supported by your installed ox_inventory
version. The weights above are examples; adjust them to your server economy.
If the resource folder has a different name, change the `zseries.` prefix in
both exports to match that folder name.

Straps are consumed while fitted and returned when removed. A pair of straps is
needed to secure both lifted tyres for towing. Leaf-spring kits are consumed
when successfully installed.

## Permissions and frameworks

Edit these values near the top of `config.lua`:

```lua
Config.Ace = 'zseries.use'
Config.ControlJob = 'wreckamended'
Config.Framework = 'auto' -- auto, esx, qbcore, qbx, or ndcore
Config.MechanicJob = 'mechanic'
Config.MechanicJobType = 'mechanic'
```

- `Config.Framework = 'auto'` checks started ND_CORE, QBX, QBCore, and ESX
  resources. Set `ndcore`, `esx`, `qbcore`, or `qbx` to select one explicitly.
- `Config.ControlJob` is the job allowed to operate and fit the boom.
- `Config.MechanicJob` / `Config.MechanicJobType` control leaf-spring
  installation.
- ACE permission can be granted in `server.cfg`, for example:

  ```cfg
  add_ace group.admin zseries.use allow
  ```

ACE access bypasses the boom-operation job check. Leaf-spring installation
still requires the configured mechanic job.

## Vehicle setup

Boom placement is enabled for unlisted carrier models by default. Stand beside
a parked vehicle and use `/zboom place` to open the placement preview. Use the
preview controls to position the equipment, then press Enter to fit and save
the mount position for that vehicle model. Saved positions are stored in server
resource KVP; the `nathanownboss` profile deliberately preserves its configured
default instead of replacing it with a saved position. Use `/zboom install`
for the standard install flow; models without a fitted profile open the
placement preview automatically.

The included `bison`, `nathanownboss`, and `nathan22nali` profiles are examples
and model-specific fits. Adjust `Config.Profiles` in `config.lua` or
`truck_profiles.json` for server-specific carriers. Root offsets use metres:
`x` is right, `y` is forward, and `z` is up. `/zboom mount x y z` changes the
current rig's mount offset directly.

Fitting the boom to any vehicle model does not mean every vehicle can be towed.
The towed vehicle must be empty and networked, be an automobile with usable
wheel bones, and fit the pickup limits. Motorcycles, bicycles, boats, aircraft,
trains, and other non-automobile vehicle types are not supported as towed
vehicles. For custom addon vehicles with unusual wheel bones, mass, length, or
tyre size, configure `Config.TargetProfiles` in `config.lua`.

## Commands and controls

### Boom commands

Run `/zboom` followed by one of these actions:

| Command | Action |
| --- | --- |
| `install` | Fit a boom or start placement for an unprofiled model. |
| `place` | Calibrate or reposition the boom mount. |
| `up`, `down` | Raise or lower the lift; Up can automatically grip an aligned axle. |
| `in`, `out` | Retract or extend the boom. |
| `open`, `close` | Open or close the arms. |
| `fold`, `deploy` | Fold or deploy the arms. |
| `stow` | Return the folded lift to its stowed position. |
| `hook [auto\|front\|rear]` | Attach a nearby vehicle axle to the lift. |
| `release` | Release the towed vehicle after lowering it. |
| `remove` | Remove the fitted boom if it is not towing a vehicle. |
| `status` | Show rig position and hydraulic state. |
| `inspect` | Report the nearest axle's pickup alignment. |
| `towstatus` | Show attachment and wheel information in the F8 console. |
| `mount x y z` | Set the current rig's mount offset. |
| `debug` | Toggle debug markers. |

Placement preview: arrow keys move the mount, Page Up/Down changes height,
Shift moves faster, Ctrl moves in smaller steps, R resets the position, Tab
toggles the preview pose, Enter saves, and Backspace cancels.

### Remote controls

Use `/zremote` or press F7 to toggle the remote. Default bindings are:

| Key | Action |
| --- | --- |
| Numpad 8 / 2 | Up / down |
| Numpad 4 / 6 | In / out |
| Numpad 7 / 9 | Open / close |

These bindings can be changed in FiveM's key-bindings menu.

### Straps

- Use the `zseries_towstrap` inventory item beside a lifted tyre, or run
  `/zstrap` to fit a strap and `/zstrap remove` to remove one.
- `/zstrapcheck` reports whether the configured ox_inventory item exists.
- Server console only: `zstrapgive <playerId> [count]` gives test straps (1–10).

## Configuration

`config.lua` contains permissions, framework selection, vehicle placement,
target pickup limits, strap behavior, and leaf-spring tuning. Common options:

- `Config.Placement.AllowUnlisted`: allow boom fitting on unlisted carrier
  models (enabled by default).
- `Config.Profiles`: per-carrier lift geometry and limits.
- `Config.TargetProfiles`: custom axle offsets or pickup limits for addon cars.
- `Config.MaxTargetMass` / `Config.MaxTargetLength`: default target guidance.
- `Config.Straps`: item name, inventory resource, and strap interaction settings.
- `Config.LeafSprings`: item name and handling multipliers.

Back up `config.lua` and server resource KVP before replacing files during an
update. Model-mount offsets are stored on the server; currently fitted rigs are
runtime state and should be treated as non-persistent across a resource/server
restart.

## Troubleshooting

- **No permission:** grant `zseries.use` or set the correct framework and
  `Config.ControlJob`. Confirm the relevant framework resource is started.
- **Item does nothing:** check that the item name matches `config.lua`, its
  client export points to the correct resource name, and `ox_inventory`
  started before `zseries`.
- **Missing strap item:** run `/zstrapcheck` and verify the item is registered
  in ox_inventory.
- **Boom models missing:** verify all `.ydr` and `.ytyp` files are present in
  `stream/` and that the resource was not partially copied.
- **Vehicle cannot be picked up:** confirm it is empty, near and aligned with
  the cradle, and has wheel bones supported by the game. Configure
  `Config.TargetProfiles` for unusual addon vehicles.
- **Poor boom fit:** use `/zboom place` on the carrier and save a better mount
  position. Test the fit with the boom both stowed and deployed.

## Credits and usage

Showcase links:

- [Original Z-Series video](https://www.tiktok.com/@boomie1053/video/7704222620371258638)
- [Z-Series update video](https://www.tiktok.com/@boomie1053/video/7707807446625979661)

No license file is included in this repository. Contact the author for
permission before redistributing, reselling, or publishing modified versions.
