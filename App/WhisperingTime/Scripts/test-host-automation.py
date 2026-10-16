#!/usr/bin/env python3
"""Isolated host-gate regression checks; all fixtures stay in repository TMP/."""

import sys
sys.dont_write_bytecode = True

import fcntl
import importlib.util
import json
import os
from pathlib import Path
import signal
import stat
import subprocess
import tempfile
import time
import unittest
from unittest import mock


SCRIPT = Path(__file__).with_name("host-automation.py").resolve()
SPEC = importlib.util.spec_from_file_location("host_automation", SCRIPT)
gate_module = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = gate_module
SPEC.loader.exec_module(gate_module)
Process = gate_module.Process
FIXTURES = SCRIPT.parents[3] / "TMP" / "自动化测试排队" / "隔离回归"
FIXTURES.mkdir(parents=True, exist_ok=True)


WRAPPER = r"""
import sys
sys.dont_write_bytecode = True
import importlib.util
from pathlib import Path
spec = importlib.util.spec_from_file_location('host_automation', sys.argv[1])
module = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = module
spec.loader.exec_module(module)
gate = module.HostGate(Path(sys.argv[2]), process_provider=lambda: [])
try:
    sys.exit(gate.run(sys.argv[3:]))
except module.Cancelled as error:
    sys.exit(128 + error.signum)
"""


class GateFixtures(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="case-", dir=str(FIXTURES))
        self.addCleanup(self.temporary.cleanup)
        self.directory = Path(self.temporary.name)
        self.lock = self.directory / "coordination" / "host.lock"

    def gate(self, tables, sleeps=None, logs=None):
        iterator = iter(tables)
        sleeps = [] if sleeps is None else sleeps
        return gate_module.HostGate(
            self.lock, process_provider=lambda: next(iterator),
            sleeper=sleeps.append, clock=lambda: sum(sleeps),
            logger=([] if logs is None else logs).append,
        )

    def hold_lock(self, metadata):
        gate = gate_module.HostGate(self.lock)
        descriptor = gate._open_lock()
        fcntl.flock(descriptor, fcntl.LOCK_EX | fcntl.LOCK_NB)
        gate._write_metadata(descriptor, metadata)
        self.addCleanup(os.close, descriptor)
        return descriptor

    def assert_lock_held(self):
        descriptor = os.open(str(self.lock), os.O_RDWR)
        try:
            with self.assertRaises(BlockingIOError):
                fcntl.flock(descriptor, fcntl.LOCK_EX | fcntl.LOCK_NB)
        finally:
            os.close(descriptor)

    def spawn(self, command):
        environment = os.environ.copy()
        environment["PYTHONDONTWRITEBYTECODE"] = "1"
        process = subprocess.Popen(
            [sys.executable, "-c", WRAPPER, str(SCRIPT), str(self.lock)] + list(command),
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, env=environment,
        )
        self.addCleanup(self.cleanup_process, process)
        return process

    @staticmethod
    def cleanup_process(process):
        if process.poll() is None:
            process.terminate()
            try:
                process.communicate(timeout=6)
            except subprocess.TimeoutExpired:
                process.kill()
                process.communicate(timeout=3)
        else:
            process.communicate()

    def wait_for_file(self, path, timeout=8):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            if path.exists() and path.read_text().strip():
                return path.read_text().strip()
            time.sleep(0.02)
        self.fail("fixture did not become ready: %s" % path)


class ProcessRecognitionTests(unittest.TestCase):
    def runner(self, executable, arguments="", state="S"):
        return gate_module.is_test_runner(Process(50001, 1, state, executable, arguments))

    def test_native_runners_and_paths_with_spaces(self):
        for executable in (
            "/Applications/Xcode Beta.app/Contents/Developer/usr/bin/xctest",
            "/tmp/Product With Spaces.app/Contents/MacOS/ProjectUITests-Runner",
            "/tmp/XCTRunner",
            "/tmp/PackageTests.xctest/Contents/MacOS/PackageTests",
            "/sdk/flutter/bin/cache/artifacts/engine/darwin/flutter_tester",
            "/var/folders/random/go-build123/b001/engine.test",
        ):
            with self.subTest(executable=executable):
                self.assertTrue(self.runner(executable))

    def test_exact_hosted_xctest_option(self):
        executable = "/tmp/My Product.app/Contents/MacOS/印迹"
        self.assertTrue(self.runner(executable, executable + " -XCTest All"))
        self.assertFalse(self.runner(executable, executable + " --test-library --fixture sample"))
        self.assertFalse(self.runner(executable, executable + " --log /tmp/-XCTest.log"))
        self.assertFalse(self.runner("/bin/echo", "echo -XCTest"))
        self.assertTrue(self.runner("/tmp/engine.test", "engine.test -test.timeout=10m0s"))

    def test_native_runner_bundle_without_xctest_option(self):
        for executable in (
            "/tmp/PianoRoam-Runner.app/Contents/MacOS/PianoRoam-Runner",
            "/tmp/Build Products/My Product-Runner.app/Contents/MacOS/My Product-Runner",
        ):
            with self.subTest(executable=executable):
                self.assertTrue(self.runner(executable, executable + " -NSTreatUnknownArgumentsAsOpen NO -ApplePersistenceIgnoreState YES"))
        self.assertFalse(self.runner("/tmp/PianoRoam-Runner", "PianoRoam-Runner --preview"))
        self.assertFalse(self.runner("/tmp/PianoRoam-Runner.app/Contents/MacOS/Preview", "Preview"))
        self.assertFalse(self.runner("/tmp/PianoRoam.app/Contents/MacOS/PianoRoam", "PianoRoam --log PianoRoam-Runner.app"))

    def test_xcodebuild_actions_not_option_values(self):
        executable = "/Applications/Xcode Beta.app/Contents/Developer/usr/bin/xcodebuild"
        for arguments in (
            "test -scheme Product",
            "-project '/repo/Project With Spaces.xcodeproj' -scheme Product test",
            "-xctestrun '/tmp/Build Products/Plan.xctestrun' test-without-building",
            "-scheme test -configuration Debug test-without-building",
        ):
            with self.subTest(arguments=arguments):
                self.assertTrue(self.runner(executable, executable + " " + arguments))
        for arguments in (
            "build -scheme Product",
            "-scheme test -configuration test build",
            "-project test -destination test build-for-testing",
            "-scheme Product -showBuildSettings",
            "build TEST_LABEL=test",
        ):
            with self.subTest(arguments=arguments):
                self.assertFalse(self.runner(executable, executable + " " + arguments))

    def test_python_test_invocations(self):
        for executable, arguments in (
            ("/usr/bin/python3", "python3 -m pytest test_file.py"),
            ("/usr/bin/python3", "python3 -m unittest discover"),
            ("/Library/Developer Tools/Python", "/Library/Developer Tools/Python -I -W ignore -m unittest"),
            ("/opt/Python", "/opt/python3.9 -m pytest"),
            ("/usr/bin/python3", "python3 /venv/bin/pytest tests"),
            ("/venv/bin/pytest", "pytest tests"),
        ):
            with self.subTest(arguments=arguments):
                self.assertTrue(self.runner(executable, arguments))

    def test_javascript_test_invocations(self):
        for executable, arguments in (
            ("/usr/bin/node", "node /project/node_modules/playwright/cli.js test"),
            ("/usr/bin/node", "node /project/node_modules/@playwright/test/cli.js test --headed"),
            ("/usr/bin/node", "node /project/node_modules/.bin/playwright test"),
            ("/usr/bin/node", "node --require bootstrap.js /project/node_modules/cypress/bin/cypress run"),
            ("/opt/playwright", "playwright test"),
            ("/Applications/Cypress.app/Contents/MacOS/Cypress", "Cypress --run-project /project"),
        ):
            with self.subTest(arguments=arguments):
                self.assertTrue(self.runner(executable, arguments))

    def test_substrings_frontends_daemons_and_zombies_do_not_block(self):
        for executable, arguments, state in (
            ("/usr/bin/python3", "python3 -c 'print(\"pytest -m unittest\")'", "S"),
            ("/usr/bin/python3", "python3 report.py --description pytest", "S"),
            ("/Library/Python.framework/Versions/3.9/Python", "/usr/bin/python3 /repo/host-automation.py run -- /usr/bin/python3 -m pytest", "S"),
            ("/usr/bin/node", "node -e 'console.log(\"playwright test\")'", "S"),
            ("/usr/bin/node", "node report.js playwright test", "S"),
            ("/usr/bin/node", "node /project/node_modules/playwright/cli.js show-report", "S"),
            ("/usr/bin/node", "node /project/node_modules/cypress/bin/cypress open", "S"),
            ("/bin/zsh", "zsh -c 'python -m pytest'", "S"),
            ("/usr/bin/xcodebuild", "xcodebuild build -scheme ProductUITests-Runner", "S"),
            ("/usr/bin/node", "node xcodebuildmcp macos test", "S"),
            ("/usr/local/bin/go", "go test ./...", "S"),
            ("/tmp/example.test", "example.test --preview", "S"),
            ("/usr/libexec/testmanagerd", "testmanagerd", "S"),
            ("/tmp/xctest", "xctest tests", "Z"),
            ("/tmp/ProjectUITests-Runner", "ProjectUITests-Runner", "Z+"),
        ):
            with self.subTest(arguments=arguments, state=state):
                self.assertFalse(self.runner(executable, arguments, state))

    def test_self_and_ancestors_are_excluded(self):
        processes = [
            Process(100, 90, "S", "/usr/bin/python3", "python3 -m unittest"),
            Process(90, 80, "S", "/tmp/xctest"),
            Process(80, 1, "S", "/tmp/XCTRunner"),
            Process(101, 1, "S", "/tmp/xctest"),
        ]
        self.assertEqual([process.pid for process in gate_module.busy_processes(processes, 100, 90)], [101])

    def test_native_runner_and_xcodebuild_ancestors_are_excluded(self):
        executable = "/tmp/PianoRoam-Runner.app/Contents/MacOS/PianoRoam-Runner"
        processes = [
            Process(100, 90, "S", "/usr/bin/python3", "python3 host-automation.py wait"),
            Process(90, 80, "S", executable, executable),
            Process(80, 1, "S", "/usr/bin/xcodebuild", "xcodebuild -scheme PianoRoam test"),
            Process(101, 1, "S", executable, executable),
            Process(102, 1, "S", "/usr/bin/xcodebuild", "xcodebuild test-without-building"),
        ]
        self.assertEqual([process.pid for process in gate_module.busy_processes(processes, 100, 90)], [101, 102])

    def test_ps_columns_keep_full_executable_path(self):
        with mock.patch.object(gate_module, "_ps", side_effect=[
            " 42 1 S /Applications/Xcode Beta.app/Contents/Developer/usr/bin/xctest\n",
            " 42 /Applications/Xcode Beta.app/Contents/Developer/usr/bin/xctest bundle\n",
        ]) as reader:
            processes = gate_module.read_process_table()
        self.assertEqual(reader.call_args_list, [mock.call("pid=,ppid=,stat=,comm="), mock.call("pid=,args=")])
        self.assertEqual(processes[0].executable, "/Applications/Xcode Beta.app/Contents/Developer/usr/bin/xctest")
        self.assertTrue(gate_module.is_test_runner(processes[0]))

    def test_ps_failure_is_an_error(self):
        result = subprocess.CompletedProcess([], 1, stdout="", stderr="not available")
        with mock.patch.object(gate_module.subprocess, "run", return_value=result):
            with self.assertRaises(gate_module.AutomationError):
                gate_module.read_process_table()


class WaitingTests(GateFixtures):
    def test_busy_busy_idle_waits_exactly_three_seconds_each_time(self):
        active = [Process(50001, 1, "S", "/tmp/xctest", "xctest secret_test_data")]
        sleeps, logs = [], []
        self.gate([active, active, []], sleeps, logs).wait()
        self.assertEqual(sleeps, [3, 3])
        self.assertEqual(len(logs), 2)
        self.assertIn("50001 / xctest", logs[0])
        self.assertNotIn("secret_test_data", logs[0])

    def test_idle_and_resident_daemon_do_not_sleep(self):
        sleeps = []
        self.gate([[Process(50001, 1, "S", "/usr/libexec/testmanagerd")]], sleeps).wait()
        self.assertEqual(sleeps, [])

    def test_lock_is_private_and_keeps_the_same_inode(self):
        self.gate([[]]).wait()
        inode = self.lock.stat().st_ino
        self.gate([[]]).wait()
        self.assertEqual(self.lock.stat().st_ino, inode)
        self.assertEqual(stat.S_IMODE(self.lock.stat().st_mode), 0o600)
        self.assertEqual(stat.S_IMODE(self.lock.parent.stat().st_mode), 0o700)

    def test_ancestor_reentry_preserves_outer_lock_and_scans_runners(self):
        owner = 50001
        self.hold_lock({"owner_pid": owner})
        owner_process = Process(owner, 1, "S", "/usr/bin/python3")
        current = Process(os.getpid(), owner, "S", "/usr/bin/python3")
        external = Process(50002, 1, "S", "/tmp/xctest")
        sleeps = []
        self.gate([[owner_process, current], [owner_process, current, external], [owner_process, current]], sleeps).wait()
        self.assertEqual(sleeps, [3])
        self.assert_lock_held()

    def test_detached_matching_session_can_reenter(self):
        owner = 50001
        self.hold_lock({"owner_pid": owner, "session_token": "fixture-secret"})
        table = [Process(owner, 1, "S", "/usr/bin/python3")]
        sleeps = []
        with mock.patch.dict(os.environ, {gate_module.OWNER_ENV: str(owner), gate_module.TOKEN_ENV: "fixture-secret"}):
            self.gate([table, table], sleeps).wait()
        self.assertEqual(sleeps, [])
        self.assert_lock_held()

    def test_nested_run_fails_instead_of_waiting_for_its_own_ancestor(self):
        owner = 50001
        self.hold_lock({"owner_pid": owner})
        table = [Process(owner, 1, "S", "/usr/bin/python3"), Process(os.getpid(), owner, "S", "/usr/bin/python3")]
        sleeps = []
        marker = self.directory / "must-not-launch"
        with self.assertRaisesRegex(gate_module.AutomationError, "已处于受保护测试命令中"):
            self.gate([table], sleeps).run([sys.executable, "-c", "from pathlib import Path; Path(%r).touch()" % str(marker)])
        self.assertEqual(sleeps, [])
        self.assertFalse(marker.exists())
        self.assert_lock_held()

    def test_wrong_session_waits_until_lock_released(self):
        owner = 50001
        descriptor = self.hold_lock({"owner_pid": owner, "session_token": "correct-secret"})
        sleeps = []
        def release_after_sleep(seconds):
            sleeps.append(seconds)
            fcntl.flock(descriptor, fcntl.LOCK_UN)
        gate = self.gate([[Process(owner, 1, "S", "/usr/bin/python3")], []], sleeps)
        gate.sleeper = release_after_sleep
        with mock.patch.dict(os.environ, {gate_module.OWNER_ENV: str(owner), gate_module.TOKEN_ENV: "wrong-secret"}):
            gate.wait()
        self.assertEqual(sleeps, [3])

    def test_owner_must_be_alive_for_session_reentry(self):
        owner = 50001
        descriptor = self.hold_lock({"owner_pid": owner, "session_token": "correct-secret"})
        sleeps = []
        def release_after_sleep(seconds):
            sleeps.append(seconds)
            fcntl.flock(descriptor, fcntl.LOCK_UN)
        gate = self.gate([[], []], sleeps)
        gate.sleeper = release_after_sleep
        with mock.patch.dict(os.environ, {gate_module.OWNER_ENV: str(owner), gate_module.TOKEN_ENV: "correct-secret"}):
            gate.wait()
        self.assertEqual(sleeps, [3])

    def test_process_read_failure_releases_lock_and_does_not_launch(self):
        gate = gate_module.HostGate(self.lock, process_provider=mock.Mock(side_effect=gate_module.AutomationError("fixture ps failed")))
        marker = self.directory / "must-not-exist"
        with self.assertRaises(gate_module.AutomationError):
            gate.run([sys.executable, "-c", "from pathlib import Path; Path(%r).touch()" % str(marker)])
        self.assertFalse(marker.exists())
        self.gate([[]]).wait()


class SubprocessTests(GateFixtures):
    def test_two_run_commands_never_overlap(self):
        events = self.directory / "events.jsonl"
        worker = self.directory / "record.py"
        worker.write_text(
            "import json,sys,time\n"
            "from pathlib import Path\n"
            "path=Path(sys.argv[1])\n"
            "def record(kind):\n"
            "    with path.open('a') as stream: stream.write(json.dumps([sys.argv[2],kind,time.time()])+'\\n')\n"
            "record('start')\n"
            "time.sleep(0.5)\n"
            "record('end')\n"
        )
        first = self.spawn([sys.executable, str(worker), str(events), "first"])
        self.wait_for_file(events)
        second = self.spawn([sys.executable, str(worker), str(events), "second"])
        self.assertEqual(first.communicate(timeout=8)[1], "")
        _, second_error = second.communicate(timeout=8)
        self.assertEqual(first.returncode, 0)
        self.assertEqual(second.returncode, 0, second_error)
        records = [json.loads(line) for line in events.read_text().splitlines()]
        self.assertEqual([(record[0], record[1]) for record in records], [("first", "start"), ("first", "end"), ("second", "start"), ("second", "end")])
        self.assertGreaterEqual(records[2][2], records[1][2])
        self.assertIn("3 秒后重试", second_error)

    def test_child_failure_exit_code_is_preserved(self):
        process = self.spawn([sys.executable, "-c", "import sys; sys.exit(7)"])
        process.communicate(timeout=5)
        self.assertEqual(process.returncode, 7)
        self.gate([[]]).wait()

    def test_owner_crash_releases_os_lock(self):
        ready = self.directory / "child.pid"
        process = self.spawn([sys.executable, "-c", "import os,time; from pathlib import Path; Path(%r).write_text(str(os.getpid())); time.sleep(30)" % str(ready)])
        child_pid = int(self.wait_for_file(ready))
        try:
            process.kill()
            # Its intentionally surviving child still holds the stdout pipe;
            # wait only for the killed lock owner before checking flock.
            process.wait(timeout=5)
            sleeps = []
            self.gate([[]], sleeps).wait()
            self.assertEqual(sleeps, [])
        finally:
            try:
                os.killpg(child_pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            process.communicate(timeout=5)

    def test_cancel_terminates_child_process_group_and_releases_lock(self):
        ready = self.directory / "family.json"
        child = self.directory / "family.py"
        child.write_text(
            "import json,os,signal,subprocess,sys,time\n"
            "from pathlib import Path\n"
            "signal.signal(signal.SIGTERM, signal.SIG_IGN)\n"
            "grandchild=subprocess.Popen([sys.executable,'-c','import signal,time; signal.signal(signal.SIGTERM, signal.SIG_IGN); time.sleep(30)'])\n"
            "Path(sys.argv[1]).write_text(json.dumps([os.getpid(),grandchild.pid]))\n"
            "time.sleep(30)\n"
        )
        process = self.spawn([sys.executable, str(child), str(ready)])
        family = json.loads(self.wait_for_file(ready))
        try:
            process.terminate()
            process.communicate(timeout=8)
            self.assertEqual(process.returncode, 128 + signal.SIGTERM)
            for pid in family:
                state = subprocess.run(["/bin/ps", "-p", str(pid), "-o", "stat="], stdout=subprocess.PIPE, text=True).stdout.strip()
                self.assertTrue(not state or state.startswith("Z"), "fixture child %s is still active: %s" % (pid, state))
            self.gate([[]]).wait()
        finally:
            try:
                os.killpg(family[0], signal.SIGKILL)
            except ProcessLookupError:
                pass


if __name__ == "__main__":
    unittest.main(verbosity=2)
