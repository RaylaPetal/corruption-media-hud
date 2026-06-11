// CorruptionMediaHUD.lsl — Media HUD renderer (worn HUD object, separate from the monitor)
//
// LINKSET LAYOUT:
//   Link 1 = achievements media → achievements.html   (hidden until its button is hit)
//   Link 2 = circle BUTTON (non-media) — click expands / collapses the HUD
//   Link 3 = main HUD media → index.html
//   Link 4 = owner media → owner.html  (OPTIONAL new prim; hidden until "My Owner" is hit)
//
// Achievements & Owner are independent secondary panels, each toggled exactly the same
// proven way (show = full size+opaque, hide = TINY+transparent). If link 4 doesn't exist
// yet, the owner calls are harmless no-ops and the rest of the HUD works normally.

integer HUD_CHAN   = -87432;   // must match the monitor
integer SEX_CHAN   = -87433;   // → inm_lovense: "sex|<0-3>" sustained-vibe intensity
integer OWNER_HUD_CHAN = -87434; // ← CorruptionMatch: "ownr|<ownerName>|<tasks>"
integer MEDIA_FACE = 4;

integer LINK_ACH = 1;          // achievements media
integer LINK_BTN = 3;          // circle button (non-media)
integer LINK_HUD = 4;          // main HUD media
integer LINK_OWN = 2;          // owner media (optional new prim)

string  HUD_URL = "https://raylapetal.github.io/corruption-media-hud/";
string  ACH_URL = "https://raylapetal.github.io/corruption-media-hud/achievements.html";
string  OWN_URL = "https://raylapetal.github.io/corruption-media-hud/owner.html";

string  lastMsg  = "";         // last broadcast, re-pushed on view changes
integer expanded = FALSE;      // HUD shown?
integer achShown = FALSE;      // achievements panel shown?
integer ownShown = FALSE;      // owner panel shown?
string  ownerName  = "";       // current owner (from CorruptionMatch) — drives owner panel + button
string  ownerTasks = "";       // "type:count:progress:done;…"
string  gURL = "";             // inbound HTTPS endpoint (pages fetch it)
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
    llSetLinkMedia(LINK_OWN, MEDIA_FACE, mediaParams(OWN_URL));   // no-op if link 4 absent
}

// Remember each media prim's full size (persisted). Guard against a tiny cached value:
// if a prim was ever captured while hidden (TINY), it could never grow again — a value
// under 0.05 is treated as invalid and re-measured from the live prim.
vector capSize(string lsdKey, integer link, vector fallback) {
    vector v = (vector)llLinksetDataRead(lsdKey);
    if (llVecMag(v) >= 0.05) return v;                          // valid cached size
    v = llList2Vector(llGetLinkPrimitiveParams(link, [PRIM_SIZE]), 0);
    if (llVecMag(v) >= 0.05) { llLinksetDataWrite(lsdKey, (string)v); return v; }
    return fallback;                                            // prim currently tiny/hidden → sane size
}
captureSizes() {
    // Versioned keys (…2) drop stale cache from the old prim numbering; ach/own panels
    // share the main HUD's size; the HUD has a default so a tiny prim can't lock it small.
    fullHudSize = capSize("sz_hud2", LINK_HUD, <0.22, 0.16, 0.02>);
    fullAchSize = capSize("sz_ach2", LINK_ACH, fullHudSize);
    fullOwnSize = capSize("sz_own2", LINK_OWN, fullHudSize);
}

setVis(integer link, integer show, vector full) {
    vector s; float a;
    if (show) { s = full; a = 1.0; } else { s = TINY; a = 0.0; }
    llSetLinkPrimitiveParamsFast(link, [PRIM_SIZE, s, PRIM_COLOR, ALL_SIDES, <1.0,1.0,1.0>, a]);
}
applyVis() {
    scaleGuardUntil = llGetUnixTime() + 3;
    if (!expanded) { achShown = FALSE; ownShown = FALSE; }
    setVis(LINK_HUD, expanded, fullHudSize);
    setVis(LINK_ACH, expanded && achShown, fullAchSize);
    setVis(LINK_OWN, expanded && ownShown, fullOwnSize);
}

// Main + achievements pages read the same live data. (1024-char URL cap: only fields the
// pages read are sent.)
pushData(string msg) {
    list p = llParseStringKeepNulls(msg, ["|"], []);
    string json = llList2Json(JSON_OBJECT, [
        "xp", llList2String(p, 1),
        "lv", llList2String(p, 2),
        "pr", llList2String(p, 3),
        "tp", llList2String(p, 5),
        "th", llList2String(p, 6),
        "lc", llList2String(p, 10),
        "it", llList2String(p, 11),
        "pg", llList2String(p, 12),
        "lb", llList2String(p, 13),
        "lt", llList2String(p, 14),
        "ct", llList2String(p, 15),
        "cr", llList2String(p, 17),
        "cs", llList2String(p, 63),
        "hp", llList2String(p, 41),
        "oc", llList2String(p, 60),
        "nc", llList2String(p, 61),
        "zp", llList2String(p, 18),
        "za", llList2String(p, 19),
        "zf", llList2String(p, 20),
        "dx", llList2String(p, 21),
        "ac", llList2String(p, 22),
        "wx", llList2String(p, 23),
        "zc", llList2String(p, 24),
        "zb", llList2String(p, 25),
        "no", llList2String(p, 26),
        "ht", llList2String(p, 27),
        "mx", llList2String(p, 28),
        "dp", llList2String(p, 43),
        "dl", llList2String(p, 44),
        "wp", llList2String(p, 45),
        "wl", llList2String(p, 46),
        "ow", ownerName,             // owner name → index.html shows the "My Owner" button when set
        "ep", gURL,
        "nw", (string)llGetUnixTime()
    ]);
    p = [];
    string hash = "#" + llEscapeURL(json);
    llSetLinkMedia(LINK_HUD, MEDIA_FACE, [PRIM_MEDIA_CURRENT_URL, HUD_URL + hash]);
    llSetLinkMedia(LINK_ACH, MEDIA_FACE, [PRIM_MEDIA_CURRENT_URL, ACH_URL + hash]);
}

// Owner page gets its own (small) payload, pushed only when owner state changes.
pushOwner() {
    string oj = llList2Json(JSON_OBJECT, [ "ow", ownerName, "tk", ownerTasks, "ep", gURL ]);
    llSetLinkMedia(LINK_OWN, MEDIA_FACE, [PRIM_MEDIA_CURRENT_URL, OWN_URL + "#" + llEscapeURL(oj)]);
}

bootView() {
    expanded = (llLinksetDataRead("hud_exp") == "1");
    achShown = FALSE; ownShown = FALSE;
    applyVis();
}

requestURL() {
    if (gURL != "") { llReleaseURL(gURL); gURL = ""; }
    gURLReq = llRequestSecureURL();
}

default {
    state_entry()
    {
        setupMedia();
        llListen(HUD_CHAN, "", NULL_KEY, "");
        llListen(OWNER_HUD_CHAN, "", NULL_KEY, "");
        captureSizes();
        bootView();
        requestURL();
        llSetTimerEvent(15.0);
        if (lastMsg != "") { pushData(lastMsg); pushOwner(); }
    }

    attach(key id)
    {
        if (id != NULL_KEY) {
            setupMedia();
            captureSizes();
            bootView();
            requestURL();
            llSetTimerEvent(15.0);
            if (lastMsg != "") { pushData(lastMsg); pushOwner(); }
        }
    }

    timer()
    {
        if (gURL == "") requestURL();
    }

    touch_start(integer n)
    {
        if (llDetectedKey(0) != llGetOwner()) return;
        if (llDetectedLinkNumber(0) != LINK_BTN) return;
        expanded = !expanded;
        if (!expanded) { achShown = FALSE; ownShown = FALSE; }
        llLinksetDataWrite("hud_exp", (string)expanded);
        applyVis();
    }

    http_request(key id, string method, string body)
    {
        if (id == gURLReq) {
            if (method == URL_REQUEST_GRANTED) {
                gURL = body;
                if (lastMsg != "") pushData(lastMsg);
                pushOwner();
            }
            return;
        }
        string q = llGetHTTPHeader(id, "x-query-string");
        // Sex mode: relay the chosen intensity straight to inm_lovense (0 = off).
        integer sx = llSubStringIndex(q, "sex=");
        if (sx >= 0) {
            llRegionSayTo(llGetOwner(), SEX_CHAN, "sex|" + llGetSubString(q, sx + 4, sx + 4));
            llHTTPResponse(id, 200, "ok");
            return;
        }
        // Secondary panels — independent prims, only one open at a time.
        if      (llSubStringIndex(q, "ach=1") >= 0) { achShown = TRUE;  ownShown = FALSE; }
        else if (llSubStringIndex(q, "ach=0") >= 0) { achShown = FALSE; }
        else if (llSubStringIndex(q, "own=1") >= 0) { ownShown = TRUE;  achShown = FALSE; pushOwner(); }
        else if (llSubStringIndex(q, "own=0") >= 0) { ownShown = FALSE; }
        applyVis();
        llHTTPResponse(id, 200, "ok");
    }

    listen(integer chan, string name, key id, string msg)
    {
        if (llList2Key(llGetObjectDetails(id, [OBJECT_OWNER]), 0) != llGetOwner()) return;
        if (chan == OWNER_HUD_CHAN) {
            if (llSubStringIndex(msg, "ownr|") != 0) return;
            list p = llParseStringKeepNulls(msg, ["|"], []);
            ownerName  = llList2String(p, 1);
            ownerTasks = llList2String(p, 2);
            p = [];
            if (lastMsg != "") pushData(lastMsg);   // refresh the "My Owner" button on the main page
            pushOwner();                            // refresh the owner panel
            return;
        }
        if (chan != HUD_CHAN) return;
        if (llSubStringIndex(msg, "hud|") != 0) return;
        lastMsg = msg;
        pushData(msg);
    }

    changed(integer c)
    {
        if (c & (CHANGED_OWNER | CHANGED_INVENTORY)) { llResetScript(); return; }

        if (c & CHANGED_SCALE) {
            if (llGetUnixTime() < scaleGuardUntil) return;
            if (!expanded) return;
            fullHudSize = llList2Vector(llGetLinkPrimitiveParams(LINK_HUD, [PRIM_SIZE]), 0);
            llLinksetDataWrite("sz_hud2", (string)fullHudSize);
            if (achShown) {
                fullAchSize = llList2Vector(llGetLinkPrimitiveParams(LINK_ACH, [PRIM_SIZE]), 0);
                llLinksetDataWrite("sz_ach2", (string)fullAchSize);
            }
            if (ownShown) {
                fullOwnSize = llList2Vector(llGetLinkPrimitiveParams(LINK_OWN, [PRIM_SIZE]), 0);
                llLinksetDataWrite("sz_own2", (string)fullOwnSize);
            }
        }
    }
}
