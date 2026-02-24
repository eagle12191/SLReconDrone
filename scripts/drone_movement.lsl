// ============================================================
// SL Recon Drone - Movement Module
// File: drone_movement.lsl
// ============================================================
// Handles autonomous flight:
//   - Random wandering within a configurable radius
//   - Smooth movement toward waypoints via llMoveToTarget
//   - Obstacle avoidance (reacts to sensor module messages)
//   - Configurable speed, hover height, and wander radius
//
// Requires STATUS_PHYSICS = TRUE on the drone prim.
// Uses llSetBuoyancy(1.0) to counteract gravity.
// ============================================================

// ---- Shared command constants (same in every module) --------
integer CMD_START             = 100;
integer CMD_STOP              = 101;
integer CMD_HOVER             = 102;
integer CMD_FPV_ON            = 103;   // (unused here - forwarded by main)
integer CMD_FPV_OFF           = 104;   // (unused here)
integer CMD_STATUS            = 105;
integer CMD_SET_SPEED         = 106;
integer CMD_SET_HEIGHT        = 107;
integer CMD_OBSTACLE_DETECTED = 200;
integer CMD_OBSTACLE_CLEAR    = 201;
integer CMD_RECALL            = 108;
integer CMD_DEBUG             = 109;

// ---- Movement configuration (owner-tunable via commands) ----
float CFG_SPEED            = 3.5;    // Normal SL walking speed (m/s)
float CFG_HOVER_HEIGHT     = 5.0;    // Hover height above start Z (metres)
float CFG_WANDER_RADIUS    = 20.0;   // Max lateral wander from start XY (metres)
float CFG_UPDATE_INTERVAL  = 1.5;    // Seconds between waypoint recalculations
float CFG_WAYPOINT_REACH   = 2.0;    // Distance at which waypoint is "reached" (metres)
float CFG_AVOID_STEP       = 6.0;    // How far to step sideways when avoiding (metres)
float CFG_MIN_FLIGHT_HEIGHT = 2.5;   // Minimum AGL flight height (metres)
float CFG_MAX_FLIGHT_HEIGHT = 25.0;  // Maximum flight height above start Z (metres)

// ---- Runtime state ------------------------------------------
integer gRunning   = FALSE;
integer gHovering  = FALSE;
integer gAvoiding  = FALSE;
integer gRecalling = FALSE;
integer DEBUG      = FALSE;   // Toggled via /42 debug on

vector  gStartPos  = ZERO_VECTOR;
vector  gTargetPos = ZERO_VECTOR;
vector  gAvoidDir  = ZERO_VECTOR;

// ---- Generate a random wander waypoint ----------------------
vector randomWaypoint()
{
    float angle  = llFrand(TWO_PI);
    float radius = CFG_WANDER_RADIUS;
    if (radius == 0.0) radius = 256.0;   // 0 = unlimited
    float dist   = 3.0 + llFrand(radius - 3.0);              // at least 3 m away

    // Height: vary around CFG_HOVER_HEIGHT with some randomness
    float zOffset = CFG_HOVER_HEIGHT + llFrand(6.0) - 3.0;
    if (zOffset < CFG_MIN_FLIGHT_HEIGHT) zOffset = CFG_MIN_FLIGHT_HEIGHT;
    if (zOffset > CFG_MAX_FLIGHT_HEIGHT) zOffset = CFG_MAX_FLIGHT_HEIGHT;

    vector wp = <gStartPos.x + dist * llCos(angle),
                 gStartPos.y + dist * llSin(angle),
                 gStartPos.z + zOffset>;
    if (DEBUG) llOwnerSay("[Move|DBG] randomWaypoint -> " + (string)wp
                          + "  dist=" + (string)dist
                          + "  zOff=" + (string)zOffset);
    return wp;
}

// ---- Move smoothly toward a target --------------------------
moveTo(vector target)
{
    vector dir  = llVecNorm(target - llGetPos());
    // Face the direction of travel only when there's a meaningful horizontal
    // component - passing a zero vector to llRotBetween is undefined in LSL
    // and will break the movement script (e.g. pure vertical avoidance).
    vector   hDir = <dir.x, dir.y, 0.0>;
    rotation tRot;   // declared outside the if-block (required by SL Mono compiler)
    if (llVecMag(hDir) > 0.01)
    {
        tRot = llRotBetween(<1.0, 0.0, 0.0>, llVecNorm(hDir));
        llSetRot(tRot);
    }
    // Derive tau from speed so the drone moves at roughly CFG_SPEED m/s
    float dist = llVecMag(target - llGetPos());
    float tau  = dist / CFG_SPEED;
    if (tau < 0.1) tau = 0.1;   // Safety floor to avoid division-by-zero artefacts
    if (DEBUG) llOwnerSay("[Move|DBG] moveTo " + (string)target
                          + "  dist=" + (string)dist
                          + "  tau=" + (string)tau
                          + "  speed=" + (string)CFG_SPEED);
    llMoveToTarget(target, tau);
}

// ---- Hold position ------------------------------------------
hoverInPlace()
{
    llMoveToTarget(llGetPos(), 0.4);   // 0.4 s tau for stable hover
}

// ---- Stop all movement --------------------------------------
stopMoving()
{
    llStopMoveToTarget();
    llSetVelocity(ZERO_VECTOR, FALSE);
    llSetAngularVelocity(ZERO_VECTOR, FALSE);
}

// ---- Script body --------------------------------------------
default
{
    state_entry()
    {
        // Enable physics and neutralise gravity
        llSetStatus(STATUS_PHYSICS, TRUE);
        llSetStatus(STATUS_ROTATE_X, FALSE);   // Keep drone level
        llSetStatus(STATUS_ROTATE_Y, FALSE);
        llSetBuoyancy(1.0);                    // Neutrally buoyant - no sinking

        gStartPos  = llGetPos();
        gTargetPos = gStartPos;
        llOwnerSay("[Move] Movement module ready.  startPos=" + (string)gStartPos);
        if (DEBUG) llOwnerSay("[Move|DBG] state_entry: physics ON, buoyancy 1.0, startPos=" + (string)gStartPos);
    }

    link_message(integer sender, integer num, string str, key id)
    {
        // ---- Start autonomous flight -------------------------
        if (num == CMD_START)
        {
            gRunning   = TRUE;
            gHovering  = FALSE;
            gAvoiding  = FALSE;
            gRecalling = FALSE;
            gStartPos  = llGetPos();
            gTargetPos = randomWaypoint();
            llOwnerSay("[Move] CMD_START - target=" + (string)gTargetPos);
            if (DEBUG) llOwnerSay("[Move|DBG] CMD_START received. startPos=" + (string)gStartPos
                                  + "  firstTarget=" + (string)gTargetPos);
            llSetTimerEvent(CFG_UPDATE_INTERVAL);
            moveTo(gTargetPos);
        }

        // ---- Stop all movement ------------------------------
        else if (num == CMD_STOP)
        {
            gRunning   = FALSE;
            gHovering  = FALSE;
            gAvoiding  = FALSE;
            gRecalling = FALSE;
            llSetTimerEvent(0.0);
            stopMoving();
            if (DEBUG) llOwnerSay("[Move|DBG] CMD_STOP: all movement halted.");
        }

        // ---- Hover in place ---------------------------------
        else if (num == CMD_HOVER)
        {
            gHovering  = TRUE;
            gAvoiding  = FALSE;
            gRecalling = FALSE;
            hoverInPlace();
            llSetTimerEvent(1.0);   // Keep refreshing hold
        }

        // ---- Tune speed -------------------------------------
        else if (num == CMD_SET_SPEED)
        {
            float v = (float)str;
            if (v > 0.0 && v <= 20.0)
                CFG_SPEED = v;
            // CFG_SPEED is used to compute the llMoveToTarget tau dynamically,
            // so a higher value means a shorter tau and faster movement.
        }

        // ---- Tune hover height ------------------------------
        else if (num == CMD_SET_HEIGHT)
        {
            float h = (float)str;
            if (h >= CFG_MIN_FLIGHT_HEIGHT && h <= CFG_MAX_FLIGHT_HEIGHT)
                CFG_HOVER_HEIGHT = h;
        }

        // ---- Obstacle detected (from sensor module) ---------
        else if (num == CMD_OBSTACLE_DETECTED)
        {
            if (!gAvoiding)
            {
                gAvoiding = TRUE;
                // str contains avoidance direction as "<x,y,z>"
                gAvoidDir  = (vector)str;
                // Compute a new safe waypoint in the avoidance direction
                gTargetPos = llGetPos() + gAvoidDir * CFG_AVOID_STEP
                             + <0.0, 0.0, CFG_AVOID_STEP * 0.5>;
                if (DEBUG) llOwnerSay("[Move|DBG] OBSTACLE_DETECTED avoidDir=" + str
                                      + "  newTarget=" + (string)gTargetPos);
                moveTo(gTargetPos);
            }
        }

        // ---- Obstacle cleared (from sensor module) ----------
        else if (num == CMD_OBSTACLE_CLEAR)
        {
            if (gAvoiding)
            {
                gAvoiding  = FALSE;
                gTargetPos = randomWaypoint();
                if (DEBUG) llOwnerSay("[Move|DBG] OBSTACLE_CLEAR, resuming to " + (string)gTargetPos);
                if (gRunning) moveTo(gTargetPos);
            }
        }

        // ---- Debug toggle -----------------------------------
        else if (num == CMD_DEBUG)
        {
            DEBUG = (str == "on");
        }

        // ---- Recall to owner's position ---------------------
        else if (num == CMD_RECALL)
        {
            gRunning   = FALSE;
            gHovering  = FALSE;
            gAvoiding  = FALSE;
            gRecalling = TRUE;
            list details = llGetObjectDetails(llGetOwner(), [OBJECT_POS]);
            if (llGetListLength(details) > 0)
            {
                vector ownerPos = llList2Vector(details, 0);
                gTargetPos = ownerPos + <0.0, 0.0, CFG_HOVER_HEIGHT>;
                if (DEBUG) llOwnerSay("[Move|DBG] CMD_RECALL: ownerPos=" + (string)ownerPos
                                      + "  target=" + (string)gTargetPos);
                moveTo(gTargetPos);
                llSetTimerEvent(CFG_UPDATE_INTERVAL);
            }
            else if (DEBUG)
            {
                llOwnerSay("[Move|DBG] CMD_RECALL: llGetObjectDetails returned no data for owner!");
            }
        }
    }

    timer()
    {
        if (gHovering)
        {
            hoverInPlace();
            return;
        }

        if (gRecalling)
        {
            // Track owner's live position in case they move during recall
            list details = llGetObjectDetails(llGetOwner(), [OBJECT_POS]);
            if (llGetListLength(details) > 0)
            {
                vector ownerPos = llList2Vector(details, 0);
                gTargetPos = ownerPos + <0.0, 0.0, CFG_HOVER_HEIGHT>;
                if (llVecMag(llGetPos() - gTargetPos) < CFG_WAYPOINT_REACH)
                {
                    gRecalling = FALSE;
                    gHovering  = TRUE;
                    hoverInPlace();
                    llOwnerSay("[Drone] Recalled - hovering near owner.");
                    return;
                }
                moveTo(gTargetPos);
            }
            return;
        }

        if (!gRunning) return;

        vector current = llGetPos();

        // Pick new waypoint when close enough to current target
        if (llVecMag(current - gTargetPos) < CFG_WAYPOINT_REACH && !gAvoiding)
        {
            gTargetPos = randomWaypoint();
            if (DEBUG) llOwnerSay("[Move|DBG] timer: waypoint reached, new target=" + (string)gTargetPos
                                  + "  pos=" + (string)current);
        }

        moveTo(gTargetPos);
    }

    on_rez(integer start_param)
    {
        llResetScript();
    }
}
