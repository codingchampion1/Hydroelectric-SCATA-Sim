local TweenService = game:GetService("TweenService")

local button = script.Parent.InletFrame.ImageLabel

local negativeButton = button["1DecreaseTextButton"]
local stopButton = button["2StopTextButton"]
local positiveButton = button["3IncreaseTextButton"]
local genBreaker = button.Parent.Parent.GridBreakerFrame.ImageButton
local autoButton = button.Parent.Parent.AutoFrame.ImageButton

local screenGui = button.Parent.Parent.Parent

local volumeFrame = screenGui.InletInfoFrame.VolumeFrame.NumberTextLabel
local inletFrame = screenGui.InletInfoFrame.PercentFrame.NumberTextLabel
local genRpmFrame = screenGui.GeneratorInfoFrame["1GenRpmFrame"].NumberTextLabel
local genPowerFrame = screenGui.GeneratorInfoFrame["2PowerFrame"].NumberTextLabel
local gridInfoFrame = screenGui.GridInfoFrame.Frame.NumberTextLabel
local pointsInfoFrame = screenGui.PointsInfoFrame.Frame.NumberTextLabel

local syncroscopeFrame = screenGui.SyncroscopeInfoFrame.Frame
local spinner = syncroscopeFrame.SpinnerImageLabel

local genBreakerDebounce = true
local autoButtonDebounce = true

local status = 0 -- -1 = close, 0 = idle, 1 = open
local maxWaterFlow = 250 -- m^3
local gameTicks = 1 -- a variable for how long the simulation has ran, 0.1 seconds is a game tick

local WATER_INERTIA = 0.25   -- Fast
local GEN_INERTIA   = 0.025   -- Slowest
local ELEC_INERTIA = 0.125 -- Medium

local function calculateEqualPercentage(number)
	local result = maxWaterFlow * math.pow(20, (number/100)-1)
	if result < 12.5 then return 12.5 end
	if result > 250 then return 250 end
	return result
end

local function calculateValveFromEqualPercentage(targetFlow)
	if targetFlow <= 12.5 then return 0 end 
	if targetFlow >= 250 then return 100 end

	local logRatio = math.log(targetFlow / maxWaterFlow)
	local logBase = math.log(20)

	local inletPercent = ( (logRatio / logBase) + 1 ) * 100  

	return math.clamp(inletPercent, 0, 100)
end

local function calculateGenTorque(number)
	return number/0.441 -- 0.441 is cross-section of 0.75 meter pipe
end

local function calculateGenRpm(number)
	return (number*60)/(math.pi*0.75) -- assuming 0.75 meter pipe and low head, causing turbine diameter to be 0.75 meters.
end

local function calculateValvePercentage(newStatus)
	status = newStatus
	if status == 0 then
		button.Rotation = 0
	elseif status == 1 then
		button.Rotation = 40
	else -- status == -1
		button.Rotation = -40
	end
end

local function calculatePowerAfterSync(number)
	return (number*1000*9.81*30*0.85)/1000000 -- returns Power in MW
end

local function calculateIntakeFromPowerRequirement(targetPower)
	return (targetPower*1000000)/(0.85*9.81*30*1000) -- returns % value
end

local function calculateGridRequirements(waitInGameTicks)
	local modulo = waitInGameTicks % 1000
	if modulo ~= 0 then return end
	local requirement = math.random(10,59) -- megawatts
	return requirement :: number
end

local function wrapAngle(angle)
	while angle > 180 do
		angle -= 360
	end
	while angle < -180 do
		angle += 360
	end
	return angle
end

local function onClick(value)
	return function()
		calculateValvePercentage(value)
	end
end

local genRpm = 0
local function onClickGenBreaker()
	if genBreakerDebounce then return end
	if genBreaker.Rotation == -40 then genBreaker.Rotation = 40
		genRpm = 1800
		genRpmFrame.Text = tostring(genRpm)
		spinner.Rotation = 90
	else 
		genBreaker.Rotation = -40
		genBreakerDebounce = true
		genPowerFrame.Text = 0
	end
end

local function onClickAutoButton()
	if autoButtonDebounce then return end
	if autoButton.Rotation == -40 then 
		autoButton.Rotation = 40
	else 
		autoButton.Rotation = -40
	end
end

-- Connect the click event once
negativeButton.MouseButton1Click:Connect(onClick(-1))
stopButton.MouseButton1Click:Connect(onClick(0))
positiveButton.MouseButton1Click:Connect(onClick(1))

genBreaker.MouseButton1Click:Connect(onClickGenBreaker)
autoButton.MouseButton1Click:Connect(onClickAutoButton)

-- Update loop
local angleToBeWrapped = 90
local points = 0
local gridRequirement = math.random(10,59) :: number -- megawatts
local oldGridRequirement = gridRequirement
local equalPercentage = 0
local currentGenRpm = 0
local currentPower = 0
gridInfoFrame.Text = gridRequirement

while true do
	task.wait(0.1)
	local number = tonumber(inletFrame.Text)
	number += status*math.random()*0.3 -- arbitrary number for decimals and control
	inletFrame.Text = tostring(number)
	local targetFlow = calculateEqualPercentage(number) - 12.5
	equalPercentage += (targetFlow - equalPercentage) * WATER_INERTIA
	volumeFrame.Text = tostring(equalPercentage)
	if genBreaker.Rotation == -40 then -- Grid Breaker is off, assuming control of Generator
		autoButtonDebounce = true
		if number and number > 0 and number < 100 then
			-- Valid range: process normally
			local genTorque = calculateGenTorque(equalPercentage)
			genRpm = calculateGenRpm(genTorque)
			genRpm = genRpm + (genRpm - currentGenRpm) * GEN_INERTIA
			currentGenRpm = genRpm
			genRpmFrame.Text = tostring(genRpm)
		elseif number < 0 then
			-- Below minimum: cap to 0
			number = 0
			genRpmFrame.Text = tostring(number)
			inletFrame.Text = tostring(number)
		elseif number > 100 then
			-- Above maximum: cap to 100
			number = 100
			inletFrame.Text = tostring(number)
		else
			warn("Unexpected number: " .. tostring(number))
		end
	else -- Grid Breaker is on, power generation scripts here...
		if autoButton.Rotation == -40 then -- Auto is off, manual control 
			spinner.Rotation = 90
			autoButtonDebounce = false
			if number and number >= 0 and number < 100 then
				local targetPower = calculatePowerAfterSync(equalPercentage)
				currentPower += (targetPower - currentPower) * ELEC_INERTIA
				genPowerFrame.Text = tostring(currentPower)
				if gridRequirement then
					oldGridRequirement = gridRequirement
					gridInfoFrame.Text = tostring(gridRequirement)
				end
				gridRequirement = calculateGridRequirements(gameTicks) -- returns nil if modulo of gameticks and 1000 is not 0, else return requirement.
				-- Fixed: Check if power is within ±3 of requirement (inclusive range)
				if currentPower and oldGridRequirement then
					if math.abs(currentPower - oldGridRequirement) <= 3 then
						points += 1
						pointsInfoFrame.Text = tostring(points)
					end
				end	
				print(oldGridRequirement)
			elseif number < 0 then
				-- Below minimum: cap to 0 and process
				number = 0
				inletFrame.Text = tostring(number)
			elseif number > 100 then
				-- Above maximum: cap to 100 and process
				number = 100
				inletFrame.Text = tostring(number)
			else
				warn("Unexpected number: " .. tostring(number))
			end
		else -- autocontrol is on
			local intakeRequirement = calculateIntakeFromPowerRequirement(oldGridRequirement)
			local valveRequirement = calculateValveFromEqualPercentage(intakeRequirement)+4

			-- 1. Use a small tolerance (deadband) so it doesn't jitter
			local tolerance = 1 
			local difference = number - valveRequirement

			-- 2. If the difference is LARGER than tolerance, move the valve
			if math.abs(difference) > tolerance then
				if number > valveRequirement then 
					calculateValvePercentage(-1) -- Move toward Close
				elseif number < valveRequirement then 
					calculateValvePercentage(1)  -- Move toward Open
				end
			else
				-- 3. We are on target! Stop moving.
				calculateValvePercentage(0)
			end

			-- Ensure power is still updated on the UI while in Auto
			local targetPower = calculatePowerAfterSync(equalPercentage)
			currentPower += (targetPower - currentPower) * ELEC_INERTIA
			genPowerFrame.Text = tostring(currentPower)
			
			if gridRequirement then
				oldGridRequirement = gridRequirement
				gridInfoFrame.Text = tostring(gridRequirement)
			end
			gridRequirement = calculateGridRequirements(gameTicks) -- returns nil if modulo of gameticks and 1000 is not 0, else return requirement.
			if currentPower and oldGridRequirement then
				if math.abs(currentPower - oldGridRequirement) <= 3 then
					points += 1
					pointsInfoFrame.Text = tostring(points)
				end
			end
		end
	end

	-- Calculate distance after genRpm is updated
	local distance = math.abs(genRpm-1800)

	-- Check for sync condition (RPM close to 3600 and spinner centered)
	if distance < 50 and (angleToBeWrapped > 75 and angleToBeWrapped < 105) or (angleToBeWrapped < -75 and angleToBeWrapped > -105) then
		genBreakerDebounce = false
	else
		genBreakerDebounce = true
	end
	--print(angleToBeWrapped)
	-- Calculate syncroscope
	local targetRotation

	if distance <= 500 then
		if genRpm > 1800 then 
			targetRotation = spinner.Rotation + (distance/2)
		else 
			targetRotation = spinner.Rotation + (-distance/2)
		end
	else
		targetRotation = 90
	end
	
	angleToBeWrapped = wrapAngle(targetRotation)

	-- Create and play the tween
	local tweenInfo = TweenInfo.new(
		0.1, -- Duration (seconds)
		Enum.EasingStyle.Linear -- Easing style
	)

	local rotationTween = TweenService:Create(spinner, tweenInfo, {Rotation = targetRotation})
	if genBreaker.Rotation == -40 then
		rotationTween:Play()
	end
	gameTicks += 1
end
