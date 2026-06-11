integer HUD_CHAN = -87432;   // must match inm_monitor

string  wearerName;

// The overlay owns its own page rotation now (Core no longer drives it). It caches the
// last broadcast and flips between detail pages on its own timer.
string  gLastMsg = "";   // last "hud|..." broadcast (re-rendered each rotation)
integer gPage    = 0;    // which detail page (Spunked loads vs status)
integer gRotate  = 10;   // rotation seconds, from broadcast field 66 (menu "rotate" setting)

// One colour per title, same order as the level titles (blush white → deep purple).
// Prestige titles (idx >= 10) render gold. Mirrors Core's old titleColor()/table.
list TITLE_COLORS = [
    <1.00, 0.85, 0.90>, <1.00, 0.55, 0.72>, <1.00, 0.25, 0.50>, <1.00, 0.05, 0.35>,
    <1.00, 0.00, 0.10>, <0.90, 0.00, 0.00>, <1.00, 0.28, 0.00>, <0.85, 0.00, 0.55>,
    <0.60, 0.00, 0.90>, <0.38, 0.00, 0.72>
];

vector titleColor(integer idx) {
    if (idx >= 10) return <1.00, 0.78, 0.10>;   // gold for prestige titles
    return llList2Vector(TITLE_COLORS, idx);
}

string prestigePrefix(integer p) {
    if (p <= 0) return "";
    list romans = ["I","II","III","IV","V","VI","VII","VIII","IX","X"];
    if (p <= 10) return "[" + llList2String(romans, p - 1) + "] ";
    return "[" + (string)p + "] ";
}

// Live body mirror (set per broadcast) — drives the status line. Same logic Core had.
// cThroat/cAnal are the INM internal creampies (0 on Spunked, where throat/anal are
// folded into cFace/cAss instead).
integer cFace; integer cChest; integer cPussy; integer cAss; integer cBody;
integer cThroat; integer cAnal; integer cVagCream;
integer cCumSys;   // 0 = Spunked (simple status), 1 = INM (in-depth creampie status)

string getStatus() {
    integer pExt = cPussy - cVagCream;   // "on pussy" (external) = total pussy minus creampie

    // ════ INM: in-depth tracking — throat / vaginal / anal creampies + tits/coverage ════
    if (cCumSys == 1) {
        integer cps = (cThroat > 0) + (cVagCream > 0) + (cAnal > 0);   // distinct holes creampied
        integer nI  = (pExt>0)+(cVagCream>0)+(cAss>0)+(cAnal>0)+(cFace>0)+(cThroat>0)+(cChest>0)+(cBody>0);
        if (nI == 0) return "Clean ✧";

        // multi-hole creampie combos (most depraved first)
        if (cps == 3)                  return "Bred in Every Hole ♥♥♥";
        if (cVagCream > 0 && cAnal > 0)   return "Pussy & Ass Bred ♥♥";
        if (cThroat   > 0 && cVagCream > 0) return "Throat & Pussy Bred ♥♥";
        if (cThroat   > 0 && cAnal > 0)   return "Throat & Ass Bred ♥♥";

        // individual creampies — the three INM holes
        if (cVagCream >= 3) return "Womb Flooded ♥";
        if (cVagCream >  0) return "Pussy Creampied ♥";
        if (cAnal     >= 3) return "Ass Bred Deep ♥";
        if (cAnal     >  0) return "Anal Creampied ♥";
        if (cThroat   >= 3) return "Throat Flooded ♥";
        if (cThroat   >  0) return "Throat Creampied ♥";

        // external coverage (incl. tits)
        if (cChest >= 3) return "Tits Glazed ♥";
        if (cChest >  0) return "Tits Covered ♥";
        if (cFace  >= 4) return "Face Drenched ♥";
        if (cFace  >  0) return "Messy Face ♥";
        if (pExt   >= 4) return "Pussy Soaked ♥";
        if (pExt   >  0) return "Pussy Covered ♥";
        if (cAss   >= 4) return "Ass Glazed ♥";
        if (cAss   >  0) return "Ass Covered ♥";
        if (cBody  >= 3) return "Body Drenched ♥";
        if (cBody  >  0) return "Getting Messy ♥";
        return "Clean ✧";
    }

    // ════ Spunked: simple coverage (face / ass / pussy / creampie) ════
    integer n     = (cPussy > 0) + (cAss > 0) + (cFace > 0) + (cChest > 0) + (cBody > 0);
    integer total = cFace + cPussy + cAss + cChest + cBody;
    integer holes = (cFace > 0) + (cPussy > 0) + (cAss > 0);

    if (n == 0) return "Clean ✧";

    if (n == 5 && total >= 8) return "Absolute Cumdump ★★";
    if (n == 5)               return "Head to Toe ★";

    if (holes == 3 && total >= 9) return "Every Hole Wrecked ♥";
    if (holes == 3)               return "Every Hole Used ♥";

    if (cPussy > 0 && cAss > 0)  return "Both Holes Filled ♥";
    if (cFace > 0 && cPussy > 0) {
        if (cFace >= 3 || cPussy >= 3) return "Throat & Pussy Ruined ♥";
        return "Throat & Pussy Used ♥";
    }
    if (cFace > 0 && cAss > 0)   return "Face & Ass Stuffed ♥";

    if (n >= 3) return "Messy Slut ★";
    if (n >= 2) return "Used & Dirty ✦";

    if (cFace     >= 4) return "Face Drenched ♥";
    if (cFace     >  0) return "Messy Face ♥";
    if (cVagCream >  0) return "Creampied ♥";          // split: internal creampie
    if (pExt      >= 4) return "Pussy Flooded ♥";      // split: on-pussy external
    if (pExt      >  0) return "Pussy Covered ♥";
    if (cAss      >= 4) return "Ass Wrecked ♥";
    if (cAss      >  0) return "Ass Creampied ♥";
    if (cChest    >= 3) return "Chest Soaked ♥";
    if (cChest    >  0) return "Chest Covered ♥";
    if (cBody     >= 3) return "Body Drenched ♥";
    if (cBody     >  0) return "Getting Messy ♥";

    return "Clean ✧";
}

// Render the floating text from Core's broadcast. KeepNulls so an empty field
// (e.g. nextTitle) can't shift the indices we read.
render(string msg) {
    list p = llParseStringKeepNulls(msg, ["|"], []);
    integer xp          = (integer)llList2String(p, 1);
    integer lv          = (integer)llList2String(p, 2);
    integer prestige    = (integer)llList2String(p, 3);
    integer titleIdx    = (integer)llList2String(p, 4);
    integer totalCount  = (integer)llList2String(p, 5);
    integer sessPart    = (integer)llList2String(p, 7);
    integer lvTop       = (integer)llList2String(p, 14);
    string  curTitle    =          llList2String(p, 15);
    integer creampie    = (integer)llList2String(p, 17);
    integer pussyC      = (integer)llList2String(p, 18);
    integer assC        = (integer)llList2String(p, 19);
    integer faceC       = (integer)llList2String(p, 20);
    integer showTitle   = (integer)llList2String(p, 29);
    integer showStatus  = (integer)llList2String(p, 30);
    // field 31 (was displayPage) is now overlay-owned (gPage); rotation interval is field 66
    integer ri = (integer)llList2String(p, 66);
    if (ri > 0 && ri != gRotate) { gRotate = ri; llSetTimerEvent((float)gRotate); }
    cFace  = (integer)llList2String(p, 32);
    cChest = (integer)llList2String(p, 33);
    cPussy = (integer)llList2String(p, 34);
    cAss   = (integer)llList2String(p, 35);
    cBody  = (integer)llList2String(p, 36);
    cThroat = (integer)llList2String(p, 58);   // INM throat creampie (0 on Spunked)
    cAnal   = (integer)llList2String(p, 59);   // INM anal creampie (0 on Spunked)
    cVagCream = (integer)llList2String(p, 62);  // vaginal creampie (both systems)
    cCumSys   = (integer)llList2String(p, 63);  // 0 Spunked / 1 INM → which status set to render
    integer oralCream = (integer)llList2String(p, 60);   // throat creampies (lifetime, INM)
    integer analCream = (integer)llList2String(p, 61);   // anal creampies (lifetime, INM)
    integer inmFlags  = (integer)llList2String(p, 64);   // INM flags: 1 bredPlugged, 2 dripping
    string  lastPartner =          llList2String(p, 38);   // 37 is now difficulty (leaderboard)
    p = [];

    vector col   = titleColor(titleIdx);
    string title = prestigePrefix(prestige) + curTitle;

    if (!showTitle && !showStatus) { llSetText("", col, 0.0); return; }
    if (!showStatus) { llSetText("✧✦ " + title + " ✦✧\n", col, 1.0); return; }

    string s = "";
    if (showTitle) s += "✧✦ " + title + " ✦✧\n";
    string lvLine = wearerName + " Corruption | ";
    if (prestige > 0) lvLine += "P" + (string)prestige + " ";
    lvLine += "Lv." + (string)lv + "\n";
    s += lvLine;
    s += (string)xp + "/" + (string)lvTop + " XP\n";

    if (gPage == 0)
    {
        // ── Page 0: loads ── (INM shows its creampie breakdown; Spunked shows loads)
        if (cCumSys == 1)
        {
            integer totalCream = creampie + oralCream + analCream;
            s += "--------\n";
            s += "Creampied " + (string)totalCream + " times ♥\n";
            s += "Throat: " + (string)oralCream
               + "  Pussy: " + (string)creampie
               + "  Ass: " + (string)analCream;
            string flair = "";   // INM-only live state
            if (inmFlags & 1) flair = "Bred & Plugged ♥";
            if (inmFlags & 2) { if (flair != "") flair += " · "; flair += "Dripping"; }
            if (flair != "") s += "\n" + flair;
        }
        else
        {
            s += "--------\n";
            s += "Loads Received:\n";
            s += "Face: " + (string)faceC
               + " Pussy: " + (string)pussyC
               + " Ass: " + (string)assC + "\n";
            s += "Creampied: " + (string)creampie + " times ♥";
        }
    }
    else
    {
        // ── Page 1: status / fucked by / session ── (both systems; getStatus branches)
        s += "--------\n";
        s += "Status: " + getStatus() + "\n";
        s += "Fucked by " + (string)totalCount + " people\n";
        s += (string)sessPart + " this session";
        if (lastPartner != "") s += " · Last: " + lastPartner;
    }

    llSetText(s, col, 1.0);
}

default {
    state_entry() {
        wearerName = llGetDisplayName(llGetOwner());
        llSetTimerEvent((float)gRotate);   // own the page rotation (Core no longer drives it)
    }

    attach(key id) {
        if (id != NULL_KEY) {
            wearerName = llGetDisplayName(llGetOwner());
            llSetTimerEvent((float)gRotate);
        }
    }

    link_message(integer sender, integer num, string msg, key id) {
        if (num != HUD_CHAN) return;
        if (llSubStringIndex(msg, "hud|") != 0) return;
        gLastMsg = msg;       // cache so the rotation timer can re-render between broadcasts
        render(msg);
    }

    timer() {
        gPage = !gPage;       // flip the detail page
        if (gLastMsg != "") render(gLastMsg);
    }

    changed(integer c) {
        if (c & (CHANGED_OWNER | CHANGED_INVENTORY)) llResetScript();
    }
}
