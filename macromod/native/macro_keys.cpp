/* Farever Macros: reads whether a key is physically down, even when the game window is not focused.
 * It only answers "is this one key down right now" for keys the mod asks about; it installs no hook
 * and records nothing. https://learn.microsoft.com/windows/win32/api/winuser/nf-winuser-getasynckeystate
 */
#define WIN32_LEAN_AND_MEAN
#include <windows.h>

#ifndef _WIN64
#error Farever Macros requires Windows x64
#endif

static int key_down(int vk) {
    if (vk <= 0 || vk > 254) return 0;
    return (GetAsyncKeyState(vk) & 0x8000) ? 1 : 0;
}

// HashLink DEFINE_PRIM ABI: i = i32. No libhl dependency.
#define EXPORT extern "C" __declspec(dllexport)
EXPORT void *hlp_key_down(const char **signature) { *signature = "Pi_i"; return reinterpret_cast<void *>(&key_down); }
