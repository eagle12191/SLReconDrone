// ============================================================
// SL Recon Drone - FPV Camera Module
// ============================================================
// Gives the drone owner a first-person view from the drone's
// perspective by continuously updating the camera position and
// focus point to match the drone's pose.
//
// PERMISSIONS : The owner must grant PERMISSION_CONTROL_CAMERA.
//   • If the drone is ATTACHED, permission is requested on rez.
//   • If the drone is REZZED, the owner must click the object
//     (touch_start) to trigger the permission request, or the
//     main script will request it when FPV_ON is received.
//
// TOGGLE : Send /42 fpv to enable, /42 fpv_off to disable.
// ============================================================

// ---- Shared command constants (same in every module) --------
integer CMD_FPV_ON  = 103;
integer CMD_FPV_OFF = 104;

// ---- FPV camera configuration -------------------------------
float CFG_CAM_FORWARD_OFFSET = 0.2;    // Metres ahead of drone centre
float CFG_CAM_UP_OFFSET      = 0.05;   // Metres above drone centre
float CFG_CAM_FOCUS_DIST     = 12.0;   // Metres ahead for focus point
float CFG_CAM_FOV            = 1.05;   // Field of view in radians (~60°)
float CFG_CAM_LAG            = 0.05;   // Camera lag (0 = instant, 1 = sluggish)
float CFG_UPDATE_RATE        = 0.1;    // Camera refresh interval in seconds

// ---- Runtime state ------------------------------------------
integer gFPVActive      = FALSE;
integer gPermsGranted   = FALSE;

// ---- Ask owner for camera control permission ----------------
requestPermissions()
{
    llRequestPermissions(llGetOwner(), PERMISSION_CONTROL_CAMERA);
}

// ---- Push the camera to drone's current pose ----------------
updateCamera()
{
    vector   pos = llGetPos();
    rotation rot = llGetRot();

    // Camera sits just in front of and slightly above the drone
    vector camOffset   = <CFG_CAM_FORWARD_OFFSET, 0.0, CFG_CAM_UP_OFFSET> * rot;
    vector camPos      = pos + camOffset;

    // Focus point is directly ahead along the drone's forward axis
    vector focusOffset = <CFG_CAM_FOCUS_DIST, 0.0, 0.0> * rot;
    vector focusPos    = pos + focusOffset;

    llSetCameraParams([
        CAMERA_ACTIVE,          TRUE,
        CAMERA_POSITION,        camPos,
        CAMERA_FOCUS,           focusPos,
        CAMERA_POSITION_LAG,    CFG_CAM_LAG,
        CAMERA_FOCUS_LAG,       CFG_CAM_LAG,
        CAMERA_FOV,             CFG_CAM_FOV,
        CAMERA_POSITION_LOCKED, TRUE,
        CAMERA_FOCUS_LOCKED,    TRUE
    ]);
}

// ---- Release camera back to the owner -----------------------
releaseCamera()
{
    llClearCameraParams();
    gFPVActive = FALSE;
    llSetTimerEvent(0.0);
    llOwnerSay("[Camera] FPV disabled – camera returned to normal.");
}

// ---- Script body --------------------------------------------
default
{
    state_entry()
    {
        gFPVActive    = FALSE;
        gPermsGranted = FALSE;

        // If already attached, request permissions immediately
        if (llGetAttached() != 0)
            requestPermissions();
    }

    // Owner touches the drone → request permissions (rezzed scenario)
    touch_start(integer num_detected)
    {
        if (llDetectedKey(0) == llGetOwner() && !gPermsGranted)
        {
            llOwnerSay("[Camera] Requesting camera permission…");
            requestPermissions();
        }
    }

    run_time_permissions(integer perms)
    {
        if (perms & PERMISSION_CONTROL_CAMERA)
        {
            gPermsGranted = TRUE;
            llOwnerSay("[Camera] Camera permission granted.");

            // If FPV was already requested before perms were granted, start now
            if (gFPVActive)
            {
                llSetTimerEvent(CFG_UPDATE_RATE);
                updateCamera();
            }
        }
        else
        {
            gPermsGranted = FALSE;
            llOwnerSay("[Camera] Camera permission denied – FPV unavailable.");
        }
    }

    link_message(integer sender, integer num, string str, key id)
    {
        // ---- Enable FPV -------------------------------------
        if (num == CMD_FPV_ON)
        {
            gFPVActive = TRUE;
            if (!gPermsGranted)
            {
                llOwnerSay("[Camera] Requesting camera permission – please Accept.");
                requestPermissions();
            }
            else
            {
                llSetTimerEvent(CFG_UPDATE_RATE);
                updateCamera();
                llOwnerSay("[Camera] FPV enabled.");
            }
        }

        // ---- Disable FPV ------------------------------------
        else if (num == CMD_FPV_OFF)
        {
            releaseCamera();
        }
    }

    timer()
    {
        if (!gFPVActive || !gPermsGranted)
        {
            llSetTimerEvent(0.0);
            return;
        }
        updateCamera();
    }

    // Release camera if the object is detached or reset
    attach(key id)
    {
        if (id == NULL_KEY)
            releaseCamera();   // Being detached
        else
            requestPermissions();   // Being attached – request perms
    }

    on_rez(integer start_param)
    {
        llResetScript();
    }
}
