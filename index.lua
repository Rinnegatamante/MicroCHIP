-- CHIP-8 State
local opcode = 0
local ram = {}
local V = {}
local I = 0x000
local PC = 0x000
local SP = 0
local screen = {} -- 64x32 -> 960x480 (x15)
local delay_timer = 0
local sound_timer = 0
local stack = {}
local key = {}
local updateScreen = false
local beep = nil
local cur_rom = ""

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
	{["val"] = SCE_CTRL_UP, ["int"] = 0x01},
	{["val"] = SCE_CTRL_DOWN, ["int"] = 0x04},
	{["val"] = SCE_CTRL_LEFT, ["int"] = 0x02},
	{["val"] = SCE_CTRL_RIGHT, ["int"] = 0x03},
	{["val"] = SCE_CTRL_TRIANGLE, ["int"] = 0x0C},
	{["val"] = SCE_CTRL_CROSS, ["int"] = 0x0D},
	{["val"] = SCE_CTRL_SQUARE, ["int"] = 0x0E},
	{["val"] = SCE_CTRL_CIRCLE, ["int"] = 0x0F},
	{["val"] = SCE_CTRL_LTRIGGER, ["int"] = 0x05},
	{["val"] = SCE_CTRL_RTRIGGER, ["int"] = 0x06},
	{["val"] = SCE_CTRL_START, ["int"] = 0x07},
	{["val"] = SCE_CTRL_SELECT, ["int"] = 0x08}
}

-- Emulator State
local state = 0
local old_state = 0
local romFolder = "ux0:data/MicroCHIP/roms"
local savFolder = "ux0:data/MicroCHIP/saves"
local roms = {}
local ver = "1.0"
local cursor = 1
local oldpad = SCE_CTRL_CROSS
local notification = ""
local t = nil
local old_t = nil
local pause_menu_entries = {"Resume game", "Save savestate", "Load savestate", "Options", "Close rom"}

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

-- Clear CHIP-8 screen
function clearScreen()
	for i=0, 0x800 do
		screen[i] = 0
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
	
	-- Clearing screen
	clearScreen()
	
	-- Resetting stack, keystates, registers and ram
	for i=0, 15 do
		stack[i] = 0
		V[i] = 0
		key[i] = 0
	end
	for i=0, 0xFFF do
		ram[i] = 0
	end
	
	-- Reset timers
	delay_timer = 0
	sound_timer = 0
	
	-- Loading fontset
	for i=0, 0x4F do
		ram[i] = fontset[i+1]
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
	cur_rom = roms[cursor]
	pushNotification("Rom " .. cur_rom .. " loaded successfully!")
end

-- Draw CHIP-8 display on screen
function drawScreen()
	for y=0, 31 do
		for x=0, 63 do
			x_val = x * 15
			y_val = (y * 15) + 32
			if screen[bit32.lshift(y,6) + x] == 0 then
				Graphics.fillRect(x_val, x_val + 15, y_val, y_val + 15, bg_color)
			else
				Graphics.fillRect(x_val, x_val + 15, y_val, y_val + 15, nbg_color)
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
	bit1 = bit32.rshift(bit32.band(opcode,0xF000),12)
	bit2 = bit32.rshift(bit32.band(opcode,0x0F00),8)
	bit3 = bit32.rshift(bit32.band(opcode,0x00F0),4)
	bit4 = bit32.band(opcode,0x000F)
	
	-- Executing opcode
	PC = PC + 2
	if bit1 == 0x0 then
		if bit4 == 0x0 then -- CLS
			clearScreen()
		elseif bit4 == 0xE then -- RET
			SP = SP - 1
			PC = stack[SP]
		else
			showError("ERROR: Unknown opcode: 0x" .. string.format("%X",opcode))
		end
	elseif bit1 == 0x1 then -- JP
		PC = bit32.band(opcode,0x0FFF)
	elseif bit1 == 0x2 then -- CALL
		stack[SP] = PC
		SP = SP + 1
		PC = bit32.band(opcode,0x0FFF)
	elseif bit1 == 0x3 then -- SE
		val = bit32.band(opcode, 0x00FF)
		if V[bit2] == val then
			PC = PC + 2
		end
	elseif bit1 == 0x4 then -- SNE
		val = bit32.band(opcode, 0x00FF)
		if V[bit2] ~= val then
			PC = PC + 2
		end
	elseif bit1 == 0x5 then -- SE
		if V[bit2] == V[bit3] then
			PC = PC + 2
		end
	elseif bit1 == 0x6 then -- LD
		V[bit2] = bit32.band(opcode, 0x00FF)
	elseif bit1 == 0x7 then -- ADD
		V[bit2] = bit32.band(V[bit2] + bit32.band(opcode, 0x00FF), 0x00FF)
	elseif bit1 == 0x8 then
		if bit4 == 0x0 then -- LD
			V[bit2] = V[bit3]
		elseif bit4 == 0x1 then -- OR
			V[bit2] = bit32.band(bit32.bor(V[bit2],V[bit3]),0x00FF)
		elseif bit4 == 0x2 then -- AND
			V[bit2] = bit32.band(V[bit2],V[bit3])
		elseif bit4 == 0x3 then -- XOR
			V[bit2] = bit32.band(bit32.bxor(V[bit2],V[bit3]),0x00FF)
		elseif bit4 == 0x4 then -- ADD
			V[bit2] = V[bit2] + V[bit3]
			if V[bit2] > 0xFF then
				V[0xF] = 1
				V[bit2] = bit32.band(V[bit2], 0x00FF)
			else
				V[0xF] = 0
			end
		elseif bit4 == 0x5 then -- SUB
			if V[bit3] > V[bit2] then
				V[0xF] = 0
			else
				V[0xF] = 1
			end
			V[bit2] = V[bit2] - V[bit3]
		elseif bit4 == 0x6 then -- SHR
			V[0xF] = bit32.band(V[bit3],1)
			V[bit2] = bit32.rshift(V[bit3],1)
		elseif bit4 == 0x7 then -- SUBN
			V[bit2] = V[bit3] - V[bit2]
			if V[bit2] > 0 then
				V[0xF] = 1
			else
				V[0xF] = 0
				V[bit2] = bit32.band(V[bit2], 0x00FF)
			end
		elseif bit4 == 0xE then -- SHL
			V[0xF] = bit32.band(bit32.rshift(V[bit3],7),1)
			V[bit2] = bit32.lshift(V[bit3],1)
		else
			showError("ERROR: Unknown opcode: 0x" .. string.format("%X",opcode))
		end
	elseif bit1 == 0x9 then -- SNE
		if V[bit2] ~= V[bit3] then
			PC = PC + 2
		end
	elseif bit1 == 0xA then -- LD I
		I = bit32.band(opcode,0x0FFF)
	elseif bit1 == 0xB then -- JP V0
		PC = V[0] + bit32.band(opcode, 0x0FFF)
	elseif bit1 == 0xC then -- RND
		V[bit2] = bit32.band(math.random() % 0x100, bit32.band(opcode, 0x00FF))
	elseif bit1 == 0xD then -- DRW
		local x = V[bit2]
		local y = V[bit3]
		local h = bit4
		V[0xF] = 0
		for yline=0, h-1 do
			local y_idx = (y + yline) % 32
			pixel = ram[I + yline]
			for xline=0, 7 do
				local x_idx = (x + xline) % 64
				if ((bit32.band(pixel,bit32.rshift(0x80, xline))) ~= 0) then
					pixel_idx = x_idx + (bit32.lshift(y_idx, 6))
					if screen[pixel_idx] == 1 then
						V[0xF] = 1
						screen[pixel_idx] = 0
					else
						screen[pixel_idx] = 1
					end
				end
			end
		end
		updateScreen = true
	elseif bit1 == 0xE then
		if bit3 == 0x9 and bit4 == 0xE then -- SKP
			if key[V[bit2]] then
				PC = PC + 2
			end
		elseif bit3 == 0xA and bit4 == 0x1 then -- SKNP
			if not key[V[bit2]] then
				PC = PC + 2
			end
		else
			showError("ERROR: Unknown opcode: 0x" .. string.format("%X",opcode))
		end
	elseif bit1 == 0xF then
		if bit3 == 0x0 and bit4 == 0x7 then -- LD DT
			V[bit2] = delay_timer
		elseif bit3 == 0x0 and bit4 == 0xA then -- LD KEY
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
		elseif bit3 == 0x1 and bit4 == 0x5 then -- LD DT (set)
			delay_timer = V[bit2]
		elseif bit3 == 0x1 and bit4 == 0x8 then -- LD ST (set)
			sound_timer = V[bit2]
		elseif bit3 == 0x1 and bit4 == 0xE then -- ADD I
			I = I + V[bit2]
		elseif bit3 == 0x2 and bit4 == 0x9 then -- LD sprite
			I = V[bit2] * 5
		elseif bit3 == 0x3 and bit4 == 0x3 then -- LD BCD
			local n = V[bit2]
			ram[I] = (n / 100) % 10
			ram[I + 1] = (n / 10) % 10
			ram[I + 2] = n % 10
		elseif bit3 == 0x5 and bit4 == 0x5 then -- LD mpoke
			for i=0, bit2 do
				ram[I + i] = V[i]
			end
			I = I + bit2 + 1
		elseif bit3 == 0x6 and bit4 == 0x5 then -- LD mpeek
			for i=0, bit2 do
				V[I] = ram[I + i]
				i = i + 1
			end
			I = I + bit2 + 1
		else
			showError("ERROR: Unknown opcode: 0x" .. string.format("%X",opcode))
		end
	else
		showError("ERROR: Unknown opcode: 0x" .. string.format("%X",opcode))
	end
	
	-- Updating timers
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
			loadSavestate()
			pushNotification("Savestate loaded successfully!")
		elseif cursor == 4 then -- Options
			state = 3
			cursor = 1
			old_state = 2
			old_bg_color = bg_color
			old_nbg_color = nbg_color
		elseif cursor == 5 then -- Close rom
			state = 0
			cursor = 1
		end
	end
	oldpad = pad
end

-- Draws pause menu
function drawPauseMenu()
	Graphics.fillRect(300, 660, 150, 260, white)
	Graphics.fillRect(301, 659, 151, 259, black)
	for i=1, #pause_menu_entries do
		if i == cursor then
			Graphics.debugPrint(305, 155 + (i-1)*20, pause_menu_entries[i], cyan)
		else
			Graphics.debugPrint(305, 155 + (i-1)*20, pause_menu_entries[i], white)
		end
	end
end

-- Save options config
function saveConfig()
	if System.doesFileExist("ux0:data/MicroCHIP/options.cfg") then
		System.deleteFile("ux0:data/MicroCHIP/options.cfg")
	end
	local fd = System.openFile("ux0:data/MicroCHIP/options.cfg", FCREATE)
	System.writeFile(fd, string.char(bg_r), 1)
	System.writeFile(fd, string.char(bg_g), 1)
	System.writeFile(fd, string.char(bg_b), 1)
	System.writeFile(fd, string.char(nbg_r), 1)
	System.writeFile(fd, string.char(nbg_g), 1)
	System.writeFile(fd, string.char(nbg_b), 1)
	System.closeFile(fd)
	pushNotification("Config saved successfully!")
end

-- Load options config
function loadConfig()
	if System.doesFileExist("ux0:data/MicroCHIP/options.cfg") then
		local fd = System.openFile("ux0:data/MicroCHIP/options.cfg", FREAD)
		bg_r = string.byte(System.readFile(fd, 1))
		bg_g = string.byte(System.readFile(fd, 1))
		bg_b = string.byte(System.readFile(fd, 1))
		nbg_r = string.byte(System.readFile(fd, 1))
		nbg_g = string.byte(System.readFile(fd, 1))
		nbg_b = string.byte(System.readFile(fd, 1))
		System.closeFile(fd)
		bg_color = Color.new(bg_r, bg_g, bg_b)
		nbg_color = Color.new(nbg_r, nbg_g, nbg_b)
	end
end

-- Draw options menu
function drawOptionsMenu()
	Screen.clear()
	
	-- Background color tab	
	Graphics.fillRect(20, 940, 50, 220, white)
	Graphics.fillRect(21, 939, 51, 219, black)
	Graphics.fillRect(40, 80, 140, 180, white)
	Graphics.fillRect(41, 79, 141, 179, bg_color)
	if cursor > 0 and cursor < 4 then
		Graphics.fillRect(99, 867, 104 + (cursor - 1) * 40, 126 + (cursor - 1) * 40, cyan)
	end
	Graphics.fillRect(100, 101 + 3 * bg_r, 105, 125, red)
	Graphics.fillRect(100, 101 + 3 * bg_g, 145, 165, green)
	Graphics.fillRect(100, 101 + 3 * bg_b, 185, 205, blue)
	Graphics.debugPrint(40, 65, "Background color", white)
	
	-- Non background color tab
	Graphics.fillRect(20, 940, 240, 410, white)
	Graphics.fillRect(21, 939, 241, 409, black)
	Graphics.fillRect(40, 80, 330, 370, white)
	Graphics.fillRect(41, 79, 331, 369, nbg_color)
	if cursor > 3 and cursor < 7 then
		Graphics.fillRect(99, 867, 294 + (cursor - 4) * 40, 316 + (cursor - 4) * 40, cyan)
	end
	Graphics.fillRect(100, 101 + 3 * nbg_r, 295, 315, red)
	Graphics.fillRect(100, 101 + 3 * nbg_g, 335, 355, green)
	Graphics.fillRect(100, 101 + 3 * nbg_b, 375, 395, blue)
	Graphics.debugPrint(40, 255, "Sprites color", white)
	
	-- Menu entries
	if cursor == 7 then
		Graphics.debugPrint(20, 450, "Save changes", cyan)
	else
		Graphics.debugPrint(20, 450, "Save changes", white)
	end
	if cursor == 8 then
		Graphics.debugPrint(20, 470, "Discard changes", cyan)
	else
		Graphics.debugPrint(20, 470, "Discard changes", white)
	end
	
end

function handleOptionsKeys()
	pad = Controls.read()
	if Controls.check(pad, SCE_CTRL_UP) and not Controls.check(oldpad, SCE_CTRL_UP) then
		cursor = cursor - 1
		if cursor < 1 then
			cursor = 8
		end
	elseif Controls.check(pad, SCE_CTRL_DOWN) and not Controls.check(oldpad, SCE_CTRL_DOWN) then
		cursor = cursor + 1
		if cursor > 8 then
			cursor = 1
		end
	elseif Controls.check(pad, SCE_CTRL_CROSS) and not Controls.check(oldpad, SCE_CTRL_CROSS) then
		if cursor == 7 then
			state = old_state
			cursor = 1
			saveConfig()
		elseif cursor == 8 then
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
		executeOpcode()
		if updateScreen then
			Graphics.initBlend()
			drawScreen()
			Graphics.fillRect(0, 960, 0, 32, black)
			if state_timer > 0 then
				Graphics.debugPrint(0, 0, notification, yellow)
				state_timer = state_timer - 1
			end
			Graphics.termBlend()
			Screen.flip()
		end
		handleKeys()
	elseif state == 2 then -- Pause menu
		Graphics.initBlend()
		drawScreen()
		Graphics.fillRect(0, 960, 0, 32, black)
		if state_timer > 0 then
			Graphics.debugPrint(0, 0, notification, yellow)
			state_timer = state_timer - 1
		end
		drawPauseMenu()
		Graphics.termBlend()
		Screen.flip()
		handlePauseKeys()
	elseif state == 3 then -- Options Menu
		Graphics.initBlend()
		drawOptionsMenu()
		Graphics.termBlend()
		Screen.flip()
		handleOptionsKeys()
	end
	
end