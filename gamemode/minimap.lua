local CLIENT = CLIENT
local SERVER = SERVER
local concommand = concommand
local file = file
local game = game
local hook = hook
local math = math
local player = player
local string = string
local table = table
local team = team
local umsg = umsg
local usermessage = usermessage
local util = util
local vgui = vgui
local Entity = Entity
local ErrorNoHalt = ErrorNoHalt
local LocalPlayer = LocalPlayer
local Material = Material
local pairs = pairs
local RunConsoleCommand = RunConsoleCommand
local tonumber = tonumber
local tostring = tostring

module("minimap")

local map_material_name = ""
local map_material
local map_texture

local image_left = 0
local image_top = 0
local image_right = 1
local image_bottom = 1

local map_left = -16384
local map_top = 16384
local map_right = 16384
local map_bottom = -16384

local tomini_ratio_x = 1
local tomini_ratio_y = 1

local sector_width = 256
local sector_height = 256

local Ents = {}

function LoadEmpiresScript()
	local minimap_file = file.Read("resource/maps/"..game.GetMap()..".txt", true)
	if (!minimap_file) then
		ErrorNoHalt("Empires minimap file not found!\n")
	end
	local t = util.KeyValuesToTable(minimap_file or "")
	local texture_w, texture_h = 1, 1
	
	if (CLIENT) then
		map_material_name = t.image or ""
		map_material = Material(map_material_name)
		map_texture = map_material:GetMaterialTexture("$basetexture")
		texture_w = map_texture:GetActualWidth() or 64
		texture_h = map_texture:GetActualHeight() or 64
	end
	
	image_left = tonumber(t.min_image_x or 0) / texture_w
	image_top = tonumber(t.min_image_y or 0) / texture_h
	image_right = (tonumber(t.max_image_x or 64)) / texture_w
	image_bottom = (tonumber(t.max_image_y or 64)) / texture_h

	map_left = tonumber(t.min_bounds_x or -16384)
	map_top = tonumber(t.min_bounds_y or 16384)
	map_right = tonumber(t.max_bounds_x or 16384)
	map_bottom = tonumber(t.max_bounds_y or -16384)
	
	tomini_ratio_x = (image_right - image_left) / (map_right - map_left)
	tomini_ratio_y = (image_bottom - image_top) / (map_bottom - map_top)
	
	-- This may seem wrong, but this is how Empires actually loads its minimap scripts.
	sector_width = tonumber(t.sector_height or 256) / texture_w
	sector_height = tonumber(t.sector_width or 256) / texture_h
	
	VLines = {}
	HLines = {}
	local linepos = image_left
	while linepos < image_right do
		table.insert(VLines, linepos)
		linepos = linepos + sector_width
	end
	table.insert(VLines, image_right)
	linepos = image_top
	while linepos < image_bottom do
		table.insert(HLines, linepos)
		linepos = linepos + sector_height
	end
	table.insert(HLines, image_bottom)
end

function WorldToMinimap(worldx, worldy)
	local minix = (worldx - map_left) * tomini_ratio_x + image_left
	local miniy = (worldy - map_top) * tomini_ratio_y + image_top
	return minix, miniy
end

function GetImageBounds()
	return image_left, image_right, image_top, image_bottom
end

function GetSector(pos)
	-- This isn't quite right
	local minix, miniy = WorldToMinimap(pos.x, pos.y)
	if minix < image_left || minix > image_right || miniy < image_top || miniy > image_bottom then return "Unknown" end
	local SectorL = math.floor((minix - image_left) / sector_width)
	local SectorN = math.floor((miniy - image_top) / sector_height)
	return string.char(65 + SectorL, 49 + SectorN)
end

function GetSectorSize()
	return sector_width, sector_height
end

function GetEnts()
	return Ents
end

if (SERVER) then
	local function mm_request_entity(ply, cmd, args)
		local entid = tonumber(args[1])
		local ent = Entity(entid)
		if !ent:IsValid() then return end
		local enttable = Ents[entid]
		if ent:Team() == ply:Team() || (enttable.cansee & ply:TeamMask() > 0) then
			umsg.Start("mm_type_update", ply)
			umsg.Short(entid)
			umsg.String(ent:GetClass())
			umsg.Short(ent:Team())
			umsg.End()
		end
	end
	concommand.Add("mm_request_entity", mm_request_entity)

	local t_plys = {}
	local t_ents = {}
	
	local function ServerThink()
		if (#t_plys == 0) then
			t_plys = player.GetAll()
		end
		local ply = t_plys[1]
		if !ply then return end
		if (#t_ents == 0) then
			local ent
			for k, v in pairs(Ents) do
				ent = Entity(k)
				if !ent:IsValid() then continue end
				if (ply:Team() == ent:Team()) then
					table.insert(t_ents, ent)
				end
			end
		end
		local count = math.min(#t_ents, 28)
		umsg.Start("mm_pos_update", ply)
		umsg.Char(count)
		for i=1, count do
			local ent = t_ents[i]
			umsg.Short(ent:EntIndex())
			local pos = ent:GetPos()
			umsg.Short(math.floor(pos.x))
			umsg.Short(math.floor(pos.y))
			umsg.Short(ent:IsPlayer() and (ent:EyeAngles().y - 90) or 0)
		end
		umsg.End()
		for i=1, count do table.remove(t_ents, 1) end
		if (#t_ents == 0) then table.remove(t_plys, 1) end
	end
	hook.Add("Think", "mm_ServerThink", ServerThink)

	function Register(ent)
		Ents[ent:EntIndex()] = {}
	end

	function UnRegister(ent)
		Ents[ent:EntIndex()] = nil
	end
end

if (CLIENT) then
	local function mm_pos_update(um)
		local entid, x, y, ang
		local count = um:ReadChar()
		for i=1, count do
			entid = um:ReadShort()
			if (!Ents[entid]) then
				Ents[entid] = {}
				RunConsoleCommand("mm_request_entity", tostring(entid))
			end
			local enttable = Ents[entid]
			enttable.x = um:ReadShort()
			enttable.y = um:ReadShort()
			enttable.ang = um:ReadShort()
			
			
		end
	end
	usermessage.Hook("mm_pos_update", mm_pos_update)
	
	local function mm_type_update(um)
		local entid = um:ReadShort()
		if (!Ents[entid]) then Ents[entid] = {} end
		local enttable = Ents[entid]
		enttable.class = um:ReadString()
		enttable.team = um:ReadShort()
	end
	usermessage.Hook("mm_type_update", mm_type_update)
	
	local function init()
		Panel = vgui.Create("Minimap")
	end
	hook.Add("PostGamemodeLoaded", "mm_init", init)
	
	local function ClientThink()
		for k, v in pairs(Ents) do
			local ent = Entity(k)
			if !ent:IsValid() then continue end
			v.class = ent:GetClass()
			v.team = ent:Team()
			local pos = ent:GetPos()
			v.x = pos.x
			v.y = pos.y
			v.ang = ent:IsPlayer() and (ent:EyeAngles().y - 90) or 0
		end
	end
	hook.Add("Think", "mm_ClientThink", ClientThink)

	local Materials = {
		["player"] = Material("vgui/player"),
		["rts_barracks"] = Material("minimap/mmico_barracks")
	}
	
	function GetMapMaterial()
		return map_material
	end
end
