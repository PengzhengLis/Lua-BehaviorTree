
local AITypes = {
    FLT_MAX = 3.402823466e+38,
    INT_MAX = 2147483647,
    INT_MIN = -2147483648,
}

AITypes.FAISystem = {
    InvalidRotation = { Pitch = AITypes.FLT_MAX, Yaw = AITypes.FLT_MAX, Roll = AITypes.FLT_MAX },
    InvalidLocation = { X = AITypes.FLT_MAX, Y = AITypes.FLT_MAX, Z = AITypes.FLT_MAX },
    InvalidDirection = { X = 0.0, Y = 0.0, Z = 0.0 },
    InvalidRange = -1.0,
    InfiniteInterval = -AITypes.FLT_MAX,
    InvalidUnsignedID = AITypes.INT_MAX,
}

function AITypes.FAISystem.IsValidLocation(TestLocation)
    return -AITypes.InvalidLocation.X < TestLocation.X and TestLocation.X < AITypes.InvalidLocation.X
    and -AITypes.InvalidLocation.Y < TestLocation.Y and TestLocation.Y < AITypes.InvalidLocation.Y
    and -AITypes.InvalidLocation.Z < TestLocation.Z and TestLocation.Z < AITypes.InvalidLocation.Z;
end

function AITypes.FAISystem.IsZero(TestVector)
    return TestVector.X == 0.0 and TestVector.Y == 0.0 and TestVector.Z == 0.0
end

function AITypes.FAISystem.IsValidDirection(TestVector)
	return AITypes.FAISystem.IsValidLocation(TestVector) and not IsZero(TestVector);
end

function AITypes.FAISystem.IsValidRotation(TestRotation)
    return TestRotation.X ~= AITypes.FAISystem.InvalidRotation.X or
    TestRotation.Y ~= AITypes.FAISystem.InvalidRotation.Y or 
    TestRotation.Z ~= AITypes.FAISystem.InvalidRotation.Z
end

AITypes.FAIDistanceType = {
    Distance3D = 0,
    Distance2D = 1,
    DistanceZ = 2,
}

return AITypes