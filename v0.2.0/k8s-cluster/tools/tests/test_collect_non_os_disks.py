import json
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


collect_non_os_disks = _import_tooling_module("collect_non_os_disks")


class TestCollectNonOsDisks(unittest.TestCase):
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
            hosts = collect_non_os_disks.load_hosts(hosts_file)
            self.assertEqual([h.name for h in hosts], ["k8s-master-01", "k8s-worker-01"])
            self.assertEqual([h.ip for h in hosts], ["10.0.0.1", "10.0.0.2"])
            self.assertEqual([h.user for h in hosts], ["ansible", "root"])

    def test_parse_limit_selects_hosts(self) -> None:
        hosts = [
            collect_non_os_disks.Host(name="a", ip="1.1.1.1", user="ansible"),
            collect_non_os_disks.Host(name="b", ip="1.1.1.2", user="ansible"),
        ]
        selected = collect_non_os_disks.parse_limit("b,a", hosts)
        self.assertEqual([h.name for h in selected], ["b", "a"])

    def test_parse_limit_errors_on_unknown_host(self) -> None:
        hosts = [collect_non_os_disks.Host(name="a", ip="1.1.1.1", user="ansible")]
        with self.assertRaises(RuntimeError):
            collect_non_os_disks.parse_limit("nope", hosts)

    def test_ssh_json_success(self) -> None:
        host = collect_non_os_disks.Host(name="a", ip="1.1.1.1", user="ansible")
        ssh_key = Path("/tmp/fakekey")

        def fake_run(cmd, input=None, text=None, stdout=None, stderr=None, timeout=None):
            class P:
                returncode = 0
                stdout = '{"hello": "world"}'
                stderr = ""
            return P()

        with mock.patch.object(collect_non_os_disks.subprocess, "run", side_effect=fake_run):
            data, err = collect_non_os_disks.ssh_json(host, ssh_key, timeout_s=5)
            self.assertIsNone(err)
            self.assertEqual(data, {"hello": "world"})

    def test_ssh_json_nonzero(self) -> None:
        host = collect_non_os_disks.Host(name="a", ip="1.1.1.1", user="ansible")
        ssh_key = Path("/tmp/fakekey")

        def fake_run(cmd, input=None, text=None, stdout=None, stderr=None, timeout=None):
            class P:
                returncode = 255
                stdout = ""
                stderr = "Permission denied"
            return P()

        with mock.patch.object(collect_non_os_disks.subprocess, "run", side_effect=fake_run):
            data, err = collect_non_os_disks.ssh_json(host, ssh_key, timeout_s=5)
            self.assertIsNone(data)
            self.assertIn("Permission denied", err or "")

    def test_ssh_json_invalid_json(self) -> None:
        host = collect_non_os_disks.Host(name="a", ip="1.1.1.1", user="ansible")
        ssh_key = Path("/tmp/fakekey")

        def fake_run(cmd, input=None, text=None, stdout=None, stderr=None, timeout=None):
            class P:
                returncode = 0
                stdout = "not json"
                stderr = ""
            return P()

        with mock.patch.object(collect_non_os_disks.subprocess, "run", side_effect=fake_run):
            data, err = collect_non_os_disks.ssh_json(host, ssh_key, timeout_s=5)
            self.assertIsNone(data)
            self.assertIn("failed to parse JSON", err or "")

    def test_write_reports_creates_json_and_md(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            out_json = Path(td) / "report.json"
            out_md = Path(td) / "report.md"

            results = [
                {
                    "host": {"name": "k8s-master-01", "ip": "10.0.0.1", "user": "ansible"},
                    "data": {
                        "hostname": "k8s-master-01",
                        "os_disks": [{"name": "sda"}],
                        "non_os_disks": [{"name": "sdb"}, {"name": "sdc"}],
                    },
                }
            ]

            collect_non_os_disks.write_reports(results, out_json, out_md)
            self.assertTrue(out_json.is_file())
            self.assertTrue(out_md.is_file())

            payload = json.loads(out_json.read_text())
            self.assertIn("results", payload)

            md = out_md.read_text()
            self.assertIn("k8s-master-01", md)
            self.assertIn("sdb", md)


if __name__ == "__main__":
    unittest.main()

