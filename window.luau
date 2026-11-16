-- OMP Skills 侧边栏：每个标签独立维护目录、搜索条件和分页状态。
local catalog = require("./catalog")
local view = require("./view")
local TITLE = "OMP Skills"
local panes = {}
local opening = false
local sizing = false
local next_size_check = 0
local home = tern.getenv("HOME") or tern.getenv("USERPROFILE") or "."
local omp_executable = tern.getenv("OMP_EXE")
if not omp_executable or omp_executable == "" then
	local bundled = home .. "/Library/Application Support/Tern/omp/bin/omp"
	omp_executable = if tern.runtime.os == "macos" and tern.fs.exists(bundled) then bundled else "omp"
end
local tern_executable = tern.getenv("TERN_EXE")
if not tern_executable or tern_executable == "" then
	local app = "/Applications/Tern.app/Contents/MacOS/tern"
	tern_executable = if tern.runtime.os == "macos" and tern.fs.exists(app) then app else "tern"
end

-- 只操作本插件的原生面板，不影响 History 或其他插件。
local function owned(canvas)
	return canvas.owner == tern.plugin.id and canvas.title == TITLE
end

-- 初始化标签独立的 UI 状态，重载时可从已有面板恢复。
local function new_state(tab, origin)
	return {
		tab = tab, origin = origin, cwd = home,
		rows = {}, filtered = {}, query = "", page = 1, size = 8,
		loading = false, error = nil, warnings = 0,
	}
end

-- 优先沿用打开侧栏的工作窗格，关闭后再选择同标签中的本地工作目录。
local function working_directory(cx, state)
	local origin = if state.origin then cx.session:pane(state.origin) else nil
	if origin and origin.tab == state.tab and origin.cwd and origin.cwd ~= "" then return origin.cwd end
	for _, pane in cx.session:panes() do
		if pane.tab == state.tab and (pane.kind == "terminal" or pane.kind == "agent") and pane.cwd and pane.cwd ~= "" then
			state.origin = pane.pane
			return pane.cwd
		end
	end
	return home
end

-- 只更新发起动作的面板，避免其他标签的页码和搜索被覆盖。
local function redraw(cx, pane)
	local state = panes[pane]
	if not state then return end
	for _, canvas in cx.canvas:list() do
		if canvas.pane == pane and owned(canvas) then
			local main, dock = view.render(state)
			cx.canvas:set(pane, { view = main, dock = dock })
			return
		end
	end
	-- 启动恢复和关闭期间面板可能先消失，不能向已失效的 ID 写入。
	panes[pane] = nil
end

-- 后台调用 OMP 的真实发现入口，保留自定义目录、链接和 managed skills 规则。
local function refresh(cx, pane)
	local state = panes[pane]
	if not state or state.loading then return end
	local cwd = working_directory(cx, state)
	if cwd ~= state.cwd then
		state.cwd = cwd
		state.rows, state.filtered = {}, {}
		state.page = 1
	end
	state.loading = true
	state.error = nil
	local started, err = pcall(function()
		tern.process.run({ omp_executable, "skill", "list", "--json" }, { cwd = cwd, timeout_ms = 30000 }, function(result, next_cx)
			-- 面板关闭或插件重载后，不把迟到的结果写入新面板。
			if not next_cx or panes[pane] ~= state then return end
			state.loading = false
			if result.status ~= 0 then
				state.error = if result.timed_out then "OMP 读取超时，请刷新重试" elseif result.stderr ~= "" then result.stderr else "请确认 OMP 支持 skill list --json"
			else
				local ok, rows, warnings = pcall(catalog.decode, result.stdout)
				if ok then
					state.rows = rows
					state.filtered = catalog.filter(rows, state.query)
					state.warnings = warnings
				else
					state.error = tostring(rows)
				end
			end
			if state.error then
				state.rows, state.filtered = {}, {}
				state.warnings = 0
			end
			redraw(next_cx, pane)
		end)
	end)
	if not started then
		state.loading = false
		state.error = "无法启动 OMP：" .. tostring(err)
		state.rows, state.filtered = {}, {}
		state.warnings = 0
	end
	redraw(cx, pane)
end

-- 当前标签只挂载一个侧栏；默认隐藏，打开时不抢走终端焦点。
local function ensure_sidebar(cx)
	if tern.kv.get("visible") ~= true or opening then return end
	local focused = cx.session:focused()
	local tab = if focused then cx.session:tab_of(focused) else nil
	if not tab then return end
	for _, canvas in cx.canvas:list() do
		if owned(canvas) and cx.session:tab_of(canvas.pane) == tab then
			if not panes[canvas.pane] then
				panes[canvas.pane] = new_state(tab, focused)
				refresh(cx, canvas.pane)
			end
			return
		end
	end
	opening = true
	local state = new_state(tab, focused)
	state.loading = true
	local main, dock = view.render(state)
	local pane, err = cx.canvas:open({
		title = TITLE,
		about = "按字母浏览、搜索并复制已安装的 OMP Skills 名称。",
		view = main, dock = dock, how = "beside", target = focused,
		dir = "left", ratio = 0.25, focus = false,
	})
	opening = false
	if pane then
		state.loading = false
		panes[pane] = state
		refresh(cx, pane)
	else
		cx:toast("error", "无法打开 OMP Skills 侧边栏", tostring(err))
	end
end

-- 关闭开关会隐藏所有标签的 Skills 面板，其他插件不受影响。
local function hide_sidebars(cx, closed_pane)
	tern.kv.set("visible", false)
	for _, canvas in cx.canvas:list() do
		if owned(canvas) then
			panes[canvas.pane] = nil
			if canvas.pane ~= closed_pane then cx.layout:close(canvas.pane) end
		end
	end
end

-- 根据真实窗格高度调整每页数量，尺寸变化后保留原页首附近的位置。
local function update_sizes(cx)
	if sizing or not next(panes) then return end
	sizing = true
	local started = pcall(function()
		tern.process.run({ tern_executable, "ls", "--json" }, { timeout_ms = 5000 }, function(result, next_cx)
			sizing = false
			if not next_cx or result.status ~= 0 then return end
			local ok, data = pcall(tern.json.decode, result.stdout)
			if not ok or type(data) ~= "table" or type(data.sessions) ~= "table" then return end
			for _, session in data.sessions do
				for _, tab in session.tabs or {} do
					for _, block in tab.blocks or {} do
						local state = panes[block.id]
						if state and type(block.rows) == "number" and block.rows > 0 then
							local size = math.clamp(math.floor((block.rows - 4) / 3), 1, 300)
							if size ~= state.size then
								state.page = math.floor((state.page - 1) * state.size / size) + 1
								state.size = size
								redraw(next_cx, block.id)
							end
						end
					end
				end
			end
		end)
	end)
	if not started then sizing = false end
end

-- 搜索和清除都回到第一页，不改变技能的字母排序。
local function set_query(cx, pane, query)
	local state = panes[pane]
	if not state then return end
	state.query, state.page = query, 1
	state.filtered = catalog.filter(state.rows, query)
	redraw(cx, pane)
end

tern.on("canvas_action", function(ev, cx)
	if ev.owner ~= tern.plugin.id then return nil end
	local state = panes[ev.pane]
	if not state then return nil end
	local path = string.match(ev.act, "^copy:(.+)$")
	if path then
		for _, row in state.filtered do
			if row.path == path then
				cx:copy(row.name)
				cx:toast("info", "已复制 Skill 名称", row.name)
				break
			end
		end
	elseif ev.act == "search" then
		cx:prompt({ value = state.query, placeholder = "搜索名称、简介、来源或路径", action = "search" }):next(function(value, err, next_cx)
			if not next_cx or panes[ev.pane] ~= state then return end
			if err then next_cx:toast("error", "搜索失败", err)
			elseif value ~= nil then set_query(next_cx, ev.pane, value) end
		end)
	elseif ev.act == "clear" then
		set_query(cx, ev.pane, "")
	elseif ev.act == "refresh" then
		refresh(cx, ev.pane)
	elseif ev.act == "prev" or ev.act == "next" then
		local pages = math.max(1, math.ceil(#state.filtered / state.size))
		state.page = math.clamp(state.page + (if ev.act == "next" then 1 else -1), 1, pages)
		redraw(cx, ev.pane)
	else
		return nil
	end
	return true
end)

tern.command({
	id = "toggle", title = "OMP Skills: toggle sidebar", icon = "search",
	run = function(cx)
		if tern.kv.get("visible") == true then hide_sidebars(cx)
		else tern.kv.set("visible", true) ensure_sidebar(cx) end
	end,
})
tern.chrome.widget("toggle", {
	name = "OMP Skills", description = "显示或隐藏已安装的 OMP Skills", icon = "search",
	render = function(_pane)
		return { text = "", title = "显示/隐藏 OMP Skills", command = "plugin.omp-skills.toggle" }
	end,
})

-- 保留现有工具栏项目，仅添加本插件的开关。
local function initialize(cx)
	local widgets = cx.settings:get("widgets") or {}
	local found = false
	for _, widget in widgets do
		if widget.id == "omp-skills/toggle" then found = true break end
	end
	if not found then
		table.insert(widgets, { id = "omp-skills/toggle" })
		cx.settings:set("widgets", widgets)
	end
	for _, canvas in cx.canvas:list() do
		if owned(canvas) and not panes[canvas.pane] then
			panes[canvas.pane] = new_state(cx.session:tab_of(canvas.pane), nil)
			refresh(cx, canvas.pane)
		end
	end
	ensure_sidebar(cx)
end

-- 定时挂载新标签的面板，并移除只剩本插件侧栏的标签。
local function tick(cx)
	tern.timer(1000, tick)
	if not cx then return end
	for pane, state in panes do
		local count = 0
		for _, item in cx.session:panes() do
			if item.tab == state.tab then count += 1 end
		end
		if count == 1 then panes[pane] = nil cx.layout:close(pane) end
	end
	ensure_sidebar(cx)
	if tern.now() >= next_size_check then
		next_size_check = tern.now() + 2000
		update_sizes(cx)
	end
end

-- 关闭整个标签不改变其他标签的开关状态。
tern.on("tab_closed", function(ev)
	for pane, state in panes do
		if state.tab == ev.tab then panes[pane] = nil end
	end
end)
tern.on("pane_closed", function(ev, cx)
	local was_sidebar = panes[ev.pane] ~= nil
	panes[ev.pane] = nil
	if was_sidebar and tern.kv.get("visible") == true then hide_sidebars(cx, ev.pane) end
end)

-- 可见面板每三十秒刷新，隐藏时不启动 OMP 子进程。
local function refresh_tick(cx)
	tern.timer(30000, refresh_tick)
	if cx then
		for pane in panes do refresh(cx, pane) end
	end
end

tern.on("window_start", initialize)
tern.timer(100, function(cx) if cx then initialize(cx) end end)
tern.timer(1000, tick)
tern.timer(30000, refresh_tick)
