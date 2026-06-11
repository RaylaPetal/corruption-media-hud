// DomDialog.lsl  —  menu for the DOM HUD (parallel to CorruptionDialog).

integer DOM_MENU_CMD   = 88012;  // this → DomCore
integer DOM_MENU_STATE = 88011;  // DomCore → this
integer DIALOG_TO_MATCH = 88021; // this → DomMatch
integer MATCH_TO_DIALOG = 88020; // DomMatch → this
integer DIALOG_CHAN    = -9989;
integer dialogMode     = 0;

// matching state
string  matchKind = "own";
list    candNames; list candKeys;          // scan picker
list    ownNames;  list ownKeys;           // owned roster
key     selSub = NULL_KEY; string selSubName = "";
string  taskType = "serve";

string  LEADERBOARD_URL = "https://raylapetal.github.io/corruption-media-hud/dom/leaderboard.html";

key wearer;

list DOM_TITLES = ["Curious Hand","Teasing Top","Rough Dom","Cruel Dom","Sadist",
                   "Breeder","Depraved Master","Cum Lord","Merciless Owner","Apex Predator"];

// cached state
integer c_lv = 1;
integer c_titleIdx = 0;
integer c_showTitle = TRUE;
integer c_showStatus = TRUE;
integer c_rotate = 10;
integer c_conquests = 0;
integer c_loads = 0;
integer c_bred = 0;
integer c_subs = 0;
integer c_prestige = 0;
string  c_ownedName = "";
list DOM_PRESTIGE_TITLES = ["Eternal Master", "Legendary Sire", "God of Conquest", "Immortal Breeder"];
list DOM_PRESTIGE_REQ    = [1, 3, 6, 10];

sendCmd(string cmd) { llMessageLinked(LINK_SET, DOM_MENU_CMD, cmd, ""); }
sendMatch(string cmd) { llMessageLinked(LINK_SET, DIALOG_TO_MATCH, cmd, ""); }

openMain() {
    dialogMode = 1;
    list buttons = ["Change Title","Display","Rotate Speed",
                    "Owned Sub","Matching","Leaderboard","Test Act"];
    if (c_lv >= 10 && c_prestige < 10) buttons += ["Prestige"];
    buttons += ["Reset","Cancel"];
    string pp = ""; if (c_prestige > 0) pp = "  [P" + (string)c_prestige + "]";
    string ownLine = ""; if (c_ownedName != "") ownLine = "\nOwned sub: " + c_ownedName;
    llDialog(wearer,
        "\n⚜ Dominance Menu ⚜\n"
        + "Lv." + (string)c_lv + pp + " · " + titleLabel(c_titleIdx) + "\n"
        + "Conquests: " + (string)c_conquests + "   Loads: " + (string)c_loads + "\n"
        + "Bred: " + (string)c_bred + ownLine,
        buttons, DIALOG_CHAN);
}

openDisplay() {
    dialogMode = 10;
    string tBtn; if (c_showTitle) tBtn = "Hide Title"; else tBtn = "Show Title";
    string sBtn; if (c_showStatus) sBtn = "Hide Status"; else sBtn = "Show Status";
    llDialog(wearer, "Display Settings", [tBtn, sBtn, "Back"], DIALOG_CHAN);
}

showTitleDialog() {
    list buttons = [];
    integer i;
    for (i = 0; i < c_lv && i < 10; i++) buttons += [llList2String(DOM_TITLES, i)];
    if (c_prestige >= 1) buttons += ["✦ Prestige Titles"];
    if (c_subs > 0)      buttons += ["⛓ Owner Title"];
    buttons += ["Back"];
    dialogMode = 2;
    llDialog(wearer, "Choose your title (unlocked up to Lv." + (string)c_lv + "):", buttons, DIALOG_CHAN);
}

showPrestigeTitleDialog() {
    list buttons = [];
    integer i;
    for (i = 0; i < llGetListLength(DOM_PRESTIGE_TITLES); i++)
        if (c_prestige >= llList2Integer(DOM_PRESTIGE_REQ, i))
            buttons += [llList2String(DOM_PRESTIGE_TITLES, i)];
    buttons += ["Back"];
    dialogMode = 12;
    llDialog(wearer, "✦ Prestige Titles ✦\nExclusive titles earned through prestige:", buttons, DIALOG_CHAN);
}

// ── Matching ─────────────────────────────────────────────────────────
openMatch() {
    dialogMode = 30;
    string head = "\n🔗 Matching\n\nScan for nearby Subs. \"Claim a Sub\" asks to own them; "
        + "\"Find a Mate\" is a casual hookup. They must accept.";
    if (c_subs > 0) head += "\n\nYou already own someone — release them before claiming another.";
    llDialog(wearer, head, ["Claim a Sub","Find a Mate","Back"], DIALOG_CHAN);
}
startScan(string kind) {
    matchKind = kind; candNames = []; candKeys = [];
    sendMatch("scan");
    dialogMode = 31;
    llDialog(wearer, "\n📡 Scanning for nearby Subs…\n\nThe list of who's nearby will open here automatically in a moment.",
        ["Cancel"], DIALOG_CHAN);
}
showCandidates(string payload) {
    candNames = []; candKeys = [];
    list rows = llParseString2List(payload, ["|"], []);
    integer i;
    for (i = 0; i < llGetListLength(rows) && i < 11; i++) {
        list kv = llParseString2List(llList2String(rows, i), ["="], []);
        if (llGetListLength(kv) == 2) { candNames += [llList2String(kv, 0)]; candKeys += [(key)llList2String(kv, 1)]; }
    }
    if (llGetListLength(candNames) == 0) { dialogMode = 0;
        llDialog(wearer, "\nNo Subs answered. Make sure they're nearby with the HUD.", ["Back"], DIALOG_CHAN); return; }
    dialogMode = 32;
    llDialog(wearer, "\nPick a Sub to send your request to:", candNames + ["Back"], DIALOG_CHAN);
}
showIncoming(string fromName, string kind) {
    string verb = "has shown interest in you";
    if (kind == "own") verb = "wants you as their Owner";
    dialogMode = 33;
    llDialog(wearer, "\n💌 " + fromName + " " + verb + ".\n\nClaim them?",
        ["Accept","Deny"], DIALOG_CHAN);
}
showOwned(string payload) {
    ownNames = []; ownKeys = [];
    list rows = llParseString2List(payload, [";"], []);
    integer i;
    for (i = 0; i < llGetListLength(rows) && i < 11; i++) {
        list kv = llParseString2List(llList2String(rows, i), ["="], []);
        if (llGetListLength(kv) == 2) { ownNames += [llList2String(kv, 0)]; ownKeys += [(key)llList2String(kv, 1)]; }
    }
    if (llGetListLength(ownNames) == 0) { dialogMode = 0;
        llDialog(wearer, "\nYou don't own anyone yet. Use Matching to claim a Sub.", ["Back"], DIALOG_CHAN); return; }
    // one sub only → go straight to their management actions
    selSub = llList2Key(ownKeys, 0); selSubName = llList2String(ownNames, 0);
    openSubActions();
}
openSubActions() {
    dialogMode = 35;
    llDialog(wearer, "\nManage " + selSubName + ":", ["Set Task","Clear Tasks","Release","Back"], DIALOG_CHAN);
}
openTaskType() {
    dialogMode = 36;
    llDialog(wearer, "\nTask for " + selSubName + ":\n• Serve = take loads from you\n• Breed = let you cum inside",
        ["Serve","Breed","Back"], DIALOG_CHAN);
}

parseState(string s) {
    list p = llParseString2List(s, ["|"], []);
    c_lv         = (integer)llList2String(p, 0);
    c_titleIdx   = (integer)llList2String(p, 1);
    c_showTitle  = (integer)llList2String(p, 2);
    c_showStatus = (integer)llList2String(p, 3);
    c_rotate     = (integer)llList2String(p, 4);
    c_conquests  = (integer)llList2String(p, 5);
    c_loads      = (integer)llList2String(p, 6);
    c_bred       = (integer)llList2String(p, 7);
    c_subs       = (integer)llList2String(p, 8);
    c_prestige   = (integer)llList2String(p, 9);
    c_ownedName  = llList2String(p, 10);
    p = [];
}

// Title label for the menu header (handles level / prestige / owner indices safely).
string titleLabel(integer idx) {
    if (idx == 99) return "Owner's Title";
    if (idx >= 10) return llList2String(DOM_PRESTIGE_TITLES, idx - 10);
    if (idx < 0 || idx >= llGetListLength(DOM_TITLES)) idx = 0;
    return llList2String(DOM_TITLES, idx);
}

default {
    state_entry() {
        wearer = llGetOwner();
        llListen(DIALOG_CHAN, "", wearer, "");
        sendCmd("req");
    }

    touch_start(integer n) {
        if (llDetectedKey(0) != wearer) return;
        openMain();
    }

    link_message(integer sn, integer num, string str, key id) {
        if (num == DOM_MENU_STATE) { parseState(str); return; }
        if (num == MATCH_TO_DIALOG) {
            list c = llParseString2List(str, ["|"], []);
            string ev = llList2String(c, 0);
            if      (ev == "cands")    showCandidates(llDeleteSubString(str, 0, 5));   // strip "cands|"
            else if (ev == "owned")    showOwned(llDeleteSubString(str, 0, 5));        // strip "owned|"
            else if (ev == "incoming") showIncoming(llList2String(c, 1), llList2String(c, 2));
            else if (ev == "bond")     { llOwnerSay(llList2String(c, 1) + " is now yours."); }
            else if (ev == "unbond")   { llOwnerSay("Your Sub has been released."); }
            return;
        }
    }

    listen(integer chan, string name, key id, string msg) {
        if (chan != DIALOG_CHAN) return;

        if (dialogMode == 2) {                          // title pick
            if (msg == "Back") { openMain(); return; }
            if (msg == "✦ Prestige Titles") { showPrestigeTitleDialog(); return; }
            if (msg == "⛓ Owner Title") { if (c_subs > 0) sendCmd("title|99"); dialogMode = 0; return; }
            integer idx = llListFindList(DOM_TITLES, [msg]);
            if (idx != -1 && idx < c_lv) sendCmd("title|" + (string)idx);
        }
        else if (dialogMode == 12) {                     // prestige title pick
            if (msg == "Back") { showTitleDialog(); return; }
            integer pi = llListFindList(DOM_PRESTIGE_TITLES, [msg]);
            if (pi != -1 && c_prestige >= llList2Integer(DOM_PRESTIGE_REQ, pi))
                sendCmd("title|" + (string)(10 + pi));
        }
        else if (dialogMode == 10) {                    // display
            if (msg == "Back") { openMain(); return; }
            integer df = c_showTitle | (c_showStatus << 1);
            if      (msg == "Hide Title"  || msg == "Show Title")  df = df ^ 1;
            else if (msg == "Hide Status" || msg == "Show Status") df = df ^ 2;
            sendCmd("display|" + (string)df);
            c_showTitle = df & 1; c_showStatus = (df >> 1) & 1;
            openDisplay();
            return;
        }
        else if (dialogMode == 4) {                     // rotate textbox
            float v = (float)msg;
            if (v < 2.0) v = 2.0; if (v > 60.0) v = 60.0;
            sendCmd("rotate|" + (string)((integer)v));
        }
        else if (dialogMode == 3) {                     // reset confirm
            if (msg == "Confirm Reset") sendCmd("reset");
        }
        else if (dialogMode == 9) {                      // prestige confirm
            if (msg == "Confirm Prestige") sendCmd("prestige");
        }
        else if (dialogMode == 11) {                    // leaderboard
            if (msg == "Back") { openMain(); return; }
            if (msg == "Open Link")
                llLoadURL(wearer, "Open the Hall of Conquest leaderboard?",
                    LEADERBOARD_URL + "?t=" + (string)llGetUnixTime());
        }
        else if (dialogMode == 30) {                     // matching root
            if (msg == "Back") { openMain(); return; }
            if (msg == "Claim a Sub") { startScan("own"); return; }
            if (msg == "Find a Mate") { startScan("mate"); return; }
        }
        else if (dialogMode == 31) {                     // scanning wait (picker auto-replaces when results arrive)
            if (msg == "Cancel" || msg == "Back") { openMain(); return; }
        }
        else if (dialogMode == 32) {                     // candidate picker
            if (msg == "Back") { openMatch(); return; }
            integer ci = llListFindList(candNames, [msg]);
            if (ci != -1) { sendMatch("offer|" + (string)llList2Key(candKeys, ci) + "|" + msg + "|" + matchKind);
                dialogMode = 0; }
        }
        else if (dialogMode == 33) {                     // incoming proposal
            if (msg == "Accept") sendMatch("accept"); else sendMatch("deny");
            dialogMode = 0;
        }
        else if (dialogMode == 34) {                     // owned roster
            if (msg == "Back") { openMain(); return; }
            integer oi = llListFindList(ownNames, [msg]);
            if (oi != -1) { selSub = llList2Key(ownKeys, oi); selSubName = msg; openSubActions(); return; }
        }
        else if (dialogMode == 35) {                     // sub actions
            if (msg == "Back") { openMain(); return; }
            if (msg == "Set Task")    { openTaskType(); return; }
            if (msg == "Clear Tasks") { sendMatch("taskclr|" + (string)selSub); dialogMode = 0; return; }
            if (msg == "Release")     { sendMatch("release|" + (string)selSub); dialogMode = 0; return; }
        }
        else if (dialogMode == 36) {                     // task type
            if (msg == "Back") { openSubActions(); return; }
            if (msg == "Serve") taskType = "serve"; else if (msg == "Breed") taskType = "breed"; else return;
            dialogMode = 37;
            llTextBox(wearer, "How many times must " + selSubName + " " + taskType + " you? (1-99)", DIALOG_CHAN);
            return;
        }
        else if (dialogMode == 37) {                     // task count
            integer n = (integer)msg; if (n < 1) n = 1; if (n > 99) n = 99;
            sendMatch("task|" + (string)selSub + "|" + taskType + "|" + (string)n);
            dialogMode = 0;
            return;
        }
        else {                                          // main menu
            if      (msg == "Change Title") { showTitleDialog(); return; }
            else if (msg == "Display")      { openDisplay(); return; }
            else if (msg == "Rotate Speed") {
                dialogMode = 4;
                llTextBox(wearer, "Display rotation seconds (2-60, current "
                    + (string)c_rotate + "):", DIALOG_CHAN);
                return;
            }
            else if (msg == "Owned Sub")  { sendMatch("list"); return; }
            else if (msg == "Matching")   { openMatch(); return; }
            else if (msg == "Leaderboard") {
                dialogMode = 11;
                llDialog(wearer,
                    "\n🏆 Hall of Conquest\n\n"
                    + "See how your dominance ranks against every other predator — live data.\n\n"
                    + "Tap \"Open Link\" to view it in your browser.",
                    ["Open Link","Back"], DIALOG_CHAN);
                return;
            }
            else if (msg == "Test Act") { sendCmd("testact"); }
            else if (msg == "Prestige") {
                dialogMode = 9;
                llDialog(wearer,
                    "\n✦ Prestige ✦\n\nReset to Lv.1 and become Prestige " + (string)(c_prestige + 1)
                    + "?\n\nXP and level reset; conquests/loads/bred are kept.\n"
                    + "Permanent +" + (string)((c_prestige + 1) * 10) + "% Dominance XP.",
                    ["Confirm Prestige","Cancel"], DIALOG_CHAN);
                return;
            }
            else if (msg == "Reset") {
                dialogMode = 3;
                llDialog(wearer, "Reset ALL dominance stats?\nThis cannot be undone.",
                    ["Confirm Reset","Cancel"], DIALOG_CHAN);
                return;
            }
        }
        dialogMode = 0;
    }

    changed(integer c) {
        if (c & (CHANGED_OWNER | CHANGED_INVENTORY)) llResetScript();
    }
}
