// CorruptionRewards.lsl — achievements + daily/weekly goals (the "rewards" subsystem)
//
// WHY THIS SCRIPT EXISTS: this is the part of the game that GROWS over time (every
// new achievement / goal is more code + more strings). Keeping it in Core kept
// pushing Core toward the 64KB Mono limit. So the evaluation lives here instead.
//
// DESIGN — stateless evaluator, Core stays the source of truth:
//   • Core broadcasts the full stat snapshot on HUD_CHAN (it already did; we just
//     appended the few fields this needs — session zones + claimed bitfields).
//   • This script reads that snapshot, decides which achievements/goals NEWLY
//     qualify (mask out the ones Core says are already claimed), and tells Core to
//     grant them: REWARD_GRANT, "<kind>|<bit>|<amount>|<label>".
//   • Core's grantReward() sets the flag bit (dedup-guarded) and awards the XP, so
//     ALL persistence stays in Core's single save blob / DB path. No state here.
//
// Because Core sets the bit and immediately re-broadcasts, a NEW qualify can't be
// re-sent (the bit is now in the broadcast). Core also guards, so even an in-flight
// duplicate is harmless.

integer HUD_CHAN     = -87432;   // Core's broadcast (received via LINK_SET in-linkset)
integer REWARD_GRANT = 88006;    // → Core: grant this reward (set bit + award XP)

// ── goal thresholds + bonuses (own them here; Core no longer does) ──
integer DAILY_GOAL_XP    = 2000;   integer DAILY_BONUS      = 1000;
integer DAILY_GOAL_PART  = 2;      integer DAILY_BONUS_PART = 800;
integer DAILY_GOAL_LOAD  = 10;     integer DAILY_BONUS_LOAD = 600;
integer WEEKLY_GOAL_XP   = 12000;  integer WEEKLY_BONUS      = 5000;
integer WEEKLY_GOAL_PART = 10;     integer WEEKLY_BONUS_PART = 4000;
integer WEEKLY_GOAL_LOAD = 50;     integer WEEKLY_BONUS_LOAD = 3000;

integer PRESTIGE_MAX = 10;

grant(string kind, integer bit, integer amount, string label) {
    llMessageLinked(LINK_SET, REWARD_GRANT,
        kind + "|" + (string)bit + "|" + (string)amount + "|" + label, "");
}

default {
    // No llListen: Core sends the broadcast to the whole linkset via llMessageLinked,
    // so we get it here as a link_message (the worn HUD object is the one that listens).
    link_message(integer s, integer num, string str, key id) {
        if (num != HUD_CHAN) return;
        if (llSubStringIndex(str, "hud|") != 0) return;

        list p = llParseStringKeepNulls(str, ["|"], []);

        // ── stats this subsystem cares about (parsed indices; see Core updateDisplay) ──
        integer lvl        = (integer)llList2String(p, 2);
        integer prestige   = (integer)llList2String(p, 3);
        integer totalCount = (integer)llList2String(p, 5);
        integer totalHits  = (integer)llList2String(p, 6);    // lifetime loads (all zones)
        integer partners   = (integer)llList2String(p, 7);
        integer creampie   = (integer)llList2String(p, 17);
        integer pussyC     = (integer)llList2String(p, 18);   // lifetime vaginal loads
        integer assC       = (integer)llList2String(p, 19);   // lifetime anal loads
        integer faceC      = (integer)llList2String(p, 20);   // lifetime facials
        integer dXP        = (integer)llList2String(p, 21);
        integer achFlags   = (integer)llList2String(p, 22);
        integer wXP        = (integer)llList2String(p, 23);
        integer notoriety  = (integer)llList2String(p, 26);
        integer dPart      = (integer)llList2String(p, 43);
        integer dLoad      = (integer)llList2String(p, 44);
        integer wPart      = (integer)llList2String(p, 45);
        integer wLoad      = (integer)llList2String(p, 46);
        integer sFace      = (integer)llList2String(p, 50);   // appended for this script
        integer sPussy     = (integer)llList2String(p, 51);
        integer sAss       = (integer)llList2String(p, 52);
        integer sChest     = (integer)llList2String(p, 53);
        integer sBody      = (integer)llList2String(p, 54);
        integer dClaimed   = (integer)llList2String(p, 55);
        integer wClaimed   = (integer)llList2String(p, 56);
        integer oralCream  = (integer)llList2String(p, 60);   // INM throat creampies (lifetime)
        integer analCream  = (integer)llList2String(p, 61);   // INM anal creampies (lifetime)
        integer inmFlags   = (integer)llList2String(p, 64);   // INM flags: 1 bredPlugged, 4 glazed
        integer maxAud     = (integer)llList2String(p, 65);   // peak audience DURING an act (Exhibitionist)
        p = [];

        // ── achievements: build the "qualified" mask, then grant only the new bits ──
        integer q = 0;
        if (creampie >= 1)                                         q = q | 1;
        if (sFace > 0 && sPussy > 0 && sAss > 0)                   q = q | 2;
        if (maxAud >= 5)                                           q = q | 4;     // Exhibitionist: a load landed with 5+ watching
        if (totalCount >= 25)                                      q = q | 8;
        if (sFace > 0 && sPussy > 0 && sAss > 0 && sChest > 0 && sBody > 0) q = q | 16;
        if (prestige >= 1)                                         q = q | 32;
        if (prestige >= 5)                                         q = q | 64;
        if (prestige >= PRESTIGE_MAX)                              q = q | 128;
        if (partners >= 3)                                         q = q | 256;
        if (sFace + sPussy + sAss + sChest + sBody >= 12)          q = q | 512;
        if (notoriety >= 200)                                      q = q | 1024;
        // ── new tiers (bits 2048+) ──
        if (creampie >= 10)                                        q = q | 2048;      // Bred
        if (creampie >= 50)                                        q = q | 4096;      // Breeding Stock
        if (totalHits >= 500)                                      q = q | 8192;      // Used Up
        if (lvl >= 5)                                              q = q | 16384;     // Rising Slut
        if (lvl >= 10)                                             q = q | 32768;     // Corrupted
        if (faceC >= 50)                                           q = q | 65536;     // Throat Goat
        if (assC >= 50)                                            q = q | 131072;    // Anal Addict
        if (pussyC >= 100)                                         q = q | 262144;    // Pussy Pet
        if (notoriety >= 500)                                      q = q | 524288;    // Notorious
        if (notoriety >= 1000)                                     q = q | 1048576;   // Cum Legend
        if (sFace + sPussy + sAss + sChest + sBody >= 25)          q = q | 2097152;   // Marathon
        if (partners >= 5)                                         q = q | 4194304;   // Town Bicycle
        if (oralCream >= 10)                                       q = q | 8388608;   // Throat Bred (INM)
        if (analCream >= 10)                                       q = q | 16777216;  // Anal Bred (INM)
        if (inmFlags & 4)                                          q = q | 33554432;  // Glazed Head to Toe (INM)
        if (inmFlags & 1)                                          q = q | 67108864;  // Corked Cumdump (INM)

        integer newAch = q & ~achFlags;   // only the ones not already unlocked
        if (newAch) {
            if (newAch & 1)    grant("ach", 1,    200,  "🏆 First Creampie");
            if (newAch & 2)    grant("ach", 2,    500,  "🏆 All Holes Used");
            if (newAch & 4)    grant("ach", 4,    600,  "🏆 Exhibitionist");
            if (newAch & 8)    grant("ach", 8,    1500, "🏆 Town Toy");
            if (newAch & 16)   grant("ach", 16,   800,  "🏆 Head to Toe");
            if (newAch & 32)   grant("ach", 32,   1000, "🏆 First Prestige");
            if (newAch & 64)   grant("ach", 64,   3000, "🏆 Prestige V");
            if (newAch & 128)  grant("ach", 128,  6000, "🏆 Max Prestige");
            if (newAch & 256)  grant("ach", 256,  1000, "🏆 Gangbang");
            if (newAch & 512)  grant("ach", 512,  1200, "🏆 Soaked");
            if (newAch & 1024) grant("ach", 1024, 1500, "🏆 Local Legend");
            if (newAch & 2048)    grant("ach", 2048,    800,  "🏆 Bred");
            if (newAch & 4096)    grant("ach", 4096,    2500, "🏆 Breeding Stock");
            if (newAch & 8192)    grant("ach", 8192,    2500, "🏆 Used Up");
            if (newAch & 16384)   grant("ach", 16384,   500,  "🏆 Rising Slut");
            if (newAch & 32768)   grant("ach", 32768,   1500, "🏆 Corrupted");
            if (newAch & 65536)   grant("ach", 65536,   1200, "🏆 Throat Goat");
            if (newAch & 131072)  grant("ach", 131072,  1200, "🏆 Anal Addict");
            if (newAch & 262144)  grant("ach", 262144,  1500, "🏆 Pussy Pet");
            if (newAch & 524288)  grant("ach", 524288,  2000, "🏆 Notorious");
            if (newAch & 1048576) grant("ach", 1048576, 3000, "🏆 Cum Legend");
            if (newAch & 2097152) grant("ach", 2097152, 2000, "🏆 Marathon");
            if (newAch & 4194304) grant("ach", 4194304, 1500, "🏆 Town Bicycle");
            if (newAch & 8388608)  grant("ach", 8388608,  1200, "🏆 Throat Bred");
            if (newAch & 16777216) grant("ach", 16777216, 1200, "🏆 Anal Bred");
            if (newAch & 33554432) grant("ach", 33554432, 2000, "🏆 Glazed Head to Toe");
            if (newAch & 67108864) grant("ach", 67108864, 2500, "🏆 Corked Cumdump");
        }

        // ── daily / weekly goals (claimed bitfields: bit1 XP, bit2 partners, bit4 loads) ──
        if (!(dClaimed & 1) && dXP   >= DAILY_GOAL_XP)    grant("dg", 1, DAILY_BONUS,       "Daily goal: XP");
        if (!(dClaimed & 2) && dPart >= DAILY_GOAL_PART)  grant("dg", 2, DAILY_BONUS_PART,  "Daily goal: Partners");
        if (!(dClaimed & 4) && dLoad >= DAILY_GOAL_LOAD)  grant("dg", 4, DAILY_BONUS_LOAD,  "Daily goal: Loads");
        if (!(wClaimed & 1) && wXP   >= WEEKLY_GOAL_XP)   grant("wg", 1, WEEKLY_BONUS,      "Weekly goal: XP");
        if (!(wClaimed & 2) && wPart >= WEEKLY_GOAL_PART) grant("wg", 2, WEEKLY_BONUS_PART, "Weekly goal: Partners");
        if (!(wClaimed & 4) && wLoad >= WEEKLY_GOAL_LOAD) grant("wg", 4, WEEKLY_BONUS_LOAD, "Weekly goal: Loads");
    }

    changed(integer c) {
        if (c & (CHANGED_OWNER | CHANGED_INVENTORY)) llResetScript();
    }
}
