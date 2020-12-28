-- CHIP-8 State
local opcode = 0
local ram = {}
local V = {}
local I = 0x000
local PC = 0x000
local SP = 0
local screen = {} -- 64x32 -> 960x480 (x15)
local super_screen = {} -- 128x64 -> 896x448 (x7)
local delay_timer = 0
local sound_timer = 0
local stack = {}
local hp48_flags = {}
local key = {}
local updateScreen = false
local beep = nil
local cur_rom = ""
local schip_mode = false
local update_timers = false

-- Custom colors
local bg_r = 0
local bg_g = 0
local bg_b = 0
local nbg_r = 255
local nbg_g = 255
local nbg_b = 255

-- Colors
local white = Color.new(255, 255, 255)
local black = Color.new(0, 0, 0)
local cyan = Color.new(0, 162, 232)
local yellow = Color.new(255, 255, 0)
local red = Color.new(255, 0, 0)
local green = Color.new(0, 255, 0)
local blue = Color.new(0, 0, 255)
local bg_color = Color.new(bg_r, bg_g, bg_b)
local nbg_color = Color.new(nbg_r, nbg_g, nbg_b)
local old_bg_color = bg_color
local old_nbg_color = nbg_color

-- Key Mapping
local keys = {
	{["name"] = "Up", ["val"] = SCE_CTRL_UP, ["int"] = 0x1},
	{["name"] = "Down", ["val"] = SCE_CTRL_DOWN, ["int"] = 0x4},
	{["name"] = "Left", ["val"] = SCE_CTRL_LEFT, ["int"] = 0x2},
	{["name"] = "Right", ["val"] = SCE_CTRL_RIGHT, ["int"] = 0x3},
	{["name"] = "Triangle", ["val"] = SCE_CTRL_TRIANGLE, ["int"] = 0xC},
	{["name"] = "Cross", ["val"] = SCE_CTRL_CROSS, ["int"] = 0xD},
	{["name"] = "Square", ["val"] = SCE_CTRL_SQUARE, ["int"] = 0xE},
	{["name"] = "Circle", ["val"] = SCE_CTRL_CIRCLE, ["int"] = 0xF},
	{["name"] = "L Trigger", ["val"] = SCE_CTRL_LTRIGGER, ["int"] = 0x5},
	{["name"] = "R Trigger", ["val"] = SCE_CTRL_RTRIGGER, ["int"] = 0x6},
	{["name"] = "Start", ["val"] = SCE_CTRL_START, ["int"] = 0x7},
	{["name"] = "Select", ["val"] = SCE_CTRL_SELECT, ["int"] = 0x8}
}
local keys_backup = {}

-- Localizing most used functions for performance
local drawRect = Graphics.fillRect

-- Emulator State
local state = 0
local old_state = 0
local emuFolder = "ux0:data/MicroCHIP"
local romFolder = emuFolder .. "/roms"
local savFolder = emuFolder .. "/saves"
local roms = {}
local ver = "1.0"
local cursor = 1
local currentRomCursor = -1
local oldpad = SCE_CTRL_CROSS
local notification = ""
local t = nil
local old_t = nil
local pause_menu_entries = {"Resume game", "Save savestate", "Load savestate", "Reset game", "Show/Hide Debugger", "Options", "Close rom"}
local debugger = false

-- CHIP-8 Fontset
local fontset = {
	0xF0, 0x90, 0x90, 0x90, 0xF0, -- 0
	0x20, 0x60, 0x20, 0x20, 0x70, -- 1
	0xF0, 0x10, 0xF0, 0x80, 0xF0, -- 2
	0xF0, 0x10, 0xF0, 0x10, 0xF0, -- 3
	0x90, 0x90, 0xF0, 0x10, 0x10, -- 4
	0xF0, 0x80, 0xF0, 0x10, 0xF0, -- 5
	0xF0, 0x80, 0xF0, 0x90, 0xF0, -- 6
	0xF0, 0x10, 0x20, 0x40, 0x40, -- 7
	0xF0, 0x90, 0xF0, 0x90, 0xF0, -- 8
	0xF0, 0x90, 0xF0, 0x10, 0xF0, -- 9
	0xF0, 0x90, 0xF0, 0x90, 0x90, -- A
	0xE0, 0x90, 0xE0, 0x90, 0xE0, -- B
	0xF0, 0x80, 0x80, 0x80, 0xF0, -- C
	0xE0, 0x90, 0x90, 0x90, 0xE0, -- D
	0xF0, 0x80, 0xF0, 0x80, 0xF0, -- E
	0xF0, 0x80, 0xF0, 0x80, 0x80  -- F
}

-- SCHIP-8 Fontset
local super_fontset = {
	0xFF, 0xFF, 0xC3, 0xC3, 0xC3, 0xC3, 0xC3, 0xC3, 0xFF, 0xFF, -- 0
	0x18, 0x78, 0x78, 0x18, 0x18, 0x18, 0x18, 0x18, 0xFF, 0xFF, -- 1
	0xFF, 0xFF, 0x03, 0x03, 0xFF, 0xFF, 0xC0, 0xC0, 0xFF, 0xFF, -- 2
	0xFF, 0xFF, 0x03, 0x03, 0xFF, 0xFF, 0x03, 0x03, 0xFF, 0xFF, -- 3
	0xC3, 0xC3, 0xC3, 0xC3, 0xFF, 0xFF, 0x03, 0x03, 0x03, 0x03, -- 4
	0xFF, 0xFF, 0xC0, 0xC0, 0xFF, 0xFF, 0x03, 0x03, 0xFF, 0xFF, -- 5
	0xFF, 0xFF, 0xC0, 0xC0, 0xFF, 0xFF, 0xC3, 0xC3, 0xFF, 0xFF, -- 6
	0xFF, 0xFF, 0x03, 0x03, 0x06, 0x0C, 0x18, 0x18, 0x18, 0x18, -- 7
	0xFF, 0xFF, 0xC3, 0xC3, 0xFF, 0xFF, 0xC3, 0xC3, 0xFF, 0xFF, -- 8
	0xFF, 0xFF, 0xC3, 0xC3, 0xFF, 0xFF, 0x03, 0x03, 0xFF, 0xFF, -- 9
	0x7E, 0xFF, 0xC3, 0xC3, 0xC3, 0xFF, 0xFF, 0xC3, 0xC3, 0xC3, -- A
	0xFC, 0xFC, 0xC3, 0xC3, 0xFC, 0xFC, 0xC3, 0xC3, 0xFC, 0xFC, -- B
	0x3C, 0xFF, 0xC3, 0xC0, 0xC0, 0xC0, 0xC0, 0xC3, 0xFF, 0x3C, -- C
	0xFC, 0xFE, 0xC3, 0xC3, 0xC3, 0xC3, 0xC3, 0xC3, 0xFE, 0xFC, -- D
	0xFF, 0xFF, 0xC0, 0xC0, 0xFF, 0xFF, 0xC0, 0xC0, 0xFF, 0xFF, -- E
	0xFF, 0xFF, 0xC0, 0xC0, 0xFF, 0xFF, 0xC0, 0xC0, 0xC0, 0xC0  -- F
}

-- Clear CHIP-8 screen
function clearScreen()
	for i=0, 0x800 do
		screen[i] = 0
	end
	updateScreen = true
end

-- Clear SCHIP-8 screen
function clearSuperScreen()
	for i=0, 0x2000 do
		super_screen[i] = 0
	end
	updateScreen = true
end

-- Push a notification state on screen
function pushNotification(text)
	notification = text
	state_timer = 500
end

-- Initialize CHIP-8 machine
function initEmu()
	
	-- Resetting emulator state
	PC = 0x200
	opcode = 0
	I = 0x000
	SP = 0
	schip_mode = false
	
	-- Clearing screen
	clearScreen()
	clearSuperScreen()
	
	-- Resetting stack, keystates, registers, HP48 flags and ram
	for i=0, 15 do
		stack[i] = 0
		V[i] = 0
		key[i] = 0
	end
	for i=0, 0xFFF do
		ram[i] = 0
	end
	for i=0, 7 do
		hp48_flags[i] = 0
	end
	
	-- Reset timers
	delay_timer = 0
	sound_timer = 0
	
	-- Loading CHIP-8 fontset
	for i=0, 0x4F do
		ram[i] = fontset[i+1]
	end
	
	-- Loading SCHIP-8 fontset
	for i=0, 0x9F do
		ram[i + 0x50] = super_fontset[i+1]
	end
	
	-- Selecting a seed for random purposes
	h,m,s = System.getTime() 
	dv,d,m,y = System.getDate()
	seed = s + 60*s + h*3600 + d*24*3600
	math.randomseed(seed)
	
end

-- Terminate system
function termEmu()
	Sound.close(beep)
	System.exit()
end

-- Clear device screen
function purgeScreen()
	for i=0,2 do
		Graphics.initBlend()
		Screen.clear()
		Graphics.termBlend()
		Screen.flip()
	end
end

-- Load a CHIP-8 rom
function loadRom(filename)
	initEmu()
	fd = System.openFile(filename, FREAD)
	rom_size = System.sizeFile(fd)
	for i=0, rom_size-1 do
		ram[i + 0x200] = string.byte(System.readFile(fd, 1))
	end
	System.closeFile(fd)
	purgeScreen()
	cur_rom = roms[currentRomCursor]
	pushNotification("Rom " .. cur_rom .. " loaded successfully!")
end

-- Draw CHIP-8 display on screen
function drawScreen()
	if schip_mode then
		for y=0, 63 do
			for x=0, 127 do
				x_val = (x * 7) + 32
				y_val = (y * 7) + 48
				if super_screen[bit32.lshift(y,7) + x] == 0 then
					drawRect(x_val, x_val + 7, y_val, y_val + 7, bg_color)
				else
					drawRect(x_val, x_val + 7, y_val, y_val + 7, nbg_color)
				end
			end
		end
	else
		for y=0, 31 do
			for x=0, 63 do
				x_val = x * 15
				y_val = (y * 15) + 32
				if screen[bit32.lshift(y,6) + x] == 0 then
					drawRect(x_val, x_val + 15, y_val, y_val + 15, bg_color)
				else
					drawRect(x_val, x_val + 15, y_val, y_val + 15, nbg_color)
				end
			end
		end
	end
	updateScreen = false
end

-- Handle CHIP-8 keyboard
function handleKeys()
	local i = 1
	local pad = Controls.read()
	while i <= #keys do
		key[keys[i].int] = Controls.check(pad, keys[i].val)
		i = i + 1
	end
	t = Controls.readTouch()
	if t ~= nil and not (old_t ~= nil) then
		if state == 1 then
			state = 2
			pushNotification("Game paused.")
			cursor = 1
		end
	end
	old_t = t
end

-- Show an error on screen
function showError(text)
	System.setMessage(text, false, BUTTON_OK)
	while true do
		Graphics.initBlend()
		Graphics.termBlend()
		Screen.flip()
		status = System.getMessageState()
		if status ~= RUNNING then
			break
		end
	end
	if state == 0 then
		System.exit()
	else
		state = 0
	end
end

-- Show an answer on screen
function showAnswer(text)
	System.setMessage(text, false, BUTTON_YES_NO)
	while true do
		Graphics.initBlend()
		Graphics.termBlend()
		Screen.flip()
		status = System.getMessageState()
		if status ~= RUNNING then
			if status == CANCELED then
				return false
			else
				return true
			end
		end
	end
end

-- Execute a CHIP-8 cycle
function executeOpcode()

	-- Fetching opcode
	opcode = bit32.bor(bit32.lshift(ram[PC],8), ram[PC + 1])
	local bit1 = bit32.rshift(bit32.band(opcode,0xF000),12)
	local bit2 = bit32.rshift(bit32.band(opcode,0x0F00),8)
	local bit3 = bit32.rshift(bit32.band(opcode,0x00F0),4)
	local bit4 = bit32.band(opcode,0x000F)
	
	-- Executing opcode
	PC = PC + 2
	if bit1 == 0x0 then
		if bit3 == 0xC then -- SCD nibble *SCHIP*
			for y=0, 63 do
				for x=0, 127 do
					local yline = bit32.lshift(y , 7)
					super_screen[x + bit32.lshift(y + bit4,7)] = super_screen[x + yline]
					if y < bit4 then
						super_screen[x + yline] = 0
					end
				end
			end
		elseif bit3 == 0xE and bit4 == 0x0 then -- CLS
			if schip_mode then
				clearSuperScreen()
			else
				clearScreen()
			end
		elseif bit3 == 0xE and bit4 == 0xE then -- RET
			SP = SP - 1
			PC = stack[SP]
		elseif bit3 == 0xF and bit4 == 0xB then -- SCR *SCHIP*
			for y=0, 63 do
				local yline = bit32.lshift(y , 7)
				for x=4, 127 do
					super_screen[x + yline] = super_screen[x + yline - 4]
				end
				super_screen[yline] = 0
				super_screen[yline+1] = 0
				super_screen[yline+2] = 0
				super_screen[yline+3] = 0
			end
		elseif bit3 == 0xF and bit4 == 0xC then -- SCL *SCHIP*
			for y=0, 63 do
				local yline = bit32.lshift(y , 7)
				for x=0, 123 do	
					super_screen[x + yline] = super_screen[x + yline + 4]
				end
				super_screen[yline+124] = 0
				super_screen[yline+125] = 0
				super_screen[yline+126] = 0
				super_screen[yline+127] = 0
			end
		elseif bit3 == 0xF and bit4 == 0xD then -- EXIT
			state = 0
		elseif bit3 == 0xF and bit4 == 0xE then -- LOW *SCHIP*
			schip_mode = false
		elseif bit3 == 0xF and bit4 == 0xF then -- HIGH *SCHIP*
			schip_mode = true
		else
			showError("ERROR: Unknown opcode: 0x" .. string.format("%X",opcode))
		end
	elseif bit1 == 0x1 then -- JP addr
		PC = bit32.band(opcode,0x0FFF)
	elseif bit1 == 0x2 then -- CALL addr
		stack[SP] = PC
		SP = SP + 1
		PC = bit32.band(opcode,0x0FFF)
	elseif bit1 == 0x3 then -- SE Vx, byte
		if V[bit2] == bit32.band(opcode, 0x00FF) then
			PC = PC + 2
		end
	elseif bit1 == 0x4 then -- SNE Vx, byte
		if V[bit2] ~= bit32.band(opcode, 0x00FF) then
			PC = PC + 2
		end
	elseif bit1 == 0x5 then -- SE Vx, Vy
		if V[bit2] == V[bit3] then
			PC = PC + 2
		end
	elseif bit1 == 0x6 then -- LD Vx, byte
		V[bit2] = bit32.band(opcode, 0x00FF)
	elseif bit1 == 0x7 then -- ADD Vx, byte
		V[bit2] = bit32.band(V[bit2] + bit32.band(opcode, 0x00FF), 0x00FF)
	elseif bit1 == 0x8 then
		if bit4 == 0x0 then -- LD Vx, Vy
			V[bit2] = V[bit3]
		elseif bit4 == 0x1 then -- OR Vx, Vy
			V[bit2] = bit32.bor(V[bit2],V[bit3])
		elseif bit4 == 0x2 then -- AND Vx, Vy
			V[bit2] = bit32.band(V[bit2],V[bit3])
		elseif bit4 == 0x3 then -- XOR Vx, Vy
			V[bit2] = bit32.bxor(V[bit2],V[bit3])
		elseif bit4 == 0x4 then -- ADD Vx, Vy
			V[bit2] = V[bit2] + V[bit3]
			if V[bit2] > 0xFF then
				V[0xF] = 1
				V[bit2] = bit32.band(V[bit2], 0x00FF)
			else
				V[0xF] = 0
			end
		elseif bit4 == 0x5 then -- SUB Vx, Vy
			V[bit2] = V[bit2] - V[bit3]
			if V[bit2] > 0 then
				V[0xF] = 1
			else
				V[0xF] = 0
				V[bit2] = bit32.band(V[bit2], 0x00FF)
			end
		elseif bit4 == 0x6 then -- SHR Vx
			V[0xF] = bit32.band(V[bit2],1)
			V[bit2] = bit32.rshift(V[bit2],1)
		elseif bit4 == 0x7 then -- SUBN Vx, Vy
			V[bit2] = V[bit3] - V[bit2]
			if V[bit2] > 0 then
				V[0xF] = 1
			else
				V[0xF] = 0
				V[bit2] = bit32.band(V[bit2], 0x00FF)
			end
		elseif bit4 == 0xE then -- SHL Vx
			if bit32.band(V[bit2], 0x80) == 0x80 then
				V[0xF] = 1
			else
				V[0xF] = 0
			end
			V[bit2] = bit32.band(bit32.lshift(V[bit2],1), 0x00FF)
		else
			showError("ERROR: Unknown opcode: 0x" .. string.format("%X",opcode))
		end
	elseif bit1 == 0x9 then -- SNE Vx, Vy
		if V[bit2] ~= V[bit3] then
			PC = PC + 2
		end
	elseif bit1 == 0xA then -- LD I, addr
		I = bit32.band(opcode,0x0FFF)
	elseif bit1 == 0xB then -- JP V0, addr
		PC = V[0] + bit32.band(opcode, 0x0FFF)
	elseif bit1 == 0xC then -- RND Vx, byte
		V[bit2] = bit32.band(math.random(0, 0xFF), bit32.band(opcode, 0x00FF))
	elseif bit1 == 0xD then -- DRW Vx, Vy, nibble
		local x = V[bit2]
		local y = V[bit3]
		local h = bit4
		local pixel
		V[0xF] = 0
		if schip_mode then
			if h == 0 then
				for yline=0, 15 do
					local y_idx = (y + yline) % 64
					local y_pixel = bit32.lshift(yline,1)
					pixel = ram[I + y_pixel]
					for xline=0, 7 do
						local x_idx = (x + xline) % 128
						if ((bit32.band(pixel,bit32.rshift(0x80, xline))) > 0) then
							pixel_idx = x_idx + (bit32.lshift(y_idx, 7))
							if super_screen[pixel_idx] == 1 then
								V[0xF] = 1
							end
							super_screen[pixel_idx] = bit32.bxor(super_screen[pixel_idx],1)
						end
					end
					pixel = ram[I + y_pixel]
					for xline=8, 15 do
						local x_idx = (x + xline) % 128
						if ((bit32.band(pixel,bit32.rshift(0x80, xline))) > 0) then
							pixel_idx = x_idx + (bit32.lshift(y_idx, 7))
							if super_screen[pixel_idx] == 1 then
								V[0xF] = 1
							end
							super_screen[pixel_idx] = bit32.bxor(super_screen[pixel_idx],1)
						end
					end
				end
			else
				for yline=0, h-1 do
					local y_idx = (y + yline) % 64
					pixel = ram[I + yline]
					for xline=0, 7 do
						local x_idx = (x + xline) % 128
						if ((bit32.band(pixel,bit32.rshift(0x80, xline))) > 0) then
							pixel_idx = x_idx + (bit32.lshift(y_idx, 7))
							if super_screen[pixel_idx] == 1 then
								V[0xF] = 1
							end
							super_screen[pixel_idx] = bit32.bxor(super_screen[pixel_idx],1)
						end
					end
				end
			end
		else
			if h == 0 then
				h = 16
			end
			for yline=0, h-1 do
				local y_idx = (y + yline) % 32
				pixel = ram[I + yline]
				for xline=0, 7 do
					local x_idx = (x + xline) % 64
					if ((bit32.band(pixel,bit32.rshift(0x80, xline))) > 0) then
						pixel_idx = x_idx + (bit32.lshift(y_idx, 6))
						if screen[pixel_idx] == 1 then
							V[0xF] = 1
						end
						screen[pixel_idx] = bit32.bxor(screen[pixel_idx],1)
					end
				end
			end
		end
		updateScreen = true
	elseif bit1 == 0xE then
		if bit3 == 0x9 and bit4 == 0xE then -- SKP Vx
			if key[V[bit2]] then
				PC = PC + 2
			end
		elseif bit3 == 0xA and bit4 == 0x1 then -- SKPN Vx
			if not key[V[bit2]] then
				PC = PC + 2
			end
		else
			showError("ERROR: Unknown opcode: 0x" .. string.format("%X",opcode))
		end
	elseif bit1 == 0xF then
		if bit3 == 0x0 and bit4 == 0x7 then -- LD Vx, DT
			V[bit2] = delay_timer
		elseif bit3 == 0x0 and bit4 == 0xA then -- LD Vx, K
			keyPress = false
			for key_idx=0, 15 do
				if key[key_idx] then
					V[bit2] = key_idx
					keyPress = true
					break
				end
			end
			if not keyPress then
				PC = PC - 2
			end
		elseif bit3 == 0x1 and bit4 == 0x5 then -- LD DT, Vx
			delay_timer = V[bit2]
		elseif bit3 == 0x1 and bit4 == 0x8 then -- LD ST, Vx
			sound_timer = V[bit2]
		elseif bit3 == 0x1 and bit4 == 0xE then -- ADD I, Vx
			I = I + V[bit2]
		elseif bit3 == 0x2 and bit4 == 0x9 then -- LD F, Vx
			I = V[bit2] * 5
		elseif bit3 == 0x3 and bit4 == 0x0 then -- LD LF, Vx *SCHIP*
			I = V[bit2] * 10 + 0x50
		elseif bit3 == 0x3 and bit4 == 0x3 then -- LD B, Vx
			local n = V[bit2]
			ram[I] = math.floor(n / 100) % 10
			ram[I + 1] = math.floor(n / 10) % 10
			ram[I + 2] = n % 10
		elseif bit3 == 0x5 and bit4 == 0x5 then -- LD [I], Vx
			for i=0, bit2 do
				ram[I + i] = V[i]
			end
		elseif bit3 == 0x6 and bit4 == 0x5 then -- LD Vx, [I]
			for i=0, bit2 do
				V[i] = ram[I + i]
			end
		elseif bit3 == 0x7 and bit4 == 0x5 then -- LD R, Vx *SCHIP*
			for i=0, bit2 do
				hp48_flags[i] = V[i]
			end
		elseif bit3 == 0x8 and bit4 == 0x5 then -- LD Vx, R *SCHIP*
			for i=0, bit2 do
				V[i] = hp48_flags[i]
			end
		else
			showError("ERROR: Unknown opcode: 0x" .. string.format("%X",opcode))
		end
	else
		showError("ERROR: Unknown opcode: 0x" .. string.format("%X",opcode))
	end
	
end

function handleTimers()
	
	update_timers = not update_timers
	
	-- Updating timers
	if update_timers then
		if delay_timer > 0 then
			delay_timer = delay_timer - 1
		end
		if sound_timer > 0 then
			if sound_timer == 1 then
				Sound.play(beep, NO_LOOP)
			end
			sound_timer = sound_timer - 1
		end
	end
	
end

-- Get Roms List
function getRomList()
	System.createDirectory(romFolder)
	System.createDirectory(savFolder)
	files = System.listDirectory(romFolder)
	for i, file in pairs(files) do
		if not file.directory then
			table.insert(roms, file.name)
		end
	end
	if #roms == 0 then
		showError("FATAL ERROR: No roms detected.")
	end
end

-- Draw roms selector on screen
function drawRomSelector()
	Screen.clear()
	Graphics.debugPrint(0, 0, "MicroCHIP v." .. ver .. " - Select rom to play", yellow)
	if cursor > 24 then
		first = cursor - 24
	else
		first = 0
	end
	for i, rom in pairs(roms) do
		if i > first then
			if cursor == i then
				Graphics.debugPrint(0, 15 + (i - first) * 20, rom, cyan)
			else
				Graphics.debugPrint(0, 15 + (i - first) * 20, rom, white)
			end
		end
	end
end

-- Handle rom selector user input
function handleRomSelection()
	local loadState = false
	pad = Controls.read()
	if Controls.check(pad, SCE_CTRL_UP) and not Controls.check(oldpad, SCE_CTRL_UP) then
		cursor = cursor - 1
		if cursor < 1 then
			cursor = #roms
		end
	elseif Controls.check(pad, SCE_CTRL_DOWN) and not Controls.check(oldpad, SCE_CTRL_DOWN) then
		cursor = cursor + 1
		if cursor > #roms then
			cursor = 1
		end
	elseif Controls.check(pad, SCE_CTRL_CROSS) and not Controls.check(oldpad, SCE_CTRL_CROSS) then
		if System.doesFileExist(savFolder.."/"..roms[cursor]..".sav") then
			loadState = showAnswer("A savestate has been detected. Do you want to load it?")	
		end
		currentRomCursor = cursor
		loadRom(romFolder.."/"..roms[cursor])
		if loadState then
			loadSavestate()
		end
		state = 1
	end
	oldpad = pad
end

-- Load a savestate
function loadSavestate()
	if not System.doesFileExist(savFolder.."/"..cur_rom..".sav") then
        return false
	end
	local fd = System.openFile(savFolder.."/"..cur_rom..".sav", FREAD)
	PC_b1 = string.byte(System.readFile(fd,1))
	PC_b2 = string.byte(System.readFile(fd,1))
	PC = PC_b2 + bit32.lshift(PC_b1,8)
	I_b1 = string.byte(System.readFile(fd,1))
	I_b2 = string.byte(System.readFile(fd,1))
	I = I_b2 + bit32.lshift(I_b1,8)
	SP = string.byte(System.readFile(fd,1))
	delay_timer = string.byte(System.readFile(fd,1))
	sound_timer = string.byte(System.readFile(fd,1))
	for i=0, 15 do
		V[i] = string.byte(System.readFile(fd,1))
	end
	for i=0, 15 do
		S_b1 = string.byte(System.readFile(fd,1))
		S_b2 = string.byte(System.readFile(fd,1))
		stack[i] = S_b2 + bit32.lshift(S_b1,8)
	end
	for i=0, 0x800 do
		screen[i] = string.byte(System.readFile(fd,1))
	end
	for i=0, 0xFFF do
		ram[i] = string.byte(System.readFile(fd,1))
	end
	System.closeFile(fd)
	return true
end

-- Save a savestate
function saveSavestate()
	if System.doesFileExist(savFolder.."/"..cur_rom..".sav") then
		System.deleteFile(savFolder.."/"..cur_rom..".sav")
	end
	local fd = System.openFile(savFolder.."/"..cur_rom..".sav", FCREATE)
	local buffer = ""
	PC_b1 = bit32.rshift(bit32.band(PC,0xFF00),8)
	PC_b2 = bit32.band(PC,0x00FF)
	buffer = buffer .. string.char(PC_b1) .. string.char(PC_b2)
	I_b1 = bit32.rshift(bit32.band(I,0xFF00),8)
	I_b2 = bit32.band(I,0x00FF)
	buffer = buffer .. string.char(I_b1) .. string.char(I_b2)
	buffer = buffer .. string.char(SP) .. string.char(delay_timer) .. string.char(sound_timer)
	for i=0, 15 do
		buffer = buffer .. string.char(V[i])
	end
	for i=0, 15 do
		S_b1 = bit32.rshift(bit32.band(stack[i],0xFF00),8)
		S_b2 = bit32.band(stack[i],0x00FF)
		buffer = buffer .. string.char(S_b1) .. string.char(S_b2)
	end
	for i=0, 0x800 do
		buffer = buffer .. string.char(screen[i])
	end
	for i=0, 0xFFF do
		buffer = buffer .. string.char(ram[i])
	end
	System.writeFile(fd,buffer,0x1828)
	System.closeFile(fd)
end

-- Handle pause menu keys
function handlePauseKeys()
	t = Controls.readTouch()
	if t ~= nil and not (old_t ~= nil) then
		state = 1
		pushNotification("Game resumed.")
	end
	old_t = t
	pad = Controls.read()
	if Controls.check(pad, SCE_CTRL_UP) and not Controls.check(oldpad, SCE_CTRL_UP) then
		cursor = cursor - 1
		if cursor < 1 then
			cursor = #pause_menu_entries
		end
	elseif Controls.check(pad, SCE_CTRL_DOWN) and not Controls.check(oldpad, SCE_CTRL_DOWN) then
		cursor = cursor + 1
		if cursor > #pause_menu_entries then
			cursor = 1
		end
	elseif Controls.check(pad, SCE_CTRL_CROSS) and not Controls.check(oldpad, SCE_CTRL_CROSS) then
		if cursor == 1 then -- Resume game
			state = 1
			pushNotification("Game resumed.")
		elseif cursor == 2 then -- Save savestate
			saveSavestate()
			pushNotification("Savestate created successfully!")
		elseif cursor == 3 then -- Load savestate
			if loadSavestate() then 
				pushNotification("Savestate loaded successfully!")
			else
			    pushNotification("Savestate does not exist")
			end
		elseif cursor == 4 then -- Reset game
			loadRom(romFolder.."/"..roms[currentRomCursor])
			state = 1
		elseif cursor == 5 then -- Show / Hide debugger
			debugger = not debugger
			if debugger then
				pushNotification("Debugger enabled")
			else
				-- Clear screen to remove debugger stuff
				purgeScreen()
				pushNotification("Debugger disabled")
			end
		elseif cursor == 6 then -- Options
			state = 3
			cursor = 1
			old_state = 2
			old_bg_color = bg_color
			old_nbg_color = nbg_color
		elseif cursor == 7 then -- Close rom
			state = 0
			cursor = currentRomCursor
		end
	end
	oldpad = pad
end

-- Draws pause menu
function drawPauseMenu()
	-- Calculate the space occupied by the entries based on their number
	local menu_entries_height = #pause_menu_entries*22
	drawRect(300, 660, 150, 150 + menu_entries_height, white)
	drawRect(301, 659, 151, 149 + menu_entries_height, black)
	for i=1, #pause_menu_entries do
		if i == cursor then
			Graphics.debugPrint(305, 155 + (i-1)*20, pause_menu_entries[i], cyan)
		else
			Graphics.debugPrint(305, 155 + (i-1)*20, pause_menu_entries[i], white)
		end
	end
end

-- Draws debugger
function drawDebugger()
	drawRect(5, 955, 470, 540, white)
	drawRect(6, 954, 471, 539, black)
	Graphics.debugPrint(10, 475, "PC: 0x" .. string.format("%X",PC), white)
	Graphics.debugPrint(10, 495, "SP: 0x" .. string.format("%X",SP), white)
	if SP > 0 then
		Graphics.debugPrint(10, 515, "RA: 0x" .. string.format("%X",stack[SP-1]), white)
	else
		Graphics.debugPrint(10, 515, "RA: 0x00", white)
	end
	for i=0, 15 do
		local z = i % 3
		Graphics.debugPrint(130 + math.floor(i/3) * 120, 475 + 20 * z, "V" .. i .. ": 0x" .. string.format("%X",V[i]), white)
	end
	Graphics.debugPrint(730, 495, "I: 0x" .. string.format("%X",I), white)
	Graphics.debugPrint(730, 515, "Ins: 0x" .. string.format("%X",opcode), white)
end

-- Save options config
function saveConfig()
	if System.doesFileExist(emuFolder .. "/options.cfg") then
		System.deleteFile(emuFolder .. "/options.cfg")
	end
	local fd = System.openFile(emuFolder .. "/options.cfg", FCREATE)
	System.writeFile(fd, string.char(bg_r), 1)
	System.writeFile(fd, string.char(bg_g), 1)
	System.writeFile(fd, string.char(bg_b), 1)
	System.writeFile(fd, string.char(nbg_r), 1)
	System.writeFile(fd, string.char(nbg_g), 1)
	System.writeFile(fd, string.char(nbg_b), 1)
	for i=1, 12 do
		System.writeFile(fd, string.char(keys[i].int), 1)
	end
	System.closeFile(fd)
	pushNotification("Config saved successfully!")
end

-- Load options config
function loadConfig()
	if System.doesFileExist(emuFolder .. "/options.cfg") then
		local fd = System.openFile(emuFolder .. "/options.cfg", FREAD)
		bg_r = string.byte(System.readFile(fd, 1))
		bg_g = string.byte(System.readFile(fd, 1))
		bg_b = string.byte(System.readFile(fd, 1))
		nbg_r = string.byte(System.readFile(fd, 1))
		nbg_g = string.byte(System.readFile(fd, 1))
		nbg_b = string.byte(System.readFile(fd, 1))
		for i=1, 12 do
			keys[i].int = string.byte(System.readFile(fd, 1))
		end
		System.closeFile(fd)
		bg_color = Color.new(bg_r, bg_g, bg_b)
		nbg_color = Color.new(nbg_r, nbg_g, nbg_b)
	end
end

-- Draw keys rebind menu
function drawRebindMenu()
	Screen.clear()
	for i=1, 12 do
		if i == cursor then
			Graphics.debugPrint(20, 30 + i * 20, keys[i].name .. " : " .. string.format("%X", keys[i].int), cyan)
		else
			Graphics.debugPrint(20, 30 + i * 20, keys[i].name .. " : " .. string.format("%X", keys[i].int), white)
		end
	end
	if cursor == 13 then
		Graphics.debugPrint(20, 320, "Save changes", cyan)
	else
		Graphics.debugPrint(20, 320, "Save changes", white)
	end
	if cursor == 14 then
		Graphics.debugPrint(20, 340, "Discard changes", cyan)
	else
		Graphics.debugPrint(20, 340, "Discard changes", white)
	end
end

function handleRebindKeys()
	pad = Controls.read()
	if Controls.check(pad, SCE_CTRL_UP) and not Controls.check(oldpad, SCE_CTRL_UP) then
		cursor = cursor - 1
		if cursor < 1 then
			cursor = 14
		end
	elseif Controls.check(pad, SCE_CTRL_DOWN) and not Controls.check(oldpad, SCE_CTRL_DOWN) then
		cursor = cursor + 1
		if cursor > 14 then
			cursor = 1
		end
	elseif Controls.check(pad, SCE_CTRL_CROSS) and not Controls.check(oldpad, SCE_CTRL_CROSS) then
		if cursor >= 13 then
			state = 3
			cursor = 1
			if cursor == 14 then
				for i=1, 12 do
					keys[i].int = keys_backup[i]
				end
			end
		end
	elseif Controls.check(pad, SCE_CTRL_LEFT) and not Controls.check(oldpad, SCE_CTRL_LEFT) then
		if cursor <= 12 then
			if keys[cursor].int > 0x1 then
				keys[cursor].int = keys[cursor].int - 1
			end
		end
	elseif Controls.check(pad, SCE_CTRL_RIGHT) and not Controls.check(oldpad, SCE_CTRL_RIGHT) then
		if cursor <= 12 then
			if keys[cursor].int < 0xF then
				keys[cursor].int = keys[cursor].int + 1
			end
		end
	end
	oldpad = pad
end

-- Draw options menu
function drawOptionsMenu()
	Screen.clear()
	
	-- Background color tab	
	drawRect(20, 940, 50, 220, white)
	drawRect(21, 939, 51, 219, black)
	drawRect(40, 80, 140, 180, white)
	drawRect(41, 79, 141, 179, bg_color)
	if cursor > 0 and cursor < 4 then
		drawRect(99, 867, 104 + (cursor - 1) * 40, 126 + (cursor - 1) * 40, cyan)
	end
	drawRect(100, 101 + 3 * bg_r, 105, 125, red)
	drawRect(100, 101 + 3 * bg_g, 145, 165, green)
	drawRect(100, 101 + 3 * bg_b, 185, 205, blue)
	Graphics.debugPrint(40, 65, "Background color", white)
	
	-- Non background color tab
	drawRect(20, 940, 240, 410, white)
	drawRect(21, 939, 241, 409, black)
	drawRect(40, 80, 330, 370, white)
	drawRect(41, 79, 331, 369, nbg_color)
	if cursor > 3 and cursor < 7 then
		drawRect(99, 867, 294 + (cursor - 4) * 40, 316 + (cursor - 4) * 40, cyan)
	end
	drawRect(100, 101 + 3 * nbg_r, 295, 315, red)
	drawRect(100, 101 + 3 * nbg_g, 335, 355, green)
	drawRect(100, 101 + 3 * nbg_b, 375, 395, blue)
	Graphics.debugPrint(40, 255, "Sprites color", white)
	
	-- Menu entries
	if cursor == 7 then
		Graphics.debugPrint(20, 450, "Rebind keys", cyan)
	else
		Graphics.debugPrint(20, 450, "Rebind keys", white)
	end
	if cursor == 8 then
		Graphics.debugPrint(20, 470, "Save changes", cyan)
	else
		Graphics.debugPrint(20, 470, "Save changes", white)
	end
	if cursor == 9 then
		Graphics.debugPrint(20, 490, "Discard changes", cyan)
	else
		Graphics.debugPrint(20, 490, "Discard changes", white)
	end
	
end

function handleOptionsKeys()
	pad = Controls.read()
	if Controls.check(pad, SCE_CTRL_UP) and not Controls.check(oldpad, SCE_CTRL_UP) then
		cursor = cursor - 1
		if cursor < 1 then
			cursor = 9
		end
	elseif Controls.check(pad, SCE_CTRL_DOWN) and not Controls.check(oldpad, SCE_CTRL_DOWN) then
		cursor = cursor + 1
		if cursor > 9 then
			cursor = 1
		end
	elseif Controls.check(pad, SCE_CTRL_CROSS) and not Controls.check(oldpad, SCE_CTRL_CROSS) then
		if cursor == 7 then
			state = 4
			cursor = 1
			for i=1, 12 do
				keys_backup[i] = keys[i].int
			end
		elseif cursor == 8 then
			state = old_state
			cursor = 1
			saveConfig()
		elseif cursor == 9 then
			state = old_state
			cursor = 1
			bg_color = old_bg_color
			nbg_color = old_nbg_color
			bg_r = Color.getR(bg_color)
			bg_g = Color.getG(bg_color)
			bg_b = Color.getB(bg_color)
			nbg_r = Color.getR(nbg_color)
			nbg_g = Color.getG(nbg_color)
			nbg_b = Color.getB(nbg_color)
		end
		if state == 1 then
			cursor = 4
		end
	elseif Controls.check(pad, SCE_CTRL_LEFT) then
		if cursor == 1 then
			bg_r = bg_r - 1
			if bg_r < 0 then
				bg_r = 0
			end
		elseif cursor == 2 then
			bg_g = bg_g - 1
			if bg_g < 0 then
				bg_g = 0
			end
		elseif cursor == 3 then
			bg_b = bg_b - 1
			if bg_b < 0 then
				bg_b = 0
			end
		elseif cursor == 4 then
			nbg_r = nbg_r - 1
			if nbg_r < 0 then
				nbg_r = 0
			end
		elseif cursor == 5 then
			nbg_g = nbg_g - 1
			if nbg_g < 0 then
				nbg_g = 0
			end
		elseif cursor == 6 then
			nbg_b = nbg_b - 1
			if nbg_b < 0 then
				nbg_b = 0
			end
		end
		bg_color = Color.new(bg_r, bg_g, bg_b)
		nbg_color = Color.new(nbg_r, nbg_g, nbg_b)
	elseif Controls.check(pad, SCE_CTRL_RIGHT) then
		if cursor == 1 then
			bg_r = bg_r + 1
			if bg_r > 255 then
				bg_r = 255
			end
		elseif cursor == 2 then
			bg_g = bg_g + 1
			if bg_g > 255 then
				bg_g = 255
			end
		elseif cursor == 3 then
			bg_b = bg_b + 1
			if bg_b > 255 then
				bg_b = 255
			end
		elseif cursor == 4 then
			nbg_r = nbg_r + 1
			if nbg_r > 255 then
				nbg_r = 255
			end
		elseif cursor == 5 then
			nbg_g = nbg_g + 1
			if nbg_g > 255 then
				nbg_g = 255
			end
		elseif cursor == 6 then
			nbg_b = nbg_b + 1
			if nbg_b > 255 then
				nbg_b = 255
			end
		end
		bg_color = Color.new(bg_r, bg_g, bg_b)
		nbg_color = Color.new(nbg_r, nbg_g, nbg_b)
	end
	oldpad = pad
end

-- Initializing emulator
Sound.init()
beep = Sound.open("app0:beep.ogg")
getRomList()
loadConfig()

-- Main loop
while true do
	
	if state == 0 then -- Rom selection
		Graphics.initBlend()
		drawRomSelector()
		Graphics.termBlend()
		Screen.flip()
		handleRomSelection()
	elseif state == 1 then -- Game loop
		handleKeys()
		for i=0, 8 do
			executeOpcode()
		end
		if updateScreen then
			Graphics.initBlend()
			drawScreen()
			drawRect(0, 960, 0, 32, black)
			if state_timer > 0 then
				Graphics.debugPrint(0, 0, notification, yellow)
				state_timer = state_timer - 1
			end
			if debugger then
				drawDebugger()
			end
			Graphics.termBlend()
			Screen.flip()
		end
		handleTimers()
	elseif state == 2 then -- Pause menu
		Graphics.initBlend()
		drawScreen()
		drawRect(0, 960, 0, 32, black)
		if state_timer > 0 then
			Graphics.debugPrint(0, 0, notification, yellow)
			state_timer = state_timer - 1
		end
		drawPauseMenu()
		if debugger then
			drawDebugger()
		end
		Graphics.termBlend()
		Screen.flip()
		handlePauseKeys()
	elseif state == 3 then -- Options Menu
		Graphics.initBlend()
		drawOptionsMenu()
		Graphics.termBlend()
		Screen.flip()
		handleOptionsKeys()
	elseif state == 4 then -- Keys Rebinding
		Graphics.initBlend()
		drawRebindMenu()
		Graphics.termBlend()
		Screen.flip()
		handleRebindKeys()
	end
	
end