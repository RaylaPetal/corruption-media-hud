// DomCore.lsl  —  brain of the DOM HUD (parallel to CorruptionCore on the sub side).
//
// Tracks DOMINANCE progression — the one doing the corrupting: conquests (partners
// used), loads delivered, breedings, infamy. Mirrors the sub Core's architecture
// (single LSD save blob, broadcast to media/overlay/rewards, menu command handling)
// but is its own object with its own 64KB budget, so it never touches the sub system.
//
// DETECTION IS LIVE: a partner's sub HUD region-says "report|<subUUID>|<loads>|<creampie>"
// to us (DOM_REPORT) whenever we cum on them, and processReport() turns that into conquests
// / loads / breedings + XP. A "Test Act" menu button simulates one for testing.

// ── channels ──
integer DOM_HUD_CHAN   = -87440;  // core → dom media / overlay / rewards (broadcast)
integer DOM_MENU_CMD   = 88012;   // menu → core
integer DOM_MENU_STATE = 88011;   // core → menu
integer DOM_REPORT     = -87450;  // sub HUDs → this dom: "report|<subUUID>|<loads>|<creampie>"
integer DOM_REWARD     = 90111;   // dom_rewards → core: grant an achievement
integer DOM_DB_RESTORE = 88013;   // dom_db → core: blob rehydrated, reload
integer DOM_DB_FLUSH   = 88014;   // core → dom_db: upload this snapshot now (reset)
integer DOM_OWN_COUNT  = 88031;   // dom_match → core: number of owned subs (→ subsOwned stat)

key wearer;

// ── persistent dominance state ──
integer domXP;
integer domLevel = 1;        // cached computeLevel()
integer conquests;           // unique partners used (lifetime)
integer loadsSent;           // loads delivered (lifetime)
integer bred;                // breedings / creampies delivered (lifetime)
integer infamy;              // dom reputation (lifetime) — placeholder source for now
integer subsOwned;           // claimed subs (placeholder; 0 until the match system lands)
integer selectedTitleIdx;
integer showTitle  = TRUE;
integer showStatus = TRUE;
float   rotateInterval = 10.0;
integer achFlags;            // dom achievements bitfield

// ── session state (reset on a fresh day / manual reset) ──
list    sessTargets;         // UUIDs used this session (dedup for session conquests)
integer sConquests;
integer sLoads;
string  lastSubName = "";    // most recent partner (comma-free)
string ownedName = "";      // the sub we own (from DomMatch) — drives the owned-sub page
key ownedKey = NULL_KEY;   // their key, for the URL hash (also from DomMatch)
integer OWNED_TITLE_IDX = 99;   // sentinel selectedTitleIdx for the owner-granted title
integer dayStartTime;

// ── XP curve + dom titles ──
list LEVEL_XP = [0, 300, 800, 1600, 3000, 6000, 12000, 24000, 45000, 90000];
integer ENDLESS_STEP = 45000;
list DOM_TITLES = ["Curious Hand","Teasing Top","Rough Dom","Cruel Dom","Sadist",
                   "Breeder","Depraved Master","Cum Lord","Merciless Owner","Apex Predator"];

// Prestige (mirror of the sub): at max level, prestige to reset level/xp for a permanent
// XP buff + an exclusive prestige title. Prestige titles occupy selectedTitleIdx 10+i.
integer domPrestige   = 0;
integer DOM_PRESTIGE_MAX = 10;
list DOM_PRESTIGE_TITLES = ["Eternal Master", "Legendary Sire", "God of Conquest", "Immortal Breeder"];
list DOM_PRESTIGE_REQ    = [1, 3, 6, 10];

// XP per act (placeholder values — tune freely)
integer XP_FUCK  = 60;       // a new partner used
integer XP_LOAD  = 25;       // per load delivered
integer XP_BREED = 120;      // a breeding (creampie)

// XP decay — a dom who stops dominating goes soft (mirror of the sub's idle decay).
integer IDLE_THRESHOLD = 259200; // seconds idle before decay starts (3 days)
integer DECAY_INTERVAL = 3600;   // lose XP every this many seconds once idle
integer DECAY_AMOUNT   = 50;     // XP lost per decay tick
integer lastActTime;             // last time we dominated someone
integer lastDecayTime;

integer timerTick;

// ── helpers ──────────────────────────────────────────
integer computeLevel() {
    integer n = llGetListLength(LEVEL_XP);
    integer topXP = llList2Integer(LEVEL_XP, n - 1);
    if (domXP >= topXP) return n + (domXP - topXP) / ENDLESS_STEP;
    integer i;
    for (i = n - 2; i >= 0; i--)
        if (domXP >= llList2Integer(LEVEL_XP, i)) return i + 1;
    return 1;
}

integer xpFloor() {
    integer n = llGetListLength(LEVEL_XP);
    if (domLevel < n) return llList2Integer(LEVEL_XP, domLevel - 1);
    integer topXP = llList2Integer(LEVEL_XP, n - 1);
    return topXP + (domLevel - n) * ENDLESS_STEP;
}

integer xpTop() {
    integer n = llGetListLength(LEVEL_XP);
    if (domLevel < n) return llList2Integer(LEVEL_XP, domLevel);
    integer topXP = llList2Integer(LEVEL_XP, n - 1);
    return topXP + (domLevel - n + 1) * ENDLESS_STEP;
}

string titleName(integer idx) {
    if (idx == OWNED_TITLE_IDX) {
        if (ownedName != "") return ownedName + "'s Owner";
        return llList2String(DOM_TITLES, 0);   // bond gone but title still selected → safe fallback
    }
    if (idx >= 10) return llList2String(DOM_PRESTIGE_TITLES, idx - 10);   // prestige title
    integer last = llGetListLength(DOM_TITLES) - 1;
    if (idx > last) idx = last;
    if (idx < 0) idx = 0;
    return llList2String(DOM_TITLES, idx);
}

clampTitle() {
    if (selectedTitleIdx >= 10) return;   // prestige (10+) & owner (99) titles aren't level-gated
    integer maxIdx = domLevel - 1;
    integer last = llGetListLength(DOM_TITLES) - 1;
    if (maxIdx > last) maxIdx = last;
    if (selectedTitleIdx > maxIdx) selectedTitleIdx = maxIdx;
}

// Permanent reward for prestiging: +10% XP per prestige level (mirror of the sub).
float getPrestigeMult() { return 1.0 + (float)domPrestige * 0.10; }

// ── broadcast to dom media / overlay / rewards ──
string updateDisplay() {
    integer lvBase = xpFloor();
    integer lvTop  = xpTop();
    string curTitle  = titleName(selectedTitleIdx);
    string nextTitle = "";
    integer last = llGetListLength(DOM_TITLES) - 1;
    if (selectedTitleIdx < last) nextTitle = llList2String(DOM_TITLES, selectedTitleIdx + 1);

    // Concatenated (not a list literal) to keep the heap peak low — same discipline as the sub.
    string msg =
          "dhud|" + (string)domXP + "|" + (string)domLevel + "|" + (string)selectedTitleIdx  // 0-3
        + "|" + (string)conquests + "|" + (string)loadsSent + "|" + (string)bred             // 4-6
        + "|" + (string)infamy + "|" + (string)sConquests + "|" + (string)sLoads             // 7-9
        + "|" + (string)lvBase + "|" + (string)lvTop                                         // 10-11
        + "|" + curTitle + "|" + nextTitle                                                   // 12-13
        + "|" + (string)achFlags + "|" + (string)showTitle + "|" + (string)showStatus        // 14-16
        + "|" + (string)subsOwned + "|" + (string)((integer)rotateInterval)                  // 17-18
        + "|" + lastSubName + "|" + ownedName + "|" + (string)ownedKey                        // 19-21 (kept in place)
        + "|" + (string)domPrestige + "|" + (string)lastActTime + "|" + (string)IDLE_THRESHOLD; // 22-24 (appended)

    llSay(DOM_HUD_CHAN, msg);                                 // worn media/overlay (separate prims hear via listen)
    llMessageLinked(LINK_SET, DOM_HUD_CHAN, msg, NULL_KEY);   // same-linkset consumers (rewards/overlay)
    return msg;
}

broadcastState() {
    llMessageLinked(LINK_SET, DOM_MENU_STATE,
          (string)domLevel + "|" + (string)selectedTitleIdx + "|" + (string)showTitle  // 0-2
        + "|" + (string)showStatus + "|" + (string)((integer)rotateInterval)           // 3-4
        + "|" + (string)conquests + "|" + (string)loadsSent + "|" + (string)bred        // 5-7
        + "|" + (string)subsOwned + "|" + (string)domPrestige + "|" + ownedName, "");   // 8-10
}

// ── persistence (own LSD key, append-only like the sub blob) ──
saveState() {
    llLinksetDataWrite("dom_state",
          (string)domXP + "," + (string)conquests + "," + (string)loadsSent
        + "," + (string)bred + "," + (string)infamy + "," + (string)selectedTitleIdx
        + "," + (string)(showTitle + showStatus * 2) + "," + (string)subsOwned
        + "," + (string)dayStartTime + "," + (string)achFlags
        + "," + (string)((integer)rotateInterval) + "," + (string)sConquests
        + "," + (string)sLoads + "," + lastSubName + "," + ownedName + "," + (string)ownedKey  // 12-15
        + "," + (string)domPrestige + "," + (string)lastActTime + "," + (string)lastDecayTime);  // 16-18 (appended)
    broadcastState();
}

loadState() {
    string d = llLinksetDataRead("dom_state");
    if (d == "" || llSubStringIndex(d, ",") == -1) return;
    list p = llParseStringKeepNulls(d, [","], []);
    integer n = llGetListLength(p);
    if (n < 1) return;
    domXP            = (integer)llList2String(p, 0);
    if (n >= 2) conquests   = (integer)llList2String(p, 1);
    if (n >= 3) loadsSent   = (integer)llList2String(p, 2);
    if (n >= 4) bred         = (integer)llList2String(p, 3);
    if (n >= 5) infamy       = (integer)llList2String(p, 4);
    if (n >= 6) selectedTitleIdx = (integer)llList2String(p, 5);
    if (n >= 7) { integer df = (integer)llList2String(p, 6); showTitle = df & 1; showStatus = (df >> 1) & 1; }
    if (n >= 8) subsOwned    = (integer)llList2String(p, 7);
    if (n >= 9) dayStartTime = (integer)llList2String(p, 8);
    if (n >= 10) achFlags    = (integer)llList2String(p, 9);
    if (n >= 11) rotateInterval = (float)((integer)llList2String(p, 10));
    if (n >= 12) sConquests  = (integer)llList2String(p, 11);
    if (n >= 13) sLoads      = (integer)llList2String(p, 12);
    if (n >= 14) lastSubName = llList2String(p, 13);
    if (n >= 15) ownedName   = llList2String(p, 14);
    if (n >= 16) ownedKey     = (key)llList2String(p, 15);
    if (n >= 17) domPrestige  = (integer)llList2String(p, 16);
    if (n >= 18) lastActTime  = (integer)llList2String(p, 17);
    if (n >= 19) lastDecayTime = (integer)llList2String(p, 18);
    p = [];
    domLevel = computeLevel();
    clampTitle();
}

addXP(integer amount) {
    integer prevLv = domLevel;
    domXP += amount;
    if (domXP < 0) domXP = 0;
    domLevel = computeLevel();
    if (domLevel > prevLv && selectedTitleIdx < domLevel - 1) selectedTitleIdx = domLevel - 1;
    clampTitle();
}

// A reported dom act from a sub HUD: who (tgt), how many loads delivered, was it a creampie?
// A new unique partner this session = a conquest; loads add to loadsSent; creampie = a breeding.
processReport(key tgt, integer loads, integer creampie) {
    if (loads < 1) loads = 1;
    integer xp = 0;

    // New unique partner this session → a conquest.
    if (tgt != NULL_KEY && tgt != wearer && llListFindList(sessTargets, [(string)tgt]) == -1) {
        sessTargets += [(string)tgt];
        sConquests++;
        conquests++;
        xp += XP_FUCK;
        string nm = llGetDisplayName(tgt);
        integer sp = llSubStringIndex(nm, " ");
        if (sp > 0) nm = llGetSubString(nm, 0, sp - 1);
        lastSubName = llDumpList2String(llParseString2List(nm, [",", "|"], []), "");
    }

    loadsSent += loads; sLoads += loads; xp += XP_LOAD * loads;
    if (creampie) { bred++; xp += XP_BREED; }
    addXP((integer)((float)xp * getPrestigeMult() + 0.5));   // prestige buff carries across resets

    // dominating resets the idle/decay clock
    integer now = llGetUnixTime();
    lastActTime = now; lastDecayTime = now;

    updateDisplay();
    saveState();
}

// Idle XP decay — a dom who stops dominating goes soft (mirror of the sub). Never drops
// below the current level's floor. Called on attach/rez (offline catch-up) and the timer.
applyDecay() {
    integer now = llGetUnixTime();
    if (now - lastActTime < IDLE_THRESHOLD) return;
    integer decayStart = lastActTime + IDLE_THRESHOLD;
    if (lastDecayTime > decayStart) decayStart = lastDecayTime;
    integer ticks = (now - decayStart) / DECAY_INTERVAL;
    if (ticks <= 0) return;
    lastDecayTime = decayStart + ticks * DECAY_INTERVAL;
    integer loss    = ticks * DECAY_AMOUNT;
    integer floorXP = xpFloor();
    if (domXP - loss < floorXP) loss = domXP - floorXP;   // never decay past the level base
    if (loss <= 0) return;
    addXP(-loss);
    llOwnerSay("-" + (string)loss + " Dominance (" + (string)ticks + "h soft from no conquests)");
    saveState();
    updateDisplay();
}

resetSession() {
    sessTargets = [];
    sConquests  = 0;
    sLoads      = 0;
}

processMenuCmd(string str) {
    list c = llParseString2List(str, ["|"], []);
    string cmd = llList2String(c, 0);

    if (cmd == "title") {
        integer idx = (integer)llList2String(c, 1);
        integer ok = FALSE;
        if (idx == OWNED_TITLE_IDX) {
            if (ownedName != "") ok = TRUE;          // only selectable while actually owning someone
        }
        else if (idx >= 10) {
            integer pi = idx - 10;                   // prestige title: gated by prestige, not level
            if (pi < llGetListLength(DOM_PRESTIGE_TITLES) &&
                domPrestige >= llList2Integer(DOM_PRESTIGE_REQ, pi)) ok = TRUE;
        }
        else if (idx >= 0 && idx < domLevel) ok = TRUE;
        if (ok) {
            selectedTitleIdx = idx;
            saveState();
            updateDisplay();
        }
    }
    else if (cmd == "prestige") {
        if (domPrestige >= DOM_PRESTIGE_MAX) {
            llOwnerSay("You've already reached maximum prestige (" + (string)DOM_PRESTIGE_MAX + ").");
            return;
        }
        domPrestige++;
        domXP = 0; domLevel = 1; selectedTitleIdx = 0;
        resetSession();
        saveState();
        updateDisplay();
        llOwnerSay("✦ Prestige " + (string)domPrestige + " — reborn crueler! Permanent +"
            + (string)(domPrestige * 10) + "% Dominance XP ✦");
    }
    else if (cmd == "display") {
        integer df = (integer)llList2String(c, 1);
        showTitle = df & 1; showStatus = (df >> 1) & 1;
        saveState(); updateDisplay();
    }
    else if (cmd == "rotate") {
        rotateInterval = (float)llList2String(c, 1);
        if (rotateInterval < 2.0) rotateInterval = 2.0;
        if (rotateInterval > 60.0) rotateInterval = 60.0;
        saveState(); updateDisplay();
    }
    else if (cmd == "reset") {
        domXP = conquests = loadsSent = bred = infamy = subsOwned = selectedTitleIdx = 0;
        achFlags = 0; domPrestige = 0;
        domLevel = 1;
        dayStartTime = llGetUnixTime();
        lastActTime = llGetUnixTime(); lastDecayTime = lastActTime;
        resetSession();
        llLinksetDataDelete("dom_state");
        // push the zeroed snapshot to the cloud now, so a detach can't leave stale rank data
        llMessageLinked(LINK_SET, DOM_DB_FLUSH, updateDisplay(), NULL_KEY);
        broadcastState();
        llOwnerSay("Dominance reset.");
    }
    else if (cmd == "testact") {
        // TEMP: simulate a reported dom act so the HUD is testable without a partner.
        processReport(llGenerateKey(), 1 + (integer)llFrand(3.0), llFrand(1.0) < 0.5);
        llOwnerSay("[test] simulated a dom act.");
    }
    else if (cmd == "req") {
        broadcastState();
    }
    c = [];
}

reinit() {
    loadState();
    if (dayStartTime == 0)  dayStartTime  = llGetUnixTime();
    if (lastActTime == 0)   lastActTime   = llGetUnixTime();
    if (lastDecayTime == 0) lastDecayTime = lastActTime + IDLE_THRESHOLD;
    applyDecay();              // catch up on idle time spent detached
    updateDisplay();
    broadcastState();
}

default {
    state_entry() {
        wearer = llGetOwner();
        llListen(DOM_REPORT, "", NULL_KEY, "");   // sub HUDs report acts here (region-said to us)
        reinit();
        llSetAlpha(0, ALL_SIDES);
        llSetTimerEvent(5.0);
    }

    on_rez(integer p) { reinit(); }
    attach(key id) { if (id != NULL_KEY) { llListen(DOM_REPORT, "", NULL_KEY, ""); reinit(); } }

    // Real detection: a sub's HUD region-says "report|<subUUID>|<loads>|<creampie>" when
    // we cum on them. Their say is targeted at us, so only our own HUD hears it.
    listen(integer chan, string name, key id, string msg) {
        if (chan != DOM_REPORT) return;
        if (llSubStringIndex(msg, "report|") != 0) return;
        list r = llParseString2List(msg, ["|"], []);
        processReport((key)llList2String(r, 1), (integer)llList2String(r, 2),
                      (integer)llList2String(r, 3));
        r = [];
    }

    link_message(integer sn, integer num, string str, key id) {
        if (num == DOM_MENU_CMD) { processMenuCmd(str); return; }
        if (num == DOM_DB_RESTORE) { loadState(); updateDisplay(); broadcastState();
            llOwnerSay("Dominance restored from cloud."); return; }
        if (num == DOM_OWN_COUNT)
        {
            // DomMatch owner bond set/cleared → "<ownedName>|<ownedKey>" ("" = released)
            list p = llParseStringKeepNulls(str, ["|"], []);
            ownedName = llList2String(p, 0);
            ownedKey  = (key)llList2String(p, 1);
            subsOwned = (ownedName != "");
            if (ownedName == "" && selectedTitleIdx == OWNED_TITLE_IDX) {
                selectedTitleIdx = domLevel - 1; clampTitle();   // bond gone → drop the owner title
            }
            p = [];
            saveState();
            updateDisplay();
            return;
        }
            
        if (num == DOM_REWARD) {
            // dom_rewards grants an achievement: "<bit>|<amount>|<label>"
            list r = llParseString2List(str, ["|"], []);
            integer bit = (integer)llList2String(r, 0);
            integer amt = (integer)llList2String(r, 1);
            string label = llList2String(r, 2);
            r = [];
            if (achFlags & bit) return;          // dedup
            achFlags = achFlags | bit;
            domXP += amt; domLevel = computeLevel(); clampTitle();
            llOwnerSay("✦ " + label + " — +" + (string)amt + " Dominance ✦");
            saveState(); updateDisplay();
            return;
        }
    }

    timer() {
        timerTick++;
        if (timerTick % 2 == 0) updateDisplay();   // ~10s refresh
        if (timerTick % 12 == 0) applyDecay();     // ~once a minute, idle decay (self-guards)
        // Daily session reset (24h).
        if (llGetUnixTime() - dayStartTime >= 86400) {
            dayStartTime = llGetUnixTime();
            resetSession();
            saveState();
            updateDisplay();
        }
    }

    changed(integer c) {
        if (c & CHANGED_OWNER) { llLinksetDataReset(); llResetScript(); }
    }
}
