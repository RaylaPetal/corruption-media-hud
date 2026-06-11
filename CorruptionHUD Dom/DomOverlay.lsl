// DomOverlay.lsl  —  floating text for the DOM HUD (parallel to CorruptionOverlay).
// Renders the dom's title + dominance from DomCore's "dhud|" broadcast, and owns its
// own page rotation (Core just supplies the interval at field 18).

integer DOM_HUD_CHAN = -87440;   // DomCore broadcast

string  wearerName;
string  gLastMsg = "";
integer gPage    = 0;
integer gRotate  = 10;

// dom theme: deep crimson glow (vs the sub's title-colour gradient)
vector  DOM_COL = <0.85, 0.06, 0.10>;

string romanPrefix() { return ""; }   // (no prestige on the dom side yet)

render(string msg) {
    list p = llParseStringKeepNulls(msg, ["|"], []);
    integer xp        = (integer)llList2String(p, 1);
    integer lv        = (integer)llList2String(p, 2);
    integer conquests = (integer)llList2String(p, 4);
    integer loadsSent = (integer)llList2String(p, 5);
    integer bred      = (integer)llList2String(p, 6);
    integer infamy    = (integer)llList2String(p, 7);
    integer sConq     = (integer)llList2String(p, 8);
    integer sLoads    = (integer)llList2String(p, 9);
    integer lvTop     = (integer)llList2String(p, 11);
    string  curTitle  =          llList2String(p, 12);
    integer showTitle = (integer)llList2String(p, 15);
    integer showStatus= (integer)llList2String(p, 16);
    integer subsOwned = (integer)llList2String(p, 17);
    integer ri        = (integer)llList2String(p, 18);
    string  lastSub   =          llList2String(p, 19);
    p = [];
    if (ri > 0 && ri != gRotate) { gRotate = ri; llSetTimerEvent((float)gRotate); }

    if (!showTitle && !showStatus) { llSetText("", DOM_COL, 0.0); return; }
    if (!showStatus) { llSetText("⚜ " + curTitle + " ⚜\n", DOM_COL, 1.0); return; }

    string s = "";
    if (showTitle) s += "⚜ " + curTitle + " ⚜\n";
    s += wearerName + " Dominance | Lv." + (string)lv + "\n";
    s += (string)xp + "/" + (string)lvTop + " XP\n";

    if (gPage == 0) {
        s += "--------\n";
        s += "Conquests: " + (string)conquests + "\n";
        s += "Loads Sent: " + (string)loadsSent + "  Bred: " + (string)bred;
    } else {
        s += "--------\n";
        s += "This session: " + (string)sConq + " used · " + (string)sLoads + " loads\n";
        s += "Infamy: " + (string)infamy;
        if (lastSub != "") s += "\nLast: " + lastSub;
    }

    llSetText(s, DOM_COL, 1.0);
}

default {
    state_entry() {
        wearerName = llGetDisplayName(llGetOwner());
        llSetTimerEvent((float)gRotate);
    }
    attach(key id) {
        if (id != NULL_KEY) { wearerName = llGetDisplayName(llGetOwner()); llSetTimerEvent((float)gRotate); }
    }

    link_message(integer sn, integer num, string msg, key id) {
        if (num != DOM_HUD_CHAN) return;
        if (llSubStringIndex(msg, "dhud|") != 0) return;
        gLastMsg = msg;
        render(msg);
    }

    timer() {
        gPage = !gPage;
        if (gLastMsg != "") render(gLastMsg);
    }

    changed(integer c) {
        if (c & (CHANGED_OWNER | CHANGED_INVENTORY)) llResetScript();
    }
}
