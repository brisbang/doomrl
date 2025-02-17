# doomrl

DRL a.k.a. doomrl, a.k.a, D**m, the Roguelike, version 0.9.9.8
http://drl.chaosforge.org/

This release is dedicated to Jupiter Hell Classic, the newly announced commercial remake/expansion to DRL:

https://store.steampowered.com/app/3126530/Jupiter_Hell_Classic/

If you enjoy this Open Source release, please consider wishlisting and later buying Jupiter Hell Classic! Also, you might be interested in DRL's modern 3D spiritual successor, Jupiter Hell (yes, it's still turn-based :P):

https://store.steampowered.com/app/811320/Jupiter_Hell/

Parts of this codebase date back to 2002, please do not judge! :P

This FreePascal source code release is provided as is. You can try compiling it using the latest version of Lazarus ( http://www.lazarus-ide.org/ ). You will also need the FPC Valkyrie library ( https://github.com/ChaosForge/fpcvalkyrie/ ), version 0.9.0. You will also probably need the binary files of the full game downloadable from http://drl.chaosforge.org/ (in particular the sound, soundhq, music and mp3 folder contents, and the premade drl.wad and core.wad if you don't want to create it yourself).

Compilation instructions, short version:

1. Download DRL from http://drl.chaosforge.org/
2. Copy bin/mp3, bin/music, bin/sound, bin/soundhq from the DRL folders to the source tree bin folder
3. Download 64-bit Lazarus
4. Open src/makewad.lpi build, do not run
5. Run makewad.exe from the command line in the bin folder to generate drl.wad and core.wad (precompiled lua files)
6. Open src/drl.lpi, build and run
7. Enjoy

Lua makefile path (tested on Windows, might work on Linux):

1. Have lua 5.1 in your path
2. Have fpc bin directory in your path
3. From the root folder run lua5.1 makefile.lua
4. You can build packages by running "lua5.1 makefile.lua all" or lq or hq

Longer instructions to set up a Windows debug environment:
1. Download DRL source from http://drl.chaosforge.org/
2. Download the DRL binaries (if you haven't already)
3. Copy the following DLLs from the DRL binaries into bin:
  * SDL2.dll (true source: https://github.com/libsdl-org/SDL/releases/tag/release-2.32.0)
  * SDL_mixer.dll (true source: https://github.com/libsdl-org/SDL_mixer/releases/tag/release-2.6.3)
  * SDL_image.dll (true source: https://github.com/libsdl-org/SDL_image/releases/tag/release-2.8.5)
  * fmod64.dll (true source: www.fmod.com/download)
  * (if referencing v0.9.9.8 or less) mp3\* to data\drlhq\music
  * (if referencing v0.9.9.8 or less) wavhq\* to data\drlhq\sounds
  * (if referencing v0.9.9.9 or higher) data\drlhq\music\* to data\drlhq\music
  * (if referencing v0.9.9.9 or higher) data\drlhq\sounds\* to data\drlhq\sounds
4. Download fpcvalkyrie (to a folder at the same level as the DRL source) from https://github.com/ChaosForge/fpcvalkyrie/.
5. Ensure doomrl and fpcvalkyrie are on the same release branch (e.g. master or development)
6. Download lua 5.1 (e.g. 5.1.5) from https://sourceforge.net/projects/luabinaries/files/5.1.5/Tools%20Executables/. Unzip it.
7. Update system environment variables to place lua5.1 in your path
8. Download and install Lazarus 64-bit (the location will be referred to as %Lazarus location%)

Using Lazarus IDE
9. Open src/makewad.lpi (with Lazarus). Build. You should receive '...bin\makewad.exe: Success'
10. Start a command prompt and change to the bin folder. Run makewad.exe to generate the drl.wad and core.wad (precompiled lua files)
11. Open src/drl.lpi. Build. You should receive '...bin\drl.exe: Success'
12. Open up the Run\Run Parameters screen. Correct the working directory to point to your bin folder. Also note the Command Line Parameters, which might change the application's behaviour
13. Run

Using Visual Studio Code (1):
9. Open Visual Studio Code
10. Install FreePascal Toolkit
11. Add %Lazarus%\fpc\3.2.2\bin\x86_64-win64 to your path

Using Visual Studio Code (2) [Instructions appropriated from https://stephan-bester.medium.com/free-pascal-in-visual-studio-code-e1e0a240a430]
9. Open Visual Studio Code
9b. Add E:\lazarus\mingw\x86_64-win64\bin to your path
10. Install the OmniPascal extension
11. Manage (the cog)/Settings/User/Extensions/OmniPascal configuration
* Default Development Environment: FreePascal
* Free Pascal Source Path: %Lazarus location%\fpc\3.2.2\bin\x86_64-win64
* Lazbuild path: %Lazarus location%
12. In VSCode Explorer, open the DRL folder
13. In the status bar you'll see OmniPascal: Select project. Click and choose drl.lpi
14. Install the Native Debug extension
15. Run Terminal/Configure Tasks/Create tasks.json from Template (prob not required)
16. Download content from https://gist.github.com/stepbester/96e6310e7e94cd7c64b54f9efa38489f
17. Run Terminal/Run Task... and choose fpc: Create Build Folders
18. Run Run/Add Configuration... then choose GDB from the list
19. Change target to point to "./build/debug/drl"


Notes on Lua5.1 (from epyon)
v5.1 is compulsory. DoomRL references the dll by name, and the dynamic headers are written against 5.1. I don't even think it will work due to the changes in env-tables. DRL uses a few sophisticated Lua tricks. Initially the reason to keep being 5.1 compatible for both DRL and JH was due to LuaJIT compatibility, but I guess that point is moot now.

All code is (C) 2003-2024 Kornel Kisielewicz

Code is distributed under the GPL 2.0 license (see LICENSE file in this folder)

Original art and sprites (0.9.9.7) by Derek Yu, (C) 2003-2024, licensed under CC BY-SA 4.0. Modified version and additions (0.9.9.8+) by Łukasz Śliwiński, (C) 2024, licensed under CC BY-SA 4.0.

All art is distributed under the CC-BY-SA 4.0 license (see LICENSE file in the bin/graphics/ folder).

sincerely,
Kornel Kisielewicz 
ChaosForge