# SL Recon Drone

A modular, autonomous drone for **Second Life** written in LSL (Linden Scripting Language).  
The system is split into four independent scripts that communicate via `llMessageLinked`, making it easy to extend or replace individual modules.

---

## Features

| Module | File | Responsibility |
|--------|------|----------------|
| Main Controller | `drone_main.lsl` | Chat commands & inter-module routing |
| Movement | `drone_movement.lsl` | Autonomous flight, random wandering, obstacle avoidance |
| Sensor | `drone_sensor.lsl` | Obstacle / object detection via `llCastRay` |
| FPV Camera | `drone_camera.lsl` | First-person camera control (toggle on/off) |

---

## Quick Setup

1. **Create a prim** (any shape) in Second Life – this is the drone body.
2. Open the prim's **Contents** tab.
3. Drop all four `drone_*.lsl` script files into the prim contents.
4. The scripts will initialise automatically.  You should see in local chat:
   ```
   [Drone] Main controller ready.  Speak on /42 to control.
   ```
5. *(Optional)* Attach the prim to your avatar for camera control without needing a manual permission grant.

---

## Chat Commands

Speak on channel **`/42`** (default) to control the drone:

| Command | Description |
|---------|-------------|
| `/42 start` | Begin autonomous random flight |
| `/42 stop` | Stop all movement immediately |
| `/42 hover` | Hold current position |
| `/42 fpv` | Enable first-person (FPV) camera |
| `/42 fpv_off` | Disable FPV, return normal camera |
| `/42 speed <n>` | Set flight speed in m/s (e.g. `/42 speed 3.5`) |
| `/42 height <n>` | Set hover height above start in metres |
| `/42 status` | Show running / FPV state |
| `/42 help` | Show in-world command list |

> **Tip:** Change `CHAT_CHANNEL` in `drone_main.lsl` if channel 42 conflicts with other scripts.

---

## Configuration Reference

### `drone_movement.lsl`

| Variable | Default | Description |
|----------|---------|-------------|
| `CFG_SPEED` | `3.5` | Flight speed in m/s (normal SL walk speed) |
| `CFG_HOVER_HEIGHT` | `5.0` | Height above start Z when hovering (metres) |
| `CFG_WANDER_RADIUS` | `20.0` | Max horizontal distance from start (metres) |
| `CFG_UPDATE_INTERVAL` | `1.5` | Waypoint recalculation interval (seconds) |
| `CFG_WAYPOINT_REACH` | `2.0` | Distance to consider a waypoint "reached" (metres) |
| `CFG_AVOID_STEP` | `6.0` | Sideways step distance when avoiding obstacles (metres) |
| `CFG_MIN_FLIGHT_HEIGHT` | `2.5` | Minimum height above ground (metres) |
| `CFG_MAX_FLIGHT_HEIGHT` | `25.0` | Maximum height above start Z (metres) |

### `drone_sensor.lsl`

| Variable | Default | Description |
|----------|---------|-------------|
| `CFG_SCAN_INTERVAL` | `0.5` | Ray-cast scan frequency (seconds) |
| `CFG_RAY_DISTANCE` | `6.0` | Length of each detection ray (metres) |
| `CFG_SENSOR_RANGE` | `8.0` | Secondary `llSensor` radius (metres) |
| `CFG_SENSOR_ARC` | `PI_BY_TWO` | Secondary sensor forward arc (radians) |

### `drone_camera.lsl`

| Variable | Default | Description |
|----------|---------|-------------|
| `CFG_CAM_FORWARD_OFFSET` | `0.2` | Camera position ahead of drone centre (metres) |
| `CFG_CAM_UP_OFFSET` | `0.05` | Camera position above drone centre (metres) |
| `CFG_CAM_FOCUS_DIST` | `12.0` | Focus point distance ahead (metres) |
| `CFG_CAM_FOV` | `1.05` | Field of view in radians (~60°) |
| `CFG_CAM_LAG` | `0.05` | Camera smoothing lag (0 = instant) |
| `CFG_UPDATE_RATE` | `0.1` | Camera refresh rate (seconds) |

---

## Architecture & Inter-Module Communication

All modules broadcast and receive commands through **`llMessageLinked(LINK_SET, cmdInt, dataStr, NULL_KEY)`**.  Every script is in the same prim and listens for specific command integers:

```
100  CMD_START             → movement & sensor start
101  CMD_STOP              → movement & sensor stop
102  CMD_HOVER             → movement holds position
103  CMD_FPV_ON            → camera enables FPV
104  CMD_FPV_OFF           → camera releases control
105  CMD_STATUS            → informational broadcast
106  CMD_SET_SPEED         → movement tunes CFG_SPEED
107  CMD_SET_HEIGHT        → movement tunes CFG_HOVER_HEIGHT
200  CMD_OBSTACLE_DETECTED → sensor → movement (avoidance vector in str)
201  CMD_OBSTACLE_CLEAR    → sensor → movement (path clear)
```

### Adding a New Module

1. Create a new `drone_<module>.lsl` file.
2. Copy the shared command constants block at the top.
3. Add a `link_message` handler for any commands your module responds to.
4. Add new command integers (≥ 300) for your module's own messages.
5. Drop the script into the drone prim – no other scripts need to change.

---

## FPV Camera Notes

- If the drone is **attached** to your avatar, camera permissions are requested automatically on attachment.
- If the drone is **rezzed** in-world, click the drone once to trigger the permission request, then press **Accept**.  After that, `/42 fpv` will work without clicking again.
- Use `/42 fpv_off` or simply detach the object to restore your normal camera.

---

## Requirements

- A Second Life or OpenSim region with physics and `llCastRay` support.
- Permissions: `PERMISSION_CONTROL_CAMERA` (for FPV).
- The prim must have **Physics** enabled (`STATUS_PHYSICS = TRUE`) – the movement script sets this automatically.
