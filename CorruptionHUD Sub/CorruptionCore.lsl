key wearer;
integer showTitle  = TRUE;
integer showStatus = TRUE;
integer isLocked       = FALSE;
integer achFlags       = 0;    // unlocked achievements bitfield (persisted)
integer diffChosen     = FALSE; // difficulty locked once chosen; cleared only by Reset (anti-cheat)

// === Communication channels ===
integer SPUNKED_EVENT    = 90100; // passive report (deltas) from inm_spunked relay
integer SPUNKED_SYNC     = 90101; // current-state resync from inm_spunked relay
integer INM_STATE        = 90103; // inm relay → core: INM-only flags (plug/drip/glazed/rlv)
integer MENU_CMD         = 88002; // menu → core
integer MENU_STATE       = 88001; // core → menu
integer DB_RESTORE       = 88003; // inm_db → core: blob rehydrated into Linkset Data, reload
integer DB_FLUSH         = 88004; // core → inm_db: upload this exact snapshot now (bypass debounce)
integer HEAT_SET         = 88005; // inm_immersion → core: start the In-Heat XP buff
integer REWARD_GRANT     = 88006; // inm_rewards → core: grant an achievement/goal (set bit + award XP)
integer OWNER_SET        = 88030; // CorruptionMatch → core: "<ownerName>" bond formed ("" = bond cleared)
integer HUD_CHAN = -87432;  // must match monitor
integer HAPTIC_EVENT = 90200; // core → inm_lovense: "<event>|<intensity 0-20>"

// === Cum system ===
integer cumSystem   = 1;  // 0 = Spunked, 1 = INM

// === Persistent totals ===
integer totalCount;
integer pussyCount;
integer assCount;
integer faceCount;
integer creampieCount;
integer oralCreamCount;   // throat/oral creampies (lifetime) — INM only
integer analCreamCount;   // anal creampies (lifetime) — INM only
integer chestCount;
integer bodyCount;
integer xp;
integer level = 1;   // cached computeLevel(); refreshed ONLY where xp changes
integer selectedTitleIdx;
string  ownerName = "";   // set by CorruptionMatch when owned; enables the "<Owner>'s Slut" title (idx 99)
integer OWNER_TITLE_IDX = 99;   // sentinel selectedTitleIdx for the owner-granted title

// === Session state (reset on clean) ===
// s* = cumulative loads per zone this session (feeds the "session hits" stat)
integer sFace;
integer sPussy;
integer sAss;
integer sChest;
integer sBody;
list    sessionPartners;
string  lastPartnerName;
integer sessionPartnerCount = 0;

// === Live body state (current cum stacks, mirror of Spunked) ===
// Feeds the broadcast status line (rendered by inm_text) and the "clean?" lock checks.
integer cFace;     // facial (external)
integer cThroat;   // throat / oral creampie (internal) — INM only (0 on Spunked)
integer cChest;    // chest
integer cPussy;    // groin + vaginal creampie (combined; overlay derives on-pussy = cPussy - cVagCream)
integer cVagCream; // vaginal creampie (internal) — tracked by BOTH systems
integer cAss;      // butt (external)
integer cAnal;     // anal creampie (internal) — INM only (0 on Spunked)
integer cBody;     // back + arms + legs
integer inmFlags;  // INM-only live flags from the relay: 1 bredPlugged, 2 dripping, 4 glazed, 8 rlv (broadcast field 64)

// === PA live state ===
float paArousal    = 0.0;   // 0 – 400
float paCloseness  = 0.0;   // 0.0 – 1.0

float vagMult  = 1.0;
float boobMult = 1.0;
float buttMult = 1.0;

// === Config ===
integer difficulty    = 1;    // 0 = Tease (easy), 1 = Naughty (normal), 2 = Slut (hard)
integer IDLE_THRESHOLD = 86400;  // seconds idle before decay kicks in (1 day)
integer DECAY_INTERVAL = 3600;   // once idle, lose XP every this many seconds (1 hour)
integer DECAY_AMOUNT   = 250;    // how much XP to lose on each decay tick (floored at current level base)
integer lastDecayTime;
// Daily / weekly goals — evaluated in CorruptionRewards.lsl now (it owns the
// thresholds + bonuses). Core only keeps DAILY_GOAL_XP because the menu displays it
// (broadcastState field 16). The counters/claimed flags still live + persist here.
integer DAILY_GOAL_XP    = 2000;   // shown by the menu (keep in sync with rewards script)

// These are set at runtime by setDifficulty() — do not hardcode elsewhere
integer XP_CREAMPIE = 120;
integer XP_FACE     = 80;
integer XP_CHEST    = 60;
integer XP_BODY     = 35;
integer XP_ORGASM   = 200;
// Per-system load-XP multiplier (Spunked = fewer zones/act → boosted; INM = 1x). See getSystemMult().
float   SPUNKED_XP_MULT = 4.0;

// Steeper curve: INM spreads one cum to many zones (each counts as a "load"), so XP
// stacks fast per act. ~3-4x the old thresholds so a busy session is a few levels, not 7+.
list LEVEL_XP        = [0, 2500, 7000, 16000, 30000, 52000, 85000, 130000, 200000, 320000];
integer ENDLESS_STEP  = 150000; // XP per level beyond the last defined level (endless)
integer PRESTIGE_GOAL = 842500; // sum of all LEVEL_XP entries
integer PRESTIGE_MAX  = 10;     // prestige caps here (matches the I–X numeral prefix)
// CORRUPTION_MULT moved to inm_immersion (it sends the level-up arousalMultiplier now).
list TITLES   = ["Innocent One",
                 "Curious Kitten",
                 "Naughty Girl",
                 "Slutty",
                 "Filthy Slut",
                 "Cum Slut",
                 "Depraved Whore",
                 "Cock Addict",
                 "Mindless Fucktoy",
                 "Cum Dumpster"];

// Prestige-exclusive titles, selectable once prestige >= the matching req.
// They occupy selectedTitleIdx 10+ (PRESTIGE_TITLES index = selectedTitleIdx-10)
// and are gated by prestige, not level, so they're never lost to a level reset.
list PRESTIGE_TITLES   = ["Eternal Cumslut", "Legendary Whore", "Goddess of Filth", "Immortal Cumdump"];
list PRESTIGE_TITLE_REQ = [1, 3, 6, 10];

integer lastCumTime;

// Goal tracking (persisted). dailyClaimed/weeklyClaimed are BITFIELDS now:
// bit 1 = XP goal, bit 2 = partners goal, bit 4 = loads goal.
integer dailyXPGained  = 0;
integer dayStartTime;
integer weeklyXPGained = 0;
integer weekStartTime  = 0;
integer dailyClaimed   = 0;
integer weeklyClaimed  = 0;
integer dailyPartners  = 0;   // new partners this day  (period-reset)
integer weeklyPartners = 0;
integer dailyLoads     = 0;   // loads received this day (period-reset)
integer weeklyLoads    = 0;

// Orgasm diminishing returns (session-only, reset on clean)
integer orgasmXPPercent = 100;  // starts at 100%, drops 5% each orgasm, floor 5%

integer lastMultSentTime = 0;   // unix time of last corruption multiplier sent to PA
integer prestigeLevel    = 0;   // number of times player has prestiged
integer nearbyCount           = 0;      // avatars within AUDIENCE_RANGE (updated while scan active)
integer AUDIENCE_RANGE        = 20;     // meters to scan for audience

// === New systems (persisted) ===
integer notoriety = 0;          // reputation from witnessed/public acts (lifetime; leaderboard)
integer maxAudience = 0;        // most people nearby DURING an actual act (lifetime) — Exhibitionist ach
integer heatUntil = 0;          // unix time the "In Heat" XP buff expires
integer notedThisAct = FALSE;   // notoriety already counted this act? re-arms after a gap
integer reliefDone   = FALSE;   // edging relief already granted this act?
integer NOTORIETY_GAP = 1800;   // seconds with no cum events that ends an "act"
integer RELIEF_MAX  = 150;      // max edging-relief XP (at full arousal)
integer HEAT_DUR    = 1800;     // "In Heat" buff length (seconds) — set by creampie + HEAT_SET
integer HEAT_MULT_I = 150;      // "In Heat" XP multiplier ×100 (1.5×)
integer hapticsOn   = TRUE;     // Lovense/LoveBridge haptics enabled? (persisted)
integer immersionOn = TRUE;     // arousal/immersion features (sparks, grope, vibes) enabled? (persisted)
integer adultBypass = FALSE;    // override the Adult-region safety gate for arousal (persisted; default OFF = safe)
integer ambientGapMin      = 180;  // passive tease idle range min (menu-set, persisted, broadcast to inm_immersion)
integer ambientGapMax      = 600;  // passive tease idle range max (menu-set, persisted, broadcast to inm_immersion)

integer timerTick      = 0;
float   rotateInterval = 10.0; // overlay page-rotation seconds (persisted setting; the OVERLAY owns the rotation now, Core just stores + broadcasts it)

// ── difficulty ───────────────────────────────────────
// 0 = Tease  (easy):   decay after 7 days,  higher XP
// 1 = Naughty (normal): decay after 3 days, base XP
// 2 = Slut   (hard):   decay after 12 hours, lower XP

setDifficulty(integer d) {
    if (d != 0 && d != 2) d = 1;   // only Tease/Naughty/Slut; anything else (old Custom) → Naughty
    difficulty = d;
    if (d == 0) {
        IDLE_THRESHOLD = 604800;   // 7 days
        XP_CREAMPIE = 180;  XP_FACE = 120;
        XP_CHEST    = 90;   XP_BODY = 52;   XP_ORGASM = 300;
    } else if (d == 2) {
        IDLE_THRESHOLD = 43200;    // 12 hours
        XP_CREAMPIE = 72;   XP_FACE = 48;
        XP_CHEST    = 36;   XP_BODY = 21;   XP_ORGASM = 120;
    } else {
        IDLE_THRESHOLD = 259200;   // 3 days (Naughty)
        XP_CREAMPIE = 120;  XP_FACE = 80;
        XP_CHEST    = 60;   XP_BODY = 35;   XP_ORGASM = 200;
    }
}

string prestigePrefix(integer p) {
    if (p <= 0) return "";
    list romans = ["I","II","III","IV","V","VI","VII","VIII","IX","X"];
    if (p <= 10) return "[" + llList2String(romans, p - 1) + "] ";
    return "[" + (string)p + "] ";
}

// Title name/colour by index. 0-9 = level titles; 10+ = prestige titles (gold).
string titleName(integer idx) {
    if (idx == OWNER_TITLE_IDX) {
        if (ownerName != "") return ownerName + "'s Slut";
        return llList2String(TITLES, 0);   // bond gone but title still selected → safe fallback
    }
    if (idx >= 10) return llList2String(PRESTIGE_TITLES, idx - 10);
    return llList2String(TITLES, idx);
}

// ── helpers ──────────────────────────────────────────

integer computeLevel() {
    integer n     = llGetListLength(LEVEL_XP);
    integer topXP = llList2Integer(LEVEL_XP, n - 1);   // last defined threshold (100000)
    // Endless levels: each ENDLESS_STEP of XP past the top threshold = +1 level
    if (xp >= topXP) return n + (xp - topXP) / ENDLESS_STEP;
    integer i;
    for (i = n - 2; i >= 0; i--)
        if (xp >= llList2Integer(LEVEL_XP, i)) return i + 1;
    return 1;
}

// XP threshold that reaches the level AFTER the current one (handles endless).
integer xpForNextLevel() {
    integer n = llGetListLength(LEVEL_XP);
    if (level < n) return llList2Integer(LEVEL_XP, level);   // LEVEL_XP[level] = lv+1 threshold
    integer topXP = llList2Integer(LEVEL_XP, n - 1);
    return topXP + (level - n + 1) * ENDLESS_STEP;
}

// XP at the START of the current level. Decay never drops below this, so idling
// erodes progress within a level but can never cost you the level or its title.
integer xpFloor() {
    integer n = llGetListLength(LEVEL_XP);
    if (level < n) return llList2Integer(LEVEL_XP, level - 1);
    integer topXP = llList2Integer(LEVEL_XP, n - 1);
    return topXP + (level - n) * ENDLESS_STEP;
}

clampTitle() {
    if (selectedTitleIdx >= 10) return;   // prestige titles are prestige-gated, not level-gated
    integer maxIdx = level - 1;
    if (selectedTitleIdx > maxIdx) selectedTitleIdx = maxIdx;
}

float getXPMultiplier() {
    if (paCloseness > 0.0)
        return 1.5 + paCloseness;
    return 1.0 + (paArousal / 400.0) * 0.5;
}

float getAudienceMult() {
    integer capped = nearbyCount;
    if (capped > 10) capped = 10;
    return 1.0 + (float)capped * 0.10;
}

// Permanent reward for prestiging: +10% XP per prestige level. This carries
// across the level reset, so prestige makes all future leveling faster.
float getPrestigeMult() {
    return 1.0 + (float)prestigeLevel * 0.10;
}

integer clamp0(integer v) {
    if (v < 0) return 0;   // Spunked uses negatives for disabled/unavailable zones
    return v;
}

// True if any cum is currently on the body (used to gate unlock).
integer bodyDirty() {
    return (cFace + cChest + cPussy + cAss + cBody) > 0;
}

// Returns the broadcast string it just sent (so the reset path can flush it to the
// DB without keeping a permanent copy in a global).
string updateDisplay() {
    integer lv    = level;
    integer nLvls = llGetListLength(LEVEL_XP);

    // XP band for current level (endless past the last defined level)
    integer lvBase;
    integer lvTop;
    if (lv < nLvls) {
        lvBase = llList2Integer(LEVEL_XP, lv - 1);
        lvTop  = llList2Integer(LEVEL_XP, lv);
    } else {
        integer topXP = llList2Integer(LEVEL_XP, nLvls - 1);
        lvBase = topXP + (lv - nLvls) * ENDLESS_STEP;
        lvTop  = lvBase + ENDLESS_STEP;
    }

    integer prestigeGoal = PRESTIGE_GOAL;
    string curTitle  = titleName(selectedTitleIdx);
    string nextTitle = "";
    if (selectedTitleIdx < 10 && selectedTitleIdx + 1 < llGetListLength(TITLES))
        nextTitle = llList2String(TITLES, selectedTitleIdx + 1);

    // Combined climax meter: arousal fills the first half (0–400), closeness the
    // second (0–1). Orgasm at 1.0. So it rises during denial buildup, not only acts.
    float climaxPct = (paArousal / 400.0 + paCloseness) / 2.0;
    if (climaxPct > 1.0) climaxPct = 1.0;

    // Broadcast to HUD first so it updates even on the early returns below
    integer sessionHits = sFace + sPussy + sAss + sChest + sBody;
    integer totalHits   = faceCount + pussyCount + assCount + chestCount + bodyCount;
    integer heatRem     = heatUntil - llGetUnixTime();
    if (heatRem < 0) heatRem = 0;

    // Combined XP multiplier the player currently has (global mults only; the
    // per-zone bodyMult isn't included). ×100 so it travels as an integer.
    integer mult100 = (integer)(getXPMultiplier() * getAudienceMult()
        * getPrestigeMult() * getComboMult() * getHeatMult() * 100.0 + 0.5);

    // Built by direct concatenation (not a 39-element list literal) to keep the heap
    // peak low — this runs at the tail of the deep cum-event chain. Field order MUST
    // match the consumers (media HUD, inm_text, inm_db); indices noted in comments.
    string msg =
          "hud|"   + (string)xp + "|" + (string)lv + "|" + (string)prestigeLevel          // 0-3
        + "|" + (string)selectedTitleIdx + "|" + (string)totalCount + "|" + (string)totalHits  // 4-6
        + "|" + (string)sessionPartnerCount + "|" + (string)sessionHits + "|" + (string)climaxPct // 7-9
        + "|" + (string)lastCumTime + "|" + (string)IDLE_THRESHOLD + "|" + (string)prestigeGoal   // 10-12
        + "|" + (string)lvBase + "|" + (string)lvTop                                       // 13-14
        + "|" + curTitle + "|" + nextTitle                                                 // 15-16
        + "|" + (string)creampieCount + "|" + (string)pussyCount + "|" + (string)assCount + "|" + (string)faceCount // 17-20
        + "|" + (string)dailyXPGained + "|" + (string)achFlags + "|" + (string)weeklyXPGained     // 21-23
        + "|" + (string)chestCount + "|" + (string)bodyCount                               // 24-25
        + "|" + (string)notoriety + "|" + (string)heatRem + "|" + (string)mult100          // 26-28
        + "|" + (string)showTitle + "|" + (string)showStatus + "|0"                        // 29-31 (31 was displayPage, now overlay-owned → placeholder)
        + "|" + (string)cFace + "|" + (string)cChest + "|" + (string)cPussy + "|" + (string)cAss + "|" + (string)cBody // 32-36
        + "|" + (string)difficulty                                                         // 37
        + "|" + lastPartnerName                                                            // 38
        + "|" + (string)ambientGapMin + "|" + (string)ambientGapMax                        // 39-40: inm_immersion tease throttle
        + "|" + (string)hapticsOn + "|" + (string)nearbyCount                              // 41-42: inm_immersion (Lovense gate, audience)
        + "|" + (string)dailyPartners + "|" + (string)dailyLoads                           // 43-44: daily goal counters (HUD)
        + "|" + (string)weeklyPartners + "|" + (string)weeklyLoads                          // 45-46: weekly goal counters (HUD)
        + "|" + (string)((integer)paArousal) + "|" + (string)((integer)(paCloseness * 100.0)) // 47 arousal 0-400, 48 closeness 0-100 (immersion)
        + "|" + (string)immersionOn                                                         // 49: immersion master toggle
        + "|" + (string)sFace + "|" + (string)sPussy + "|" + (string)sAss + "|" + (string)sChest + "|" + (string)sBody // 50-54 session zones (rewards: All Holes / Head to Toe / Soaked)
        + "|" + (string)dailyClaimed + "|" + (string)weeklyClaimed                           // 55-56 goal claimed bitfields (rewards dedup)
        + "|" + (string)adultBypass                                                          // 57 adult-region bypass (immersion)
        + "|" + (string)cThroat + "|" + (string)cAnal                                        // 58-59 live mirror throat/anal (overlay)
        + "|" + (string)oralCreamCount + "|" + (string)analCreamCount                        // 60-61 oral/anal creampie counts (rewards/HUD)
        + "|" + (string)cVagCream + "|" + (string)cumSystem                                  // 62 vaginal creampie mirror, 63 cumSystem (overlay conditional render)
        + "|" + (string)inmFlags                                                             // 64 INM-only flags (plug/drip/glazed/rlv)
        + "|" + (string)maxAudience                                                          // 65 peak audience during an act (Exhibitionist)
        + "|" + (string)((integer)rotateInterval);                                           // 66 overlay page-rotation seconds (overlay self-rotates)

    llSay(HUD_CHAN, msg);                                // separate worn HUD object
    llMessageLinked(LINK_SET, HUD_CHAN, msg, NULL_KEY);  // inm_db + inm_text (same linkset)
    return msg;
}

applyArousalPA(float amount, string bodypart)
{
    llMessageLinked(LINK_SET, 0,
        "caeilarousalup|" + (string)wearer + "|" + (string)((integer)amount) + "|" + bodypart, "");
}

// ALL haptics (load / creampie / orgasm / level-up buzz) now live in inm_immersion —
// it owns the Lovense relay and reads level/arousal/lastCum from the broadcast, so it
// drives these buzzes itself. Core only still sends the "stop|0" on the menu toggle.

addXP(integer amount) {
    if (amount > 0) {
        // Track period XP for the daily/weekly goals (no per-day cap on earning).
        dailyXPGained  += amount;
        weeklyXPGained += amount;
    }

    integer prevLv = level;
    xp += amount;
    if (xp < 0) xp = 0;
    level = computeLevel();
    integer newLv = level;
    if (newLv > prevLv) {
        integer ti = newLv - 1;
        integer lastT = llGetListLength(TITLES) - 1;
        if (ti > lastT) ti = lastT;
        notifyPA(2, "✦ Lv." + (string)newLv + " — " + llList2String(TITLES, ti) + "! ✦");
        // Level-up buzz + the corruption arousalMultiplier are sent by inm_immersion
        // now (it sees the new level in the broadcast). Core just updates progression.
        if (selectedTitleIdx < 10) selectedTitleIdx = ti;   // auto-advance level title (keep prestige titles)
    }
    clampTitle();
}

// Session combo: each EXTRA unique partner this session adds +10% XP (cap +100%).
float getComboMult() {
    integer over = sessionPartnerCount - 1;
    if (over <= 0) return 1.0;
    if (over > 10) over = 10;
    return 1.0 + (float)over * 0.10;
}

// "In Heat" buff: timed XP multiplier set by a heat event or a creampie.
float getHeatMult() {
    if (llGetUnixTime() < heatUntil) return (float)HEAT_MULT_I / 100.0;
    return 1.0;
}

// Spunked typically lands 1-2 zones per act vs INM's many, so each Spunked load is
// worth more to keep an *act* worth similar XP on either system (INM still gets more
// loads, just lower-value each). SPUNKED_XP_MULT is declared up top with the XP consts.
float getSystemMult() {
    if (cumSystem == 0) return SPUNKED_XP_MULT;   // 0 = Spunked
    return 1.0;                                   // 1 = INM (the curve is tuned to it)
}

earnXP(integer base, float bodyMult) {
    addXP((integer)((float)base * getXPMultiplier() * bodyMult * getAudienceMult()
        * getPrestigeMult() * getComboMult() * getHeatMult() * getSystemMult() + 0.5));
}

// Grant a reward the CorruptionRewards.lsl evaluator decided we earned:
// str = "<kind>|<bit>|<amount>|<label>", kind = ach | dg (daily goal) | wg (weekly).
// Core is the single source of truth: it sets the persisted flag bit (dedup-guarded
// so a duplicate / in-flight grant is harmless) and awards the flat bonus XP. The
// bonus is added directly (NOT via addXP) so it doesn't itself count toward XP goals.
grantReward(string str) {
    list r       = llParseString2List(str, ["|"], []);
    string kind  = llList2String(r, 0);
    integer bit  = (integer)llList2String(r, 1);
    integer amt  = (integer)llList2String(r, 2);
    string label = llList2String(r, 3);
    r = [];

    if (kind == "ach")      { if (achFlags      & bit) return; achFlags      = achFlags      | bit; }
    else if (kind == "dg")  { if (dailyClaimed  & bit) return; dailyClaimed  = dailyClaimed  | bit; }
    else if (kind == "wg")  { if (weeklyClaimed & bit) return; weeklyClaimed = weeklyClaimed | bit; }
    else return;

    xp += amt;
    level = computeLevel();
    clampTitle();
    notifyPA(2, "✦ " + label + " complete! +" + (string)amt + " XP ✦");
    saveState();
    updateDisplay();
}

onOrgasm() {
    // Diminishing returns: each orgasm this session earns 70% of the last
    integer orgasmXP = (XP_ORGASM * orgasmXPPercent) / 100;
    if (orgasmXP < 5) orgasmXP = 5;
    orgasmXPPercent = (orgasmXPPercent * 95) / 100;
    if (orgasmXPPercent < 5) orgasmXPPercent = 5;
    orgasmXP = (integer)((float)orgasmXP * getAudienceMult() * getPrestigeMult() + 0.5);
    addXP(orgasmXP);
    notifyPA(1, "✦ Orgasm! +" + (string)orgasmXP + " XP");
    // Orgasm buzz is handled by inm_immersion (its finishOrgasm fires on the same PA
    // arousalOrgasm event) — sending it here too would double-buzz the toy.
    saveState();
    updateDisplay();   // broadcast → rewards script picks up any newly-met XP goal
}

resetSession() {
    sFace = sPussy = sAss = sChest = sBody = 0;
    sessionPartners     = [];
    sessionPartnerCount = 0;
    orgasmXPPercent     = 100;
}

// Broadcast settings the menu script needs to render its dialogs. Concatenated
// (not a 21-element list literal) to avoid a transient-list heap spike. Field order
// and "|" separator MUST match the menu's parse; field 16 = daily XP GOAL.
broadcastState() {
    llMessageLinked(LINK_SET, MENU_STATE,
          (string)level + "|" + (string)difficulty + "|" + (string)immersionOn + "|" + (string)adultBypass + "|" + (string)cumSystem // 0-4 (2=immersionOn, 3=adultBypass)
        + "|" + (string)isLocked + "|" + (string)showTitle + "|" + (string)showStatus                      // 5-7
        + "|" + (string)((integer)rotateInterval) + "|" + (string)prestigeLevel                            // 8-9
        + "|" + (string)lastCumTime + "|" + (string)IDLE_THRESHOLD + "|" + (string)DECAY_INTERVAL + "|" + (string)DECAY_AMOUNT // 10-13
        + "|" + (string)dailyXPGained + "|" + (string)dayStartTime + "|" + (string)DAILY_GOAL_XP           // 14-16
        + "|" + (string)hapticsOn + "|" + (string)ambientGapMax + "|" + (string)ambientGapMin              // 17-19
        + "|" + (string)diffChosen                                                                         // 20
        + "|" + ownerName + "|" + (string)selectedTitleIdx, "");                                            // 21 owner name (Dialog shows the title btn), 22 current title idx
}

saveState() {
    // Direct concatenation, NOT a 48-element list literal — this runs at the deep
    // cum-event tail, so allocating a transient list here was a heap-peak spike (the
    // cause of Stack-Heap collisions). Same approach as updateDisplay(). Field order
    // and the "," separator MUST stay identical and APPEND-ONLY (DB blob compat).
    // lastPartnerName (field 40) was comma-stripped at capture, so it's CSV-safe.
    llLinksetDataWrite("inm_state",
          (string)totalCount + "," + (string)pussyCount + "," + (string)assCount      // 0-2
        + "," + (string)faceCount + "," + (string)chestCount + "," + (string)creampieCount // 3-5
        + "," + (string)bodyCount + "," + (string)xp + "," + (string)selectedTitleIdx  // 6-8
        + "," + (string)lastCumTime + "," + (string)difficulty + "," + (string)dailyXPGained // 9-11
        + "," + (string)dayStartTime + "," + (string)cumSystem + "," + (string)lastDecayTime // 12-14
        + "," + (string)lastMultSentTime + "," + (string)(!immersionOn) + "," + (string)adultBypass // 15-17 (16=!immersionOn, 17=adult bypass)
        + "," + (string)prestigeLevel + "," + (string)(showTitle + showStatus * 2) + "," + (string)isLocked // 18-20
        + "," + (string)sFace + "," + (string)sPussy + "," + (string)sAss + "," + (string)sChest + "," + (string)sBody // 21-25
        + "," + (string)cFace + "," + (string)cChest + "," + (string)cPussy + "," + (string)cAss + "," + (string)cBody // 26-30
        + "," + (string)achFlags + "," + (string)weeklyXPGained + "," + (string)weekStartTime // 31-33
        + "," + (string)dailyClaimed + "," + (string)weeklyClaimed                      // 34-35
        + "," + (string)notoriety + "," + (string)heatUntil + "," + (string)hapticsOn   // 36-38
        + "," + (string)sessionPartnerCount + "," + lastPartnerName                     // 39-40 (name comma-free)
        + "," + (string)ambientGapMin + "," + (string)ambientGapMax                     // 41-42 passive-vibe idle range
        + "," + (string)diffChosen                                                      // 43 difficulty locked (anti-cheat)
        + "," + (string)dailyPartners + "," + (string)weeklyPartners                    // 44-45 goal counters
        + "," + (string)dailyLoads + "," + (string)weeklyLoads                          // 46-47
        + "," + (string)oralCreamCount + "," + (string)analCreamCount                   // 48-49 INM internal creampie counts
        + "," + (string)cThroat + "," + (string)cAnal                                   // 50-51 live mirror (throat/anal)
        + "," + (string)cVagCream                                                       // 52 live mirror (vaginal creampie)
        + "," + (string)maxAudience                                                      // 53 peak audience during an act (Exhibitionist)
        + "," + ownerName);                                                             // 54 owner name (comma/pipe-free; "" if unowned)
    broadcastState();
}

loadState() {

    llOwnerSay("Loading user...");
    string d = llLinksetDataRead("inm_state");
    if (d == "" || llSubStringIndex(d, ",") == -1) return;
    // KeepNulls so an empty name field can't shift the idle-range fields after it.
    list parts = llParseStringKeepNulls(d, [","], []);
    d = ""; // free raw string early
    integer n = llGetListLength(parts);
    if (n < 6) return;
    totalCount    = (integer)llList2String(parts, 0);
    pussyCount    = (integer)llList2String(parts, 1);
    assCount      = (integer)llList2String(parts, 2);
    faceCount     = (integer)llList2String(parts, 3);
    chestCount    = (integer)llList2String(parts, 4);
    creampieCount = (integer)llList2String(parts, 5);
    if (n >= 7) bodyCount        = (integer)llList2String(parts, 6);
    if (n >= 8) xp               = (integer)llList2String(parts, 7);
    if (n >= 9) selectedTitleIdx = (integer)llList2String(parts, 8);
    if (n >= 10) lastCumTime = (integer)llList2String(parts, 9);
    // (slot 16 = !immersionOn, slot 17 = adultBypass — both reuse old custom-diff placeholders)
    if (n >= 11) setDifficulty((integer)llList2String(parts, 10));
    else         setDifficulty(difficulty);
    if (n >= 12) dailyXPGained = (integer)llList2String(parts, 11);
    if (n >= 13) dayStartTime  = (integer)llList2String(parts, 12);
    if (n >= 14) cumSystem     = (integer)llList2String(parts, 13);
    if (n >= 15) lastDecayTime    = (integer)llList2String(parts, 14);
    if (n >= 16) lastMultSentTime = (integer)llList2String(parts, 15);
    if (n >= 19) prestigeLevel = (integer)llList2String(parts, 18);
    if (n >= 20) {
        integer df = (integer)llList2String(parts, 19);
        showTitle  = df & 1;
        showStatus = (df >> 1) & 1;
    }
    if (n >= 21) isLocked = (integer)llList2String(parts, 20);
    if (n >= 22) sFace  = (integer)llList2String(parts, 21);
    if (n >= 23) sPussy = (integer)llList2String(parts, 22);
    if (n >= 24) sAss   = (integer)llList2String(parts, 23);
    if (n >= 25) sChest = (integer)llList2String(parts, 24);
    if (n >= 26) sBody  = (integer)llList2String(parts, 25);
    if (n >= 27) cFace  = (integer)llList2String(parts, 26);
    if (n >= 28) cChest = (integer)llList2String(parts, 27);
    if (n >= 29) cPussy = (integer)llList2String(parts, 28);
    if (n >= 30) cAss   = (integer)llList2String(parts, 29);
    if (n >= 31) cBody  = (integer)llList2String(parts, 30);
    if (n >= 32) achFlags       = (integer)llList2String(parts, 31);
    if (n >= 33) weeklyXPGained = (integer)llList2String(parts, 32);
    if (n >= 34) weekStartTime  = (integer)llList2String(parts, 33);
    if (n >= 35) dailyClaimed   = (integer)llList2String(parts, 34);
    if (n >= 36) weeklyClaimed  = (integer)llList2String(parts, 35);
    if (n >= 37) notoriety      = (integer)llList2String(parts, 36);
    if (n >= 38) heatUntil      = (integer)llList2String(parts, 37);
    if (n >= 39) hapticsOn      = (integer)llList2String(parts, 38);
    if (n >= 40) sessionPartnerCount = (integer)llList2String(parts, 39);
    if (n >= 41) lastPartnerName     = llList2String(parts, 40);
    if (n >= 42) ambientGapMin       = (integer)llList2String(parts, 41);
    if (n >= 43) ambientGapMax       = (integer)llList2String(parts, 42);
    if (n >= 44) diffChosen          = (integer)llList2String(parts, 43);
    if (n >= 45) dailyPartners       = (integer)llList2String(parts, 44);
    if (n >= 46) weeklyPartners      = (integer)llList2String(parts, 45);
    if (n >= 47) dailyLoads          = (integer)llList2String(parts, 46);
    if (n >= 48) weeklyLoads         = (integer)llList2String(parts, 47);
    if (n >= 49) oralCreamCount      = (integer)llList2String(parts, 48);
    if (n >= 50) analCreamCount      = (integer)llList2String(parts, 49);
    if (n >= 51) cThroat             = (integer)llList2String(parts, 50);
    if (n >= 52) cAnal               = (integer)llList2String(parts, 51);
    if (n >= 53) cVagCream           = (integer)llList2String(parts, 52);
    if (n >= 54) maxAudience         = (integer)llList2String(parts, 53);
    if (n >= 55) ownerName           = llList2String(parts, 54);     // owner bond (CorruptionMatch re-asserts it on attach anyway)
    if (n >= 17) immersionOn = !(integer)llList2String(parts, 16);   // slot 16: 0=on (old placeholder default)
    // slot 17 (old custom-diff placeholder) reused for adultBypass; == 1 guard so a
    // legacy non-0/1 value there can't accidentally turn the safety bypass on.
    if (n >= 18) adultBypass = ((integer)llList2String(parts, 17) == 1);
    parts = []; // free heap
    level = computeLevel();   // refresh cache from loaded xp before clampTitle
    clampTitle();
    llOwnerSay("User loaded, welcome back " + llGetDisplayName(wearer) + "!  "
        + "[mem: " + (string)llGetUsedMemory() + " used / "
        + (string)llGetFreeMemory() + " free]");
}

// Calculates offline idle time and applies accumulated XP decay.
// Called on attach/rez so the HUD can't be cheated by taking it off.
applyAccumulatedDecay() {
    integer now = llGetUnixTime();
    if (now - lastCumTime < IDLE_THRESHOLD) return;

    // Start counting from when decay first kicked in, or from last applied tick —
    // whichever is later, to avoid re-applying ticks the timer already handled.
    integer decayStart = lastCumTime + IDLE_THRESHOLD;

    if (lastDecayTime > decayStart)
        decayStart = lastDecayTime;

    integer ticks = (now - decayStart) / DECAY_INTERVAL;

    if (ticks <= 0) return;

    lastDecayTime = decayStart + (ticks * DECAY_INTERVAL);   // advance the clock regardless

    integer loss    = ticks * DECAY_AMOUNT;
    integer floorXP = xpFloor();
    if (xp - loss < floorXP) loss = xp - floorXP;   // never decay past the current level base
    if (loss <= 0) return;                          // already at the floor — nothing to lose

    addXP(-loss);
    notifyPA(2, "-" + (string)loss + " XP (" + (string)ticks + "h idle decay)");
    saveState();
    updateDisplay();
}

// ── PA integration ────────────────────────────────────

notifyPA(integer msgType, string msg) {
    llMessageLinked(LINK_SET, 0,
        "arousalSetText|" + (string)wearer + "|" + (string)msgType + "|" + msg, "");
}

// The level-up corruption arousalMultiplier is sent by inm_immersion now (it owns the
// level-up reactions). lastMultSentTime stays as a persisted placeholder (save slot 15)
// for append-only compatibility; it is simply no longer updated here.

// ── achievements + goals ───────────────────────────────
// Both are now EVALUATED in CorruptionRewards.lsl (it reads the HUD broadcast and
// calls grantReward() above when something newly qualifies). achFlags / dailyClaimed
// / weeklyClaimed and all the counters still live + persist here — only the
// threshold/label tables moved out, so Core stops growing as we add achievements.
// achFlags bits: 1 First Creampie | 2 All Holes | 4 Exhibitionist | 8 Town Toy |
// 16 Head to Toe | 32/64/128 prestige | 256 Gangbang | 512 Soaked | 1024 Local Legend.

// ── cum system handlers ────────────────────────────────

// Pre-parsed cum data (Spunked or INM relay): 10 current (0-9), 10 deltas (10-19).
// Slots 8/9 = oral & anal creampie (INM only; 0 from Spunked).
processLinkedSpunked(string data, key instigator) {
    list p = llParseString2List(data, ["|"], []);
    integer curHead  = clamp0(llList2Integer(p, 0));
    integer curChest = clamp0(llList2Integer(p, 1));
    integer curGroin = clamp0(llList2Integer(p, 2));
    integer curBack  = clamp0(llList2Integer(p, 3));
    integer curButt  = clamp0(llList2Integer(p, 4));
    integer curArms  = clamp0(llList2Integer(p, 5));
    integer curLegs  = clamp0(llList2Integer(p, 6));
    integer curCream = clamp0(llList2Integer(p, 7));
    integer curOral  = clamp0(llList2Integer(p, 8));
    integer curAnal  = clamp0(llList2Integer(p, 9));
    integer dHead    = llList2Integer(p, 10);
    integer dChest   = llList2Integer(p, 11);
    integer dGroin   = llList2Integer(p, 12);
    integer dBack    = llList2Integer(p, 13);
    integer dButt    = llList2Integer(p, 14);
    integer dArms    = llList2Integer(p, 15);
    integer dLegs    = llList2Integer(p, 16);
    integer dCream   = llList2Integer(p, 17);
    integer dOral    = llList2Integer(p, 18);
    integer dAnal    = llList2Integer(p, 19);
    p = []; // free early

    // Refresh live body mirror (current stacks) used by the status line / dirty checks
    cFace     = curHead;
    cThroat   = curOral;     // 0 on Spunked
    cChest    = curChest;
    cPussy    = curGroin + curCream;
    cVagCream = curCream;    // vaginal creampie split out (both systems)
    cAss      = curButt;
    cAnal     = curAnal;     // 0 on Spunked
    cBody     = curBack + curArms + curLegs;

    // No deltas — state report only, nothing to process
    if (dHead <= 0 && dChest <= 0 && dGroin <= 0 && dBack <= 0 &&
        dButt <= 0 && dArms  <= 0 && dLegs  <= 0 && dCream <= 0 &&
        dOral <= 0 && dAnal <= 0) return;

    if (instigator != NULL_KEY && instigator != wearer) {
        if (llListFindList(sessionPartners, [(string)instigator]) == -1) {
            sessionPartners += [(string)instigator];
            sessionPartnerCount++;
            totalCount++;
            dailyPartners++;        // daily/weekly partner goals
            weeklyPartners++;
        }
        string fullName = llGetDisplayName(instigator);
        integer spaceIdx = llSubStringIndex(fullName, " ");
        if (spaceIdx > 0) fullName = llGetSubString(fullName, 0, spaceIdx - 1);
        // Strip commas HERE (once per new partner) so saveState — which runs at the
        // deep cum-event tail — doesn't rebuild a list every single save.
        lastPartnerName = llDumpList2String(llParseString2List(fullName, [","], []), "");
    }

    integer evNow = llGetUnixTime();
    if (evNow - lastCumTime >= NOTORIETY_GAP) {
        notedThisAct = FALSE;
        reliefDone   = FALSE;
    }
    lastCumTime = evNow;
    lastDecayTime = evNow;

    // Edging payoff: ONCE per act, on the first event — based on how built-up she
    // was. Gated so later loads (which themselves raise arousal) don't re-grant it.
    if (!reliefDone) {
        integer relief = (integer)(paArousal / 400.0 * (float)RELIEF_MAX);
        if (relief > 0) { addXP(relief); notifyPA(1, "Relief! +" + (string)relief + " XP ♥"); }
        reliefDone = TRUE;
    }

    // Notoriety: counted ONCE per act (first witnessed event). Subsequent loads
    // in the same scene don't re-add; it re-arms after NOTORIETY_GAP of no events.
    if (nearbyCount > 0 && !notedThisAct) { notoriety += nearbyCount; notedThisAct = TRUE; }

    // Largest audience present while she was actually being used (drives the Exhibitionist
    // achievement — so it can't be earned just by standing near a crowd, only by a load
    // landing with people watching). This block only runs on a real act (past the no-delta return).
    if (nearbyCount > maxAudience) maxAudience = nearbyCount;

    if (dHead  > 0) { faceCount++;  sFace++;  earnXP(XP_FACE,     1.0);      applyArousalPA((float)XP_FACE     * 0.5, "noanim"); }
    if (dChest > 0) { chestCount++; sChest++; earnXP(XP_CHEST,    boobMult); applyArousalPA((float)XP_FACE     * 0.5, "boobs");  }
    if (dGroin > 0) { pussyCount++; sPussy++; earnXP(XP_CHEST,    vagMult);  applyArousalPA((float)XP_CHEST    * 0.5, "vagina"); }
    if (dCream > 0) { pussyCount++; sPussy++; creampieCount++; earnXP(XP_CREAMPIE, vagMult); applyArousalPA((float)XP_CREAMPIE * 0.5, "vagina");
                      heatUntil = lastCumTime + HEAT_DUR; }   // a creampie puts her "In Heat"
    if (dButt  > 0) { assCount++;   sAss++;   earnXP(XP_CHEST,    buttMult); applyArousalPA((float)XP_CHEST    * 0.5, "butt");   }
    if (dBack  > 0) { bodyCount++;  sBody++;  earnXP(XP_BODY, 1.0);          applyArousalPA((float)XP_BODY     * 0.5, "noanim"); }
    if (dArms  > 0) { bodyCount++;  sBody++;  earnXP(XP_BODY, 1.0);          applyArousalPA((float)XP_BODY     * 0.5, "noanim"); }
    if (dLegs  > 0) { bodyCount++;  sBody++;  earnXP(XP_BODY, 1.0);          applyArousalPA((float)XP_BODY     * 0.5, "noanim"); }
    // INM-only internal creampies (oral/anal). No "In Heat" — only a vaginal creampie breeds.
    if (dOral  > 0) { oralCreamCount++; earnXP(XP_FACE,  1.0);     applyArousalPA((float)XP_FACE  * 0.5, "noanim"); }
    if (dAnal  > 0) { analCreamCount++; earnXP(XP_CHEST, buttMult); applyArousalPA((float)XP_CHEST * 0.5, "butt");   }

    // Count loads received this event (one per zone hit) for the daily/weekly load goals.
    integer ld = (dHead>0) + (dChest>0) + (dGroin>0) + (dCream>0) + (dButt>0) + (dBack>0) + (dArms>0) + (dLegs>0) + (dOral>0) + (dAnal>0);
    dailyLoads  += ld;
    weeklyLoads += ld;

    // Load/creampie haptic buzz is driven by inm_immersion now: it sees lastCumTime
    // (and creampieCount) advance in this broadcast and fires the buzz immediately.
    updateDisplay();   // broadcast → inm_rewards (ach/goals) + inm_immersion (haptics)
    saveState();
}

// Resync the body mirror from an InTotalEncodedV2 reply (8 current stacks, no
// deltas/XP/logic). Recovers true Spunked state on (re)attach.
applySpunkedSync(string data) {
    list p = llParseString2List(data, ["|"], []);
    integer h  = clamp0(llList2Integer(p, 0));
    integer ch = clamp0(llList2Integer(p, 1));
    integer g  = clamp0(llList2Integer(p, 2));
    integer bk = clamp0(llList2Integer(p, 3));
    integer bt = clamp0(llList2Integer(p, 4));
    integer a  = clamp0(llList2Integer(p, 5));
    integer l  = clamp0(llList2Integer(p, 6));
    integer cr = clamp0(llList2Integer(p, 7));
    integer or = clamp0(llList2Integer(p, 8));   // oral creampie (INM only; 0 from Spunked)
    integer an = clamp0(llList2Integer(p, 9));   // anal creampie (INM only)
    p = [];

    cFace = h; cThroat = or; cChest = ch; cPussy = g + cr; cVagCream = cr; cAss = bt; cAnal = an; cBody = bk + a + l;
    saveState();
    updateDisplay();
}

// Future INM support: add an inm_inm.lsl relay forwarding on a new num, handled
// here like processLinkedSpunked.

// Player commands from inm_menu.lsl (via MENU_CMD).
processMenuCmd(string str) {
    list c = llParseString2List(str, ["|"], []);
    string cmd = llList2String(c, 0);

    if (cmd == "title") {
        integer idx = (integer)llList2String(c, 1);
        integer ok = FALSE;
        if (idx == OWNER_TITLE_IDX) {
            if (ownerName != "") ok = TRUE;   // only selectable while actually owned
        }
        else if (idx >= 10) {
            integer pi = idx - 10;   // prestige title: gated by prestige, not level
            if (pi < llGetListLength(PRESTIGE_TITLES) &&
                prestigeLevel >= llList2Integer(PRESTIGE_TITLE_REQ, pi)) ok = TRUE;
        }
        else if (idx >= 0 && idx < level) ok = TRUE;
        if (ok) {
            selectedTitleIdx = idx;
            saveState();
            updateDisplay();
        }
    }
    else if (cmd == "reset") {
        totalCount = pussyCount = assCount = faceCount = chestCount =
            creampieCount = bodyCount = xp = selectedTitleIdx = 0;
        oralCreamCount = analCreamCount = cThroat = cAnal = cVagCream = inmFlags = 0;
        maxAudience    = 0;
        level = 1;
        dailyXPGained  = 0;
        dayStartTime   = llGetUnixTime();
        prestigeLevel  = 0;
        achFlags       = 0;             // "Reset ALL stats" → clear achievements too
        weeklyXPGained = 0;
        weekStartTime  = llGetUnixTime();
        dailyClaimed   = 0;
        weeklyClaimed  = 0;
        dailyPartners  = 0;
        weeklyPartners = 0;
        dailyLoads     = 0;
        weeklyLoads    = 0;
        notoriety      = 0;
        heatUntil      = 0;
        notedThisAct   = FALSE;
        reliefDone     = FALSE;
        diffChosen     = FALSE;          // unlock difficulty → menu re-prompts the choice
        lastCumTime   = llGetUnixTime(); // reset idle clock so decay doesn't kick in immediately
        lastDecayTime = lastCumTime;
        resetSession();
        llLinksetDataReset();
        string snap = updateDisplay();
        broadcastState();
        // Push the zeroed snapshot to the DB now (don't wait for the debounce —
        // otherwise a reset-then-detach could leave stale progress that a fresh
        // object would restore).
        llMessageLinked(LINK_SET, DB_FLUSH, snap, NULL_KEY);
    }
    else if (cmd == "display") {
        integer df = (integer)llList2String(c, 1);
        showTitle  = df & 1;
        showStatus = (df >> 1) & 1;
        saveState();
        updateDisplay();
    }
    else if (cmd == "prestige") {
        if (prestigeLevel >= PRESTIGE_MAX) {
            llOwnerSay("You've already reached maximum prestige (" + (string)PRESTIGE_MAX + ").");
            return;
        }
        prestigeLevel++;
        xp               = 0;
        level            = 1;
        selectedTitleIdx = 0;
        resetSession();
        saveState();
        updateDisplay();             // broadcast → rewards script awards prestige achievements
        notifyPA(2, "✦ Prestige " + prestigePrefix(prestigeLevel)
            + "— reborn filthier! Permanent +" + (string)(prestigeLevel * 10) + "% XP ✦");
    }
    else if (cmd == "difficulty") {
        // Locked once chosen — only a Reset can clear diffChosen and allow a re-pick.
        if (diffChosen) { llOwnerSay("🔒 Difficulty is locked. Reset your stats to choose again."); return; }
        setDifficulty((integer)llList2String(c, 1));
        diffChosen = TRUE;
        saveState();
        updateDisplay();
        llOwnerSay("Difficulty set and locked in. Reset stats to change it.");
    }
    else if (cmd == "cumSystem") {
        cumSystem = (integer)llList2String(c, 1);
        if (cumSystem == 0) inmFlags = 0;   // Spunked has no plug/drip/etc. — clear stale INM flags
        saveState();
        updateDisplay();
        llOwnerSay("Cum system updated.");
    }
    else if (cmd == "rotate") {
        rotateInterval = (float)llList2String(c, 1);   // display threshold only; the timer stays fixed at 5s
        saveState();
        llOwnerSay("Rotate interval set to " + (string)((integer)rotateInterval) + "s.");
    }
    else if (cmd == "lock") {
        integer wantLock = (integer)llList2String(c, 1);
        if (wantLock) {
            isLocked = TRUE;
            llOwnerSay("@detach=n");
            saveState();
            llOwnerSay("System locked. Core settings can't be changed.");
        } else {
            if (bodyDirty()) {
                llOwnerSay("Cannot unlock while cum is detected on your body. Clean up first.");
                return;
            }
            isLocked = FALSE;
            llOwnerSay("@detach=y");
            saveState();
            llOwnerSay("System unlocked.");
        }
    }
    else if (cmd == "haptics") {
        if (isLocked) {
            llOwnerSay("🔒 System is locked. Unlock to change haptic settings.");
            return;
        }
        hapticsOn = (integer)llList2String(c, 1);
        if (!hapticsOn) llMessageLinked(LINK_SET, HAPTIC_EVENT, "stop|0", NULL_KEY); // silence the toy now
        saveState();
        broadcastState();
        if (hapticsOn) llOwnerSay("Lovense enabled."); else llOwnerSay("Lovense disabled.");
    }
    else if (cmd == "immersion") {
        if (isLocked) {
            llOwnerSay("🔒 System is locked. Unlock to change immersion settings.");
            return;
        }
        immersionOn = (integer)llList2String(c, 1);
        saveState();        // persists (slot 16) + broadcasts to menu
        updateDisplay();    // pushes immersionOn to inm_immersion on the HUD broadcast
        if (immersionOn) llOwnerSay("Immersion features enabled."); else llOwnerSay("Immersion features disabled.");
    }
    else if (cmd == "adultbypass") {
        if (isLocked) {
            llOwnerSay("🔒 System is locked. Unlock to change this.");
            return;
        }
        adultBypass = (integer)llList2String(c, 1);
        saveState();        // persists (slot 48) + broadcasts to menu
        updateDisplay();    // pushes adultBypass to inm_immersion (HUD field 57)
        if (adultBypass) llOwnerSay("⚠ Adult-region bypass ON — arousal will play in non-Adult regions too.");
        else             llOwnerSay("Adult-region bypass OFF — arousal restricted to Adult regions (safe default).");
    }
    else if (cmd == "vibeidle") {
        if (isLocked) {
            llOwnerSay("🔒 System is locked. Unlock to change vibe idle settings.");
            return;
        }
        ambientGapMin = (integer)llList2String(c, 1);
        ambientGapMax = (integer)llList2String(c, 2);
        if (ambientGapMin < 60)   ambientGapMin = 60;
        if (ambientGapMin > 1800) ambientGapMin = 1800;
        if (ambientGapMax < ambientGapMin) ambientGapMax = ambientGapMin;
        if (ambientGapMax > 1800) ambientGapMax = 1800;
        saveState();   // persists the range in inm_state (→ DB blob) and broadcasts to the menu
        llOwnerSay("Passive vibe idle: " + (string)(ambientGapMin / 60) + "-"
            + (string)(ambientGapMax / 60) + " min between buzzes.");
    }
    else if (cmd == "req") {
        broadcastState();
    }
    c = [];
}

// Refresh on every attach/rez/start: load state, apply idle decay, re-assert
// the RLV lock, push fresh data. Called from state_entry, on_rez and attach.
reinit()
{
    loadState();                  // loadState calls setDifficulty + loads the idle range
    // Idle range now lives in the save blob (→ DB backup); just enforce bounds.
    if (ambientGapMin < 60)   ambientGapMin = 60;     // 1-min floor
    if (ambientGapMin > 1800) ambientGapMin = 1800;
    if (ambientGapMax < ambientGapMin) ambientGapMax = ambientGapMin;
    if (ambientGapMax > 1800) ambientGapMax = 1800;   // 30-min cap
    llLinksetDataDelete("inm_cfg");   // legacy key, no longer used (one-time cleanup)
    if (lastCumTime == 0) lastCumTime = llGetUnixTime();
    if (lastDecayTime == 0) lastDecayTime = lastCumTime + IDLE_THRESHOLD;
    if (dayStartTime == 0)  dayStartTime  = llGetUnixTime();
    if (weekStartTime == 0) weekStartTime = llGetUnixTime();
    applyAccumulatedDecay();
    if (isLocked) llOwnerSay("@detach=n");
    updateDisplay();
    broadcastState();
    llMessageLinked(LINK_SET, 0, "getArousalMultipliers|" + (string)wearer, "");
}

default {
    state_entry()
    {
        wearer     = llGetOwner();
        setDifficulty(difficulty); 
        reinit();
        llSetAlpha(0, ALL_SIDES);
        llSetTimerEvent(5.0);
    }

    on_rez(integer param)
    {
        reinit();
    }

    attach(key id)
    {
        if (id != NULL_KEY) reinit(); 
    }

    link_message(integer sender_num, integer num, string str, key id)
    {
        // Spunked relay from inm_spunked.lsl
        if (num == SPUNKED_EVENT) { processLinkedSpunked(str, id); return; }
        if (num == SPUNKED_SYNC)  { applySpunkedSync(str); return; }

        // INM-only live flags (plug/drip/glazed/rlv). A creampied-and-plugged hole keeps
        // her "In Heat" (the load stays in). Re-broadcast only when the flags change so
        // the overlay/rewards/immersion pick them up promptly.
        if (num == INM_STATE) {
            integer nf = (integer)str;
            if (nf & 1) heatUntil = llGetUnixTime() + HEAT_DUR;   // bit1 = bred & plugged
            if (nf != inmFlags) { inmFlags = nf; updateDisplay(); }
            return;
        }

        // Menu commands from inm_menu.lsl
        if (num == MENU_CMD) { processMenuCmd(str); return; }

        // Reward grant from inm_rewards.lsl (achievement/goal newly earned)
        if (num == REWARD_GRANT) { grantReward(str); return; }

        // Owner bond set/cleared by CorruptionMatch. str = owner display name ("" = unbound).
        // Name is comma/pipe-stripped by the match script so it's save/broadcast safe.
        if (num == OWNER_SET) {
            ownerName = str;
            if (ownerName == "" && selectedTitleIdx == OWNER_TITLE_IDX) {
                selectedTitleIdx = level - 1;   // bond gone → fall back to the current level title
                clampTitle();
            }
            saveState();
            updateDisplay();
            return;
        }

        // DB restore: inm_db wrote a backed-up save into Linkset Data; reload it
        if (num == DB_RESTORE) {
            loadState();
            updateDisplay();
            broadcastState();
            llOwnerSay("Progress restored from cloud backup.");
            return;
        }

        // In-Heat buff: inm_immersion fired a passive heat event → start the 1.5× XP
        // buff (XP balancing stays here; immersion only owns the trigger timing).
        if (num == HEAT_SET) {
            heatUntil = llGetUnixTime() + HEAT_DUR;
            updateDisplay();
            return;
        }

        list    args         = llParseString2List(str, ["|"], [""]);
        string  preParseTask = llList2String(args, 0);
        integer taskIndex    = llSubStringIndex(preParseTask, (string)wearer);
        string  task         = llDeleteSubString(str, taskIndex, -1);
        float   arg1f        = llList2Float(args, 1);
        float   arg2f        = llList2Float(args, 2);
        float   arg3f        = llList2Float(args, 3);
        float   arg4f        = llList2Float(args, 4);
        args = []; preParseTask = "";

        if (task == "arousal") {
            paArousal   = arg1f;
            paCloseness = arg2f;
            updateDisplay();
            return;
        }
        else if (task == "arousalOrgasm") {
            onOrgasm();
            return;
        }
        else if (task == "multipliers") {
            vagMult  = arg1f;
            boobMult = arg3f;
            buttMult = arg4f;
            return;
        }
    }


    timer()
    {
        integer now = llGetUnixTime();
        timerTick++;

        // Periodic refresh (~10s) so audience / heat / multiplier display stays current.
        // Page rotation is the OVERLAY's job now — Core no longer flips a page.
        if (timerTick % 2 == 0) updateDisplay();

        // Light audience read so "watched" feeds XP/notoriety (and is broadcast to
        // inm_immersion for its arousal engine). sensor()/no_sensor() keep it current.
        if (timerTick % 60 == 0)
            llSensor("", NULL_KEY, AGENT, (float)AUDIENCE_RANGE, PI);

        // XP decay — still ONLY after a long idle (the punishment window).
        if (now - lastCumTime >= IDLE_THRESHOLD)
        {
            integer decayStart = lastCumTime + IDLE_THRESHOLD;

            if (lastDecayTime < decayStart)
                lastDecayTime = decayStart;

            integer ticks = (now - lastDecayTime) / DECAY_INTERVAL;

            if (ticks > 0)
            {
                lastDecayTime += ticks * DECAY_INTERVAL;

                integer loss    = ticks * DECAY_AMOUNT;
                integer floorXP = xpFloor();
                if (xp - loss < floorXP) loss = xp - floorXP;   // never decay past the level base

                if (loss > 0)
                {
                    addXP(-loss);
                    saveState();
                    updateDisplay();
                }
            }
        }

        if (timerTick >= 60) {
            timerTick = 0;
            llMessageLinked(LINK_SET, 0, "getArousalMultipliers|" + (string)wearer, "");
        }

        if (now - dayStartTime >= 86400) {
            resetSession();
            dayStartTime  = now;
            dailyXPGained = 0;
            dailyClaimed  = 0;
            dailyPartners = 0;
            dailyLoads    = 0;
            saveState();
            updateDisplay();
        }
        if (now - weekStartTime >= 604800) {   // 7 days
            weekStartTime  = now;
            weeklyXPGained = 0;
            weeklyClaimed  = 0;
            weeklyPartners = 0;
            weeklyLoads    = 0;
            saveState();
        }
    }

    sensor(integer num)
    {
        nearbyCount = num - 1;
        if (nearbyCount < 0) nearbyCount = 0;
    }

    no_sensor()
    {
        nearbyCount = 0;
    }

    changed(integer c)
    {
        // Wipe only on real owner change. NOT on CHANGED_INVENTORY — that fires
        // on any script edit/update and would erase saved progress.
        if (c & CHANGED_OWNER) {
            llLinksetDataReset();
            llResetScript();
        }
    }

}
