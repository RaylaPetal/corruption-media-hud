// DomDB.lsl — Supabase leaderboard + cloud backup for the DOM HUD.
// EXACT mirror of CorruptionDB: the broadcast arrives as a LINK MESSAGE (DomCore and this
// script share the brain linkset and DomCore does llMessageLinked(LINK_SET, DOM_HUD_CHAN)),
// NOT via region listen. Uploads dom stats to the `doms` table and backs up the dom_state blob.

integer DOM_HUD_CHAN   = -87440;   // DomCore broadcast (link message + region say)
integer DOM_DB_RESTORE = 88013;    // → DomCore: blob rehydrated, reload it
integer DOM_DB_FLUSH   = 88014;    // DomCore → here: upload this exact snapshot now (reset)

string  SUPA_URL = "https://nvaxbkqyggwfkowrtekx.supabase.co/rest/v1/doms";
string  SUPA_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im52YXhia3F5Z2d3Zmtvd3J0ZWt4Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODAzMTEyMDUsImV4cCI6MjA5NTg4NzIwNX0.-HrF4QK56BCJglhJEr2qNeTkR894RTcpYe6jStg7S_g";

integer IDLE_WAIT = 360;
integer MAX_WAIT  = 1800;

string  pending    = "";
string  lastSig    = "";
string  curSig     = "";
integer changeTime = 0;
integer burstStart = 0;

integer ready      = FALSE;
key     restoreReq = NULL_KEY;

list supaHeaders() {
    return [
        HTTP_CUSTOM_HEADER, "apikey",        SUPA_KEY,
        HTTP_CUSTOM_HEADER, "Authorization", "Bearer " + SUPA_KEY
    ];
}

// Leaderboard fields from the dhud broadcast: 1 xp, 2 level, 4 conquests, 5 loads,
// 6 bred, 7 infamy, 12 curTitle, 14 achFlags, 22 domPrestige.
string sigOf(list p) {
    return llList2String(p, 1) + "|" + llList2String(p, 2) + "|" + llList2String(p, 4) + "|" +
           llList2String(p, 5) + "|" + llList2String(p, 6) + "|" + llList2String(p, 7) + "|" +
           llList2String(p, 12) + "|" + llList2String(p, 14) + "|" + llList2String(p, 22);
}

tryRestore() {
    // keep local ONLY if it holds real progress (domXP = blob field 0)
    string d = llLinksetDataRead("dom_state");
    if (d != "" && (integer)llList2String(llParseString2List(d, [","], []), 0) > 0) {
        ready = TRUE;
        return;
    }
    string url = SUPA_URL + "?uuid=eq." + (string)llGetOwner() + "&select=save";
    restoreReq = llHTTPRequest(url, [HTTP_METHOD, "GET"] + supaHeaders(), "");
}

upload(string msg) {
    list p = llParseString2List(msg, ["|"], []);
    key owner = llGetOwner();
    string body = llList2Json(JSON_OBJECT, [
        "uuid",      (string)owner,
        "name",      llGetDisplayName(owner),
        "xp",        llList2String(p, 1),
        "level",     llList2String(p, 2),
        "conquests", llList2String(p, 4),
        "loads",     llList2String(p, 5),
        "bred",      llList2String(p, 6),
        "infamy",    llList2String(p, 7),
        "title",     llList2String(p, 12),
        "ach",       llList2String(p, 14),
        "prestige",  llList2String(p, 22),
        "save",      llLinksetDataRead("dom_state")
    ]);
    p = [];
    llHTTPRequest(SUPA_URL, [
        HTTP_METHOD,        "POST",
        HTTP_MIMETYPE,      "application/json",
        HTTP_CUSTOM_HEADER, "Prefer", "resolution=merge-duplicates"
    ] + supaHeaders(), body);
}

default {
    state_entry() {
        tryRestore();
        llSetTimerEvent(30.0);
    }

    attach(key id) {
        if (id != NULL_KEY) {
            tryRestore();
            llSetTimerEvent(30.0);
        }
    }

    link_message(integer sender_num, integer num, string msg, key id)
    {
        if (num == DOM_DB_FLUSH) {
            if (!ready) return;
            upload(msg);
            pending    = msg;
            curSig     = sigOf(llParseString2List(msg, ["|"], []));
            lastSig    = curSig;
            burstStart = 0;
            return;
        }

        if (num != DOM_HUD_CHAN) return;
        if (llSubStringIndex(msg, "dhud|") != 0) return;

        pending = msg;
        string sig = sigOf(llParseString2List(msg, ["|"], []));
        if (sig != curSig) {
            curSig     = sig;
            changeTime = llGetUnixTime();
            if (curSig != lastSig && burstStart == 0) burstStart = changeTime;
        }
    }

    timer() {
        if (!ready) {
            if (restoreReq == NULL_KEY) tryRestore();
            return;
        }
        if (curSig == lastSig) return;
        integer now = llGetUnixTime();
        if (now - changeTime >= IDLE_WAIT || (burstStart && now - burstStart >= MAX_WAIT)) {
            upload(pending);
            lastSig    = curSig;
            burstStart = 0;
        }
    }

    http_response(key id, integer status, list meta, string body) {
        if (id == restoreReq) {
            restoreReq = NULL_KEY;
            if (status != 200) {
                llOwnerSay("[domDB] restore lookup failed (" + (string)status + ") — holding uploads, will retry");
                return;
            }
            string blob = llJsonGetValue(body, [0, "save"]);
            if (blob != JSON_INVALID && blob != JSON_NULL && blob != "") {
                llLinksetDataWrite("dom_state", blob);
                llMessageLinked(LINK_SET, DOM_DB_RESTORE, "", NULL_KEY);
                pending = ""; curSig = ""; lastSig = "";
            }
            ready = TRUE;
            return;
        }
        if (status != 200 && status != 201)
            llOwnerSay("[domDB] upload failed (" + (string)status + "): " + body);
    }

    changed(integer c) {
        if (c & CHANGED_OWNER) {
            llLinksetDataDelete("dom_state");
            llResetScript();
            return;
        }
        if (c & CHANGED_INVENTORY) llResetScript();
    }
}
