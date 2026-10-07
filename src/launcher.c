#ifndef UNICODE
#define UNICODE
#endif
#ifndef _UNICODE
#define _UNICODE
#endif
#include <windows.h>
#include <tlhelp32.h>
#include <wchar.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>

/* SPDX-License-Identifier: MIT
 * Start screen for Thor Forever: shows the installed game version, opens
 * Battle.net for updates, changes a few tuning.conf settings and starts the
 * game. Battle.net does the update
 * itself; this program never touches the game's files or memory. Playing
 * keeps GameHub's tracked process alive until the game bridge finishes. */

#define KIT L"Z:\\sdcard\\Download\\Thor-Forever"
#define ID_PLAY 101
#define ID_UPDATE 102
#define ID_QUIT 103
#define ID_REMOVE 104
#define ID_SETTING 110
#define ID_REFRESH 1

static const wchar_t *const program_dirs[] = {
    L"C:\\Program Files (x86)", L"C:\\Program Files"
};
static HWND menu_window, version_text, status_text, play_button, notice_text, remove_button;

/* Settings that can be changed on the start screen. Each tap on a button
 * moves to the next value and saves it to tuning.conf. */
struct setting {
    const char *key;
    const wchar_t *label;
    const char *values[4];
    const wchar_t *names[4];
    HWND button;
};
static struct setting settings[] = {
    { "FPS_CAP", L"FPS cap", { "30", "45", "60", "0" }, { L"30", L"45", L"60", L"none" }, NULL },
    { "HUD", L"Overlay", { "off", "fps", "fps,frametimes,compiler", NULL }, { L"off", L"FPS", L"FPS + graph", NULL }, NULL },
    { "PROFILE", L"Measuring", { "off", "on", NULL, NULL }, { L"off", L"on", NULL, NULL }, NULL },
};
#define SETTING_COUNT (int)(sizeof(settings) / sizeof(*settings))
static char tuning[65536];
static HFONT font, big_font;
static int bnet_started, removing, menu_width, menu_height, notice_height;
static void refresh_copies(void);
static void remove_other_copy(HWND window);

/* Reads a small text file into buffer, NUL-terminated. */
static int read_text(const wchar_t *path, char *buffer, DWORD size)
{
    HANDLE file;
    DWORD count = 0;
    file = CreateFileW(path, GENERIC_READ, FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
                       NULL, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, NULL);
    if (file == INVALID_HANDLE_VALUE) return 0;
    if (!ReadFile(file, buffer, size - 1, &count, NULL)) count = 0;
    CloseHandle(file);
    buffer[count] = 0;
    return count > 0;
}

/* Copies field number index of a '|' separated line (ending at '\r', '\n'
 * or NUL) into out. */
static void get_field(const char *line, int index, char *out, size_t size)
{
    size_t n = 0;
    while (index > 0 && *line && *line != '\n' && *line != '\r') {
        if (*line++ == '|') --index;
    }
    if (index > 0) { out[0] = 0; return; }
    while (*line && *line != '|' && *line != '\r' && *line != '\n' && n + 1 < size) out[n++] = *line++;
    out[n] = 0;
}

/* Index of the column called name in a .build.info header ("Name!TYPE:n"). */
static int find_column(const char *header, const char *name)
{
    char field[64];
    int i;
    for (i = 0; i < 64; ++i) {
        char *bang;
        get_field(header, i, field, sizeof(field));
        if (!field[0]) return -1;
        if ((bang = strchr(field, '!'))) *bang = 0;
        if (!strcmp(field, name)) return i;
    }
    return -1;
}

/* Finds the game in this container and reads its installed version from the
 * plain-text .build.info that Battle.net writes. The row is picked by the
 * product named in _classic_beta_\.flavor.info. */
static int read_installed_version(wchar_t *out, size_t size)
{
    static char info[65536];
    char flavor[512], product[64] = "", field[64], *line;
    wchar_t path[MAX_PATH];
    int product_col, version_col, i;
    size_t d;
    for (d = 0; d < sizeof(program_dirs) / sizeof(*program_dirs); ++d) {
        swprintf(path, MAX_PATH, L"%ls\\World of Warcraft\\.build.info", program_dirs[d]);
        if (read_text(path, info, sizeof(info))) break;
    }
    if (d == sizeof(program_dirs) / sizeof(*program_dirs)) return 0;
    swprintf(path, MAX_PATH, L"%ls\\World of Warcraft\\_classic_beta_\\.flavor.info", program_dirs[d]);
    if (read_text(path, flavor, sizeof(flavor)) && (line = strchr(flavor, '\n')))
        get_field(line + 1, 0, product, sizeof(product));
    product_col = find_column(info, "Product");
    version_col = find_column(info, "Version");
    if (version_col < 0) return 0;
    for (line = strchr(info, '\n'); line; line = strchr(line, '\n')) {
        ++line;
        if (!*line || *line == '\r' || *line == '\n') continue;
        if (product[0] && product_col >= 0) {
            get_field(line, product_col, field, sizeof(field));
            if (strcmp(field, product)) continue;
        }
        get_field(line, version_col, field, sizeof(field));
        if (!field[0]) continue;
        for (i = 0; field[i] && (size_t)i + 1 < size; ++i) out[i] = (unsigned char)field[i];
        out[i] = 0;
        return 1;
    }
    return 0;
}

/* Battle.net often keeps running in the tray after its window is closed, so
 * it counts as open only while one of its windows is visible. */
static DWORD bnet_pids[32];
static int bnet_count, bnet_visible;

static BOOL CALLBACK find_bnet_window(HWND window, LPARAM unused)
{
    DWORD pid = 0;
    int i;
    (void)unused;
    if (!IsWindowVisible(window)) return TRUE;
    GetWindowThreadProcessId(window, &pid);
    for (i = 0; i < bnet_count; ++i)
        if (bnet_pids[i] == pid) { bnet_visible = 1; return FALSE; }
    return TRUE;
}

static int battle_net_open(void)
{
    PROCESSENTRY32W entry;
    HANDLE snap = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
    bnet_count = 0;
    bnet_visible = 0;
    if (snap == INVALID_HANDLE_VALUE) return 0;
    entry.dwSize = sizeof(entry);
    if (Process32FirstW(snap, &entry)) {
        do {
            if (!_wcsicmp(entry.szExeFile, L"Battle.net.exe") && bnet_count < 32)
                bnet_pids[bnet_count++] = entry.th32ProcessID;
        } while (Process32NextW(snap, &entry));
    }
    CloseHandle(snap);
    if (bnet_count) EnumWindows(find_bnet_window, 0);
    return bnet_visible;
}

static int start_battle_net(void)
{
    static const wchar_t *const names[] = { L"Battle.net Launcher.exe", L"Battle.net.exe" };
    wchar_t dir[MAX_PATH], exe[MAX_PATH], command[MAX_PATH + 4];
    STARTUPINFOW si = {0};
    PROCESS_INFORMATION pi = {0};
    size_t d, i;
    si.cb = sizeof(si);
    for (d = 0; d < sizeof(program_dirs) / sizeof(*program_dirs); ++d) {
        swprintf(dir, MAX_PATH, L"%ls\\Battle.net", program_dirs[d]);
        for (i = 0; i < sizeof(names) / sizeof(*names); ++i) {
            swprintf(exe, MAX_PATH, L"%ls\\%ls", dir, names[i]);
            if (GetFileAttributesW(exe) == INVALID_FILE_ATTRIBUTES) continue;
            swprintf(command, MAX_PATH + 4, L"\"%ls\"", exe);
            if (!CreateProcessW(exe, command, NULL, NULL, FALSE, 0, NULL, dir, &si, &pi)) return 0;
            CloseHandle(pi.hThread);
            CloseHandle(pi.hProcess);
            return 1;
        }
    }
    return 0;
}

/* Start of the "KEY=" line in tuning.conf, or NULL. */
static char *find_setting(const char *key)
{
    size_t len = strlen(key);
    char *line = tuning;
    while (line && *line) {
        if (!strncmp(line, key, len) && line[len] == '=') return line;
        line = strchr(line, '\n');
        if (line) ++line;
    }
    return NULL;
}

static int current_value(const struct setting *s)
{
    char *line = find_setting(s->key), value[64];
    size_t n = 0;
    int i;
    if (!line) return -1;
    line += strlen(s->key) + 1;
    while (*line && *line != '\r' && *line != '\n' && *line != '#' && n + 1 < sizeof(value)) {
        if (*line != ' ' && *line != '\t') value[n++] = *line;
        ++line;
    }
    value[n] = 0;
    for (i = 0; i < 4 && s->values[i]; ++i)
        if (!strcmp(value, s->values[i])) return i;
    return -1;
}

static void show_setting(struct setting *s)
{
    wchar_t text[64];
    int i = current_value(s);
    swprintf(text, 64, L"%ls: %ls", s->label, i < 0 ? L"custom" : s->names[i]);
    SetWindowTextW(s->button, text);
}

/* Replaces the value on the KEY= line (or adds the line) and saves the file
 * through a temporary file, so a failed write never leaves half a file. */
static int save_setting(const struct setting *s, const char *value)
{
    static char out[65536 + 128];
    char *line = find_setting(s->key), *rest;
    size_t head, vlen = strlen(value), klen = strlen(s->key), tail;
    HANDLE file;
    DWORD written;
    if (line) {
        head = (size_t)(line - tuning);
        rest = line + klen + 1;
        while (*rest && *rest != '\r' && *rest != '\n') ++rest;
    } else {
        head = strlen(tuning);
        rest = tuning + head;
    }
    tail = strlen(rest);
    if (head + klen + 2 + vlen + tail + 1 >= sizeof(tuning)) return 0;
    memcpy(out, tuning, head);
    if (!line && head && tuning[head - 1] != '\n') out[head++] = '\n';
    memcpy(out + head, s->key, klen);
    out[head + klen] = '=';
    memcpy(out + head + klen + 1, value, vlen);
    head += klen + 1 + vlen;
    if (!line) out[head++] = '\n';
    memcpy(out + head, rest, tail);
    head += tail;
    file = CreateFileW(KIT L"\\tuning.conf.tmp", GENERIC_WRITE, 0, NULL, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
    if (file == INVALID_HANDLE_VALUE) return 0;
    if (!WriteFile(file, out, (DWORD)head, &written, NULL) || written != head) {
        CloseHandle(file);
        DeleteFileW(KIT L"\\tuning.conf.tmp");
        return 0;
    }
    CloseHandle(file);
    if (!MoveFileExW(KIT L"\\tuning.conf.tmp", KIT L"\\tuning.conf", MOVEFILE_REPLACE_EXISTING)) return 0;
    memcpy(tuning, out, head);
    tuning[head] = 0;
    return 1;
}

static void next_setting(HWND window, struct setting *s)
{
    int i = current_value(s) + 1;
    if (i >= 4 || !s->values[i]) i = 0;
    if (!save_setting(s, s->values[i]))
        MessageBoxW(window, L"Could not save tuning.conf.", L"Thor Forever", MB_OK | MB_ICONERROR);
    show_setting(s);
}

/* Battle.net and its helpers keep running in the background after its
 * window is closed. Ends them before the game starts, the same as closing
 * the container after updating. */
static void close_battle_net(void)
{
    static const wchar_t *const names[] = {
        L"Battle.net.exe", L"Battle.net Launcher.exe", L"Battle.net Helper.exe",
        L"Agent.exe", L"BlizzardError.exe"
    };
    HANDLE procs[64];
    PROCESSENTRY32W entry;
    HANDLE snap = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
    int count = 0, i;
    size_t n;
    if (snap == INVALID_HANDLE_VALUE) return;
    entry.dwSize = sizeof(entry);
    if (Process32FirstW(snap, &entry)) {
        do {
            for (n = 0; n < sizeof(names) / sizeof(*names); ++n) {
                HANDLE proc;
                if (_wcsicmp(entry.szExeFile, names[n]) || count >= 64) continue;
                proc = OpenProcess(PROCESS_TERMINATE | SYNCHRONIZE, FALSE, entry.th32ProcessID);
                if (proc && TerminateProcess(proc, 0)) procs[count++] = proc;
                else if (proc) CloseHandle(proc);
            }
        } while (Process32NextW(snap, &entry));
    }
    CloseHandle(snap);
    for (i = 0; i < count; ++i) {
        WaitForSingleObject(procs[i], 5000);
        CloseHandle(procs[i]);
    }
}

static void refresh(void)
{
    wchar_t version[64], text[128];
    if (read_installed_version(version, 64))
        swprintf(text, 128, L"Installed game version: %ls", version);
    else
        wcscpy(text, L"Installed game version: not found");
    SetWindowTextW(version_text, text);
    if (battle_net_open())
        SetWindowTextW(status_text, L"Battle.net is open. Press Update there if it offers one. "
                                    L"When it's done, close Battle.net and press Play.");
    else if (bnet_started)
        SetWindowTextW(status_text, L"Battle.net is closed. The version above is now installed.");
    else
        SetWindowTextW(status_text, L"Press Update with Battle.net to check for a game update.");
    refresh_copies();
}

static HWND add_control(HWND parent, const wchar_t *cls, const wchar_t *text, DWORD style,
                        int x, int y, int w, int h, int id, HFONT f)
{
    HWND control = CreateWindowExW(0, cls, text, WS_CHILD | WS_VISIBLE | style, x, y, w, h,
                                   parent, (HMENU)(INT_PTR)id, NULL, NULL);
    SendMessageW(control, WM_SETFONT, (WPARAM)f, TRUE);
    return control;
}

static LRESULT CALLBACK window_proc(HWND window, UINT message, WPARAM wparam, LPARAM lparam)
{
    switch (message) {
    case WM_COMMAND:
        switch (LOWORD(wparam)) {
        case ID_PLAY:
        case IDOK:
            if (removing) return 0;
            if (battle_net_open() &&
                MessageBoxW(window, L"Battle.net is still open. If it is updating the game, "
                            L"starting now breaks the update.\n\nClose Battle.net and start the game?",
                            L"Thor Forever", MB_YESNO | MB_ICONWARNING | MB_DEFBUTTON2) != IDYES)
                return 0;
            close_battle_net();
            DestroyWindow(window);
            PostQuitMessage(ID_PLAY);
            return 0;
        case ID_UPDATE:
            if (battle_net_open()) {
                SetWindowTextW(status_text, L"Battle.net is already open.");
            } else if (start_battle_net()) {
                bnet_started = 1;
                SetWindowTextW(status_text, L"Starting Battle.net...");
            } else {
                MessageBoxW(window, L"Battle.net was not found in this container.",
                            L"Thor Forever", MB_OK | MB_ICONERROR);
            }
            return 0;
        case ID_REMOVE:
            remove_other_copy(window);
            return 0;
        case ID_SETTING:
        case ID_SETTING + 1:
        case ID_SETTING + 2:
            next_setting(window, &settings[LOWORD(wparam) - ID_SETTING]);
            return 0;
        case ID_QUIT:
        case IDCANCEL:
            if (removing) {
                MessageBoxW(window, L"The other game copy is still being removed. Wait until it's done.",
                            L"Thor Forever", MB_OK | MB_ICONINFORMATION);
                return 0;
            }
            DestroyWindow(window);
            PostQuitMessage(ID_QUIT);
            return 0;
        }
        break;
    case WM_TIMER:
        refresh();
        return 0;
    case WM_CLOSE:
        if (removing) {
            MessageBoxW(window, L"The other game copy is still being removed. Wait until it's done.",
                        L"Thor Forever", MB_OK | MB_ICONINFORMATION);
            return 0;
        }
        DestroyWindow(window);
        PostQuitMessage(ID_QUIT);
        return 0;
    }
    return DefWindowProcW(window, message, wparam, lparam);
}

/* Shows the start screen. Returns ID_PLAY or ID_QUIT. */
static int show_menu(HINSTANCE instance)
{
    WNDCLASSW wc = {0};
    MSG msg;
    HWND window;
    int sw = GetSystemMetrics(SM_CXSCREEN), sh = GetSystemMetrics(SM_CYSCREEN);
    int u = sh / 24, w = sw * 3 / 5, h, x = u, y = u, bw, i;
    if (u < 16) u = 16;
    if (w < 24 * u) w = 24 * u < sw ? 24 * u : sw;
    h = 15 * u;
    font = CreateFontW(-u * 2 / 3, 0, 0, 0, FW_NORMAL, 0, 0, 0, DEFAULT_CHARSET, 0, 0,
                       CLEARTYPE_QUALITY, 0, L"Tahoma");
    big_font = CreateFontW(-u, 0, 0, 0, FW_BOLD, 0, 0, 0, DEFAULT_CHARSET, 0, 0,
                           CLEARTYPE_QUALITY, 0, L"Tahoma");
    wc.lpfnWndProc = window_proc;
    wc.hInstance = instance;
    wc.hCursor = LoadCursorW(NULL, (LPCWSTR)IDC_ARROW);
    wc.hbrBackground = (HBRUSH)(COLOR_BTNFACE + 1);
    wc.lpszClassName = L"ThorForeverMenu";
    RegisterClassW(&wc);
    window = CreateWindowExW(WS_EX_APPWINDOW, wc.lpszClassName, L"Thor Forever",
                             WS_POPUP | WS_CAPTION | WS_SYSMENU,
                             (sw - w) / 2, (sh - h) / 2, w, h, NULL, NULL, instance, NULL);
    menu_window = window;
    menu_width = w;
    menu_height = h;
    notice_height = 4 * u;
    {
        RECT client;
        GetClientRect(window, &client);
        w = client.right;
    }
    add_control(window, L"STATIC", L"World of Warcraft on the AYN Thor", SS_LEFT,
                x, y, w - 2 * u, u * 3 / 2, 0, big_font);
    y += u * 2;
    version_text = add_control(window, L"STATIC", L"", SS_LEFT, x, y, w - 2 * u, u, 0, font);
    y += u;
    status_text = add_control(window, L"STATIC", L"", SS_LEFT, x, y, w - 2 * u, u * 2, 0, font);
    y += u * 3;
    bw = (w - 4 * u) / 3;
    if (!read_text(KIT L"\\tuning.conf", tuning, sizeof(tuning))) tuning[0] = 0;
    for (i = 0; i < SETTING_COUNT; ++i) {
        settings[i].button = add_control(window, L"BUTTON", L"", BS_PUSHBUTTON | WS_TABSTOP,
                                         x + i * (bw + u), y, bw, u * 2, ID_SETTING + i, font);
        show_setting(&settings[i]);
    }
    y += u * 3;
    play_button = add_control(window, L"BUTTON", L"Play", BS_DEFPUSHBUTTON | WS_TABSTOP,
                              x, y, bw, u * 3, ID_PLAY, big_font);
    add_control(window, L"BUTTON", L"Update with\nBattle.net", BS_PUSHBUTTON | BS_MULTILINE | WS_TABSTOP,
                x + bw + u, y, bw, u * 3, ID_UPDATE, font);
    add_control(window, L"BUTTON", L"Quit", BS_PUSHBUTTON | WS_TABSTOP,
                x + 2 * (bw + u), y, bw, u * 3, ID_QUIT, font);
    /* Shown only when the game is installed in more than one container. */
    y += u * 4;
    notice_text = add_control(window, L"STATIC", L"", SS_LEFT, x, y, 2 * bw + u, u * 3, 0, font);
    remove_button = add_control(window, L"BUTTON", L"Remove other copy", BS_PUSHBUTTON | WS_TABSTOP,
                                x + 2 * (bw + u), y, bw, u * 2, ID_REMOVE, font);
    ShowWindow(notice_text, SW_HIDE);
    ShowWindow(remove_button, SW_HIDE);
    refresh();
    SetTimer(window, ID_REFRESH, 2000, NULL);
    ShowWindow(window, SW_SHOW);
    SetForegroundWindow(window);
    SetFocus(play_button);
    while (GetMessageW(&msg, NULL, 0, 0) > 0) {
        if (IsWindow(window) && IsDialogMessageW(window, &msg)) continue;
        TranslateMessage(&msg);
        DispatchMessageW(&msg);
    }
    DeleteObject(font);
    DeleteObject(big_font);
    return (int)msg.wParam;
}

/* When the bridge does not start, records what start.exe returned and which
 * processes run, into logs\\launch-diag.txt, to find out what blocks it. */
static void write_diag(HANDLE starter, const wchar_t *command)
{
    PROCESSENTRY32W entry;
    HANDLE snap, file;
    DWORD code = 0, written;
    char line[600];
    int n;
    file = CreateFileW(KIT L"\\logs\\launch-diag.txt", GENERIC_WRITE, FILE_SHARE_READ, NULL,
                       CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
    if (file == INVALID_HANDLE_VALUE) return;
    if (!GetExitCodeProcess(starter, &code)) code = 0xffffffff;
    n = snprintf(line, sizeof(line), "command: %ls\r\nstart.exe exit code: %lu%s\r\nprocesses:\r\n",
                 command, (unsigned long)code, code == STILL_ACTIVE ? " (still running)" : "");
    if (n > 0) WriteFile(file, line, (DWORD)strlen(line), &written, NULL);
    snap = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
    if (snap != INVALID_HANDLE_VALUE) {
        entry.dwSize = sizeof(entry);
        if (Process32FirstW(snap, &entry)) {
            do {
                n = snprintf(line, sizeof(line), "  %lu %ls (parent %lu)\r\n", (unsigned long)entry.th32ProcessID,
                             entry.szExeFile, (unsigned long)entry.th32ParentProcessID);
                if (n > 0) WriteFile(file, line, (DWORD)strlen(line), &written, NULL);
            } while (Process32NextW(snap, &entry));
        }
        CloseHandle(snap);
    }
    CloseHandle(file);
}

/* The game bridge: installer/entry.sh, started through start.exe /unix.
 * Once Battle.net has run in the GameHub session, GameHub no longer starts
 * it (start.exe returns 0 but the script never runs). So when entry.sh
 * supports it, the bridge is started in "wait" mode as soon as the start
 * screen opens, and Play only tells it to go on. */
static wchar_t bridge_token[80], bridge_command[1024];
static HANDLE bridge_starter;
static int bridge_waiting;

static void entry_path(wchar_t *out, const wchar_t *token, const wchar_t *suffix)
{
    swprintf(out, 512, L"%ls\\logs\\ENTRY-%ls.%ls", KIT, token, suffix);
}

static int touch(const wchar_t *path)
{
    HANDLE file = CreateFileW(path, GENERIC_WRITE, 0, NULL, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
    if (file == INVALID_HANDLE_VALUE) return 0;
    CloseHandle(file);
    return 1;
}

static int start_bridge(int wait)
{
    wchar_t start[MAX_PATH];
    STARTUPINFOW si = {0};
    PROCESS_INFORMATION pi = {0};
    DWORD length = GetSystemDirectoryW(start, MAX_PATH);
    si.cb = sizeof(si);
    if (!length || length + 11 >= MAX_PATH) return 0;
    wcscat(start, L"\\start.exe");
    CreateDirectoryW(KIT L"\\logs", NULL);
    swprintf(bridge_token, 80, L"%lu-%llu", GetCurrentProcessId(), GetTickCount64());
    swprintf(bridge_command, 1024, L"\"%ls\" /unix /system/bin/sh /sdcard/Download/Thor-Forever/installer/entry.sh %ls%ls",
             start, bridge_token, wait ? L" wait" : L"");
    if (!CreateProcessW(start, bridge_command, NULL, NULL, FALSE, 0, NULL, NULL, &si, &pi)) return 0;
    CloseHandle(pi.hThread);
    if (bridge_starter) CloseHandle(bridge_starter);
    bridge_starter = pi.hProcess;
    return 1;
}

/* Starts the waiting bridge if this entry.sh supports it. */
static void prepare_bridge(void)
{
    static char script[8192];
    if (!read_text(KIT L"\\installer\\entry.sh", script, sizeof(script))) return;
    if (!strstr(script, "TF_WAIT_FOR_PLAY")) return;
    bridge_waiting = start_bridge(1);
}

/* Tells a waiting bridge to end, for Quit. */
static void cancel_bridge(void)
{
    wchar_t path[512];
    if (!bridge_waiting) return;
    entry_path(path, bridge_token, L"quit");
    touch(path);
}

/* With the game installed in more than one GameHub container, the waiting
 * bridge lists the copies in logs\\ENTRY-<token>.copies ("HERE", "OTHER" or
 * "ELSEWHERE" and the container's folder name) and their sizes in .sizes
 * (installer/game-copies.sh). The start screen shows a notice and can ask
 * the bridge to delete the other container's World of Warcraft folder
 * (.remove); the answer comes back in .removed. */
static char other_name[128];
static wchar_t notice_message[512];

static int container_name_ok(const char *name)
{
    size_t n = strlen(name), i;
    if (!n || n >= sizeof(other_name) || !strcmp(name, ".") || !strcmp(name, "..")) return 0;
    for (i = 0; i < n; ++i) {
        char c = name[i];
        if (!((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') ||
              c == '_' || c == '-' || c == '.')) return 0;
    }
    return 1;
}

/* Splits "KIND rest of line" at the first space; returns the next line. */
static char *split_line(char *line, char **kind, char **rest)
{
    char *end = line + strcspn(line, "\r\n"), *next = *end ? end + 1 : end;
    *end = 0;
    *kind = line;
    *rest = strchr(line, ' ');
    if (*rest) *(*rest)++ = 0;
    else *rest = end;
    return next;
}

static void show_notice(int on, int button)
{
    int shown = IsWindowVisible(notice_text);
    RECT r;
    ShowWindow(remove_button, on && button ? SW_SHOW : SW_HIDE);
    if (on == shown) return;
    ShowWindow(notice_text, on ? SW_SHOW : SW_HIDE);
    /* Grows the window, staying centered. */
    GetWindowRect(menu_window, &r);
    SetWindowPos(menu_window, NULL, r.left, r.top + (on ? -notice_height : notice_height) / 2,
                 menu_width, menu_height + (on ? notice_height : 0), SWP_NOZORDER);
}

static void refresh_copies(void)
{
    static char copies[4096], sizes[4096];
    wchar_t path[512], text[1024], size_text[64] = L"size not measured yet";
    char *line, *kind, *rest, first_other[128] = "";
    int others = 0, elsewhere = 0, i;
    if (!bridge_waiting) return;
    if (removing) {
        entry_path(path, bridge_token, L"removed");
        if (!read_text(path, sizes, 32)) return;
        DeleteFileW(path);
        removing = 0;
        EnableWindow(play_button, TRUE);
        EnableWindow(remove_button, TRUE);
        if (atoi(sizes) == 0 && sizes[0] == '0')
            swprintf(notice_message, 512, L"The other game copy was removed.");
        else
            swprintf(notice_message, 512, L"Could not remove the other game copy (code %d). "
                     L"Details are in logs\\ENTRY-%ls.log.", atoi(sizes), bridge_token);
    }
    entry_path(path, bridge_token, L"copies");
    if (!read_text(path, copies, sizeof(copies))) copies[0] = 0;
    for (line = copies; *line;) {
        line = split_line(line, &kind, &rest);
        if (!strcmp(kind, "OTHER")) {
            if (!others++ && container_name_ok(rest)) strcpy(first_other, rest);
        } else if (!strcmp(kind, "ELSEWHERE")) {
            ++elsewhere;
        }
    }
    strcpy(other_name, first_other);
    if (removing) return;
    if (other_name[0]) {
        entry_path(path, bridge_token, L"sizes");
        if (!read_text(path, sizes, sizeof(sizes))) sizes[0] = 0;
        for (line = sizes; *line;) {
            char *kb;
            line = split_line(line, &kind, &kb);
            if (strcmp(kind, "SIZE") || !(rest = strchr(kb, ' '))) continue;
            *rest++ = 0;
            if (!strcmp(rest, other_name))
                swprintf(size_text, 64, L"%.1f GB", strtod(kb, NULL) / (1024.0 * 1024.0));
        }
        for (i = 0; other_name[i] && i < 14; ++i) path[i] = (unsigned char)other_name[i];
        wcscpy(path + i, other_name[i] ? L"..." : L"");
        swprintf(text, 1024, L"The game is also installed in another GameHub container (%ls, %ls). "
                 L"You play from the copy in this container.", path, size_text);
        if (notice_message[0]) {
            wcscat(text, L" ");
            wcsncat(text, notice_message, 1023 - wcslen(text));
        }
        SetWindowTextW(notice_text, text);
        show_notice(1, 1);
    } else if (others || elsewhere) {
        SetWindowTextW(notice_text, others
                       ? L"The game is also installed in another GameHub container. Its folder name has "
                         L"unusual characters, so it can't be removed from here."
                       : L"The game is installed in other GameHub containers, but not in this one. "
                         L"Start Thor Forever from the container you play in.");
        show_notice(1, 0);
    } else if (notice_message[0]) {
        SetWindowTextW(notice_text, notice_message);
        show_notice(1, 0);
    } else {
        show_notice(0, 0);
    }
}

/* Asks before deleting: the other container's World of Warcraft folder. */
static void remove_other_copy(HWND window)
{
    wchar_t path[512], tmp[512], text[512], name[128];
    char line[160];
    HANDLE file;
    DWORD written;
    int i, ok;
    if (removing || !other_name[0]) return;
    for (i = 0; other_name[i]; ++i) name[i] = (unsigned char)other_name[i];
    name[i] = 0;
    swprintf(text, 512, L"Delete the World of Warcraft folder in the other GameHub container (%ls)?\n\n"
             L"The game in this container stays as it is, with its settings and addons. "
             L"This can't be undone.", name);
    if (MessageBoxW(window, text, L"Thor Forever", MB_YESNO | MB_ICONWARNING | MB_DEFBUTTON2) != IDYES) return;
    entry_path(path, bridge_token, L"remove");
    entry_path(tmp, bridge_token, L"remove.tmp");
    snprintf(line, sizeof(line), "%s\n", other_name);
    file = CreateFileW(tmp, GENERIC_WRITE, 0, NULL, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
    ok = file != INVALID_HANDLE_VALUE;
    if (ok) {
        ok = WriteFile(file, line, (DWORD)strlen(line), &written, NULL) && written == strlen(line);
        CloseHandle(file);
    }
    if (!ok || !MoveFileExW(tmp, path, MOVEFILE_REPLACE_EXISTING)) {
        DeleteFileW(tmp);
        MessageBoxW(window, L"Could not ask for the removal.", L"Thor Forever", MB_OK | MB_ICONERROR);
        return;
    }
    removing = 1;
    notice_message[0] = 0;
    EnableWindow(play_button, FALSE);
    EnableWindow(remove_button, FALSE);
    SetWindowTextW(notice_text, L"Removing the other game copy. This can take a few minutes; "
                                L"Play works again when it's done.");
}

/* Starts the game and waits for it, as GameHub tracks this process. */
static int run_game(void)
{
    wchar_t begun[512], done[512], ready[512], go[512], old_begun[512], old_done[512];
    DWORD count;
    ULONGLONG deadline;
    HANDLE result;
    char buffer[32] = {0};
    char *end;
    unsigned long parsed;
    int started = 0;
    if (bridge_waiting) {
        entry_path(ready, bridge_token, L"ready");
        entry_path(go, bridge_token, L"go");
        /* The waiting bridge may still be starting up. */
        deadline = GetTickCount64() + 20000;
        while (GetFileAttributesW(ready) == INVALID_FILE_ATTRIBUTES && GetTickCount64() < deadline) Sleep(250);
        if (GetFileAttributesW(ready) != INVALID_FILE_ATTRIBUTES && touch(go)) started = 1;
        else cancel_bridge();
    }
    if (!started && !start_bridge(0)) {
        MessageBoxW(NULL, L"Could not start Thor Forever.", L"Thor Forever", MB_OK | MB_ICONERROR);
        return 5;
    }
    entry_path(begun, bridge_token, L"started");
    entry_path(done, bridge_token, L"done");
    /* installer/entry.sh from before the start screen writes these files
     * into the kit folder itself; accept that too. */
    swprintf(old_begun, 512, L"%ls\\ENTRY-%ls.started", KIT, bridge_token);
    swprintf(old_done, 512, L"%ls\\ENTRY-%ls.done", KIT, bridge_token);
    /* start.exe exit is not game exit; use the bridge's completion handshake. */
    deadline = GetTickCount64() + 60000;
    while (GetFileAttributesW(begun) == INVALID_FILE_ATTRIBUTES) {
        if (GetFileAttributesW(old_begun) != INVALID_FILE_ATTRIBUTES) {
            wcscpy(done, old_done);
            break;
        }
        if (GetTickCount64() >= deadline) {
            write_diag(bridge_starter, bridge_command);
            MessageBoxW(NULL, L"The game did not start. Close Thor Forever, start it again from GameHub and press Play.\n\n"
                        L"Details are in logs\\launch-diag.txt.", L"Thor Forever", MB_OK | MB_ICONERROR);
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

int WINAPI wWinMain(HINSTANCE instance, HINSTANCE previous, PWSTR args, int show)
{
    (void)previous; (void)args; (void)show;
    if (GetFileAttributesW(KIT L"\\installer\\entry.sh") == INVALID_FILE_ATTRIBUTES) {
        MessageBoxW(NULL, L"Required files are missing. Extract the complete package into Download/Thor-Forever.", L"Thor Forever", MB_OK | MB_ICONERROR);
        return 2;
    }
    prepare_bridge();
    if (show_menu(instance) != ID_PLAY) {
        cancel_bridge();
        return 0;
    }
    return run_game();
}
