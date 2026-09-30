"""power-report: summarise the power-log sampler's output.

Reads samples-*.jsonl and marks.jsonl from --dir (default
/var/lib/power-log), read-only. Prints coverage, time-weighted
battery/RAPL/GPU means per bucket, suspend drain, and top cgroups.

The per-cgroup figures are ESTIMATES: package energy split by CPU-time
share. Display, GPU and radios are not attributed to anyone.
"""
import argparse
import bisect
import glob
import json
import os
import re
import sys
import time
from collections import defaultdict
from datetime import datetime

COLS = ("bat_discharge_w", "rapl_pkg_w", "gpu_w")
MIN_H = 5 / 60
NUM = re.compile(r"^(-?[\d.]+|n/a)$")


def load(path, bad):
    out = []
    try:
        with open(path) as f:
            for line in f:
                if not line.strip():
                    continue
                try:
                    obj = json.loads(line)
                    float(obj["ts"])
                except (ValueError, KeyError, TypeError):
                    bad[0] += 1
                    continue
                if isinstance(obj, dict):
                    out.append(obj)
                else:
                    bad[0] += 1
    except FileNotFoundError:
        pass
    except OSError as e:
        print(f"power-report: {path}: {e}", file=sys.stderr)
    return out


def ftime(ts):
    return datetime.fromtimestamp(ts).strftime("%Y-%m-%d %H:%M")


def fnum(x, fmt="{:.2f}"):
    return "n/a" if x is None else fmt.format(x)


def table(header, rows):
    if not rows:
        print("  (none)")
        return
    rows = [header] + rows
    w = [max(len(str(r[i])) for r in rows) for i in range(len(header))]
    for n, r in enumerate(rows):
        cells = [str(c).rjust(w[i]) if NUM.match(str(c))
                 else str(c).ljust(w[i]) for i, c in enumerate(r)]
        print("  " + "  ".join(cells).rstrip())
        if n == 0:
            print("  " + "  ".join("-" * x for x in w))


def weighted(samples):
    """(hours, n, {col: time-weighted mean or None}) over tick samples."""
    tot = 0.0
    acc = {c: [0.0, 0.0] for c in COLS}
    for s in samples:
        dt = s.get("interval_s")
        if not dt or dt <= 0:
            continue
        tot += dt
        for c in COLS:
            v = s.get(c)
            if v is not None:
                acc[c][0] += v * dt
                acc[c][1] += dt
    means = {c: a[0] / a[1] if a[1] else None for c, a in acc.items()}
    return tot / 3600, len(samples), means


def stats_row(label, samples):
    h, n, m = weighted(samples)
    return h, [label, f"{h:.2f}", n] + [fnum(m[c]) for c in COLS]


def onoff(v, name):
    return "?" if v is None else (name if v else "no-" + name)


def context_key(s):
    b = s.get("brightness_pct")
    band = "?" if b is None else f"{min(int(b) // 25, 3) * 25}-" \
        f"{min(int(b) // 25, 3) * 25 + 25}%"
    return ("AC" if s.get("ac") else "bat" if s.get("ac") is False
            else "ac?",
            s.get("profile") or "?",
            onoff(s.get("screen_on"), "screen"),
            f"lid-{s.get('lid') or '?'}",
            "br" + band,
            onoff(s.get("panel_power_savings"), "pps"),
            onoff(s.get("bt_blocked"), "bt-off"),
            onoff(s.get("wifi_powersave"), "wifi-ps"))


STAT_HDR = ["hours", "samples", "bat_W", "pkg_W", "gpu_W"]


def report_buckets(ticks, by, marks, end_ts):
    groups = defaultdict(list)
    if by == "context":
        head = ["ac", "profile", "screen", "lid", "brightness",
                "pps", "bt", "wifi"]
        for s in ticks:
            groups[context_key(s)].append(s)
    elif by == "gen":
        head = ["gen", "ac", "screen"]
        for s in ticks:
            groups[(s.get("gen") or "?",
                    "AC" if s.get("ac") else "bat",
                    onoff(s.get("screen_on"), "screen"))].append(s)
    else:
        return report_marks(ticks, marks, end_ts)
    rows = []
    for k, v in groups.items():
        h, r = stats_row(" ".join(k), v)
        if h >= MIN_H:
            rows.append((h, list(k) + r[1:]))
    rows.sort(key=lambda x: -x[0])
    print(f"\n== Buckets by {by} (time-weighted means; "
          "buckets < 5 min hidden) ==")
    table(head + STAT_HDR, [r for _, r in rows])


def report_marks(ticks, marks, end_ts):
    print("\n== Buckets by mark (window = mark to next mark) ==")
    marks = sorted(marks, key=lambda m: m["ts"])
    times = [s["ts"] for s in ticks]
    rows = []
    for i, m in enumerate(marks):
        if m.get("label") == "end":
            continue
        a = m["ts"]
        b = marks[i + 1]["ts"] if i + 1 < len(marks) else end_ts
        win = ticks[bisect.bisect_left(times, a):
                    bisect.bisect_left(times, b)]
        _, r = stats_row(str(m.get("label")), win)
        rows.append([r[0], ftime(a), f"{(b - a) / 3600:.2f}"] + r[1:])
    table(["label", "start", "dur_h", "hours", "samples"]
          + STAT_HDR[2:], rows)


def report_coverage(samples, ticks):
    print("== Coverage ==")
    if not samples:
        print("  no samples")
        return
    hrs = defaultdict(float)
    for s in ticks:
        dt = s.get("interval_s") or 0
        hrs["AC" if s.get("ac") else "bat"
            if s.get("ac") is False else "unknown"] += dt / 3600
    gens = sorted({s.get("gen") for s in samples if s.get("gen")})
    print(f"  span:     {ftime(samples[0]['ts'])} .. "
          f"{ftime(samples[-1]['ts'])}")
    print(f"  samples:  {len(samples)} ({len(ticks)} ticks)")
    print(f"  on battery {hrs['bat']:.1f} h, on AC {hrs['AC']:.1f} h"
          + (f", unknown {hrs['unknown']:.1f} h" if hrs["unknown"] else ""))
    print(f"  generations: {len(gens)}: {', '.join(gens)}")


def report_suspend(samples):
    print("\n== Suspend drain ==")
    rows = []
    pend = {}
    for s in samples:
        boot = s.get("boot_id")
        if s.get("kind") == "suspend":
            pend[boot] = s
        elif s.get("kind") == "resume" and boot in pend:
            a = pend.pop(boot)
            h = (s["ts"] - a["ts"]) / 3600
            if h <= 0:
                continue
            dp = None
            if a.get("bat_pct") is not None \
                    and s.get("bat_pct") is not None:
                dp = a["bat_pct"] - s["bat_pct"]
            mw = None
            qa, qb = a.get("bat_charge_uah"), s.get("bat_charge_uah")
            va, vb = a.get("bat_voltage_uv"), s.get("bat_voltage_uv")
            if None not in (qa, qb, va, vb):
                mw = (qa - qb) / 1e6 * (va + vb) / 2e6 * 1000 / h
            rows.append([ftime(a["ts"]), f"{h:.2f}", fnum(dp, "{:d}"),
                         fnum(None if dp is None else dp / h),
                         fnum(mw, "{:.0f}")])
    table(["suspended", "hours", "d_bat_%", "%/h", "avg_mW"], rows)


def short_cg(cg):
    cg = cg.strip("/")
    cg = re.sub(r"^user\.slice/user-\d+\.slice/user@\d+\.service/", "",
                cg)
    cg = re.sub(r"(-\d+)+\.(scope|service)$", r".\2", cg)
    cg = cg.replace("\\x2d", "-")
    return cg or "/"


def report_cgroups(ticks):
    print("\n== Top cgroups (ESTIMATE: package energy split by CPU-time "
          "share; ignores display/GPU/radio) ==")
    wh = defaultdict(float)
    cpu = defaultdict(float)
    for s in ticks:
        j, tot = s.get("rapl_pkg_j"), s.get("cpu_total_s")
        if j is None or not tot or tot <= 0:
            continue
        for c in s.get("cgroups") or []:
            name = short_cg(c["cg"])
            cpu[name] += c["cpu_s"]
            wh[name] += j * c["cpu_s"] / tot / 3600
    top = sorted(wh, key=lambda k: -wh[k])[:15]
    table(["cgroup", "cpu_s", "Wh"],
          [[k, f"{cpu[k]:.0f}", f"{wh[k]:.3f}"] for k in top])


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--dir", default="/var/lib/power-log")
    ap.add_argument("--since", type=float, metavar="DAYS")
    ap.add_argument("--by", choices=("context", "gen", "mark"),
                    default="context")
    a = ap.parse_args()
    bad = [0]
    samples = []
    for p in sorted(glob.glob(os.path.join(a.dir, "samples-*.jsonl"))):
        samples += load(p, bad)
    marks = load(os.path.join(a.dir, "marks.jsonl"), bad)
    if a.since is not None:
        cut = time.time() - a.since * 86400
        samples = [s for s in samples if s["ts"] >= cut]
        marks = [m for m in marks if m["ts"] >= cut]
    samples.sort(key=lambda s: s["ts"])
    ticks = [s for s in samples if s.get("kind") == "tick"]
    if bad[0]:
        print(f"power-report: skipped {bad[0]} malformed lines",
              file=sys.stderr)
    report_coverage(samples, ticks)
    end_ts = samples[-1]["ts"] if samples else time.time()
    report_buckets(ticks, a.by, marks, end_ts)
    report_suspend(samples)
    report_cgroups(ticks)


if __name__ == "__main__":
    main()
