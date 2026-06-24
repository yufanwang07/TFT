import os
import sys
import glob
import time
import ctypes
import threading

import numpy as np
import cv2
import mss

import win32gui
import win32con
import win32api


FEAT = 28
MATCH_THRESHOLD = 0.65
OCCUPANCY_STD = 22.0
ICON_1080 = 34
SEARCH_SHIFTS = (-6, -4, -2, 0, 2, 4, 6)
FINE_SHIFTS = (-1, 0, 1)


def rects_from_geo(geo):
    rects = []
    pitch = geo["pitch"]
    w = geo["slot_w"]
    for ci, cx in enumerate(geo["col_x"]):
        for r in range(geo["n_slots"]):
            y = int(round(geo["first_y"] + r * pitch))
            rects.append((ci, r, int(cx), y, int(w)))
    return rects


def autodetect_bench(img):
    H, W = img.shape[:2]
    strip_w = int(W * 0.11)
    strip = img[:, :strip_w]
    gray = cv2.cvtColor(strip, cv2.COLOR_BGR2GRAY).astype(np.float32)

    gx = np.abs(cv2.Sobel(gray, cv2.CV_32F, 1, 0, ksize=3)).mean(axis=0)
    if gx.max() < 1e-3:
        return None
    th = gx.max() * 0.4
    xs = np.where(gx[3:] > th)[0] + 3
    left = int(xs[0]) if len(xs) else int(9 * W / 1920)

    vmap = np.abs(cv2.Sobel(gray, cv2.CV_32F, 1, 0, ksize=3))

    cx0, cx1 = left + 3, min(left + 36, strip_w)
    coldark = gray[:, cx0:cx1].mean(axis=1)
    is_dark = coldark < 18.0

    raw = []
    i = 0
    while i < H:
        if is_dark[i]:
            j = i
            while j < H and is_dark[j]:
                j += 1
            raw.append(((i + j) // 2, j - i))
            i = j
        else:
            i += 1
    min_h = int(round(20 * H / 1080))
    max_h = int(round(60 * H / 1080))
    bands = [(c, h) for c, h in raw if min_h <= h <= max_h]

    if len(bands) >= 2:
        centers = [c for c, h in bands]
        diffs = np.diff(centers)
        good = diffs[(diffs > 25) & (diffs < 90)]
        pitch = int(round(np.median(good))) if len(good) else int(round(51 * H / 1080))
        sw = max(int(np.median([h for c, h in bands])), int(pitch * 0.74))
        top_black = centers[0]
        bot_black = centers[-1]
    else:
        return None

    band = vmap[:, max(0, left) : min(left + int(pitch), strip_w)]
    rfe = band.max(axis=1)
    rfe_th = max(6.0, float(np.median(rfe)) * 1.5)
    dark_centers = [c for c, h in bands]

    def near_dark_band(cy):
        return any(abs(cy - c) <= pitch * 0.4 for c in dark_centers)

    def is_slot_row(cy):
        y0, y1 = cy - sw // 2, cy + sw // 2
        if y0 < 0 or y1 > H:
            return False
        interior = gray[y0:y1, left + 3 : min(left + sw, strip_w)]
        if interior.size == 0:
            return False
        if interior.mean() < 22:
            return near_dark_band(cy) or float((rfe[y0:y1] > rfe_th).mean()) > 0.3
        return float((rfe[y0:y1] > rfe_th).mean()) > 0.3

    MAX_SLOTS = 10
    centers_down = []
    c = top_black
    hard_limit = min(bot_black + pitch // 2, H - sw // 2)
    while c <= hard_limit and len(centers_down) < MAX_SLOTS:
        centers_down.append(c)
        c += pitch
    while centers_down and not is_slot_row(centers_down[-1]):
        centers_down.pop()

    centers_up = []
    c = top_black - pitch
    while c - sw // 2 >= 0 and is_slot_row(c):
        centers_up.append(c)
        c -= pitch
    centers_up.reverse()

    allc = centers_up + centers_down
    if not allc:
        return None

    first_y = allc[0] - sw // 2
    icon_x = left + 2
    return dict(
        col_x=[icon_x, icon_x + pitch],
        slot_w=int(sw),
        first_y=int(first_y),
        pitch=float(pitch),
        n_slots=len(allc),
        left=int(left),
    )


def feature_vector(bgr):
    tile = cv2.resize(bgr, (FEAT, FEAT), interpolation=cv2.INTER_AREA)
    v = tile.astype(np.float32).reshape(-1)
    v -= v.mean()
    n = np.linalg.norm(v)
    if n < 1e-6:
        return None
    return v / n


def load_templates(items_dir):
    paths = sorted(glob.glob(os.path.join(items_dir, "*.*")))
    names, vecs = [], []
    for p in paths:
        img = cv2.imread(p, cv2.IMREAD_UNCHANGED)
        if img is None:
            continue
        if img.ndim == 3 and img.shape[2] == 4:
            alpha = img[:, :, 3:4] / 255.0
            img = (img[:, :, :3] * alpha).astype(np.uint8)
        elif img.ndim == 2:
            img = cv2.cvtColor(img, cv2.COLOR_GRAY2BGR)
        else:
            img = img[:, :, :3]
        img = cv2.resize(img, (ICON_1080, ICON_1080), interpolation=cv2.INTER_AREA)
        v = feature_vector(img)
        if v is None:
            continue
        names.append(os.path.splitext(os.path.basename(p))[0])
        vecs.append(v)
    if not vecs:
        return [], np.empty((0, FEAT * FEAT * 3), np.float32)
    return names, np.stack(vecs).astype(np.float32)


def _occupied(frame, x, y, w):
    cell = frame[y : y + w, x : x + w]
    if cell.shape[0] != w or cell.shape[1] != w:
        return False
    return cell.std() >= OCCUPANCY_STD


def _slot_candidates(frame, cx, cy, ts, shifts):
    H, W = frame.shape[:2]
    out, offs = [], []
    for dy in shifts:
        yy = cy + dy
        if yy < 0 or yy + ts > H:
            continue
        for dx in shifts:
            xx = cx + dx
            if xx < 0 or xx + ts > W:
                continue
            v = feature_vector(frame[yy : yy + ts, xx : xx + ts])
            if v is not None:
                out.append(v)
                offs.append((dx, dy))
    return out, offs


def detect_items(frame, names, templates, rects):
    col1 = [r for r in rects if r[0] == 0]
    col2 = [r for r in rects if r[0] == 1]
    n_slots = len(col1)

    col1_occ = [r for r in col1 if _occupied(frame, r[2], r[3], r[4])]
    active = list(col1_occ)
    if n_slots and len(col1_occ) == n_slots:
        active += [r for r in col2 if _occupied(frame, r[2], r[3], r[4])]

    if not active or not templates.shape[0]:
        return []

    H = frame.shape[0]
    ts = max(12, int(round(ICON_1080 * H / 1080)))
    coarse = [int(round(s * H / 1080)) for s in SEARCH_SHIFTS]
    fine = [int(round(s * H / 1080)) for s in FINE_SHIFTS]

    detections = []
    for ci, r, x, y, w in active:
        cx = x + (w - ts) // 2
        cy = y + (w - ts) // 2

        cands, offs = _slot_candidates(frame, cx, cy, ts, coarse)
        if not cands:
            continue
        V = np.stack(cands)
        S = V @ templates.T
        si, _ = np.unravel_index(int(S.argmax()), S.shape)
        bdx, bdy = offs[si]

        cands2, _ = _slot_candidates(frame, cx + bdx, cy + bdy, ts, fine)
        V2 = np.stack(cands2) if cands2 else V
        best_per_tpl = (V2 @ templates.T).max(axis=0)
        k = int(best_per_tpl.argmax())
        sc = float(best_per_tpl[k])
        if sc < MATCH_THRESHOLD:
            continue
        detections.append(
            {
                "col": ci,
                "row": r,
                "x": x,
                "y": y,
                "w": w,
                "name": names[k],
                "score": sc,
            }
        )
    return detections


EXCLUDE_FROM_CAPTURE = "--no-exclude-capture" not in sys.argv

TARGET_FPS = 1.0
if "--fps" in sys.argv:
    try:
        TARGET_FPS = float(sys.argv[sys.argv.index("--fps") + 1])
    except (ValueError, IndexError):
        pass


gdi32 = ctypes.windll.gdi32
user32 = ctypes.windll.user32


class BITMAPINFOHEADER(ctypes.Structure):
    _fields_ = [
        ("biSize", ctypes.c_uint32),
        ("biWidth", ctypes.c_int32),
        ("biHeight", ctypes.c_int32),
        ("biPlanes", ctypes.c_uint16),
        ("biBitCount", ctypes.c_uint16),
        ("biCompression", ctypes.c_uint32),
        ("biSizeImage", ctypes.c_uint32),
        ("biXPelsPerMeter", ctypes.c_int32),
        ("biYPelsPerMeter", ctypes.c_int32),
        ("biClrUsed", ctypes.c_uint32),
        ("biClrImportant", ctypes.c_uint32),
    ]


class BITMAPINFO(ctypes.Structure):
    _fields_ = [("bmiHeader", BITMAPINFOHEADER), ("bmiColors", ctypes.c_uint32 * 3)]


class ScreenGrabber(threading.Thread):
    """Background thread holding the most recent monitor frame (BGR)."""

    def __init__(self, monitor_index=1):
        super().__init__(daemon=True)
        self.monitor_index = monitor_index
        self.lock = threading.Lock()
        self.frame = None
        self.running = True
        self.region = None

    def run(self):
        with mss.MSS() as sct:
            mon = sct.monitors[self.monitor_index]
            self.region = (mon["left"], mon["top"], mon["width"], mon["height"])
            while self.running:
                shot = sct.grab(mon)
                arr = np.frombuffer(shot.raw, np.uint8).reshape(
                    shot.height, shot.width, 4
                )
                bgr = arr[:, :, :3]
                with self.lock:
                    self.frame = bgr.copy()

    def latest(self):
        with self.lock:
            return None if self.frame is None else self.frame

    def stop(self):
        self.running = False


class Overlay:
    def __init__(self, x, y, w, h, exclude_from_capture=False):
        self.x, self.y, self.w, self.h = x, y, w, h
        self.exclude_from_capture = exclude_from_capture
        self.hwnd = self._create_window()
        self._init_dib()

    def _create_window(self):
        hInstance = win32api.GetModuleHandle(None)
        class_name = "TFTItemOverlay"

        wc = win32gui.WNDCLASS()
        wc.lpfnWndProc = win32gui.DefWindowProc
        wc.hInstance = hInstance
        wc.lpszClassName = class_name
        wc.hbrBackground = 0
        try:
            win32gui.RegisterClass(wc)
        except win32gui.error:
            pass

        ex_style = (
            win32con.WS_EX_LAYERED
            | win32con.WS_EX_TRANSPARENT
            | win32con.WS_EX_TOPMOST
            | win32con.WS_EX_TOOLWINDOW
        )
        style = win32con.WS_POPUP

        hwnd = win32gui.CreateWindowEx(
            ex_style,
            class_name,
            "TFT Overlay",
            style,
            self.x,
            self.y,
            self.w,
            self.h,
            0,
            0,
            hInstance,
            None,
        )

        if self.exclude_from_capture:
            WDA_EXCLUDEFROMCAPTURE = 0x00000011
            if not user32.SetWindowDisplayAffinity(hwnd, WDA_EXCLUDEFROMCAPTURE):
                user32.SetWindowDisplayAffinity(hwnd, 0x00000001)

        win32gui.ShowWindow(hwnd, win32con.SW_SHOWNOACTIVATE)
        return hwnd

    _HWND_TOPMOST = -1
    _SWP_FLAGS = 0x0001 | 0x0002 | 0x0010 | 0x0040

    def topmost(self):
        win32gui.SetWindowPos(
            self.hwnd, self._HWND_TOPMOST, 0, 0, 0, 0, self._SWP_FLAGS
        )

    def _init_dib(self):
        self.screen_dc = user32.GetDC(0)
        self.mem_dc = gdi32.CreateCompatibleDC(self.screen_dc)

        bmi = BITMAPINFO()
        bmi.bmiHeader.biSize = ctypes.sizeof(BITMAPINFOHEADER)
        bmi.bmiHeader.biWidth = self.w
        bmi.bmiHeader.biHeight = -self.h
        bmi.bmiHeader.biPlanes = 1
        bmi.bmiHeader.biBitCount = 32
        bmi.bmiHeader.biCompression = 0

        self.bits_ptr = ctypes.c_void_p()
        self.hbmp = gdi32.CreateDIBSection(
            self.mem_dc, ctypes.byref(bmi), 0, ctypes.byref(self.bits_ptr), None, 0
        )
        self.old_bmp = gdi32.SelectObject(self.mem_dc, self.hbmp)
        self.buf_size = self.w * self.h * 4

    def update(self, bgra):
        if not bgra.flags["C_CONTIGUOUS"]:
            bgra = np.ascontiguousarray(bgra)
        ctypes.memmove(self.bits_ptr, bgra.ctypes.data, self.buf_size)

        size = (self.w, self.h)
        src = (0, 0)
        pos = (self.x, self.y)
        blend = (win32con.AC_SRC_OVER, 0, 255, win32con.AC_SRC_ALPHA)

        win32gui.UpdateLayeredWindow(
            self.hwnd,
            self.screen_dc,
            pos,
            size,
            self.mem_dc,
            src,
            0,
            blend,
            win32con.ULW_ALPHA,
        )

    def destroy(self):
        gdi32.SelectObject(self.mem_dc, self.old_bmp)
        gdi32.DeleteObject(self.hbmp)
        gdi32.DeleteDC(self.mem_dc)
        user32.ReleaseDC(0, self.screen_dc)
        win32gui.DestroyWindow(self.hwnd)


def render_layer(w, h, detections, found=True):
    layer = np.zeros((h, w, 4), np.uint8)

    if not found:
        msg = "Cannot find items"
        org = (20, 60)
        cv2.putText(
            layer,
            msg,
            org,
            cv2.FONT_HERSHEY_SIMPLEX,
            0.9,
            (0, 0, 0, 255),
            4,
            cv2.LINE_AA,
        )
        cv2.putText(
            layer,
            msg,
            org,
            cv2.FONT_HERSHEY_SIMPLEX,
            0.9,
            (0, 0, 255, 255),
            2,
            cv2.LINE_AA,
        )

    for d in detections:
        x, y, bw = d["x"], d["y"], d["w"]
        col = (0, 255, 0)
        cv2.rectangle(layer, (x, y), (x + bw, y + bw), col + (255,), 2)
        label = f"{d['name']} {d['score']:.2f}"
        ty = y + bw // 2
        cv2.putText(
            layer,
            label,
            (x + bw + 4, ty),
            cv2.FONT_HERSHEY_SIMPLEX,
            0.45,
            (0, 0, 0, 255),
            3,
            cv2.LINE_AA,
        )
        cv2.putText(
            layer,
            label,
            (x + bw + 4, ty),
            cv2.FONT_HERSHEY_SIMPLEX,
            0.45,
            col + (255,),
            1,
            cv2.LINE_AA,
        )

    a = layer[:, :, 3:4].astype(np.float32) / 255.0
    layer[:, :, :3] = (layer[:, :, :3].astype(np.float32) * a).astype(np.uint8)
    return layer


def main_loop(run_seconds=0):
    names, templates = load_templates("items")
    print(f"Loaded {len(names)} templates.")

    grabber = ScreenGrabber(monitor_index=1)
    grabber.start()
    while grabber.region is None or grabber.latest() is None:
        time.sleep(0.01)
    left, top, W, H = grabber.region
    print(f"Overlaying monitor region {W}x{H} at ({left},{top}). Ctrl+C to quit.")

    geo = autodetect_bench(grabber.latest())
    if geo:
        rects = rects_from_geo(geo)
        print(
            f"Auto-detected bench: first_y={geo['first_y']} pitch={geo['pitch']:.0f} "
            f"slots={geo['n_slots']} slot_w={geo['slot_w']}"
        )
    else:
        rects = None
        print("Cannot find items.")

    overlay = Overlay(left, top, W, H, exclude_from_capture=EXCLUDE_FROM_CAPTURE)
    overlay.topmost()

    n = 0
    detect_ms = 0.0
    last_report = time.perf_counter()
    start = last_report
    last_geo = last_report
    fps_count = 0
    try:
        while True:
            if run_seconds and (time.perf_counter() - start) >= run_seconds:
                print("\nTimed run complete.")
                break
            frame = grabber.latest()
            if frame is None:
                time.sleep(0.005)
                continue

            now0 = time.perf_counter()
            if now0 - last_geo >= 2.0:
                g = autodetect_bench(frame)
                rects = rects_from_geo(g) if g else None
                last_geo = now0

            t0 = time.perf_counter()
            dets = detect_items(frame, names, templates, rects) if rects else []
            detect_ms += (time.perf_counter() - t0) * 1000.0
            n += 1
            fps_count += 1

            layer = render_layer(W, H, dets, found=rects is not None)
            overlay.update(layer)

            win32gui.PumpWaitingMessages()
            overlay.topmost()

            now = time.perf_counter()
            if now - last_report >= 1.0:
                print(
                    f"  overlay {fps_count} fps | detect {detect_ms / n:.3f} ms/frame "
                    f"| {len(dets)} items",
                    end="\r",
                )
                fps_count = 0
                last_report = now

            if TARGET_FPS > 0:
                spent = time.perf_counter() - t0
                rest = (1.0 / TARGET_FPS) - spent
                if rest > 0:
                    time.sleep(rest)
    except KeyboardInterrupt:
        print("\nStopping...")
    finally:
        grabber.stop()
        overlay.destroy()


if __name__ == "__main__":
    secs = 0
    if len(sys.argv) > 1:
        try:
            secs = float(sys.argv[1])
        except ValueError:
            secs = 0
    main_loop(run_seconds=secs)
