integer HUD_CHAN   = -87432;   // must match inm_monitor
integer DB_RESTORE = 88003;    // → core: blob rehydrated, reload it
integer DB_FLUSH   = 88004;    // core → here: upload this exact snapshot now (reset)

string  SUPA_URL = "https://nvaxbkqyggwfkowrtekx.supabase.co/rest/v1/players";
string  SUPA_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im52YXhia3F5Z2d3Zmtvd3J0ZWt4Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODAzMTEyMDUsImV4cCI6MjA5NTg4NzIwNX0.-HrF4QK56BCJglhJEr2qNeTkR894RTcpYe6jStg7S_g";

integer IDLE_WAIT = 360;       // upload after this many seconds of NO relevant change (debounce)
integer MAX_WAIT  = 1800;      // safety cap: upload at least this often while changes keep coming

string  pending    = "";       // latest full broadcast (source for columns + name)
string  lastSig    = "";       // leaderboard fields at last UPLOAD
string  curSig     = "";       // leaderboard fields in latest broadcast
integer changeTime = 0;        // when curSig last changed (debounce anchor)
integer burstStart = 0;        // when the current run of unsaved changes began (for MAX_WAIT)

integer ready      = FALSE;    // uploads held until the restore attempt resolves
key     restoreReq = NULL_KEY; // in-flight GET so http_response can tell it apart

integer DEBUG = FALSE;          // TEMP: chat diagnostics; set FALSE for release
integer heard = 0;             // TEMP: count broadcasts heard

list supaHeaders() {
    return [
        HTTP_CUSTOM_HEADER, "apikey",        SUPA_KEY,
        HTTP_CUSTOM_HEADER, "Authorization", "Bearer " + SUPA_KEY
    ];
}

// Just the fields that matter to the leaderboard, from Core's broadcast:
// 1 xp, 2 level, 3 prestige, 5 totalCount(partners), 6 totalHits(loads),
// 15 curTitle, 22 achFlags, 26 notoriety, 37 difficulty.
string sigOf(list p) {
    return llList2String(p, 1) + "|" + llList2String(p, 2) + "|" +
           llList2String(p, 3) + "|" + llList2String(p, 5) + "|" +
           llList2String(p, 6) + "|" + llList2String(p, 15) + "|" +
           llList2String(p, 22) + "|" + llList2String(p, 26) + "|" +
           llList2String(p, 37);   // difficulty — re-upload when it changes
}

// New/empty object → ask the DB for this avatar's saved blob.
tryRestore() {
    // Restore only "when needed": keep local ONLY if it holds REAL progress
    // (xp != 0, blob index 7). A fresh / zeroed / copied blob is worthless, so
    // pull the cloud save. Avoids clobbering newer local with the older cloud copy.
    string d = llLinksetDataRead("inm_state");
    if (d != "" && (integer)llList2String(llParseString2List(d, [","], []), 7) > 0) {
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
        "uuid",     (string)owner,
        "name",     llGetDisplayName(owner),
        "xp",       llList2String(p, 1),   // current total xp (resets on prestige; leaderboard breaks ties with it)
        "level",    llList2String(p, 2),
        "prestige", llList2String(p, 3),
        "partners",  llList2String(p, 5),
        "loads",     llList2String(p, 6),
        "title",     llList2String(p, 15),
        "ach",       llList2String(p, 22),
        "notoriety", llList2String(p, 26),
        "difficulty", llList2String(p, 37),            // 0 Tease / 1 Naughty / 2 Slut / 3 Custom
        "save",      llLinksetDataRead("inm_state")   // full blob for cross-update restore
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
        llListen(HUD_CHAN, "", NULL_KEY, "");
        tryRestore();
        llSetTimerEvent(30.0);
        if (DEBUG) llOwnerSay("[DB] start. localData=" +
            (string)(llLinksetDataRead("inm_state") != "") + " ready=" + (string)ready);
    }
    
    attach(key id) {
        llListen(HUD_CHAN, "", NULL_KEY, "");
        tryRestore();
        llSetTimerEvent(30.0);
        if (DEBUG) llOwnerSay("[DB] start. localData=" +
            (string)(llLinksetDataRead("inm_state") != "") + " ready=" + (string)ready);
    }

    link_message(integer sender_num, integer num, string msg, key id)
    {
        if (num == DB_FLUSH) {
            // Core's authoritative snapshot (e.g. the zeroed reset state).
            // Upload it now, bypassing the debounce.
            if (!ready) return;        // restore not resolved; debounce will catch it
            upload(msg);
            pending    = msg;
            curSig     = sigOf(llParseString2List(msg, ["|"], []));
            lastSig    = curSig;       // mark saved so the debounce won't repeat it
            burstStart = 0;
            if (DEBUG) llOwnerSay("[DB] flush upload (forced snapshot).");
            return;
        }

        if (num != HUD_CHAN) return;
        if (llSubStringIndex(msg, "hud|") != 0) return;

        pending = msg;

        list p = llParseString2List(msg, ["|"], []);

        string sig = sigOf(p);

        if (sig != curSig)
        {
            curSig     = sig;
            changeTime = llGetUnixTime();

            if (curSig != lastSig && burstStart == 0)
                burstStart = changeTime;
        }

        if (DEBUG && heard == 0)
        {
            heard = 1;
            llOwnerSay("[DB] heard link message. sig=" + sig);
        }
    }

    timer() {
        if (!ready) {
            if (restoreReq == NULL_KEY) tryRestore();   // retry until the row is read (no clobber)
            if (DEBUG) llOwnerSay("[DB] timer: waiting on restore…");
            return;
        }
        if (curSig == lastSig) { if (DEBUG) llOwnerSay("[DB] timer: no leaderboard change to save"); return; }
        integer now = llGetUnixTime();
        if (now - changeTime >= IDLE_WAIT || (burstStart && now - burstStart >= MAX_WAIT)) {
            if (DEBUG) llOwnerSay("[DB] uploading now...");
            upload(pending);
            lastSig    = curSig;
            burstStart = 0;
        } else if (DEBUG) {
            llOwnerSay("[DB] timer: debounce " + (string)(now - changeTime) + "/" + (string)IDLE_WAIT + "s");
        }
    }

    http_response(key id, integer status, list meta, string body) {
        if (id == restoreReq) {
            restoreReq = NULL_KEY;
            // CRITICAL: do NOT enable uploads unless we actually READ the row.
            // Otherwise a failed lookup would let the boot-default (Lv.1) upload
            // and clobber the saved row — then every restore brings back Lv.1.
            if (status != 200) {
                llOwnerSay("[DB] restore lookup failed (" + (string)status + ") — holding uploads, will retry");
                return;   // ready stays FALSE; the timer retries
            }
            string blob = llJsonGetValue(body, [0, "save"]);
            if (blob != JSON_INVALID && blob != JSON_NULL && blob != "") {
                llLinksetDataWrite("inm_state", blob);
                llMessageLinked(LINK_SET, DB_RESTORE, "", NULL_KEY);
                pending = ""; curSig = ""; lastSig = "";   // drop the stale Lv.1 boot snapshot
                if (DEBUG) llOwnerSay("[DB] restored from cloud backup.");
            } else if (DEBUG) {
                llOwnerSay("[DB] no saved row for this avatar — starting fresh.");
            }
            ready = TRUE;     // read confirmed (restored, or genuinely new) → uploads allowed
            return;
        }
        if (DEBUG) llOwnerSay("[DB] upload http status=" + (string)status);
        if (status != 200 && status != 201)
            llOwnerSay("[DB] upload failed (" + (string)status + "): " + body);
    }

    changed(integer c) {
        if (c & CHANGED_OWNER) {
            // New owner → the local save belongs to the previous owner. Drop it so
            // tryRestore fetches THIS owner's cloud save (or starts fresh).
            llLinksetDataDelete("inm_state");
            llResetScript();
            return;
        }
        if (c & CHANGED_INVENTORY) llResetScript();
    }
}
