# Game direction

Civilization Legacy is a working title. The design below describes planned gameplay;
the implemented prototype is currently the terrain, climate and biome map editor.

## Core game design

Progress has three sources:

1. **Player knowledge:** better plans, resource allocation, expansion and timing.
2. **Prestige:** modest inherited advantages and new strategic possibilities.
3. **World history:** roads, ruins, infrastructure and other consequences that
   survive the end of a civilization.

The civilization skill tree resets between runs so players can try different
builds. The exact respec rules, prestige rewards and progression balance remain
open design decisions. Major upgrades should change capabilities or decisions.

Prototype examples, not finalized features:

- Irrigation creates a surplus that supports another settlement or an army.
- Governors automate stable provinces through growth, commerce or frontier policy.
- An era can end voluntarily after a milestone; the player chooses a legacy.
- Infrastructure, knowledge and institutions offer different successor advantages.
- A successor can restore a former capital or reuse an inherited road network.

Initial audience hypothesis: active strategy sessions with automated development
between decisions, a pause/save-anywhere model, and a finishable campaign over
several evenings. Suggested first-run length is 15–25 minutes and later runs
30–45 minutes. These are targets to test, not content or playtime promises.

## Map and civilization layers

The intended 3D grand strategy presentation combines readable terrain with future
political overlays, settlements, roads and ruins. Heightfield geometry, geographic
cells, province membership, ownership and civilization history have separate owners.
Changing a province's owner should not rebuild the landscape or erase its history.

Future painting tools will edit a shared province-ID layer and authored terrain
data. Borders and adjacency should derive from that layer. Geographic travel costs
may eventually help seed provinces, but Voronoi cells are not provinces today.

## First gameplay milestone: two civilizations, one map

- Create and inspect a small set of provinces with terrain-following borders.
- Place a settlement and connect locations with a road.
- Offer two useful civilization skill-tree branches and automate one routine task.
- End an era, choose a legacy, and start a successor civilization.
- Retain a recognizable road or ruin and let the successor reuse it.
- Save province identity, civilization state and inherited world history.

These systems are planned. Current terrain documents preserve the landscape and
its climate, not a playable civilization campaign.

## Questions to validate

1. **Hook:** Can someone recognize civilization building and inherited
   consequences after ten seconds of play footage?
2. **First upgrade:** Can the player explain the new capability it enables?
3. **Automation:** Does it retire maintenance and introduce a useful decision?
4. **Prestige:** Can the player describe a different plan for the next civilization?
5. **Return:** Do players return for a plan, discovery or attachment to a place?
6. **Audience:** Does the experience fit active, interruptible strategy sessions?

Visually inspect the map at normal play distance and the closest supported zoom.
Check border clarity, province picking, terrain transitions, text readability and
the visibility of inherited structures. Headless checks cannot establish these.

