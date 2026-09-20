/*
 * Copyright (C) 2014 AITIAL Paris
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */


#include "gAppManager.h"
#include "gApp.h"

#ifdef __EMSCRIPTEN__
#include <emscripten/emscripten.h>
#endif


int main(int argc, char **argv) {
	int width = 1280, height = 720;
#ifdef __EMSCRIPTEN__
	// Start at the size of the page. Emscripten pins whatever size the engine
	// asks for onto the canvas element as an !important inline style, so a
	// desktop sized window would hang off the side of a phone screen until the
	// first resize landed. gCanvas keeps it in step after this.
	width = EM_ASM_INT({ return window.innerWidth; });
	height = EM_ASM_INT({ return window.innerHeight; });
#endif

	gStartEngine(new gApp(argc, argv), "Neon Dodger", G_WINDOWMODE_APP, width, height, G_SCREENSCALING_AUTO, 1280, 720);

	return 0;
}
