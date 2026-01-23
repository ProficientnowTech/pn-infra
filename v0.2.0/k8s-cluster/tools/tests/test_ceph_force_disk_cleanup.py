import tempfile
import unittest
from pathlib import Path
from unittest import mock


def _import_tooling_module(module_name: str):
    import sys
    from pathlib import Path

    tools_dir = Path(__file__).resolve().parents[1]
    sys.path.insert(0, str(tools_dir))
    return __import__(module_name)


ceph_force_disk_cleanup = _import_tooling_module("ceph_force_disk_cleanup")


class TestCephForceDiskCleanup(unittest.TestCase):
    def test_load_hosts_parses_hosts_and_defaults_user(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            hosts_file = Path(td) / "hosts.yml"
            hosts_file.write_text(
                """
all:
  hosts:
    k8s-master-01:
      ansible_host: 10.0.0.1
    k8s-worker-01:
      ansible_host: 10.0.0.2
      ansible_user: root
""".lstrip()
            )
            hosts = ceph_force_disk_cleanup.load_hosts(hosts_file)
            self.assertEqual([h.name for h in hosts], ["k8s-master-01", "k8s-worker-01"])
            self.assertEqual([h.ip for h in hosts], ["10.0.0.1", "10.0.0.2"])
            self.assertEqual([h.user for h in hosts], ["ansible", "root"])

    def test_parse_limit_errors_on_unknown_host(self) -> None:
        hosts = [
            ceph_force_disk_cleanup.Host(name="a", ip="1.1.1.1", user="ansible"),
            ceph_force_disk_cleanup.Host(name="b", ip="1.1.1.2", user="ansible"),
        ]
        with self.assertRaises(RuntimeError):
            ceph_force_disk_cleanup.parse_limit("c", hosts)

    def test_run_remote_includes_mode_env_var(self) -> None:
        host = ceph_force_disk_cleanup.Host(name="a", ip="1.1.1.1", user="ansible")
        ssh_key = Path("/tmp/fakekey")

        def fake_run(cmd, input=None, text=None, stdout=None, stderr=None, timeout=None):
            self.assertIn("CEPH_CLEANUP_MODE=fast", cmd)
            class P:
                returncode = 0
                stdout = '{"ok": true}'
                stderr = ""
            return P()

        with mock.patch.object(ceph_force_disk_cleanup.subprocess, "run", side_effect=fake_run):
            data, err = ceph_force_disk_cleanup.run_remote(
                host, ssh_key=ssh_key, timeout_s=5, dry_run=True, mode="fast"
            )
            self.assertIsNone(err)
            self.assertEqual(data, {"ok": True})

    def test_main_requires_yes_when_not_dry_run(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            hosts_file = Path(td) / "hosts.yml"
            ssh_key = Path(td) / "id_ed25519"
            hosts_file.write_text(
                """
all:
  hosts:
    k8s-master-01:
      ansible_host: 10.0.0.1
""".lstrip()
            )
            ssh_key.write_text("dummy")

            with mock.patch.object(
                ceph_force_disk_cleanup,
                "run_remote",
                return_value=({"ok": True}, None),
            ):
                with mock.patch(
                    "sys.argv",
                    [
                        "ceph_force_disk_cleanup.py",
                        "--hosts-file",
                        str(hosts_file),
                        "--ssh-key",
                        str(ssh_key),
                        "--mode",
                        "fast",
                    ],
                ):
                    with self.assertRaises(SystemExit) as cm:
                        ceph_force_disk_cleanup.main()
                    self.assertIn("Refusing to wipe disks", str(cm.exception))

    def test_main_allows_dry_run_without_yes(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            hosts_file = Path(td) / "hosts.yml"
            ssh_key = Path(td) / "id_ed25519"
            out_json = Path(td) / "report.json"
            hosts_file.write_text(
                """
all:
  hosts:
    k8s-master-01:
      ansible_host: 10.0.0.1
""".lstrip()
            )
            ssh_key.write_text("dummy")

            def fake_run_remote(*args, **kwargs):
                return {"ok": True, "hostname": "k8s-master-01"}, None

            with mock.patch.object(ceph_force_disk_cleanup, "run_remote", side_effect=fake_run_remote):
                with mock.patch(
                    "sys.argv",
                    [
                        "ceph_force_disk_cleanup.py",
                        "--hosts-file",
                        str(hosts_file),
                        "--ssh-key",
                        str(ssh_key),
                        "--dry-run",
                        "--mode",
                        "full",
                        "--parallel",
                        "1",
                        "--output-json",
                        str(out_json),
                    ],
                ):
                    rc = ceph_force_disk_cleanup.main()
                    self.assertEqual(rc, 0)
                    self.assertTrue(out_json.is_file())


if __name__ == "__main__":
    unittest.main()

