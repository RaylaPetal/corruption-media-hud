// CorruptionMatch.lsl  —  SUB side of the matching / owner / tasks system.
// Lives in the monitor linkset (with CorruptionCore), like CorruptionDB.
//
// RESPONSIBILITIES
//   • Discovery + proposal handshake with Dom HUDs over MATCH_CHAN (region).
//   • Persists the owner bond (one owner only) and the owner's tasks in LSD.
//   • Tells CorruptionCore the owner name (OWNER_SET) so it can offer the
//     "<Owner>'s Slut" title (selectedTitleIdx 99).
//   • Tracks task progress from the same SPUNKED_EVENT packet the rest of the
//     HUD uses — a task advances only when the instigator IS the owner.
//   • Pushes owner+task state to the worn Media HUD's owner page (OWNER_HUD_CHAN).
//
// SHARED PROTOCOL (identical in DomMatch.lsl) — all region msgs on MATCH_CHAN:
//   scan|<role>|<uuid>                       broadcast: "who's nearby?"  (reply if OPPOSITE role)
//   here|<role>|<uuid>|<name>                directed reply to the scanner
//   offer|<role>|<uuid>|<name>|<kind>        directed proposal (kind = own | mate)
//   reply|<accept0/1>|<role>|<uuid>|<name>   directed answer to an offer
//   task|<type>|<count>                      owner → sub: set/replace a task (type = serve | breed)
//   taskclr                                  owner → sub: clear all tasks
//   unbind|<uuid>                            either side ends the bond
//   taskdone|<type>                          sub → owner: a task just completed

integer MATCH_CHAN      = -87460;  // region handshake (shared by both HUD types)
integer OWNER_HUD_CHAN  = -87434;  // → worn Media HUD owner page
integer HUD_CHAN        = -87432;  // Core's broadcast (we use it as a "everyone's up" boot signal)
integer SPUNKED_EVENT   = 90100;   // normalized cum packet (instigator = id)
integer DIALOG_TO_MATCH = 88021;   // CorruptionDialog → here
integer MATCH_TO_DIALOG = 88020;   // here → CorruptionDialog
integer OWNER_SET       = 88030;   // here → CorruptionCore: owner name ("" = unbound)

integer SCAN_SECS = 3;             // how long to gather scan replies (region chat is ~instant)

key     wearer;
key     owner    = NULL_KEY;       // our owner (a dom), if any
string  ownerNm  = "";
list    cands;                     // transient scan results: "name=uuid" entries
key     offerFrom = NULL_KEY;      // a dom who proposed, awaiting our accept/deny
string  offerName = "";
string  offerKind = "own";        // kind of the pending INCOMING offer (own | mate)
string  pendingKind = "own";      // kind of the offer WE sent out
list    tasks;                     // each: "type:count:progress:done"
integer scanning = FALSE;
integer pushedOwner = FALSE;       // re-pushed the owner page once after the Media HUD is up

// region-chat `id` is the SENDING OBJECT's key — resolve the avatar behind it
// (reliable for OTHER avatars' objects; we never message our own here).
key senderAv(key id) { return llList2Key(llGetObjectDetails(id, [OBJECT_OWNER]), 0); }

// commas/pipes/colons are our delimiters — keep names free of them
string clean(string s) {
    return llDumpList2String(llParseString2List(s, [",", "|", ":", "="], []), " ");
}
string shortName(key k) {
    string n = llGetDisplayName(k);
    integer sp = llSubStringIndex(n, " ");
    if (sp > 0) n = llGetSubString(n, 0, sp - 1);   // first name keeps the title compact
    return clean(n);
}

saveBond() {
    if (owner == NULL_KEY) llLinksetDataDelete("match_owner");
    else llLinksetDataWrite("match_owner", (string)owner + "|" + ownerNm);
}
saveTasks() { llLinksetDataWrite("match_tasks", llDumpList2String(tasks, ";")); }

pushOwnerPage() {
    string ts = llDumpList2String(tasks, ";");
    // region say so the SEPARATE worn Media HUD object hears it (our own owner panel)
    llRegionSay(OWNER_HUD_CHAN, "ownr|" + ownerNm + "|" + ts);
    // mirror our task progress to the owner so their HUD can show it live
    if (owner != NULL_KEY) llRegionSayTo(owner, MATCH_CHAN, "tasks|" + ts);
}

notifyOwnerName() {
    llMessageLinked(LINK_SET, OWNER_SET, ownerNm, NULL_KEY);   // "" clears it
}

// A "mate" match is just a hookup — no owner bond, allowed even while owned.
hookup(string nm) {
    llOwnerSay("💕 You and " + nm + " are hooking up — no strings, just fun.");
}

formBond(key dom, string nm) {
    owner = dom; ownerNm = clean(nm);
    tasks = [];                       // fresh owner → fresh task slate
    saveBond(); saveTasks();
    notifyOwnerName();
    pushOwnerPage();
    llMessageLinked(LINK_SET, MATCH_TO_DIALOG, "bond|" + ownerNm, NULL_KEY);
    llOwnerSay("💞 You now belong to " + ownerNm + ". A new title and their tasks await.");
}

breakBond(integer tellPartner) {
    if (tellPartner && owner != NULL_KEY) llRegionSayTo(owner, MATCH_CHAN, "unbind|" + (string)wearer);
    owner = NULL_KEY; ownerNm = ""; tasks = [];
    saveBond(); saveTasks();
    notifyOwnerName();
    pushOwnerPage();
    llMessageLinked(LINK_SET, MATCH_TO_DIALOG, "unbond", NULL_KEY);
    llOwnerSay("⛓ You are no longer owned.");
}

// advance tasks when the instigator is our owner. loads>0 = "serve", creampie = "breed".
progressTasks(integer loads, integer creampie) {
    integer i; integer isChanged = FALSE;
    for (i = 0; i < llGetListLength(tasks); i++) {
        list t = llParseString2List(llList2String(tasks, i), [":"], []);
        string type = llList2String(t, 0);
        integer count = (integer)llList2String(t, 1);
        integer prog  = (integer)llList2String(t, 2);
        integer done  = (integer)llList2String(t, 3);
        if (done) jump next;
        integer add = 0;
        if (type == "serve" && loads > 0) add = 1;
        else if (type == "breed" && creampie) add = 1;
        if (add) {
            prog += add;
            if (prog >= count) { prog = count; done = 1;
                llRegionSayTo(owner, MATCH_CHAN, "taskdone|" + type);
                llOwnerSay("✅ Task complete for " + ownerNm + ": " + type + " " + (string)count + "×.");
            }
            tasks = llListReplaceList(tasks,
                [type + ":" + (string)count + ":" + (string)prog + ":" + (string)done], i, i);
            isChanged = TRUE;
        }
        @next;
    }
    if (isChanged) { saveTasks(); pushOwnerPage(); }
}

default {
    state_entry() {
        wearer = llGetOwner();
        llListen(MATCH_CHAN, "", NULL_KEY, "");
        string b = llLinksetDataRead("match_owner");
        if (b != "") { list p = llParseString2List(b, ["|"], []);
            owner = (key)llList2String(p, 0); ownerNm = llList2String(p, 1); }
        string tk = llLinksetDataRead("match_tasks");
        if (tk != "") tasks = llParseString2List(tk, [";"], []);
        notifyOwnerName();      // re-assert the bond to Core after any reset/relog
        pushOwnerPage();
    }

    attach(key id) { if (id != NULL_KEY) llResetScript(); }

    link_message(integer sn, integer num, string str, key id) {
        if (num == HUD_CHAN) {   // first Core broadcast → the Media HUD's owner listener is up now
            if (!pushedOwner) { pushedOwner = TRUE; pushOwnerPage(); }
            return;
        }
        if (num == SPUNKED_EVENT) {
            if (id != owner || owner == NULL_KEY) return;      // only OUR owner's loads count
            list p = llParseStringKeepNulls(str, ["|"], []);
            integer loads = 0; integer i;
            for (i = 10; i <= 19; i++) if ((integer)llList2String(p, i) > 0) loads++;
            integer creampie = (((integer)llList2String(p, 17) > 0)
                             || ((integer)llList2String(p, 18) > 0)
                             || ((integer)llList2String(p, 19) > 0));
            p = [];
            if (loads > 0) progressTasks(loads, creampie);
            return;
        }
        if (num != DIALOG_TO_MATCH) return;
        list c = llParseString2List(str, ["|"], []);
        string cmd = llList2String(c, 0);
        if (cmd == "scan") {
            cands = []; scanning = TRUE;
            llRegionSay(MATCH_CHAN, "scan|sub|" + (string)wearer);
            llSetTimerEvent((float)SCAN_SECS);
        }
        else if (cmd == "offer") {                              // we picked a dom from the list
            key tgt = (key)llList2String(c, 1);
            string knd = llList2String(c, 3); if (knd == "") knd = "own";
            if (knd == "own" && owner != NULL_KEY) {
                llOwnerSay("You already belong to " + ownerNm + ". Leave them first, or use Find a Mate.");
                return;
            }
            pendingKind = knd;
            llRegionSayTo(tgt, MATCH_CHAN,
                "offer|sub|" + (string)wearer + "|" + shortName(wearer) + "|" + knd);
            llOwnerSay("Proposal sent — waiting for them to accept…");
        }
        else if (cmd == "accept") {                             // accept an incoming dom offer
            if (offerFrom == NULL_KEY) return;
            if (offerKind == "own" && owner != NULL_KEY) {      // can't take a 2nd owner
                llRegionSayTo(offerFrom, MATCH_CHAN, "reply|0|sub|" + (string)wearer + "|x|" + offerKind);
                offerFrom = NULL_KEY; return;
            }
            llRegionSayTo(offerFrom, MATCH_CHAN,
                "reply|1|sub|" + (string)wearer + "|" + shortName(wearer) + "|" + offerKind);
            if (offerKind == "own") formBond(offerFrom, offerName);
            else                    hookup(offerName);
            offerFrom = NULL_KEY;
        }
        else if (cmd == "deny") {
            if (offerFrom != NULL_KEY)
                llRegionSayTo(offerFrom, MATCH_CHAN, "reply|0|sub|" + (string)wearer + "|x|" + offerKind);
            offerFrom = NULL_KEY;
        }
        else if (cmd == "unbind") breakBond(TRUE);
    }

    timer() {
        llSetTimerEvent(0.0);
        scanning = FALSE;
        llMessageLinked(LINK_SET, MATCH_TO_DIALOG, "cands|" + llDumpList2String(cands, "|"), NULL_KEY);
    }

    listen(integer chan, string nm, key id, string msg) {
        if (chan != MATCH_CHAN) return;
        list p = llParseString2List(msg, ["|"], []);
        string t = llList2String(p, 0);

        if (t == "scan") {                                      // a dom is scanning → answer
            if (llList2String(p, 1) != "dom") return;           // opposite role only
            key from = (key)llList2String(p, 2);
            if (from == wearer) return;
            llRegionSayTo(from, MATCH_CHAN, "here|sub|" + (string)wearer + "|" + shortName(wearer));
        }
        else if (t == "here" && scanning) {                     // a dom answered our scan
            if (llList2String(p, 1) != "dom") return;
            string entry = llList2String(p, 3) + "=" + llList2String(p, 2);
            if (llListFindList(cands, [entry]) == -1 && llGetListLength(cands) < 11) cands += [entry];
        }
        else if (t == "offer") {                                // a dom proposes to us
            if (llList2String(p, 1) != "dom") return;
            string knd = llList2String(p, 4); if (knd == "") knd = "own";
            if (knd == "own" && owner != NULL_KEY) {            // already owned; mates are fine
                llRegionSayTo((key)llList2String(p, 2), MATCH_CHAN, "reply|0|sub|" + (string)wearer + "|x|" + knd);
                return;
            }
            offerFrom = (key)llList2String(p, 2);
            offerName = llList2String(p, 3);
            offerKind = knd;
            llMessageLinked(LINK_SET, MATCH_TO_DIALOG,
                "incoming|" + offerName + "|" + knd, NULL_KEY);
        }
        else if (t == "reply") {                                // answer to OUR offer
            if (llList2String(p, 2) != "dom") return;
            string knd = llList2String(p, 5); if (knd == "") knd = pendingKind;
            if ((integer)llList2String(p, 1) == 1) {
                if (knd == "own") formBond((key)llList2String(p, 3), llList2String(p, 4));
                else              hookup(llList2String(p, 4));
            } else llOwnerSay("They declined.");
        }
        else if (t == "task") {                                 // owner sets a task
            if (owner == NULL_KEY || senderAv(id) != owner) return;
            string type = llList2String(p, 1);
            integer cnt = (integer)llList2String(p, 2); if (cnt < 1) cnt = 1;
            // replace an existing task of the same type, else append
            integer i; integer found = FALSE;
            for (i = 0; i < llGetListLength(tasks); i++)
                if (llSubStringIndex(llList2String(tasks, i), type + ":") == 0) {
                    tasks = llListReplaceList(tasks, [type + ":" + (string)cnt + ":0:0"], i, i);
                    found = TRUE;
                }
            if (!found) tasks += [type + ":" + (string)cnt + ":0:0"];
            saveTasks(); pushOwnerPage();
            llOwnerSay("📋 " + ownerNm + " set a task: " + type + " " + (string)cnt + "×.");
        }
        else if (t == "taskclr") { if (owner != NULL_KEY && senderAv(id) == owner) {
            tasks = []; saveTasks(); pushOwnerPage(); llOwnerSay(ownerNm + " cleared your tasks."); } }
        else if (t == "unbind") { if (owner != NULL_KEY && senderAv(id) == owner) breakBond(FALSE); }
    }

    changed(integer c) {
        if (c & CHANGED_OWNER) { llLinksetDataDelete("match_owner"); llLinksetDataDelete("match_tasks"); llResetScript(); return; }
        if (c & CHANGED_INVENTORY) llResetScript();
    }
}