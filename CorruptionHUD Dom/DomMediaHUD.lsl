// DomMediaHUD.lsl — media HUD renderer for the DOM HUD (mirror of CorruptionMediaHUD).
//
// LINKSET LAYOUT (worn HUD object):
//   Link 1 = achievements media → dom achievements page  (hidden until its button is hit)
//   Link 2 = circle BUTTON (non-media) — click expands / collapses
//   Link 3 = main HUD media → dom main page
//   Link 4 = owner media → dom owner page  (OPTIONAL new prim; hidden until "My Sub" is hit)
//
// Achievements & Owner are independent secondary panels. If link 4 doesn't exist yet the
// owner calls are harmless no-ops and the rest of the HUD works normally.

integer DOM_HUD_CHAN = -87440;   // DomCore broadcast
integer DOM_OWNER_HUD_CHAN = -87441; // ← DomMatch: "ownr|<subName>|<subTasks>"
integer MEDIA_FACE   = 4;

integer LINK_ACH = 1;
integer LINK_BTN = 3;
integer LINK_HUD = 4;
integer LINK_OWN = 2;

// ⚠ EDIT these to wherever you host the dom pages.
string  HUD_URL = "https://raylapetal.github.io/corruption-media-hud/dom.html";
string  ACH_URL = "https://raylapetal.github.io/corruption-media-hud/dom-achievements.html";
string  OWN_URL = "https://raylapetal.github.io/corruption-media-hud/dom-owner.html";

string  lastMsg  = "";
integer expanded = FALSE;
integer achShown = FALSE;
integer ownShown = FALSE;
string  ownedName = "";          // the sub we own (from DomMatch) — drives owner panel + button
string  subTasks  = "";          // "type:count:progress:done;…"
string  gURL = "";
key     gURLReq;

vector  fullHudSize;
vector  fullAchSize;
vector  fullOwnSize;
vector  TINY = <0.01, 0.01, 0.01>;
integer scaleGuardUntil = 0;

list mediaParams(string url) {
    return [
        PRIM_MEDIA_AUTO_PLAY,      TRUE,
        PRIM_MEDIA_PERMS_INTERACT, PRIM_MEDIA_PERM_OWNER,
        PRIM_MEDIA_PERMS_CONTROL,  PRIM_MEDIA_PERM_NONE,
        PRIM_MEDIA_WIDTH_PIXELS,   1024,
        PRIM_MEDIA_HEIGHT_PIXELS,  1024,
        PRIM_MEDIA_AUTO_SCALE,     TRUE,
        PRIM_MEDIA_HOME_URL,       url,
        PRIM_MEDIA_CURRENT_URL,    url
    ];
}

setupMedia() {
    llSetLinkMedia(LINK_HUD, MEDIA_FACE, mediaParams(HUD_URL));
    llSetLinkMedia(LINK_ACH, MEDIA_FACE, mediaParams(ACH_URL));
    llSetLinkMedia(LINK_OWN, MEDIA_FACE, mediaParams(OWN_URL));
}

vector capSize(string lsdKey, integer link, vector fallback) {
    vector v = (vector)llLinksetDataRead(lsdKey);
    if (llVecMag(v) >= 0.05) return v;                          // valid cached size
    v = llList2Vector(llGetLinkPrimitiveParams(link, [PRIM_SIZE]), 0);
    if (llVecMag(v) >= 0.05) { llLinksetDataWrite(lsdKey, (string)v); return v; }
    return fallback;                                            // prim currently tiny/hidden → sane size
}
captureSizes() {
    // Versioned keys (…2) drop any stale cache from the old prim numbering. The ach/own
    // panels share the main HUD's size, so they fall back to it; the HUD has a default so
    // a prim left tiny by a previous script can't lock the whole HUD small.
    fullHudSize = capSize("dsz_hud2", LINK_HUD, <0.22, 0.16, 0.02>);
    fullAchSize = capSize("dsz_ach2", LINK_ACH, fullHudSize);
    fullOwnSize = capSize("dsz_own2", LINK_OWN, fullHudSize);
}

setVis(integer link, integer show, vector full) {
    vector s; float a;
    if (show) { s = full; a = 1.0; } else { s = TINY; a = 0.0; }
    llSetLinkPrimitiveParamsFast(link, [PRIM_SIZE, s, PRIM_COLOR, ALL_SIDES, <1,1,1>, a]);
}
applyVis() {
    scaleGuardUntil = llGetUnixTime() + 3;
    if (!expanded) { achShown = FALSE; ownShown = FALSE; }
    setVis(LINK_HUD, expanded, fullHudSize);
    setVis(LINK_ACH, expanded && achShown, fullAchSize);
    setVis(LINK_OWN, expanded && ownShown, fullOwnSize);
}

pushData(string msg) {
    list p = llParseStringKeepNulls(msg, ["|"], []);
    string json = llList2Json(JSON_OBJECT, [
        "xp", llList2String(p, 1),
        "lv", llList2String(p, 2),
        "ti", llList2String(p, 3),
        "cq", llList2String(p, 4),
        "ls", llList2String(p, 5),
        "br", llList2String(p, 6),
        "in", llList2String(p, 7),
        "sc", llList2String(p, 8),
        "sl", llList2String(p, 9),
        "lb", llList2String(p, 10),
        "lt", llList2String(p, 11),
        "ct", llList2String(p, 12),
        "ac", llList2String(p, 14),
        "su", llList2String(p, 17),
        "ow", ownedName,
        "ep", gURL,
        "nw", (string)llGetUnixTime()
    ]);
    p = [];
    string hash = "#" + llEscapeURL(json);
    llSetLinkMedia(LINK_HUD, MEDIA_FACE, [PRIM_MEDIA_CURRENT_URL, HUD_URL + hash]);
    llSetLinkMedia(LINK_ACH, MEDIA_FACE, [PRIM_MEDIA_CURRENT_URL, ACH_URL + hash]);
}

pushOwner() {
    // dom:1 → owner.html flips its labels to "You own …"
    string oj = llList2Json(JSON_OBJECT, [ "ow", ownedName, "tk", subTasks, "dom", "1", "ep", gURL ]);
    llSetLinkMedia(LINK_OWN, MEDIA_FACE, [PRIM_MEDIA_CURRENT_URL, OWN_URL + "#" + llEscapeURL(oj)]);
}

bootView() {
    expanded = (llLinksetDataRead("dhud_exp") == "1");
    achShown = FALSE; ownShown = FALSE;
    applyVis();
}

requestURL() {
    if (gURL != "") { llReleaseURL(gURL); gURL = ""; }
    gURLReq = llRequestSecureURL();
}

default {
    state_entry() {
        setupMedia();
        llListen(DOM_HUD_CHAN, "", NULL_KEY, "");
        llListen(DOM_OWNER_HUD_CHAN, "", NULL_KEY, "");
        captureSizes();
        bootView();
        requestURL();
        llSetTimerEvent(15.0);
        if (lastMsg != "") { pushData(lastMsg); pushOwner(); }
    }

    attach(key id) {
        if (id != NULL_KEY) {
            setupMedia();
            captureSizes();
            bootView();
            requestURL();
            llSetTimerEvent(15.0);
            if (lastMsg != "") { pushData(lastMsg); pushOwner(); }
        }
    }

    timer() { if (gURL == "") requestURL(); }

    touch_start(integer n) {
        if (llDetectedKey(0) != llGetOwner()) return;
        if (llDetectedLinkNumber(0) != LINK_BTN) return;
        expanded = !expanded;
        if (!expanded) { achShown = FALSE; ownShown = FALSE; }
        llLinksetDataWrite("dhud_exp", (string)expanded);
        applyVis();
    }

    http_request(key id, string method, string body) {
        if (id == gURLReq) {
            if (method == URL_REQUEST_GRANTED) { gURL = body; if (lastMsg != "") pushData(lastMsg); pushOwner(); }
            return;
        }
        string q = llGetHTTPHeader(id, "x-query-string");
        if      (llSubStringIndex(q, "dach=1") >= 0) { achShown = TRUE;  ownShown = FALSE; }
        else if (llSubStringIndex(q, "dach=0") >= 0) { achShown = FALSE; }
        else if (llSubStringIndex(q, "down=1") >= 0) { ownShown = TRUE;  achShown = FALSE; pushOwner(); }
        else if (llSubStringIndex(q, "down=0") >= 0) { ownShown = FALSE; }
        applyVis();
        llHTTPResponse(id, 200, "ok");
    }

    listen(integer chan, string name, key id, string msg) {
        if (llList2Key(llGetObjectDetails(id, [OBJECT_OWNER]), 0) != llGetOwner()) return;
        if (chan == DOM_OWNER_HUD_CHAN) {
            if (llSubStringIndex(msg, "ownr|") != 0) return;
            list p = llParseStringKeepNulls(msg, ["|"], []);
            ownedName = llList2String(p, 1);
            subTasks  = llList2String(p, 2);
            p = [];
            if (lastMsg != "") pushData(lastMsg);
            pushOwner();
            return;
        }
        if (chan != DOM_HUD_CHAN) return;
        if (llSubStringIndex(msg, "dhud|") != 0) return;
        lastMsg = msg;
        pushData(msg);
    }

    changed(integer c) {
        if (c & (CHANGED_OWNER | CHANGED_INVENTORY)) { llResetScript(); return; }
        if (c & CHANGED_SCALE) {
            if (llGetUnixTime() < scaleGuardUntil) return;
            if (!expanded) return;
            fullHudSize = llList2Vector(llGetLinkPrimitiveParams(LINK_HUD, [PRIM_SIZE]), 0);
            llLinksetDataWrite("dsz_hud2", (string)fullHudSize);
            if (achShown) {
                fullAchSize = llList2Vector(llGetLinkPrimitiveParams(LINK_ACH, [PRIM_SIZE]), 0);
                llLinksetDataWrite("dsz_ach2", (string)fullAchSize);
            }
            if (ownShown) {
                fullOwnSize = llList2Vector(llGetLinkPrimitiveParams(LINK_OWN, [PRIM_SIZE]), 0);
                llLinksetDataWrite("dsz_own2", (string)fullOwnSize);
            }
        }
    }
}
