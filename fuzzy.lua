-- fuzzy.lua
-- fuzzy chooser
-- from https://gist.github.com/RainmanNoodles/70aaff04b20763041d7acb771b0ff2b2

local log = hs.logger.new("fuzzy", "debug")

obj = {}
obj.__index = obj

local function fuzzyQuery(s, m)
	s_index = 1
	m_index = 1
	match_start = nil
	while true do
		if s_index > s:len() or m_index > m:len() then
			return -1
		end
		s_char = s:sub(s_index, s_index)
		m_char = m:sub(m_index, m_index)
		if s_char == m_char then
			if match_start == nil then
				match_start = s_index
			end
			s_index = s_index + 1
			m_index = m_index + 1
			if m_index > m:len() then
				match_end = s_index
				s_match_length = match_end-match_start
				score = m:len()/s_match_length
				return score
			end
		else
			s_index = s_index + 1
		end
	end
end

local function fuzzyFilterChoices(self, query)
	if query:len() == 0 then
		self.chooser:choices(self.choices)
		return
	end
	pickedChoices = {}
	for i,j in pairs(self.choices) do
		fullText = (j["text"] .. " " .. j["subText"]):lower()
		score = fuzzyQuery(fullText, query:lower())
		if score > 0 then
			j["fzf_score"] = score
			table.insert(pickedChoices, j)
		end
	end
	local sort_func = function( a,b ) return a["fzf_score"] > b["fzf_score"] end
	table.sort( pickedChoices, sort_func )
	self.chooser:choices(pickedChoices)
end

function obj.new(choices, fn)
    local self = {
        choices = choices,
        chooser = hs.chooser.new(fn),
    }
    self.chooser:choices(self.choices)
    self.chooser:searchSubText(true)
	self.chooser:queryChangedCallback(function(qry)
        fuzzyFilterChoices(self, qry)
    end)
    return self
end

return obj
