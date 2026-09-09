class_name Config
## Every tunable number and every content definition lives here. One file to
## balance. Numbers are the prototype's current values (see
## tasks/port-inventory.md); a number that moves should move for a reason.

const TILE := 32
const WORLD_TILES := 320
const WORLD_SIZE := TILE * WORLD_TILES   # 10240px square

# ------------------------------------------------------------------ terrain --

enum T {
	GRASS, ROAD, SIDEWALK, DIRT, FLOOR_WOOD,
	WALL, WATER, RUBBLE, LOT, FLOOR_TILE, GRAVEL,
	FIELD, SAND, FENCE,
}

## Base colour `a` and a translucent detail colour `b`, per terrain.
const TERRAIN := {
	T.GRASS:      {"a": Color("#38472a"), "b": Color("#31402552")},
	T.ROAD:       {"a": Color("#2b2c2e"), "b": Color("#33343664")},
	T.SIDEWALK:   {"a": Color("#474742"), "b": Color("#50504b64")},
	T.DIRT:       {"a": Color("#463c2d"), "b": Color("#4f442f64")},
	T.FLOOR_WOOD: {"a": Color("#463726"), "b": Color("#50402c64")},
	T.WALL:       {"a": Color("#6a6055"), "b": Color("#75695c64")},
	T.WATER:      {"a": Color("#22384a"), "b": Color("#2b445864")},
	T.RUBBLE:     {"a": Color("#3a3730"), "b": Color("#45413864")},
	T.LOT:        {"a": Color("#313236"), "b": Color("#3a3b4064")},
	T.FLOOR_TILE: {"a": Color("#54544f"), "b": Color("#5d5d5764")},
	T.GRAVEL:     {"a": Color("#3e3d38"), "b": Color("#4a4941aa")},
	T.FIELD:      {"a": Color("#4b3a26"), "b": Color("#5a4630aa")},
	T.SAND:       {"a": Color("#6e6449"), "b": Color("#7c7255aa")},
	T.FENCE:      {"a": Color("#38472a"), "b": Color("#31402552")},
}

## Indexed by T. Solid to feet: wall, water, fence.
const SOLID_BY_TILE := [0, 0, 0, 0, 0, 1, 1, 0, 0, 0, 0, 0, 0, 1]
## Solid to feet but not to bullets: you shoot across a river or over a fence.
const SHOOT_OVER_BY_TILE := [0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 1]

# ------------------------------------------------------------------- player --

const PLAYER := {
	"max_hp": 100.0,
	"r": 13.0,
	"speed": 176.0,
	"sprint_mul": 1.62,
	"max_stam": 100.0,
	"stam_drain": 26.0,
	"stam_regen": 20.0,
	"stam_regen_delay": 0.65,
	# Work costs stamina; fighting barely does. A harvest swing is the
	# expensive one and also stops recovery for stam_chop_delay afterwards.
	# A combat swing costs stam_swing and is never refused.
	"stam_chop": 6.0,
	"stam_swing": 2.0,
	"stam_chop_delay": 1.1,
	# Exhaustion has hysteresis: once the bar bottoms out you are winded, and
	# you have to get back to half before you can work again.
	"stam_winded_recovery": 0.5,
	"carry_cap": 200.0,
	"inv_slots": 30,
	"hotbar_slots": 6,
	"pickup_range": 46.0,
	"interact_range": 76.0,
	"search_time": 1.05,
	# How long E must stay down beside a car before it opens the boot instead
	# of driving. Long enough that an ordinary tap is never read as a hold.
	"boot_hold": 0.35,
	"invuln_after_hit": 0.32,
	"respawn_time": 3.0,
	"downed_time": 30.0,
	"revive_time": 2.5,
	"revive_hp_frac": 0.4,
	# Ground-ring tints, one per seat.
	"colors": ["#dff0ff", "#ffd27a", "#9fe8a0", "#f0a0e8"],
	"names": ["Survivor", "Ash", "Bex", "Cole", "Dee"],
}

# --------------------------------------------------------------- co-op --

## Phase 5. The host runs the simulation exactly as solo does; guests send
## intent up and get snapshots down. Every number the wire depends on is
## here, so the tests and the game agree about what "late" means.
const NET := {
	"max_players": 4,
	## The UDP port a host listens on and a guest dials. ENet, built into the
	## engine: no plugin, no broker. Works across a LAN, a VPN or a forwarded
	## port; see PROJECT.md §6 for what internet play without any of those
	## would take.
	"port": 27333,
	"snap_every": 3,            # simulation steps between snapshots: 20Hz at 60
	"interest_radius": 1600.0,  # px around a guest that a snapshot describes
	"sync_interval": 0.5,       # seconds between inventory / store / world diffs
	"intent_timeout": 0.4,      # a silent guest is holding nothing after this
	"snap_over": 48.0,          # a predicted position this far off snaps to the host's
	"lerp_rate": 6.0,           # ... and closer than that leans toward it at this rate
	"ease_rate": 14.0,          # everyone and everything else eases at this rate
	"hello_timeout": 15.0,      # seconds a guest waits for the host to answer
	## UPnP: the host asks its router to open the port. Off, and friends on
	## the internet need a forwarded port or a VPN.
	"upnp": true,
	"upnp_timeout_ms": 2000,    # how long to wait for a router to answer discovery
	"upnp_lease_s": 0,          # 0 is "until removed"; some routers refuse a lease
	## Room codes over WebRTC (`WebRtcHub`): built, tested, and OFF until this
	## names a broker — `server/signal.js` on a public host, e.g.
	## "wss://deadline-signal.fly.dev". Also needs the native extension in
	## `addons/webrtc/` (`tools/fetch-webrtc`). With both, START HOSTING opens
	## a room beside the UDP port and JOIN accepts a six-letter code.
	"broker": "",
	## ICE servers. WebRTC dials all of them; `NetDoor` asks the `stun:` ones
	## what this machine's public address is when UPnP will not say, so the
	## HOST page has a line to copy even with the port forwarded by hand.
	"stun": ["stun:stun.l.google.com:19302"],
	"stun_timeout_ms": 1500,     # how long to wait for a STUN server to answer
	"rtc_timeout": 25.0,        # seconds a WebRTC dial may take: broker, offer, ICE
	"guest_view_radius": 880.0, # what the spawner assumes a guest can see
}

## view_height is world pixels of height on screen at zoom 1; the camera
## zooms so that the viewport shows about that much world vertically.
const CAMERA := {"follow": 7.5, "view_height": 580.0, "min_zoom": 0.9, "max_zoom": 2.6, "lead": 0.22, "lead_max": 170.0}

# -------------------------------------------------------------- progression --

## XP to reach the next level. The first few come quickly and then it bites;
## the exponent is what stops levelling going close to linear and never
## slowing down.
static func xp_for_level(level: int) -> int:
	return floori(55.0 + 45.0 * pow(float(level - 1), 2.35))


## Skill points granted for reaching a level. Every fifth level pays double.
static func points_for_level(level: int) -> int:
	return 2 if level % 5 == 0 else 1


const ATTR_MIN := 1
const ATTR_MAX := 10
## Everyone starts at rank 2, and rank 1 is the baseline the tables are
## written against — so a new survivor already carries one rank of each.
const ATTR_START := 2

const ATTR_IDS := ["str", "per", "con", "cha", "int", "lck"]

const ATTRS := {
	"str": {"id": "str", "name": "Strength", "abbr": "STR", "color": "#d9765a",
		"blurb": "Swing harder, carry more.",
		"per_rank": "+9% melee · +25 carry · +6% chop"},
	"per": {"id": "per", "name": "Perception", "abbr": "PER", "color": "#6fb0c4",
		"blurb": "Steadier aim, sharper eyes, faster hands.",
		"per_rank": "-4% spread · -5% search time"},
	"con": {"id": "con", "name": "Constitution", "abbr": "CON", "color": "#7ec46a",
		"blurb": "More to lose before you lose it.",
		"per_rank": "+12 health · +10 stamina · +1.2 stam/s"},
	"cha": {"id": "cha", "name": "Charisma", "abbr": "CHA", "color": "#c48fd0",
		"blurb": "People will follow you, and fight for you.",
		"per_rank": "+1 slot per 2 ranks · +6% ally damage"},
	"int": {"id": "int", "name": "Intelligence", "abbr": "INT", "color": "#d0c46a",
		"blurb": "Learn faster, build cheaper, wire better.",
		"per_rank": "+7% XP · -3% build cost · +5% turret"},
	"lck": {"id": "lck", "name": "Luck", "abbr": "LCK", "color": "#d0a05a",
		"blurb": "The world is kinder than it should be.",
		"per_rank": "+2% crit · +5% rare loot"},
}

## Twenty-seven perks. `req` is the rank needed in the parent attribute, so
## investing in an attribute is what opens its tree; `max` is how many times
## the perk can be taken.
##
## The table is data only. What each one *does* is the match in
## `Perks._apply_perk`, which runs during the recompute and never on
## purchase — a test asserts every id here has a branch there.
##
## `needs` names a system that has not been built yet. Such a perk stays
## visible so the tree matches the spec and can be planned around, but it
## cannot be bought: a point spent on nothing is worse than a row that says
## why it is waiting. The field comes off as each system lands.
const PERKS := [
	# ------------------------------------------------------------ strength --
	{"id": "packMule", "attr": "str", "req": 2, "max": 3, "name": "Pack Mule",
		"desc": "+70 carry capacity per rank."},
	{"id": "heavyHitter", "attr": "str", "req": 3, "max": 3, "name": "Heavy Hitter",
		"desc": "+25% melee damage per rank."},
	{"id": "demolisher", "attr": "str", "req": 5, "max": 2, "name": "Demolisher",
		"desc": "Fell trees and salvage twice as fast per rank."},
	{"id": "adrenaline", "attr": "str", "req": 7, "max": 1, "name": "Adrenaline",
		"desc": "Below a third health: +45% melee damage and +15% speed."},

	# ---------------------------------------------------------- perception --
	{"id": "scrounger", "attr": "per", "req": 2, "max": 3, "name": "Scrounger",
		"desc": "+35% resources from containers per rank."},
	{"id": "quickHands", "attr": "per", "req": 3, "max": 2, "name": "Quick Hands",
		"desc": "-30% search time and +18 pickup range per rank."},
	{"id": "eagleEye", "attr": "per", "req": 4, "max": 3, "name": "Eagle Eye",
		"desc": "-22% weapon spread and +12% bullet range per rank."},
	{"id": "sixthSense", "attr": "per", "req": 6, "max": 1, "name": "Sixth Sense",
		"desc": "Enemies show on the minimap much further out, even unaware ones."},

	# --------------------------------------------------------- constitution --
	{"id": "thickSkin", "attr": "con", "req": 2, "max": 4, "name": "Thick Skin",
		"desc": "+30 max health per rank."},
	{"id": "marathon", "attr": "con", "req": 3, "max": 3, "name": "Marathon",
		"desc": "+45 stamina and faster recovery per rank."},
	{"id": "woodcraft", "attr": "con", "req": 4, "max": 2, "name": "Woodcraft",
		"desc": "Harvest swings cost 35% less stamina per rank."},
	{"id": "ironStomach", "attr": "con", "req": 4, "max": 2, "name": "Iron Stomach",
		"desc": "Medical supplies heal +60% and are used 30% faster per rank."},
	{"id": "secondWind", "attr": "con", "req": 6, "max": 1, "name": "Second Wind",
		"desc": "Once every two minutes, a killing blow leaves you on 1 health instead."},

	# ------------------------------------------------------------- charisma --
	{"id": "recruiter", "attr": "cha", "req": 2, "max": 3, "name": "Recruiter",
		"desc": "+1 survivor slot per rank."},
	{"id": "inspiring", "attr": "cha", "req": 3, "max": 2, "name": "Inspiring Presence",
		"desc": "Survivors gain +30% damage and +25% health per rank."},
	{"id": "quartermaster", "attr": "cha", "req": 4, "max": 2, "name": "Quartermaster",
		"desc": "Survivors eat 40% fewer Rations per rank."},
	{"id": "leader", "attr": "cha", "req": 6, "max": 1, "name": "Natural Leader",
		"desc": "Survivors earn experience 60% faster and rally after a raid."},

	# --------------------------------------------------------- intelligence --
	{"id": "fastLearner", "attr": "int", "req": 2, "max": 3, "name": "Fast Learner",
		"desc": "+22% experience from everything per rank."},
	{"id": "engineer", "attr": "int", "req": 3, "max": 3, "name": "Engineer",
		"desc": "-22% structure cost per rank."},
	{"id": "fortifier", "attr": "int", "req": 4, "max": 3, "name": "Fortifier",
		"desc": "+45% structure health per rank."},
	{"id": "gunsmith", "attr": "int", "req": 4, "max": 2, "name": "Gunsmith",
		"desc": "Crafted ammo yields +60% per rank."},
	{"id": "fireControl", "attr": "int", "req": 5, "max": 2, "name": "Fire Control",
		"desc": "+35% turret damage per rank, and half that in reach."},
	{"id": "hotwire", "attr": "int", "req": 5, "max": 2, "name": "Hotwire",
		"desc": "Start any locked car without a key. Rank 2 does it twice as fast."},

	# ------------------------------------------------------------------ luck --
	{"id": "scavengersLuck", "attr": "lck", "req": 2, "max": 3, "name": "Scavenger's Luck",
		"desc": "+30% chance of the rare entry in any loot roll, per rank."},
	{"id": "luckyStrike", "attr": "lck", "req": 3, "max": 3, "name": "Lucky Strike",
		"desc": "+7% critical hit chance per rank."},
	{"id": "ammoCache", "attr": "lck", "req": 4, "max": 2, "name": "Ammo Cache",
		"desc": "20% chance per rank that a shot costs no ammunition."},
	{"id": "lowProfile", "attr": "lck", "req": 5, "max": 2, "name": "Low Profile",
		"desc": "-30% Threat generated and quieter gunfire per rank."},
	{"id": "fortune", "attr": "lck", "req": 7, "max": 1, "name": "Fortune Favours",
		"desc": "A 35% chance that a body or a container pays out twice."},
]

## Every modifier the game reads, at its untouched base value — before any
## attribute, perk or piece of gear. `Perks.recompute_stats` writes this whole
## block onto the player and then layers the three sources over it, so a stat
## can never keep a value from a build that no longer exists.
##
## Keys are PlayerSim property names, applied with `set()`, so a typo here
## would be a silent no-op: `progression_test` asserts every key resolves.
const STAT_BASE := {
	"max_hp": 100.0, "max_stam": 100.0, "stam_regen": 20.0,
	"carry_cap": 200.0, "pickup_range": 46.0,

	"melee_mul": 1.0, "gun_mul": 1.0, "reload_mul": 1.0, "fire_rate_mul": 1.0,
	"spread_mul": 1.0, "range_mul": 1.0, "chop_mul": 1.0, "chop_stam_mul": 1.0,
	"crit_chance": 0.06, "free_shot_chance": 0.0, "speed_mul": 1.0,
	"loot_mul": 1.0, "rare_loot_mul": 1.0, "double_drop_chance": 0.0, "search_mul": 1.0,
	"build_cost_mul": 1.0, "struct_hp_mul": 1.0, "turret_mul": 1.0, "craft_yield_mul": 1.0,
	"heal_mul": 1.0, "heal_speed_mul": 1.0,
	"threat_mul": 1.0, "noise_mul": 1.0, "xp_mul": 1.0, "radar_mul": 1.0,

	# How far a zombie senses you, and how hard a hit rocks you. Both are 1.0
	# for a human and both fall as the change takes hold: the half of Mutation
	# that is a reward.
	"sense_mul": 1.0, "stagger_mul": 1.0,
	# How fast the change takes hold. Nothing lowers it yet; hydration and
	# the deeper chemistry will, and they will do it by writing here.
	"mut_rate_mul": 1.0,

	# Read by Phase 4c. Produced here because a perk that quietly does nothing
	# is worse than a field whose reader has not been written yet.
	"survivor_cap": 0, "survivor_dmg_mul": 1.0, "survivor_hp_mul": 1.0,
	"survivor_xp_mul": 1.0, "upkeep_mul": 1.0,

	"adrenaline": false, "second_wind": false,
	"hotwire": false, "hotwire_speed_mul": 1.0,

	# Summed from worn gear by the recompute and capped. Nothing else may write
	# it: damage.gd reads this rather than inspecting what is worn, so gear,
	# perks and any later source of mitigation all arrive through one number.
	"armor_dr": 0.0,
}

## Adrenaline is active below this fraction of maximum health.
const ADRENALINE_HP_FRAC := 0.34
const ADRENALINE_MELEE := 1.45
const ADRENALINE_SPEED := 1.15
## Second Wind cannot save you again until this many seconds have passed.
const SECOND_WIND_CD := 120.0

# ---------------------------------------------------------------- day/night --

## One full day in seconds. Roughly nine minutes: long enough to plan a run
## around, short enough that night is a thing that happens to you often.
const DAY_LENGTH := 540.0

## A new run starts mid-morning, so the first thing you get is a full working
## day rather than a scramble.
const DAY_START := 0.16

## Fractions of a day. Night is the shortest phase and by far the loudest.
## These name the phase for the HUD and the notices; the *darkness* is the
## curve below, which crosses the boundaries smoothly.
const PHASES := [
	{"id": "dawn",  "name": "DAWN",  "from": 0.00, "to": 0.12},
	{"id": "day",   "name": "DAY",   "from": 0.12, "to": 0.58},
	{"id": "dusk",  "name": "DUSK",  "from": 0.58, "to": 0.72},
	{"id": "night", "name": "NIGHT", "from": 0.72, "to": 1.00},
]

## How dark the world is through the day, sampled as a ramp rather than
## stepped per phase — dusk has to creep in, not snap. `a` is the darkness
## alpha and `c` is what the dark is tinted.
const DARKNESS_KEYS := [
	{"t": 0.00, "a": 0.62, "c": "#101a3a"},
	{"t": 0.10, "a": 0.22, "c": "#2a3358"},
	{"t": 0.16, "a": 0.00, "c": "#0a0c09"},
	{"t": 0.56, "a": 0.00, "c": "#0a0c09"},
	{"t": 0.66, "a": 0.30, "c": "#3a2740"},
	{"t": 0.74, "a": 0.62, "c": "#161436"},
	{"t": 0.82, "a": 0.82, "c": "#070c1c"},
	{"t": 0.96, "a": 0.78, "c": "#080f24"},
	{"t": 1.00, "a": 0.62, "c": "#101a3a"},
]

## Full night for the purpose of the multipliers below. The curve peaks a
## little above this, so `k` is clamped and the small hours are not worse
## than the rest of the night.
const DARKNESS_FULL := 0.8

## What the dark is worth to everything else. `k` is darkness over
## DARKNESS_FULL, clamped to 0..1: more of them out there, noticing you
## sooner, moving a little faster, and Threat climbing at nearly twice the
## rate. Night is the pressure valve of the whole game.
const NIGHT := {
	"density": 0.85,
	"sense": 0.55,
	"speed": 0.10,
	"threat": 0.9,
}

## Above this darkness a light is worth carrying — what the HUD hint and the
## torch prompt read.
const DARK_ENOUGH := 0.35

# ----------------------------------------------------------------- mutation --

## The one meter the player manages, and the theme of the whole game.
##
## You were bitten before the first frame and there is no cure. What there is
## is control: something in a zombie's brain suppresses the change, so the
## supply line that keeps you human runs through the horde. Food and drink are
## buffs and nothing else — there is still no hunger bar (pillar 1), because
## this replaces the chore rather than adding one.
##
## It is deliberately slow. A full cycle left alone is `days_to_full` in-game
## days, so brains are something you stock rather than something you think
## about every five minutes. And it is a two-sided bet: further along you hit
## harder and are noticed less, and you are also worse with a gun, worse to
## look at, and closer to gone.
const MUTATION := {
	"max": 100.0,
	## Nothing to full, untouched, in in-game days. `DAY_LENGTH` is 540s, so
	## 2.5 of them is about twenty-two minutes of play.
	"days_to_full": 2.5,
	## Multiplied into the base rate by the danger tier under your feet: worse
	## ground turns you faster, which is the cost of going somewhere good.
	## Indexed by tier; 0 is the tierless outskirts.
	"tier_mul": [1.0, 1.0, 1.15, 1.35, 1.6],
	## What full darkness is worth on top, scaled by the darkness curve.
	"night_mul": 1.2,
	## A zombie's melee connecting is a *bite* this often. Every hit adding
	## mutation would make this a second health bar; one in seven makes a
	## crowd something you get out of rather than trade with.
	"bite_chance": 0.14,
	"per_bite": 12.0,
	## Any single hit this big — bite or not, a Behemoth's swing or a fall —
	## is the body being overwhelmed.
	"heavy_damage": 25.0,
	"per_heavy": 5.0,
	"per_down": 10.0,
	## Where you wake up after turning. Never zero: letting the bar fill must
	## not become the cheapest way to empty it.
	"after_turn": 55.0,
	## A suppressant may overshoot by this much before a weaker one is
	## preferred, so a Serum is not spent to clear four points.
	"overshoot": 8.0,
	## The Lurch: at the top band, every so often, your legs stop being yours
	## and carry you at the nearest thing. `band` is the index it starts at, so
	## it is FERAL and nothing below. Long enough to be frightening, short
	## enough that it is a moment rather than a punishment — and rare enough
	## that it never becomes the reason you keep the meter down. That reason
	## is supposed to be the gun.
	"lurch": {
		"band": 2, "every_min": 60.0, "every_max": 140.0,
		"dur_min": 1.2, "dur_max": 1.8, "reach": 900.0,
	},
	## The living, and what they make of you. `raid_chance` is the odds, by
	## band, that the raid Threat has just scheduled arrives carrying rifles
	## instead of teeth — word travels, and a base run by something that is
	## turning is a base worth clearing out. `rescue_band` is the band at which
	## a survivor will not go anywhere with you.
	"human_raid": {"chance": [0.0, 0.25, 0.55]},
	"rescue_refuse_band": 2,
	## The three bands, low to high. `at` is the value the band starts at, and
	## the modifiers are applied by `Perks.recompute_stats` and by nothing
	## else (invariant 4) — a band change is what triggers the recompute, so
	## the meter moving a tenth of a point costs nothing.
	"bands": [
		{
			"id": "human", "name": "HUMAN", "at": 0.0, "color": "#9fd07a",
			"add": {}, "mul": {},
			"desc": "Normal. You pass for a person.",
		},
		{
			"id": "turning", "name": "TURNING", "at": 35.0, "color": "#d9c46a",
			"add": {"melee_mul": 0.20, "speed_mul": 0.06, "max_stam": 15.0},
			"mul": {"spread_mul": 1.25, "gun_mul": 0.95, "sense_mul": 0.9},
			"desc": "Stronger, faster, and worse with a gun. People notice.",
		},
		{
			"id": "feral", "name": "FERAL", "at": 70.0, "color": "#b07ad0",
			# Toughness rather than damage reduction: `armor_dr` is summed from
			# worn gear and capped, and a band adding to it after the cap
			# would either break the cap or be silently inert on the exact
			# player most likely to be Feral. Pain shows up as `stagger_mul`.
			"add": {"melee_mul": 0.45, "speed_mul": 0.12, "max_stam": 25.0, "max_hp": 15.0},
			"mul": {"spread_mul": 1.6, "gun_mul": 0.88, "sense_mul": 0.6, "stagger_mul": 0.5},
			"desc": "Dangerous. The dead barely notice you. The living do.",
		},
	],
}

## Buffs and debuffs, all of them, in one table. What raw brain matter does to
## you on the way down, what a meal is worth, what an experimental dose buys —
## every one of them is an id and a number of seconds on `PlayerSim.effects`,
## applied inside the one function that writes stats (invariant 4).
## This is also where food and drink live, mechanically. **There is no hunger
## meter and there never will be** (pillar 1): a meal is a buff with a clock
## on it, so eating is something you do before a run rather than something the
## game nags you about. Nothing in here is ever a requirement.
const EFFECTS := {
	"nausea": {
		"id": "nausea", "name": "Nausea", "dur": 60.0, "good": false, "color": "#8aa06a",
		"add": {}, "mul": {"speed_mul": 0.92, "spread_mul": 1.25, "stam_regen": 0.8},
		"desc": "Raw brain matter fighting back.",
	},
	## The Experimental dose, and the reason anybody takes one: ninety seconds
	## of being better than human on top of three quarters of the bar.
	"surge": {
		"id": "surge", "name": "Surge", "dur": 90.0, "good": true, "color": "#d0a06a",
		"add": {"melee_mul": 0.35, "speed_mul": 0.10}, "mul": {"stam_regen": 1.3},
		"desc": "Everything is louder and you are faster than it.",
	},
	## And the one-in-four it costs. Note `mut_rate_mul`: a fever does not just
	## weaken you, it turns you faster — the risk is on the same axis as the
	## reward, which is what stops Experimental being a free win.
	"fever": {
		"id": "fever", "name": "Fever", "dur": 120.0, "good": false, "color": "#c96a5a",
		"add": {}, "mul": {"max_stam": 0.85, "spread_mul": 1.2, "mut_rate_mul": 1.15},
		"desc": "It fought back. You are burning up, and turning faster.",
	},

	# ------------------------------------------------------ food and drink --
	"fed": {
		"id": "fed", "name": "Fed", "dur": 300.0, "good": true, "color": "#c4a86a",
		"add": {"max_stam": 10.0}, "mul": {"stam_regen": 1.2},
		"desc": "Something in you. You last longer.",
	},
	"sated": {
		"id": "sated", "name": "Sated", "dur": 300.0, "good": true, "color": "#b98a5a",
		"add": {"max_hp": 12.0}, "mul": {"melee_mul": 1.1},
		"desc": "A real meal. You hit harder and take more.",
	},
	"steady": {
		"id": "steady", "name": "Steady", "dur": 240.0, "good": true, "color": "#9fd0ff",
		"add": {}, "mul": {"spread_mul": 0.9, "gun_mul": 1.05},
		"desc": "Warm, sat down, hands still. You shoot straighter.",
	},
	"hydrated": {
		"id": "hydrated", "name": "Hydrated", "dur": 300.0, "good": true, "color": "#6ad0c4",
		"add": {}, "mul": {"mut_rate_mul": 0.85, "stam_regen": 1.05},
		"desc": "Water slows the change. Nobody knows why.",
	},
	"wired": {
		"id": "wired", "name": "Wired", "dur": 180.0, "good": true, "color": "#e0c24a",
		"add": {"speed_mul": 0.08}, "mul": {"fire_rate_mul": 0.92, "stam_regen": 1.1},
		"desc": "Caffeine and sugar. Faster hands, faster feet.",
	},
	"drunk": {
		"id": "drunk", "name": "Drunk", "dur": 180.0, "good": true, "color": "#d98a4a",
		"add": {"melee_mul": 0.15}, "mul": {"stagger_mul": 0.7, "spread_mul": 1.3},
		"desc": "Braver, harder to stop, and you could not hit a wall.",
	},
}

# --------------------------------------------------------------------- fire --

## Fire is what a fire arrow leaves behind: a crowd weapon with a real cost.
## It clears a horde, it can take the treeline you were going to chop, and it
## burns whoever is standing in it — you included.
##
## **Nothing here can reach a player structure.** That is a decision carried
## from the prototype, not an oversight: losing your base to your own tower
## would be the kind of surprise that ends a run. A test asserts it stays so.
const FIRE := {
	# On an enemy.
	"burn_time": 6.5,
	"burn_dps": 9.0,
	# How often a burning thing tries to set light to what is around it.
	"spread_every": 0.6,
	"to_enemy_radius": 42.0,
	"to_enemy_chance": 0.45,
	"to_prop_radius": 46.0,
	"to_prop_chance": 0.22,
	# A burning piece of scenery.
	"prop_life": 7.0,
	"prop_spread_radius": TILE * 1.6,
	"prop_spread_chance": 0.16,
	"prop_dps": 16.0,
	"prop_hurt_radius": 26.0,
	# A ceiling, because the forest is thousands of pines and a fire that
	# could take all of them at once would take the frame rate with it.
	"max_fires": 140,
	# Says so, once, when a fire you started is getting away from you.
	"wildfire_warn_at": 25,
}

## Scenery that burns. Rock, boulder, silo and wreck do not.
##
## **`hay` and `reed` are in this list and cannot currently catch**, and the
## same is true in the prototype this is ported from. Fire finds scenery by
## tile through `World.prop_at_tile`, and both are appended straight to
## `world.props` by the generator without a `prop_grid` entry — hay because
## `_add_scenery` never indexed non-harvestable scenery, reeds because the
## shoreline pass appends them directly. They are left in the table because
## a hay bale *is* flammable and the list is the design, not the plumbing.
##
## Making them reachable is a one-line index pass, but it is a gameplay
## change rather than a fix: it puts non-harvestable props in front of the
## melee chop check and the interact scan, and measurably moves the
## simulation (it broke four smoke checkpoints when tried). It wants its own
## change and its own playtest, not a line in a review pass.
const FLAMMABLE := ["tree", "pine", "bush", "thicket", "litter", "hay", "reed"]

# ---------------------------------------------------------------- resources --

## Everything that stacks as a count. Phase 2 uses the ammunition and the
## medical entries; Phase 3's inventory uses the rest. `wt` per unit.
const RES := {
	"wood":    {"name": "Wood",         "short": "WOOD", "color": "#a3763f", "wt": 1.0,  "stack": 50},
	"sticks":  {"name": "Sticks",       "short": "STCK", "color": "#8a6a3c", "wt": 0.5,  "stack": 50},
	"stone":   {"name": "Stone",        "short": "STNE", "color": "#8f8a80", "wt": 1.5,  "stack": 50},
	"fiber":   {"name": "Fiber",        "short": "FIBR", "color": "#9aae5a", "wt": 0.3,  "stack": 50},
	"scrap":   {"name": "Scrap",        "short": "SCRP", "color": "#9aa2ab", "wt": 1.0,  "stack": 50},
	"cloth":   {"name": "Cloth",        "short": "CLTH", "color": "#c2a98a", "wt": 1.0,  "stack": 50},
	"elec":    {"name": "Electronics",  "short": "ELEC", "color": "#59b8c4", "wt": 1.0,  "stack": 30},
	"battery": {"name": "Batteries",    "short": "BATT", "color": "#8fd08a", "wt": 0.5,  "stack": 20},
	"med":     {"name": "Medical",      "short": "MED",  "color": "#d9575f", "wt": 1.0,  "stack": 30},
	"parts":   {"name": "Weapon Parts", "short": "PART", "color": "#c9a227", "wt": 1.0,  "stack": 20},
	"mil":     {"name": "Military",     "short": "MIL",  "color": "#7fa14a", "wt": 1.0,  "stack": 20},
	"fuel":    {"name": "Fuel",         "short": "FUEL", "color": "#d2762c", "wt": 1.0,  "stack": 20},
	"rations": {"name": "Rations",      "short": "FOOD", "color": "#c4a86a", "wt": 1.0,  "stack": 20},
	"arrow":   {"name": "Arrows",       "short": "ARRW", "color": "#b9a072", "wt": 0.15, "stack": 60},
	"ammoP":   {"name": "9mm Rounds",   "short": "9MM",  "color": "#d8c98a", "wt": 0.2,  "stack": 120},
	"ammoS":   {"name": "Shells",       "short": "SHEL", "color": "#c9584e", "wt": 0.3,  "stack": 60},
	"ammoR":   {"name": "Rifle Rounds", "short": "RIFL", "color": "#b8a05a", "wt": 0.25, "stack": 90},
}

const CONSUMABLES := {
	"bandage": {"id": "bandage", "name": "Bandage", "heal": 28.0, "time": 0.9, "color": "#d8cfc0"},
	"medkit":  {"id": "medkit",  "name": "Medkit",  "heal": 80.0, "time": 1.6, "color": "#d9575f"},
	# Brain matter, and what it is worth. `mut` is how much eating it takes
	# off the Mutation meter; `effect` is what it does to you on the way down.
	# Quality is why a Brute is worth walking toward and a Behemoth is worth
	# a magazine: the tissue a body gives up depends on what the body was.
	"brainRaw": {"id": "brainRaw", "name": "Raw Brain Matter", "heal": 0.0, "time": 2.0,
		"mut": 10.0, "effect": "nausea", "color": "#c07f9a", "stack": 20, "wt": 0.4},
	"brainMut": {"id": "brainMut", "name": "Mutated Brain Matter", "heal": 0.0, "time": 2.2,
		"mut": 20.0, "effect": "nausea", "effect_mul": 1.5, "color": "#b06ad0", "stack": 20, "wt": 0.4},
	# Not eaten: this is the ingredient the chemistry is built on. `tool`
	# keeps it out of every "use what is to hand" path, the way a lockpick is.
	"brainSpec": {"id": "brainSpec", "name": "Neural Tissue", "heal": 0.0, "time": 0.0,
		"color": "#7fd0c4", "stack": 10, "wt": 0.3, "tool": true},
	# What a base does with raw tissue: three times the suppression and none
	# of the nausea. The first step of a chain that ends at a chemistry bench.
	"serum": {"id": "serum", "name": "Stabilized Neural Serum", "heal": 0.0, "time": 1.6,
		"mut": 30.0, "color": "#8fd08a", "stack": 10, "wt": 0.5},
	# The chemistry tier. Refined is what a base with a bench and a supply of
	# Brutes can keep you on indefinitely; Experimental is the gamble — three
	# quarters of the bar, a minute and a half of being something better than
	# human, and a one-in-four chance of paying for it afterwards.
	"suppressant": {"id": "suppressant", "name": "Refined Suppressant", "heal": 0.0, "time": 2.0,
		"mut": 50.0, "color": "#6ad0c4", "stack": 10, "wt": 0.6},
	"experimental": {"id": "experimental", "name": "Experimental Suppressant", "heal": 0.0, "time": 2.4,
		"mut": 75.0, "effect": "surge", "risk": {"chance": 0.25, "effect": "fever"},
		"color": "#d0a06a", "stack": 5, "wt": 0.7},
	# Not a healing item — it opens car doors (Phase 4). It lives here so it
	# rides along in the same inventory the rest of the small stuff uses.
	"lockpick": {"id": "lockpick", "name": "Lockpick", "heal": 0.0, "time": 0.0, "color": "#9aa2ab", "tool": true},

	# ------------------------------------------------------ food and drink --
	#
	# Buffs, and nothing else. No hunger bar sits under this table and none is
	# coming (pillar 1): eating is a thing you do before a run, not a thing
	# the game asks you for every five minutes. `food` is what the quick key
	# looks for and `rank` is the order it reaches — commonest first, so a
	# tap of F never spends the Field Ration you were saving.
	"cannedFood": {"id": "cannedFood", "name": "Tinned Food", "heal": 0.0, "time": 1.6,
		"food": true, "rank": 1, "effect": "fed", "color": "#c4a86a", "stack": 15, "wt": 0.6},
	"jerky": {"id": "jerky", "name": "Dried Meat", "heal": 0.0, "time": 1.4,
		"food": true, "rank": 2, "effect": "sated", "color": "#b98a5a", "stack": 15, "wt": 0.4},
	"hotMeal": {"id": "hotMeal", "name": "Hot Meal", "heal": 15.0, "time": 2.4,
		"food": true, "rank": 4, "effect": "steady", "color": "#d9a05a", "stack": 5, "wt": 0.9},
	"mre": {"id": "mre", "name": "Field Ration", "heal": 10.0, "time": 2.0,
		"food": true, "rank": 5, "effect": "fed", "effect_mul": 2.0, "color": "#7fa14a", "stack": 10, "wt": 0.8},
	"candyBar": {"id": "candyBar", "name": "Candy Bar", "heal": 0.0, "time": 0.8,
		"food": true, "rank": 0, "effect": "wired", "effect_mul": 0.6, "color": "#d0709a", "stack": 20, "wt": 0.2},
	"water": {"id": "water", "name": "Clean Water", "heal": 0.0, "time": 1.2,
		"food": true, "rank": 1, "effect": "hydrated", "color": "#6ad0c4", "stack": 15, "wt": 0.8},
	"soda": {"id": "soda", "name": "Warm Soda", "heal": 0.0, "time": 1.2,
		"food": true, "rank": 2, "effect": "wired", "color": "#c95a8a", "stack": 15, "wt": 0.7},
	"coffee": {"id": "coffee", "name": "Instant Coffee", "heal": 0.0, "time": 1.6,
		"food": true, "rank": 3, "effect": "wired", "effect_mul": 1.6, "color": "#8a6a3c", "stack": 10, "wt": 0.3},
	"booze": {"id": "booze", "name": "Bottle of Spirits", "heal": 0.0, "time": 1.8,
		"food": true, "rank": 6, "effect": "drunk", "color": "#d98a4a", "stack": 8, "wt": 1.0},
}

# --------------------------------------------------------------------- gear --

## What counts as "the player's base" — the thing the game had no concept of,
## which is why zombies could walk out of thin air inside the walls.
##
## The base is a radius around every piece marked `protect`: a bunk, a stash, a
## workbench, a tower. Those are the pieces somebody deliberately planted to
## make a place theirs. A length of wall is not one, so a fence post out in the
## country claims no ground, and a compound with two ends has two anchors
## rather than an average of them that covers neither.
##
## Raids are not bound by this. A raid is how a base is meant to be attacked;
## what this stops is the ambient stream materialising in the kitchen.
const BASE := {"radius": 420.0}

## Where ground litter — sticks, fiber, a loose stone — is allowed to lie, and
## how thickly. Nature stays in nature: a stick on a tarmac road or a tuft of
## dry grass on a kitchen floor reads as a bug, because it is one. Any surface
## missing from this table takes no litter at all, which is what keeps building
## interiors clear without every caller having to remember to check.
const LITTER_SURFACES := {
	T.GRASS: 0.045,
	T.DIRT: 0.045,
	T.GRAVEL: 0.03,
	T.SAND: 0.03,
	T.FIELD: 0.03,
}

const GEAR_SLOTS := ["head", "body", "hands", "legs", "feet", "offhand"]
const GEAR_SLOT_NAMES := {"head": "Head", "body": "Body", "hands": "Hands", "legs": "Legs", "feet": "Feet", "offhand": "Off-hand"}

## The five slots that carry damage reduction. Every armour rule — three tiers
## per slot, a full set under the cap, the body the biggest single
## contributor — is about these and not about the off-hand, which holds a
## light and protects nothing.
const ARMOR_SLOTS := ["head", "body", "hands", "legs", "feet"]

## Fifteen armour pieces, three tiers across five slots, plus the two lights.
## A full tier-1 set is 0.23 DR, a full tier-3 set 0.70, against a hard cap of
## 0.72: scavenging can make you tough, never immune.
##
## `light` is what Phase 4's renderer punches out of the darkness and `burn`
## is how many seconds of being lit the thing holds. The torch is the first
## night's answer — sticks and fiber — and burns itself away. The flashlight
## is brighter and reaches much further because it is a cone rather than a
## puddle, and it eats batteries, which you find before you can make them.
const GEAR := {
	"hardHat":     {"id": "hardHat",     "name": "Hard Hat",        "slot": "head",  "dr": 0.05, "wt": 3.0,  "tier": 1, "color": "#c9a227"},
	"riotHelm":    {"id": "riotHelm",    "name": "Riot Helmet",     "slot": "head",  "dr": 0.10, "wt": 5.0,  "tier": 2, "color": "#4d5866"},
	"milHelm":     {"id": "milHelm",     "name": "Combat Helmet",   "slot": "head",  "dr": 0.15, "wt": 6.0,  "tier": 3, "color": "#5b6640"},
	"lightVest":   {"id": "lightVest",   "name": "Padded Vest",     "slot": "body",  "dr": 0.10, "wt": 6.0,  "tier": 1, "color": "#6f7a52"},
	"heavyVest":   {"id": "heavyVest",   "name": "Riot Armor",      "slot": "body",  "dr": 0.20, "wt": 11.0, "tier": 2, "color": "#4d5866"},
	"milVest":     {"id": "milVest",     "name": "Plate Carrier",   "slot": "body",  "dr": 0.28, "wt": 14.0, "tier": 3, "color": "#5b6640"},
	"workGloves":  {"id": "workGloves",  "name": "Work Gloves",     "slot": "hands", "dr": 0.02, "wt": 1.0,  "tier": 1, "color": "#a3763f"},
	"tacGloves":   {"id": "tacGloves",   "name": "Tactical Gloves", "slot": "hands", "dr": 0.04, "wt": 2.0,  "tier": 2, "color": "#4d5866"},
	"armGuards":   {"id": "armGuards",   "name": "Arm Guards",      "slot": "hands", "dr": 0.07, "wt": 4.0,  "tier": 3, "color": "#5b6640"},
	"denimPants":  {"id": "denimPants",  "name": "Work Trousers",   "slot": "legs",  "dr": 0.04, "wt": 2.0,  "tier": 1, "color": "#4a5a72"},
	"paddedLegs":  {"id": "paddedLegs",  "name": "Padded Leggings", "slot": "legs",  "dr": 0.08, "wt": 5.0,  "tier": 2, "color": "#6f7a52"},
	"milGreaves":  {"id": "milGreaves",  "name": "Combat Trousers", "slot": "legs",  "dr": 0.12, "wt": 7.0,  "tier": 3, "color": "#5b6640"},
	"workBoots":   {"id": "workBoots",   "name": "Work Boots",      "slot": "feet",  "dr": 0.02, "wt": 3.0,  "tier": 1, "color": "#6b4a2f"},
	"combatBoots": {"id": "combatBoots", "name": "Combat Boots",    "slot": "feet",  "dr": 0.05, "wt": 4.0,  "tier": 2, "color": "#3f4a38"},
	"milBoots":    {"id": "milBoots",    "name": "Assault Boots",   "slot": "feet",  "dr": 0.08, "wt": 5.0,  "tier": 3, "color": "#5b6640"},
	"torch": {
		"id": "torch", "name": "Torch", "slot": "offhand", "dr": 0.0, "wt": 2.0, "tier": 1,
		"color": "#e0913a", "light": {"radius": 200.0, "strength": 0.80, "warm": "#ffb45a"},
		"burn": 210.0, "consumed": true,
	},
	"flashlight": {
		"id": "flashlight", "name": "Flashlight", "slot": "offhand", "dr": 0.0, "wt": 2.0, "tier": 2,
		"color": "#d8d2c0",
		"light": {"radius": 140.0, "strength": 0.72, "warm": "#fff6cd", "cone_len": 460.0, "cone_spread": 0.34, "cone_strength": 0.86},
		"burn": 300.0, "battery": "battery",
	},
}

## No amount of scavenging should make you immune.
const MAX_GEAR_DR := 0.72

## A lit player is noticed this much further out — the cost of seeing at night.
const LIT_SENSE_BONUS := 90.0

## What Gunsmith multiplies: everything a gun eats. Crafting a batch of
## bandages is not ammunition and is not affected.
const AMMO_IDS := ["arrow", "ammoP", "ammoS", "ammoR"]

## Weapons and consumables carry no weight of their own in the tables, so the
## item registry gives them these. A gun is six units; a bandage is half one.
const WEAPON_WT := 6.0
const CONSUMABLE_WT := 0.5
const CONSUMABLE_STACK := 10

# ------------------------------------------------------------------ weapons --

## Melee: dmg / cd / range / arc / knock. Tools are deliberately poor weapons;
## `axe`, `pick`, `knife`, `scythe`, `hammer` are what the harvest gates ask
## for, `chop_mul` is how much better than a fist they are at scenery. The
## stone tools come before the metal ones so a fresh game finds them first.
## Guns: real magazines, reload time, spread (radians), bullet speed and life,
## pellets, pierce, threat per shot and a noise radius. The bow is a gun with
## a magazine of one and no muzzle flash; it keeps drawing while held.
const WEAPONS := {
	"fists":     {"id": "fists",     "name": "Fists",            "kind": "melee", "dmg": 9.0,  "cd": 0.42, "range": 34.0, "arc": 1.0,  "knock": 70.0,  "color": "#c8b89a"},
	"pipe":      {"id": "pipe",      "name": "Steel Pipe",       "kind": "melee", "dmg": 24.0, "cd": 0.40, "range": 48.0, "arc": 1.15, "knock": 150.0, "dur": 220, "color": "#9aa2ab"},
	"machete":   {"id": "machete",   "name": "Machete",          "kind": "melee", "dmg": 40.0, "cd": 0.34, "range": 54.0, "arc": 1.0,  "knock": 110.0, "chop_mul": 1.3, "dur": 260, "color": "#cfd6dd"},
	"axe":       {"id": "axe",       "name": "Hatchet",          "kind": "melee", "dmg": 30.0, "cd": 0.52, "range": 48.0, "arc": 0.9,  "knock": 130.0, "tool": true, "axe": true, "chop_mul": 2.4, "dur": 140, "color": "#b08a5a"},
	"pick":      {"id": "pick",      "name": "Stone Pickaxe",    "kind": "melee", "dmg": 26.0, "cd": 0.62, "range": 50.0, "arc": 0.9,  "knock": 150.0, "tool": true, "pick": true, "chop_mul": 2.2, "tool_mul": 2.4, "dur": 140, "color": "#9a9088"},
	"knife":     {"id": "knife",     "name": "Stone Knife",      "kind": "melee", "dmg": 19.0, "cd": 0.28, "range": 40.0, "arc": 0.8,  "knock": 60.0,  "tool": true, "knife": true, "chop_mul": 1.5, "dur": 160, "color": "#c2b8a6"},
	"scythe":    {"id": "scythe",    "name": "Scythe",           "kind": "melee", "dmg": 24.0, "cd": 0.46, "range": 62.0, "arc": 1.6,  "knock": 80.0,  "tool": true, "scythe": true, "chop_mul": 2.0, "tool_mul": 2.2, "dur": 150, "color": "#b9b3a2"},
	"hammer":    {"id": "hammer",    "name": "Stone Hammer",     "kind": "melee", "dmg": 36.0, "cd": 0.72, "range": 46.0, "arc": 1.2,  "knock": 240.0, "tool": true, "hammer": true, "chop_mul": 1.8, "structure_mul": 0.8, "dur": 150, "color": "#8a8078"},
	"fireaxe":   {"id": "fireaxe",   "name": "Fire Axe",         "kind": "melee", "dmg": 34.0, "cd": 0.46, "range": 52.0, "arc": 1.0,  "knock": 190.0, "tool": true, "axe": true, "chop_mul": 4.2, "dur": 420, "color": "#c4463a"},
	"steelpick": {"id": "steelpick", "name": "Steel Pickaxe",    "kind": "melee", "dmg": 30.0, "cd": 0.56, "range": 54.0, "arc": 0.9,  "knock": 210.0, "tool": true, "pick": true, "chop_mul": 4.4, "tool_mul": 2.4, "dur": 420, "color": "#aeb6bd"},
	"sledge":    {"id": "sledge",    "name": "Sledgehammer",     "kind": "melee", "dmg": 78.0, "cd": 0.86, "range": 60.0, "arc": 1.7,  "knock": 340.0, "shake": 5.0, "chop_mul": 1.6, "structure_mul": 1.0, "dur": 300, "color": "#8d7a5e"},
	"bow":       {"id": "bow",       "name": "Hunting Bow",      "kind": "gun", "dmg": 19.0, "cd": 0.85,  "mag": 1,  "reload": 0.55, "spread": 0.03,  "ammo": "arrow", "speed": 780.0,  "life": 0.85, "knock": 60.0,  "shake": 0.4, "pellets": 1, "pierce": 0, "threat": 0.15, "noise": 90.0,  "bow": true, "dur": 260, "color": "#9a7a48"},
	"pistol":    {"id": "pistol",    "name": "M9 Pistol",        "kind": "gun", "dmg": 27.0, "cd": 0.17,  "mag": 12, "reload": 1.15, "spread": 0.035, "ammo": "ammoP", "speed": 1150.0, "life": 0.55, "knock": 55.0,  "shake": 1.6, "pellets": 1, "pierce": 0, "threat": 1.0,  "noise": 420.0, "dur": 600, "color": "#71787f"},
	"smg":       {"id": "smg",       "name": "Scrap SMG",        "kind": "gun", "dmg": 17.0, "cd": 0.075, "mag": 30, "reload": 1.6,  "spread": 0.075, "ammo": "ammoP", "speed": 1100.0, "life": 0.5,  "knock": 40.0,  "shake": 1.2, "pellets": 1, "pierce": 0, "threat": 0.6,  "noise": 400.0, "dur": 900, "color": "#6b7178"},
	"shotgun":   {"id": "shotgun",   "name": "Pump Shotgun",     "kind": "gun", "dmg": 16.0, "cd": 0.75,  "mag": 6,  "reload": 0.5,  "spread": 0.20,  "ammo": "ammoS", "speed": 980.0,  "life": 0.30, "knock": 230.0, "shake": 6.5, "pellets": 8, "pierce": 0, "threat": 2.4,  "noise": 620.0, "shell_reload": true, "dur": 320, "color": "#5e5148"},
	"rifle":     {"id": "rifle",     "name": "Hunting Rifle",    "kind": "gun", "dmg": 78.0, "cd": 0.52,  "mag": 8,  "reload": 1.9,  "spread": 0.012, "ammo": "ammoR", "speed": 1700.0, "life": 0.9,  "knock": 120.0, "shake": 4.2, "pellets": 1, "pierce": 2, "threat": 2.0,  "noise": 700.0, "dur": 400, "color": "#4c4136"},
	"carbine":   {"id": "carbine",   "name": "Military Carbine", "kind": "gun", "dmg": 36.0, "cd": 0.105, "mag": 40, "reload": 2.3,  "spread": 0.045, "ammo": "ammoR", "speed": 1500.0, "life": 0.8,  "knock": 70.0,  "shake": 2.0, "pellets": 1, "pierce": 1, "threat": 1.1,  "noise": 560.0, "dur": 1100, "color": "#4a5340"},
}

## Wear and repair. `dur` on a weapon above is how many *uses* it has in it:
## one connecting melee swing, or one shot. A swing that hits nothing costs
## nothing, which is the same rule that already makes flailing at the scenery
## free. A weapon with no `dur` never wears at all — that is what Fists are.
##
## `chop_mul` is the other half of the honest version: felling a tree is what
## actually blunts an axe, and it costs a tool twice what a walker does.
##
## Repair is the structure rule, applied to a recipe instead of a build cost:
## a share of what the thing cost to make, scaled by how worn it is, at the
## bench that makes it. `worn_at` and `spent_at` are only where the warnings
## fire — nothing about the weapon changes until it is broken, because a
## weapon that got quietly worse would be a chore you could not see.
##
## Every number here is a feel number and none of them has been played yet.
## Notion's Durability column is where the owner's per-weapon intent belongs;
## it is blank for every weapon in the game today, so these are the code's
## first guess and are meant to be argued with.
const WEAR := {
	# What a repair costs, as a share of the recipe, scaled by the wear.
	"repair_cost_share": 0.5,
	# Harvesting is harder on a tool than fighting is.
	"chop_mul": 2,
	# "Worn" and "nearly gone": one warning each, once per crossing.
	"worn_at": 0.3,
	"spent_at": 0.1,
}

## What each kind of scenery gives up and what it takes. `needs` is the tool
## without which nothing happens; `boost` merely does it better. Small
## scenery never has a `needs`: the tools are made from what it drops.
const HARVEST := {
	"wood":          {"res": "wood",  "min": 6, "max": 11, "bonus": "sticks", "bonus_min": 1, "bonus_max": 3, "needs": "axe", "xp": 4, "label": "WOOD"},
	"fiber":         {"res": "fiber", "min": 2, "max": 4,  "bonus": "sticks", "bonus_min": 1, "bonus_max": 2, "boost": "scythe", "xp": 2, "label": "FIBER"},
	"stone":         {"res": "stone", "min": 2, "max": 4,  "boost": "pick", "xp": 2, "label": "STONE"},
	"boulder":       {"res": "stone", "min": 9, "max": 16, "needs": "pick", "xp": 5, "label": "STONE"},
	"litter_sticks": {"res": "sticks", "min": 2, "max": 4, "xp": 1, "label": "STICKS"},
	"litter_stone":  {"res": "stone",  "min": 1, "max": 3, "xp": 1, "label": "STONE"},
	"litter_fiber":  {"res": "fiber",  "min": 2, "max": 4, "xp": 1, "label": "FIBER"},
	"thicket":       {"res": "fiber", "min": 9, "max": 15, "bonus": "sticks", "bonus_min": 2, "bonus_max": 4, "needs": "scythe", "xp": 4, "label": "FIBER"},
}

const NEEDS_HINT := {
	"axe": "You need a HATCHET to fell trees — bushes give fiber and sticks, rocks give stone",
	"pick": "That boulder needs a STONE PICKAXE — loose rocks you can break by hand",
	"scythe": "That thicket needs a SCYTHE — small bushes you can pull by hand",
}

## What a new survivor wakes up with: a pipe in the first hotbar slot and a
## couple of bandages beside it. Everything else is out there to be found.
## `weapon` is also what a death drop leaves you, so a respawn is never
## completely toothless.
const START_KIT := {
	"weapon": "pipe",
	"hotbar": [["pipe", 1], ["bandage", 2]],
}

## The six-weapon test kit. Not what a game starts with — the smoke run and
## the combat tests ask for it by name so they can fire everything.
const TEST_KIT := {
	"hotbar": [["pipe", 1], ["axe", 1], ["bow", 1], ["pistol", 1], ["shotgun", 1], ["rifle", 1]],
	"bag": [["arrow", 30], ["ammoP", 60], ["ammoS", 24], ["ammoR", 16], ["bandage", 4], ["medkit", 1]],
}

# ------------------------------------------------------------------ enemies --

## Four tiers. `struct_mul` scales damage against player structures only:
## walkers and runners threaten you, brutes are what breaches a wall.
const ENEMIES := {
	"walker":   {"id": "walker",   "name": "Walker",   "hp": 58.0,   "speed": 60.0,  "dmg": 13.0, "atk_cd": 1.0,  "atk_range": 26.0, "r": 12.0, "xp": 10,  "sense": 330.0, "knock_resist": 0.0,  "struct_mul": 0.5, "threat": 0.35, "body": "#5c6b45", "dark": "#3d4a2e"},
	"runner":   {"id": "runner",   "name": "Runner",   "hp": 44.0,   "speed": 132.0, "dmg": 11.0, "atk_cd": 0.65, "atk_range": 25.0, "r": 11.0, "xp": 18,  "sense": 430.0, "knock_resist": 0.15, "struct_mul": 0.4, "threat": 0.5,  "body": "#7a5a3c", "dark": "#513a26"},
	"brute":    {"id": "brute",    "name": "Brute",    "hp": 300.0,  "speed": 52.0,  "dmg": 34.0, "atk_cd": 1.35, "atk_range": 34.0, "r": 19.0, "xp": 55,  "sense": 380.0, "knock_resist": 0.75, "struct_mul": 2.2, "threat": 1.1,  "body": "#6b4b52", "dark": "#452f34"},
	# ------------------------------------------------------------- the living --
	#
	# Humans. `human` is what separates them from everything above: they carry
	# no brain matter worth having, they shoot back, and they are here for what
	# is in your stash rather than for you.
	#
	# They come because of what you are becoming — a raid of theirs is rolled
	# against the Mutation band (see `MUTATION.human_raid`), which is what makes
	# the meter a bet with two sides instead of a bar with a bonus.
	#
	# One thing they deliberately are *not*: zombie food. Nothing in the game
	# has enemy-versus-enemy targeting, and bolting it on for one faction would
	# be a system with one caller. A raider firing a rifle does draw the horde
	# to itself, which is the honest half of that fight and costs nothing.
	"looter": {
		"id": "looter", "name": "Looter", "hp": 70.0, "speed": 118.0, "dmg": 10.0, "atk_cd": 0.8,
		"atk_range": 26.0, "r": 12.0, "xp": 30, "sense": 460.0, "knock_resist": 0.1,
		"struct_mul": 0.6, "threat": 0.6, "human": true, "body": "#8a7a5a", "dark": "#5a4d38",
		# What it is actually here for. It empties what it can reach and runs
		# for the map edge; kill it and you get it back.
		"steal": {"stacks": 3, "flee": 22.0},
		"loot_table": "raiderBody",
	},
	"raider": {
		"id": "raider", "name": "Raider", "hp": 120.0, "speed": 92.0, "dmg": 14.0, "atk_cd": 1.0,
		"atk_range": 28.0, "r": 13.0, "xp": 60, "sense": 620.0, "knock_resist": 0.2,
		"struct_mul": 0.8, "threat": 1.0, "human": true, "body": "#7a6a8a", "dark": "#4d4258",
		# A rifle. `standoff` is the range it wants to keep — closer than that
		# and it backs up, which is what makes fighting one different to
		# fighting anything else in the game.
		"gun": {"dmg": 15.0, "range": 430.0, "standoff": 300.0, "cd": 1.5, "burst": 2,
			"burst_gap": 0.14, "spread": 0.13, "speed": 900.0, "noise": 420.0, "sfx": "rifle", "color": "#ffd08a"},
		"loot_table": "raiderBody",
	},
	"enforcer": {
		"id": "enforcer", "name": "Enforcer", "hp": 260.0, "speed": 80.0, "dmg": 26.0, "atk_cd": 1.2,
		"atk_range": 32.0, "r": 16.0, "xp": 110, "sense": 560.0, "knock_resist": 0.6,
		"struct_mul": 1.4, "threat": 1.6, "human": true, "body": "#8a5a5a", "dark": "#573838",
		# A shotgun: short, brutal, and it walks toward you while it uses it.
		"gun": {"dmg": 9.0, "range": 210.0, "standoff": 120.0, "cd": 1.9, "pellets": 5,
			"spread": 0.34, "speed": 700.0, "noise": 520.0, "sfx": "shotgun", "color": "#ffd08a"},
		"loot_table": "enforcerBody",
	},
	"behemoth": {"id": "behemoth", "name": "Behemoth", "hp": 1100.0, "speed": 46.0,  "dmg": 58.0, "atk_cd": 1.6,  "atk_range": 44.0, "r": 27.0, "xp": 200, "sense": 900.0, "knock_resist": 0.95, "struct_mul": 4.0, "threat": 2.5,  "body": "#7d4348", "dark": "#4a262b", "boss": true},
}


## What a body gives up, by what it was. One head, one roll: a kill drops
## brain matter at most once, however many loot perks are stacked on top,
## because the joke only works if a corpse has one brain in it.
##
## This is the whole reason to prefer one fight over another. A Walker is
## small change; a Brute carries the tissue a Refined dose is made of; a
## Behemoth is a chemistry set that has to be shot forty times first.
const BRAIN_DROPS := {
	"walker":   {"chance": 0.45, "id": "brainRaw",  "min": 1, "max": 1},
	"runner":   {"chance": 0.55, "id": "brainRaw",  "min": 1, "max": 2},
	"brute":    {"chance": 0.85, "id": "brainMut",  "min": 1, "max": 1,
		"also": {"id": "brainRaw", "min": 1, "max": 2}},
	"behemoth": {"chance": 1.0,  "id": "brainSpec", "min": 1, "max": 2,
		"also": {"id": "brainMut", "min": 2, "max": 2}},
}

## The ambient spawner. A standing population per danger tier near each
## living player, scaled by night and by the quiet field. The ring is off
## screen; anything further than `cull` from every player is removed.
##
## count_radius reaches past the ring's outer edge. The prototype counted
## within 950px of a ring that ran 880–1300, so most of what it spawned
## never counted and a still player in tier 1 collected 26 enemies in 20
## seconds against a target of 4 (measured here). See PROJECT.md §6.
const SPAWN := {
	"density": [0, 4, 10, 17, 24],
	"mix": {
		1: [["walker", 0.94], ["runner", 0.06]],
		2: [["walker", 0.70], ["runner", 0.28], ["brute", 0.02]],
		3: [["walker", 0.52], ["runner", 0.36], ["brute", 0.12]],
		4: [["walker", 0.40], ["runner", 0.36], ["brute", 0.24]],
	},
	"max_enemies": 160,
	"interval": 0.6,
	"count_radius": 1400.0,
	"ring_min": 880.0,
	"ring_width": 420.0,
	"cull": 2400.0,
	"seed_count": 5,
	"seed_radius": 1100.0,
	"light_sense_bonus": 90.0,
	"sneak_sense_mul": 0.55,
}

## How loud things are, as a radius. Guns carry their own in WEAPONS.
const NOISE := {
	"chop": 140.0,
	"build": 190.0,
	"turret": 520.0,
	"generator": 300.0,
	"pick_snap": 260.0,
	"engine": 420.0,
	"crash": 380.0,
	"alert_time": 8.0,
}

## The quiet field: killing buys local, temporary calm. Raids ignore it.
const QUIET := {
	"cell": 256.0,
	"per_kill": 1.0,
	"max": 6.0,
	"decay_per_sec": 6.0 / 270.0,
	"suppress_at": 2.9,
	"struct_quiet": 1.6,
	"struct_radius": 400.0,
	"floor": 0.3,
	"kernel_reach": 1.7,
}

## Navigation: a local flow field around each living player, rebuilt when
## they move a tile or the world changes. Enemies beyond it steer straight.
const NAV := {
	"radius_tiles": 40,
	"rebuild_after_tiles": 1,
	"max_age": 1.5,
}

# --------------------------------------------------------------- threat/raid --

const THREAT := {
	"max": 100.0,
	"decay_per_sec": 0.12,
	"kill_walk": 0.35,
	"per_gunshot": 1.0,
	"per_build": 1.0,
	"per_craft": 0.4,
	"per_loot": 0.45,
	"generator_per_sec": 0.55,
	"turret_per_shot": 0.06,
	"post_raid_reset": 14.0,
	"warn_at": [40.0, 70.0, 90.0],
}

const RAIDS := [
	{"name": "SCATTERED HORDE", "waves": 2, "base": 8,  "growth": 3, "mix": {"walker": 1.0}, "reward": {"scrap": 30, "wood": 30, "parts": 2}, "xp": 120},
	{"name": "RUNNING HORDE",   "waves": 3, "base": 11, "growth": 4, "mix": {"walker": 0.65, "runner": 0.35}, "reward": {"scrap": 45, "parts": 3, "elec": 10}, "xp": 220},
	{"name": "HEAVY HORDE",     "waves": 3, "base": 14, "growth": 5, "mix": {"walker": 0.55, "runner": 0.3, "brute": 0.15}, "reward": {"scrap": 60, "parts": 5, "elec": 15, "mil": 3}, "xp": 360},
	{"name": "SIEGE",           "waves": 4, "base": 18, "growth": 6, "mix": {"walker": 0.45, "runner": 0.33, "brute": 0.22}, "reward": {"scrap": 80, "parts": 7, "elec": 20, "mil": 6}, "xp": 520},
	{"name": "BEHEMOTH SIEGE",  "waves": 4, "base": 22, "growth": 7, "mix": {"walker": 0.4, "runner": 0.32, "brute": 0.25, "behemoth": 0.03}, "reward": {"scrap": 110, "parts": 10, "elec": 28, "mil": 12}, "xp": 800},
]

## The other kind of raid. Same shape as `RAIDS` and run by the same code —
## waves, spawn ring, break-off, salvage — because a raid is a raid; what
## differs is who arrives and why. They come for the stash, so the payout for
## repelling one is what they were carrying rather than horde salvage.
##
## Smaller than a horde on purpose. Six people with rifles is a harder fight
## than twenty walkers, and being outnumbered by things that shoot back is not
## the fantasy — being *hunted by the living because of what you are becoming*
## is.
const HUMAN_RAIDS := [
	{"name": "SCAVENGER CREW", "waves": 1, "base": 4, "growth": 0, "mix": {"looter": 0.75, "raider": 0.25},
		"reward": {"scrap": 30, "ammoP": 24, "med": 6}, "xp": 200},
	{"name": "RAIDING PARTY", "waves": 2, "base": 4, "growth": 2, "mix": {"looter": 0.4, "raider": 0.5, "enforcer": 0.1},
		"reward": {"scrap": 50, "ammoR": 20, "parts": 4, "med": 8}, "xp": 380},
	{"name": "PURGE SQUAD", "waves": 2, "base": 6, "growth": 3, "mix": {"raider": 0.6, "enforcer": 0.4},
		"reward": {"scrap": 70, "mil": 8, "parts": 6, "ammoR": 30}, "xp": 640},
]


const RAID := {
	"warning_time": 12.0,
	"spawn_interval": 0.22,
	"ring_min": 520.0,
	"ring_max": 800.0,
	"relocate_min": 360.0,
	"relocate_max": 560.0,
	"hp_per_index": 0.06,
	"stall_interval": 4.0,
	"stall_limit": 12.0,
	# Only a raider this far from the raid centre is a candidate for the
	# anti-stall warp. It sits below ring_min so a raider wedged where it
	# spawned is still rescued, and well above melee reach so one shouldering
	# through the fight is never teleported out of it.
	"stall_radius": 400.0,
	"stall_closing": 30.0,
	"max_seconds": 300.0,
	"breakoff_time": 25.0,
	"inter_wave": 3.5,
	"anchor_on_player_beyond": 1500.0,
	"player_lure": 300.0,
	"kill_xp_mul": 1.25,
}


## Raids past the authored list keep scaling instead of stopping.
static func raid_spec(index: int) -> Dictionary:
	if index < RAIDS.size():
		return RAIDS[index]
	var last: Dictionary = RAIDS[RAIDS.size() - 1]
	var over := index - RAIDS.size() + 1
	var spec := last.duplicate(true)
	spec.name = "BEHEMOTH SIEGE +%d" % over
	spec.base = last.base + over * 5
	spec.growth = last.growth + over
	spec.xp = roundi(last.xp * (1.0 + over * 0.35))
	var reward := {}
	for id in last.reward:
		reward[id] = roundi(last.reward[id] * (1.0 + over * 0.3))
	spec.reward = reward
	return spec



# -------------------------------------------------------------------- audio --

## Every sound in the game, as a recipe rather than a file. Nothing is loaded
## from disk: `Sfx` renders each of these to a small PCM buffer once at boot
## and plays the buffer, which is the prototype's WebAudio graph with the
## synthesis moved from play time to build time.
##
## An op is either a `tone` — an oscillator with an optional pitch sweep — or a
## `noise` — white noise through a state-variable filter with an optional
## sweep. Both have a 5ms attack and an exponential decay across `dur`, and
## `at` delays one op inside the cue so a reload can be a click and then a
## clack.
const SFX_RATE := 22050
## Master gain. Everything below is relative to this.
const SFX_GAIN := 0.35
## Distance falloff, in world pixels. Inside `near` a sound is at full volume;
## past `range` it is not played at all. The prototype had neither — every
## sound was equally loud wherever it happened, so a turret across town was as
## close as the gun in your hand.
const SFX_NEAR := 340.0
const SFX_RANGE := 1500.0

const SFX := {
	# ------------------------------------------------------------- gunfire --
	"pistol": [
		{"kind": "noise", "dur": 0.09, "gain": 0.34, "filter": "hp", "freq": 900.0, "q": 0.6},
		{"kind": "tone", "freq": 320.0, "to": 60.0, "wave": "square", "dur": 0.08, "gain": 0.22},
	],
	"smg": [
		{"kind": "noise", "dur": 0.06, "gain": 0.24, "filter": "hp", "freq": 1100.0, "q": 0.6},
		{"kind": "tone", "freq": 380.0, "to": 90.0, "wave": "square", "dur": 0.05, "gain": 0.15},
	],
	"shotgun": [
		{"kind": "noise", "dur": 0.26, "gain": 0.5, "filter": "lp", "freq": 2600.0, "to": 180.0},
		{"kind": "tone", "freq": 150.0, "to": 40.0, "wave": "saw", "dur": 0.22, "gain": 0.3},
	],
	"rifle": [
		{"kind": "noise", "dur": 0.14, "gain": 0.42, "filter": "hp", "freq": 700.0, "q": 0.8},
		{"kind": "tone", "freq": 520.0, "to": 70.0, "wave": "square", "dur": 0.13, "gain": 0.26},
	],
	## Between the SMG and the rifle, which is what it is: fast, and it carries.
	"carbine": [
		{"kind": "noise", "dur": 0.08, "gain": 0.36, "filter": "hp", "freq": 850.0, "q": 0.7},
		{"kind": "tone", "freq": 440.0, "to": 80.0, "wave": "square", "dur": 0.07, "gain": 0.2},
	],
	## Somebody else's gun, from a tower across the base. Flatter and drier
	## than yours so a firefight you are in the middle of still reads as
	## yours — and it is a separate cue rather than a fallback because the
	## fallback is how the carbine nearly shipped with the pistol's bang.
	"survivor": [
		{"kind": "noise", "dur": 0.07, "gain": 0.26, "filter": "hp", "freq": 1000.0, "q": 0.8},
		{"kind": "tone", "freq": 360.0, "to": 90.0, "wave": "square", "dur": 0.06, "gain": 0.14},
	],
	"turret": [
		{"kind": "noise", "dur": 0.05, "gain": 0.14, "filter": "hp", "freq": 1500.0, "q": 0.7},
		{"kind": "tone", "freq": 620.0, "to": 200.0, "wave": "square", "dur": 0.05, "gain": 0.08},
	],
	## The bow has no bang. A limb creak and the string letting go, quiet
	## enough that using it instead of the pistol still sounds like a choice.
	"bow": [
		{"kind": "tone", "freq": 240.0, "to": 150.0, "wave": "tri", "dur": 0.05, "gain": 0.1},
		{"kind": "noise", "dur": 0.09, "gain": 0.13, "filter": "bp", "freq": 1800.0, "to": 700.0, "q": 1.6},
	],
	"dryfire": [{"kind": "tone", "freq": 900.0, "to": 500.0, "wave": "square", "dur": 0.04, "gain": 0.09}],
	"reload": [
		{"kind": "tone", "freq": 220.0, "to": 160.0, "wave": "square", "dur": 0.06, "gain": 0.14},
		{"kind": "noise", "dur": 0.05, "gain": 0.14, "filter": "bp", "freq": 2200.0, "q": 2.0, "at": 0.11},
	],
	"reload_done": [{"kind": "tone", "freq": 340.0, "to": 520.0, "wave": "square", "dur": 0.07, "gain": 0.16}],

	# --------------------------------------------------------------- melee --
	"swing": [{"kind": "noise", "dur": 0.13, "gain": 0.16, "filter": "bp", "freq": 900.0, "to": 320.0, "q": 1.2}],
	"melee_hit": [
		{"kind": "noise", "dur": 0.11, "gain": 0.34, "filter": "lp", "freq": 900.0, "to": 200.0},
		{"kind": "tone", "freq": 130.0, "to": 55.0, "wave": "tri", "dur": 0.1, "gain": 0.22},
	],
	"bullet_hit": [{"kind": "noise", "dur": 0.07, "gain": 0.2, "filter": "bp", "freq": 1400.0, "q": 1.4}],
	"hit_wall": [{"kind": "noise", "dur": 0.06, "gain": 0.14, "filter": "hp", "freq": 2400.0, "q": 2.0}],

	# ---------------------------------------------------------------- them --
	"zombie_die": [
		{"kind": "tone", "freq": 210.0, "to": 62.0, "wave": "saw", "dur": 0.34, "gain": 0.2},
		{"kind": "noise", "dur": 0.3, "gain": 0.16, "filter": "lp", "freq": 700.0, "to": 120.0},
	],
	## The pitch wobble the prototype rolled per call is `pitch_scale` on the
	## player instead — one buffer, a different voice every time.
	"growl": [{"kind": "tone", "freq": 115.0, "to": 60.0, "wave": "saw", "dur": 0.5, "gain": 0.1}],

	# ------------------------------------------------------------------ you --
	"player_hurt": [
		{"kind": "tone", "freq": 260.0, "to": 130.0, "wave": "tri", "dur": 0.18, "gain": 0.24},
		{"kind": "noise", "dur": 0.12, "gain": 0.16, "filter": "lp", "freq": 600.0},
	],
	"player_die": [
		{"kind": "tone", "freq": 340.0, "to": 55.0, "wave": "saw", "dur": 1.1, "gain": 0.3},
		{"kind": "noise", "dur": 1.0, "gain": 0.2, "filter": "lp", "freq": 900.0, "to": 90.0},
	],
	"heal": [{"kind": "tone", "freq": 420.0, "to": 700.0, "wave": "sine", "dur": 0.28, "gain": 0.2}],

	# ---------------------------------------------------------------- stuff --
	"pickup": [
		{"kind": "tone", "freq": 640.0, "wave": "square", "dur": 0.05, "gain": 0.14},
		{"kind": "tone", "freq": 960.0, "wave": "square", "dur": 0.06, "gain": 0.12, "at": 0.05},
	],
	"loot": [
		{"kind": "noise", "dur": 0.2, "gain": 0.16, "filter": "bp", "freq": 1100.0, "q": 1.1},
		{"kind": "tone", "freq": 480.0, "to": 720.0, "wave": "square", "dur": 0.1, "gain": 0.12, "at": 0.08},
	],
	"build": [
		{"kind": "tone", "freq": 180.0, "to": 300.0, "wave": "square", "dur": 0.09, "gain": 0.2},
		{"kind": "noise", "dur": 0.1, "gain": 0.2, "filter": "lp", "freq": 1400.0, "at": 0.02},
	],
	"craft": [
		{"kind": "tone", "freq": 300.0, "wave": "square", "dur": 0.06, "gain": 0.14},
		{"kind": "tone", "freq": 450.0, "wave": "square", "dur": 0.06, "gain": 0.14, "at": 0.07},
		{"kind": "tone", "freq": 680.0, "wave": "square", "dur": 0.1, "gain": 0.15, "at": 0.14},
	],
	"chop": [
		{"kind": "noise", "dur": 0.12, "gain": 0.24, "filter": "lp", "freq": 1200.0, "to": 260.0},
		{"kind": "tone", "freq": 190.0, "to": 90.0, "wave": "tri", "dur": 0.09, "gain": 0.14},
	],
	"deny": [{"kind": "tone", "freq": 200.0, "to": 120.0, "wave": "square", "dur": 0.12, "gain": 0.16}],
	"ui": [{"kind": "tone", "freq": 700.0, "wave": "square", "dur": 0.03, "gain": 0.07}],

	# ------------------------------------------------------------- moments --
	## The change taking a step. Two notes a minor third apart, sagging: it
	## should sound like something going wrong inside you rather than like a
	## warning somebody else is giving you.
	"mutate_up": [
		{"kind": "tone", "freq": 196.0, "to": 155.0, "wave": "tri", "dur": 0.5, "gain": 0.2},
		{"kind": "tone", "freq": 98.0, "to": 78.0, "wave": "saw", "dur": 0.6, "gain": 0.14, "at": 0.06},
	],
	## And a dose landing: the same shape, rising, and cleaner.
	"mutate_down": [
		{"kind": "tone", "freq": 165.0, "to": 262.0, "wave": "tri", "dur": 0.35, "gain": 0.18},
		{"kind": "tone", "freq": 330.0, "wave": "tri", "dur": 0.22, "gain": 0.12, "at": 0.14},
	],
	## A Lurch starting. The same falling third as `mutate_up` with the floor
	## pulled out from under it: it is the sound of losing an argument with
	## your own legs.
	"lurch": [
		{"kind": "tone", "freq": 147.0, "to": 55.0, "wave": "saw", "dur": 0.7, "gain": 0.28},
		{"kind": "noise", "dur": 0.5, "gain": 0.2, "filter": "lp", "freq": 600.0, "to": 120.0},
	],
	## Gone. Low, long, and not musical.
	"turned": [
		{"kind": "noise", "dur": 0.9, "gain": 0.3, "filter": "lp", "freq": 900.0, "to": 90.0},
		{"kind": "tone", "freq": 110.0, "to": 41.0, "wave": "saw", "dur": 1.1, "gain": 0.26},
		{"kind": "tone", "freq": 73.0, "to": 38.0, "wave": "tri", "dur": 1.2, "gain": 0.2, "at": 0.1},
	],
	"level_up": [
		{"kind": "tone", "freq": 523.0, "wave": "tri", "dur": 0.22, "gain": 0.2},
		{"kind": "tone", "freq": 659.0, "wave": "tri", "dur": 0.22, "gain": 0.2, "at": 0.09},
		{"kind": "tone", "freq": 784.0, "wave": "tri", "dur": 0.22, "gain": 0.2, "at": 0.18},
		{"kind": "tone", "freq": 1047.0, "wave": "tri", "dur": 0.22, "gain": 0.2, "at": 0.27},
	],
	"raid_warn": [
		{"kind": "tone", "freq": 220.0, "to": 150.0, "wave": "saw", "dur": 0.75, "gain": 0.26},
		{"kind": "tone", "freq": 224.0, "to": 154.0, "wave": "saw", "dur": 0.75, "gain": 0.2, "at": 0.02},
	],
	"raid_win": [
		{"kind": "tone", "freq": 392.0, "wave": "tri", "dur": 0.3, "gain": 0.22},
		{"kind": "tone", "freq": 523.0, "wave": "tri", "dur": 0.3, "gain": 0.22, "at": 0.11},
		{"kind": "tone", "freq": 659.0, "wave": "tri", "dur": 0.3, "gain": 0.22, "at": 0.22},
		{"kind": "tone", "freq": 784.0, "wave": "tri", "dur": 0.3, "gain": 0.22, "at": 0.33},
		{"kind": "tone", "freq": 1047.0, "wave": "tri", "dur": 0.3, "gain": 0.22, "at": 0.44},
	],
	"struct_hit": [{"kind": "noise", "dur": 0.1, "gain": 0.2, "filter": "lp", "freq": 700.0, "to": 200.0}],
	"struct_break": [
		{"kind": "noise", "dur": 0.45, "gain": 0.34, "filter": "lp", "freq": 1600.0, "to": 100.0},
		{"kind": "tone", "freq": 160.0, "to": 45.0, "wave": "saw", "dur": 0.4, "gain": 0.2},
	],
	## A car. The prototype had none of these — it had no cars when the audio
	## was written — so they are new and they are quiet, because an engine that
	## announces itself twice (Threat already does) gets old on a long drive.
	"engine_start": [
		{"kind": "tone", "freq": 60.0, "to": 130.0, "wave": "saw", "dur": 0.55, "gain": 0.2},
		{"kind": "noise", "dur": 0.5, "gain": 0.12, "filter": "lp", "freq": 400.0, "to": 900.0},
	],
	"engine_stop": [{"kind": "tone", "freq": 130.0, "to": 45.0, "wave": "saw", "dur": 0.4, "gain": 0.16}],
	"car_wreck": [
		{"kind": "noise", "dur": 0.6, "gain": 0.4, "filter": "lp", "freq": 2200.0, "to": 90.0},
		{"kind": "tone", "freq": 120.0, "to": 38.0, "wave": "saw", "dur": 0.5, "gain": 0.24},
	],
}

## Some cues fire many times in one frame. A shotgun hitting twelve zombies has
## to be one impact, not twelve, so an identical cue inside this many
## milliseconds is dropped. Anything not listed can fire as often as it likes.
const SFX_THROTTLE := {
	"bullet_hit": 28, "hit_wall": 40, "struct_hit": 45, "zombie_die": 30,
	"melee_hit": 25, "turret": 45, "growl": 260, "player_hurt": 140,
	"chop": 60, "pickup": 40, "ui": 30,
}

# ---------------------------------------------------------------------- map --

## The minimap and the town map.
##
## `aware` and `unaware` are reveal radii in pixels, multiplied by the player's
## `radar_mul`. The prototype drew *every* enemy in the world on the minimap
## and left `radarMul` set by Sixth Sense and read by nobody, which made a
## rank-6 Perception perk do literally nothing. Here the map shows what is
## near — further for the ones that have noticed you, because a horde already
## coming for you is not a secret — and Sixth Sense (radar_mul 2.4) is what
## turns it into a radar worth having.
const MAP := {
	"corner": 168.0,          # the always-on map, bottom right
	"aware": 900.0,           # an enemy that has noticed you
	"unaware": 380.0,         # one that has not
	"discover_xp": 25,        # per danger tier of the district
	"danger_tint": 26.0,      # red added to the image per tier above 1
	"blocked_shade": 0.75,    # what a wall or water does to the pixel
}

# ---------------------------------------------------------------- districts --

## Order matters: location_at_px returns the first match, so the small named
## places inside the forest come before the forest itself.
const LOCATIONS := [
	# the town
	{"id": "camp",       "name": "ROADSIDE CAMP",       "tier": 1, "rect": Rect2i(146, 146, 28, 28), "desc": "Quiet crossroads. Good first base."},
	{"id": "suburb",     "name": "PINE HOLLOW SUBURBS", "tier": 1, "rect": Rect2i(86, 86, 62, 58),   "desc": "Empty homes. Wood, cloth, odds and ends."},
	{"id": "residenceE", "name": "EAST TERRACES",       "tier": 2, "rect": Rect2i(176, 86, 56, 44),  "desc": "Denser housing. More of them here."},
	{"id": "commercial", "name": "MARKET ROW",          "tier": 2, "rect": Rect2i(172, 136, 60, 34), "desc": "Shops and a hardware store. Loud crowds."},
	{"id": "gas",        "name": "FUEL STOP",           "tier": 2, "rect": Rect2i(110, 162, 26, 22), "desc": "Fuel and scrap. Watch the pumps."},
	{"id": "police",     "name": "PRECINCT 12",         "tier": 3, "rect": Rect2i(178, 176, 40, 34), "desc": "Guns, ammo and armour. Heavily infested."},
	{"id": "hospital",   "name": "ST. MARTHA HOSPITAL", "tier": 3, "rect": Rect2i(90, 188, 46, 42),  "desc": "Medicine. The halls are full."},
	{"id": "industrial", "name": "DOCK YARD",           "tier": 3, "rect": Rect2i(144, 198, 30, 36), "desc": "Electronics and parts. Brutes work here."},
	{"id": "military",   "name": "CHECKPOINT DELTA",    "tier": 4, "rect": Rect2i(204, 204, 32, 32), "desc": "Military hardware. You will need a plan."},
	# the country
	{"id": "farms",      "name": "HOLLOW CREEK FARMS",  "tier": 1, "rect": Rect2i(2, 66, 52, 106),   "desc": "Fields and barns across the river. Food, fuel, quiet."},
	{"id": "ranch",      "name": "SADDLEBACK RANCH",    "tier": 1, "rect": Rect2i(2, 206, 52, 50),   "desc": "Paddocks and a stable. The end of the lane."},
	{"id": "lumber",     "name": "GRAYSON LUMBER",      "tier": 2, "rect": Rect2i(88, 14, 44, 38),   "desc": "Log stacks and a sawmill. Wood by the ton."},
	{"id": "lake",       "name": "LOON LAKE",           "tier": 2, "rect": Rect2i(170, 8, 54, 46),   "desc": "A lodge on the shore. Quiet, until it is not."},
	{"id": "junkyard",   "name": "RUST BELT SALVAGE",   "tier": 2, "rect": Rect2i(166, 250, 48, 42), "desc": "Wrecks stacked three high. Scrap and parts."},
	{"id": "forest",     "name": "BLACKPINE FOREST",    "tier": 2, "rect": Rect2i(0, 0, 320, 62), "label": Vector2i(150, 6), "desc": "Deep woods. Cabins, and things between the trees."},
	# the city
	{"id": "heights",    "name": "CROWN HEIGHTS",       "tier": 3, "rect": Rect2i(240, 62, 80, 68),  "desc": "Apartment blocks. Crowded, floor after floor."},
	{"id": "downtown",   "name": "DOWNTOWN",            "tier": 4, "rect": Rect2i(240, 132, 80, 82), "desc": "Office towers and the bank. The whole city died here."},
	{"id": "mall",       "name": "GALLERIA MALL",       "tier": 3, "rect": Rect2i(240, 216, 80, 54), "desc": "Shops, a drugstore and an outfitters. Everyone came here."},
]

# --------------------------------------------------------------- structures --

## Build anywhere: a "base" is wherever your structures happen to be.
##
## `solid` blocks feet but never bullets (invariant 3) — a base you cannot
## shoot out of is a base that punishes you for building it. `protect` marks
## the pieces a raider inside the perimeter should prefer, so a horde that
## is already through heads for the workbench rather than back out. `threat`
## scales what putting one up costs you in attention. `store` is a slot
## count; `tier` 2 needs the upgraded workbench.
const STASH_SLOTS := 48
const BENCH_UPGRADE_COST := {"scrap": 55, "elec": 20, "parts": 5}

const BUILD := {
	"range": 190.0,
	# About a compound, so post-raid recovery is one decision rather than a lap.
	"repair_all_range": 520.0,
	# A repair costs this share of the build price, scaled by the damage.
	"repair_cost_share": 0.45,
	"salvage_share": 0.5,
	"store_reach_bonus": 40.0,
	"bench_range": 110.0,
}

const STRUCTURES := {
	"bedroll": {
		"id": "bedroll", "name": "Bedroll", "cost": {"wood": 15, "cloth": 12}, "hp": 90.0,
		"solid": false, "tier": 1, "threat": 1.0,
		"desc": "Sets your respawn point. Only the newest one is active.",
	},
	"bunk": {
		"id": "bunk", "name": "Bunk", "cost": {"wood": 22, "cloth": 14}, "hp": 140.0,
		"solid": true, "tier": 1, "threat": 1.0, "protect": true, "houses": 1,
		"desc": "Somewhere for one survivor to sleep. No bunk, no recruit.",
	},
	"watchtower": {
		"id": "watchtower", "name": "Watchtower", "cost": {"wood": 45, "scrap": 20}, "hp": 420.0,
		"solid": true, "tier": 1, "threat": 2.0, "protect": true, "post": "sniper",
		"sniper_range": 520.0, "sniper_dmg": 1.9,
		"desc": "Assign a survivor here and they cover the whole approach.",
	},
	"stash": {
		"id": "stash", "name": "Supply Stash", "cost": {"wood": 25, "scrap": 8}, "hp": 220.0,
		"solid": true, "tier": 1, "threat": 2.0, "protect": true, "store": STASH_SLOTS,
		"desc": "The base pantry and armoury. 48 slots. Survivors and towers feed from this one.",
	},
	"chest": {
		"id": "chest", "name": "Wooden Chest", "cost": {"wood": 20, "sticks": 8}, "hp": 180.0,
		"solid": true, "tier": 1, "threat": 0.5, "protect": true, "store": 16,
		"desc": "Sixteen slots of overflow. Cheap — build as many as you need.",
	},
	"locker": {
		"id": "locker", "name": "Steel Locker", "cost": {"scrap": 34, "parts": 1}, "hp": 420.0,
		"solid": true, "tier": 1, "threat": 1.0, "protect": true, "store": 32,
		"desc": "Thirty-two slots, and it survives a raid that flattens a chest.",
	},
	"workbench": {
		"id": "workbench", "name": "Workbench", "cost": {"wood": 30, "scrap": 18}, "hp": 300.0,
		"solid": true, "tier": 1, "threat": 3.0, "protect": true,
		"desc": "Unlocks crafting while you stand near it. Upgradeable.",
	},
	"barricade": {
		"id": "barricade", "name": "Barricade", "cost": {"wood": 8}, "hp": 160.0,
		"solid": true, "tier": 1, "threat": 0.5, "wall": true,
		"desc": "Cheap, fast, and flimsy. Good for funnelling.",
	},
	"woodWall": {
		"id": "woodWall", "name": "Wood Wall", "cost": {"wood": 16}, "hp": 340.0,
		"solid": true, "tier": 1, "threat": 1.0, "wall": true,
		"desc": "The bread-and-butter wall.",
	},
	# Built from nothing but what the ground gives up: the wall you can raise
	# before you own a single tool that needs metal.
	"stoneWall": {
		"id": "stoneWall", "name": "Stone Wall", "cost": {"stone": 18, "sticks": 4}, "hp": 430.0,
		"solid": true, "tier": 1, "threat": 1.0, "wall": true,
		"desc": "Dry stone. No wood, no scrap — just what you carried up the hill.",
	},
	"reinforcedWall": {
		"id": "reinforcedWall", "name": "Reinforced Wall", "cost": {"wood": 12, "scrap": 22}, "hp": 920.0,
		"solid": true, "tier": 1, "threat": 1.5, "wall": true,
		"desc": "Wood and sheet metal. Buys you real time.",
	},
	"metalWall": {
		"id": "metalWall", "name": "Steel Wall", "cost": {"scrap": 45, "parts": 2}, "hp": 2100.0,
		"solid": true, "tier": 2, "threat": 2.0, "wall": true,
		"desc": "Brutes still get through — eventually.",
	},
	"gate": {
		"id": "gate", "name": "Gate", "cost": {"wood": 22, "scrap": 12}, "hp": 560.0,
		"solid": true, "tier": 1, "threat": 1.5, "gate": true,
		"desc": "Stand next to it and interact to open or close.",
	},
	"spike": {
		"id": "spike", "name": "Spike Trap", "cost": {"wood": 12, "scrap": 10}, "hp": 200.0,
		"solid": false, "tier": 1, "threat": 1.5, "trap": true, "trap_dmg": 26.0, "trap_cd": 0.55,
		"desc": "Shreds anything that walks over it. Wears out.",
	},
	"turret": {
		"id": "turret", "name": "Auto Turret", "cost": {"scrap": 50, "elec": 28, "parts": 6}, "hp": 340.0,
		"solid": true, "tier": 2, "threat": 5.0, "protect": true, "powered": true,
		"range": 330.0, "dmg": 22.0, "fire_cd": 0.28, "mag": 40, "reload": 2.2,
		"desc": "Needs a powered Generator within 260px. Eats 9mm from your stash.",
	},
	"floodlight": {
		"id": "floodlight", "name": "Floodlight", "cost": {"scrap": 22, "elec": 12}, "hp": 200.0,
		"solid": false, "tier": 2, "threat": 2.0, "powered": true, "light_radius": 260.0,
		"desc": "Pushes back the dark. Needs a powered Generator within 260px.",
	},
	# The only bench that is not a step up the workbench ladder. Chemistry is
	# different work, not harder metalwork — folding it into `bench` would
	# have made Workbench II hand out the suppressants for free, and the
	# suppressant chain is the spine of the whole theme.
	"chemStation": {
		"id": "chemStation", "name": "Chemistry Station", "cost": {"scrap": 30, "elec": 20, "parts": 4, "med": 8}, "hp": 260.0,
		"solid": true, "tier": 2, "threat": 3.0, "protect": true, "station": "chem",
		"desc": "Refines brain matter into something that does not fight back. Stand near it to craft.",
	},
	"generator": {
		"id": "generator", "name": "Generator", "cost": {"scrap": 38, "elec": 16}, "hp": 380.0,
		"solid": true, "tier": 2, "threat": 4.0, "protect": true, "power_radius": 260.0,
		"fuel_burn": 0.35, "fuel_max": 100.0,
		"desc": "Burns Fuel to power turrets nearby. Loud — raises Threat while running.",
	},
}

## Crafting is instant by design: the materials are the whole cost. `bench`
## is 0 for by hand, 1 for a workbench, 2 for the upgraded one. A `hammer`
## recipe is lifted to bench 1 by a carried Stone Hammer — the work you could
## plausibly do on a flat rock — and never any further, so the hammer can
## never produce a gun. `tool` is a flag the player must be carrying
## something with (a knife cuts cordage).
##
## Order matters only for the screen: hand tools first, because the bench
## costs wood and wood costs a hatchet.
const RECIPES := [
	{"id": "bandage", "name": "Bandage x2", "bench": 0, "cost": {"cloth": 4}, "give": {"item": "bandage", "n": 2}, "xp": 3},
	{"id": "axe", "name": "Hatchet", "bench": 0, "cost": {"sticks": 3, "stone": 3, "fiber": 4}, "give": {"weapon": "axe"}, "xp": 10},
	{"id": "knife", "name": "Stone Knife", "bench": 0, "cost": {"sticks": 2, "stone": 3, "fiber": 2}, "give": {"weapon": "knife"}, "xp": 8},
	{"id": "pick", "name": "Stone Pickaxe", "bench": 0, "cost": {"sticks": 4, "stone": 4, "fiber": 3}, "give": {"weapon": "pick"}, "xp": 12},
	{"id": "scythe", "name": "Scythe", "bench": 0, "cost": {"sticks": 5, "stone": 3, "fiber": 4}, "give": {"weapon": "scythe"}, "xp": 12},
	{"id": "hammer", "name": "Stone Hammer", "bench": 0, "cost": {"sticks": 3, "stone": 6, "fiber": 2}, "give": {"weapon": "hammer"}, "xp": 12},
	# Cordage: fiber becomes cloth, but only with a blade to cut it.
	{"id": "cordage", "name": "Cloth x4", "bench": 0, "tool": "knife", "cost": {"fiber": 10}, "give": {"res": {"cloth": 4}}, "xp": 4},
	# The first night's answer to "I cannot see", made of the two things the
	# ground is covered in. It burns itself up, so it is a thing you keep
	# remaking rather than a thing you own once.
	{"id": "torch", "name": "Torch", "bench": 0, "cost": {"sticks": 3, "fiber": 3}, "give": {"gear": "torch"}, "xp": 6},
	# Bench 0, like the tools: a bow is a stick and a string, and it has to be
	# reachable in the first ten minutes to be the quiet answer to a gun.
	{"id": "bow", "name": "Hunting Bow", "bench": 0, "cost": {"sticks": 8, "fiber": 12, "cloth": 2}, "give": {"weapon": "bow"}, "xp": 18},
	{"id": "arrow", "name": "Arrows x10", "bench": 0, "cost": {"sticks": 6, "stone": 3, "fiber": 2}, "give": {"res": {"arrow": 10}}, "xp": 3},
	{"id": "workGloves", "name": "Work Gloves", "bench": 0, "cost": {"cloth": 8}, "give": {"gear": "workGloves"}, "xp": 8},
	{"id": "denimPants", "name": "Work Trousers", "bench": 0, "cost": {"cloth": 14}, "give": {"gear": "denimPants"}, "xp": 10},

	{"id": "pipe", "name": "Steel Pipe", "bench": 1, "hammer": true, "cost": {"wood": 6, "scrap": 10}, "give": {"weapon": "pipe"}, "xp": 12},
	{"id": "ammoP", "name": "9mm x24", "bench": 1, "cost": {"scrap": 9, "parts": 1}, "give": {"res": {"ammoP": 24}}, "xp": 6},
	{"id": "medkit", "name": "Medkit", "bench": 1, "cost": {"med": 5, "cloth": 5}, "give": {"item": "medkit", "n": 1}, "xp": 8},
	# Processing raw tissue is the first thing a base does for you that your
	# hands cannot: three times the suppression, none of the nausea.
	{"id": "serum", "name": "Stabilized Neural Serum", "bench": 1, "cost": {"brainRaw": 3, "med": 2, "cloth": 1}, "give": {"item": "serum", "n": 1}, "xp": 10},
	# Food is bench work, not chemistry: a fire and a pot. Both of these are
	# buffs with a clock on them and neither is ever required.
	{"id": "jerky", "name": "Dried Meat x2", "bench": 1, "hammer": true, "cost": {"rations": 4, "fiber": 2}, "give": {"item": "jerky", "n": 2}, "xp": 4},
	{"id": "hotMeal", "name": "Hot Meal", "bench": 1, "cost": {"rations": 3, "water": 1, "wood": 2}, "give": {"item": "hotMeal", "n": 1}, "xp": 6},
	{"id": "machete", "name": "Machete", "bench": 1, "cost": {"scrap": 24, "parts": 1}, "give": {"weapon": "machete"}, "xp": 25},
	# The metal tool tier: the workbench costs wood and wood costs a Hatchet,
	# so these sit exactly one step past the stone tools that got you here.
	{"id": "fireaxe", "name": "Fire Axe", "bench": 1, "cost": {"wood": 8, "scrap": 20, "parts": 2}, "give": {"weapon": "fireaxe"}, "xp": 22},
	{"id": "steelpick", "name": "Steel Pickaxe", "bench": 1, "cost": {"wood": 6, "scrap": 26, "parts": 3}, "give": {"weapon": "steelpick"}, "xp": 24},
	{"id": "pistol", "name": "M9 Pistol", "bench": 1, "cost": {"scrap": 28, "parts": 4}, "give": {"weapon": "pistol"}, "xp": 35},
	{"id": "lightVest", "name": "Padded Vest", "bench": 1, "cost": {"cloth": 22, "scrap": 12}, "give": {"gear": "lightVest"}, "xp": 25},
	{"id": "workBoots", "name": "Work Boots", "bench": 1, "cost": {"cloth": 10, "scrap": 6}, "give": {"gear": "workBoots"}, "xp": 12},
	{"id": "hardHat", "name": "Hard Hat", "bench": 1, "cost": {"scrap": 14}, "give": {"gear": "hardHat"}, "xp": 14},
	{"id": "paddedLegs", "name": "Padded Leggings", "bench": 1, "cost": {"cloth": 24, "scrap": 10}, "give": {"gear": "paddedLegs"}, "xp": 26},
	{"id": "ammoS", "name": "Shells x14", "bench": 1, "cost": {"scrap": 12, "parts": 1}, "give": {"res": {"ammoS": 14}}, "xp": 7},
	{"id": "lockpick", "name": "Lockpicks x3", "bench": 1, "hammer": true, "cost": {"scrap": 8, "parts": 1}, "give": {"item": "lockpick", "n": 3}, "xp": 6},
	{"id": "rationPack", "name": "Ration Pack x8", "bench": 1, "hammer": true, "cost": {"med": 2, "cloth": 3}, "give": {"res": {"rations": 8}}, "xp": 5},
	{"id": "fuel", "name": "Fuel x25", "bench": 1, "cost": {"scrap": 10, "elec": 4}, "give": {"res": {"fuel": 25}}, "xp": 6},
	# A battery is findable long before it is craftable — parts bins, desks,
	# glove boxes — so the flashlight is something you scavenge your way into
	# rather than a bench unlock.
	{"id": "battery", "name": "Batteries x2", "bench": 1, "cost": {"scrap": 6, "elec": 5}, "give": {"res": {"battery": 2}}, "xp": 6},
	{"id": "flashlight", "name": "Flashlight", "bench": 1, "cost": {"scrap": 10, "elec": 6, "parts": 1}, "give": {"gear": "flashlight"}, "xp": 18},

	{"id": "sledge", "name": "Sledgehammer", "bench": 2, "cost": {"wood": 18, "scrap": 38, "parts": 2}, "give": {"weapon": "sledge"}, "xp": 45},
	{"id": "smg", "name": "Scrap SMG", "bench": 2, "cost": {"scrap": 48, "parts": 8, "elec": 10}, "give": {"weapon": "smg"}, "xp": 60},
	{"id": "shotgun", "name": "Pump Shotgun", "bench": 2, "cost": {"scrap": 44, "parts": 6, "wood": 12}, "give": {"weapon": "shotgun"}, "xp": 60},
	{"id": "ammoR", "name": "Rifle Rounds x18", "bench": 2, "cost": {"scrap": 14, "parts": 2}, "give": {"res": {"ammoR": 18}}, "xp": 8},
	{"id": "rifle", "name": "Hunting Rifle", "bench": 2, "cost": {"scrap": 62, "parts": 12, "mil": 3}, "give": {"weapon": "rifle"}, "xp": 90},
	{"id": "heavyVest", "name": "Riot Armor", "bench": 2, "cost": {"scrap": 46, "cloth": 20, "mil": 4}, "give": {"gear": "heavyVest"}, "xp": 70},
	{"id": "carbine", "name": "Military Carbine", "bench": 2, "cost": {"scrap": 85, "parts": 18, "mil": 14, "elec": 12}, "give": {"weapon": "carbine"}, "xp": 150},
	{"id": "milVest", "name": "Plate Carrier", "bench": 2, "cost": {"scrap": 40, "mil": 12, "cloth": 15}, "give": {"gear": "milVest"}, "xp": 120},

	# The chemistry. `station` is a *different* gate to `bench`: standing at a
	# Chemistry Station is what unlocks these, and no amount of workbench
	# upgrading ever will. `bench` stays 0 for exactly that reason — the two
	# gates are independent, and reading `bench: 2` here would suggest the
	# ladder had anything to do with it.
	{"id": "suppressant", "name": "Refined Suppressant", "bench": 0, "station": "chem",
		"cost": {"brainRaw": 6, "brainMut": 1, "med": 4, "elec": 2}, "give": {"item": "suppressant", "n": 1}, "xp": 30},
	{"id": "experimental", "name": "Experimental Suppressant", "bench": 0, "station": "chem",
		"cost": {"brainMut": 2, "brainSpec": 1, "med": 6, "mil": 2}, "give": {"item": "experimental", "n": 1}, "xp": 60},
]

const BUILD_ORDER := [
	"woodWall", "stoneWall", "barricade", "reinforcedWall", "metalWall", "gate", "spike",
	"workbench", "chemStation", "stash", "chest", "locker", "bedroll", "bunk", "watchtower",
	"generator", "turret", "floodlight",
]

## What the survivor on a Watchtower is shooting. Bought once for the whole
## base, then chosen per tower, so two towers can answer the same approach
## differently. The axis is noise against effect: arrows are free, weak and
## almost silent; the cannon flattens a group and brings the district down on
## you. `dmg`, `cd` and `range` multiply the survivor's own numbers, so a
## levelled crew is better with every armament rather than with one.
##
## Posting a survivor is Phase 4. The table is here because the tower, its
## cost and its choice of armament are Phase 3.
const ARMAMENTS := {
	"arrows": {
		"id": "arrows", "name": "Arrows", "order": 0, "cost": {},
		"dmg": 1.0, "cd": 1.25, "range": 480.0, "noise": 90.0, "ammo": {"arrow": 1},
		"speed": 780.0, "life": 0.85, "knock": 60.0, "pierce": 0, "color": "#c8a878",
		"desc": "Quiet, cheap, and weak. Nothing hears a tower shooting arrows.",
	},
	"firearrows": {
		"id": "firearrows", "name": "Fire Arrows", "order": 1,
		"cost": {"wood": 20, "cloth": 20, "fuel": 30, "parts": 2},
		"dmg": 0.75, "cd": 1.45, "range": 480.0, "noise": 120.0, "ammo": {"arrow": 1, "fuel": 1},
		"speed": 720.0, "life": 0.85, "knock": 60.0, "pierce": 0, "color": "#ff9a3a", "burns": true,
		"desc": "Sets what it hits alight, and fire spreads. Watch your treeline.",
	},
	"sniper": {
		"id": "sniper", "name": "Sniper Rifle", "order": 2,
		"cost": {"scrap": 70, "parts": 12, "mil": 6},
		"dmg": 1.9, "cd": 1.7, "range": 520.0, "noise": 700.0, "ammo": {"ammoR": 1},
		"speed": 1700.0, "life": 0.55, "knock": 110.0, "pierce": 1, "color": "#e8f0c0",
		"desc": "One shot, one walker. Every district hears it.",
	},
	"cannon": {
		"id": "cannon", "name": "Scrap Cannon", "order": 3,
		"cost": {"scrap": 90, "parts": 8, "elec": 10},
		"dmg": 3.4, "cd": 3.2, "range": 420.0, "noise": 950.0, "ammo": {"scrap": 2},
		"speed": 900.0, "life": 0.5, "knock": 260.0, "pierce": 0, "color": "#ffd08a", "splash": 70.0,
		"desc": "Flattens a group. The loudest thing you can build.",
	},
}

## The one every base starts with, so a manned tower always does something.
const DEFAULT_ARMAMENT := "arrows"

# ---------------------------------------------------------------- survivors --

const SURVIVOR := {
	"r": 12.0,
	"base_hp": 90.0,
	"hp_per_level": 22.0,
	"base_dmg": 11.0,
	"dmg_per_level": 2.6,
	"fire_cd": 0.62,
	"range": 300.0,
	"speed": 118.0,
	"xp_per_level": 55.0,
	"max_level": 10,
	"guard_radius": 190.0,   # how far from their post they will roam
	"revive_time": 8.0,      # downed -> dead if nobody helps
	"upkeep_per_min": 1.0,   # Rations eaten per survivor per minute
	"upkeep_every": 10.0,    # how often the bill is presented
	"debt_cap": 5.0,         # a long trip away has to be recoverable
	"warn_every": 45.0,
	"hungry_speed": 0.75,
	"hungry_cd": 1.35,
	"revive_hp_frac": 0.45,
}

## How close a sniper must be to their tower to count as posted on it.
const POST_RADIUS := 52.0

## How many rescues are scattered across the world at generation.
const RESCUE_COUNT := 7
## Rescues are kept this far apart, so finding one is not finding all of them.
const RESCUE_SPACING := 700.0

## Names are cosmetic but they matter: a numbered unit is a resource, a named
## one is a person you would rather not lose.
const SURVIVOR_NAMES := [
	"Mira", "Cass", "Dev", "Rosa", "Tobin", "Junie", "Hal", "Ada",
	"Wes", "Nel", "Bram", "Ivy", "Otto", "Sona", "Rhett", "Pim",
]

const SURVIVOR_TINTS := ["#7a8fa8", "#8a7f6a", "#7f8a6a", "#8a6f7a"]

const JOBS := {
	"guard": {"id": "guard", "name": "Guard", "short": "GRD", "color": "#d9765a",
		"desc": "Holds the base and shoots what comes at it."},
	"sniper": {"id": "sniper", "name": "Sniper", "short": "SNP", "color": "#6fb0c4",
		"desc": "Posted on a Watchtower: far more range and damage, but tied to it.",
		"needs": "watchtower"},
	"scavenger": {"id": "scavenger", "name": "Scavenger", "short": "SCV", "color": "#e8c86a",
		"desc": "Makes supply runs and brings materials back to the stash."},
	"builder": {"id": "builder", "name": "Builder", "short": "BLD", "color": "#8fd07a",
		"desc": "Repairs damaged structures, during a raid and after it."},
}

const JOB_IDS := ["guard", "sniper", "scavenger", "builder"]

## Scavengers turn time into materials while you do something else. They are
## slower and less thorough than you are, which is the point.
const SCAVENGE := {
	"radius": 900.0,       # how far from the base they will range
	"reach": 68.0,         # a container's own tile is solid, so allow for it
	"search_time": 6.0,
	"give_up_after": 2.5,  # seconds of no progress before trying something else
	"deliver_range": 52.0,
	"empty_haul": {"scrap": 3},
}

## Builders are the difference, during a raid, between a wall that holds and
## one that does not.
const BUILDER := {
	"radius": 700.0,       # searched from the base, not from the builder
	"reach": 58.0,
	"give_up_after": 2.5,
	"repair_per_sec": 26.0,
	"cost_per_100": {"wood": 2, "scrap": 1},
}

## There is no pathfinding for survivors (invariant 6 is about enemies, and
## this is the same rule again): every walk to a thing has a give-up timer, and
## "no progress for `give_up_after`" drops the target and picks another.
const SURVIVOR_PROGRESS := 900.0    # squared-distance closed to count as progress

# ----------------------------------------------------------------- vehicles --

## Deliberately arcade: throttle, reverse, and steering that only bites when
## you are actually moving. Nobody wants to parallel-park during a horde.
const CAR := {
	"accel": 340.0,
	"reverse_accel": 180.0,
	"max_speed": 430.0,
	"max_reverse": 150.0,
	"brake": 520.0,
	"drag": 1.1,
	"steer": 2.5,             # radians/sec at speed
	"steer_at_speed": 170.0,  # speed at which steering is fully effective
	"r": 20.0,

	"max_hp": 420.0,
	"fuel_max": 60.0,
	"burn_per_sec": 0.55,     # idling
	"burn_per_speed": 0.004,  # plus this per unit of speed
	"trunk_cap": 400,      # units, not slots — a boot holds a haul by bulk
	"trunk_slots": 24,

	"ram_damage": 46.0,       # to an enemy you hit at speed
	"ram_self_damage": 3.0,
	"ram_speed": 60.0,        # below this you are nudging, not running over
	"crash_speed": 150.0,     # above this, hitting something hurts
	"crash_damage_per": 0.14,
	"noise_radius": 640.0,
	"noise_every": 0.5,
	"threat_per_sec": 0.5,
	"quiet_speed": 30.0,      # under this, an engine draws nothing

	"enter_range": 74.0,
	"exit_range": 34.0,
	"locked_chance": 0.62,
	## Most abandoned cars are close to empty; a full tank is a find.
	"full_tank_chance": 0.25,
	"pick_base_chance": 0.34, # before Perception
	"pick_per_perception": 0.07,
	"pick_min": 0.15,
	"pick_max": 0.92,
	"pick_time": 1.6,
	"hotwire_time": 3.2,
	## How far from a locked car its key may be hidden.
	"key_range": 520.0,
	"salvage_scrap": [14, 27],
	"salvage_parts_chance": 0.45,
}

# -------------------------------------------------------------- loot tables --

## Each entry is `{id, min, max, w}`. `id` is a resource, or a prefixed
## `weapon:` / `gear:` / `item:` id — the same grammar a ground pickup is
## decoded with, so the two can never drift apart.
##
## Every table reads true to the thing you are opening: a fridge holds food, a
## wardrobe holds clothes, a gun safe holds guns. That is what makes a
## building's exterior worth reading before you go in.
const LOOT := {
	"cabinet": [
		{"id": "item:cannedFood", "min": 1, "max": 2, "w": 16}, {"id": "item:candyBar", "min": 1, "max": 2, "w": 10},
		{"id": "rations", "min": 2, "max": 5, "w": 18}, {"id": "cloth", "min": 3, "max": 8, "w": 30},
		{"id": "wood", "min": 4, "max": 10, "w": 28}, {"id": "scrap", "min": 2, "max": 6, "w": 24},
		{"id": "med", "min": 1, "max": 2, "w": 10}, {"id": "item:bandage", "min": 1, "max": 2, "w": 8},
	],
	"kitchen": [
		# Food and drink: buffs, never a requirement (pillar 1). A kitchen is
		# where most of it is, which is also where most of it always was.
		{"id": "item:cannedFood", "min": 1, "max": 3, "w": 26}, {"id": "item:water", "min": 1, "max": 3, "w": 22},
		{"id": "item:coffee", "min": 1, "max": 2, "w": 12}, {"id": "item:booze", "min": 1, "max": 1, "w": 8},
		{"id": "rations", "min": 3, "max": 8, "w": 34}, {"id": "cloth", "min": 2, "max": 6, "w": 26},
		{"id": "scrap", "min": 3, "max": 8, "w": 30}, {"id": "med", "min": 1, "max": 3, "w": 14},
		{"id": "elec", "min": 1, "max": 2, "w": 10}, {"id": "item:bandage", "min": 1, "max": 1, "w": 10},
	],
	"toolbox": [
		{"id": "scrap", "min": 6, "max": 14, "w": 34}, {"id": "wood", "min": 8, "max": 18, "w": 30},
		{"id": "battery", "min": 1, "max": 2, "w": 12}, {"id": "parts", "min": 1, "max": 2, "w": 16},
		{"id": "elec", "min": 1, "max": 3, "w": 12},
		{"id": "weapon:pipe", "min": 1, "max": 1, "w": 6}, {"id": "weapon:axe", "min": 1, "max": 1, "w": 5},
	],
	"shelf": [
		{"id": "rations", "min": 4, "max": 10, "w": 32}, {"id": "cloth", "min": 4, "max": 10, "w": 28},
		{"id": "med", "min": 2, "max": 5, "w": 24}, {"id": "scrap", "min": 3, "max": 7, "w": 22},
		{"id": "item:bandage", "min": 1, "max": 3, "w": 16}, {"id": "elec", "min": 1, "max": 3, "w": 10},
	],
	"pharmacy": [
		{"id": "med", "min": 5, "max": 12, "w": 40}, {"id": "item:medkit", "min": 1, "max": 2, "w": 24},
		{"id": "item:bandage", "min": 2, "max": 4, "w": 24}, {"id": "cloth", "min": 3, "max": 7, "w": 12},
	],
	"electronics": [
		{"id": "elec", "min": 5, "max": 12, "w": 40}, {"id": "battery", "min": 1, "max": 4, "w": 22},
		{"id": "parts", "min": 1, "max": 3, "w": 24}, {"id": "scrap", "min": 6, "max": 14, "w": 26},
		{"id": "fuel", "min": 5, "max": 12, "w": 10},
	],
	"carTrunk": [
		{"id": "item:water", "min": 1, "max": 2, "w": 12}, {"id": "item:candyBar", "min": 1, "max": 2, "w": 8},
		{"id": "scrap", "min": 4, "max": 10, "w": 34}, {"id": "fuel", "min": 4, "max": 12, "w": 26},
		{"id": "battery", "min": 1, "max": 2, "w": 14}, {"id": "parts", "min": 1, "max": 1, "w": 14},
		{"id": "cloth", "min": 2, "max": 5, "w": 16}, {"id": "elec", "min": 1, "max": 2, "w": 10},
	],
	"policeLocker": [
		{"id": "ammoP", "min": 14, "max": 30, "w": 30}, {"id": "ammoS", "min": 6, "max": 14, "w": 20},
		{"id": "parts", "min": 2, "max": 4, "w": 16}, {"id": "gear:lightVest", "min": 1, "max": 1, "w": 8},
		{"id": "gear:heavyVest", "min": 1, "max": 1, "w": 5}, {"id": "med", "min": 2, "max": 5, "w": 10},
		{"id": "gear:riotHelm", "min": 1, "max": 1, "w": 7}, {"id": "gear:tacGloves", "min": 1, "max": 1, "w": 7},
		{"id": "gear:combatBoots", "min": 1, "max": 1, "w": 6}, {"id": "gear:paddedLegs", "min": 1, "max": 1, "w": 6},
	],
	"gunSafe": [
		{"id": "weapon:pistol", "min": 1, "max": 1, "w": 22}, {"id": "weapon:shotgun", "min": 1, "max": 1, "w": 16},
		{"id": "weapon:rifle", "min": 1, "max": 1, "w": 8}, {"id": "ammoP", "min": 20, "max": 40, "w": 22},
		{"id": "ammoS", "min": 10, "max": 20, "w": 18}, {"id": "parts", "min": 3, "max": 6, "w": 14},
	],
	"militaryCrate": [
		{"id": "item:mre", "min": 1, "max": 3, "w": 20}, {"id": "item:water", "min": 1, "max": 3, "w": 12},
		{"id": "rations", "min": 6, "max": 14, "w": 14}, {"id": "mil", "min": 4, "max": 10, "w": 32},
		{"id": "ammoR", "min": 12, "max": 26, "w": 24}, {"id": "parts", "min": 3, "max": 7, "w": 18},
		{"id": "elec", "min": 5, "max": 12, "w": 12}, {"id": "weapon:carbine", "min": 1, "max": 1, "w": 4},
		{"id": "gear:milVest", "min": 1, "max": 1, "w": 5}, {"id": "item:medkit", "min": 1, "max": 2, "w": 5},
	],
	"hospitalCrate": [
		{"id": "item:water", "min": 2, "max": 5, "w": 14},
		{"id": "rations", "min": 3, "max": 8, "w": 12}, {"id": "med", "min": 8, "max": 16, "w": 36},
		{"id": "item:medkit", "min": 1, "max": 3, "w": 26}, {"id": "elec", "min": 3, "max": 8, "w": 16},
		{"id": "parts", "min": 1, "max": 3, "w": 12}, {"id": "mil", "min": 1, "max": 3, "w": 10},
	],
	# What a person was carrying. Not a container — `ENEMIES.loot_table` names
	# these, so a body rolls the same weighted table a cupboard does and there
	# is one rolling function in the game rather than two.
	"raiderBody": [
		{"id": "ammoP", "min": 6, "max": 16, "w": 26}, {"id": "ammoR", "min": 4, "max": 12, "w": 16},
		{"id": "scrap", "min": 2, "max": 6, "w": 18}, {"id": "med", "min": 1, "max": 3, "w": 16},
		{"id": "item:bandage", "min": 1, "max": 2, "w": 16}, {"id": "item:cannedFood", "min": 1, "max": 2, "w": 14},
		{"id": "item:water", "min": 1, "max": 2, "w": 12}, {"id": "parts", "min": 1, "max": 2, "w": 10},
		{"id": "item:booze", "min": 1, "max": 1, "w": 8}, {"id": "weapon:pistol", "min": 1, "max": 1, "w": 4},
	],
	"enforcerBody": [
		{"id": "ammoS", "min": 6, "max": 14, "w": 30}, {"id": "mil", "min": 1, "max": 4, "w": 18},
		{"id": "parts", "min": 2, "max": 4, "w": 18}, {"id": "item:medkit", "min": 1, "max": 1, "w": 12},
		{"id": "gear:heavyVest", "min": 1, "max": 1, "w": 5}, {"id": "gear:riotHelm", "min": 1, "max": 1, "w": 7},
		{"id": "weapon:shotgun", "min": 1, "max": 1, "w": 6}, {"id": "item:mre", "min": 1, "max": 2, "w": 10},
	],
	"fuelPump": [{"id": "fuel", "min": 12, "max": 26, "w": 100}],
	"fuelDrum": [{"id": "fuel", "min": 8, "max": 18, "w": 70}, {"id": "scrap", "min": 2, "max": 6, "w": 30}],
	"logPile": [
		{"id": "wood", "min": 12, "max": 24, "w": 64}, {"id": "arrow", "min": 4, "max": 10, "w": 8},
		{"id": "scrap", "min": 1, "max": 3, "w": 14}, {"id": "cloth", "min": 1, "max": 3, "w": 12},
		{"id": "parts", "min": 1, "max": 1, "w": 10},
	],
	"crate": [
		{"id": "wood", "min": 8, "max": 18, "w": 30}, {"id": "scrap", "min": 8, "max": 18, "w": 30},
		{"id": "elec", "min": 2, "max": 6, "w": 16}, {"id": "parts", "min": 1, "max": 3, "w": 12},
		{"id": "cloth", "min": 4, "max": 10, "w": 12},
	],
	"bookshelf": [
		{"id": "cloth", "min": 3, "max": 8, "w": 34},      # paper and dust jackets
		{"id": "elec", "min": 1, "max": 3, "w": 16},       # an old radio, a calculator
		{"id": "rations", "min": 1, "max": 3, "w": 14},    # someone's hidden snacks
		{"id": "med", "min": 1, "max": 2, "w": 12}, {"id": "parts", "min": 1, "max": 1, "w": 8},
		{"id": "item:bandage", "min": 1, "max": 2, "w": 16},
	],
	"dresser": [
		{"id": "cloth", "min": 5, "max": 12, "w": 46}, {"id": "item:bandage", "min": 1, "max": 3, "w": 20},
		{"id": "med", "min": 1, "max": 3, "w": 14}, {"id": "scrap", "min": 1, "max": 4, "w": 12},
		{"id": "ammoP", "min": 3, "max": 8, "w": 8},       # a bedside pistol's spare rounds
	],
	"wardrobe": [
		{"id": "cloth", "min": 8, "max": 16, "w": 46}, {"id": "item:bandage", "min": 1, "max": 3, "w": 16},
		{"id": "gear:lightVest", "min": 1, "max": 1, "w": 5}, {"id": "gear:denimPants", "min": 1, "max": 1, "w": 12},
		{"id": "gear:workBoots", "min": 1, "max": 1, "w": 10}, {"id": "gear:hardHat", "min": 1, "max": 1, "w": 6},
		{"id": "gear:workGloves", "min": 1, "max": 1, "w": 10}, {"id": "scrap", "min": 1, "max": 3, "w": 10},
		{"id": "rations", "min": 1, "max": 3, "w": 8},
	],
	"desk": [
		{"id": "elec", "min": 2, "max": 6, "w": 34}, {"id": "battery", "min": 1, "max": 2, "w": 14},
		{"id": "parts", "min": 1, "max": 2, "w": 20}, {"id": "cloth", "min": 2, "max": 5, "w": 18},
		{"id": "scrap", "min": 2, "max": 6, "w": 16}, {"id": "ammoP", "min": 4, "max": 10, "w": 12},
	],
	"filing": [
		{"id": "cloth", "min": 4, "max": 10, "w": 34}, {"id": "battery", "min": 1, "max": 1, "w": 10},
		{"id": "elec", "min": 1, "max": 3, "w": 18}, {"id": "parts", "min": 1, "max": 2, "w": 16},
		{"id": "ammoP", "min": 5, "max": 12, "w": 18}, {"id": "med", "min": 1, "max": 3, "w": 14},
	],
	"fridge": [
		{"id": "item:water", "min": 2, "max": 4, "w": 30}, {"id": "item:jerky", "min": 1, "max": 3, "w": 22},
		{"id": "item:soda", "min": 1, "max": 4, "w": 26}, {"id": "item:cannedFood", "min": 1, "max": 2, "w": 18},
		{"id": "rations", "min": 6, "max": 14, "w": 58}, {"id": "med", "min": 1, "max": 3, "w": 20},
		{"id": "cloth", "min": 1, "max": 3, "w": 12}, {"id": "fuel", "min": 1, "max": 3, "w": 10},
	],
	"nightstand": [
		{"id": "med", "min": 2, "max": 5, "w": 30}, {"id": "battery", "min": 1, "max": 2, "w": 16},
		{"id": "item:bandage", "min": 1, "max": 2, "w": 22}, {"id": "ammoP", "min": 4, "max": 10, "w": 20},
		{"id": "cloth", "min": 1, "max": 4, "w": 16}, {"id": "elec", "min": 1, "max": 2, "w": 12},
	],
	"vanity": [
		{"id": "med", "min": 3, "max": 7, "w": 44}, {"id": "item:bandage", "min": 1, "max": 3, "w": 26},
		{"id": "cloth", "min": 2, "max": 6, "w": 22}, {"id": "item:medkit", "min": 1, "max": 1, "w": 8},
	],
	"footlocker": [
		{"id": "item:mre", "min": 1, "max": 2, "w": 14}, {"id": "item:booze", "min": 1, "max": 1, "w": 8},
		{"id": "mil", "min": 3, "max": 8, "w": 28}, {"id": "arrow", "min": 8, "max": 20, "w": 8},
		{"id": "ammoR", "min": 8, "max": 18, "w": 20}, {"id": "gear:milVest", "min": 1, "max": 1, "w": 6},
		{"id": "gear:milHelm", "min": 1, "max": 1, "w": 6}, {"id": "gear:armGuards", "min": 1, "max": 1, "w": 6},
		{"id": "gear:milGreaves", "min": 1, "max": 1, "w": 6}, {"id": "gear:milBoots", "min": 1, "max": 1, "w": 6},
		{"id": "parts", "min": 2, "max": 5, "w": 14}, {"id": "item:medkit", "min": 1, "max": 2, "w": 8},
		{"id": "rations", "min": 3, "max": 8, "w": 6},
	],
	"vending": [
		{"id": "item:soda", "min": 2, "max": 5, "w": 40}, {"id": "item:candyBar", "min": 2, "max": 6, "w": 44},
		{"id": "item:water", "min": 1, "max": 3, "w": 24},
		{"id": "rations", "min": 5, "max": 12, "w": 62}, {"id": "scrap", "min": 2, "max": 5, "w": 22},
		{"id": "elec", "min": 1, "max": 2, "w": 16},
	],
	"toolrack": [
		{"id": "parts", "min": 2, "max": 5, "w": 34}, {"id": "weapon:bow", "min": 1, "max": 1, "w": 6},
		{"id": "arrow", "min": 6, "max": 16, "w": 10}, {"id": "scrap", "min": 6, "max": 14, "w": 32},
		{"id": "wood", "min": 5, "max": 12, "w": 22}, {"id": "weapon:pipe", "min": 1, "max": 1, "w": 6},
		{"id": "weapon:machete", "min": 1, "max": 1, "w": 4}, {"id": "weapon:axe", "min": 1, "max": 1, "w": 8},
		{"id": "weapon:fireaxe", "min": 1, "max": 1, "w": 3},
	],
	"displaycase": [
		{"id": "elec", "min": 4, "max": 10, "w": 34}, {"id": "battery", "min": 1, "max": 3, "w": 16},
		{"id": "parts", "min": 2, "max": 5, "w": 26}, {"id": "weapon:pistol", "min": 1, "max": 1, "w": 10},
		{"id": "ammoP", "min": 10, "max": 22, "w": 18}, {"id": "scrap", "min": 3, "max": 8, "w": 14},
	],
}

# --------------------------------------------------------------- containers --

## Searchable furniture. `table` and `rolls` say what searching one gives up;
## the world generator only needs the kind to exist.
const CONTAINERS := {
	"cabinet":       {"table": "cabinet",       "rolls": [1, 2], "sprite": "cabinet",     "label": "Cabinet"},
	"kitchen":       {"table": "kitchen",       "rolls": [1, 2], "sprite": "cabinet",     "label": "Kitchen Unit"},
	"toolbox":       {"table": "toolbox",       "rolls": [1, 3], "sprite": "toolbox",     "label": "Toolbox"},
	"shelf":         {"table": "shelf",         "rolls": [1, 2], "sprite": "shelf",       "label": "Shelving"},
	"pharmacy":      {"table": "pharmacy",      "rolls": [2, 3], "sprite": "medcab",      "label": "Medicine Cabinet"},
	"electronics":   {"table": "electronics",   "rolls": [2, 3], "sprite": "crate",       "label": "Parts Bin"},
	"crate":         {"table": "crate",         "rolls": [1, 3], "sprite": "crate",       "label": "Supply Crate"},
	"safe":          {"table": "gunSafe",       "rolls": [2, 3], "sprite": "safe",        "label": "Floor Safe"},
	"locker":        {"table": "dresser",       "rolls": [1, 2], "sprite": "locker",      "label": "Staff Locker"},
	"medcab":        {"table": "vanity",        "rolls": [1, 2], "sprite": "medcab",      "label": "Medicine Cabinet"},
	"carTrunk":      {"table": "carTrunk",      "rolls": [1, 2], "sprite": "trunk",       "label": "Car Trunk"},
	"policeLocker":  {"table": "policeLocker",  "rolls": [2, 3], "sprite": "locker",      "label": "Police Locker"},
	"gunSafe":       {"table": "gunSafe",       "rolls": [2, 3], "sprite": "safe",        "label": "Gun Safe"},
	"militaryCrate": {"table": "militaryCrate", "rolls": [3, 4], "sprite": "milcrate",    "label": "Military Crate"},
	"hospitalCrate": {"table": "hospitalCrate", "rolls": [2, 4], "sprite": "medcab",      "label": "Supply Cabinet"},
	"fuelPump":      {"table": "fuelPump",      "rolls": [1, 2], "sprite": "pump",        "label": "Fuel Pump"},
	"fuelDrum":      {"table": "fuelDrum",      "rolls": [1, 2], "sprite": "drum",        "label": "Fuel Drum"},
	"logPile":       {"table": "logPile",       "rolls": [2, 3], "sprite": "logs",        "label": "Log Pile"},
	"bookshelf":     {"table": "bookshelf",     "rolls": [1, 2], "sprite": "bookshelf",   "label": "Bookshelf"},
	"dresser":       {"table": "dresser",       "rolls": [1, 2], "sprite": "dresser",     "label": "Dresser"},
	"wardrobe":      {"table": "wardrobe",      "rolls": [1, 3], "sprite": "wardrobe",    "label": "Wardrobe"},
	"desk":          {"table": "desk",          "rolls": [1, 2], "sprite": "desk",        "label": "Desk"},
	"filing":        {"table": "filing",        "rolls": [1, 3], "sprite": "filing",      "label": "Filing Cabinet"},
	"fridge":        {"table": "fridge",        "rolls": [1, 2], "sprite": "fridge",      "label": "Refrigerator"},
	"nightstand":    {"table": "nightstand",    "rolls": [1, 1], "sprite": "nightstand",  "label": "Nightstand"},
	"vanity":        {"table": "vanity",        "rolls": [1, 2], "sprite": "vanity",      "label": "Bathroom Vanity"},
	"footlocker":    {"table": "footlocker",    "rolls": [2, 3], "sprite": "footlocker",  "label": "Footlocker"},
	"vending":       {"table": "vending",       "rolls": [2, 3], "sprite": "vending",     "label": "Vending Machine"},
	"toolrack":      {"table": "toolrack",      "rolls": [1, 3], "sprite": "toolrack",    "label": "Tool Rack"},
	"displaycase":   {"table": "displaycase",   "rolls": [2, 3], "sprite": "displaycase", "label": "Display Case"},
}

## What furnishes each kind of building, as [kind, weight] picks. A house
## fills with wardrobes and a precinct with filing cabinets, so a building's
## exterior tells you what is worth searching inside.
const FURNISHING := {
	"house": [
		["cabinet", 12], ["dresser", 14], ["wardrobe", 12], ["bookshelf", 12],
		["nightstand", 12], ["fridge", 9], ["kitchen", 9], ["vanity", 8],
		["desk", 6], ["toolbox", 4], ["shelf", 4],
	],
	"store": [
		["shelf", 26], ["vending", 14], ["displaycase", 10], ["fridge", 12],
		["kitchen", 8], ["cabinet", 8], ["filing", 6], ["pharmacy", 8], ["desk", 6],
	],
	"hardware": [
		["toolrack", 24], ["toolbox", 22], ["shelf", 18], ["crate", 14],
		["displaycase", 8], ["desk", 6], ["filing", 4],
	],
	"pawn": [
		["displaycase", 30], ["electronics", 24], ["shelf", 14], ["desk", 12],
		["filing", 8], ["safe", 6],
	],
	"police": [
		["policeLocker", 24], ["filing", 20], ["locker", 14], ["desk", 14],
		["gunSafe", 8], ["vending", 6], ["shelf", 6], ["footlocker", 6],
	],
	"hospital": [
		["pharmacy", 24], ["hospitalCrate", 20], ["medcab", 16], ["vanity", 10],
		["filing", 8], ["desk", 8], ["vending", 6], ["fridge", 6], ["bookshelf", 4],
	],
	"industrial": [
		["electronics", 24], ["crate", 20], ["toolrack", 16], ["toolbox", 14],
		["filing", 8], ["desk", 8], ["shelf", 6],
	],
	"military": [
		["militaryCrate", 26], ["footlocker", 24], ["gunSafe", 10], ["filing", 8],
		["desk", 8], ["electronics", 8], ["vending", 4],
	],
	"barn": [
		["toolrack", 20], ["toolbox", 18], ["crate", 16], ["shelf", 12],
		["fuelDrum", 12], ["logPile", 10], ["cabinet", 6], ["kitchen", 6],
	],
	"farmstore": [
		["shelf", 22], ["toolrack", 16], ["crate", 14], ["vending", 10],
		["fuelDrum", 10], ["fridge", 8], ["cabinet", 8], ["toolbox", 8], ["desk", 4],
	],
	"cabin": [
		["cabinet", 14], ["bookshelf", 12], ["footlocker", 12], ["fridge", 10],
		["kitchen", 8], ["wardrobe", 8], ["nightstand", 8], ["toolbox", 8],
		["gunSafe", 7], ["shelf", 6],
	],
	"lumber": [
		["logPile", 30], ["toolrack", 16], ["toolbox", 14], ["crate", 12],
		["fuelDrum", 10], ["shelf", 6], ["desk", 6], ["cabinet", 6],
	],
	"junk": [
		["toolbox", 24], ["crate", 18], ["electronics", 16], ["toolrack", 12],
		["fuelDrum", 10], ["shelf", 8], ["filing", 6], ["desk", 6],
	],
	"apartment": [
		["dresser", 14], ["wardrobe", 12], ["nightstand", 12], ["bookshelf", 10],
		["fridge", 10], ["kitchen", 10], ["cabinet", 10], ["vanity", 8],
		["desk", 6], ["locker", 4], ["vending", 4],
	],
	"office": [
		["desk", 26], ["filing", 22], ["electronics", 12], ["vending", 10],
		["locker", 8], ["bookshelf", 8], ["cabinet", 8], ["shelf", 6],
	],
	"bank": [
		["safe", 22], ["filing", 20], ["desk", 18], ["displaycase", 10],
		["locker", 10], ["cabinet", 8], ["electronics", 6], ["vending", 6],
	],
	"mall": [
		["shelf", 20], ["displaycase", 16], ["vending", 14], ["wardrobe", 10],
		["pharmacy", 10], ["fridge", 8], ["kitchen", 8], ["electronics", 8], ["cabinet", 6],
	],
	"drugstore": [
		["pharmacy", 26], ["shelf", 24], ["medcab", 10], ["vending", 10],
		["fridge", 10], ["cabinet", 8], ["displaycase", 6], ["desk", 6],
	],
	"gunshop": [
		["displaycase", 30], ["gunSafe", 22], ["shelf", 14], ["toolrack", 12],
		["policeLocker", 8], ["footlocker", 8], ["desk", 6],
	],
}
