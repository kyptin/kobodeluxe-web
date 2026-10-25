/* IMG_Load() for the Emscripten build, using stb_image instead of SDL_image. */
#define STB_IMAGE_IMPLEMENTATION
#define STBI_ONLY_PNG
#include "stb_image.h"
#include <string.h>
#include "SDL_image.h"

SDL_Surface *IMG_Load(const char *file)
{
	int w, h, n, y;
	unsigned char *pixels;
	SDL_Surface *s;
	if(!stbi_info(file, &w, &h, &n))
	{
		SDL_SetError("IMG_Load: %s: %s", file, stbi_failure_reason());
		return NULL;
	}
	/* Like SDL_image: RGB stays 24 bit, anything with alpha (or gray) becomes RGBA */
	n = (n == 3) ? 3 : 4;
	pixels = stbi_load(file, &w, &h, NULL, n);
	if(!pixels)
	{
		SDL_SetError("IMG_Load: %s: %s", file, stbi_failure_reason());
		return NULL;
	}
	s = SDL_CreateRGBSurface(SDL_SWSURFACE | (n == 4 ? SDL_SRCALPHA : 0),
			w, h, n * 8, 0x000000ff, 0x0000ff00, 0x00ff0000,
			n == 4 ? 0xff000000 : 0);
	if(s)
	{
		SDL_LockSurface(s);
		for(y = 0; y < h; ++y)
			memcpy((Uint8 *)s->pixels + y * s->pitch,
					pixels + y * w * n, w * n);
		SDL_UnlockSurface(s);
	}
	stbi_image_free(pixels);
	return s;
}
