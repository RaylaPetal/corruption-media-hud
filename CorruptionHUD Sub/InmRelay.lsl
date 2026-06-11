// InmRelay.lsl  —  put this in the SAME PRIM as the INM/INAM API (so LINK_THIS reaches
// it for the status request, and it hears INM's -99991 reports directly).
//
// Translates INM's many body zones into the normalized 10-slot packet inm_core already
// understands (so Core needs NO changes), plus an INM-only flags message. Mirrors
// SpunkedRelay; only the source + zone mapping differ. Replaces the old InmForward +
// InmRelay pair — since everything is one linkset, no relay hop is needed.
//
// INM reports ABSOLUTE state (current stacks per zone), not deltas — so we remember the
// last values and diff them. Only positive deltas (newly applied cum) matter to Core.
//
// INM message (pipe-delimited):  Status | targetAv | transparency |
//   3 mouth 4 face 5 chest 6 crotch 7 ass 8 vaginal 9 anal 10 r_arm 11 r_leg_frt
//   12 l_arm 13 l_leg_frt  [14 neck 15 back 16 stomach 17 r_leg_bck 18 l_leg_bck
//   19 r_foot 20 l_foot 21 r_hand 22 l_hand]  ... cummer_av(-2)  SysStatus(-1)
//   (zones 14-22 only exist on INM 3.3 / INAM 2.4+; missing fields read as 0.)

integer INM_STATUS    = -99991;   // INM → scripts: cum status report
integer INM_GET       = -99990;   // scripts → INM: request a status report
integer SPUNKED_EVENT = 90100;    // → core: a change (current 0-9 + deltas 10-19 + instigator)
integer SPUNKED_SYNC  = 90101;    // → core: current-state resync (no deltas / no XP)
integer INM_STATE     = 90103;    // → core: INM-only flags bitfield (plug/drip/glazed/rlv)

// SysStatus bits we care about (see INM API doc)
integer SS_RLV        = 65536;    // 1<<16 RLV_Active
integer SS_PUSSYPLUG  = 1048576;  // 1<<20 pussyplugged
integer SS_ASSPLUG    = 2097152;  // 1<<21 assplugged
integer SS_DRIP       = 536870912;// 1<<29 dripdown

// Our packed inmFlags (what Core broadcasts at HUD field 64; consumers test these)
integer F_BREDPLUG = 1;   // a creampied hole is plugged (keeping it in)
integer F_DRIP     = 2;   // cum dripping down
integer F_GLAZED   = 4;   // covered on every major zone at once
integer F_RLV      = 8;   // RLV active in INM

// Last known stacks per normalized slot (10): Head/Chest/Groin/Back/Butt/Arms/Legs/
// VaginalCreampie + OralCreampie(throat) + AnalCreampie(internal).
integer pHead; integer pChest; integer pGroin; integer pBack;
integer pButt; integer pArms;  integer pLegs;  integer pCream;
integer pOral; integer pAnal;
integer primed = FALSE;           // first report just sets the baseline (no XP granted)

requestStatus() {
    // cummer_av comes back NULL_KEY for a requested report → treated as a baseline resync.
    llMessageLinked(LINK_THIS, INM_GET, "Get_INM_Status", llGetOwner());
}

// Read a zone stack by index. Zones occupy 3 .. (length-3); the LAST TWO fields are
// ALWAYS cummer_av then SysStatus. On a pre-3.3 INM (only zones 3-13) the 3.3 indices
// (14-22) would otherwise land on cummer_av / SysStatus, so any index in the trailing
// two slots (or below 3) returns 0 — valid for every INM version.
integer z(list p, integer i) {
    if (i < 3 || i >= llGetListLength(p) - 2) return 0;
    return (integer)llList2String(p, i);
}

default {
    state_entry() { requestStatus(); }
    attach(key id) { if (id != NULL_KEY) { primed = FALSE; requestStatus(); } }

    link_message(integer link, integer num, string msg, key id) {
        if (num != INM_STATUS) return;     // only INM cum-status reports
        if (id != llGetOwner()) return;    // only the wearer's own INM system
        list p = llParseStringKeepNulls(msg, ["|"], []);
        if (llList2String(p, 0) != "Status") { p = []; return; }   // ignore AccyStatus etc.

        // ── INM zones → our 10 normalized slots (internal split out from external) ──
        integer head  = z(p,4) + z(p,14);                                           // face + neck → facial (external)
        integer oral  = z(p,3);                                                      // mouth → throat creampie (internal)
        integer chest = z(p,5) + z(p,16);                                           // chest + stomach
        integer groin = z(p,6);                                                     // crotch (external) → pussy ext
        integer cream = z(p,8);                                                     // vaginal (internal) → creampie/breeding
        integer butt  = z(p,7);                                                     // ass (external)
        integer anal  = z(p,9);                                                     // anal → anal creampie (internal)
        integer arms  = z(p,10) + z(p,12) + z(p,21) + z(p,22);                      // arms + hands
        integer legs  = z(p,11) + z(p,13) + z(p,17) + z(p,18) + z(p,19) + z(p,20);  // legs + feet
        integer back  = z(p,15);                                                    // back

        key instigator = (key)llList2String(p, -2);   // cummer_av (NULL_KEY on a requested status)
        integer sys = (integer)llList2String(p, -1);  // SysStatus bitfield
        p = [];

        // ── INM-only flags (from SysStatus + zone coverage) → Core, every report ──
        // NB: SysStatus bits are SETTINGS, not live cum state — dripdown just means the
        // drip feature is enabled, so it's gated on actually having cum on the body.
        integer hasCum = (head + oral + chest + groin + cream + butt + anal + arms + legs + back) > 0;
        integer flags = 0;
        if ( ((sys & SS_PUSSYPLUG) != 0 && cream > 0) || ((sys & SS_ASSPLUG) != 0 && anal > 0) )
            flags = flags | F_BREDPLUG;                                      // bred & plugged (keeping it in)
        if ((sys & SS_DRIP) != 0 && hasCum) flags = flags | F_DRIP;         // drip feature on AND messy
        if (head > 0 && chest > 0 && groin > 0 && butt > 0 && arms > 0 && legs > 0)
            flags = flags | F_GLAZED;                                        // every major zone at once
        if (sys & SS_RLV) flags = flags | F_RLV;                            // RLV on (a setting; read as-is)
        llMessageLinked(LINK_SET, INM_STATE, (string)flags, NULL_KEY);

        // First report, or a requested resync (cummer NULL): set baseline, mirror state,
        // grant NO XP (we can't know what changed without a prior baseline).
        if (!primed || instigator == NULL_KEY) {
            pHead = head; pChest = chest; pGroin = groin; pBack = back;
            pButt = butt; pArms = arms;  pLegs = legs;  pCream = cream;
            pOral = oral; pAnal = anal;
            primed = TRUE;
            llMessageLinked(LINK_SET, SPUNKED_SYNC, llDumpList2String(
                [head, chest, groin, back, butt, arms, legs, cream, oral, anal], "|"), NULL_KEY);
            return;
        }

        // Diff against last known. Core ignores any slot whose delta is <= 0 (cleanup).
        integer dHead = head - pHead;   integer dChest = chest - pChest;
        integer dGroin = groin - pGroin; integer dBack = back - pBack;
        integer dButt = butt - pButt;   integer dArms = arms - pArms;
        integer dLegs = legs - pLegs;   integer dCream = cream - pCream;
        integer dOral = oral - pOral;   integer dAnal = anal - pAnal;

        pHead = head; pChest = chest; pGroin = groin; pBack = back;
        pButt = butt; pArms = arms;  pLegs = legs;  pCream = cream;
        pOral = oral; pAnal = anal;

        // Same 20-field shape SpunkedRelay emits → processLinkedSpunked handles it as-is.
        llMessageLinked(LINK_SET, SPUNKED_EVENT, llDumpList2String([
            head, chest, groin, back, butt, arms, legs, cream, oral, anal,                  // 0-9 current
            dHead, dChest, dGroin, dBack, dButt, dArms, dLegs, dCream, dOral, dAnal          // 10-19 deltas
        ], "|"), instigator);
    }

    changed(integer c) { if (c & (CHANGED_OWNER | CHANGED_INVENTORY)) llResetScript(); }
}
