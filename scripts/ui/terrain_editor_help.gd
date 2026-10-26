extends RefCounted
## Plain-language help for the map editor.

const HINTS: Dictionary = {
	"Apply trees": "Replant trees using this count and reload your saved tree scenes without rebuilding the map.",
	"terrain_template": "Choose a world shape or supplied heightmap, or import an image of your own.",
	"map_size.x": "Make the world wider from left to right without changing your window size.",
	"map_size.y": "Make the world taller from top to bottom without changing your window size.",
	"island_enabled": "Lower the edges toward the sea to surround your land with water when you press Generate.",
	"elevation": "Make hills and mountains taller or flatter when you press Generate, while keeping the same coastline.",
	"min_zoom": "Lower this number to let the wheel pull farther OUT, where 1 fits the world and 0.5 shows twice as much space.",
	"max_zoom": "Raise this number to let the wheel zoom farther IN, unless Closest view size is already stopping it.",
	"map_seed": "Use the same name or number with the same heightmap and size to make the same world again.",
	"closest_view_size": "Lower this number to show a smaller patch of ground at the closest zoom, such as 4 map units instead of 8.",
	"Farthest view": "Move the camera straight to your minimum zoom so you can check how far out it allows.",
	"Closest view": "Move the camera straight to the closest zoom allowed by Maximum zoom and Closest view size.",
	"Save terrain…": "Save the map you can currently see so you can load it again later.",
	"Load terrain…": "Open a saved map and replace the map you can currently see.",
	"Generate": "Build a new map from your chosen map settings and choose the remaining settings automatically.",
	"New seed": "Pick a new random seed and immediately build another map with your chosen heightmap and size.",
	"Import heightmap image…": "Choose an image with bright areas for high ground and dark areas for low ground, then press Generate.",
	"Export grayscale PNG…": "Save a black-and-white picture of the current map heights rather than a complete editable map.",
	"grayscale": "Show low ground as dark and high ground as bright so the heights are easier to see.",
	"preview": "Preview the current heights as a small picture where brighter areas are higher."
}

const DESCRIPTIONS: Dictionary = {
	"Noise": "A random island shaped by overlapping patterns of hills and valleys.",
	"Volcano": "A large volcanic mountain with smaller ridges around it.",
	"High Island": "A mountainous island with ridges and coastal lowlands.",
	"Low Island": "Low islands surrounded by shallow coastal water.",
	"Continents": "Large landmasses separated by ocean straits.",
	"Archipelago": "Many islands and broken ridges divided by channels.",
	"Atoll": "A low island and reef around shallow water.",
	"Mediterranean": "Land along the northern and southern edges around a central sea.",
	"Peninsula": "Land joined to one map edge and reaching out into the sea.",
	"Pangea": "One large connected landmass surrounded by water.",
	"Isthmus": "Two land areas joined by a narrow bridge of land.",
	"Shattered": "A broken world of scattered land, ridges and water.",
	"Taklamakan": "A broad inland basin enclosed by higher ground.",
	"Old World": "A large mainland with smaller nearby islands.",
	"Fractious": "Many irregular land areas separated by narrow waterways.",
	"World heightmap": "A supplied heightmap showing the whole Earth.",
	"Europe heightmap": "A supplied heightmap showing Europe and nearby land.",
	"Mediterranean heightmap": "A supplied heightmap showing the Mediterranean region."
}
