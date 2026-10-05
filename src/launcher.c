#ifndef UNICODE
#define UNICODE
#endif
#ifndef _UNICODE
#define _UNICODE
#endif
#include <windows.h>
#include <wchar.h>
#include <stdlib.h>

/* SPDX-License-Identifier: MIT
 * Keep GameHub's tracked process alive until the game bridge finishes. */
int WINAPI wWinMain(HINSTANCE instance, HINSTANCE previous, PWSTR args, int show)
{
    const wchar_t *kit = L"Z:\\sdcard\\Download\\Thor-Forever";
    wchar_t start[MAX_PATH], command[1024], token[80], begun[512], done[512], bridge[512];
    STARTUPINFOW si = {0};
    PROCESS_INFORMATION pi = {0};
    DWORD length, count;
    ULONGLONG deadline;
    HANDLE result;
    char buffer[32] = {0};
    char *end;
    unsigned long parsed;
    (void)instance; (void)previous; (void)args; (void)show;
    si.cb = sizeof(si);
    swprintf(bridge, 512, L"%ls\\installer\\entry.sh", kit);
    if (GetFileAttributesW(bridge) == INVALID_FILE_ATTRIBUTES) {
        MessageBoxW(NULL, L"Required files are missing. Extract the complete package into Download/Thor-Forever.", L"Thor Forever", MB_OK | MB_ICONERROR);
        return 2;
    }
    length = GetSystemDirectoryW(start, MAX_PATH);
    if (!length || length + 11 >= MAX_PATH) return 3;
    wcscat(start, L"\\start.exe");
    swprintf(token, 80, L"%lu-%llu", GetCurrentProcessId(), GetTickCount64());
    swprintf(begun, 512, L"%ls\\ENTRY-%ls.started", kit, token);
    swprintf(done, 512, L"%ls\\ENTRY-%ls.done", kit, token);
    if (GetFileAttributesW(begun) != INVALID_FILE_ATTRIBUTES || GetFileAttributesW(done) != INVALID_FILE_ATTRIBUTES) return 4;
    swprintf(command, 1024, L"\"%ls\" /unix /system/bin/sh /sdcard/Download/Thor-Forever/installer/entry.sh %ls", start, token);
    if (!CreateProcessW(start, command, NULL, NULL, FALSE, 0, NULL, NULL, &si, &pi)) {
        MessageBoxW(NULL, L"Could not start Thor Forever.", L"Thor Forever", MB_OK | MB_ICONERROR);
        return 5;
    }
    CloseHandle(pi.hThread);
    CloseHandle(pi.hProcess);
    /* start.exe exit is not game exit; use the bridge's completion handshake. */
    deadline = GetTickCount64() + 60000;
    while (GetFileAttributesW(begun) == INVALID_FILE_ATTRIBUTES) {
        if (GetTickCount64() >= deadline) {
            MessageBoxW(NULL, L"The launch bridge did not respond within 60 seconds. Keep the logs for diagnosis. Do not repeatedly launch it.", L"Thor Forever", MB_OK | MB_ICONERROR);
            return 6;
        }
        Sleep(250);
    }
    while (GetFileAttributesW(done) == INVALID_FILE_ATTRIBUTES) Sleep(500);
    result = CreateFileW(done, GENERIC_READ, FILE_SHARE_READ | FILE_SHARE_WRITE, NULL, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, NULL);
    if (result == INVALID_HANDLE_VALUE) return 7;
    if (!ReadFile(result, buffer, sizeof(buffer)-1, &count, NULL)) { CloseHandle(result); return 7; }
    CloseHandle(result);
    if (!count || count >= sizeof(buffer)-1 || buffer[0] < '0' || buffer[0] > '9') return 7;
    parsed = strtoul(buffer, &end, 10);
    while (*end == '\r' || *end == '\n') ++end;
    if (*end || parsed > 255) return 7;
    int code = (int)parsed;
    if (code) MessageBoxW(NULL, L"The game stopped with an error. Keep the newest logs\\run folder and ENTRY log for diagnosis.", L"Thor Forever", MB_OK | MB_ICONWARNING);
    return code;
}
