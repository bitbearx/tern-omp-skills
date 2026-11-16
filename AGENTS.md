# 开发约定

- 默认不提交代码，不创建 worktree。
- 新增函数使用中文注释；保持模块职责单一。
- 验证使用隔离 Tern 配置与守护进程，不改动用户现有 History 插件。

## 模块索引

- 根目录：`plugin.toml` 插件声明；`window.luau` 生命周期、事件及异步加载。
- `catalog.luau`：OMP 原生技能列表解码、排序、搜索。
- `view.luau` / `skills.css`：侧边栏视图及主题样式。
- `tern.d.luau`：生成的 API 类型，不手工修改。
- `README.md`：安装、数据来源、使用约定。
- `test_sidebar.py`：隔离 Tern 窗口中的核心交互回归测试。
