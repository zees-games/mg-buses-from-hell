extends RefCounted

## A generated grid, because a flat colour has no speed in it.

## Pixels per tile. One tile is one metre in world space, so this is also the
## resolution a player can resolve the ground at.
const TILE := 128

## How much darker an alternate square is. Small enough not to read as a pattern up
## close, large enough to survive being averaged away.
const CHECKER := 0.94

## How much darker a grid line is.
const LINE := 0.72

## Cached per colour, because every wall segment asks for the same one and building
## 48 identical 128x128 images is 48 times the work for one texture.
static var _cache: Dictionary = {}


## Drops the cached textures; a suite calls it before quitting so they are not reported as leaks.
static func clear_cache() -> void:
	_cache.clear()


## A one-metre grid tinted toward [param colour].
static func grid(colour: Color) -> ImageTexture:
	var key := colour.to_html(false)

	if _cache.has(key):
		return _cache[key]

	var image := Image.create_empty(TILE, TILE, true, Image.FORMAT_RGB8)

	for y in range(TILE):
		for x in range(TILE):
			var shade := 1.0

			# The checker: two squares per tile each way, so half a metre a square.
			var half := TILE / 2
			if (x < half) != (y < half):
				shade *= CHECKER

			# The lines, on the tile boundary. Two pixels, because one pixel of ink on
			# a 128-pixel square is 0.8% of the image and a mipmap eats it by the
			# second level.
			if x < 2 or y < 2:
				shade *= LINE

			image.set_pixel(
				x, y, Color(colour.r * shade, colour.g * shade, colour.b * shade)
			)

	image.generate_mipmaps()

	var texture := ImageTexture.create_from_image(image)
	_cache[key] = texture
	return texture


## The material every piece of the bowl is drawn with.
static func surface(colour: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = grid(colour)
	# [b]World-space triplanar, so one square is one metre on every surface whatever its size.[/b] Per-
	# mesh UVs would make a square on the 92-metre floor a different size from a square on a 1-metre
	# crate, and the whole point of the pattern is that its size is known.
	mat.uv1_triplanar = true
	mat.uv1_scale = Vector3.ONE
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	mat.roughness = 0.95
	return mat
