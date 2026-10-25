#!/bin/sh
# Build Kobo Deluxe for the browser (WebAssembly) with Emscripten.
#
# The game is written against SDL 1.2. Rather than Emscripten's own (very
# incomplete) SDL 1.2 emulation, we use sdl12-compat, which implements the
# SDL 1.2 API on top of SDL2, which has a mature Emscripten backend.
#
# sdl12-compat normally dlopen()s SDL2 and both libraries export functions
# with the same names (SDL_Init etc), so here SDL2 is built statically with
# every public symbol renamed to SDL2R_*, and sdl12-compat finds them through
# a static lookup table (sdl2_symtab.c) instead of dlsym().
#
# Usage: source /path/to/emsdk/emsdk_env.sh, then run emscripten/build.sh
# from the top of the source tree. Output ends up in build-web/out/.

set -e

SDL2_TAG=release-2.32.10
SDL12COMPAT_COMMIT=476f41c6159a58e72a1000501c56ed5bea288a0f
STB_COMMIT=003501f6d7a8668ce8b6d875e34dd97ad0d5d5b5

SRCDIR="$(cd "$(dirname "$0")/.." && pwd)"
EMDIR="${SRCDIR}/emscripten"
WORK="${SRCDIR}/build-web"
DEPS="${WORK}/deps"
OUT="${WORK}/out"
JOBS="${JOBS:-$(nproc 2>/dev/null || echo 4)}"

command -v emcc >/dev/null || { echo "emcc not found; source emsdk_env.sh first" >&2; exit 1; }

mkdir -p "${DEPS}" "${OUT}"

#--- Fetch dependencies -------------------------------------------------------
if [ ! -d "${DEPS}/SDL2" ]; then
	git clone -q --depth 1 -b "${SDL2_TAG}" https://github.com/libsdl-org/SDL.git "${DEPS}/SDL2"
	(cd "${DEPS}/SDL2" && git apply "${EMDIR}/sdl2.patch")
fi
if [ ! -d "${DEPS}/sdl12-compat" ]; then
	git clone -q https://github.com/libsdl-org/sdl12-compat.git "${DEPS}/sdl12-compat"
	(cd "${DEPS}/sdl12-compat" && git checkout -q "${SDL12COMPAT_COMMIT}" &&
			git apply "${EMDIR}/sdl12-compat.patch")
fi
if [ ! -f "${DEPS}/stb/stb_image.h" ]; then
	mkdir -p "${DEPS}/stb"
	curl -sSfL -o "${DEPS}/stb/stb_image.h" \
		"https://raw.githubusercontent.com/nothings/stb/${STB_COMMIT}/stb_image.h"
fi

#--- SDL2, with all public symbols renamed SDL_* -> SDL2R_* --------------------
RENAME="${DEPS}/sdl2_rename.h"
grep '^#define SDL_' "${DEPS}/SDL2/src/dynapi/SDL_dynapi_overrides.h" |
		awk '{ print "#define " $2 " SDL2R_" substr($2, 5) }' > "${RENAME}"
if [ ! -f "${DEPS}/sdl2-install/lib/libSDL2.a" ]; then
	mkdir -p "${DEPS}/sdl2-build"
	(cd "${DEPS}/sdl2-build" &&
		emcmake cmake "${DEPS}/SDL2" -DCMAKE_BUILD_TYPE=Release \
			-DSDL_SHARED=OFF -DSDL_STATIC=ON -DSDL_TEST=OFF \
			-DCMAKE_C_FLAGS="-include ${RENAME}" \
			-DCMAKE_INSTALL_PREFIX="${DEPS}/sdl2-install" &&
		make -j"${JOBS}" && make install)
fi
SDL2INC="${DEPS}/sdl2-install/include/SDL2"

#--- sdl12-compat (static) + SDL2 symbol table + IMG_Load() shim ---------------
SDL12INC="${DEPS}/sdl12-compat/include/SDL"
emcc -O2 -D_REENTRANT -I"${SDL2INC}" -I"${SDL12INC}" \
	-c "${DEPS}/sdl12-compat/src/SDL12_compat.c" -o "${DEPS}/SDL12_compat.o"
emcc -O2 -include "${RENAME}" -I"${SDL2INC}" -I"${DEPS}/sdl12-compat/src" \
	-c "${EMDIR}/sdl2_symtab.c" -o "${DEPS}/sdl2_symtab.o"
rm -f "${DEPS}/libSDL12.a"
emar rcs "${DEPS}/libSDL12.a" "${DEPS}/SDL12_compat.o" "${DEPS}/sdl2_symtab.o"
emcc -O2 -I"${DEPS}/stb" -I"${EMDIR}" -I"${SDL12INC}" \
	-c "${EMDIR}/img_shim.c" -o "${DEPS}/img_shim.o"

#--- Kobo Deluxe ---------------------------------------------------------------
mkdir -p "${WORK}/kobo"
(cd "${WORK}/kobo" &&
	emcmake cmake "${SRCDIR}" -DCMAKE_BUILD_TYPE=Release \
		-DCMAKE_INSTALL_PREFIX=/kobo \
		-DSDL_INCLUDE_DIR="${SDL12INC}" \
		-DSDL_LIBRARY="${DEPS}/libSDL12.a" \
		-DSDLIMAGE_INCLUDE_DIR="${EMDIR}" \
		-DSDLIMAGE_LIBRARY="${DEPS}/img_shim.o" \
		-DKOBO_EXTRA_LIBRARIES="${DEPS}/sdl2-install/lib/libSDL2.a" &&
	make -j"${JOBS}" kobodl)

# Final link: CMake's executable is a plain .js; relink with the web bits.
KOBOOBJ="${WORK}/kobo/src/CMakeFiles/kobodl.dir"
SHELL_HTML="${EMDIR}/shell.html"
SHELL_OPT=""
[ -f "${SHELL_HTML}" ] && SHELL_OPT="--shell-file ${SHELL_HTML}"
# KOBO_EMBED=1 puts the game data inside the .wasm instead of a separate .data
# file (for hosts that won't serve arbitrary file types)
DATA_OPT="--preload-file ${SRCDIR}/data@/kobo/share/kobodeluxe"
[ "${KOBO_EMBED}" = 1 ] && DATA_OPT="--embed-file ${SRCDIR}/data@/kobo/share/kobodeluxe"
PREJS_OPT=""
[ -f "${EMDIR}/pre.js" ] && PREJS_OPT="--pre-js ${EMDIR}/pre.js"
em++ -O2 $(find "${KOBOOBJ}" -name '*.o' | sort) \
	"${DEPS}/libSDL12.a" "${DEPS}/img_shim.o" \
	"${DEPS}/sdl2-install/lib/libSDL2.a" \
	-sASYNCIFY -sALLOW_MEMORY_GROWTH -sEXIT_RUNTIME=0 -lGL -lidbfs.js \
	-sENVIRONMENT=web -sEXPORTED_RUNTIME_METHODS=FS,IDBFS,callMain \
	${DATA_OPT} \
	${SHELL_OPT} ${PREJS_OPT} \
	-o "${OUT}/index.html"

echo "Built ${OUT}/index.html"
