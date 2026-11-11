--!nonstrict
-- Every tuning number from the original STROOP page, kept in one place so the
-- Roblox build stays numerically identical to the web version.

local Config = {}

-- ====== COLORS - 9 total. `tint` is the pale backdrop version. ======
Config.COLORS = {
	{ name = "RED",    hex = "#e03131", tint = "#f0bcbc" },
	{ name = "CYAN",   hex = "#00FFFF", tint = "#bdefef" },
	{ name = "YELLOW", hex = "#FCF55F", tint = "#f3edb8" },
	{ name = "GREEN",  hex = "#2f9e44", tint = "#b3ddbf" },
	{ name = "BLUE",   hex = "#1c3faa", tint = "#b8c4e8" },
	{ name = "PURPLE", hex = "#862e9c", tint = "#d3b6e0" },
	{ name = "PINK",   hex = "#FFB6C1", tint = "#f6dbe0" },
	{ name = "BLACK",  hex = "#14161c", tint = "#b9b9be" },
	{ name = "WHITE",  hex = "#ffffff", tint = "#eeeee9" },
}

Config.BY_NAME = {}
for _, c in ipairs(Config.COLORS) do
	Config.BY_NAME[c.name] = c
end

-- Some tints read as the same colour as another ink - red's pale tint is
-- pink to the eye - so a pink word must rule those out too, not just its own.
Config.TINT_CLASHES = {
	PINK = { "PINK", "RED" },
	RED = { "RED", "PINK" },
}

-- ====== stage 1-3 timing / progression ======
Config.BASE_TIME = 3.300
Config.TIME_DECREMENT = 0.070
Config.STAGE3_DECREMENT = 0.050 -- stage 3 resets to BASE_TIME then decays slower
Config.MIN_TIME = 1.200
Config.LIVES_START = 3 -- solo only
Config.SOLO_STAGE2_AT = 5
Config.SOLO_STAGE3_AT = 12
Config.SOLO_STAGE4_AT = Config.SOLO_STAGE3_AT + 10 -- 10 correct stage 3 answers -> boss
Config.ROUND_GRACE = 1.0
Config.REVEAL_DELAY = 1.4 -- normal between-round gap
Config.INTRO_DELAY = 5.2 -- longer gap on round 1 to fit the full transition + READY/SET/GO

-- ====== stage 4 - the boss ======
Config.BOSS_START_TIME = 4.0
Config.BOSS_STEP = 0.2
Config.BOSS_MIN_TIME = 1.2
Config.BOSS_MAX_HP = 100
Config.BOSS_HIT_SCALED = 12
Config.BOSS_HIT_BASE = 6
Config.BOSS_ALT_HIT = 25
Config.BOSS_LIVES = 4
Config.BOSS_FLASH = 2.0
Config.BOSS_REST = 2.0
Config.BOSS_FADE_AT = 0.75
Config.BOSS_VOICE_GAP = 0.8
Config.SPOT_RADIUS = 500 -- widened 100px from the original 400

Config.BOSS_LAYOUTS = {
	"orbit", "pulse", "fall", "drift", "dvd",
	"alternate", "decoy", "spotlight", "blink", "ribbon",
}

-- loudly-crying, laugh-cry, clown
Config.REACTIONS = { utf8.char(0x1F62D), utf8.char(0x1F602), utf8.char(0x1F921) }

-- DECOY challenge only - non-colour words mixed in with the nine colours.
Config.DECOY_WORDS = { "STOP PANICKING", "READY", "BLURRED", "BLAND", "PICK", "GREAT" }

-- ALTERNATE challenge only - standard HTML colour values.
Config.ALT_COLORS = {
	{ name = "MAGENTA",    hex = "#FF00FF" },
	{ name = "CHARTREUSE", hex = "#7FFF00" },
	{ name = "GRAY",       hex = "#808080" },
	{ name = "MAROON",     hex = "#800000" },
	{ name = "TEAL",       hex = "#008080" },
	{ name = "INDIGO",     hex = "#4B0082" },
	{ name = "TURQUOISE",  hex = "#40E0D0" },
	{ name = "SALMON",     hex = "#FA8072" },
	{ name = "BEIGE",      hex = "#F5F5DC" },
}

-- The ink colours themselves double as backdrop / fill options in stage 4,
-- with a deeper yellow standing in for the too-pale one.
Config.DARK_YELLOW = "#c9a227"

-- ====== theme ======
Config.THEME = {
	dark = {
		pageBg = "#12141c",
		ink = "#eef0f6",
		dim = "#7b8096",
		panel = "#1b1e29",
		panelLine = "#2a2e3c",
	},
	light = {
		pageBg = "#dcdad3",
		ink = "#16181d",
		dim = "#5f636d",
		panel = "#ffffff",
		panelLine = "#bcb8ae",
	},
	ok = "#2f9e44",
	bad = "#e03131",
	overlayBg = "#0a0b10",
}

-- ====== multiplayer ======
Config.LOBBY_CODE_CHARS = "ABCDEFGHJKMNPQRSTUVWXYZ23456789"
Config.LOBBY_CODE_LEN = 5
Config.MAX_NAME = 16
Config.HOST_TICK = 0.2 -- server round-resolution cadence

return Config
