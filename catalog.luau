-- 技能目录：复用 OMP 的发现规则，仅负责索引校验、排序和搜索。
local catalog = {}

-- 校验 OMP CLI 的输出，并缓存用于不区分大小写搜索的文本。
function catalog.decode(text)
	local data = tern.json.decode(text)
	assert(type(data) == "table" and type(data.skills) == "table", "OMP 未返回有效的 skills 列表")
	local rows = {}
	for _, skill in data.skills do
		assert(type(skill.name) == "string" and skill.name ~= "", "Skill 名称无效")
		assert(type(skill.filePath) == "string", "Skill 路径无效")
		local description = if type(skill.description) == "string" then skill.description else ""
		local source = if type(skill.source) == "string" then skill.source else ""
		table.insert(rows, {
			name = skill.name,
			description = string.gsub(description, "[%c]+", " "),
			path = skill.filePath,
			source = source,
			sort_key = string.lower(skill.name),
			search = string.lower(skill.name .. " " .. description .. " " .. source .. " " .. skill.filePath),
		})
	end
	table.sort(rows, function(a, b)
		if a.sort_key ~= b.sort_key then return a.sort_key < b.sort_key end
		if a.name ~= b.name then return a.name < b.name end
		return a.path < b.path
	end)
	local warnings = if type(data.warnings) == "table" then #data.warnings else 0
	return rows, warnings
end

-- 按字面子串搜索，保留原有字母排序，不把用户输入当作 Lua 模式。
function catalog.filter(rows, query)
	local needle = string.lower(query)
	if needle == "" then return rows end
	local filtered = {}
	for _, row in rows do
		if string.find(row.search, needle, 1, true) then table.insert(filtered, row) end
	end
	return filtered
end

return catalog
