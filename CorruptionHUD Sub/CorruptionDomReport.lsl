// CorruptionDomReport.lsl  —  SUB side of the closed-loop dom detection ("ping-pong").
//
// When the sub gets cummed on by a partner (the instigator = the dom), this reports the
// act to THAT partner's Dom HUD so it can count "loads delivered / bred". It reads the
// SAME normalized cum packet the relays already send to Core, so it works for both
// Spunked and INM with no extra detection. Lives in the sub HUD, separate from Core.
//
// The report is region-said to the instigator's avatar, so only their own attachments
// (their Dom HUD) hear it — not a region-wide broadcast.

integer SPUNKED_EVENT = 90100;   // normalized cum event (current 0-9 | deltas 10-19 | instigator=id)
integer DOM_REPORT    = -87450;  // → the instigator's Dom HUD (DomCore listens here)

key wearer;

default {
    state_entry() { wearer = llGetOwner(); }
    attach(key id) { if (id != NULL_KEY) wearer = llGetOwner(); }

    link_message(integer sn, integer num, string str, key id) {
        if (num != SPUNKED_EVENT) return;
        key dom = id;                                   // the cummer (instigator)
        if (dom == NULL_KEY || dom == wearer) return;   // no instigator / self-cum → not a dom act

        list p = llParseStringKeepNulls(str, ["|"], []);
        // Deltas are fields 10-19. loads = number of zones hit this event (one per zone,
        // matching the sub's own load counting). Creampie = any INTERNAL zone (vag/oral/anal).
        integer loads = 0;
        integer i;
        for (i = 10; i <= 19; i++) if ((integer)llList2String(p, i) > 0) loads++;
        integer creampie = (((integer)llList2String(p, 17) > 0)    // vaginal creampie
                         || ((integer)llList2String(p, 18) > 0)    // oral creampie (INM)
                         || ((integer)llList2String(p, 19) > 0));  // anal creampie (INM)
        p = [];
        if (loads < 1) return;

        llRegionSayTo(dom, DOM_REPORT, "report|" + (string)wearer + "|"
            + (string)loads + "|" + (string)creampie);
    }

    changed(integer c) { if (c & (CHANGED_OWNER | CHANGED_INVENTORY)) llResetScript(); }
}
