#!/usr/bin/env python3
"""Wait for active host test runners; hold a user-wide lock for wrapped commands.

The CLI deliberately has no alternate-lock or process-filter switches. Tests use
the injectable Python API with private fixtures under the repository's TMP/.
"""

from __future__ import annotations

import argparse
import contextlib
import errno
import fcntl
import json
import os
from pathlib import Path
import re
import secrets
import shlex
import signal
import stat
import subprocess
import sys
import time
from dataclasses import dataclass
from typing import Callable, Iterable, Optional, Sequence


POLL_SECONDS = 3
LOCK_PATH = Path("/tmp") / ("whisperingtime-host-automation-%s" % os.getuid()) / "host.lock"
OWNER_ENV = "ANMOTE_HOST_AUTOMATION_OWNER"
TOKEN_ENV = "ANMOTE_HOST_AUTOMATION_TOKEN"


class AutomationError(RuntimeError):
    pass


class Cancelled(AutomationError):
    def __init__(self, signum: int):
        super().__init__("自动化测试等待或执行已取消。")
        self.signum = signum


@dataclass(frozen=True)
class Process:
    pid: int
    ppid: int
    state: str
    executable: str
    arguments: str = ""

    @property
    def name(self) -> str:
        return os.path.basename(self.executable)


def _ps(columns: str) -> str:
    try:
        result = subprocess.run(
            ["/bin/ps", "-A", "-ww", "-o", columns],
            check=False, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            text=True,
        )
    except OSError as error:
        raise AutomationError("无法读取主机进程，未启动自动化测试：%s" % error) from error
    if result.returncode:
        raise AutomationError("无法读取主机进程（ps 退出码 %s），未启动自动化测试。" % result.returncode)
    return result.stdout


def read_process_table() -> list[Process]:
    # comm must be the final column: executable paths may themselves contain
    # spaces. Read args separately, retaining pid as the only merge key.
    commands = _ps("pid=,ppid=,stat=,comm=")
    arguments = _ps("pid=,args=")
    args_by_pid = {}
    for line in arguments.splitlines():
        parts = line.strip().split(None, 1)
        if parts and parts[0].isdigit():
            args_by_pid[int(parts[0])] = parts[1] if len(parts) == 2 else ""
    result = []
    for line in commands.splitlines():
        parts = line.strip().split(None, 3)
        if len(parts) != 4 or not parts[0].isdigit() or not parts[1].isdigit():
            if line.strip():
                raise AutomationError("无法解析主机进程列表，未启动自动化测试。")
            continue
        pid = int(parts[0])
        result.append(Process(pid, int(parts[1]), parts[2], parts[3], args_by_pid.get(pid, "")))
    if not result:
        raise AutomationError("主机进程列表为空，未启动自动化测试。")
    return result


def ancestor_pids(processes: Iterable[Process], pid: int, parent_pid: Optional[int] = None) -> set[int]:
    parents = {process.pid: process.ppid for process in processes}
    if parent_pid is not None:
        parents.setdefault(pid, parent_pid)
    result = set()
    while pid > 0 and pid not in result:
        result.add(pid)
        pid = parents.get(pid, 0)
    return result


def _words(value: str) -> list[str]:
    try:
        return shlex.split(value)
    except ValueError:
        # ps has no argv boundary encoding. An unmatched quote in an argument
        # must not stop us recognizing the executable or a leading -m option.
        return value.split()


def _arguments_after_executable(process: Process) -> list[str]:
    command = process.arguments.strip()
    executable = process.executable
    if command == executable:
        return []
    if command.startswith(executable + " "):
        return _words(command[len(executable):])
    words = _words(command)
    if not words:
        return []
    # ps comm may resolve a Python/Node symlink while argv[0] keeps its original
    # spelling. Match only the leading interpreter path, including its spaces.
    name = process.name.lower()
    if re.fullmatch(r"python(?:\d+(?:\.\d+)*)?", name):
        match = re.match(r"^(?:.*?/)?(?:python(?:\d+(?:\.\d+)*)?|Python)(?=\s|$)", command)
        if match:
            return _words(command[match.end():])
    if name in {"node", "nodejs"}:
        match = re.match(r"^(?:.*?/)?(?:node|nodejs)(?=\s|$)", command)
        if match:
            return _words(command[match.end():])
    return words[1:]


def _python_test(arguments: Sequence[str]) -> bool:
    index = 0
    while index < len(arguments):
        argument = arguments[index]
        if argument == "--":
            index += 1
            break
        if argument in {"-c", "-h", "--help", "-V", "--version"} or argument.startswith("-c"):
            return False
        if argument == "-m":
            return index + 1 < len(arguments) and arguments[index + 1] in {"pytest", "unittest"}
        if argument.startswith("-m"):
            return argument[2:] in {"pytest", "unittest"}
        if argument in {"-W", "-X"}:
            index += 2
        elif argument.startswith("-"):
            index += 1
        else:
            break
    if index >= len(arguments):
        return False
    script = Path(arguments[index])
    return script.name.lower() in {"pytest", "py.test", "pytest.py"} or (
        script.name == "__main__.py" and script.parent.name == "unittest"
    )


def _node_script(arguments: Sequence[str]) -> Optional[tuple[str, Sequence[str]]]:
    index = 0
    value_options = {"-r", "--require", "--import", "--loader", "--experimental-loader", "-C", "--conditions", "--inspect-port"}
    while index < len(arguments):
        argument = arguments[index]
        if argument == "--":
            index += 1
            break
        if argument in {"-e", "--eval", "-p", "--print", "--check", "-c"} or argument.startswith(("--eval=", "--print=")):
            return None
        if argument in value_options:
            index += 2
        elif argument.startswith("-"):
            index += 1
        else:
            break
    if index >= len(arguments):
        return None
    return arguments[index], arguments[index + 1:]


def _javascript_test(script: str, arguments: Sequence[str]) -> bool:
    path = Path(script)
    name = path.name.lower()
    parts = {part.lower() for part in path.parts}
    playwright = name in {"playwright", "playwright.js"} or (
        name == "cli.js" and bool(parts & {"playwright", "playwright-core", "@playwright"})
    )
    cypress = name in {"cypress", "cypress.js"} or (name == "index.js" and "cypress" in parts)
    return bool(arguments) and ((playwright and arguments[0] == "test") or (cypress and arguments[0] == "run"))


def is_test_runner(process: Process) -> bool:
    if process.state.upper().startswith("Z"):
        return False
    name = process.name.lower()
    if name in {"xctest", "xctrunner", "flutter_tester", "pytest", "py.test"} or "uitests-runner" in name:
        return True
    # A hosted XCTest bundle runs inside the application executable. The exact
    # leading XCTest option distinguishes that host from ordinary QA launches.
    arguments = _arguments_after_executable(process)
    if "-XCTest" in arguments and re.search(r"\.app/Contents/MacOS/[^/]+$", process.executable):
        return True
    if re.search(r"\.xctest/Contents/MacOS/[^/]+$", process.executable):
        return True
    if name.endswith(".test") and (
        any(part.startswith("go-build") for part in Path(process.executable).parts)
        or any(argument.startswith("-test.") for argument in arguments)
    ):
        return True
    if re.fullmatch(r"python(?:\d+(?:\.\d+)*)?", name):
        return _python_test(arguments)
    if name in {"node", "nodejs"}:
        invocation = _node_script(arguments)
        return bool(invocation and _javascript_test(*invocation))
    if name in {"playwright", "cypress"}:
        return _javascript_test(name, arguments) or (name == "cypress" and "--run-project" in arguments)
    return False


def busy_processes(processes: Sequence[Process], pid: Optional[int] = None, parent_pid: Optional[int] = None) -> list[Process]:
    pid = os.getpid() if pid is None else pid
    parent_pid = os.getppid() if parent_pid is None else parent_pid
    excluded = ancestor_pids(processes, pid, parent_pid)
    return [process for process in processes if process.pid not in excluded and is_test_runner(process)]


class _Cancellation:
    def __init__(self, clock: Callable[[], float]):
        self.clock = clock
        self.signum = None
        self.cancelled_at = None
        self.child = None
        self.previous = {}

    def __enter__(self):
        for signum in (signal.SIGINT, signal.SIGTERM):
            self.previous[signum] = signal.signal(signum, self._handle)
        return self

    def __exit__(self, *_):
        for signum, previous in self.previous.items():
            signal.signal(signum, previous)

    def _signal_group(self, signum: int):
        if self.child is not None:
            try:
                os.killpg(self.child.pid, signum)
            except ProcessLookupError:
                pass

    def _handle(self, signum, _frame):
        if self.signum is None:
            self.signum = signum
            self.cancelled_at = self.clock()
            self._signal_group(signum)
        else:
            self._signal_group(signal.SIGKILL)

    def check(self):
        if self.signum is not None:
            raise Cancelled(self.signum)

    def attach(self, child: subprocess.Popen):
        self.child = child
        if self.signum is not None:
            self._signal_group(self.signum)

    def reap(self) -> int:
        try:
            while True:
                try:
                    result = self.child.wait(timeout=0.1)
                    break
                except subprocess.TimeoutExpired:
                    if self.signum is not None and self.clock() - self.cancelled_at >= POLL_SECONDS:
                        self._signal_group(signal.SIGKILL)
            if self.signum is not None:
                # The direct child may exit before its own children. They all
                # belong to our private process group, so finish cancellation.
                self._signal_group(signal.SIGKILL)
                raise Cancelled(self.signum)
            return result if result >= 0 else 128 - result
        except BaseException:
            self._signal_group(signal.SIGKILL)
            self.child.wait()
            raise
        finally:
            self.child = None


class HostGate:
    def __init__(
        self, lock_path: Path = LOCK_PATH,
        process_provider: Callable[[], list[Process]] = read_process_table,
        sleeper: Callable[[float], None] = time.sleep,
        clock: Callable[[], float] = time.monotonic,
        logger: Optional[Callable[[str], None]] = None,
    ):
        self.lock_path = Path(lock_path)
        self.process_provider = process_provider
        self.sleeper = sleeper
        self.clock = clock
        self.logger = logger or (lambda value: print(value, file=sys.stderr, flush=True))
        self.session_token = secrets.token_hex(32)

    def _open_lock(self) -> int:
        directory = self.lock_path.parent
        directory.mkdir(mode=0o700, parents=True, exist_ok=True)
        info = directory.lstat()
        if not stat.S_ISDIR(info.st_mode) or info.st_uid != os.getuid():
            raise AutomationError("自动化测试锁目录不安全，未启动测试。")
        directory.chmod(0o700)
        flags = os.O_RDWR | os.O_CREAT | getattr(os, "O_NOFOLLOW", 0) | getattr(os, "O_CLOEXEC", 0)
        descriptor = os.open(str(self.lock_path), flags, 0o600)
        info = os.fstat(descriptor)
        if not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid():
            os.close(descriptor)
            raise AutomationError("自动化测试锁文件不安全，未启动测试。")
        os.fchmod(descriptor, 0o600)
        return descriptor

    @staticmethod
    def _metadata(descriptor: int) -> dict:
        try:
            os.lseek(descriptor, 0, os.SEEK_SET)
            value = json.loads(os.read(descriptor, 4096).decode("utf-8"))
            return value if isinstance(value, dict) else {}
        except (ValueError, UnicodeError):
            return {}

    @staticmethod
    def _write_metadata(descriptor: int, value: dict):
        encoded = json.dumps(value).encode("utf-8")
        os.lseek(descriptor, 0, os.SEEK_SET)
        os.write(descriptor, encoded)
        os.ftruncate(descriptor, len(encoded))

    def _sleep(self, cancellation: _Cancellation):
        cancellation.check()
        self.sleeper(POLL_SECONDS)
        cancellation.check()

    @contextlib.contextmanager
    def _idle_lock(self, cancellation: _Cancellation, allow_ancestor: bool = False):
        descriptor = self._open_lock()
        locked = False
        try:
            while True:
                cancellation.check()
                try:
                    fcntl.flock(descriptor, fcntl.LOCK_EX | fcntl.LOCK_NB)
                    locked = True
                    self._write_metadata(descriptor, {"owner_pid": os.getpid(), "session_token": self.session_token})
                    break
                except OSError as error:
                    if error.errno not in {errno.EACCES, errno.EAGAIN}:
                        raise
                    processes = self.process_provider()
                    metadata = self._metadata(descriptor)
                    owner = metadata.get("owner_pid")
                    ancestors = ancestor_pids(processes, os.getpid(), os.getppid())
                    holder = next((process for process in processes if process.pid == owner), None)
                    # Xcode can dispatch its pre-action through a detached build
                    # service. A fresh per-run secret follows the child env; it
                    # only permits reentry while that live owner holds flock.
                    token = metadata.get("session_token")
                    same_session = (
                        isinstance(token, str) and bool(token)
                        and os.environ.get(OWNER_ENV) == str(owner)
                        and secrets.compare_digest(os.environ.get(TOKEN_ENV, ""), token)
                    )
                    protected_session = isinstance(owner, int) and holder and not holder.state.upper().startswith("Z") and (owner in ancestors or same_session)
                    if protected_session:
                        if allow_ancestor:
                            break
                        raise AutomationError("已处于受保护测试命令中，无需重复使用 run 包装。")
                    detail = "PID %s / %s" % (owner if isinstance(owner, int) else "未知", holder.name if holder else "未知可执行文件")
                    self.logger("主机自动化测试锁正被占用（%s）；3 秒后重试。" % detail)
                    self._sleep(cancellation)
            while True:
                cancellation.check()
                active = busy_processes(self.process_provider())
                if not active:
                    break
                detail = "、".join("PID %s / %s" % (process.pid, process.name) for process in active)
                self.logger("检测到主机正在自动化测试（%s）；3 秒后重试。" % detail)
                self._sleep(cancellation)
            yield
        finally:
            try:
                if locked:
                    try:
                        self._write_metadata(descriptor, {})
                    finally:
                        fcntl.flock(descriptor, fcntl.LOCK_UN)
            finally:
                os.close(descriptor)

    def wait(self):
        """Point-in-time Xcode pre-action check; an owning ancestor may reenter."""
        with _Cancellation(self.clock) as cancellation:
            with self._idle_lock(cancellation, allow_ancestor=True):
                cancellation.check()

    def run(self, command: Sequence[str]) -> int:
        if not command:
            raise AutomationError("未提供要执行的自动化测试命令。")
        with _Cancellation(self.clock) as cancellation:
            with self._idle_lock(cancellation):
                cancellation.check()
                try:
                    environment = os.environ.copy()
                    environment[OWNER_ENV] = str(os.getpid())
                    environment[TOKEN_ENV] = self.session_token
                    child = subprocess.Popen(list(command), start_new_session=True, env=environment)
                except OSError as error:
                    raise AutomationError("无法启动自动化测试命令：%s" % error) from error
                cancellation.attach(child)
                return cancellation.reap()


def main(argv: Optional[Sequence[str]] = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="action", required=True)
    commands.add_parser("wait", help="等待主机测试空闲，供 Xcode TestAction PreAction 使用")
    runner = commands.add_parser("run", help="等待空闲后持锁执行测试命令")
    runner.add_argument("command", nargs=argparse.REMAINDER)
    arguments = parser.parse_args(argv)
    try:
        gate = HostGate()
        if arguments.action == "wait":
            gate.wait()
            return 0
        command = arguments.command
        if command[:1] == ["--"]:
            command = command[1:]
        return gate.run(command)
    except Cancelled as error:
        print(str(error), file=sys.stderr)
        return 128 + error.signum
    except (AutomationError, OSError) as error:
        print("自动化测试排队失败：%s" % error, file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
