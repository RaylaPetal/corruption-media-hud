key wearer;

integer MENU_CMD   = 88002; // this → core
integer MENU_STATE = 88001; // core → this
integer DIALOG_TO_MATCH = 88021; // this → CorruptionMatch
integer MATCH_TO_DIALOG = 88020; // CorruptionMatch → this
integer DIALOG_MAIN = -9988;
integer dialogMode   = 0;

string  LEADERBOARD_URL = "https://raylapetal.github.io/corruption-media-hud/leaderboard.html";

// ── Matching state ──
string  c_owner    = "";    // current owner name ("" = unowned), from MENU_STATE field 21
integer c_titleIdx = 0;     // current selected title idx (field 22) — 99 = owner title
string  matchKind  = "mate";// "own" or "mate" for the pending scan/offer
list    candNames;          // scan picker: parallel name/key lists
list    candKeys;
key     incomingKey = NULL_KEY;

// Prestige-exclusive titles (must match inm_monitor). Index i → title cmd 10+i.
list PRESTIGE_TITLES    = ["Eternal Cumslut", "Legendary Whore", "Goddess of Filth", "Immortal Cumdump"];
list PRESTIGE_TITLE_REQ = [1, 3, 6, 10];

// ── Cached state (refreshed by Core on every saveState) ──────────────
integer c_lv      = 1;
integer c_diff    = 1;
integer c_cumSys  = 0;
integer c_locked  = FALSE;
integer c_showTitle  = TRUE;
integer c_showStatus = TRUE;
integer c_rotate  = 10;
integer c_prestige = 0;
integer c_lastCum = 0;
integer c_idleThr = 259200;
integer c_decayInt = 3600;
integer c_decayAmt = 200;
integer c_dailyXP  = 0;
integer c_dayStart = 0;
integer c_dailyGoal = 2000;   // daily XP goal (broadcast field 16; was the removed cap)
integer c_haptics  = TRUE;
integer c_immersionOn = TRUE;   // arousal/immersion features — SEPARATE from Lovense (MENU_STATE field 2)
integer c_adultBypass = FALSE;  // override Adult-region safety gate for arousal (MENU_STATE field 3)
integer c_vibeIdleMin = 180;   // passive-vibe min idle gap (seconds); 60-1800
integer c_vibeIdleMax = 600;   // passive-vibe max idle gap (seconds); 60-1800
integer c_diffChosen  = TRUE;  // difficulty already locked? (FALSE → first-use prompt)
integer promptedDiff  = FALSE; // already showed the first-use difficulty picker this lock-cycle

// ── Helpers ──────────────────────────────────────────────────────────

sendCmd(string cmd) { llMessageLinked(LINK_SET, MENU_CMD, cmd, ""); }
sendMatch(string cmd) { llMessageLinked(LINK_SET, DIALOG_TO_MATCH, cmd, ""); }

string diffName(integer d) {
    if (d == 0) return "Tease";
    if (d == 2) return "Slut";
    return "Naughty";   // 1 (and any legacy Custom that migrated to Naughty)
}

string cumSystemName(integer s) {
    if (s == 1) return "INM";
    return "Spunked";
}

string prestigePrefix(integer p) {
    if (p <= 0) return "";
    list r = ["I","II","III","IV","V","VI","VII","VIII","IX","X"];
    if (p <= 10) return "[" + llList2String(r, p - 1) + "] ";
    return "[" + (string)p + "] ";
}

string formatDuration(integer secs) {
    if (secs <= 0) return "0m";
    integer d = secs / 86400;
    integer h = (secs % 86400) / 3600;
    integer m = (secs % 3600) / 60;
    string r = "";
    if (d > 0)            r += (string)d + "d ";
    if (h > 0)            r += (string)h + "h ";
    if (m > 0 || r == "") r += (string)m + "m";
    return llStringTrim(r, STRING_TRIM);
}

string buildInfoText() {
    integer now  = llGetUnixTime();
    integer idle = now - c_lastCum;
    string decayStr;
    if (idle < c_idleThr) {
        decayStr = "Safe for " + formatDuration(c_idleThr - idle);
    } else {
        integer perHr = c_decayAmt * 3600 / c_decayInt;   // XP lost per hour
        decayStr = "Active — losing " + (string)perHr
            + " XP/hr until you're used (never below your level)";
    }
    string haptics;
    if (c_haptics) haptics = "On"; else haptics = "Off";
    string imm;
    if (c_immersionOn) imm = "On"; else imm = "Off";
    integer dailyShown = c_dailyXP;
    integer secsReset  = 86400 - (now - c_dayStart);
    if (secsReset < 0) { dailyShown = 0; secsReset = 0; }
    return "── Corruption Info ──\n"
        + "Last fuck: " + formatDuration(idle) + " ago\n"
        + "Decay: "     + decayStr + "\n"
        + "─────────────────\n"
        + "Daily XP goal: "  + (string)dailyShown + " / " + (string)c_dailyGoal + " XP\n"
        + "Resets in "  + formatDuration(secsReset) + "\n"
        + "─────────────────\n"
        + "Lovense: " + haptics + "   Immersion: " + imm;
}

// ── Dialog openers ───────────────────────────────────────────────────

openMainDialog() {
    string lockBtn;
    if (c_locked) lockBtn = "Unlock"; else lockBtn = "Lock";
    list buttons = ["Change Title","Display","Settings"];
    // "Difficulty" only appears while unlocked (first use / after a reset) as a fallback
    // for re-opening the picker; once locked it's gone — re-choose only via Reset Stats.
    if (!c_diffChosen) buttons += ["Difficulty"];
    buttons += ["Leaderboard","Matching",lockBtn,"Lovense"];
    if (c_lv >= 10 && c_prestige < 10) buttons += ["Prestige"];
    buttons += ["Cancel"];
    dialogMode = 1;
    llDialog(wearer,
        "\nCorruption Menu\nChange your title, adjust settings, or reset your stats.\n\n"
        + buildInfoText(),
        buttons, DIALOG_MAIN);
}

openLeaderboardDialog() {
    dialogMode = 11;
    llDialog(wearer,
        "\n🏆 Corruption Leaderboard\n\n"
        + "See how your depravity ranks against everyone else — live data, updated as players play.\n\n"
        + "Tap \"Open Link\" to view it in your browser.",
        ["Open Link","Back"], DIALOG_MAIN);
}

// ── Matching / owner ────────────────────────────────────────────────
openMatchDialog() {
    dialogMode = 20;
    if (c_owner != "") {
        llDialog(wearer,
            "\n💞 Your Owner\n\nYou belong to " + c_owner + ".\n"
            + "Select the \"" + c_owner + "'s Slut\" title under Change Title.\n"
            + "Your tasks show on the Owner panel of your HUD.\n\n"
            + "You can still Find a Mate for casual hookups.",
            ["Find a Mate","Leave Owner","Back"], DIALOG_MAIN);
        return;
    }
    llDialog(wearer,
        "\n🔗 Matching\n\nFind a Dom nearby. \"Set an Owner\" asks them to own you; "
        + "\"Find a Mate\" shows interest. They must accept.",
        ["Set an Owner","Find a Mate","Back"], DIALOG_MAIN);
}

startScan(string kind) {
    matchKind = kind;
    candNames = []; candKeys = [];
    sendMatch("scan");
    dialogMode = 21;
    llDialog(wearer, "\n📡 Scanning for nearby Doms…\n\nThe list of who's nearby will open here automatically in a moment.",
        ["Cancel"], DIALOG_MAIN);
}

showCandidates(string payload) {
    // payload = "name=uuid|name=uuid|…"
    candNames = []; candKeys = [];
    list rows = llParseString2List(payload, ["|"], []);
    integer i;
    for (i = 0; i < llGetListLength(rows) && i < 11; i++) {
        list kv = llParseString2List(llList2String(rows, i), ["="], []);
        if (llGetListLength(kv) == 2) { candNames += [llList2String(kv, 0)]; candKeys += [(key)llList2String(kv, 1)]; }
    }
    if (llGetListLength(candNames) == 0) {
        dialogMode = 0;
        llDialog(wearer, "\nNo Doms answered. Make sure they're nearby and wearing the HUD.", ["Back"], DIALOG_MAIN);
        return;
    }
    dialogMode = 22;
    llDialog(wearer, "\nPick a Dom to send your request to:", candNames + ["Back"], DIALOG_MAIN);
}

showIncoming(string fromName, string kind) {
    string verb = "has shown interest in you";
    if (kind == "own") verb = "wants to OWN you";
    dialogMode = 23;
    llDialog(wearer, "\n💌 " + fromName + " " + verb + ".\n\nAccept their claim?",
        ["Accept","Deny"], DIALOG_MAIN);
}

openLovenseDialog() {
    dialogMode = 13;
    string lvBtn; string lvState;
    if (c_haptics) { lvBtn = "Lovense Off"; lvState = "ON"; }
    else           { lvBtn = "Lovense On";  lvState = "OFF"; }
    llDialog(wearer,
        "\n💙 Lovense\n\nToy buzzes: " + lvState + "\n\n"
        + "Passive tease buzz every " + (string)(c_vibeIdleMin / 60) + "–"
        + (string)(c_vibeIdleMax / 60) + " min.",
        [lvBtn, "Vibe Idle", "Back"], DIALOG_MAIN);
}

// Settings — the less-frequent toggles, gathered out of the main menu / Lovense menu.
openSettingsDialog() {
    dialogMode = 15;
    string imBtn; string imState;
    if (c_immersionOn) { imBtn = "Arousal Off"; imState = "ON"; }
    else               { imBtn = "Arousal On";  imState = "OFF"; }
    string byBtn; string byState;
    if (c_adultBypass) { byBtn = "Bypass Off"; byState = "ON ⚠ anywhere"; }
    else               { byBtn = "Bypass On";  byState = "OFF (Adult only)"; }
    llDialog(wearer,
        "\n⚙ Settings\n\n"
        + "Arousal (sparks / grope / moans): " + imState + "\n"
        + "Adult-region bypass: " + byState + "\n"
        + "Cum system: " + cumSystemName(c_cumSys) + "\n"
        + "Rotate speed: " + (string)c_rotate + "s",
        [imBtn, byBtn, "Rotate Speed", "Cum System", "Reset Stats", "Back"], DIALOG_MAIN);
}

openIdleDialog() {
    dialogMode = 14;
    llTextBox(wearer,
        "Passive Vibe Idle Range\n\nEnter min,max in minutes — a buzz fires at a random "
        + "gap in that range.\nExample:  2,5\n\nAllowed: 1 to 30 min.  Current: "
        + (string)(c_vibeIdleMin / 60) + "-" + (string)(c_vibeIdleMax / 60) + " min.",
        DIALOG_MAIN);
}

// First-use / post-reset welcome: pick the cum system, then chain into the difficulty
// picker (which locks). cumSystem itself isn't locked — it's changeable later in the menu.
openCumWelcome() {
    dialogMode = 7;
    llDialog(wearer,
        "✦ Welcome ✦\n\nWhich cum system are you wearing?\n\n"
        + "Spunked — the Spunked system\n"
        + "INM — INM / INAM system\n\n"
        + "(You can change this anytime in the menu.)",
        ["Spunked","INM"], DIALOG_MAIN);
}

openDifficultyDialog(integer firstUse) {
    dialogMode = 5;
    string head;
    list buttons;
    if (firstUse) {
        head = "✦ Welcome — Choose Your Difficulty ✦\n\n"
             + "This LOCKS once set, and can only be changed later by\nresetting your stats. Choose carefully:\n\n";
        buttons = ["Tease","Naughty","Slut"];
    } else {
        head = "Choose difficulty  (current: " + diffName(c_diff) + ")\n\n";
        buttons = ["Tease","Naughty","Slut","Back"];
    }
    llDialog(wearer,
        head
        + "Tease   — 7 day grace, higher XP\n"
        + "Naughty — 3 day grace, base XP\n"
        + "Slut    — 12 hour grace, lower XP",
        buttons, DIALOG_MAIN);
}

openDisplayDialog() {
    dialogMode = 10;
    string titleBtn;
    if (c_showTitle) titleBtn = "Hide Title"; else titleBtn = "Show Title";
    string statusBtn;
    if (c_showStatus) statusBtn = "Hide Status"; else statusBtn = "Show Status";
    string titleState;
    if (c_showTitle) titleState = "Visible"; else titleState = "Hidden";
    string statusState;
    if (c_showStatus) statusState = "Visible"; else statusState = "Hidden";
    llDialog(wearer,
        "Display Settings\n\nTitle:  " + titleState + "\nStatus: " + statusState,
        [titleBtn, statusBtn, "Back"], DIALOG_MAIN);
}

showTitleDialog() {
    list TITLES = ["Innocent One","Curious Kitten","Naughty Girl","Slutty",
                   "Filthy Slut","Cum Slut","Depraved Whore","Cock Addict",
                   "Mindless Fucktoy","Cum Dumpster"];
    list buttons = [];
    integer i;
    for (i = 0; i < c_lv && i < 10; i++)
        buttons += [llList2String(TITLES, i)];
    if (c_prestige >= 1) buttons += ["✦ Prestige Titles"];
    if (c_owner != "") buttons += ["💞 Owned Slut"];
    buttons += ["Back"];
    dialogMode = 2;
    llDialog(wearer,
        "Choose your title\n(Unlocked up to Lv." + (string)c_lv + "):",
        buttons, DIALOG_MAIN);
    TITLES = [];
}

showPrestigeTitleDialog() {
    list buttons = [];
    integer i;
    for (i = 0; i < llGetListLength(PRESTIGE_TITLES); i++)
        if (c_prestige >= llList2Integer(PRESTIGE_TITLE_REQ, i))
            buttons += [llList2String(PRESTIGE_TITLES, i)];
    buttons += ["Back"];
    dialogMode = 12;
    llDialog(wearer,
        "✦ Prestige Titles ✦\nExclusive titles earned through prestige:",
        buttons, DIALOG_MAIN);
}

// ── State receiver ───────────────────────────────────────────────────

parseState(string s) {
    // KeepNulls: ownerName (field 21) is empty when unowned — llParseString2List would
    // DROP that empty token and shift selectedTitleIdx into c_owner ("You belong to 3").
    list p = llParseStringKeepNulls(s, ["|"], []);
    c_lv       = (integer)llList2String(p, 0);
    c_diff     = (integer)llList2String(p, 1);
    c_immersionOn = (integer)llList2String(p, 2);   // field 2 reused (was custom-diff placeholder)
    c_adultBypass = (integer)llList2String(p, 3);   // field 3 reused (was reserved placeholder)
    c_cumSys   = (integer)llList2String(p, 4);
    c_locked   = (integer)llList2String(p, 5);
    c_showTitle  = (integer)llList2String(p, 6);
    c_showStatus = (integer)llList2String(p, 7);
    c_rotate   = (integer)llList2String(p, 8);
    c_prestige = (integer)llList2String(p, 9);
    c_lastCum  = (integer)llList2String(p, 10);
    c_idleThr  = (integer)llList2String(p, 11);
    c_decayInt = (integer)llList2String(p, 12);
    c_decayAmt = (integer)llList2String(p, 13);
    c_dailyXP  = (integer)llList2String(p, 14);
    c_dayStart = (integer)llList2String(p, 15);
    c_dailyGoal = (integer)llList2String(p, 16);
    c_haptics  = (integer)llList2String(p, 17);
    c_vibeIdleMax = (integer)llList2String(p, 18);
    c_vibeIdleMin = (integer)llList2String(p, 19);
    if (c_vibeIdleMin < 60) c_vibeIdleMin = 60;
    if (c_vibeIdleMax < c_vibeIdleMin) c_vibeIdleMax = c_vibeIdleMin;
    c_diffChosen = (integer)llList2String(p, 20);
    c_owner    = llList2String(p, 21);   // owner name ("" = unowned) → enables the owned-slut title
    c_titleIdx = (integer)llList2String(p, 22);
    p = [];

    // First use (or after a reset): difficulty isn't locked yet → greet once with the
    // cum-system picker, which then chains into the (locking) difficulty picker.
    // Re-arm while locked so a later reset prompts the whole welcome again.
    if (c_diffChosen) {
        promptedDiff = FALSE;
    } else if (!promptedDiff) {
        promptedDiff = TRUE;
        openCumWelcome();
    }
}

// ── Script state ─────────────────────────────────────────────────────

default {
    state_entry() {
        wearer = llGetOwner();
        llListen(DIALOG_MAIN, "", wearer, "");
        sendCmd("req"); // ask core to broadcast current state
    }

    touch_start(integer n) {
        if (llDetectedKey(0) != wearer) return;
        openMainDialog();
    }

    link_message(integer sender_num, integer num, string str, key id) {
        if (num == MENU_STATE) { parseState(str); return; }
        if (num == MATCH_TO_DIALOG) {
            list c = llParseString2List(str, ["|"], []);
            string ev = llList2String(c, 0);
            if (ev == "cands") showCandidates(llDeleteSubString(str, 0, 5));   // strip "cands|"
            else if (ev == "incoming") {
                incomingKey = NULL_KEY;   // the Match script holds the actual key; we just answer
                showIncoming(llList2String(c, 1), llList2String(c, 2));
            }
            else if (ev == "bond")   { llOwnerSay("You are now owned by " + llList2String(c, 1) + "."); }
            else if (ev == "unbond") { /* Core/MENU_STATE will refresh c_owner */ }
            return;
        }
    }

    listen(integer channel, string name, key id, string msg) {
        if (channel != DIALOG_MAIN) return;

        if (dialogMode == 2) {
            if (msg == "Back") { openMainDialog(); return; }
            if (msg == "✦ Prestige Titles") { showPrestigeTitleDialog(); return; }
            if (msg == "💞 Owned Slut") { if (c_owner != "") sendCmd("title|99"); dialogMode = 0; return; }
            list TITLES = ["Innocent One","Curious Kitten","Naughty Girl","Slutty",
                           "Filthy Slut","Cum Slut","Depraved Whore","Cock Addict",
                           "Mindless Fucktoy","Cum Dumpster"];
            integer idx = llListFindList(TITLES, [msg]);
            TITLES = [];
            if (idx != -1 && idx < c_lv) sendCmd("title|" + (string)idx);
        }
        else if (dialogMode == 12) {
            if (msg == "Back") { showTitleDialog(); return; }
            integer pi = llListFindList(PRESTIGE_TITLES, [msg]);
            if (pi != -1 && c_prestige >= llList2Integer(PRESTIGE_TITLE_REQ, pi))
                sendCmd("title|" + (string)(10 + pi));
        }
        else if (dialogMode == 3) {
            if (msg == "Confirm Reset") sendCmd("reset");
        }
        else if (dialogMode == 10) {
            if (msg == "Back") { openMainDialog(); return; }
            integer df = c_showTitle | (c_showStatus << 1);
            if      (msg == "Hide Title"   || msg == "Show Title")   df = df ^ 1;
            else if (msg == "Hide Status"  || msg == "Show Status")  df = df ^ 2;
            sendCmd("display|" + (string)df);
            c_showTitle  = df & 1;
            c_showStatus = (df >> 1) & 1;
            openDisplayDialog();
            return;
        }
        else if (dialogMode == 9) {
            if (msg == "Confirm Prestige") sendCmd("prestige");
        }
        else if (dialogMode == 5) {
            if (msg == "Back") { openMainDialog(); return; }
            integer d;
            if (msg == "Tease")     d = 0;
            else if (msg == "Slut") d = 2;
            else                    d = 1;
            sendCmd("difficulty|" + (string)d);
        }
        else if (dialogMode == 6) {
            if (msg == "Back") { openSettingsDialog(); return; }
            if      (msg == "Spunked") { c_cumSys = 0; sendCmd("cumSystem|0"); }
            else if (msg == "INM")     { c_cumSys = 1; sendCmd("cumSystem|1"); }
            openSettingsDialog();
            return;
        }
        else if (dialogMode == 7) {   // welcome: cum system → then difficulty (which locks)
            if      (msg == "Spunked") { c_cumSys = 0; sendCmd("cumSystem|0"); }
            else if (msg == "INM")     { c_cumSys = 1; sendCmd("cumSystem|1"); }
            openDifficultyDialog(TRUE);
            return;
        }
        else if (dialogMode == 4) {
            float v = (float)msg;
            if (v < 2.0)  v = 2.0;
            if (v > 60.0) v = 60.0;
            integer rotSecs = (integer)v;
            c_rotate = rotSecs;   // optimistic; Core confirms on next state
            sendCmd("rotate|" + (string)rotSecs);
            openSettingsDialog();
            return;
        }
        else if (dialogMode == 11) {
            if (msg == "Back") { openMainDialog(); return; }
            if (msg == "Open Link")
                // ?t=<unixtime> busts the browser cache so it always loads the latest
                // leaderboard.html (the page ignores the query; it fetches data separately).
                llLoadURL(wearer, "Open the Corruption RPG leaderboard?",
                    LEADERBOARD_URL + "?t=" + (string)llGetUnixTime());
        }
        else if (dialogMode == 20) {   // Matching root
            if (msg == "Back") { openMainDialog(); return; }
            if (msg == "Leave Owner") { sendMatch("unbind"); dialogMode = 0; return; }
            if (msg == "Set an Owner") { startScan("own"); return; }
            if (msg == "Find a Mate")  { startScan("mate"); return; }
        }
        else if (dialogMode == 21) {   // scanning wait (picker auto-replaces this when results arrive)
            if (msg == "Cancel" || msg == "Back") { openMainDialog(); return; }
        }
        else if (dialogMode == 22) {   // candidate picker
            if (msg == "Back") { openMatchDialog(); return; }
            integer ci = llListFindList(candNames, [msg]);
            if (ci != -1) {
                sendMatch("offer|" + (string)llList2Key(candKeys, ci) + "|" + msg + "|" + matchKind);
                dialogMode = 0;
            }
        }
        else if (dialogMode == 23) {   // incoming proposal accept/deny
            if (msg == "Accept") sendMatch("accept");
            else                 sendMatch("deny");
            dialogMode = 0;
        }
        else if (dialogMode == 13) {   // Lovense submenu (toy on/off + vibe idle)
            if (msg == "Back") { openMainDialog(); return; }
            if (msg == "Vibe Idle") { openIdleDialog(); return; }
            if (msg == "Lovense On" || msg == "Lovense Off") {
                integer want = 1;
                if (c_haptics) want = 0;
                c_haptics = want;            // optimistic; Core confirms on next state
                sendCmd("haptics|" + (string)want);
                openLovenseDialog();
            }
            return;
        }
        else if (dialogMode == 15) {   // Settings submenu
            if (msg == "Back") { openMainDialog(); return; }
            if (msg == "Arousal On" || msg == "Arousal Off") {
                integer wi = 1;
                if (c_immersionOn) wi = 0;
                c_immersionOn = wi;          // optimistic
                sendCmd("immersion|" + (string)wi);
                openSettingsDialog();
            }
            else if (msg == "Bypass On" || msg == "Bypass Off") {
                integer wb = 1;
                if (c_adultBypass) wb = 0;
                c_adultBypass = wb;          // optimistic
                sendCmd("adultbypass|" + (string)wb);
                openSettingsDialog();
            }
            else if (msg == "Rotate Speed") {
                dialogMode = 4;
                llTextBox(wearer,
                    "Enter display rotation interval in seconds\n(current: "
                    + (string)c_rotate + "s, range 2-60):", DIALOG_MAIN);
            }
            else if (msg == "Cum System") {
                dialogMode = 6;
                llDialog(wearer,
                    "Select cum tracking system  (current: " + cumSystemName(c_cumSys) + ")\n\n"
                    + "Spunked — needs the Spunked relay\nINM — needs the INM relay",
                    ["Spunked","INM","Back"], DIALOG_MAIN);
            }
            else if (msg == "Reset Stats") {
                if (c_locked) { llOwnerSay("System is locked. Unlock first."); return; }
                dialogMode = 3;
                llDialog(wearer,
                    "Reset ALL stats and XP?\nThis cannot be undone.",
                    ["Confirm Reset","Cancel"], DIALOG_MAIN);
            }
            return;
        }
        else if (dialogMode == 14) {   // passive-vibe idle range textbox: "min,max" minutes
            list r = llParseString2List(msg, [",", " ", "-"], []);
            integer lo = (integer)llList2String(r, 0);
            integer hi = (integer)llList2String(r, 1);
            r = [];
            if (lo < 1)  lo = 1;
            if (lo > 30) lo = 30;
            if (hi < lo) hi = lo;        // single number, or max below min → min only
            if (hi > 30) hi = 30;
            c_vibeIdleMin = lo * 60;     // optimistic; Core confirms on next state
            c_vibeIdleMax = hi * 60;
            sendCmd("vibeidle|" + (string)(lo * 60) + "|" + (string)(hi * 60));
            openLovenseDialog();
            return;
        }
        else {
            // Main menu (dialogMode 1)
            if (msg == "Lock" || msg == "Unlock") {
                integer wantLock = 1;
                if (c_locked) wantLock = 0;
                sendCmd("lock|" + (string)wantLock);
                return;
            }
            else if (msg == "Settings") { openSettingsDialog(); return; }
            else if (msg == "Prestige") {
                dialogMode = 9;
                llDialog(wearer,
                    "✦ Prestige ✦\n\nReset to Lv.1 and become " + prestigePrefix(c_prestige + 1) + "?\n\n"
                    + "XP and level will reset.\nLifetime stats are kept.\n"
                    + "Current prestige: " + (string)c_prestige,
                    ["Confirm Prestige","Cancel"], DIALOG_MAIN);
                return;
            }
            else if (msg == "Difficulty") {
                if (c_diffChosen) {
                    llOwnerSay("🔒 Difficulty is locked in. Reset Stats to choose it again.");
                    return;
                }
                openDifficultyDialog(FALSE);
                return;
            }
            else if (msg == "Display")      { openDisplayDialog(); return; }
            else if (msg == "Change Title") { showTitleDialog(); return; }
            else if (msg == "Leaderboard")  { openLeaderboardDialog(); return; }
            else if (msg == "Matching")     { openMatchDialog(); return; }
            else if (msg == "Lovense") { openLovenseDialog(); return; }
        }
        dialogMode = 0;
    }

    changed(integer c) {
        if (c & (CHANGED_OWNER | CHANGED_INVENTORY)) llResetScript();
    }
}
