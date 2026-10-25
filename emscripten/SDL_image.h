/* Minimal SDL_image 1.2 replacement for the Emscripten build: IMG_Load only. */
#ifndef KOBO_SDL_IMAGE_SHIM_H
#define KOBO_SDL_IMAGE_SHIM_H
#include "SDL.h"
#ifdef __cplusplus
extern "C" {
#endif
SDL_Surface *IMG_Load(const char *file);
#define IMG_GetError SDL_GetError
#ifdef __cplusplus
}
#endif
#endif
