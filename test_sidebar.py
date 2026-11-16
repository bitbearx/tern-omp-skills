#!/usr/bin/env python3
"""在隔离的真实 Tern 窗口中验证 Skills 侧栏的核心交互。"""

import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time
import unittest


TERN = shutil.which("tern")
OMP = shutil.which("omp")
PLUGIN = Path(__file__).resolve().parent


@unittest.skipUnless(
    TERN and OMP and os.environ.get("OMP_SKILLS_UI_TEST") == "1",
    "需要 Tern、OMP 和 OMP_SKILLS_UI_TEST=1；会打开隔离窗口",
)
class SkillsSidebarTest(unittest.TestCase):
    """使用真实 SKILL.md 和 OMP 发现入口，不替换列表或剪贴板实现。"""

    @classmethod
    def setUpClass(cls):
        """创建隔离配置和技能文件，避免读取或修改用户的技能库。"""
        cls.temp = tempfile.TemporaryDirectory(prefix="omp-skills-test-", dir="/tmp")
        cls.root = Path(cls.temp.name)
        cls.config = cls.root / "config"
        cls.home = cls.root / "home"
        cls.workspace = cls.root / "workspace"
        cls.agent = cls.home / ".omp" / "agent"
        cls.config.mkdir()
        cls.workspace.mkdir()
        cls.agent.mkdir(parents=True)
        # Tern 的工具安装器只看临时 PATH，不会覆盖用户的 omp 命令链接。
        binaries = cls.root / "bin"
        binaries.mkdir()
        (binaries / "omp").symlink_to(OMP)
        (binaries / "tern").symlink_to(TERN)
        cls.names = [f"skill-{index:02}" for index in range(24)] + ["zulu"]
        for name in reversed(cls.names):
            base = cls.root / "custom" if name == "zulu" else cls.agent / "skills"
            path = base / name / "SKILL.md"
            path.parent.mkdir(parents=True)
            description = "Unique NeedLE 中文搜索" if name == "skill-17" else f"Description of {name}"
            path.write_text(f"---\nname: {name}\ndescription: {description}\n---\nTest skill.\n", encoding="utf-8")
        (cls.agent / "config.yml").write_text(
            f"skills:\n  customDirectories:\n    - {cls.root / 'custom'}\n", encoding="utf-8"
        )
        (cls.config / "settings.json").write_text(
            json.dumps({"tabs": "Vertical", "pane_headers": "Split", "widgets": [{"id": "cpu"}]}),
            encoding="utf-8",
        )
        cls.env = os.environ.copy()
        cls.env.pop("OMP_PROFILE", None)
        cls.env.update({
            "HOME": str(cls.home), "PI_CODING_AGENT_DIR": str(cls.agent),
            "TERN_CONFIG_DIR": str(cls.config), "TERN_DAEMON_SOCKET": str(cls.root / "daemon.sock"),
            "STENCIL_LOG_DIR": str(cls.root / "logs"), "OMP_EXE": OMP,
            "PATH": str(binaries) + os.pathsep + "/usr/bin:/bin:/usr/sbin:/sbin",
        })
        cls.control = str(cls.root / "control.sock")
        cls.window = None
        cls.log = (cls.root / "window.log").open("w", encoding="utf-8")
        cls.addClassCleanup(cls.cleanup)
        subprocess.run(
            [TERN, "plugin", "link", str(PLUGIN)], cwd=cls.workspace, env=cls.env,
            capture_output=True, text=True, check=True, timeout=15,
        )
        cls.window = subprocess.Popen(
            [TERN, "--control", cls.control, str(cls.workspace)], cwd=cls.workspace,
            env=cls.env, stdout=cls.log, stderr=cls.log,
        )
        deadline = time.monotonic() + 30
        while time.monotonic() < deadline:
            try:
                if cls.ctl("tree", '[title="显示/隐藏 OMP Skills"]').get("count") == 1:
                    cls.ctl("key", "Escape")
                    return
            except (OSError, subprocess.SubprocessError, json.JSONDecodeError):
                pass
            if cls.window.poll() is not None:
                break
            time.sleep(0.1)
        raise RuntimeError("隔离窗口启动失败：" + (cls.root / "window.log").read_text())

    @classmethod
    def cleanup(cls):
        """关闭本测试拥有的窗口和会话，再清除临时目录。"""
        if cls.window and cls.window.poll() is None:
            try:
                cls.ctl("quit")
                cls.window.wait(timeout=10)
            except (OSError, subprocess.SubprocessError):
                cls.window.terminate()
                cls.window.wait(timeout=10)
        # 只停止独立 socket 对应的守护进程，不触碰用户的 Tern 会话。
        subprocess.run(
            [TERN, "daemon", "stop", "--socket", str(cls.root / "daemon.sock")],
            cwd=cls.workspace, env=cls.env, capture_output=True, timeout=10,
        )
        cls.log.close()
        cls.temp.cleanup()

    @classmethod
    def ctl(cls, *args):
        """执行原生控制命令，失败时保留 Tern 的错误输出。"""
        result = subprocess.run(
            [TERN, "ctl", "--control", cls.control, *args], cwd=cls.workspace,
            env=cls.env, check=True, capture_output=True, text=True, timeout=15,
        )
        return json.loads(result.stdout)

    def texts(self, selector):
        """提取真实渲染节点的文字，不从实现状态伪造预期结果。"""
        return [node.get("text", "") for node in self.ctl("tree", selector)["nodes"]]

    def click(self, selector):
        """点击控件并等待下一次 UI 事件处理。"""
        self.ctl("click", selector)
        self.ctl("wait", "150")

    def search(self, value):
        """通过用户可见的输入框提交搜索。"""
        self.click('[title="搜索 Skills"]')
        self.assertEqual(self.ctl("tree", '[placeholder="搜索名称、简介、来源或路径"]')["count"], 1)
        self.ctl("key", "Meta+a")
        self.ctl("type", value)
        self.ctl("key", "Enter")
        self.ctl("wait", "150")

    def test_native_catalog_interactions_and_close_during_refresh(self):
        """验证排序、跨页完整性、搜索、复制，以及刷新中关闭后的重建。"""
        self.ctl("plugins", "run", "plugin.omp-skills.toggle")
        deadline = time.monotonic() + 15
        while time.monotonic() < deadline:
            if self.texts(".omp-skills-count") == ["25 个 Skills"]:
                break
            self.ctl("wait", "150")
        self.assertEqual(self.texts(".omp-skills-count"), ["25 个 Skills"])
        self.ctl("wait", "2300")
        # 首次启动的登录卡可能晚于插件加载；关闭它后再点击侧栏。
        self.ctl("key", "Escape")
        actual = []
        for _ in range(25):
            actual.extend(self.texts(".omp-skills-name"))
            page, total = map(int, self.texts(".omp-skills-page")[0].split("/"))
            if page == total:
                break
            self.click('[title="下一页 Skills"]')
            self.assertEqual(int(self.texts(".omp-skills-page")[0].split("/")[0]), page + 1)
        self.assertGreater(total, 1)
        self.assertEqual(actual, self.names)
        self.assertEqual(self.texts(".omp-skills-name")[-1], "zulu")

        if shutil.which("pbpaste") and shutil.which("pbcopy"):
            clipboard = subprocess.run(["pbpaste"], check=True, capture_output=True).stdout
            try:
                self.click(".omp-skills-card:last-child")
                copied = subprocess.run(["pbpaste"], check=True, capture_output=True).stdout.decode()
                self.assertEqual(copied, "zulu")
            finally:
                subprocess.run(["pbcopy"], input=clipboard, check=True)

        self.search("nEeDlE")
        self.assertEqual(self.texts(".omp-skills-name"), ["skill-17"])
        self.assertEqual(self.texts(".omp-skills-page"), ["1 / 1"])
        self.search("[missing.*]")
        self.assertEqual(self.texts(".omp-skills-name"), [])
        self.assertEqual(self.texts(".omp-skills-page"), ["1 / 1"])
        self.assertIn("没有匹配", "".join(self.texts(".omp-skills-list")))
        self.click('[title="清除搜索"]')
        self.assertEqual(self.texts(".omp-skills-name")[0], "skill-00")

        self.ctl("click", '[title="刷新 Skills"]')
        self.ctl("plugins", "run", "plugin.omp-skills.toggle")
        self.ctl("wait", "2300")
        self.assertEqual(self.texts(".omp-skills-list"), [])
        self.ctl("plugins", "run", "plugin.omp-skills.toggle")
        self.ctl("wait", "1500")
        self.assertEqual(self.texts(".omp-skills-count"), ["25 个 Skills"])
        self.assertEqual(self.texts(".omp-skills-name")[0], "skill-00")
        self.assertNotIn('plugin handler failed plugin="omp-skills"', (self.root / "window.log").read_text())


if __name__ == "__main__":
    unittest.main()
