/* Static symbol table so sdl12-compat can find the (renamed) SDL2 functions
   without dlopen() on Emscripten. Compiled with -include sdl2_rename.h. */
#include <string.h>
#include "SDL.h"
#include "SDL_syswm.h"
typedef struct { const char *name; void *fn; } sdl2sym;
static const sdl2sym syms[] = {
#define SDL20_SYM(rc,fn,params,args,ret) { "SDL_" #fn, (void *)&SDL_##fn },
#include "SDL20_syms.h"
	{ NULL, NULL }
};
void *SDL12COMPAT_LookupSDL20Sym(const char *name)
{
	const sdl2sym *s;
	for (s = syms; s->name; ++s)
		if (strcmp(s->name, name) == 0)
			return s->fn;
	return NULL;
}
