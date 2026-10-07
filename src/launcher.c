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
#include <math.h>

/* SPDX-License-Identifier: MIT
 * Start screen for Thor Forever: shows the installed game version, opens
 * Battle.net for updates, changes a few tuning.conf settings and starts the
 * game. Battle.net does the update
 * itself; this program never touches the game's files or memory. Playing
 * keeps GameHub's tracked process alive until the game bridge finishes. */

#define ID_PLAY 101
#define ID_UPDATE 102
#define ID_QUIT 103
#define ID_SETTING 110
#define ID_REFRESH 1

/* The Thor-Forever folder is the folder this program is in (Download/
 * Thor-Forever by default, but any folder in shared storage works). KIT is
 * its Windows path, kit_unix the same folder for the Android shell, and
 * wine_name what Wine itself calls it (shown when nothing fits). */
static wchar_t KIT[MAX_PATH], kit_unix[MAX_PATH], wine_name[MAX_PATH];

typedef char *(CDECL *unix_name_function)(const WCHAR *);

/* A Unix path the installer scripts accept (same characters as there), and
 * the same folder as KIT: the check file check_name, made in KIT\logs, must
 * show up under Z:, which is the Unix root in every Wine prefix. */
static int same_folder(const wchar_t *candidate, const wchar_t *check_name)
{
    wchar_t seen[MAX_PATH + 64], *c;
    if (candidate[0] != L'/' || wcslen(candidate) >= MAX_PATH - 40) return 0;
    for (c = (wchar_t *)candidate; *c; ++c)
        if (!wcschr(L"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789/._-", *c)) return 0;
    if (wcsstr(candidate, L"/../") || wcsstr(candidate, L"/./")) return 0;
    if (!check_name) return 1;
    swprintf(seen, MAX_PATH + 64, L"Z:%ls/logs/%ls", candidate, check_name);
    for (c = seen; *c; ++c) if (*c == L'/') *c = L'\\';
    return GetFileAttributesW(seen) != INVALID_FILE_ATTRIBUTES;
}

static int find_kit(void)
{
    wchar_t candidates[8][MAX_PATH], check[MAX_PATH + 64], check_name[64], *slash, *c;
    unix_name_function unix_name;
    HANDLE file;
    int i, count = 0, found = 0;
    DWORD length = GetModuleFileNameW(NULL, KIT, MAX_PATH);
    if (!length || length >= MAX_PATH - 40) return 0;
    slash = wcsrchr(KIT, L'\\');
    if (!slash) return 0;
    *slash = 0;
    /* 1. What Wine says the folder is. */
    unix_name = (unix_name_function)(void (*)(void))GetProcAddress(GetModuleHandleW(L"kernel32.dll"), "wine_get_unix_file_name");
    if (unix_name) {
        char *name = unix_name(KIT);
        if (name) {
            if (!MultiByteToWideChar(CP_UTF8, 0, name, -1, wine_name, MAX_PATH)) wine_name[0] = 0;
            HeapFree(GetProcessHeap(), 0, name);
        }
    }
    if (wine_name[0]) wcscpy(candidates[count++], wine_name);
    /* 2. The path after the drive letter, under the places GameHub maps
     *    drives to: Z: is the Unix root, and other letters (D:, E:, ...)
     *    stand for shared storage or its Download folder. */
    if (KIT[0] && KIT[1] == L':' && KIT[2] == L'\\') {
        static const wchar_t *const roots[] = {
            L"", L"/sdcard", L"/storage/emulated/0", L"/sdcard/Download", L"/storage/emulated/0/Download"
        };
        size_t r;
        for (r = (KIT[0] == L'Z' || KIT[0] == L'z') ? 0 : 1; r < sizeof(roots) / sizeof(roots[0]); ++r) {
            if (wcslen(roots[r]) + wcslen(KIT + 2) >= MAX_PATH) continue;
            swprintf(candidates[count], MAX_PATH, L"%ls%ls", roots[r], KIT + 2);
            for (c = candidates[count++]; *c; ++c) if (*c == L'\\') *c = L'/';
        }
    }
    /* 3. The usual places, which earlier versions always used. */
    wcscpy(candidates[count++], L"/sdcard/Download/Thor-Forever");
    wcscpy(candidates[count++], L"/storage/emulated/0/Download/Thor-Forever");
    swprintf(check_name, 64, L"folder-check-%lu.tmp", GetCurrentProcessId());
    swprintf(check, MAX_PATH + 64, L"%ls\\logs", KIT);
    CreateDirectoryW(check, NULL);
    swprintf(check, MAX_PATH + 64, L"%ls\\logs\\%ls", KIT, check_name);
    file = CreateFileW(check, GENERIC_WRITE, 0, NULL, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
    if (file != INVALID_HANDLE_VALUE) CloseHandle(file);
    for (i = 0; i < count && !found; ++i) {
        /* Without a Z: drive or a check file, trust the first usable name. */
        int checked = file != INVALID_HANDLE_VALUE && GetFileAttributesW(L"Z:\\") != INVALID_FILE_ATTRIBUTES;
        if (same_folder(candidates[i], checked ? check_name : NULL)) {
            wcscpy(kit_unix, candidates[i]);
            found = 1;
        }
    }
    /* Only the check file this program just made in its own logs folder. */
    if (file != INVALID_HANDLE_VALUE) DeleteFileW(check);
    return found;
}

/* KIT + rel, in one of four rotating buffers. */
static const wchar_t *in_kit(const wchar_t *rel)
{
    static wchar_t buffers[4][MAX_PATH + 64];
    static int next;
    wchar_t *out = buffers[next++ & 3];
    swprintf(out, MAX_PATH + 64, L"%ls%ls", KIT, rel);
    return out;
}

static const wchar_t *const program_dirs[] = {
    L"C:\\Program Files (x86)", L"C:\\Program Files"
};
static HWND menu_window, version_text, status_text, play_button, notice_text;

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
static HFONT font, label_font;
static HBRUSH background_brush;
static int header_height;

/* Colours of the start screen, after World of Warcraft: Forever: deep sky
 * blue, light sky, cream, the teal of its logo and gold trim (colours only;
 * no game artwork is used). Headings and buttons use Cinzel (fonts/, SIL
 * Open Font License, notices/CINZEL-OFL.txt), a free Roman-capitals font. */
#define TF_BACKGROUND RGB(16, 38, 59)
#define TF_HEADER_TOP RGB(65, 110, 151)
#define TF_CREAM RGB(243, 238, 226)
#define TF_SKY RGB(169, 207, 231)
#define TF_SKY_DARK RGB(131, 176, 206)
#define TF_EDGE RGB(65, 110, 151)
#define TF_TEXT RGB(211, 230, 243)
#define TF_TEAL RGB(52, 186, 215)
#define TF_TEAL_DARK RGB(32, 129, 165)
#define TF_WARNING RGB(224, 163, 53)
#define TF_GOLD RGB(201, 168, 106)
#define TF_GOLD_LIGHT RGB(241, 228, 194)

static HFONT button_font;
static int bnet_started, menu_width, menu_height, notice_height;
static wchar_t notice_buffer[1024];
static void refresh_copies(void);
static int refresh_install(void);
static int install_clicked(HWND window);
static int quit_while_installing(HWND window);

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
    file = CreateFileW(in_kit(L"\\tuning.conf.tmp"), GENERIC_WRITE, 0, NULL, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
    if (file == INVALID_HANDLE_VALUE) return 0;
    if (!WriteFile(file, out, (DWORD)head, &written, NULL) || written != head) {
        CloseHandle(file);
        DeleteFileW(in_kit(L"\\tuning.conf.tmp"));
        return 0;
    }
    CloseHandle(file);
    if (!MoveFileExW(in_kit(L"\\tuning.conf.tmp"), in_kit(L"\\tuning.conf"), MOVEFILE_REPLACE_EXISTING)) return 0;
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
    if (!refresh_install()) refresh_copies();
}

/* Vertical gradient, one line at a time (no extra library needed). */
static void fill_gradient(HDC dc, const RECT *r, COLORREF top, COLORREF bottom)
{
    int y, h = r->bottom - r->top;
    for (y = 0; y < h; ++y) {
        int f = h > 1 ? y * 256 / (h - 1) : 0;
        RECT line = { r->left, r->top + y, r->right, r->top + y + 1 };
        HBRUSH brush = CreateSolidBrush(RGB(
            (GetRValue(top) * (256 - f) + GetRValue(bottom) * f) / 256,
            (GetGValue(top) * (256 - f) + GetGValue(bottom) * f) / 256,
            (GetBValue(top) * (256 - f) + GetBValue(bottom) * f) / 256));
        FillRect(dc, &line, brush);
        DeleteObject(brush);
    }
}

static void frame(HDC dc, RECT r, COLORREF color)
{
    HBRUSH brush = CreateSolidBrush(color);
    FrameRect(dc, &r, brush);
    DeleteObject(brush);
}

/* The header is drawn SCALE times larger and then shrunk, which smooths
 * the letter outlines and the infinity swash (GDI itself draws them with
 * hard, stair-stepped edges). It is drawn once and kept in header_cache. */
#define SCALE 3
static HBITMAP header_cache;
static int unit;
static const wchar_t *heading_face = L"Tahoma";

/* A word in the style of the game's logo, centred on cx, cy: a metal
 * gradient (top, middle, bottom colours) with a dark bronze outline and a
 * soft shadow. */
/* Fills region grown by radius (copies shifted around circles), shifted
 * down by drop: an outline that only follows the letters' outer edges. */
static void grown_region(HDC dc, HRGN region, int radius, int drop, COLORREF color)
{
    HBRUSH brush = CreateSolidBrush(color);
    HRGN copy = CreateRectRgn(0, 0, 0, 0);
    int ring, step;
    for (ring = 1; ring <= 3; ++ring)
        for (step = 0; step < 24; ++step) {
            double angle = 6.283185307 * step / 24;
            int dx = (int)(radius * ring / 3.0 * cos(angle)), dy = (int)(radius * ring / 3.0 * sin(angle));
            CombineRgn(copy, region, NULL, RGN_COPY);
            OffsetRgn(copy, dx, dy + drop);
            FillRgn(dc, copy, brush);
        }
    DeleteObject(copy);
    DeleteObject(brush);
}

static void logo_word(HDC dc, const wchar_t *word, int cx, int cy, const COLORREF metal[3])
{
    int length = (int)wcslen(word), x, y;
    SIZE size;
    HRGN region;
    RECT fill;
    GetTextExtentPoint32W(dc, word, length, &size);
    x = cx - size.cx / 2;
    y = cy - size.cy / 2;
    /* WINDING: overlapping parts of a letter stay filled instead of
     * cancelling out into holes. */
    SetPolyFillMode(dc, WINDING);
    BeginPath(dc);
    TextOutW(dc, x, y, word, length);
    EndPath(dc);
    region = PathToRegion(dc);
    if (!region) return;
    grown_region(dc, region, 3 * SCALE, 2 * SCALE, RGB(10, 22, 34));
    grown_region(dc, region, 5 * SCALE / 2, 0, RGB(138, 102, 52));
    grown_region(dc, region, 3 * SCALE / 2, 0, RGB(42, 26, 12));
    SelectClipRgn(dc, region);
    fill.left = x;
    fill.right = x + size.cx;
    fill.top = y;
    fill.bottom = y + size.cy / 2;
    fill_gradient(dc, &fill, metal[0], metal[1]);
    fill.top = fill.bottom;
    fill.bottom = y + size.cy;
    fill_gradient(dc, &fill, metal[1], metal[2]);
    SelectClipRgn(dc, NULL);
    DeleteObject(region);
}

/* A round dot of radius r at x, y. */
static void dot(HDC dc, double x, double y, double r)
{
    Ellipse(dc, (int)(x - r), (int)(y - r), (int)(x + r + 1), (int)(y + r + 1));
}

/* The infinity sign under FOREVER: calligraphic (thin where the strokes
 * cross, full on the loops), in the same silvery white as FOREVER, with a
 * dark edge. The lines to its sides are added by swash_tails. */
static void swash(HDC dc, int cx, int cy, int half_width, int thickness)
{
    static const COLORREF colors[3] = { RGB(8, 22, 34), RGB(214, 210, 200), RGB(255, 255, 255) };
    int pass, i, steps = 1600;
    HGDIOBJ old_pen = SelectObject(dc, GetStockObject(NULL_PEN));
    for (pass = 0; pass < 3; ++pass) {
        HBRUSH brush = CreateSolidBrush(colors[pass]);
        HGDIOBJ old_brush = SelectObject(dc, brush);
        double grow = pass == 0 ? 1.5 * SCALE : 0, shrink = pass == 2 ? 0.35 : 1, lift = pass == 2 ? 0.35 : 0;
        for (i = 0; i < steps; ++i) {
            double a = 6.283185307 * i / steps, s = sin(a), c = cos(a), d = 1 + s * s;
            double x = cx + half_width * c / d, y = cy + half_width * 1.1 * s * c / d;
            double r = thickness * (0.3 + 0.7 * fabs(c));
            dot(dc, x, y - r * lift, r * shrink + grow);
        }
        SelectObject(dc, old_brush);
        DeleteObject(brush);
    }
    SelectObject(dc, old_pen);
}

/* Share of the pixel row [y, y + 1] covered by [top, bottom]. */
static double cover(int y, double top, double bottom)
{
    double a = top > y ? top : y, b = bottom < y + 1 ? bottom : y + 1;
    return b > a ? b - a : 0;
}

static void blend(unsigned char *p, COLORREF color, double amount)
{
    if (amount <= 0) return;
    if (amount > 1) amount = 1;
    p[0] = (unsigned char)(p[0] + (GetBValue(color) - p[0]) * amount);
    p[1] = (unsigned char)(p[1] + (GetGValue(color) - p[1]) * amount);
    p[2] = (unsigned char)(p[2] + (GetRValue(color) - p[2]) * amount);
}

/* The lines left and right of the infinity sign, drawn straight into the
 * finished w-pixel-wide header with exact coverage per pixel, so they
 * taper smoothly to a sharp point: from start pixels off the centre cx,
 * length pixels long, half as thick as r0 at the start, around row cy. */
static void swash_tails(unsigned char *bits, int w, int h, double cx, double cy, double start,
                        double length, double r0)
{
    int side, x, y;
    for (side = -1; side <= 1; side += 2)
        for (x = 0; x < w; ++x) {
            double off = side * (x + 0.5 - cx) - start, f, r, edge;
            if (off < 0 || off > length) continue;
            f = off / length;
            r = r0 * pow(1 - f, 1.4);
            edge = 0.7 * (1 - f);
            for (y = (int)(cy - r - 2); y <= (int)(cy + r + 2); ++y) {
                unsigned char *p;
                if (y < 0 || y >= h) continue;
                p = bits + 4 * ((size_t)y * w + x);
                blend(p, RGB(8, 22, 34), cover(y, cy - r - edge, cy + r + edge) * 0.8);
                blend(p, RGB(226, 222, 212), cover(y, cy - r, cy + r));
            }
        }
}

/* Draws the header (background, WORLD OF WARCRAFT, FOREVER, swash) at
 * SCALE and shrinks it to w by h, averaging each SCALE x SCALE block. */
static HBITMAP make_header(HDC screen, int w, int h)
{
    BITMAPINFO info = {0};
    unsigned char *big_bits, *bits;
    HDC dc = CreateCompatibleDC(screen);
    HBITMAP big, small;
    HGDIOBJ old;
    HFONT title, forever;
    RECT all = { 0, 0, w * SCALE, h * SCALE };
    int x, y, bx, by, u = unit * SCALE;
    info.bmiHeader.biSize = sizeof(info.bmiHeader);
    info.bmiHeader.biWidth = w * SCALE;
    info.bmiHeader.biHeight = -h * SCALE;
    info.bmiHeader.biPlanes = 1;
    info.bmiHeader.biBitCount = 32;
    big = CreateDIBSection(screen, &info, DIB_RGB_COLORS, (void **)&big_bits, NULL, 0);
    info.bmiHeader.biWidth = w;
    info.bmiHeader.biHeight = -h;
    small = CreateDIBSection(screen, &info, DIB_RGB_COLORS, (void **)&bits, NULL, 0);
    if (!dc || !big || !small) {
        if (big) DeleteObject(big);
        if (small) DeleteObject(small);
        if (dc) DeleteDC(dc);
        return NULL;
    }
    old = SelectObject(dc, big);
    fill_gradient(dc, &all, TF_HEADER_TOP, TF_BACKGROUND);
    SetBkMode(dc, TRANSPARENT);
    title = CreateFontW(-u * 21 / 20, 0, 0, 0, FW_BOLD, 0, 0, 0, DEFAULT_CHARSET, 0, 0,
                        ANTIALIASED_QUALITY, 0, heading_face);
    forever = CreateFontW(-u * 31 / 20, 0, 0, 0, FW_BOLD, 0, 0, 0, DEFAULT_CHARSET, 0, 0,
                          ANTIALIASED_QUALITY, 0, heading_face);
    {
        /* Champagne gold like "Warcraft" in the logo, silvery white like its
         * "Forever". */
        static const COLORREF gold[3] = { RGB(255, 253, 242), RGB(241, 228, 194), RGB(176, 140, 84) };
        static const COLORREF white[3] = { RGB(255, 255, 255), RGB(244, 242, 236), RGB(184, 180, 170) };
        SelectObject(dc, title);
        SetTextCharacterExtra(dc, u / 12);
        logo_word(dc, L"WORLD OF WARCRAFT", w * SCALE / 2, u, gold);
        SelectObject(dc, forever);
        SetTextCharacterExtra(dc, u / 8);
        logo_word(dc, L"FOREVER", w * SCALE / 2, u * 46 / 20, white);
        /* "on the AYN Thor" right of FOREVER, on its baseline. */
        {
            SIZE word, small;
            HFONT device = CreateFontW(-u / 2, 0, 0, 0, FW_BOLD, 0, 0, 0, DEFAULT_CHARSET, 0, 0,
                                       ANTIALIASED_QUALITY, 0, heading_face);
            TEXTMETRICW big_metrics, small_metrics;
            int x0, base;
            GetTextExtentPoint32W(dc, L"FOREVER", 7, &word);
            GetTextMetricsW(dc, &big_metrics);
            base = u * 46 / 20 - word.cy / 2 + big_metrics.tmAscent;
            x0 = w * SCALE / 2 + word.cx / 2 + u / 3;
            SetTextCharacterExtra(dc, u / 40);
            SelectObject(dc, device);
            GetTextMetricsW(dc, &small_metrics);
            GetTextExtentPoint32W(dc, L"on the AYN Thor", 15, &small);
            SetTextColor(dc, RGB(10, 22, 34));
            TextOutW(dc, x0 + SCALE, base - small_metrics.tmAscent + SCALE, L"on the AYN Thor", 15);
            SetTextColor(dc, TF_SKY);
            TextOutW(dc, x0, base - small_metrics.tmAscent, L"on the AYN Thor", 15);
            SelectObject(dc, forever);
            DeleteObject(device);
        }
        SetTextCharacterExtra(dc, 0);
    }
    swash(dc, w * SCALE / 2, u * 7 / 2, u * 6 / 5, u / 22);
    SelectObject(dc, old);
    DeleteObject(title);
    DeleteObject(forever);
    DeleteDC(dc);
    GdiFlush();
    for (y = 0; y < h; ++y)
        for (x = 0; x < w; ++x) {
            unsigned sum[3] = { 0, 0, 0 };
            for (by = 0; by < SCALE; ++by)
                for (bx = 0; bx < SCALE; ++bx) {
                    const unsigned char *p = big_bits + 4 * ((size_t)(y * SCALE + by) * w * SCALE + x * SCALE + bx);
                    sum[0] += p[0];
                    sum[1] += p[1];
                    sum[2] += p[2];
                }
            bits[4 * ((size_t)y * w + x)] = (unsigned char)(sum[0] / (SCALE * SCALE));
            bits[4 * ((size_t)y * w + x) + 1] = (unsigned char)(sum[1] / (SCALE * SCALE));
            bits[4 * ((size_t)y * w + x) + 2] = (unsigned char)(sum[2] / (SCALE * SCALE));
        }
    DeleteObject(big);
    swash_tails(bits, w, h, w / 2.0, unit * 7 / 2.0, unit * 6 / 5.0 + unit / 10.0, unit * 2.4, unit / 22.0 * 1.2);
    return small;
}

/* Background, frame and the header. */
static void paint_menu(HWND window)
{
    PAINTSTRUCT ps;
    HDC dc = BeginPaint(window, &ps);
    RECT client;
    GetClientRect(window, &client);
    FillRect(dc, &client, background_brush);
    if (!header_cache) header_cache = make_header(dc, client.right, header_height);
    if (header_cache) {
        HDC source = CreateCompatibleDC(dc);
        HGDIOBJ old = SelectObject(source, header_cache);
        BitBlt(dc, 0, 0, client.right, header_height, source, 0, 0, SRCCOPY);
        SelectObject(source, old);
        DeleteDC(source);
    }
    frame(dc, client, TF_GOLD);
    InflateRect(&client, -1, -1);
    frame(dc, client, RGB(74, 52, 24));
    InflateRect(&client, -3, -3);
    frame(dc, client, TF_SKY_DARK);
    EndPaint(window, &ps);
}

/* Buttons: Play in the teal of the Forever logo, the others in deep blue.
 * The three setting buttons show their name small and the value in light
 * sky blue. */
static void draw_button(const DRAWITEMSTRUCT *d)
{
    HDC dc = d->hDC;
    RECT r = d->rcItem, inner;
    wchar_t text[160], *colon;
    int play = d->hwndItem == play_button, i, setting = 0;
    int pressed = d->itemState & ODS_SELECTED, disabled = d->itemState & ODS_DISABLED;
    int focus = d->itemState & ODS_FOCUS;
    COLORREF top, bottom, edge, ink;
    for (i = 0; i < SETTING_COUNT; ++i) if (d->hwndItem == settings[i].button) setting = 1;
    if (disabled) {
        top = RGB(44, 58, 72); bottom = RGB(34, 46, 58); edge = RGB(70, 88, 106); ink = RGB(128, 146, 162);
    } else if (play) {
        top = TF_TEAL; bottom = TF_TEAL_DARK; edge = TF_GOLD; ink = RGB(255, 255, 255);
    } else {
        top = RGB(37, 70, 102); bottom = RGB(22, 48, 73); edge = TF_EDGE; ink = TF_TEXT;
    }
    if (pressed) { COLORREF swap = top; top = bottom; bottom = swap; }
    if (focus && !disabled) edge = TF_GOLD_LIGHT;
    fill_gradient(dc, &r, top, bottom);
    frame(dc, r, edge);
    inner = r;
    InflateRect(&inner, -1, -1);
    frame(dc, inner, RGB(9, 24, 38));
    if (pressed) OffsetRect(&r, 1, 1);
    GetWindowTextW(d->hwndItem, text, 160);
    SetBkMode(dc, TRANSPARENT);
    colon = setting ? wcschr(text, L':') : NULL;
    if (colon) {
        RECT label = r, value = r;
        *colon = 0;
        label.bottom = r.top + (r.bottom - r.top) * 9 / 20;
        value.top = label.bottom;
        value.bottom = r.bottom - (r.bottom - r.top) / 10;
        SelectObject(dc, label_font);
        SetTextColor(dc, disabled ? ink : TF_SKY);
        DrawTextW(dc, text, -1, &label, DT_CENTER | DT_BOTTOM | DT_SINGLELINE | DT_NOPREFIX);
        SelectObject(dc, button_font);
        SetTextColor(dc, disabled ? ink : TF_GOLD_LIGHT);
        DrawTextW(dc, colon[1] == L' ' ? colon + 2 : colon + 1, -1, &value,
                  DT_CENTER | DT_VCENTER | DT_SINGLELINE | DT_NOPREFIX);
    } else {
        RECT measure = r;
        int height;
        SelectObject(dc, button_font);
        SetTextColor(dc, ink);
        InflateRect(&measure, -4, 0);
        height = DrawTextW(dc, text, -1, &measure, DT_CENTER | DT_WORDBREAK | DT_CALCRECT | DT_NOPREFIX);
        measure.left = r.left + 4;
        measure.right = r.right - 4;
        measure.top = r.top + (r.bottom - r.top - height) / 2;
        measure.bottom = measure.top + height;
        DrawTextW(dc, text, -1, &measure, DT_CENTER | DT_WORDBREAK | DT_NOPREFIX);
    }
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
            /* Install or Repair while Thor Forever is not ready to play. */
            if (install_clicked(window)) return 0;
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
        case ID_SETTING:
        case ID_SETTING + 1:
        case ID_SETTING + 2:
            next_setting(window, &settings[LOWORD(wparam) - ID_SETTING]);
            return 0;
        case ID_QUIT:
        case IDCANCEL:
            if (!quit_while_installing(window)) return 0;
            DestroyWindow(window);
            PostQuitMessage(ID_QUIT);
            return 0;
        }
        break;
    case WM_TIMER:
        refresh();
        return 0;
    case WM_PAINT:
        paint_menu(window);
        return 0;
    case WM_ERASEBKGND:
        return 1;
    case WM_DRAWITEM:
        draw_button((const DRAWITEMSTRUCT *)lparam);
        return TRUE;
    case WM_CTLCOLORSTATIC: {
        HDC dc = (HDC)wparam;
        HWND control = (HWND)lparam;
        SetTextColor(dc, control == notice_text ? TF_WARNING : control == version_text ? TF_GOLD_LIGHT : TF_TEXT);
        SetBkColor(dc, TF_BACKGROUND);
        return (LRESULT)background_brush;
    }
    case WM_CLOSE:
        if (!quit_while_installing(window)) return 0;
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
    int u = sh / 24, w = sw * 3 / 5, h, x = u, y = u, bw, bh, i;
    if (u < 16) u = 16;
    if (w < 24 * u) w = 24 * u < sw ? 24 * u : sw;
    header_height = u * 17 / 4;
    h = header_height + u * 11;
    /* Cinzel from fonts/, for this program only; Tahoma when it is missing. */
    if (AddFontResourceExW(in_kit(L"\\fonts\\Cinzel-Bold.ttf"), FR_PRIVATE, 0)) heading_face = L"Cinzel";
    unit = u;
    button_font = CreateFontW(-u * 2 / 3, 0, 0, 0, FW_BOLD, 0, 0, 0, DEFAULT_CHARSET, 0, 0,
                              ANTIALIASED_QUALITY, 0, heading_face);
    label_font = CreateFontW(-u / 2, 0, 0, 0, FW_BOLD, 0, 0, 0, DEFAULT_CHARSET, 0, 0,
                             ANTIALIASED_QUALITY, 0, heading_face);
    background_brush = CreateSolidBrush(TF_BACKGROUND);
    font = CreateFontW(-u * 2 / 3, 0, 0, 0, FW_NORMAL, 0, 0, 0, DEFAULT_CHARSET, 0, 0,
                       CLEARTYPE_QUALITY, 0, L"Tahoma");
    wc.lpfnWndProc = window_proc;
    wc.hInstance = instance;
    wc.hCursor = LoadCursorW(NULL, (LPCWSTR)IDC_ARROW);
    wc.hbrBackground = background_brush;
    /* Repaint everything when the window grows for the note. */
    wc.style = CS_HREDRAW | CS_VREDRAW;
    wc.lpszClassName = L"ThorForeverMenu";
    RegisterClassW(&wc);
    window = CreateWindowExW(WS_EX_APPWINDOW, wc.lpszClassName, L"Thor Forever",
                             WS_POPUP | WS_SYSMENU,
                             (sw - w) / 2, (sh - h) / 2, w, h, NULL, NULL, instance, NULL);
    menu_window = window;
    menu_width = w;
    menu_height = h;
    notice_height = 5 * u;
    {
        RECT client;
        GetClientRect(window, &client);
        w = client.right;
    }
    y = header_height + u / 2;
    version_text = add_control(window, L"STATIC", L"", SS_LEFT, x, y, w - 2 * u, u, 0, font);
    y += u;
    status_text = add_control(window, L"STATIC", L"", SS_LEFT, x, y, w - 2 * u, u * 2, 0, font);
    y += u * 3;
    /* All six buttons share one size and style; Play is the teal one. */
    bw = (w - 4 * u) / 3;
    bh = u * 5 / 2;
    if (!read_text(in_kit(L"\\tuning.conf"), tuning, sizeof(tuning))) tuning[0] = 0;
    for (i = 0; i < SETTING_COUNT; ++i) {
        settings[i].button = add_control(window, L"BUTTON", L"", BS_OWNERDRAW | WS_TABSTOP,
                                         x + i * (bw + u), y, bw, bh, ID_SETTING + i, font);
        show_setting(&settings[i]);
    }
    y += bh + u / 2;
    play_button = add_control(window, L"BUTTON", L"Play", BS_OWNERDRAW | WS_TABSTOP,
                              x, y, bw, bh, ID_PLAY, button_font);
    add_control(window, L"BUTTON", L"Update with Battle.net", BS_OWNERDRAW | WS_TABSTOP,
                x + bw + u, y, bw, bh, ID_UPDATE, button_font);
    add_control(window, L"BUTTON", L"Quit", BS_OWNERDRAW | WS_TABSTOP,
                x + 2 * (bw + u), y, bw, bh, ID_QUIT, button_font);
    /* Shown only when the game is installed in more than one container. */
    y += bh + u;
    notice_text = add_control(window, L"STATIC", L"", SS_LEFT, x, y, w - 2 * u, u * 4, 0, font);
    ShowWindow(notice_text, SW_HIDE);
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
    DeleteObject(label_font);
    if (header_cache) DeleteObject(header_cache);
    header_cache = NULL;
    DeleteObject(button_font);
    DeleteObject(background_brush);
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
    file = CreateFileW(in_kit(L"\\logs\\launch-diag.txt"), GENERIC_WRITE, FILE_SHARE_READ, NULL,
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
    CreateDirectoryW(in_kit(L"\\logs"), NULL);
    swprintf(bridge_token, 80, L"%lu-%llu", GetCurrentProcessId(), GetTickCount64());
    swprintf(bridge_command, 1024, L"\"%ls\" /unix /system/bin/sh %ls/installer/entry.sh %ls%ls",
             start, kit_unix, bridge_token, wait ? L" wait" : L"");
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
    if (!read_text(in_kit(L"\\installer\\entry.sh"), script, sizeof(script))) return;
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
 * bridge lists the copies in logs\\ENTRY-<token>.copies ("HERE", "OTHER",
 * "LEFTOVER" or "ELSEWHERE" and the container's folder name; see
 * installer/game-copies.sh), and the start screen shows a note. It does not
 * offer to delete the other copy: on the device, a delete aimed at another
 * container from inside GameHub removed files elsewhere (the logs folder). */
static void show_notice(int on)
{
    int shown = IsWindowVisible(notice_text);
    RECT r;
    if (on == shown) return;
    ShowWindow(notice_text, on ? SW_SHOW : SW_HIDE);
    /* Grows the window, staying centered. */
    GetWindowRect(menu_window, &r);
    SetWindowPos(menu_window, NULL, r.left, r.top + (on ? -notice_height : notice_height) / 2,
                 menu_width, menu_height + (on ? notice_height : 0), SWP_NOZORDER);
}

static void refresh_copies(void)
{
    static char copies[4096];
    wchar_t path[512], name[24];
    char *line, *end, *rest;
    int other = 0, leftover = 0, elsewhere = 0, i;
    if (!bridge_waiting) return;
    entry_path(path, bridge_token, L"copies");
    if (!read_text(path, copies, sizeof(copies))) copies[0] = 0;
    name[0] = 0;
    for (line = copies; *line; line = *end ? end + 1 : end) {
        end = line + strcspn(line, "\r\n");
        rest = strchr(line, ' ');
        if (!rest || rest > end) continue;
        ++rest;
        if (!strncmp(line, "OTHER ", 6)) ++other;
        else if (!strncmp(line, "LEFTOVER ", 9)) ++leftover;
        else if (!strncmp(line, "ELSEWHERE ", 10)) ++elsewhere;
        else continue;
        if (!name[0]) {
            /* The start of the container's name is enough to recognise it. */
            for (i = 0; i < 14 && rest + i < end; ++i) name[i] = (unsigned char)rest[i];
            wcscpy(name + i, rest + i < end ? L"..." : L"");
        }
    }
    if (other || leftover) {
        swprintf(notice_buffer, 1024, other
                 ? L"The game is also installed in another GameHub container (%ls). You play from the "
                   L"copy in this container. To free its storage, delete that container in GameHub."
                 : L"Part of a game copy is still in another GameHub container (%ls). You play from the "
                   L"copy in this container. To free its storage, delete that container in GameHub.",
                 name);
        SetWindowTextW(notice_text, notice_buffer);
        show_notice(1);
    } else if (elsewhere) {
        SetWindowTextW(notice_text, L"The game is installed in other GameHub containers, but not in this "
                                    L"one. Start Thor Forever from the container you play in.");
        show_notice(1);
    } else {
        show_notice(0);
    }
}

/* Install and Repair. The waiting bridge writes logs\\ENTRY-<token>.state
 * (installer/install-state.sh): STATE installed|missing|broken, GAME
 * found|missing|multiple, PAYLOAD ok|missing <files>. When it is not
 * installed, Play becomes Install (or Repair); pressing it asks the bridge
 * (.install / .repair) to run installer/start-install.sh. While that runs,
 * .progress holds "<uptime> <phase>"; the result comes in .installed. */
enum { STATE_UNKNOWN, STATE_INSTALLED, STATE_MISSING, STATE_BROKEN };
static int install_state, game_state, payload_ok, installing;
static char payload_missing[256];
static unsigned long install_beat;
static ULONGLONG install_seen;
static wchar_t install_message[512];

static void read_state(void)
{
    static char data[1024];
    wchar_t path[512];
    char *line, *end;
    entry_path(path, bridge_token, L"state");
    if (!read_text(path, data, sizeof(data))) return;
    payload_ok = 0;
    for (line = data; *line; line = *end ? end + 1 : end) {
        end = line + strcspn(line, "\r\n");
        if (!strncmp(line, "STATE installed", 15)) install_state = STATE_INSTALLED;
        else if (!strncmp(line, "STATE missing", 13)) install_state = STATE_MISSING;
        else if (!strncmp(line, "STATE broken", 12)) install_state = STATE_BROKEN;
        else if (!strncmp(line, "GAME found", 10)) game_state = 1;
        else if (!strncmp(line, "GAME multiple", 13)) game_state = 2;
        else if (!strncmp(line, "GAME missing", 12)) game_state = 0;
        else if (!strncmp(line, "PAYLOAD ok", 10)) payload_ok = 1;
        else if (!strncmp(line, "PAYLOAD missing", 15)) {
            size_t n = (size_t)(end - line) - 15;
            if (n >= sizeof(payload_missing)) n = sizeof(payload_missing) - 1;
            memcpy(payload_missing, line + 15, n);
            payload_missing[n] = 0;
        }
    }
}

static const wchar_t *phase_text(const char *phase, int *step)
{
    static const char *const names[] = {
        "payload", "storage", "extraction", "components", "prefix", "dxvk", "game", "prepared"
    };
    static const wchar_t *const texts[] = {
        L"checking the install files", L"checking free storage", L"unpacking Wine",
        L"copying the graphics driver", L"setting up the Windows environment", L"installing DXVK",
        L"preparing the game and its settings", L"finishing"
    };
    int i;
    for (i = 0; i < 8; ++i)
        if (!strcmp(phase, names[i])) { *step = i + 1; return texts[i]; }
    *step = 0;
    return L"starting";
}

/* What is needed before installing, or 0 if everything is there. */
static int install_blocker(wchar_t *text, size_t size)
{
    wchar_t files[256];
    int i;
    if (game_state == 0) {
        swprintf(text, size, L"The game is not installed in this GameHub container. Install it with "
                 L"Battle.net first (Update with Battle.net), then come back here.");
        return 1;
    }
    if (game_state == 2) {
        swprintf(text, size, L"The game is in several GameHub containers, but not in this one. "
                 L"Start Thor Forever from the container you play in.");
        return 1;
    }
    if (!payload_ok) {
        for (i = 0; payload_missing[i] && i < 255; ++i) files[i] = (unsigned char)payload_missing[i];
        files[i] = 0;
        swprintf(text, size, L"These install files are missing in the Thor-Forever folder's payload folder:%ls. "
                 L"Extract the complete Thor Forever package again.", files);
        return 1;
    }
    return 0;
}

/* Updates the start screen for installing; returns 1 if it uses the note. */
static int refresh_install(void)
{
    static char data[4096];
    static wchar_t text[1024], details[4096];
    wchar_t path[512];
    if (!bridge_waiting) return 0;
    if (installing) {
        entry_path(path, bridge_token, L"installed");
        if (read_text(path, data, sizeof(data))) {
            char *rest = strchr(data, '\n');
            int code = atoi(data);
            /* Left for the bridge, which removes it before the next run. */
            installing = 0;
            install_state = STATE_UNKNOWN;
            if (!rest || !MultiByteToWideChar(CP_UTF8, 0, rest + 1, -1, details, 3000)) details[0] = 0;
            details[3000] = 0;
            for (size_t n = wcslen(details); n && (details[n - 1] == '\n' || details[n - 1] == '\r' ||
                                                   details[n - 1] == ' '); --n)
                details[n - 1] = 0;
            if (code == 0) {
                swprintf(install_message, 512, L"%ls Press Play to start the game.", details);
            } else {
                swprintf(install_message, 512, L"Installing stopped (code %d). Press Repair to try again.", code);
                swprintf(text, 1024, L"%ls\n\nDetails:\n", install_message);
                wcsncat(text, details, 1023 - wcslen(text));
                MessageBoxW(menu_window, text, L"Thor Forever", MB_OK | MB_ICONWARNING);
            }
        } else {
            unsigned long beat = 0;
            char phase[64] = "";
            int step;
            entry_path(path, bridge_token, L"progress");
            if (read_text(path, data, 128) && sscanf(data, "%lu %63s", &beat, phase) == 2 && beat != install_beat) {
                const wchar_t *what = phase_text(phase, &step);
                install_beat = beat;
                install_seen = GetTickCount64();
                if (step)
                    swprintf(text, 1024, L"Installing, step %d of 8: %ls. This takes a few minutes; "
                             L"leave Thor Forever open.", step, what);
                else
                    swprintf(text, 1024, L"Installing: %ls. This takes a few minutes; leave Thor Forever open.", what);
                SetWindowTextW(notice_text, text);
            } else if (GetTickCount64() - install_seen > 90000) {
                installing = 0;
                install_state = STATE_UNKNOWN;
                swprintf(install_message, 512, L"Installing stopped responding. Close Thor Forever, start it "
                         L"again from GameHub and press Repair.");
            }
            SetWindowTextW(status_text, L"Installing Thor Forever...");
            show_notice(1);
            return 1;
        }
    }
    read_state();
    EnableWindow(play_button, TRUE);
    switch (install_state) {
    case STATE_MISSING:
        SetWindowTextW(play_button, L"Install");
        SetWindowTextW(status_text, L"Thor Forever is not installed in this GameHub container yet.");
        if (!install_blocker(text, 1024))
            swprintf(text, 1024, L"%ls%lsEverything needed is there. Press Install: it takes a few minutes "
                     L"and needs about 3 GB of free storage.", install_message, install_message[0] ? L" " : L"");
        break;
    case STATE_BROKEN:
        SetWindowTextW(play_button, L"Repair");
        SetWindowTextW(status_text, L"The Thor Forever installation is unfinished or damaged.");
        if (!install_blocker(text, 1024))
            swprintf(text, 1024, L"%ls%lsRepair sets the damaged installation aside (nothing is deleted), "
                     L"installs again and keeps your game settings.", install_message, install_message[0] ? L" " : L"");
        break;
    default:
        SetWindowTextW(play_button, L"Play");
        if (!install_message[0]) return 0;
        wcscpy(text, install_message);
        break;
    }
    SetWindowTextW(notice_text, text);
    show_notice(1);
    return 1;
}

/* Quit while installing: asks first. Returns 1 to quit. */
static int quit_while_installing(HWND window)
{
    if (!installing) return 1;
    return MessageBoxW(window, L"Thor Forever is still installing. If you quit now, the installation may stay "
                       L"unfinished; Repair can redo it next time.\n\nQuit anyway?",
                       L"Thor Forever", MB_YESNO | MB_ICONWARNING | MB_DEFBUTTON2) == IDYES;
}

/* Play pressed: starts Install or Repair instead when needed. Returns 1 if
 * it handled the click. */
static int install_clicked(HWND window)
{
    wchar_t path[512], text[1024];
    if (installing) return 1;
    if (install_state != STATE_MISSING && install_state != STATE_BROKEN) return 0;
    if (install_blocker(text, 1024)) {
        MessageBoxW(window, text, L"Thor Forever", MB_OK | MB_ICONINFORMATION);
        return 1;
    }
    if (install_state == STATE_BROKEN &&
        MessageBoxW(window, L"Repair Thor Forever?\n\nThe damaged installation is set aside (nothing is deleted), "
                    L"a new one is made, and your game settings are copied over. This takes a few minutes.",
                    L"Thor Forever", MB_YESNO | MB_ICONQUESTION) != IDYES)
        return 1;
    entry_path(path, bridge_token, install_state == STATE_BROKEN ? L"repair" : L"install");
    if (!touch(path)) {
        MessageBoxW(window, L"Could not start the installation.", L"Thor Forever", MB_OK | MB_ICONERROR);
        return 1;
    }
    installing = 1;
    install_beat = 0;
    install_seen = GetTickCount64();
    install_message[0] = 0;
    EnableWindow(play_button, FALSE);
    SetWindowTextW(play_button, L"Installing...");
    SetWindowTextW(notice_text, L"Installing: starting.");
    return 1;
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
    if (!find_kit()) {
        wchar_t text[3 * MAX_PATH + 400];
        swprintf(text, 3 * MAX_PATH + 400,
                 L"Thor Forever cannot find the Android path of the folder it is in. Use a folder in your device's "
                 L"storage (for example Download/Thor-Forever) whose path has only letters, digits, - _ and . (no spaces).\n\n"
                 L"Folder: %ls\nWine calls it: %ls", KIT, wine_name[0] ? wine_name : L"(no answer)");
        MessageBoxW(NULL, text, L"Thor Forever", MB_OK | MB_ICONERROR);
        return 2;
    }
    if (GetFileAttributesW(in_kit(L"\\installer\\entry.sh")) == INVALID_FILE_ATTRIBUTES) {
        MessageBoxW(NULL, L"Required files are missing. Extract the complete package again, so that the installer "
                    L"and payload folders are next to Thor-Forever.exe.", L"Thor Forever", MB_OK | MB_ICONERROR);
        return 2;
    }
    prepare_bridge();
    if (show_menu(instance) != ID_PLAY) {
        cancel_bridge();
        return 0;
    }
    return run_game();
}
