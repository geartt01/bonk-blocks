# Publishing Bonk Blocks

About 20 minutes. You need Roblox Studio, this project, and your Roblox account.

## 1. Get the latest version into Studio

1. In VS Code's terminal, in the `BonkBlocks` folder: `rojo serve`
2. In Studio, open your Bonk Blocks place, then go to **Plugins → Rojo → Connect**. It should say *Connected*.
   (No place yet? Run `rojo build -o BonkBlocks.rbxlx`, open that file in Studio, then connect.)
3. **Lighting → Technology = Future** in the Properties panel. Scripts can't set this, so do it by hand.

## 2. Final check in Studio

1. Press **Play**. In Output you should see `[SmokeTest] 12/12 passed` and no red errors.
2. Watch the intro → RELEASE card → a welcome block drops. Break it: coins fly into the counter.
3. **Test → Clients and Servers → 2 Players → Start**: both players see each other, the blimp, the fireworks at round end.
4. Stop the test. Debug tools (F8 panel, smoke test, starting coins) only run in Studio, so they won't be live.

## 3. Publish

1. **File → Publish to Roblox** (Alt+P) → **Create new experience**.
   - Name: `Bonk Blocks`
   - Description: paste the DESCRIPTION part of `marketing/description.txt`
   - Creator: you (or your group, if you'll run the game from a group)
   - Genre: Party & Casual
   - Devices: **Computer, Phone, Tablet** (the UI is built mobile-first)
2. Click **Create**. The experience exists now, but it's **private**.

## 4. Game Settings (Home → Game Settings in Studio)

| Tab | Setting | Value | Why |
|---|---|---|---|
| Security | Enable Studio Access to API Services | **On** | Coins, Blocklings and rebirths save (ProfileStore / DataStores) |
| Avatar | Avatar type | **R15** | Emotes and the victory dance need R15 |
| Places | Max players | **12** | The stadium and block caps are tuned for 12 |
| Monetization | everything | off | No monetization yet |

Click **Save**, then **File → Publish to Roblox** again so the place has the settings.

## 5. Creator Dashboard (create.roblox.com → Creations → Bonk Blocks)

1. **Configure → Basic Settings**
   - Icon: `marketing/icon.png`
   - Thumbnails: `marketing/thumbnail.png` (add more later to A/B test them)
   - Description and genre if they're not set yet
2. **Maturity & Compliance questionnaire**: answer honestly. Cartoon bonks with no blood or damage should come out as **Minimal or Mild**. Public experiences need this done.
3. **Audience / Access**: All ages. Leave private servers off for now.
4. Optional:
   - **Badges** (Associated Items → Badges; a few are free each day). Paste their ids into `Config.Badges`.
   - **Events** (Engagement → Events): schedule **BONK PARTY, every Saturday 18:00 UTC** so followers get notified. It's already built into the game.

## 6. Go public

1. Test the live version first: on roblox.com open your experience and click **Play**. Play a round, leave, rejoin, and check that your coins saved. In-game, **F9** opens the Developer Console: the *Server* tab should show no red errors.
2. Creator Dashboard → your experience → **Make Public** (or Configure → Basic Settings → Public).
   If the button is greyed out, Roblox tells you what's missing. Usually it's the questionnaire or account verification.

## 7. Updating later

1. Make changes, sync with Rojo, test in Studio.
2. Bump `Config.Release.Version` and edit `Config.Release.Items`, so returning players see the RELEASE card with what's new.
3. **File → Publish to Roblox**.
4. Creator Dashboard → experience → **⋯ → Migrate to Latest Update** (moves players to new servers without kicking them).

## 8. Getting players

See **LAUNCH.md**: icon/thumbnail A/B tests, a small Sponsored Ads test, short daily clips (Mega Block fights, Rainbow pulls), and pushing the Saturday BONK PARTY in your group.
