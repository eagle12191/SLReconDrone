// ============================================================
// SL Recon Drone - Main Controller Module
// ============================================================
// Purpose : Receives commands from chat or linked scripts and
//           routes them to the appropriate sub-module.
//
// SETUP   : Drop ALL five drone_*.lsl scripts into the same
//           object (drone prim), then click "Reset Scripts".
//
// CHAT    : Speak on /42 (default) to control the drone.
//           e.g.  /42 start   /42 stop   /42 help
// ============================================================

// ---- Shared command constants (same in every module) --------
integer CMD_START             = 100;
integer CMD_STOP              = 101;
integer CMD_HOVER             = 102;
integer CMD_FPV_ON            = 103;
integer CMD_FPV_OFF           = 104;
integer CMD_STATUS            = 105;
integer CMD_SET_SPEED         = 106;
integer CMD_SET_HEIGHT        = 107;
integer CMD_RECALL            = 108;
integer CMD_OBSTACLE_DETECTED = 200;
integer CMD_OBSTACLE_CLEAR    = 201;

// ---- Configuration ------------------------------------------
integer CHAT_CHANNEL = 42;   // Owner speaks on /42  (change if needed)

// ---- Runtime state ------------------------------------------
integer gRunning   = FALSE;
integer gFPVActive = FALSE;

// ---- Helper: broadcast a command to all scripts in object ---
broadcast(integer cmd, string data)
{
    llMessageLinked(LINK_SET, cmd, data, NULL_KEY);
}

// ---- Parse and act on a text command ------------------------
handleCommand(string raw)
{
    list   parts = llParseString2List(llToLower(llStringTrim(raw, STRING_TRIM)), [" "], []);
    string verb  = llList2String(parts, 0);

    if (verb == "start")
    {
        gRunning = TRUE;
        broadcast(CMD_START, "");
        broadcast(CMD_STATUS, "Drone started.");
        llOwnerSay("[Drone] Started – flying autonomously.");
    }
    else if (verb == "stop")
    {
        gRunning   = FALSE;
        gFPVActive = FALSE;
        broadcast(CMD_STOP, "");
        broadcast(CMD_STATUS, "Drone stopped.");
        llOwnerSay("[Drone] Stopped.");
    }
    else if (verb == "hover")
    {
        broadcast(CMD_HOVER, "");
        llOwnerSay("[Drone] Hovering in place.");
    }
    else if (verb == "fpv" || verb == "fpv_on")
    {
        gFPVActive = TRUE;
        broadcast(CMD_FPV_ON, "");
        llOwnerSay("[Drone] FPV camera enabled.");
    }
    else if (verb == "fpv_off")
    {
        gFPVActive = FALSE;
        broadcast(CMD_FPV_OFF, "");
        llOwnerSay("[Drone] FPV camera disabled.");
    }
    else if (verb == "status")
    {
        llOwnerSay("[Drone] Running: " + (string)gRunning +
                   "  |  FPV: "       + (string)gFPVActive);
    }
    else if (verb == "speed")
    {
        string val = llList2String(parts, 1);
        if (val != "")
        {
            broadcast(CMD_SET_SPEED, val);
            llOwnerSay("[Drone] Speed set to " + val + " m/s.");
        }
        else
        {
            llOwnerSay("[Drone] Usage: speed <metres-per-second>  (e.g. speed 3.5)");
        }
    }
    else if (verb == "height")
    {
        string val = llList2String(parts, 1);
        if (val != "")
        {
            broadcast(CMD_SET_HEIGHT, val);
            llOwnerSay("[Drone] Hover height set to " + val + " m above start.");
        }
        else
        {
            llOwnerSay("[Drone] Usage: height <metres>  (e.g. height 5)");
        }
    }
    else if (verb == "recall")
    {
        broadcast(CMD_RECALL, "");
        llOwnerSay("[Drone] Recalling to your position…");
    }
    else if (verb == "help")
    {
        llOwnerSay("[Drone] Commands (speak on /" + (string)CHAT_CHANNEL + "):\n"
            + "  start       – begin autonomous flight\n"
            + "  stop        – stop all movement\n"
            + "  hover       – hold current position\n"
            + "  fpv / fpv_off – toggle first-person camera\n"
            + "  speed <n>   – set flight speed in m/s\n"
            + "  height <n>  – set hover height in metres\n"
            + "  recall      – fly back to your position\n"
            + "  status      – show current state\n"
            + "  help        – show this message");
    }
    else
    {
        llOwnerSay("[Drone] Unknown command: \"" + raw + "\" – try: help");
    }
}

// ---- Script body --------------------------------------------
default
{
    state_entry()
    {
        // Listen for owner commands on the configured channel
        llListen(CHAT_CHANNEL, "", llGetOwner(), "");
        llOwnerSay("[Drone] Main controller ready.  Speak on /"
                   + (string)CHAT_CHANNEL + " to control.  Try: /"
                   + (string)CHAT_CHANNEL + " help");
    }

    // Owner chat command
    listen(integer channel, string name, key id, string message)
    {
        if (channel == CHAT_CHANNEL && id == llGetOwner())
            handleCommand(message);
    }

    // Allow other scripted objects to send commands via llSay on
    // a public channel by bridging link messages received from
    // a companion HUD script (extend here as needed).
    link_message(integer sender, integer num, string str, key id)
    {
        // Re-broadcast any CMD_ values sent by external scripts
        // that are already loaded in this object (no-op if the
        // command came from one of our own sub-modules).
        if (num >= CMD_START && num <= CMD_RECALL)
            broadcast(num, str);
    }

    on_rez(integer start_param)
    {
        llResetScript();
    }
}
