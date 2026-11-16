-- 侧边栏视图：名称与简介两行展示，工具栏和分页栏不随列表滚动。
local ui = tern.ui
local view = {}

-- 构建当前窗格的列表及底部分页；空列表也保持有效页码。
function view.render(state)
	local pages = math.max(1, math.ceil(#state.filtered / state.size))
	state.page = math.clamp(state.page, 1, pages)
	local cards = {}
	if state.error then
		table.insert(cards, ui.el("div", { class = "omp-skills-message", text = "读取失败：" .. state.error }))
	elseif state.loading and #state.rows == 0 then
		table.insert(cards, ui.text("正在读取 Skills…"))
	elseif #state.filtered == 0 then
		table.insert(cards, ui.text(if state.query == "" then "没有已安装的 Skills" else "没有匹配的 Skills"))
	else
		local first = (state.page - 1) * state.size + 1
		local last = math.min(state.page * state.size, #state.filtered)
		for index = first, last do
			local row = state.filtered[index]
			table.insert(cards, ui.el("button", {
				key = "skill_" .. row.path,
				class = "omp-skills-card",
				title = "点击复制：" .. row.name .. "\n" .. row.description .. "\n" .. row.path,
				actions = { click = "copy:" .. row.path },
			}, {
				ui.el("div", { class = "omp-skills-name", text = row.name }),
				ui.el("div", { class = "omp-skills-description", text = if row.description ~= "" then row.description else row.source }),
			}))
		end
	end
	local main = ui.node("col", { gap = "none" }, {
		ui.el("div", { class = "omp-skills-toolbar" }, {
			ui.el("div", {
				class = "omp-skills-query",
				text = if state.query == "" then "A–Z · 点击复制名称" else "搜索：" .. state.query,
				title = if state.query == "" then state.cwd else state.query,
			}),
			ui.button("", { icon = "search", title = "搜索 Skills", size = "sm", actions = { click = "search" } }),
			ui.button("", { icon = "x", title = "清除搜索", size = "sm", disabled = state.query == "", actions = { click = "clear" } }),
			ui.button("", { icon = "repeat", title = "刷新 Skills", size = "sm", disabled = state.loading, actions = { click = "refresh" } }),
		}),
		ui.el("div", { class = "omp-skills-list" }, cards),
	})
	local count = tostring(#state.filtered) .. " 个 Skills"
	if state.warnings > 0 then count ..= " · " .. state.warnings .. " 个警告" end
	local dock = ui.el("div", { class = "omp-skills-footer" }, {
		ui.node("row", { gap = "xs" }, {
			ui.button("", { icon = "arrow-left", title = "上一页 Skills", size = "sm", disabled = state.page == 1, actions = { click = "prev" } }),
			ui.el("div", { class = "omp-skills-page", text = state.page .. " / " .. pages }),
			ui.button("", { icon = "arrow-right", title = "下一页 Skills", size = "sm", disabled = state.page == pages, actions = { click = "next" } }),
		}),
		ui.el("div", { class = "omp-skills-count", text = count, title = "发现警告可在当前目录运行 omp skill list --json 查看" }),
	})
	return main, dock
end

return view
