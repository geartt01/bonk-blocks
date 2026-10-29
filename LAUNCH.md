# Bonk Blocks: launch plan for 100+ CCU

CCU on Roblox ≈ **how many people the algorithm shows you to** × **how many click** × **how long they stay
and come back**. Recommendations are driven by engagement (session length, D1/D7 retention, play with
friends). So the game has to (1) convert a click into a hooked player in 30 seconds, (2) give reasons to
stay 15+ minutes, and (3) give reasons to come back and bring friends. The code now covers all three.
The rest of this plan is the part code can't do.

## What's in the game for each lever

| Lever | Feature | Where |
|---|---|---|
| 30-second hook | Spawn into a live arena, welcome block, first crack ≤15s, "TAP TO BONK!", first upgrade ≤30s, impact frames | RoundService, BlockService, HammerController, ShopController |
| Session length | 3-min rounds, events every 10 min, Mega Block boss, quests, combo + frenzy, collection | EventService, QuestService |
| Come back tomorrow | 7-day streak (day 7 = Rare+ pet), daily quests, rebirth multipliers, mutations to chase | DailyService, RebirthService, BlocklingService |
| Appointments | **Events on the real clock**: the same event on every server at :00, :10, :20... | `Config.Events` |
| Bring friends | +10% coins per friend in the server (max +30%), INVITE button | SocialService, SocialController |
| Clip-worthy moments | Rainbow Blockling server-wide shout, Mega Block destroyed, team victory dance, Moon Gravity launches | — |
| Profile visibility | Badges: first crack, first pet, Mega Block, first win, rebirth, Rainbow, full collection | AchievementService, `Config.Badges` |
| Measure it | Onboarding funnel + `SecondsToFirstCrack` / `SecondsToFirstUpgrade` | FunnelService |

## Before launch (one weekend)

1. **Assets that change click-through rate** (the #1 discovery factor):
   - **Icon**: one giant cartoon hammer mid-bonk on a glowing mystery block, coins exploding, a Rainbow Blockling peeking out. Bright saturated colors, no text, readable at 50×50 px. Make 3 variants.
   - **Thumbnails** (16:9, 3–5): (a) 8 players swarming the Mega Block, (b) a Rainbow Blockling reveal, (c) a team victory dance, (d) a hammer frenzy with speed lines. Large expressive characters, one focal point each.
   - Use the Creator Dashboard **thumbnail/icon A/B test** (Experience → Associated Items → Icon/Thumbnails → "Test"). Keep the winner after ~1,000 impressions each.
2. **Title**: `Bonk Blocks` plus at most one emoji-free tag in brackets for updates, e.g. `Bonk Blocks [MEGA BLOCK]`. Change the tag with each update. Don't keyword-stuff.
3. **Description** (first 2 lines show in search):
   > Bonk giant mystery blocks with a huge hammer! Crack them for coins, crush them for points, and collect 12 Blocklings, with Shiny and Rainbow ones too.
   > MEGA BLOCK every 10 minutes on every server. Play with friends for +30% coins!
4. **Sound**: fill `Config.Sounds` with Creator Store audio (bonk, crack, coin, crush, event horn). Sound is half of the "juice".
5. **Badges**: create the 7 badges (Creator Dashboard → Badges, a few free per day) and paste the ids into `Config.Badges`.
6. **Settings**: Max players **12** (more players per server = livelier servers and higher CCU per server). Lighting Technology **Future**. Genres: Party & Casual / Fighting. Devices: Phone, Tablet, Computer, Console. Turn on **Private servers** (free, helps friend groups).
7. **Maturity questionnaire**: answer honestly. Cartoon bonking with no blood should rate **Minimal**.

## Launch week

- **Day 0**: publish, then playtest with 8 real people (friends, a Discord) in one server. Watch Output for errors, and fix them before any marketing.
- **Day 1–3: Sponsored Ads** (Ads Manager → Sponsored Experiences). Start small (≈ 1,000–3,000 Robux/day) for 3 days to seed retention data. Watch **D1 retention ≥ 20%** and **average session ≥ 12 min**. If they're lower, fix the game first, not the ads.
- **Day 1–7: short-form video**, 1–2 per day (YouTube Shorts / TikTok / Reels). The hooks write themselves:
  - "We found a RAINBOW Blockling" (reveal + server shout)
  - "8 players vs the MEGA BLOCK" (boss HP bar draining, impact frame at the end)
  - "Moon Gravity sent this block to space"
  - Screen-record on a phone at 60 FPS with the HUD on.
- **Community**: a Roblox **group** (members get a shout-out), and a Discord with an #event-times channel. The global clock means you can say "Mega Block at :00".

## Keep it climbing: update rhythm

Roblox rewards active games. Ship something **every week**, small is fine, and change the title tag.

| Week | Update | Uses |
|---|---|---|
| 1 | Launch | — |
| 2 | 2 new Blocklings + a new event (e.g. "Bouncy Hour": every block is Bouncy) | `Config.Blocklings.Species`, `Config.Events` |
| 3 | Limited-time Blockling (only drops during one weekend's Bonanza) | `BlocklingService.Roll` filter |
| 4 | New arena theme (snow/lava) rotating per round | DevArena → your arena tags |
| 5 | Weekly leaderboard reset + top-3 badge | LeaderboardService |
| 6 | Hammer skins (cosmetic, earnable) → then a monetization pass | HammerService template |

## Metrics to watch (Creator Dashboard → Analytics)

- **Funnel** (Funnels tab): Joined → FirstSwing should be ≥ 90%, FirstCrack ≥ 80%, FirstUpgrade ≥ 50%. A big drop means that step is confusing; fix it first.
- **Custom events**: `SecondsToFirstCrack` median ≤ 15, `SecondsToFirstUpgrade` median ≤ 40.
- **Retention**: D1 ≥ 20% (good ≥ 30%), D7 ≥ 7%.
- **Session length**: ≥ 12 min. If it's low, events are too far apart: try `IntervalMinutes = 7`.
- **Friends**: the share of sessions with a friend in the server should rise after you push the INVITE button in videos.

## Monetization later (when you're ready; nothing is built)

The hooks exist: `CoinService.RegisterMultiplier("Gamepass2x", …)`, an extra pet slot via `Progression.BlocklingSlots`,
dev products through `MarketplaceService.ProcessReceipt` → `CoinService.Add(player, n, "DevProduct:<id>")` with
receipt ids stored in the profile. Add it **after** retention is healthy, because monetizing a leaky game just makes it leak faster.
