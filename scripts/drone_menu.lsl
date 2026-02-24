// ============================================================
// SL Recon Drone - Menu Module
// File: drone_menu.lsl
// ============================================================
// Opens a popup dialog when the owner touches the drone.
// Buttons map directly to drone commands; Speed and Height
// prompt a text-box for numeric entry.
//
// DROP this script into the drone alongside the other modules.
// No other scripts need to be changed - this module sends
// llMessageLinked commands exactly like the chat system does.
//
// LAYOUT  (SL fills dialog rows bottom-left -> right):
//
//   [ Height... ] [ Speed...  ] [   Start  ]
//   [ Recall    ] [ Hover     ] [   Stop   ]
//   [ Status    ] [ FPV Off   ] [  FPV On  ]
//   [  (space)  ] [ Dbg Off   ] [  Dbg On  ]
//
// ============================================================

// ---- Shared command constants (same in every module) --------
integer CMD_START      = 100;
integer CMD_STOP       = 101;
integer CMD_HOVER      = 102;
integer CMD_FPV_ON     = 103;
integer CMD_FPV_OFF    = 104;
integer CMD_STATUS     = 105;
integer CMD_SET_SPEED  = 106;
integer CMD_SET_HEIGHT = 107;
integer CMD_RECALL     = 108;
integer CMD_DEBUG      = 109;

// ---- Menu button labels (max 24 chars each) -----------------
string BTN_START   = "Start";
string BTN_STOP    = "Stop";
string BTN_HOVER   = "Hover";
string BTN_RECALL  = "Recall";
string BTN_FPV_ON  = "FPV On";
string BTN_FPV_OFF = "FPV Off";
string BTN_SPEED   = "Speed...";
string BTN_HEIGHT  = "Height...";
string BTN_STATUS  = "Status";
string BTN_DBG_ON  = "Dbg On";
string BTN_DBG_OFF = "Dbg Off";

// ---- Pending text-box input type ----------------------------
integer PENDING_NONE   = 0;
integer PENDING_SPEED  = 1;
integer PENDING_HEIGHT = 2;

// ---- Runtime state ------------------------------------------
integer gListenHandle = 0;    // Handle for the dialog channel
integer gTextHandle   = 0;    // Handle for the text-box channel
integer gChannel      = 0;    // Random dialog channel
integer gTextChannel  = 0;    // Random text-box channel
integer gPending      = 0;    // Which text-box response we're waiting for

integer LISTEN_TIMEOUT = 30;  // Auto-close after this many seconds

// ---- Clean up all active listens and the timer --------------
closeListens()
{
    if (gListenHandle) { llListenRemove(gListenHandle); gListenHandle = 0; }
    if (gTextHandle)   { llListenRemove(gTextHandle);   gTextHandle   = 0; }
    llSetTimerEvent(0.0);
    gPending = PENDING_NONE;
}

// ---- Open the main menu dialog ------------------------------
openMenu()
{
    closeListens();

    // Use a large random negative channel to avoid clashes
    gChannel      = -1 - (integer)llFrand(2147483646.0);
    gListenHandle = llListen(gChannel, "", llGetOwner(), "");
    llSetTimerEvent((float)LISTEN_TIMEOUT);

    // Buttons listed bottom-left across rows (3 x 3 = 9 buttons)
    llDialog(llGetOwner(),
        "\n=== Recon Drone ===\n\nChoose a command:",
        [BTN_STATUS, BTN_FPV_OFF, BTN_FPV_ON,
         BTN_RECALL, BTN_HOVER,   BTN_STOP,
         BTN_HEIGHT, BTN_SPEED,   BTN_START,
         " ",        BTN_DBG_OFF, BTN_DBG_ON],
        gChannel);
}

// ---- Open a text-box for numeric input ----------------------
openTextBox(integer pending, string prompt)
{
    closeListens();
    gPending     = pending;
    gTextChannel = -1 - (integer)llFrand(2147483646.0);
    gTextHandle  = llListen(gTextChannel, "", llGetOwner(), "");
    llSetTimerEvent((float)LISTEN_TIMEOUT);
    llTextBox(llGetOwner(), prompt, gTextChannel);
}

// ---- Dispatch a button press to the rest of the drone -------
handleButton(string btn)
{
    if      (btn == BTN_START)   llMessageLinked(LINK_SET, CMD_START,   "", NULL_KEY);
    else if (btn == BTN_STOP)    llMessageLinked(LINK_SET, CMD_STOP,    "", NULL_KEY);
    else if (btn == BTN_HOVER)   llMessageLinked(LINK_SET, CMD_HOVER,   "", NULL_KEY);
    else if (btn == BTN_RECALL)  llMessageLinked(LINK_SET, CMD_RECALL,  "", NULL_KEY);
    else if (btn == BTN_FPV_ON)  llMessageLinked(LINK_SET, CMD_FPV_ON,  "", NULL_KEY);
    else if (btn == BTN_FPV_OFF) llMessageLinked(LINK_SET, CMD_FPV_OFF, "", NULL_KEY);
    else if (btn == BTN_STATUS)  llMessageLinked(LINK_SET, CMD_STATUS,  "", NULL_KEY);
    else if (btn == BTN_DBG_ON)  { llMessageLinked(LINK_SET, CMD_DEBUG, "on",  NULL_KEY); llOwnerSay("[Menu] Debug logging ON.");  }
    else if (btn == BTN_DBG_OFF) { llMessageLinked(LINK_SET, CMD_DEBUG, "off", NULL_KEY); llOwnerSay("[Menu] Debug logging OFF."); }
    else if (btn == BTN_SPEED)
    {
        // openTextBox keeps a listen open – return without closeListens()
        openTextBox(PENDING_SPEED,
            "Enter flight speed in m/s\n(e.g. 3.5  -  valid range: 0.1 to 20.0):");
        return;
    }
    else if (btn == BTN_HEIGHT)
    {
        openTextBox(PENDING_HEIGHT,
            "Enter hover height in metres\n(e.g. 5.0  -  valid range: 2.5 to 25.0):");
        return;
    }

    // All instant-action buttons close the menu after dispatching
    closeListens();
}

// ---- Validate and dispatch a text-box response --------------
handleTextInput(string input)
{
    float val = (float)llStringTrim(input, STRING_TRIM);

    if (gPending == PENDING_SPEED)
    {
        if (val > 0.0 && val <= 20.0)
            llMessageLinked(LINK_SET, CMD_SET_SPEED, (string)val, NULL_KEY);
        else
            llOwnerSay("[Menu] Speed must be between 0.1 and 20.0 m/s - not changed.");
    }
    else if (gPending == PENDING_HEIGHT)
    {
        if (val >= 2.5 && val <= 25.0)
            llMessageLinked(LINK_SET, CMD_SET_HEIGHT, (string)val, NULL_KEY);
        else
            llOwnerSay("[Menu] Height must be between 2.5 and 25.0 m - not changed.");
    }

    closeListens();
}

// ---- Script body --------------------------------------------
default
{
    state_entry()
    {
        gListenHandle = 0;
        gTextHandle   = 0;
        gPending      = PENDING_NONE;
    }

    // Owner touches the drone -> open menu
    touch_start(integer num_detected)
    {
        if (llDetectedKey(0) == llGetOwner())
            openMenu();
    }

    listen(integer channel, string name, key id, string message)
    {
        if (id != llGetOwner()) return;

        if (channel == gChannel)
        {
            // Dialog button pressed
            closeListens();
            handleButton(message);
        }
        else if (channel == gTextChannel)
        {
            // Text-box response received
            handleTextInput(message);
        }
    }

    // Auto-expire the open dialog / text-box after LISTEN_TIMEOUT seconds
    timer()
    {
        closeListens();
        llOwnerSay("[Menu] Menu timed out - touch the drone to reopen.");
    }

    on_rez(integer start_param)
    {
        llResetScript();
    }
}
