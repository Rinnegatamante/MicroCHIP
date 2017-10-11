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

-- Colors
white = Color.new(255, 255, 255)
black = Color.new(0, 0, 0)
cyan = Color.new(0, 162, 232)
yellow = Color.new(255, 255, 0)
bg_color = black
non_bg_color = white

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
	local i = 0
	while i < 0x50 do
		ram[i] = fontset[i+1]
		i = i + 1
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
	local i = 0
	while i < rom_size do
		ram[i + 0x200] = string.byte(System.readFile(fd, 1))
		i = i + 1
	end
	System.closeFile(fd)
	in_game = true
	purgeScreen()
	cur_rom = roms[cursor]
	pushNotification("Rom " .. cur_rom .. " loaded successfully!")
end

-- Draw CHIP-8 display on screen
function drawScreen()
	if updateScreen then
		for y=0, 31 do
			for x=0, 63 do
				x_val = x * 15
				y_val = (y * 15) + 32
				if screen[bit32.lshift(y,6) + x] == 0 then
					Graphics.fillRect(x_val, x_val + 15, y_val, y_val + 15, bg_color)
				else
					Graphics.fillRect(x_val, x_val + 15, y_val, y_val + 15, non_bg_color)
				end
			end
		end
		updateScreen = false
	end
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
	if bit1 == 0x0 then
		if bit4 == 0x0 then
			clearScreen()
			PC = PC + 2
		elseif bit4 == 0xE then
			SP = SP - 1
			PC = stack[SP]
			PC = PC + 2
		else
			showError("ERROR: Unknown opcode: 0x" .. string.format("%x",opcode))
		end
	elseif bit1 == 0x1 then
		PC = bit32.band(opcode,0x0FFF)
	elseif bit1 == 0x2 then
		stack[SP] = PC
		SP = SP + 1
		PC = bit32.band(opcode,0x0FFF)
	elseif bit1 == 0x3 then
		val = bit32.band(opcode, 0x00FF)
		if V[bit2] == val then
			PC = PC + 4
		else
			PC = PC + 2
		end
	elseif bit1 == 0x4 then
		val = bit32.band(opcode, 0x00FF)
		if V[bit2] == val then
			PC = PC + 2
		else
			PC = PC + 4
		end
	elseif bit1 == 0x5 then
		if V[bit2] == V[bit3] then
			PC = PC + 4
		else
			PC = PC + 2
		end
	elseif bit1 == 0x6 then
		V[bit2] = bit32.band(opcode, 0x00FF)
		PC = PC + 2
	elseif bit1 == 0x7 then
		V[bit2] = V[bit2] + bit32.band(opcode, 0x00FF)
		PC = PC + 2
	elseif bit1 == 0x8 then
		if bit4 == 0x0 then
			V[bit2] = V[bit3]
			PC = PC + 2
		elseif bit4 == 0x1 then
			V[bit2] = bit32.bor(V[bit2],V[bit3])
			PC = PC + 2
		elseif bit4 == 0x2 then
			V[bit2] = bit32.band(V[bit2],V[bit3])
			PC = PC + 2
		elseif bit4 == 0x3 then
			V[bit2] = bit32.bxor(V[bit2],V[bit3])
			PC = PC + 2
		elseif bit4 == 0x4 then
			if V[bit3] > (0xFF - V[bit2]) then
				V[0xF] = 1
			else
				V[0xF] = 0
			end
			V[bit2] = V[bit2] + V[bit3]
			PC = PC + 2
		elseif bit4 == 0x5 then
			if V[bit3] > V[bit2] then
				V[0xF] = 0
			else
				V[0xF] = 1
			end
			V[bit2] = V[bit2] - V[bit3]
			PC = PC + 2
		elseif bit4 == 0x6 then
			V[0xF] = bit32.band(V[bit2],1)
			V[bit2] = bit32.rshift(V[bit2],1)
			PC = PC + 2
		elseif bit4 == 0x7 then
			if V[bit2] > V[bit3] then
				V[0xF] = 0
			else
				V[0xF] = 1
			end
			V[bit2] = V[bit3] - V[bit2]
			PC = PC + 2
		elseif bit4 == 0xE then
			V[0xF] = bit32.rshift(V[bit2],7)
			V[bit2] = bit32.lshift(V[bit2],1)
			PC = PC + 2
		else
			showError("ERROR: Unknown opcode: 0x" .. string.format("%x",opcode))
		end
	elseif bit1 == 0x9 then
		if V[bit2] == V[bit3] then
			PC = PC + 2
		else
			PC = PC + 4
		end
	elseif bit1 == 0xA then
		I = bit32.band(opcode,0x0FFF)
		PC = PC + 2
	elseif bit1 == 0xB then
		PC = V[0] + bit32.band(opcode, 0x0FFF)
	elseif bit1 == 0xC then
		V[bit2] = bit32.band(math.random() % 0xFF, bit32.band(opcode, 0x00FF))
		PC = PC + 2
	elseif bit1 == 0xD then
		local x = V[bit2]
		local y = V[bit3]
		local h = bit4
		V[0xF] = 0
		for yline=0, h-1 do
			if y + yline < 32 then
				pixel = ram[I + yline]
				for xline=0, 7 do
					if x + xline < 64 then
						if ((bit32.band(pixel,bit32.rshift(0x80, xline))) ~= 0) then
							pixel_idx = x + xline + (bit32.lshift(y + yline, 6))
							if screen[pixel_idx] == 1 then
								V[0xF] = 1
							end
							screen[pixel_idx] = bit32.bxor(screen[pixel_idx], 1)
						end
					end
				end
			end
		end
		updateScreen = true
		PC = PC + 2
	elseif bit1 == 0xE then
		if bit3 == 0x9 and bit4 == 0xE then
			if key[V[bit2]] then
				PC = PC + 4
			else
				PC = PC + 2
			end
		elseif bit3 == 0xA and bit4 == 0x1 then
			if key[V[bit2]] then
				PC = PC + 2
			else
				PC = PC + 4
			end
		else
			showError("ERROR: Unknown opcode: 0x" .. string.format("%x",opcode))
		end
	elseif bit1 == 0xF then
		if bit3 == 0x0 and bit4 == 0x7 then
			V[bit2] = delay_timer
			PC = PC + 2
		elseif bit3 == 0x0 and bit4 == 0xA then
			keyPress = false
			local key_idx = 0
			while key_idx < 16 do
				if key[key_idx] then
					V[bit2] = key_idx
					keyPress = true
				end
				key_idx = key_idx + 1
			end
			if not keyPress then
				return
			end
			PC = PC + 2
		elseif bit3 == 0x1 and bit4 == 0x5 then
			delay_timer = V[bit2]
			PC = PC + 2
		elseif bit3 == 0x1 and bit4 == 0x8 then
			sound_timer = V[bit2]
			PC = PC + 2
		elseif bit3 == 0x1 and bit4 == 0xE then
			if (I + V[bit2]) > 0xFFF then
				V[0xF] = 1
			else
				V[0xF] = 0
			end
			I = I + V[bit2]
			PC = PC + 2
		elseif bit3 == 0x2 and bit4 == 0x9 then
			I = V[bit2] * 5
			PC = PC + 2
		elseif bit3 == 0x3 and bit4 == 0x3 then
			ram[I] = V[bit2] / 100
			ram[I + 1] = (V[bit2] / 10) % 10
			ram[I + 2] = (V[bit2] % 100) % 10
			PC = PC + 2
		elseif bit3 == 0x5 and bit4 == 0x5 then
			for i=0, bit2 - 1 do
				ram[I + i] = V[i]
			end
			I = I + bit2 + 1
			PC = PC + 2
		elseif bit3 == 0x6 and bit4 == 0x5 then
			for i=0, bit2 - 1 do
				V[I] = ram[I + i]
				i = i + 1
			end
			I = I + bit2 + 1
			PC = PC + 2
		else
			showError("ERROR: Unknown opcode: 0x" .. string.format("%x",opcode))
		end
	else
		showError("ERROR: Unknown opcode: 0x" .. string.format("%x",opcode))
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
			loadSavestate(savFolder.."/"..roms[cursor]..".sav")
		end
		state = 1
	end
	oldpad = pad
end

-- Load a savestate
function loadSavestate(filename)
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
	PC_b1 = bit32.rshift(bit32.band(PC,0xFF00),8)
	PC_b2 = bit32.band(PC,0x00FF)
	System.writeFile(fd,string.char(PC_b1),1)
	System.writeFile(fd,string.char(PC_b2),1)
	I_b1 = bit32.rshift(bit32.band(I,0xFF00),8)
	I_b2 = bit32.band(I,0x00FF)
	System.writeFile(fd,string.char(I_b1),1)
	System.writeFile(fd,string.char(I_b2),1)
	System.writeFile(fd,string.char(SP),1)
	System.writeFile(fd,string.char(delay_timer),1)
	System.writeFile(fd,string.char(sound_timer),1)
	for i=0, 15 do
		System.writeFile(fd,string.char(V[i]),1)
	end
	for i=0, 15 do
		S_b1 = bit32.rshift(bit32.band(stack[i],0xFF00),8)
		S_b2 = bit32.band(stack[i],0x00FF)
		System.writeFile(fd,string.char(S_b1),1)
		System.writeFile(fd,string.char(S_b2),1)
	end
	for i=0, 0x800 do
		System.writeFile(fd,string.char(screen[i]),1)
	end
	for i=0, 0xFFF do
		System.writeFile(fd,string.char(ram[i]),1)
	end
	System.closeFile(fd)
end

-- Handle pause menu keys
function handlePauseKeys()
	t = Controls.readTouch()
	if t ~= nil and not (old_t ~= nil) then
		state = 1
		pushNotification("Game resumed")
	end
	old_t = t
	pad = Controls.read()
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
			pushNotification("Game resumed")
		elseif cursor == 2 then -- Save savestate
			saveSavestate()
			pushNotification("Savestate created successfully!")
		elseif cursor == 3 then -- Load savestate
			loadSavestate()
			pushNotification("Savestate loaded successfully!")
		elseif cursor == 4 then -- Options
			-- TODO
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

-- Initializing emulator
Sound.init()
beep = Sound.open("app0:beep.ogg")
getRomList()

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
		Graphics.initBlend()
		drawScreen()
		Graphics.fillRect(0, 960, 0, 32, black)
		if state_timer > 0 then
			Graphics.debugPrint(0, 0, notification, yellow)
			state_timer = state_timer - 1
		end
		Graphics.termBlend()
		Screen.flip()
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
	end
	
end