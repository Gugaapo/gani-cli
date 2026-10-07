-- Saves gani-cli watch progress from inside mpv.
-- Streaming URLs change every session, so mpv's own watch-later files cannot resume them.
-- The shell writes the show title; this script updates position, duration, and status.

local mp = require("mp")
local options = require("mp.options")

local o = {
	hist = "",
	id = "",
	ep = "",
	mode = "sub",
	next = "none",
}
options.read_options(o, "gani_progress")

local finish_ratio = 0.90
local finish_tail = 15
local min_duration = 30

local function field(line, index)
	local current = 1
	for value in (line .. "\t"):gmatch("([^\t]*)\t") do
		if current == index then
			return value
		end
		current = current + 1
	end
	return ""
end

local function split_fields(line)
	local fields = {}
	for value in (line .. "\t"):gmatch("([^\t]*)\t") do
		fields[#fields + 1] = value
	end
	if #fields > 0 and fields[#fields] == "" then
		fields[#fields] = nil
	end
	return fields
end

local function flag_and_title(fields)
	if #fields >= 9 then
		local parts = {}
		for i = 9, #fields do
			parts[#parts + 1] = fields[i]
		end
		return fields[8] or "", table.concat(parts, "\t")
	end
	local parts = {}
	for i = 8, #fields do
		parts[#parts + 1] = fields[i]
	end
	return "", table.concat(parts, "\t")
end

local function write_history(status, pos, dur)
	if o.hist == "" or o.id == "" then
		return
	end
	local title = ""
	local flag = ""
	local kept = {}
	local input = io.open(o.hist, "r")
	if input then
		for line in input:lines() do
			if line ~= "" then
				if field(line, 7) == o.id then
					-- A newer playback of another episode owns this row.
					if field(line, 5) ~= o.ep then
						input:close()
						return
					end
					flag, title = flag_and_title(split_fields(line))
				else
					kept[#kept + 1] = line
				end
			end
		end
		input:close()
	end
	local row = string.format(
		"%d\t%s\t%.3f\t%.3f\t%s\t%s\t%s\t%s\t%s",
		os.time(),
		status,
		pos or 0,
		dur or 0,
		o.ep,
		o.mode,
		o.id,
		flag,
		title
	)
	local tmp = o.hist .. ".lua"
	local output = io.open(tmp, "w")
	if not output then
		return
	end
	output:write(row, "\n")
	for i = 1, #kept do
		output:write(kept[i], "\n")
	end
	output:close()
	os.rename(tmp, o.hist)
end

local last_pos = nil
local last_dur = nil

mp.observe_property("time-pos", "number", function(_, value)
	if value and value >= 0 then
		last_pos = value
	end
end)
mp.observe_property("duration", "number", function(_, value)
	if value and value > 0 then
		last_dur = value
	end
end)

local function save()
	local pos = mp.get_property_number("time-pos") or last_pos
	local dur = mp.get_property_number("duration") or last_dur
	if not pos or pos < 0 then
		return
	end
	local status = "watching"
	if dur and dur >= min_duration then
		if (pos / dur) >= finish_ratio or (dur - pos) <= finish_tail then
			if o.next == "" or o.next == "none" then
				status = "completed"
			else
				status = "finished"
			end
		end
	end
	write_history(status, pos, dur or 0)
end

mp.add_periodic_timer(5, save)
mp.register_event("end-file", save)
mp.register_event("shutdown", save)
