// DomMatch.lsl  —  DOM side of the matching / owner / tasks system.
// Lives in the Dom HUD linkset (with DomCore), mirrors CorruptionMatch.
//
// RESPONSIBILITIES
//   • Discovery + proposal handshake with Sub HUDs over MATCH_CHAN (region).
//   • Persists the ONE owned sub (symmetric with the sub's one-owner rule).
//   • Tells DomCore whether a sub is owned (DOM_OWN_COUNT → subsOwned stat).
//   • Sets / clears tasks on the owned sub, mirrors their task progress back,
//     and pushes owner state to the Dom Media HUD's owned-sub page.
//
// SHARED PROTOCOL (see CorruptionMatch.lsl) — region msgs on MATCH_CHAN:
//   scan / here / offer / reply / task / taskclr / unbind / taskdone / tasks

integer MATCH_CHAN      = -87460;
integer DOM_OWNER_HUD_CHAN = -87441; // → Dom Media HUD owned-sub page
integer DOM_HUD_CHAN    = -87440;    // DomCore broadcast (boot "everyone's up" signal)
integer DIALOG_TO_MATCH = 88021;     // DomDialog → here
integer MATCH_TO_DIALOG = 88020;     // here → DomDialog
integer DOM_OWN_COUNT   = 88031;     // here → DomCore: 0/1 owned

integer SCAN_SECS = 3;   // region replies are ~instant; this just collects them

key     wearer;
key     ownedSub = NULL_KEY;       // the sub we own (one only)
string  ownedName = "";
string  subTasks  = "";            // mirrored from the sub: "type:count:progress:done;…"
list    cands;                     // transient scan results
key     offerFrom = NULL_KEY;      // a sub awaiting our accept/deny
string  offerName = "";
string  offerKind = "own";        // kind of the pending INCOMING offer (own | mate)
string  pendingKind = "own";      // kind of the offer WE sent out
integer scanning = FALSE;
integer pushedOwner = FALSE;

// region-chat `id` is the SENDING OBJECT's key — resolve the avatar behind it.
key senderAv(key id) { return llList2Key(llGetObjectDetails(id, [OBJECT_OWNER]), 0); }

string clean(string s) {
    return llDumpList2String(llParseString2List(s, [",", "|", ":", "="], []), " ");
}
string shortName(key k) {
    string n = llGetDisplayName(k);
    integer sp = llSubStringIndex(n, " ");
    if (sp > 0) n = llGetSubString(n, 0, sp - 1);
    return clean(n);
}

pushOwnerPage() {
    llRegionSay(DOM_OWNER_HUD_CHAN, "ownr|" + ownedName + "|" + subTasks);
}

// Persist the single owned sub + tell DomCore ("<name>|<key>", empty name = released).
saveBond() {
    if (ownedSub == NULL_KEY) llLinksetDataDelete("dom_owned");
    else llLinksetDataWrite("dom_owned", (string)ownedSub + "|" + ownedName);
    llMessageLinked(LINK_SET, DOM_OWN_COUNT, ownedName + "|" + (string)ownedSub, NULL_KEY);
}

// A "mate" match is just a hookup — no ownership, no persistence, allowed even when owned.
hookup(string nm) {
    llOwnerSay("💕 You and " + nm + " are hooking up — no strings, just fun.");
}

formBond(key sub, string nm) {
    if (ownedSub != NULL_KEY) return;            // one sub only
    ownedSub = sub; ownedName = clean(nm); subTasks = "";
    saveBond(); pushOwnerPage();
    llMessageLinked(LINK_SET, MATCH_TO_DIALOG, "bond|" + ownedName, NULL_KEY);
    llOwnerSay("⛓ " + ownedName + " is now yours. Set them tasks from Owned Sub.");
}
release(integer tellSub) {
    if (ownedSub == NULL_KEY) return;
    if (tellSub) llRegionSayTo(ownedSub, MATCH_CHAN, "unbind|" + (string)wearer);
    llOwnerSay("Released " + ownedName + ".");
    ownedSub = NULL_KEY; ownedName = ""; subTasks = "";
    saveBond(); pushOwnerPage();
    llMessageLinked(LINK_SET, MATCH_TO_DIALOG, "unbond", NULL_KEY);
}

default {
    state_entry() {
        wearer = llGetOwner();
        llListen(MATCH_CHAN, "", NULL_KEY, "");
        string o = llLinksetDataRead("dom_owned");
        if (o != "") { list p = llParseString2List(o, ["|"], []);
            ownedSub = (key)llList2String(p, 0); ownedName = llList2String(p, 1); }
        llMessageLinked(LINK_SET, DOM_OWN_COUNT, ownedName + "|" + (string)ownedSub, NULL_KEY);
    }

    attach(key id) { if (id != NULL_KEY) llResetScript(); }

    link_message(integer sn, integer num, string str, key id) {
        if (num == DOM_HUD_CHAN) {   // first DomCore broadcast → Media HUD owner listener is up
            if (!pushedOwner) { pushedOwner = TRUE; pushOwnerPage(); }
            return;
        }
        if (num != DIALOG_TO_MATCH) return;
        list c = llParseString2List(str, ["|"], []);
        string cmd = llList2String(c, 0);
        if (cmd == "scan") {
            cands = []; scanning = TRUE;
            llRegionSay(MATCH_CHAN, "scan|dom|" + (string)wearer);
            llSetTimerEvent((float)SCAN_SECS);
        }
        else if (cmd == "offer") {
            key tgt = (key)llList2String(c, 1);
            string knd = llList2String(c, 3); if (knd == "") knd = "own";
            if (knd == "own" && ownedSub != NULL_KEY) {
                llOwnerSay("You already own " + ownedName + ". Release them first, or use Find a Mate.");
                return;
            }
            pendingKind = knd;
            llRegionSayTo(tgt, MATCH_CHAN,
                "offer|dom|" + (string)wearer + "|" + shortName(wearer) + "|" + knd);
            llOwnerSay("Proposal sent — waiting for them to accept…");
        }
        else if (cmd == "accept") {
            if (offerFrom == NULL_KEY) return;
            if (offerKind == "own" && ownedSub != NULL_KEY) {   // can't take a 2nd owned sub
                llRegionSayTo(offerFrom, MATCH_CHAN, "reply|0|dom|" + (string)wearer + "|x|" + offerKind);
                offerFrom = NULL_KEY; return;
            }
            llRegionSayTo(offerFrom, MATCH_CHAN,
                "reply|1|dom|" + (string)wearer + "|" + shortName(wearer) + "|" + offerKind);
            if (offerKind == "own") formBond(offerFrom, offerName);
            else                    hookup(offerName);
            offerFrom = NULL_KEY;
        }
        else if (cmd == "deny") {
            if (offerFrom != NULL_KEY)
                llRegionSayTo(offerFrom, MATCH_CHAN, "reply|0|dom|" + (string)wearer + "|x|" + offerKind);
            offerFrom = NULL_KEY;
        }
        else if (cmd == "list") {                       // dialog wants the owned sub (0/1)
            string roster = "";
            if (ownedSub != NULL_KEY) roster = ownedName + "=" + (string)ownedSub;
            llMessageLinked(LINK_SET, MATCH_TO_DIALOG, "owned|" + roster, NULL_KEY);
        }
        else if (cmd == "task") {                       // task|<subUUID>|<type>|<count>
            if (ownedSub == NULL_KEY) return;
            llRegionSayTo(ownedSub, MATCH_CHAN, "task|" + llList2String(c, 2) + "|" + llList2String(c, 3));
            llOwnerSay("Task assigned to " + ownedName + ".");
        }
        else if (cmd == "taskclr") {
            if (ownedSub != NULL_KEY) llRegionSayTo(ownedSub, MATCH_CHAN, "taskclr");
        }
        else if (cmd == "release") release(TRUE);
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

        if (t == "scan") {                              // a sub is scanning → answer
            if (llList2String(p, 1) != "sub") return;
            key from = (key)llList2String(p, 2);
            if (from == wearer) return;
            llRegionSayTo(from, MATCH_CHAN, "here|dom|" + (string)wearer + "|" + shortName(wearer));
        }
        else if (t == "here" && scanning) {
            if (llList2String(p, 1) != "sub") return;
            string entry = llList2String(p, 3) + "=" + llList2String(p, 2);
            if (llListFindList(cands, [entry]) == -1 && llGetListLength(cands) < 11) cands += [entry];
        }
        else if (t == "offer") {                        // a sub proposes to us
            if (llList2String(p, 1) != "sub") return;
            string knd = llList2String(p, 4); if (knd == "") knd = "own";
            if (knd == "own" && ownedSub != NULL_KEY) {  // can't be claimed by a 2nd; mates are fine
                llRegionSayTo((key)llList2String(p, 2), MATCH_CHAN, "reply|0|dom|" + (string)wearer + "|x|" + knd);
                return;
            }
            offerFrom = (key)llList2String(p, 2);
            offerName = llList2String(p, 3);
            offerKind = knd;
            llMessageLinked(LINK_SET, MATCH_TO_DIALOG,
                "incoming|" + offerName + "|" + knd, NULL_KEY);
        }
        else if (t == "reply") {                        // answer to OUR offer
            if (llList2String(p, 2) != "sub") return;
            string knd = llList2String(p, 5); if (knd == "") knd = pendingKind;
            if ((integer)llList2String(p, 1) == 1) {
                if (knd == "own") formBond((key)llList2String(p, 3), llList2String(p, 4));
                else              hookup(llList2String(p, 4));
            } else llOwnerSay("They declined.");
        }
        else if (t == "tasks") {                        // owned sub mirrored their task state
            if (ownedSub == NULL_KEY || senderAv(id) != ownedSub) return;
            subTasks = llList2String(p, 1);             // the task string has no "|", so it's p[1]
            pushOwnerPage();
        }
        else if (t == "taskdone") {                     // owned sub finished a task
            if (ownedSub == NULL_KEY || senderAv(id) != ownedSub) return;
            llOwnerSay("✅ " + ownedName + " completed a task (" + llList2String(p, 1) + ") for you.");
        }
        else if (t == "unbind") {                       // the sub left us
            if (ownedSub != NULL_KEY && senderAv(id) == ownedSub) release(FALSE);
        }
    }

    changed(integer c) {
        if (c & CHANGED_OWNER) { llLinksetDataDelete("dom_owned"); llResetScript(); return; }
        if (c & CHANGED_INVENTORY) llResetScript();
    }
}
