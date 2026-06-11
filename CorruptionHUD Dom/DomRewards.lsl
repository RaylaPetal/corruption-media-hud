// DomRewards.lsl  —  dom achievements (parallel to CorruptionRewards on the sub side).
// Stateless evaluator: reads DomCore's "dhud|" broadcast, and when an achievement newly
// qualifies tells DomCore to grant it (DomCore stays the single source of truth + dedups).

integer DOM_HUD_CHAN = -87440;   // ← DomCore broadcast (heard via LINK_SET in-linkset)
integer DOM_REWARD   = 90111;    // → DomCore: "<bit>|<amount>|<label>"

grant(integer bit, integer amount, string label) {
    llMessageLinked(LINK_SET, DOM_REWARD, (string)bit + "|" + (string)amount + "|" + label, "");
}

default {
    link_message(integer s, integer num, string str, key id) {
        if (num != DOM_HUD_CHAN) return;
        if (llSubStringIndex(str, "dhud|") != 0) return;

        list p = llParseStringKeepNulls(str, ["|"], []);
        integer level     = (integer)llList2String(p, 2);
        integer conquests = (integer)llList2String(p, 4);
        integer loadsSent = (integer)llList2String(p, 5);
        integer bred      = (integer)llList2String(p, 6);
        integer infamy    = (integer)llList2String(p, 7);
        integer achFlags  = (integer)llList2String(p, 14);
        integer subsOwned = (integer)llList2String(p, 17);
        p = [];

        integer q = 0;
        if (conquests >= 1)   q = q | 1;       // First Conquest
        if (loadsSent >= 50)  q = q | 2;       // Stud
        if (bred >= 10)       q = q | 4;       // Breeder
        if (conquests >= 25)  q = q | 8;       // Town Stud
        if (level >= 5)       q = q | 16;      // Cruel
        if (level >= 10)      q = q | 32;      // Apex
        if (loadsSent >= 200) q = q | 64;      // Prolific
        if (bred >= 50)       q = q | 128;     // Breeding Bull
        if (infamy >= 200)    q = q | 256;     // Infamous
        if (subsOwned >= 1)   q = q | 512;     // Owner       (placeholder until match system)
        if (subsOwned >= 3)   q = q | 1024;    // Harem       (placeholder)

        integer newA = q & ~achFlags;
        if (!newA) return;
        if (newA & 1)    grant(1,    200,  "🏆 First Conquest");
        if (newA & 2)    grant(2,    600,  "🏆 Stud");
        if (newA & 4)    grant(4,    800,  "🏆 Breeder");
        if (newA & 8)    grant(8,    1500, "🏆 Town Stud");
        if (newA & 16)   grant(16,   500,  "🏆 Cruel");
        if (newA & 32)   grant(32,   1500, "🏆 Apex Predator");
        if (newA & 64)   grant(64,   2000, "🏆 Prolific");
        if (newA & 128)  grant(128,  2500, "🏆 Breeding Bull");
        if (newA & 256)  grant(256,  1500, "🏆 Infamous");
        if (newA & 512)  grant(512,  1000, "🏆 Owner");
        if (newA & 1024) grant(1024, 2500, "🏆 Harem");
    }

    changed(integer c) {
        if (c & (CHANGED_OWNER | CHANGED_INVENTORY)) llResetScript();
    }
}
