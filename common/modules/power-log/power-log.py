"""power-log: append one power sample (JSON line) or a mark.

samples-YYYY-MM.jsonl, one object per line, every key always present,
null when unreadable:
  ts, kind (tick|suspend|resume), boot_id, gen (system generation),
  interval_s (since previous sample this boot; null on the first)
  ac, bat_status, bat_pct, bat_charge_uah, bat_voltage_uv,
  bat_w (instant; + discharging, - charging),
  bat_discharge_w (d charge x V / dt; ticks while discharging only)
  rapl_pkg_w, rapl_core_w, rapl_pkg_j (over interval; ticks only)
  gpu_w, gpu_busy_pct, profile, brightness_pct, panel_power_savings,
  bt_blocked, wifi_powersave, lid, screen_on
  cpu_total_s, cgroups ([{cg, cpu_s}] top 10 leaf cgroups by CPU s)
marks.jsonl: {ts, label}; a mark closes the previous window, `end` only
closes. power-report reads both.
"""
import argparse
import glob
import json
import os
import subprocess
import sys
import time

# Substituted by default.nix (store paths); the env override is for tests.
POWERPROFILESCTL = os.environ.get("POWER_LOG_POWERPROFILESCTL", "@powerprofilesctl@")
IW = os.environ.get("POWER_LOG_IW", "@iw@")
LID_STATE = os.environ.get("POWER_LOG_LID_STATE", "@lid_state@")
DIR = os.environ.get("POWER_LOG_DIR", "/var/lib/power-log")
CGROOT = "/sys/fs/cgroup"
RAPL = "/sys/class/powercap/intel-rapl:0"


def read(path):
    try:
        with open(path) as f:
            return f.read().strip()
    except OSError:
        return None


def read_int(path):
    v = read(path)
    try:
        return int(v)
    except (TypeError, ValueError):
        return None


def first(pattern, sub=""):
    for p in sorted(glob.glob(pattern)):
        v = read(os.path.join(p, sub) if sub else p)
        if v is not None:
            return v
    return None


def run(argv):
    try:
        r = subprocess.run(argv, capture_output=True, text=True, timeout=10)
    except (OSError, subprocess.SubprocessError):
        return None
    return r.stdout.strip() if r.returncode == 0 else None


def power_supply():
    ac = None
    for p in glob.glob("/sys/class/power_supply/*"):
        if read(p + "/type") == "Mains":
            ac = bool(ac) or read(p + "/online") == "1"
    bat = next(iter(sorted(glob.glob("/sys/class/power_supply/BAT*"))), None)
    out = {"ac": ac, "bat_status": None, "bat_pct": None,
           "bat_charge_uah": None, "bat_voltage_uv": None, "bat_w": None}
    if bat is None:
        return out
    out["bat_status"] = read(bat + "/status")
    out["bat_pct"] = read_int(bat + "/capacity")
    out["bat_charge_uah"] = read_int(bat + "/charge_now")
    out["bat_voltage_uv"] = read_int(bat + "/voltage_now")
    cur = read_int(bat + "/current_now")
    if cur is not None and out["bat_voltage_uv"] is not None:
        w = cur * out["bat_voltage_uv"] / 1e12
        out["bat_w"] = w if out["bat_status"] != "Charging" else -w
    return out


def rapl_energy(sub):
    d = RAPL + sub
    return read_int(d + "/energy_uj"), read_int(d + "/max_energy_range_uj")


def delta_uj(now, prev, rng):
    if now is None or prev is None:
        return None
    if now < prev:
        if not rng:
            return None
        return now + rng - prev
    return now - prev


def leaf_cgroups():
    out = {}
    for d, subdirs, _ in os.walk(CGROOT):
        if subdirs or d == CGROOT:
            continue
        for line in (read(d + "/cpu.stat") or "").splitlines():
            k, _, v = line.partition(" ")
            if k == "usage_usec" and v.isdigit():
                out[os.path.relpath(d, CGROOT)] = int(v)
    return out


def gpu_w():
    v = first("/sys/class/drm/card*/device/hwmon/hwmon*/power1_average")
    return int(v) / 1e6 if v and v.isdigit() else None


def brightness_pct():
    for p in sorted(glob.glob("/sys/class/backlight/*")):
        cur, mx = read_int(p + "/brightness"), read_int(p + "/max_brightness")
        if cur is not None and mx:
            return round(cur * 100 / mx)
    return None


def bt_blocked():
    seen = False
    for p in glob.glob("/sys/class/rfkill/rfkill*"):
        if read(p + "/type") == "bluetooth":
            seen = True
            if read(p + "/soft") == "1" or read(p + "/hard") == "1":
                return True
    return False if seen else None


def wifi_powersave():
    for line in (run([IW, "dev"]) or "").splitlines():
        if line.strip().startswith("Interface "):
            ps = run([IW, "dev", line.split()[1], "get", "power_save"])
            if ps:
                return ps.strip().endswith("on")
    return None


def screen_on():
    dpms = first("/sys/class/drm/card*-eDP-*/dpms")
    en = first("/sys/class/drm/card*-eDP-*/enabled")
    if dpms is None or en is None:
        return None
    return dpms == "On" and en == "enabled"


def load_state():
    try:
        with open(DIR + "/state.json") as f:
            return json.load(f)
    except (OSError, ValueError):
        return {}


def save_state(state):
    tmp = DIR + "/state.json.tmp"
    with open(tmp, "w") as f:
        json.dump(state, f)
    os.replace(tmp, DIR + "/state.json")


def sample(kind):
    now = time.time()
    boot_id = read("/proc/sys/kernel/random/boot_id")
    prev = load_state()
    if prev.get("boot_id") != boot_id:
        prev = {}
    dt = now - prev["ts"] if "ts" in prev else None
    if dt is not None and dt <= 0:
        dt = None
    tick = kind == "tick"

    ps = power_supply()
    pkg, pkg_rng = rapl_energy("")
    core, core_rng = rapl_energy("/intel-rapl:0:0")
    cgs = leaf_cgroups()

    line = {"ts": now, "kind": kind, "boot_id": boot_id,
            "gen": os.path.basename(os.path.realpath("/run/current-system")),
            "interval_s": dt}
    line.update(ps)

    line["bat_discharge_w"] = None
    statuses = (ps["bat_status"], prev.get("bat_status"))
    both_discharging = statuses == ("Discharging", "Discharging")
    have_charge = None not in (ps["bat_charge_uah"], ps["bat_voltage_uv"],
                               prev.get("bat_charge_uah"))
    if tick and dt and both_discharging and have_charge:
        d_uah = prev["bat_charge_uah"] - ps["bat_charge_uah"]
        line["bat_discharge_w"] = d_uah * ps["bat_voltage_uv"] / 1e12 * 3600 / dt

    line["rapl_pkg_w"] = line["rapl_core_w"] = line["rapl_pkg_j"] = None
    if tick and dt:
        d_pkg = delta_uj(pkg, prev.get("rapl_pkg_uj"), pkg_rng)
        d_core = delta_uj(core, prev.get("rapl_core_uj"), core_rng)
        if d_pkg is not None:
            line["rapl_pkg_j"] = d_pkg / 1e6
            line["rapl_pkg_w"] = d_pkg / 1e6 / dt
        if d_core is not None:
            line["rapl_core_w"] = d_core / 1e6 / dt

    line["gpu_w"] = gpu_w()
    busy = first("/sys/class/drm/card*/device/gpu_busy_percent")
    line["gpu_busy_pct"] = int(busy) if busy and busy.isdigit() else None
    line["profile"] = run([POWERPROFILESCTL, "get"])
    line["brightness_pct"] = brightness_pct()
    pps = first("/sys/class/drm/card*-eDP-*/amdgpu/panel_power_savings")
    line["panel_power_savings"] = int(pps) if pps and pps.isdigit() else None
    line["bt_blocked"] = bt_blocked()
    line["wifi_powersave"] = wifi_powersave()
    line["lid"] = run([LID_STATE]) if LID_STATE else None
    line["screen_on"] = screen_on()

    line["cpu_total_s"] = None
    line["cgroups"] = []
    if dt and prev.get("cg"):
        deltas = {}
        for cg, usec in cgs.items():
            if cg in prev["cg"] and usec >= prev["cg"][cg]:
                deltas[cg] = (usec - prev["cg"][cg]) / 1e6
        line["cpu_total_s"] = sum(deltas.values())
        top = sorted(deltas.items(), key=lambda kv: -kv[1])[:10]
        line["cgroups"] = [{"cg": cg, "cpu_s": s} for cg, s in top]

    state = {"boot_id": boot_id, "ts": now,
             "bat_charge_uah": ps["bat_charge_uah"],
             "bat_status": ps["bat_status"],
             "rapl_pkg_uj": pkg, "rapl_core_uj": core, "cg": cgs}
    return line, state


def cmd_sample(args):
    line, state = sample(args.kind)
    text = json.dumps(line, separators=(",", ":"))
    if args.dry_run:
        print(text)
        return 0
    path = time.strftime(DIR + "/samples-%Y-%m.jsonl", time.localtime(line["ts"]))
    fd = os.open(path, os.O_WRONLY | os.O_APPEND | os.O_CREAT, 0o644)
    with os.fdopen(fd, "a") as f:
        f.write(text + "\n")
    save_state(state)
    return 0


def cmd_mark(args):
    entry = json.dumps({"ts": time.time(), "label": args.label})
    with open(DIR + "/marks.jsonl", "a") as f:
        f.write(entry + "\n")
    return 0


def main():
    ap = argparse.ArgumentParser(prog="power-log")
    sub = ap.add_subparsers(dest="cmd", required=True)
    s = sub.add_parser("sample", help="append one sample (root)")
    s.add_argument("--kind", choices=["tick", "suspend", "resume"], default="tick")
    s.add_argument("--dry-run", action="store_true",
                   help="print the line; write nothing")
    s.set_defaults(fn=cmd_sample)
    m = sub.add_parser("mark", help="open a named window; 'end' just closes")
    m.add_argument("label")
    m.set_defaults(fn=cmd_mark)
    args = ap.parse_args()
    try:
        return args.fn(args)
    except OSError as e:
        print("power-log: %s" % e, file=sys.stderr)
        return 1


sys.exit(main())
