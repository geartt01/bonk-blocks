--[[
	HammerPose: grip poses shared by HammerService (builds the weld) and
	HammerController (tweens the weld's C0 for the swing).

	Angles rotate the handle around the hand's X axis:
	positive = head tips backwards (wind-up), negative = forwards/down (smash).
]]

local Config = require(script.Parent:WaitForChild("Config"))

local HammerPose = {}

HammerPose.Idle = -25
HammerPose.Windup = 55
HammerPose.Smash = -118
HammerPose.SmashTime = 0.06
HammerPose.RecoverTime = 0.22

local R15_OFFSET = CFrame.new(0, -0.3, 0) -- RightHand
local R6_OFFSET = CFrame.new(0, -1, 0) -- bottom of "Right Arm"

function HammerPose.C0(isR6: boolean, angleDegrees: number): CFrame
	return (if isR6 then R6_OFFSET else R15_OFFSET) * CFrame.Angles(math.rad(angleDegrees), 0, 0)
end

-- Seconds from button press until the head lands (when the client sends SwingRequest)
function HammerPose.ImpactDelay(): number
	return Config.Hammer.Windup + HammerPose.SmashTime
end

return HammerPose
