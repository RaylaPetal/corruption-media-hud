integer HUD_CHAN     = -87432;   // must match inm_monitor
integer HAPTIC_EVENT = 90200;    // → inm_lovense
integer HEAT_SET     = 88005;    // → inm_monitor: start the In-Heat XP buff
integer SPUNKED_CMD  = 4953;     // Spunked request channel (add/remove cum)

// ── master switches (constants for now; ask to add a menu toggle) ──
integer ENABLED       = TRUE;    // visible EFFECTS (moan/grope/strip). Arousal engine always runs.
integer STRIP_ENABLED = FALSE;    // RLV stripping (needs RLVa)

// ── arousal-engine constants (ported verbatim from Core) ──
integer PASSIVE_AROUSAL = 30;
integer HEAT_DUR        = 1800;  // must match Core (used here only for the re-trigger cooldown)
integer HEAT_COOLDOWN   = 3600;

// ── effect thresholds on arousalFrac (0..1; ~1.0 = max arousal / mid-act) ──
float   MOAN_AT   = 0.35;
float   GROPE_AT  = 0.55;
float   CLOSE_AT  = 0.75;
float   FRENZY_AT = 0.90;

// ── neglect: no act this long → pin arousal at max + relentless pump ──
integer NEGLECT_IDLE = 86400;    // 1 day (172800 for 2 days)
integer NEGLECT_PUSH = 40;       // flat arousal added per tick while neglected (> PA's ~5 decay)

float   TICK = 15.0;

list TOP_PARTS = ["rightboob","leftboob"];
list BOTTOM_PARTS = ["vagina"];

// ── sudden-urge tuning (the "spark") ──
float   URGE_BASE      = 2.0;    // base per-tick % chance for an urge to fire
float   URGE_IDLE_DIV  = 30.0;   // +1% to that chance per this many idle minutes
float   URGE_MAX       = 25.0;   // chance cap
integer URGE_GAP       = 2400;   // rest after a spike (~30-40 min before the urge can spike again)
integer URGE_SPIKE_MIN = 250;    // a spike lands at 250..400 arousal (capped at max)
integer URGE_SPIKE_RNG = 200;
integer NEEDY_MIN      = 240;    // idle minutes before an urge can tip to orgasm (4h)
float   ORGASM_CHANCE  = 35.0;   // % of urges (while needy) that go all the way
integer ORGASM_GAP     = 4200;   // rest after an orgasm (gap + rand(gap) = 1-2 h)
integer ORGASM_CUM     = 1;      // Spunked groin stacks added by a self-orgasm (resets the act timer)
integer ORGASM_MAX     = 90;     // safety: if groping hasn't caused a natural orgasm by now, force one

string curGropePart = "";

integer urgeCooldownUntil = 0;

// ── state from the broadcast ──
float   arousal     = 0.0;       // actual PA arousal 0-400 (raw from Core, NOT derived)
float   closeness   = 0.0;       // PA closeness 0-1 (>0 = mid-act building to orgasm)
float   arousalFrac = 0.0;       // arousal / 400  (pure arousal; closeness is separate)
float   prevFrac    = 0.0;
integer lastCum     = 0;
integer level       = 1;
integer mess        = 0;
integer nearbyCount = 0;
integer ambGapMin   = 180;
integer ambGapMax   = 600;
integer hapticsOn   = TRUE;
integer immersionOn = TRUE;      // master toggle (menu) — gates everything
integer regionAdult = TRUE;      // SAFETY: immersion only runs in Adult-rated regions
integer adultBypass = FALSE;     // owner override (menu): if TRUE, arousal runs in non-Adult regions too

// ── haptics + level-up reactions (moved from Core; driven off the broadcast) ──
// Per-level corruption arousal multiplier sent to PA on level-up (was Core's).
list CORRUPTION_MULT = [1.0, 1.05, 1.10, 1.20, 1.35, 1.50, 1.70, 1.90, 2.20, 2.50];
integer creampieCnt  = 0;        // creampieCount from the broadcast (field 17)
integer prevLevel    = -1;       // last level seen (-1 = not primed yet) → level-up buzz + mult
integer prevActCum   = -1;       // last cum-event time we fired an active buzz for
integer prevCreampie = -1;       // creampieCount at the last event (creampie vs load buzz)
integer actBuzzCD    = 0;        // throttle for the active load buzz (creampie forces through)

// ── engine state ──
integer passiveCooldown    = 0;
integer ambientVibeCDUntil = 0;
integer heatCDUntil        = 0;

// ── effect state ──
integer neglected    = FALSE;
integer wasNeglected = FALSE;
integer frenzy       = FALSE;
integer stripLevel   = 0;        // 0 none, 1 top removed, 2 bottom removed
integer curGrope     = 0;        // grope intensity currently set (avoid re-spam)
integer gropeUntil = 0;
integer gropeDelay = 0;          // delay between grope end and next possible start (tease rhythm)
integer gropeCounter = 0;        // self-gropes done this high-arousal episode (cap 3; resets when arousal<GROPE_AT or on relief)
integer moanCD       = 0;
integer prevLastCum  = -1;
integer orgasmMode    = FALSE;   // she's rubbing toward a natural orgasm (caught via PA's event)
integer strippedCurrentGrope = FALSE;  // whether we've already stripped for the current grope (only matters at high arousal)
integer upperLocked = FALSE;  // whether the upper attachment is currently locked off (waiting for low arousal to re-enable)
integer lowerLocked = FALSE;  // whether the lower attachment is currently locked off (waiting for

string  wearer;   // owner uuid string (refreshed on entry/attach)

// raw PA send (ungated — used by stopGrope so a grope/freeze can ALWAYS be released)
emitPA(string cmd)   { llMessageLinked(LINK_SET, 0, cmd, ""); }
// PA / avatar outputs — gated on immersionOn (the "arousal/immersion" features)
moan(integer tier)   { if (!immersionOn) return; emitPA("arousalForceMoan|" + wearer + "|" + (string)tier); }
notifyPA(integer ty, string m) { if (!immersionOn) return; emitPA("arousalSetText|" + wearer + "|" + (string)ty + "|" + m); }

// Lovense buzz — gated on hapticsOn (the "Lovense" feature), independent of immersion.
sendHaptic(string ev, integer inten) {
    if (!hapticsOn) return;
    llMessageLinked(LINK_SET, HAPTIC_EVENT, ev + "|" + (string)inten, NULL_KEY);
}

// live PA arousal 0-400 (raw from the broadcast)
float paNow() { return arousal; }

// Active-load buzz level 0-20 (closeness-weighted) — Core's old vibeLevel() formula.
// Closeness dominates (up to 1000 of the 1400 range) so the buzz ramps toward orgasm.
integer vibeLevelAct() {
    integer v = (integer)(20.0 * (arousal + 1000.0 * closeness) / 1400.0);
    if (v > 20) v = 20;
    if (v < 0)  v = 0;
    return v;
}

// Level-up corruption arousal multiplier → PA (moved from Core). Ungated like the old
// Core call (a progression buff, not a gated immersion effect); skipped at level 1.
sendCorruptionMult() {
    integer mi   = level - 1;
    integer last = llGetListLength(CORRUPTION_MULT) - 1;
    if (mi > last) mi = last;          // endless levels keep the top multiplier
    float mult = llList2Float(CORRUPTION_MULT, mi);
    if (mult <= 1.0) return;
    string multStr = llGetSubString((string)mult, 0, 4);
    emitPA("arousalMultiplier|" + wearer + "|all|" + multStr + "|86400");
    llOwnerSay("Corruption arousal boost: x" + multStr + " (24h)");
}

// SAFETY: the immersion system (moans, self-grope, orgasms, vibes) is only allowed in
// Adult-rated regions. Refresh the cached flag and announce a change to the owner.
updateRating() {
    integer wasAdult = regionAdult;
    // Bypass ON → always treat as Adult (owner opted to run arousal anywhere).
    regionAdult = (adultBypass || llToUpper(llGetEnv("region_rating")) == "ADULT");
    if (regionAdult != wasAdult) {
        if (regionAdult) llOwnerSay("Arousal resumed (Adult region).");
        else             llOwnerSay("Arousal paused — this region isn't Adult-rated.");
    }
}

// push arousal up, but never into the orgasm zone (passive must not finish her)
applyPassive(float amt) {
    if (!immersionOn) return;   // arousal pushes are an immersion (PA) output
    float cap = 400.0 - paNow();
    if (cap <= 0.0) return;
    if (amt > cap) amt = cap;
    if (amt < 1.0) return;
    emitPA("caeilarousalup|" + wearer + "|" + (string)((integer)amt) + "|noanim");
}

// tease vibe level from arousal during denial (closeness 0 → ~ paArousal/70)
integer vibeLvl() { return (integer)(arousalFrac * 5.7); }

// === vibe ENGINE — always on (core mechanic). Ported denial buildup + heat + tease. ===
vibeEngine(integer now)
{
    if (now < ambientVibeCDUntil)
        return;

    integer intensity = 5;

    if (mess > 0)
        intensity += mess;

    if (neglected)
        intensity += 5;

    if (intensity > 20)
        intensity = 20;

    sendHaptic("ambient", intensity);

    ambientVibeCDUntil = now + ambGapMin + (integer)llFrand((float)(ambGapMax - ambGapMin));
}

suddenUrge(integer now)
{
    if (now < urgeCooldownUntil) return;
    if (closeness > 0.0) return;   // she's mid-act / already climaxing — don't interfere

    integer idleMin = (now - lastCum) / 60;

    // Per-tick chance for an urge to fire; climbs the longer she's left unused.
    float chance = URGE_BASE + (float)idleMin / URGE_IDLE_DIV;
    if (chance > URGE_MAX) chance = URGE_MAX;
    if (llFrand(100.0) >= chance) return;

    // Needy too long → a chance this urge tips her all the way to orgasm, then a long rest.
    if (idleMin >= NEEDY_MIN && llFrand(200.0) < ORGASM_CHANCE)
    {
        if (llGetAgentInfo(wearer) & AGENT_SITTING) return;
        urgeCooldownUntil = now + ORGASM_GAP + (integer)llFrand((float)ORGASM_GAP);
        if (immersionOn)
        {
            notifyPA(1, "She's right on the edge..");
            orgasmMode = TRUE;
            strippedCurrentGrope = TRUE;        // don't strip mid-climax
            curGropePart = "vagina";
            emitPA("arousalGropeSelf|" + wearer + "|vagina|4");
            curGrope = 4;
            gropeUntil = now + ORGASM_MAX;      // safety deadline → force the orgasm if it stalls
            moan(2);
        }
        else
        {
            sendHaptic("orgasm", 20);           // immersion off, Lovense on → just the toy buzz
        }
        return;
    }

    // Otherwise: a sudden spike of need toward (but not past) max arousal.
    integer target = URGE_SPIKE_MIN + (integer)llFrand((float)URGE_SPIKE_RNG);
    integer spike  = target - (integer)paNow();
    if (spike > 0)
    {
        applyPassive((float)spike);
        notifyPA(1, "A sudden wave of need leaves her trembling...");
        sendHaptic("ambient", 12);
        moan(2);
    }
    urgeCooldownUntil = now + URGE_GAP + (integer)llFrand(800.0);   // ~30-40 min until the next urge
}

string chooseGropePart()
{
    float a = arousalFrac;

    // low arousal = mostly chest
    if (a < 0.60)
    {
        if (llFrand(100.0) < 80.0)
        {
            if (llFrand(2.0) < 1.0) return "leftboob";
            return "rightboob";
        }

        return "vagina";
    }

    // medium arousal
    if (a < 0.85)
    {
        float r = llFrand(100.0);

        if (r < 20.0)
        {
            if (llFrand(2.0) < 1.0) return "leftboob";
            return "rightboob";
        }

        if (r < 80.0) return "vagina";

        if (llFrand(2.0) < 1.0) return "leftbutt";
        return "rightbutt";
    }

    return "vagina";
}

integer gropeIntensity() {
    if (arousalFrac >= FRENZY_AT) return 4;
    if (arousalFrac >= CLOSE_AT)  return 3;
    return 2;
}

startGrope(integer inten)
{
    if (!immersionOn) return;                             // grope is an immersion (avatar) output
    if (llGetAgentInfo(wearer) & AGENT_SITTING) return;   // don't grope while seated

    strippedCurrentGrope = FALSE;
    curGropePart = chooseGropePart();

    emitPA("arousalGropeSelf|" + wearer + "|" + curGropePart + "|" + (string)gropeIntensity());
    emitPA("freezeArousal|" + wearer);   // hold arousal so the grope can't spike her to orgasm
    curGrope = inten;
}

stopGrope()
{
    if (curGropePart != "")
    {
        emitPA("arousalGropeSelf|" + wearer + "|" + curGropePart + "|0");
        emitPA("unfreezeArousal|" + wearer);   // release the freeze paired with startGrope
    }
    curGropePart = "";
    curGrope = 0;
    orgasmMode = FALSE;   // stopping the grope ends any orgasm build-up tied to it
}

// End an orgasm build-up. forced=FALSE → PA already came naturally (just clean up + mess);
// forced=TRUE → safety timeout, push it over with arousalForceOrgasm.
finishOrgasm(integer forced)
{
    orgasmMode = FALSE;
    stopGrope();
    // SAFETY: never produce climax content outside an Adult region (fresh check —
    // this can be called async from the PA orgasm link message between timer ticks).
    if (!adultBypass && llToUpper(llGetEnv("region_rating")) != "ADULT") return;
    if (forced) emitPA("arousalForceOrgasm|" + wearer + "|1|super");
    // Real Spunked mess in the groin → Core cum event → lastCumTime resets → the whole
    // neediness/urge timer restarts (can't re-orgasm until she's been left needy again).
    llSay(SPUNKED_CMD, "Request*CumGroin*" + wearer + "*" + (string)ORGASM_CUM);
    moan(3);
    sendHaptic("orgasm", 20);
    integer now = llGetUnixTime();
    gropeDelay = now + 5 + (integer)llFrand(10.0);
    urgeCooldownUntil = now + ORGASM_GAP + (integer)llFrand((float)ORGASM_GAP);
}

strip(integer toBottom)
{
    if (!STRIP_ENABLED || !immersionOn) return;

    if (toBottom)
    {
        llOwnerSay("@detachall:Corruption/Lower=force");
    }
    else
    {
        llOwnerSay("@detachall:Corruption/Upper=force");
    }
}

onRelief()
{
    frenzy = FALSE;
    wasNeglected = FALSE;

    stopGrope();
    gropeCounter = 0;   // an act satisfies her → refresh the 3-grope budget for next time

    stripLevel = 0;
}

integer gropeIsBottom()
{
    return (
        curGropePart == "vagina" ||
        curGropePart == "rightbutt" ||
        curGropePart == "leftbutt"
    );
}

effects(integer now) {
    if (!ENABLED) { stopGrope(); return; }

    integer rose = (arousalFrac > prevFrac + 0.04);
    if (arousalFrac >= MOAN_AT && (rose || now >= moanCD)) {
        integer tier = 1;
        if (arousalFrac >= CLOSE_AT)  tier = 2;
        if (arousalFrac >= FRENZY_AT) tier = 3;
        moan(tier);
        moanCD = now + 5 + (integer)llFrand(5.0);
    }

    if (neglected && !wasNeglected) moan(2);
    wasNeglected = neglected;

    if (!frenzy && arousalFrac >= FRENZY_AT) { frenzy = TRUE; moan(3); }

    // Grope BUDGET: she self-gropes at most 3 times per high-arousal episode, then
    // stops even if she stays maxed. The budget only refreshes once she calms back
    // below GROPE_AT (a new episode) or an act resets it (onRelief) — so a high arousal
    // level on its own can never loop the groping.
    if (arousalFrac < GROPE_AT) gropeCounter = 0;

    // Self-grope chance rises with how aroused she is.
    float gchance = 10.0;
    if (arousalFrac >= CLOSE_AT)  gchance = 20.0;
    if (arousalFrac >= FRENZY_AT) gchance = 40.0;

    if (arousalFrac >= GROPE_AT && closeness <= 0.0 && curGrope == 0
        && gropeCounter < 3 && now >= gropeDelay)
    {
        if (llFrand(100.0) < gchance)
        {
            gropeUntil = now + 10 + (integer)llFrand(10.0);
            gropeCounter++;                 // counts toward the 3-per-episode cap
            startGrope(gropeIntensity());   // freezes arousal itself
        }
    }

    if (curGrope > 0 && now >= gropeUntil)
    {
        if (orgasmMode)
        {
            finishOrgasm(TRUE);             // safety deadline hit with no natural orgasm → force it
        }
        else
        {
            stopGrope();                    // a tease grope ends; gropeCounter stays (caps at 3)
            gropeDelay = now + 15 + (integer)llFrand(10.0);
        }
    }

    // Strip the region she's groping (top vs bottom) once per grope, only while active.
    if (curGrope > 0 && !strippedCurrentGrope)
    {
        strip(gropeIsBottom());
        strippedCurrentGrope = TRUE;
    }

    prevFrac = arousalFrac;
}

default {
    state_entry() {
        wearer = (string)llGetOwner();
        updateRating();
        llListen(HUD_CHAN, "", NULL_KEY, "");
        llSetTimerEvent(TICK);
    }

    attach(key id) { if (id != NULL_KEY) wearer = (string)llGetOwner(); }

    link_message(integer s, integer num, string str, key id) {
        list    args         = llParseString2List(str, ["|"], [""]);
        string  preParseTask = llList2String(args, 0);
        integer taskIndex    = llSubStringIndex(preParseTask, (string)wearer);
        string  task         = llDeleteSubString(str, taskIndex, -1);

        if (task == "arousalOrgasm") {
            finishOrgasm(FALSE);
            return;
        }

        if (num != HUD_CHAN) return;
        if (llSubStringIndex(str, "hud|") != 0) return;
        list p = llParseStringKeepNulls(str, ["|"], []);
        level      = (integer)llList2String(p, 2);
        lastCum    = (integer)llList2String(p, 10);
        creampieCnt= (integer)llList2String(p, 17);
        mess    = (integer)llList2String(p, 32) + (integer)llList2String(p, 33)
                + (integer)llList2String(p, 34) + (integer)llList2String(p, 35)
                + (integer)llList2String(p, 36);
        ambGapMin   = (integer)llList2String(p, 39);
        ambGapMax   = (integer)llList2String(p, 40);
        hapticsOn   = (integer)llList2String(p, 41);
        nearbyCount = (integer)llList2String(p, 42);
        arousal     = (float)((integer)llList2String(p, 47));        // 0-400 actual arousal
        closeness   = (float)((integer)llList2String(p, 48)) / 100.0; // 0-1 closeness
        immersionOn = (integer)llList2String(p, 49);
        adultBypass = (integer)llList2String(p, 57);   // owner override for non-Adult regions
        integer inmFlags = (integer)llList2String(p, 64);   // INM: 2 dripping, 8 rlv
        p = [];
        // INM extras: dripping ramps the ambient tease (more mess); RLV auto-enables the
        // RLV strip feature only when INM confirms RLV is actually active (0 on Spunked).
        if (inmFlags & 2) mess += 6;
        // STRIP_ENABLED = ((inmFlags & 8) != 0);
        arousalFrac = arousal / 400.0;   // pure arousal 0-1 (closeness tracked separately)
        if (ambGapMax < ambGapMin) ambGapMax = ambGapMin;
        if (prevLastCum == -1) { prevLastCum = lastCum; prevFrac = arousalFrac; }

        // ── active haptics + level-up reactions (moved from Core) ──
        // Driven straight off the broadcast so a load/level-up buzzes immediately (Core
        // sends this broadcast at the tail of the same cum event). sendHaptic() gates on
        // hapticsOn; the corruption multiplier is ungated (matches old Core behaviour).
        if (prevLevel == -1) {                 // first broadcast → prime, don't fire
            prevLevel = level; prevActCum = lastCum; prevCreampie = creampieCnt;
        } else {
            integer nowT = llGetUnixTime();
            if (level > prevLevel) {           // leveled up
                prevLevel = level;
                sendHaptic("levelup", 20);
                sendCorruptionMult();
            }
            if (lastCum > prevActCum) {        // a new cum event landed
                if (creampieCnt > prevCreampie) {           // creampie → forced strong buzz
                    sendHaptic("creampie", 20);
                    actBuzzCD = nowT + 25;
                } else if (nowT >= actBuzzCD) {             // plain load → throttled buzz
                    integer li = vibeLevelAct();
                    if (li < 12) li = 12;                   // active loads hit harder than tease
                    sendHaptic("load", li);
                    actBuzzCD = nowT + 20;
                }
                prevActCum   = lastCum;
                prevCreampie = creampieCnt;
            }
        }
    }

    timer() {
        integer now = llGetUnixTime();

        // SAFETY: outside an Adult region the whole immersion system is suppressed.
        if (!regionAdult) { if (curGrope > 0) stopGrope(); return; }

        // Both features off → fully idle (release any grope once, then nothing).
        if (!immersionOn && !hapticsOn) { if (curGrope > 0) stopGrope(); return; }

        // Immersion off (but Lovense on) → no avatar effects; release any active grope.
        if (!immersionOn && curGrope > 0) stopGrope();

        if (lastCum > prevLastCum) { prevLastCum = lastCum; onRelief(); }
        neglected = (now - lastCum >= NEGLECT_IDLE);

        vibeEngine(now);                 // Lovense ambient buzz (sendHaptic gates on hapticsOn)
        if (immersionOn) effects(now);   // grope / moans / strip — avatar effects only
        suddenUrge(now);                 // PA parts gate on immersionOn; haptic on hapticsOn
    }

    changed(integer c) {
        if (c & (CHANGED_OWNER | CHANGED_INVENTORY)) { stopGrope(); llResetScript(); }

        if (c & CHANGED_REGION)
        {
            updateRating();
        }
    }
}
