

local addonName, addon = ...;

local playerUnitToken = "player";

local repTotals = {
    [0] = -21000,
    [1] = -12000,
    [2] = -6000,
    [3] = -3000,
    [4] = 0,
    [5] = 3000,
    [6] = 6000,
    [7] = 12000,
    [8] = 21000,
}

--Global namespace for the module so addons can interact with it
TbdAltManager_Reputations = {}

--Callback registry
TbdAltManager_Reputations.CallbackRegistry = CreateFromMixins(CallbackRegistryMixin)
TbdAltManager_Reputations.CallbackRegistry:OnLoad()
TbdAltManager_Reputations.CallbackRegistry:GenerateCallbackEvents({
    "Character_OnAdded",
    "Character_OnChanged",
    "Character_OnRemoved",

    "DataProvider_OnInitialized",
})



local characterDefaults = {
    uid = "",
    reputations = {}
}


--Main DataProvider for the module
local CharacterDataProvider = CreateFromMixins(DataProviderMixin)

function CharacterDataProvider:InsertCharacter(characterUID)

    local character = self:FindElementDataByPredicate(function(characterData)
        return (characterData.uid == characterUID)
    end)

    if not character then        
        local newCharacter = {}
        for k, v in pairs(characterDefaults) do
            newCharacter[k] = v
        end

        newCharacter.uid = characterUID

        self:Insert(newCharacter)
        TbdAltManager_Reputations.CallbackRegistry:TriggerEvent("Character_OnAdded")
    end
end

function CharacterDataProvider:FindCharacterByUID(characterUID)
    return self:FindElementDataByPredicate(function(character)
        return (character.uid == characterUID)
    end)
end









--Expose some api via the namespace
TbdAltManager_Reputations.Api = {}

function TbdAltManager_Reputations.Api.EnumerateCharacters()
    return CharacterDataProvider:EnumerateEntireRange()
end

function TbdAltManager_Reputations.Api.GetAllKnownReputationHeaders()

    local ret = {}

    local seen = {}

    local temp = {}

    for _, character in CharacterDataProvider:EnumerateEntireRange() do

        if character.reputations then

            for _, repData in ipairs(character.reputations) do
        
                local repType, headerName, headerID, factionName, factionID, currentStanding, currentReactionThreshold, nextReactionTreshold = strsplit(":", repData)
                
                if not seen[headerName] then
                    seen[headerName] = true
                    temp[tonumber(headerID)] = headerName
                end
            end
        end
    end

    for k, v in pairs(temp) do
        table.insert(ret, {
            headerID = k,
            headerName = v,
        })
    end

    return ret;
end

function TbdAltManager_Reputations.Api.GetReputationDataByHeaderID(headerID, characterUID, returnTable)

    headerID = string.format("%d", headerID)

    local ret = {}

    for _, character in CharacterDataProvider:EnumerateEntireRange() do

        if character.reputations and (characterUID == nil or (characterUID == character.uid)) then

            for _, repData in ipairs(character.reputations) do
        
                local repType, h_name, h_id, factionName, factionID, currentStanding, currentReactionThreshold, nextReactionTreshold, reaction = strsplit(":", repData)
                
                if headerID == h_id then

                    if returnTable then
                        -- table.insert(ret, {
                        --     characterUID = character.uid,
                        --     factionID = tonumber(factionID),
                        --     factionName = factionName,
                        --     reaction = tonumber(reaction),
                        --     currentStanding = tonumber(currentStanding),
                        --     currentReactionThreshold = tonumber(currentReactionThreshold),
                        --     nextReactionTreshold = tonumber(nextReactionTreshold),
                        -- })

                    else
                        table.insert(ret, {
                            characterUID = character.uid,
                            repDataString = repData,
                        })
                    end

                end

            end
        end
    end

    return ret
end








local eventsToRegister = {
    "ADDON_LOADED",
    "PLAYER_ENTERING_WORLD",
    "CHAT_MSG_COMBAT_FACTION_CHANGE",
}

--Frame to setup event listening
local ReputationsEventFrame = CreateFrame("Frame")
for _, event in ipairs(eventsToRegister) do
    ReputationsEventFrame:RegisterEvent(event)
end
ReputationsEventFrame:SetScript("OnEvent", function(self, event, ...)
    if self[event] then
        self[event](self, ...)
    end
end)

-- function ReputationsEventFrame:SetReputation(rep, value)
--     if self.character and self.character.reputations then
--         self.character.reputations[rep] = value;
--         TbdAltManager_Reputations.CallbackRegistry:TriggerEvent("Character_OnChanged", self.character)
--     end
-- end

function ReputationsEventFrame:SetReputations(reputations)
    if self.character and self.character.reputations then
        self.character.reputations = reputations
        TbdAltManager_Reputations.CallbackRegistry:TriggerEvent("Character_OnChanged", self.character)
    end
end

function ReputationsEventFrame:ADDON_LOADED(...)
    if (... == addonName) then
        if TbdAltManager_Reputations_SavedVariables == nil then

            CharacterDataProvider:Init({})
            TbdAltManager_Reputations_SavedVariables = CharacterDataProvider:GetCollection()
    
        else
    
            local data = TbdAltManager_Reputations_SavedVariables
            CharacterDataProvider:Init(data)
            TbdAltManager_Reputations_SavedVariables = CharacterDataProvider:GetCollection()
    
        end

        if not CharacterDataProvider:IsEmpty() then
            TbdAltManager_Reputations.CallbackRegistry:TriggerEvent("DataProvider_OnInitialized")
        end
    end

    if (... == "ViragDevTool") then
        ViragDevTool_AddData(TbdAltManager_Reputations_SavedVariables, addonName)
    end
end

function ReputationsEventFrame:PLAYER_ENTERING_WORLD()
    
    local account = "Default"
    local realm = GetRealmName()
    local name = UnitName(playerUnitToken)

    self.characterUID = string.format("%s.%s.%s", account, realm, name)

    CharacterDataProvider:InsertCharacter(self.characterUID)

    self.character = CharacterDataProvider:FindCharacterByUID(self.characterUID)

    local reputations = self:GetAllCurrentReputations()
    self:SetReputations(reputations)


end

function ReputationsEventFrame:CHAT_MSG_COMBAT_FACTION_CHANGE()

    --this should maybe look at updatign the specific rep?

    --for now just scan them all
    local reputations = self:GetAllCurrentReputations()
    self:SetReputations(reputations)
end

function ReputationsEventFrame:GetAllCurrentReputations()

    local reputations = {};

    local numFactions = C_Reputation.GetNumFactions()
    local factionIndex = 1
    local preHeader, categoryID;

    while (factionIndex <= numFactions) do
        local factionData = C_Reputation.GetFactionDataByIndex(factionIndex)

        if ViragDevTool_AddData then
            ViragDevTool_AddData(factionData, factionData.name)
        end
        
        if factionData.isHeader and not factionData.isHeaderWithRep then
            preHeader = factionData.name
            categoryID = factionData.factionID
            if factionData.isCollapsed then
                C_Reputation.ExpandFactionHeader(factionIndex)
                numFactions = C_Reputation.GetNumFactions()
            end
        end

        --[[
            Should this get renown data?
            https://warcraft.wiki.gg/wiki/API_C_MajorFactions.GetMajorFactionData

            This will only return data for factions where there is renown data. While on one hand this is a good idea
            It could be wise to just leave this in a simple form to catch faction names, IDs etc


            Note 2:
            Updating this to return data as expected to see in the character rep panel

            There are a few types of rep in the game, from what i can see the following is a general idea

            legacy
            the standard hated to exalted rep of old expansions

            renown
            the newer rep system, generally used on major factions

            friendships
            used on lesser factions

        ]]

        local progress = factionData.currentStanding - factionData.currentReactionThreshold
        local lowerBound = 0;
        local upperBound = factionData.nextReactionThreshold - factionData.currentReactionThreshold;
        local reaction = factionData.reaction;
        local repType = "legacy"

        local renownData = C_MajorFactions.GetMajorFactionData(factionData.factionID)
        if renownData and (renownData.name == factionData.name) then
            progress = renownData.renownReputationEarned
            lowerBound = 0
            upperBound = renownData.renownLevelThreshold
            reaction = renownData.renownLevel
            repType = "renown"
        end

        local friendshipData = C_GossipInfo.GetFriendshipReputation(factionData.factionID)
        if friendshipData and (friendshipData.name == factionData.name) then
            progress = friendshipData.standing - friendshipData.reactionThreshold
            lowerBound = 0
            upperBound = friendshipData.nextThreshold - friendshipData.reactionThreshold
            reaction = friendshipData.reaction
            repType = "friendship"
        end

        if factionData.name then
            if factionData.isHeader and factionData.isHeaderWithRep then
                local repData = string.format("%s:%s:%d:%s:%d:%d:%d:%d:%s", repType, preHeader, categoryID, factionData.name, factionData.factionID, progress, lowerBound, upperBound, reaction)
                table.insert(reputations, repData)
            else
                if not factionData.isHeader then
                    local repData = string.format("%s:%s:%d:%s:%d:%d:%d:%d:%s", repType, preHeader, categoryID, factionData.name, factionData.factionID, progress, lowerBound, upperBound, reaction)
                    table.insert(reputations, repData)
                end
            end

            -- local currentValue = factionData.currentStanding - factionData.currentReactionThreshold
            -- local barMaxValue = factionData.nextReactionThreshold - factionData.currentReactionThreshold

        end
        factionIndex = factionIndex + 1
    end

    return reputations;
end