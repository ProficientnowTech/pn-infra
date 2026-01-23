#!/usr/bin/env python3

import argparse
import concurrent.futures
import datetime as dt
import json
import os
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple


@dataclass(frozen=True)
class Host:
    name: str
    ip: str
    user: str


def default_artifacts_dir() -> Path:
    return Path(__file__).resolve().parent.parent / ".artifacts"


REMOTE_PY = r"""
import json, os, re, shlex, subprocess, sys

DRY_RUN = os.environ.get("CEPH_CLEANUP_DRY_RUN", "0") == "1"
MODE = os.environ.get("CEPH_CLEANUP_MODE", "full").strip().lower()
if MODE not in ("fast", "full", "overwrite"):
    raise SystemExit(json.dumps({"ok": False, "error": f"invalid CEPH_CLEANUP_MODE: {MODE}"}))

def have(cmd: str) -> bool:
    return subprocess.run(["bash", "-lc", f"command -v {shlex.quote(cmd)} >/dev/null 2>&1"]).returncode == 0

def run(cmd, check=True):
    p = subprocess.run(cmd, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if check and p.returncode != 0:
        raise RuntimeError(f"command failed: {cmd}\n{p.stderr.strip()}")
    return p

def sudo(cmd, check=True):
    if isinstance(cmd, str):
        cmd = ["bash", "-lc", cmd]
    return run(["sudo", "-n", *cmd], check=check)

def sudo_try(cmd):
    try:
        return sudo(cmd, check=False)
    except Exception:
        return None

def sh(cmd):
    return run(cmd, check=True).stdout

lsblk = json.loads(
    sh(
        [
            "lsblk",
            "-J",
            "-b",
            "-o",
            "NAME,KNAME,PATH,TYPE,SIZE,MODEL,SERIAL,VENDOR,ROTA,TRAN,WWN,FSTYPE,MOUNTPOINTS,UUID",
        ]
    )
)

node_by_name = {}
node_by_path = {}
parents = {}

def walk(node, parent_name=None):
    name = node.get("name")
    if name:
        node_by_name[name] = node
        p = node.get("path")
        if p:
            node_by_path[p] = name
        if parent_name:
            parents.setdefault(name, set()).add(parent_name)
    for ch in node.get("children") or []:
        walk(ch, name)

for top in lsblk.get("blockdevices") or []:
    walk(top, None)

def name_from_source(src: str):
    if not src:
        return None
    if src in node_by_path:
        return node_by_path[src]
    if src.startswith("/dev/"):
        base = os.path.basename(src)
        if base in node_by_name:
            return base
    return None

def disks_for_device_name(dev_name: str):
    if not dev_name:
        return set()
    out = set()
    q = [dev_name]
    seen = set()
    while q:
        cur = q.pop()
        if cur in seen:
            continue
        seen.add(cur)
        node = node_by_name.get(cur)
        if not node:
            continue
        if node.get("type") == "disk":
            out.add(cur)
            continue
        for p in parents.get(cur, ()):
            q.append(p)
    return out

def mount_source(mp: str):
    p = run(["findmnt", "-nro", "SOURCE", mp], check=False)
    if p.returncode != 0:
        return None
    return p.stdout.strip()

mount_sources = {}
for mp in ("/", "/boot", "/boot/efi", "/var"):
    src = mount_source(mp)
    if src:
        mount_sources[mp] = src

os_disks = set()
unresolved_mount_sources = {}
for mp, src in mount_sources.items():
    n = name_from_source(src)
    if not n:
        unresolved_mount_sources[mp] = src
        continue
    os_disks |= disks_for_device_name(n)

physical_disk_name = re.compile(r"^(sd|vd|xvd|nvme|mmcblk|hd|dasd)")
all_disks = sorted(
    {name for name, node in node_by_name.items() if node.get("type") == "disk" and physical_disk_name.match(name or "")}
)
target_disks = [d for d in all_disks if d not in os_disks]

def disk_info(name: str):
    n = node_by_name.get(name, {})
    return {
        "name": n.get("name"),
        "path": n.get("path"),
        "size_bytes": n.get("size"),
        "model": n.get("model"),
        "serial": n.get("serial"),
        "vendor": n.get("vendor"),
        "rota": n.get("rota"),
        "tran": n.get("tran"),
        "wwn": n.get("wwn"),
    }

def descendants(root_name: str):
    out = []
    seen = set()
    q = [root_name]
    while q:
        cur = q.pop()
        if cur in seen:
            continue
        seen.add(cur)
        n = node_by_name.get(cur)
        if n:
            out.append(n)
            for ch in n.get("children") or []:
                if ch.get("name"):
                    q.append(ch["name"])
    return out

actions = []
warnings = []

def record(action, **kw):
    actions.append({"action": action, **kw})

record("detected", os_disks=sorted(os_disks), target_disks=target_disks)

if not os_disks:
    raise SystemExit(json.dumps({"ok": False, "error": "OS disk detection returned empty set; refusing to continue", "actions": actions}))

if unresolved_mount_sources:
    warnings.append({"warning": "unresolved_mount_sources", "details": unresolved_mount_sources})

if not target_disks:
    print(json.dumps({"ok": True, "skipped": True, "hostname": sh(["hostname"]).strip(), "actions": actions, "warnings": warnings}))
    raise SystemExit(0)

def stop_services():
    for svc in ("kubelet", "containerd", "docker"):
        if DRY_RUN:
            record("service_stop_dry_run", service=svc)
            continue
        p = sudo_try(["systemctl", "stop", svc])
        if p and p.returncode == 0:
            record("service_stop", service=svc)

def stop_ceph_processes():
    # Best-effort shutdown of rook/ceph processes so devices can be unmounted/closed.
    if DRY_RUN:
        record("ceph_stop_dry_run")
        return
    # systemd unit globs require a shell for expansion.
    sudo_try("systemctl stop ceph\\* 2>/dev/null || true")
    sudo_try("systemctl stop rook\\* 2>/dev/null || true")
    for proc in ("ceph-mon", "ceph-osd", "ceph-mgr", "ceph-mds", "radosgw", "ceph"):
        sudo_try(["pkill", "-9", proc])
    record("ceph_stop")

def list_mountpoints(cmd: str):
    p = run(["bash", "-lc", cmd], check=False)
    if p.returncode != 0:
        return []
    return [ln.strip() for ln in (p.stdout or "").splitlines() if ln.strip()]

def umount_ceph_mounts():
    # Best-effort unmount of any ceph/rook related mounts.
    mountpoints = list_mountpoints("mount | grep -E 'ceph|rook' | awk '{print $3}' | sort -u")
    if mountpoints:
        record("ceph_mounts_detected", mountpoints=mountpoints)
    umount_paths(mountpoints)

def umount_paths(mounts):
    for mp in mounts:
        if not mp or mp in ("/", "/boot", "/boot/efi", "/var"):
            continue
        if DRY_RUN:
            record("umount_dry_run", mountpoint=mp)
            continue
        p = sudo_try(["umount", "-lf", mp])
        record("umount", mountpoint=mp, rc=getattr(p, "returncode", None))

def zap_blockdev(dev_path: str):
    if not dev_path:
        return
    if DRY_RUN:
        record("wipefs_dry_run", device=dev_path)
        return
    p = sudo_try(["wipefs", "-a", dev_path])
    record("wipefs", device=dev_path, rc=getattr(p, "returncode", None))

def zap_disk_table(disk_path: str):
    if not disk_path:
        return
    if DRY_RUN:
        record("sgdisk_zap_dry_run", device=disk_path)
        return
    if subprocess.run(["bash","-lc","command -v sgdisk >/dev/null 2>&1"]).returncode == 0:
        p = sudo_try(["sgdisk", "--zap-all", "--clear", disk_path])
        record("sgdisk_zap", device=disk_path, rc=getattr(p, "returncode", None))
    else:
        record("sgdisk_missing", device=disk_path)

def wipe_start_end(disk_path: str):
    if not disk_path:
        return
    if DRY_RUN:
        record("dd_dry_run", device=disk_path)
        return
    # Wipe first and last 16MiB (enough to clear common metadata) without spending hours on large disks.
    p1 = sudo_try(["dd", "if=/dev/zero", f"of={disk_path}", "bs=1M", "count=16", "conv=fsync"])
    record("dd_start", device=disk_path, rc=getattr(p1, "returncode", None))
    # Seek to last 16MiB
    sz = sudo_try(["blockdev", "--getsize64", disk_path])
    if not sz or sz.returncode != 0:
        record("dd_end_skip", device=disk_path, reason="blockdev_failed")
        return
    try:
        size_bytes = int((sz.stdout or "0").strip())
    except Exception:
        record("dd_end_skip", device=disk_path, reason="blockdev_parse_failed")
        return
    if size_bytes <= 32 * 1024 * 1024:
        record("dd_end_skip", device=disk_path, reason="disk_too_small")
        return
    seek_mib = (size_bytes // (1024 * 1024)) - 16
    p2 = sudo_try(["dd", "if=/dev/zero", f"of={disk_path}", "bs=1M", "count=16", f"seek={seek_mib}", "conv=fsync"])
    record("dd_end", device=disk_path, seek_mib=seek_mib, rc=getattr(p2, "returncode", None))

def wipe_full(disk_path: str):
    if not disk_path:
        return
    if DRY_RUN:
        record("full_wipe_dry_run", device=disk_path)
        return

    # Prefer device-native discard when available (fast, but depends on underlying storage).
    if subprocess.run(["bash", "-lc", "command -v blkdiscard >/dev/null 2>&1"]).returncode == 0:
        p = sudo_try(["blkdiscard", "-f", disk_path])
        if p and p.returncode == 0:
            record("blkdiscard_full", device=disk_path)
            return
        record("blkdiscard_failed", device=disk_path, rc=getattr(p, "returncode", None), stderr=getattr(p, "stderr", "")[:2000])
    else:
        record("blkdiscard_missing", device=disk_path)

    # Fallback: full zero-fill. This CAN take hours/days for large HDDs.
    record("dd_full_start", device=disk_path)
    p = sudo_try(["dd", "if=/dev/zero", f"of={disk_path}", "bs=64M", "status=none", "conv=fsync"])
    record("dd_full", device=disk_path, rc=getattr(p, "returncode", None))

def wipe_overwrite(disk_path: str):
    if not disk_path:
        return
    if DRY_RUN:
        record("overwrite_dry_run", device=disk_path)
        return
    record("dd_overwrite_start", device=disk_path)
    p = sudo_try(["dd", "if=/dev/zero", f"of={disk_path}", "bs=64M", "status=none", "conv=fsync"])
    record("dd_overwrite", device=disk_path, rc=getattr(p, "returncode", None))

def remove_ceph_dirs():
    for path in ("/var/lib/rook", "/var/lib/ceph", "/etc/ceph", "/var/log/ceph"):
        if DRY_RUN:
            record("rm_rf_dry_run", path=path)
            continue
        p = sudo_try(["rm", "-rf", path])
        record("rm_rf", path=path, rc=getattr(p, "returncode", None))

def lvm_cleanup_for_disk(disk_path: str):
    # Remove any LVM artifacts that live on the target disk (common with ceph-volume LVM).
    if not disk_path or not have("pvs") or not have("vgs") or not have("vgremove") or not have("pvremove"):
        record("lvm_tools_missing_or_skipped", device=disk_path)
        return

    if DRY_RUN:
        record("lvm_cleanup_dry_run", device=disk_path)
        return

    sudo_try(["vgchange", "-an"])

    p = sudo_try(["pvs", "--noheadings", "-o", "pv_name,vg_name"])
    if not p or p.returncode != 0:
        record("lvm_pvs_failed", device=disk_path, rc=getattr(p, "returncode", None))
        return

    pvs_on_disk = []
    vgs_on_disk = []
    for ln in (p.stdout or "").splitlines():
        parts = [x for x in ln.strip().split() if x]
        if len(parts) < 1:
            continue
        pv = parts[0]
        vg = parts[1] if len(parts) > 1 else ""
        if pv.startswith(disk_path):
            pvs_on_disk.append(pv)
            if vg:
                vgs_on_disk.append(vg)

    vgs_on_disk = sorted(set(vgs_on_disk))
    pvs_on_disk = sorted(set(pvs_on_disk))
    record("lvm_found", device=disk_path, vgs=vgs_on_disk, pvs=pvs_on_disk)

    for vg in vgs_on_disk:
        r = sudo_try(["vgremove", "-f", vg])
        record("vgremove", vg=vg, rc=getattr(r, "returncode", None))
    for pv in pvs_on_disk:
        r = sudo_try(["pvremove", "-ff", "-y", pv])
        record("pvremove", pv=pv, rc=getattr(r, "returncode", None))

def remove_systemd_units():
    if DRY_RUN:
        record("systemd_cleanup_dry_run")
        return
    sudo_try("rm -f /etc/systemd/system/ceph*.service /etc/systemd/system/rook*.service 2>/dev/null || true")
    sudo_try(["systemctl", "daemon-reload"])
    record("systemd_cleanup")

def require_sudo():
    if DRY_RUN:
        record("sudo_check_dry_run")
        return
    p = run(["sudo", "-n", "true"], check=False)
    if p.returncode != 0:
        raise SystemExit(json.dumps({"ok": False, "error": "sudo -n failed; ensure the SSH user has passwordless sudo", "actions": actions}))

require_sudo()
stop_services()
stop_ceph_processes()
umount_ceph_mounts()

for disk in target_disks:
    disk_path = node_by_name.get(disk, {}).get("path") or f"/dev/{disk}"
    record("target_disk", disk=disk, info=disk_info(disk))

    nodes = descendants(disk)
    # Unmount anything mounted on descendants.
    mounts = []
    for n in nodes:
        for mp in n.get("mountpoints") or []:
            if mp:
                mounts.append(mp)
    umount_paths(sorted(set(mounts)))

    lvm_cleanup_for_disk(disk_path)

    # Best effort: remove dm devices in the descendant chain (common with ceph-volume LVM).
    for n in nodes:
        if n.get("type") in ("lvm", "crypt"):
            kname = n.get("kname")
            if kname and not DRY_RUN:
                p = sudo_try(["dmsetup", "remove", "--force", kname])
                record("dmsetup_remove", device=kname, rc=getattr(p, "returncode", None))
            elif kname:
                record("dmsetup_remove_dry_run", device=f"/dev/{kname}")

    # Wipe filesystem / LVM / Ceph signatures for disk and descendants.
    for n in nodes:
        dev_path = n.get("path")
        if dev_path:
            zap_blockdev(dev_path)

    zap_disk_table(disk_path)
    if MODE == "fast":
        wipe_start_end(disk_path)
    elif MODE == "overwrite":
        wipe_overwrite(disk_path)
    else:
        wipe_full(disk_path)

    if DRY_RUN:
        record("partprobe_dry_run", device=disk_path)
    else:
        p = sudo_try(["partprobe", disk_path])
        record("partprobe", device=disk_path, rc=getattr(p, "returncode", None))
        sudo_try(["udevadm", "settle"])
        record("udevadm_settle", device=disk_path)

remove_ceph_dirs()
remove_systemd_units()

print(json.dumps({"ok": True, "hostname": sh(["hostname"]).strip(), "mode": MODE, "actions": actions, "warnings": warnings, "os_disks": [disk_info(d) for d in sorted(os_disks)], "target_disks": [disk_info(d) for d in target_disks]}))
"""


def load_hosts(hosts_file: Path) -> List[Host]:
    try:
        import yaml  # type: ignore
    except Exception as e:
        raise RuntimeError(
            "PyYAML is required to parse hosts.yml. Install with: pip install pyyaml"
        ) from e

    data = yaml.safe_load(hosts_file.read_text())
    hosts = (data or {}).get("all", {}).get("hosts", {})
    out: List[Host] = []
    for name, meta in hosts.items():
        if not isinstance(meta, dict):
            continue
        ip = meta.get("ansible_host")
        if not ip:
            continue
        user = meta.get("ansible_user") or "ansible"
        out.append(Host(name=name, ip=str(ip), user=str(user)))
    return out


def parse_limit(limit: Optional[str], all_hosts: List[Host]) -> List[Host]:
    if not limit:
        return all_hosts
    requested: List[str] = []
    seen: set[str] = set()
    for raw in limit.split(","):
        name = raw.strip()
        if not name or name in seen:
            continue
        seen.add(name)
        requested.append(name)
    by_name = {h.name: h for h in all_hosts}
    selected = []
    missing = []
    for name in requested:
        if name in by_name:
            selected.append(by_name[name])
        else:
            missing.append(name)
    if missing:
        raise RuntimeError(f"--limit references unknown hosts: {', '.join(missing)}")
    return selected


def run_remote(
    host: Host, ssh_key: Path, timeout_s: int, dry_run: bool, mode: str
) -> Tuple[Optional[Dict[str, Any]], Optional[str]]:
    connect_timeout = 10 if timeout_s == 0 else min(timeout_s, 10)
    cmd = [
        "ssh",
        "-i",
        str(ssh_key),
        "-o",
        "IdentitiesOnly=yes",
        "-o",
        "IdentityAgent=none",
        "-o",
        "PreferredAuthentications=publickey",
        "-o",
        "BatchMode=yes",
        "-o",
        "StrictHostKeyChecking=no",
        "-o",
        "UserKnownHostsFile=/dev/null",
        "-o",
        f"ConnectTimeout={connect_timeout}",
        f"{host.user}@{host.ip}",
        "CEPH_CLEANUP_DRY_RUN=1" if dry_run else "CEPH_CLEANUP_DRY_RUN=0",
        f"CEPH_CLEANUP_MODE={mode}",
        "python3",
        "-",
    ]
    try:
        p = subprocess.run(
            cmd,
            input=REMOTE_PY,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=None if timeout_s == 0 else timeout_s,
        )
    except subprocess.TimeoutExpired:
        return None, f"timeout after {timeout_s}s"
    if p.returncode != 0:
        err = (p.stderr or "").strip() or f"ssh exited {p.returncode}"
        # Some failures are intentionally JSON from the remote; try parse first.
        try:
            data = json.loads((p.stdout or "").strip() or "{}")
            return data, None
        except Exception:
            return None, err
    try:
        return json.loads(p.stdout), None
    except Exception as e:
        return None, f"failed to parse JSON output: {e}"


def main() -> int:
    ap = argparse.ArgumentParser(
        description="Ceph forced disk cleanup (non-OS physical disks only) across nodes in Kubespray hosts.yml."
    )
    ap.add_argument("--hosts-file", required=True, type=Path)
    ap.add_argument("--ssh-key", required=True, type=Path)
    ap.add_argument("--limit", help="Comma-separated hostnames from hosts.yml")
    ap.add_argument("--dry-run", action="store_true", help="Show actions; do not wipe")
    ap.add_argument("--yes", action="store_true", help="Required to run without --dry-run (IRREVERSIBLE)")
    ap.add_argument(
        "--mode",
        choices=["fast", "full", "overwrite"],
        default="full",
        help="fast: wipe signatures/partition tables; full: wipe entire disks (blkdiscard if available else full zero-fill); overwrite: write zeros over every byte (slow)",
    )
    ap.add_argument("--timeout", type=int, default=60, help="SSH timeout per host (seconds); use 0 for no timeout")
    ap.add_argument("--parallel", type=int, default=8, help="Parallel SSH workers")
    ap.add_argument(
        "--output-json",
        type=Path,
        default=default_artifacts_dir() / "ceph_force_disk_cleanup_report.json",
    )
    args = ap.parse_args()

    if not args.hosts_file.is_file():
        raise SystemExit(f"hosts file not found: {args.hosts_file}")
    if not args.ssh_key.is_file():
        raise SystemExit(f"ssh key not found: {args.ssh_key}")

    if not args.dry_run and not args.yes:
        raise SystemExit(
            "Refusing to wipe disks without explicit confirmation. Re-run with --yes (THIS IS DESTRUCTIVE AND CANNOT BE UNDONE)."
        )

    all_hosts = load_hosts(args.hosts_file)
    hosts = parse_limit(args.limit, all_hosts)

    results: List[Dict[str, Any]] = []

    def one(h: Host) -> Dict[str, Any]:
        data, err = run_remote(h, args.ssh_key, timeout_s=args.timeout, dry_run=args.dry_run, mode=args.mode)
        out: Dict[str, Any] = {"host": {"name": h.name, "ip": h.ip, "user": h.user}, "dry_run": args.dry_run, "mode": args.mode}
        if err:
            out["error"] = err
        else:
            out["data"] = data
        return out

    with concurrent.futures.ThreadPoolExecutor(max_workers=args.parallel) as ex:
        futs = [ex.submit(one, h) for h in hosts]
        for fut in concurrent.futures.as_completed(futs):
            results.append(fut.result())

    results.sort(key=lambda r: r["host"]["name"])
    args.output_json.parent.mkdir(parents=True, exist_ok=True)
    payload = {"generated_at_utc": dt.datetime.now(dt.timezone.utc).isoformat(), "results": results}
    args.output_json.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n")

    failures = [r for r in results if r.get("error") or not (r.get("data") or {}).get("ok")]
    if failures:
        sys.stderr.write(
            f"[ERROR] cleanup had failures on {len(failures)}/{len(results)} hosts. See {args.output_json}\n"
        )
        return 2
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except KeyboardInterrupt:
        raise SystemExit(130)
