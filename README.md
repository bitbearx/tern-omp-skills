# OMP Skills for Tern

在 Tern 左侧浏览已安装的 OMP Skills：按名称 A–Z 排序，搜索名称、简介、来源或文件路径，按侧栏高度自动分页。点击条目将 **Skill 名称** 复制到系统剪贴板，并显示成功提示；不会执行 Skill，也不会复制整个文件。

## 安装

需要 Tern，以及支持 `omp skill list --json` 的 OMP（本机使用 18.20.3）。没有 Python 或第三方包运行时依赖。

```sh
cd tern-omp-skills
tern plugin link .
```

侧边栏默认隐藏。点击窗口右上角的 Skills 搜索图标，或在命令面板运行 `OMP Skills: toggle sidebar`。该入口位于 History 图标左侧，不覆盖 History。不注册默认快捷键，避免抢占 Tern 预设按键。

- 搜索按钮打开搜索框；清除按钮恢复完整列表。搜索不区分大小写，按字面子串匹配，搜索后回到第一页。
- 底部显示当前页、总页数和匹配数量；窗口高度变化后调整每页条数。
- 每个标签页独立保存搜索和页码，使用打开侧栏时工作窗格的目录发现 Skills。
- 点击刷新立即重新读取；可见时每 30 秒刷新，隐藏时不启动扫描。
- 关闭侧栏会隐藏其他标签页的 Skills 侧栏；关闭整个标签不会隐藏其他标签的侧栏。显示状态会保存。
- 悬停条目查看完整简介和文件路径。

沿用 History 的原生画布及主题样式。Tern 的 `tiles` 布局在多面板标签中可能把侧栏放到视口外，遇到时请切换 `rail`；插件不会改动全局布局。工具栏使用 Tern 小组件；若小组件栏被隐藏，可通过命令面板打开侧栏。

## 数据来源

直接运行本地 `omp skill list --json`，由 OMP 负责全局、当前项目、共享目录、`skills.customDirectories`、managed skills、链接及同名冲突的发现规则；不另写目录扫描器。这里展示的是 **OMP Skills，不是 Tern 插件或 OMP 扩展列表**。隐藏于模型提示词的 Skill 只要出现在该命令结果中，也会列出。

环境继承 Tern 窗口进程，包括 `PI_CODING_AGENT_DIR`、`OMP_PROFILE` 等；不是读取某个运行中 OMP 会话的临时命令行参数。仅支持本机目录，不查询远程主机。目录变化会在下一次刷新时重新发现。

macOS 默认优先使用 Tern 自带的 `~/Library/Application Support/Tern/omp/bin/omp`，其他情况使用 PATH 中的 `omp`。可在启动 Tern 前设置 `OMP_EXE` 指向指定 OMP 可执行文件，`TERN_EXE` 可覆盖尺寸查询使用的 Tern 路径。

读取失败会显示错误，不伪装为空列表；修复 OMP 路径或权限后点刷新。若底部出现发现警告，在相同目录运行 `omp skill list --json` 查看 `warnings`。插件自身不调用模型，也不上传 Skill 内容。

## 开发

- `window.luau`：原生侧栏生命周期、异步发现、搜索/复制事件、尺寸和分页状态。
- `catalog.luau`：OMP JSON 索引校验、稳定排序及字面搜索。
- `view.luau`：列表、工具栏和分页视图。
- `skills.css`：主题样式、Skills 工具栏入口。
- `plugin.toml`：插件声明。
- `tern.d.luau`：由 `tern plugin types .` 生成的 Tern API 类型。

修改源码后 Tern 自动重载。卸载链接：

```sh
tern plugin unlink omp-skills
```

运行核心 UI 回归测试（需要 `python3`，会打开使用临时技能库和独立配置的真实 Tern 窗口）：

```sh
OMP_SKILLS_UI_TEST=1 python3 -m unittest -v test_sidebar
```

覆盖跨页排序与完整性、搜索重置页码、空结果、macOS 系统剪贴板、刷新中关闭及重新打开。
