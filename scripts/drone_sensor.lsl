// ============================================================
// SL Recon Drone - Sensor / Obstacle Detection Module
// File: drone_sensor.lsl
// ============================================================
// Casts rays ahead of the drone to detect obstacles and
// broadcasts avoidance vectors to the movement module.
//
// Uses llCastRay in five directions (forward, ±left/right,
// ±up/down relative to forward) for wide field sensing.
// Falls back to llSensor for nearby phantom/moving objects.
// ============================================================

// ---- Shared command constants (same in every module) --------
integer CMD_START             = 100;
integer CMD_STOP              = 101;
integer CMD_OBSTACLE_DETECTED = 200;
integer CMD_OBSTACLE_CLEAR    = 201;
integer CMD_DEBUG             = 109;

// ---- Sensor configuration -----------------------------------
float   CFG_SCAN_INTERVAL  = 0.5;    // Seconds between ray scans
float   CFG_RAY_DISTANCE   = 6.0;    // Ray cast length in metres
float   CFG_SENSOR_RANGE   = 8.0;    // llSensor radius for nearby objects
float   CFG_SENSOR_ARC     = PI_BY_TWO; // Sensor arc (90 degrees forward cone)

// ---- Runtime state ------------------------------------------
integer gRunning         = FALSE;
integer gObstaclePresent = FALSE;
integer DEBUG            = FALSE;   // Toggled via /42 debug on

// ---- Debug helper -------------------------------------------
dbg(string msg)
{
    if (DEBUG) llOwnerSay("[Sensor|DBG] " + msg);
}

// ---- Cast rays and compute avoidance direction --------------
detectObstacles()
{
    vector pos = llGetPos();
    rotation rot = llGetRot();

    // Five probe directions in drone-local space -> world space
    vector fwd   = llVecNorm(<1.0,  0.0,  0.0> * rot);
    vector fwdL  = llVecNorm(<1.0,  0.5,  0.0> * rot);   // forward-left
    vector fwdR  = llVecNorm(<1.0, -0.5,  0.0> * rot);   // forward-right
    vector fwdU  = llVecNorm(<1.0,  0.0,  0.4> * rot);   // forward-up
    vector fwdD  = llVecNorm(<1.0,  0.0, -0.4> * rot);   // forward-down

    list dirs = [fwd, fwdL, fwdR, fwdU, fwdD];

    integer i;
    for (i = 0; i < 5; i++)
    {
        vector dir      = llList2Vector(dirs, i);
        vector endpoint = pos + dir * CFG_RAY_DISTANCE;

        // Cast ray – get hit position and surface normal
        list result = llCastRay(pos, endpoint,
                                [RC_DATA_FLAGS, RC_GET_NORMAL | RC_GET_ROOT_KEY]);

        integer hitCount = llList2Integer(result, -1);

        if (hitCount > 0)
        {
            // Each hit entry: [key, vector hitPos, vector hitNormal]
            vector hitPos    = llList2Vector(result, 1);
            vector hitNormal = llList2Vector(result, 2);

            // Ignore ground-plane hits: a nearly-upward normal whose hit point
            // is at or below the drone's own altitude is just terrain beneath
            // the flight path – not a real forward obstacle.
            if (hitNormal.z > 0.85 && hitPos.z <= pos.z + 0.5)
            {
                dbg("ray dir[" + (string)i + "] ground-plane hit ignored (z="
                    + (string)hitPos.z + "  droneZ=" + (string)pos.z + ")");
                jump next_ray;
            }

            // Avoidance direction: reflect off surface + climb component
            vector avoidDir = llVecNorm(hitNormal + <0.0, 0.0, 0.6>);

            if (!gObstaclePresent)
            {
                gObstaclePresent = TRUE;
                dbg("ray hit on dir[" + (string)i + "]  normal=" + (string)hitNormal
                    + "  avoidDir=" + (string)avoidDir);
                llMessageLinked(LINK_SET,
                                CMD_OBSTACLE_DETECTED,
                                (string)avoidDir,
                                NULL_KEY);
            }
            return;   // First hit is enough to trigger avoidance
        }
        @next_ray;
    }

    // No rays hit anything – clear the obstacle flag
    if (gObstaclePresent)
    {
        gObstaclePresent = FALSE;
        dbg("all rays clear – sending OBSTACLE_CLEAR");
        llMessageLinked(LINK_SET, CMD_OBSTACLE_CLEAR, "", NULL_KEY);
    }
}

// ---- Script body --------------------------------------------
default
{
    state_entry()
    {
        gRunning         = FALSE;
        gObstaclePresent = FALSE;
    }

    link_message(integer sender, integer num, string str, key id)
    {
        if (num == CMD_START)
        {
            gRunning         = TRUE;
            gObstaclePresent = FALSE;
            dbg("CMD_START: sensor scanning started, interval=" + (string)CFG_SCAN_INTERVAL
                + "  range=" + (string)CFG_SENSOR_RANGE);
            llSetTimerEvent(CFG_SCAN_INTERVAL);
            // Secondary sensor: detect nearby physical/moving objects
            llSensorRepeat("", NULL_KEY, ACTIVE | PASSIVE | SCRIPTED,
                           CFG_SENSOR_RANGE, CFG_SENSOR_ARC,
                           CFG_SCAN_INTERVAL * 2.0);
        }
        else if (num == CMD_STOP)
        {
            gRunning         = FALSE;
            gObstaclePresent = FALSE;
            dbg("CMD_STOP: sensor scanning halted.");
            llSetTimerEvent(0.0);
            llSensorRemove();
        }
        else if (num == CMD_DEBUG)
        {
            DEBUG = (str == "on");
        }
    }

    timer()
    {
        if (gRunning)
            detectObstacles();
    }

    // llSensor callback – used as secondary detection for
    // nearby objects that llCastRay might miss (e.g. fast movers)
    sensor(integer num_detected)
    {
        if (!gRunning) return;

        // If something is very close, trigger avoidance immediately
        vector obstaclePos = llDetectedPos(0);
        vector myPos       = llGetPos();
        vector awayDir     = llVecNorm(myPos - obstaclePos + <0.0, 0.0, 1.0>);

        if (!gObstaclePresent)
        {
            gObstaclePresent = TRUE;
            dbg("llSensor hit: obst=" + (string)obstaclePos + "  awayDir=" + (string)awayDir);
            llMessageLinked(LINK_SET,
                            CMD_OBSTACLE_DETECTED,
                            (string)awayDir,
                            NULL_KEY);
        }
    }

    no_sensor()
    {
        // Secondary sensor sees nothing – leave primary ray logic in control
    }

    on_rez(integer start_param)
    {
        llResetScript();
    }
}
