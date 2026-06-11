// inm_spunked.lsl — Spunked cum system relay
// Listens on the Spunked passive report channel, parses SpunkedReportV3 /
// SpunkedResponseV3, and forwards pre-extracted values to inm_core via
// link_message. All game logic lives in inm_core; this script is a thin bridge.

integer SPUNKED_CHAN     = 4954; // reports/responses FROM Spunked
integer SPUNKED_CMD_CHAN = 4953; // queries TO Spunked
integer SPUNKED_EVENT    = 90100; // passive report (deltas) → core
integer SPUNKED_SYNC     = 90101; // query reply (current state) → core

// Ask Spunked for the wearer's current cum state (reply on SPUNKED_CHAN).
requestState() {
    llSay(SPUNKED_CMD_CHAN, "Request*InTotalEncodedV2*" + (string)llGetOwner());
}

default {
    state_entry() {
        llListen(SPUNKED_CHAN, "", NULL_KEY, "");
        requestState();
    }

    attach(key id) {
        if (id != NULL_KEY) requestState(); // re-sync on (re)attach
    }

    listen(integer channel, string name, key id, string msg) {
        // Only accept messages from the wearer's own Spunked system
        key owner = llGetOwner();
        if (llGetOwnerKey(id) != owner && id != owner) return;

        list cmds = llParseString2List(msg, ["*"], []);
        string kw = llList2String(cmds, 0);

        if (kw == "SpunkedReportV3") {
            // Passive state change. Forward current (0-7) + deltas (8-15) + instigator.
            key instigator = llList2Key(cmds, 19);
            // 10 current (0-9) + 10 deltas (10-19). Slots 8/9 = oral & anal creampie —
            // Spunked can't detect those, so they're always 0 here (INM fills them).
            llMessageLinked(LINK_SET, SPUNKED_EVENT, llDumpList2String([
                llList2Integer(cmds, 1),   // 0 curHead
                llList2Integer(cmds, 2),   // 1 curChest
                llList2Integer(cmds, 3),   // 2 curGroin
                llList2Integer(cmds, 4),   // 3 curBack
                llList2Integer(cmds, 5),   // 4 curButt
                llList2Integer(cmds, 6),   // 5 curArms
                llList2Integer(cmds, 7),   // 6 curLegs
                llList2Integer(cmds, 17),  // 7 curCreampie (vaginal)
                0,                         // 8 curOralCreampie  (n/a in Spunked)
                0,                         // 9 curAnalCreampie  (n/a in Spunked)
                llList2Integer(cmds, 10),  // 10 dHead
                llList2Integer(cmds, 11),  // 11 dChest
                llList2Integer(cmds, 12),  // 12 dGroin
                llList2Integer(cmds, 13),  // 13 dBack
                llList2Integer(cmds, 14),  // 14 dButt
                llList2Integer(cmds, 15),  // 15 dArms
                llList2Integer(cmds, 16),  // 16 dLegs
                llList2Integer(cmds, 18),  // 17 dCreampie (vaginal)
                0,                         // 18 dOralCreampie
                0                          // 19 dAnalCreampie
            ], "|"), instigator);
        }
        else if (kw == "SpunkedResponseV3") {
            // Query reply: current state only (Facial..Creampie at indices 1-8).
            llMessageLinked(LINK_SET, SPUNKED_SYNC, llDumpList2String([
                llList2Integer(cmds, 1),   // 0 facial
                llList2Integer(cmds, 2),   // 1 chest
                llList2Integer(cmds, 3),   // 2 groin
                llList2Integer(cmds, 4),   // 3 back
                llList2Integer(cmds, 5),   // 4 butt
                llList2Integer(cmds, 6),   // 5 arms
                llList2Integer(cmds, 7),   // 6 legs
                llList2Integer(cmds, 8),   // 7 creampie (vaginal)
                0,                         // 8 oral creampie  (n/a in Spunked)
                0                          // 9 anal creampie  (n/a in Spunked)
            ], "|"), NULL_KEY);
        }

        cmds = [];
    }

    changed(integer c) {
        if (c & (CHANGED_OWNER | CHANGED_INVENTORY)) llResetScript();
    }
}
