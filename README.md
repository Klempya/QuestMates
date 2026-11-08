# QuestMates

A World of Warcraft addon for **WoW Forever** that helps you quest **together**:
it lists your quests, and when you pick one it finds nearby players who have
the same quest — either peers running QuestMates (they answer automatically),
or simply anyone standing around you (one click invites them). A radar shows
who is near you, and a minimap button opens/closes the window.

## Install

1. Download the repo (green **Code** button → **Download ZIP**) and extract it.
2. Copy the `QuestMates/` folder into `<WoW>\Interface\Addons\`.
3. In game: `/console reloadui`.

## Using it

- Type **`/qg`** (or click the **compass icon on the minimap**) to open the window.
- **Click a quest** in the list to select it, then click **Find mates**
  (« Chercher des partenaires » on a French client) to announce it: players in
  your zone who run QuestMates and have the same quest answer automatically and
  appear in the **Responders** panel (« Réponses ») — click **Invite** (« Inviter »)
  next to a name to invite them.
- **Invite nearby** (« Inviter les proches ») invites the players physically
  around you, even if they don't have the addon (max 5 per click, a few seconds
  apart).
- The **radar** window shows nearby players as green dots (within ~45 yd).
- Bottom checkboxes: auto-announce when changing zone · auto-accept invites from
  responders · auto-invite nearby players after each announcement · show the
  invite counter · show the radar.
- Useful commands: `/qg lfm` (announce), `/qg nearby on|off`,
  `/qg invitehow auto|api|chat` (invite method; `chat` = prefilled `/invite`,
  just press Enter), `/qg delay <s>`, `/qg expire <s>`.
- Troubleshooting: `/qg probe` and `/qg selftest` print diagnostics in chat if
  something doesn't work; `/qg debug` shows the traffic.

## Notes

- The nearby-invite button and the radar rely on **friendly nameplates**: enable
  them with their keybind (Ctrl+V / Ctrl+Shift+V) if players don't show up.
- Opposite-faction players are skipped (the server rejects those invites).
- The addon syncs over a hidden chat channel (`QuestGroupSync`); all of its
  traffic is invisible in your chat windows.
- Everything is saved per character (window position, options).

## Development

Headless test suite: `sh tests/run.sh` (needs lua5.1/luajit). Implementation
notes and client-specific quirks: `CONTEXT.md`.

## License

MIT — see `LICENSE`.
