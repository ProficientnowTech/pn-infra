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
import json, os, subprocess, sys
import re

def sh(cmd):
    p = subprocess.run(cmd, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if p.returncode != 0:
        raise RuntimeError(f"command failed: {cmd}\n{p.stderr.strip()}")
    return p.stdout

def sh_try(cmd):
    p = subprocess.run(cmd, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if p.returncode != 0:
        return None
    return p.stdout

lsblk = json.loads(sh(["lsblk","-J","-b","-o","NAME,KNAME,PATH,TYPE,SIZE,MODEL,SERIAL,VENDOR,ROTA,TRAN,WWN,FSTYPE,MOUNTPOINTS,UUID"]))

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
    # fall back to basename of /dev/xxx
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

mount_sources = {}
for mp in ("/", "/boot", "/boot/efi", "/var"):
    src = sh_try(["findmnt","-nro","SOURCE",mp])
    if src:
        mount_sources[mp] = src.strip()

os_disks = set()
unresolved_sources = {}
for mp, src in mount_sources.items():
    n = name_from_source(src)
    if not n:
        unresolved_sources[mp] = src
        continue
    os_disks |= disks_for_device_name(n)

all_disks = []
for name, node in node_by_name.items():
    if node.get("type") == "disk":
        all_disks.append(name)

physical_disk_name = re.compile(r"^(sd|vd|xvd|nvme|mmcblk|hd|dasd)")
all_physical_disks = [d for d in all_disks if physical_disk_name.match(d or "")]

non_os_disks = [d for d in sorted(set(all_physical_disks)) if d not in os_disks]

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

result = {
    "hostname": sh(["hostname"]).strip(),
    "os_disks": [disk_info(d) for d in sorted(os_disks)],
    "non_os_disks": [disk_info(d) for d in non_os_disks],
    "mount_sources": mount_sources,
    "unresolved_mount_sources": unresolved_sources,
}

print(json.dumps(result, sort_keys=True))
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


def ssh_json(host: Host, ssh_key: Path, timeout_s: int) -> Tuple[Optional[Dict[str, Any]], Optional[str]]:
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
        f"ConnectTimeout={min(timeout_s, 10)}",
        f"{host.user}@{host.ip}",
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
            timeout=timeout_s,
        )
    except subprocess.TimeoutExpired:
        return None, f"timeout after {timeout_s}s"
    if p.returncode != 0:
        err = (p.stderr or "").strip() or f"ssh exited {p.returncode}"
        return None, err
    try:
        return json.loads(p.stdout), None
    except Exception as e:
        return None, f"failed to parse JSON output: {e}"


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


def write_reports(results: List[Dict[str, Any]], out_json: Path, out_md: Path) -> None:
    out_json.parent.mkdir(parents=True, exist_ok=True)
    out_md.parent.mkdir(parents=True, exist_ok=True)

    payload = {
        "generated_at_utc": dt.datetime.now(dt.timezone.utc).isoformat(),
        "results": results,
    }
    out_json.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n")

    lines: List[str] = []
    lines.append(f"# Non-OS Disks Report\n")
    lines.append(f"- Generated at (UTC): `{payload['generated_at_utc']}`\n")
    lines.append("")
    for r in results:
        lines.append(f"## {r['host']['name']} ({r['host'].get('ip','')})")
        if r.get("error"):
            lines.append(f"- Status: `unreachable` ({r['error']})")
            lines.append("")
            continue
        data = r.get("data") or {}
        os_disks = data.get("os_disks") or []
        non_os = data.get("non_os_disks") or []
        lines.append(f"- Status: `ok` (hostname `{data.get('hostname','')}`)")
        lines.append(f"- OS disks: `{', '.join([d.get('name','?') for d in os_disks]) or 'unknown'}`")
        lines.append(f"- Non-OS disks: `{', '.join([d.get('name','?') for d in non_os]) or 'none'}`")
        lines.append("")
        if non_os:
            lines.append("| name | path | size(bytes) | model | serial | vendor | rota | tran | wwn |")
            lines.append("|---|---:|---:|---|---|---|---:|---|---|")
            for d in non_os:
                lines.append(
                    "| {name} | {path} | {size_bytes} | {model} | {serial} | {vendor} | {rota} | {tran} | {wwn} |".format(
                        name=d.get("name") or "",
                        path=d.get("path") or "",
                        size_bytes=d.get("size_bytes") or "",
                        model=(d.get("model") or "").replace("|", "\\|"),
                        serial=(d.get("serial") or "").replace("|", "\\|"),
                        vendor=(d.get("vendor") or "").replace("|", "\\|"),
                        rota=d.get("rota") if d.get("rota") is not None else "",
                        tran=(d.get("tran") or "").replace("|", "\\|"),
                        wwn=(d.get("wwn") or "").replace("|", "\\|"),
                    )
                )
            lines.append("")
    out_md.write_text("\n".join(lines).rstrip() + "\n")


def main() -> int:
    ap = argparse.ArgumentParser(
        description="Collect per-node non-OS disk inventory from Kubespray hosts.yml."
    )
    ap.add_argument("--hosts-file", required=True, type=Path)
    ap.add_argument("--ssh-key", required=True, type=Path)
    ap.add_argument("--limit", help="Comma-separated hostnames from hosts.yml")
    ap.add_argument("--timeout", type=int, default=30, help="SSH timeout per host (seconds)")
    ap.add_argument("--parallel", type=int, default=12, help="Parallel SSH workers")
    ap.add_argument(
        "--output-json",
        type=Path,
        default=default_artifacts_dir() / "non_os_disks_report.json",
    )
    ap.add_argument(
        "--output-md",
        type=Path,
        default=default_artifacts_dir() / "non_os_disks_report.md",
    )
    args = ap.parse_args()

    if not args.hosts_file.is_file():
        raise SystemExit(f"hosts file not found: {args.hosts_file}")
    if not args.ssh_key.is_file():
        raise SystemExit(f"ssh key not found: {args.ssh_key}")

    all_hosts = load_hosts(args.hosts_file)
    hosts = parse_limit(args.limit, all_hosts)

    results: List[Dict[str, Any]] = []

    def one(h: Host) -> Dict[str, Any]:
        data, err = ssh_json(h, args.ssh_key, timeout_s=args.timeout)
        out: Dict[str, Any] = {"host": {"name": h.name, "ip": h.ip, "user": h.user}}
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
    write_reports(results, args.output_json, args.output_md)

    failed = [r for r in results if r.get("error")]
    if failed:
        sys.stderr.write(
            f"[WARN] {len(failed)}/{len(results)} hosts unreachable. See {args.output_md}\n"
        )
        return 2
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except KeyboardInterrupt:
        raise SystemExit(130)
