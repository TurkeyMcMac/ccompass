-- compass configuration interface - adjustable from other mods or minetest.conf settings
ccompass = {}

-- default target to static_spawnpoint or 0/0/0
ccompass.default_target = minetest.setting_get_pos("static_spawnpoint") or {x=0, y=0, z=0}

-- Re-calibration allowed
ccompass.recalibrate = minetest.settings:get_bool("ccompass_recalibrate")
if ccompass.recalibrate == nil then
	ccompass.recalibrate = true
end

-- Target restriction
ccompass.restrict_target = minetest.settings:get_bool("ccompass_restrict_target")
ccompass.restrict_target_nodes = {}
local nodes_setting = minetest.settings:get("ccompass_restrict_target_nodes")
if nodes_setting then
	nodes_setting:gsub("[^,]+", function(z)
		ccompass.restrict_target_nodes[z] = true
	end)
end

ccompass.allow_climbable_target = not minetest.settings:get_bool("ccompass_deny_climbable_target")
ccompass.allow_damaging_target = minetest.settings:get_bool("ccompass_allow_damage_target")

-- Teleport targets
ccompass.teleport_nodes = {}
local teleport_nodes_setting = minetest.settings:get("ccompass_teleport_nodes")
if teleport_nodes_setting then
	teleport_nodes_setting:gsub("[^,]+", function(z)
		ccompass.teleport_nodes[z] = true
	end)
else
	ccompass.teleport_nodes["default:mese"] = true
end
-- Permited nodes above target
ccompass.nodes_over_target_allow = {}
nodes_setting = minetest.settings:get("ccompass_nodes_over_target_allow")
if nodes_setting then
	nodes_setting:gsub("[^,]+", function(z)
		ccompass.nodes_over_target_allow[z] = true
	end)
end
-- Not permited nodes above target
ccompass.nodes_over_target_deny = {}
nodes_setting = minetest.settings:get("ccompass_nodes_over_target_deny")
if nodes_setting then
	nodes_setting:gsub("[^,]+", function(z)
		ccompass.nodes_over_target_deny[z] = true
	end)
end
-- Permited drawtype of nodes above target
ccompass.nodes_over_target_allow_drawtypes = {}
nodes_setting = minetest.settings:get("ccompass_nodes_over_target_allow_drawtypes")
if nodes_setting then
	nodes_setting:gsub("[^,]+", function(z)
		ccompass.nodes_over_target_allow_drawtypes[z] = true
	end)
else
	ccompass.nodes_over_target_allow_drawtypes = {
		airlike = true,
		flowingliquid = true,
		liquid = true,
		plantlike = true,
		plantlike_rooted = true,
	}
end

-- default to legacy behaviour
ccompass.stack_max = tonumber(minetest.settings:get("ccompass_stack_max") or 1) or 1
ccompass.allow_using_stacks = minetest.settings:get_bool("ccompass_allow_using_stacks")

if minetest.settings:get_bool("ccompass_aliasses") then
	minetest.register_alias("compass:0", "ccompass:0")
	minetest.register_alias("compass:1", "ccompass:1")
	minetest.register_alias("compass:2", "ccompass:2")
	minetest.register_alias("compass:3", "ccompass:3")
	minetest.register_alias("compass:4", "ccompass:4")
	minetest.register_alias("compass:5", "ccompass:5")
	minetest.register_alias("compass:6", "ccompass:6")
	minetest.register_alias("compass:7", "ccompass:7")
	minetest.register_alias("compass:8", "ccompass:8")
	minetest.register_alias("compass:9", "ccompass:9")
	minetest.register_alias("compass:10", "ccompass:10")
	minetest.register_alias("compass:11", "ccompass:11")
end

-- set a position to the compass stack
function ccompass.set_target(stack, param)
	param = param or {}
	-- param.target_pos_string
	-- param.target_name
	-- param.playername

	local meta=stack:get_meta()
	meta:set_string("target_pos", param.target_pos_string)
	if param.target_name == "" then
		meta:set_string("description", "Compass to "..param.target_pos_string)
	else
		meta:set_string("description", "Compass to "..param.target_name)
	end

	if param.playername then
		local player = minetest.get_player_by_name(param.playername)
		minetest.chat_send_player(param.playername, "Calibration done to "..param.target_name.." "..param.target_pos_string)
		minetest.sound_play({ name = "ccompass_calibrate", gain = 1 }, { pos = player:getpos(), max_hear_distance = 3 })
	end
end


-- Get compass target
local function get_destination(player, stack)
	local posstring = stack:get_meta():get_string("target_pos")
	if posstring ~= "" then
		return minetest.string_to_pos(posstring)
	else
		return ccompass.default_target
	end
end

function ccompass.is_safe_target(target, nodename)
	local node_def = minetest.registered_nodes[nodename]
	-- unknown node: not dangerous but probably best treated as one
	if not node_def then return false end
	-- white-list
	if ccompass.nodes_over_target_allow[nodename] then return true end
	-- black-list
	if ccompass.nodes_over_target_deny[nodename] then return false end
	-- damaging node
	if not ccompass.allow_damaging_target then
		if node_def.damage_per_second and 0 < node_def.damage_per_second then
			return false
		end
	end
	-- climbable nodes are ok depending on settings
	if ccompass.allow_climbable_target and node_def.climbable then return true end
	-- deeper checks
	local is_good_draw_type = ccompass.nodes_over_target_allow_drawtypes
	if is_good_draw_type[node_def.drawtype] then return true end

	-- anything else is assumed dangerous
	return false
end

function ccompass.is_safe_target_under(target, nodename)
	local node_def = minetest.registered_nodes[nodename]
	-- unknown node: not dangerous but probably best treated as one
	if not node_def then return false end
	-- damaging node
	if not ccompass.allow_damaging_target then
		if node_def.damage_per_second and 0 < node_def.damage_per_second then
			return false
		end
	end
	-- climbable nodes are ok depending on settings
	if ccompass.allow_climbable_target and node_def.climbable then return true end
	-- solid / walkable
	if node_def.walkable then return true end

	-- anything else is assumed unsafe
	return false
end

local function check_target(cur_target, nodenames_cache)
	--check target
	local nodename = nodenames_cache[cur_target.y] or minetest.get_node(cur_target).name
	if nodename == "ignore" then return false end
	nodenames_cache[cur_target.y] = nodename
	if ccompass.is_safe_target(cur_target, nodename) then

		-- Check under
		cur_target.y = cur_target.y - 1
		nodename = nodenames_cache[cur_target.y] or minetest.get_node(cur_target).name
		if nodename == "ignore" then return false end
		nodenames_cache[cur_target.y] = nodename
		if ccompass.is_safe_target_under(cur_target, nodename) then

			-- Check head
			cur_target.y = cur_target.y + 2
			nodename = nodenames_cache[cur_target.y] or minetest.get_node(cur_target).name
			if nodename == "ignore" then return false end
			nodenames_cache[cur_target.y] = nodename
			if ccompass.is_safe_target(cur_target, nodename) then
				return true
			end
		end
	end
end

local function teleport_above(playername, target, counter)
	local player = minetest.get_player_by_name(playername)
	if not player then
		return
	end

	local found_place = false
	local cur_target = { x = target.x, z = target.z } -- y is handled in loop

	local nodenames_cache = {}

	for i = (counter or 0), 80 do
		-- Search above
		cur_target.y = target.y + i
		found_place  = check_target(cur_target, nodenames_cache)
		if found_place == false then
			minetest.emerge_area(cur_target, cur_target)
			minetest.after(0.1, teleport_above, playername, target, i)
			return
		elseif found_place == true then
			cur_target.y = target.y + i -- reset after check_target
			break
		end

		if i > 0 then
			-- Search bellow
			cur_target.y = target.y - i
			found_place  = check_target(cur_target, nodenames_cache)
			if found_place == false then
				minetest.emerge_area(cur_target, cur_target)
				minetest.after(0.1, teleport_above, playername, target, i)
				return
			elseif found_place == true then
				cur_target.y = target.y - i  -- reset after check_target
				break
			end
		end
	end

	if found_place then
		player:set_pos(cur_target)
	else
		minetest.chat_send_player(playername, "Could not find suitable surrounding at target.")
	end
end

-- get right image number for players compass
local function get_compass_stack(player, stack)
	local target = get_destination(player, stack)
	local pos = player:get_pos()
	local dir = player:get_look_horizontal()
	local angle_north = math.deg(math.atan2(target.x - pos.x, target.z - pos.z))
	if angle_north < 0 then
		angle_north = angle_north + 360
	end
	local angle_dir = math.deg(dir)
	local angle_relative = (angle_north + angle_dir) % 360
	local compass_image = math.floor((angle_relative/22.5) + 0.5)%16

	-- create new stack with metadata copied
	local metadata = stack:get_meta():to_table()

	local newstack = ItemStack("ccompass:"..compass_image.." "..stack:get_count())
	if metadata then
		newstack:get_meta():from_table(metadata)
	end
	if ccompass.usage_hook then
		newstack = ccompass.usage_hook(newstack, player) or newstack
	end
	return newstack
end

-- Calibrate compass on pointed_thing
local function on_use_function(itemstack, player, pointed_thing)
	-- if using with a bunch together, need to check server preference
	if 1 ~= itemstack:get_count() and not ccompass.allow_using_stacks then
		minetest.chat_send_player(player:get_player_name(), "Use a single compass.")
		return
	end
	-- possible only on nodes
	if pointed_thing.type ~= "node" then --support nodes only for destination
		minetest.chat_send_player(player:get_player_name(), "Calibration can be done on nodes only")
		return
	end

	local nodepos = minetest.get_pointed_thing_position(pointed_thing)
	local node = minetest.get_node(nodepos)

	-- Do teleport to target
	if ccompass.teleport_nodes[node.name] then
		teleport_above(player:get_player_name(), get_destination(player, itemstack))
		return
	end

	-- recalibration allowed?
	if not ccompass.recalibrate then
		local destination = itemstack:get_meta():get_string("target_pos")
		if destination ~= "" then
			minetest.chat_send_player(player:get_player_name(), "Compass already calibrated")
			return
		end
	end

	-- target nodes restricted?
	if ccompass.restrict_target then
		if not ccompass.restrict_target_nodes[node.name] then
			minetest.chat_send_player(player:get_player_name(), "Calibration on this node not possible")
			return
		end
	end

	-- check if waypoint name set in target node
	local nodepos_string = minetest.pos_to_string(nodepos)
	local nodemeta = minetest.get_meta(nodepos)
	local waypoint_name = nodemeta:get_string("waypoint_name")
	local waypoint_pos = nodemeta:get_string("waypoint_pos")
	local skip_namechange = nodemeta:get_string("waypoint_skip_namechange")
	local itemmeta=itemstack:get_meta()

	if waypoint_pos and waypoint_pos ~= "" then
		nodepos_string = waypoint_pos
	end

	if skip_namechange ~= "" then
		ccompass.set_target(itemstack, {
				target_pos_string = nodepos_string,
				target_name = waypoint_name,
				playername = player:get_player_name()
			})
	else
		-- show the formspec to player
		itemmeta:set_string("tmp_target_pos", nodepos_string) --just save temporary
		minetest.show_formspec(player:get_player_name(), "ccompass",
				"size[10,2.5]" ..
				"field[1,1;8,1;name;Destination name:;"..waypoint_name.."]"..
				"button_exit[0.7,2;3,1;cancel;Cancel]"..
				"button_exit[3.7,2;5,1;ok;Calibrate]" )
	end
	return itemstack
end

-- Process the calibration using entered data
minetest.register_on_player_receive_fields(function(player, formname, fields)
	if formname == "ccompass" and fields.name and (fields.ok or fields.key_enter) then
		local stack=player:get_wielded_item()
		local meta=stack:get_meta()
		ccompass.set_target(stack, {
				target_pos_string = meta:get_string("tmp_target_pos"),
				target_name = fields.name,
				playername = player:get_player_name()
			})
		meta:set_string("tmp_target_pos", "")
		player:set_wielded_item(stack)
	end
end)

-- update inventory
minetest.register_globalstep(function(dtime)
	for i,player in ipairs(minetest.get_connected_players()) do
		if player:get_inventory() then
			for i,stack in ipairs(player:get_inventory():get_list("main")) do
				if i > 8 then
					break
				end
				if string.sub(stack:get_name(), 0, 9) == "ccompass:" then
					player:get_inventory():set_stack("main", i, get_compass_stack(player, stack))
				end
			end
		end
	end
end)

-- register items
for i = 0, 15 do
	local image = "ccompass_16_"..i..".png"
	local groups = {}
	if i > 0 then
		groups.not_in_creative_inventory = 1
	end
	local itemname = "ccompass:"..i
	minetest.register_craftitem(itemname, {
		description = "Compass",
		inventory_image = image,
		wield_image = image,
		stack_max = ccompass.stack_max or 42,
		groups = groups,
		on_use = on_use_function,
	})
	-- reset recipe
	minetest.register_craft({
		type = "shapeless",
		output = "ccompass:0",
		recipe = { itemname }
	})
end

minetest.register_craft({
	output = 'ccompass:0',
	recipe = {
		{'', 'default:steel_ingot', ''},
		{'default:steel_ingot', 'default:mese_crystal_fragment', 'default:steel_ingot'},
		{'', 'default:steel_ingot', ''}
	}
})
-- add an alternative recipe
minetest.register_craft({
	output = 'ccompass:0',
	recipe = {
		{'default:steel_ingot', '', 'default:steel_ingot'},
		{'', 'default:mese_crystal_fragment', ''},
		{'default:steel_ingot', '', 'default:steel_ingot'}
	}
})

