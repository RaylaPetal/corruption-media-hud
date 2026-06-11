integer HAPTIC_EVENT = 90200;     // Core → here: "<event>|<intensity 0-20>"
integer SEX_CHAN     = -87433;    // HUD → here: "sex|<0-3>" (0 off, 1 slow, 2 med, 3 intense)
integer LB_CHAN      = -4257001;  // LoveBridge receiver channel
integer ENABLED      = TRUE;      // master on/off

integer sexMode      = 0;         // sustained intensity: 0 off, 1 slow, 2 med, 3 intense
integer oneShot      = FALSE;     // a one-off buzz is currently playing (resume sustain after)
float   SUSTAIN_VARY = 4.0;       // seconds between sustained-pattern variations

// Base pattern pools (one per event). buildPat() picks one at random, scales its
// levels to the event's intensity (each is authored peaking at 20), and wraps it
// in a cpatt with a random delay — so repeated buzzes vary. cpatt LOOPS, so a short
// pattern fills the whole duration; keep EVERY pattern <= 9 levels (older toys stop
// above that). Shape per context: thrust waves, deep throbs, climactic pulses, etc.
list loadPats   = ["6,12,20,12", "8,14,20,16,11", "10,20,13,20,11"];          // firm thrust
list creamPats  = ["8,13,18,20,20,18,13,9", "10,16,20,20,20,15,10,6"];        // deep, throbbing fill
list orgasmPats = ["3,8,13,18,20,18,20,18,20", "6,11,16,20,16,20,16,20,20"];  // climax
list heatPats   = ["2,6,11,16,20,14,8,4", "3,8,13,18,20,13,8,3"];             // warm rising wave
list popPats    = ["0,20,0,20,0,20,0", "0,16,20,0,20,16,0"];                  // levelup pops
list teasePats  = ["0,7,14,20,14,7,0", "0,5,10,15,20,13,8,3", "0,8,16,11,5,0"]; // gentle tease

sendLB(string cmd) {
    if (!ENABLED) return;
    // llGetOwner() is always correct (no cached key to go stale / be NULL). Target the
    // owner's attachments directly per LoveBridge guidance. Format: key|command|level.
    key o = llGetOwner();
    llRegionSayTo(o, LB_CHAN, (string)o + "|" + cmd);
}

stopToy() {
    llSetTimerEvent(0.0);
    sendLB("vibrate|0");   // directly zero the vibrator — the real LoveBridge stop
}

string lvl(integer a) {
    if (a < 0) a = 0;
    if (a > 20) a = 20;
    return (string)a;
}

// Pick a random base pattern from `pool`, scale every level to `inten` (base peaks
// at 20, so the scaled peak ≈ inten), and wrap as a cpatt with a random delay in
// [dmin, dmin+drange). Variety per buzz; intensity still tracks what Core sends.
string buildPat(list pool, integer inten, integer dmin, integer drange) {
    list parts = llParseString2List(
        llList2String(pool, (integer)llFrand((float)llGetListLength(pool))), [","], []);
    integer n = llGetListLength(parts);
    string body = "";
    integer i;
    for (i = 0; i < n; i++) {
        if (i) body += ",";
        body += lvl((integer)llList2String(parts, i) * inten / 20);
    }
    integer ms = dmin + (integer)llFrand((float)drange);
    return "cpatt|" + (string)ms + "|" + body;
}

// Build & send one (randomised) sustained "thrusting" wave for the current sexMode.
// cpatt loops on the toy between re-issues, so vibration stays continuous; the
// per-tick jitter keeps it from feeling mechanically repetitive.
sustainSend() {
    integer delay; integer lo; integer hi;
    if (sexMode == 1)      { delay = 420; lo = 3;  hi = 9;  }   // Slow   — gentle, lazy grind (~140 bpm)
    else if (sexMode == 2) { delay = 280; lo = 7;  hi = 15; }   // Medium — steady, building thrust
    else                   { delay = 150; lo = 12; hi = 20; }   // Intense — fast, deep & strong

    delay += (integer)llFrand(80.0) - 40;          // ±40ms pace jitter
    if (delay < 100) delay = 100;                  // API minimum

    integer peak = hi - (integer)llFrand(3.0);     // peak: hi or up to 2 below
    integer m    = (lo + hi) / 2 + (integer)llFrand(3.0) - 1;   // jittered mid
    // low → mid → peak → mid → low, looped by cpatt
    string pat = lvl(lo) + "," + lvl(m) + "," + lvl(peak) + "," + lvl(m) + "," + lvl(lo);
    sendLB("cpatt|" + (string)delay + "|" + pat);
}

// Apply a new sustained intensity (0 = off). Doesn't interrupt a one-off buzz in
// progress — the timer resumes the right state when that buzz finishes.
setSexMode(integer m) {
    if (m < 0) m = 0;
    if (m > 3) m = 3;
    sexMode = m;
    if (oneShot) return;                 // let the current buzz finish; timer handles resume
    if (sexMode > 0) {
        sustainSend();
        llSetTimerEvent(SUSTAIN_VARY);
    } else {
        stopToy();
    }
}

playEvent(string ev, integer inten) {
    if (ev == "stop") { sexMode = 0; oneShot = FALSE; stopToy(); return; }
    if (ev == "ambient" && sexMode > 0) return;   // already buzzing; skip gentle teasing
    if (inten < 0) inten = 0;
    if (inten > 20) inten = 20;
    string c   = "";
    float  dur = 2.0;

    // Each event: a random pattern from its pool, scaled to inten, with a per-context
    // delay range (fast = thrust/climax, slow = warm tease). dur = how long it loops.
    if (ev == "load")          { c = buildPat(loadPats,   inten, 140, 100); dur = 20; }  // long active buzz
    else if (ev == "creampie") { c = buildPat(creamPats,  inten, 130, 70);  dur = 25; }
    else if (ev == "orgasm")   { c = buildPat(orgasmPats, inten, 90,  50);  dur = 30; }
    else if (ev == "heat")     { c = buildPat(heatPats,   inten, 240, 80);  dur = 15;  }
    else if (ev == "levelup")  { c = buildPat(popPats,    inten, 110, 40);  dur = 15;  }
    else if (ev == "ambient")  { c = buildPat(teasePats,  inten, 270, 80);  dur = 30; }  // passive tease
    else return;

    sendLB(c);
    oneShot = TRUE;          // this buzz owns the toy for `dur`; timer resumes after
    llSetTimerEvent(dur);
}

default {
    state_entry() {
        llListen(SEX_CHAN, "", NULL_KEY, "");
    }

    link_message(integer s, integer num, string str, key id) {
        if (num != HAPTIC_EVENT) return;
        list p = llParseString2List(str, ["|"], []);
        playEvent(llList2String(p, 0), (integer)llList2String(p, 1));
        p = [];
    }

    listen(integer chan, string name, key id, string msg) {
        if (chan != SEX_CHAN) return;
        if (llList2Key(llGetObjectDetails(id, [OBJECT_OWNER]), 0) != llGetOwner()) return;
        list p = llParseString2List(msg, ["|"], []);
        if (llList2String(p, 0) == "sex") setSexMode((integer)llList2String(p, 1));
        p = [];
    }

    timer() {
        if (oneShot) {
            oneShot = FALSE;             // the one-off buzz just ended
            if (sexMode > 0) { sustainSend(); llSetTimerEvent(SUSTAIN_VARY); }
            else stopToy();
            return;
        }
        // Sustained variety tick (only runs while sex mode is on)
        if (sexMode > 0) { sustainSend(); llSetTimerEvent(SUSTAIN_VARY); }
        else stopToy();
    }

    changed(integer c) {
        if (c & (CHANGED_OWNER | CHANGED_INVENTORY)) llResetScript();
    }
}
