-- name:Ryu Hide and Seek
-- incompatible: gamemode
-- description: Tweaked Hide and Seek\n\nAll Seekers appear as a metal character.\n\nDuring the hiding phase, the seeker \nis slowed heavily and cannot tag.\n\nAfter the round has started,\nseekers are 20% faster.\n\nAll players return to the entrance\nwhen a round starts.\n\n\nOriginal Concept and Code by:\nSuper Keeberghrh\nand djoslin0\n\nModified by VianArdene\n\nFeel free to modify further for your own purposes under a different name.

-- constants
local ROUND_STATE_WAIT        = 0
local ROUND_STATE_ACTIVE      = 1
local ROUND_STATE_SEEKERS_WIN = 2
local ROUND_STATE_HIDERS_WIN  = 3
local ROUND_STATE_UNKNOWN_END = 4
local ROUND_STATE_HIDING = 5

-- globals
gGlobalSyncTable.roundState   = ROUND_STATE_WAIT -- current round state
gGlobalSyncTable.touchTag = false
gGlobalSyncTable.hiderCaps = false
gGlobalSyncTable.seekerCaps = false
gGlobalSyncTable.banKoopaShell = true
gGlobalSyncTable.disableBLJ = true
gGlobalSyncTable.displayTimer = 0 -- the displayed timer

-- variables
local sRoundTimer        = 0            -- the server's round timer
local sRoundHideTimeout = 30 * 30      -- 30 seconds to hide
local sRoundEndTimeout   = 3 * 60 * 30  -- three minutes
local sRoundGGs = 5 * 30
local numberOfSeekers = 2
local pauseExitTimer = 0
local canLeave = false
local sFlashingIndex = 0
local puX = 0
local puZ = 0
local np = gNetworkPlayers[0]
local cannonTimer = 0

-- server settings
gServerSettings.bubbleDeath = 0

--localize functions to improve performance
local
hook_chat_command, network_player_set_description, hook_on_sync_table_change, network_is_server,
hook_event, djui_popup_create, network_get_player_text_color_string, play_sound,
play_character_sound, djui_chat_message_create, djui_hud_set_resolution, djui_hud_set_font,
djui_hud_set_color, djui_hud_render_rect, djui_hud_print_text, djui_hud_get_screen_width, djui_hud_get_screen_height,
djui_hud_measure_text, tostring, warp_to_level, warp_to_start_level, warp_to_castle, stop_cap_music, dist_between_objects,
math_floor, math_ceil, table_insert, table_remove, set_camera_mode
=
hook_chat_command, network_player_set_description, hook_on_sync_table_change, network_is_server,
hook_event, djui_popup_create, network_get_player_text_color_string, play_sound,
play_character_sound, djui_chat_message_create, djui_hud_set_resolution, djui_hud_set_font,
djui_hud_set_color, djui_hud_render_rect, djui_hud_print_text, djui_hud_get_screen_width, djui_hud_get_screen_height,
djui_hud_measure_text, tostring, warp_to_level, warp_to_start_level, warp_to_castle, stop_cap_music, dist_between_objects,
math.floor, math.ceil, table.insert, table.remove, set_camera_mode

local function on_or_off(value)
    if value then return "enabled" end
    return "disabled"
end

local function server_update()
    -- increment timer
    sRoundTimer = sRoundTimer + 1
    gGlobalSyncTable.displayTimer = math_floor(sRoundTimer / 30)

    -- figure out state of the game
    local hasSeeker = false
    local hasHider = false
    local activePlayers = {}
    local connectedCount = 0
    for i = 0, (MAX_PLAYERS-1) do
        if gNetworkPlayers[i].connected then
            connectedCount = connectedCount + 1
            table_insert(activePlayers, gPlayerSyncTable[i])
            if gPlayerSyncTable[i].seeking then
                hasSeeker = true
            else
                hasHider = true
            end
        end
    end

    -- only change state if there are 2+ players
    if connectedCount < 2 then
        gGlobalSyncTable.roundState = ROUND_STATE_WAIT
        return
    elseif gGlobalSyncTable.roundState == ROUND_STATE_WAIT then
        gGlobalSyncTable.roundState = ROUND_STATE_UNKNOWN_END
        sRoundTimer = 0
        gGlobalSyncTable.displayTimer = 0
    end

    -- check to see if the round should end
    if gGlobalSyncTable.roundState == ROUND_STATE_ACTIVE then
        if not hasHider or not hasSeeker or sRoundTimer > sRoundEndTimeout then
            if not hasHider then
                gGlobalSyncTable.roundState = ROUND_STATE_SEEKERS_WIN
            elseif sRoundTimer > sRoundEndTimeout then
                gGlobalSyncTable.roundState = ROUND_STATE_HIDERS_WIN
            else
                gGlobalSyncTable.roundState = ROUND_STATE_UNKNOWN_END
            end
            sRoundTimer = 0
            gGlobalSyncTable.displayTimer = 0
        else
            return
        end
    end

    if (gGlobalSyncTable.roundState == ROUND_STATE_HIDERS_WIN or 
    gGlobalSyncTable.roundState == ROUND_STATE_SEEKERS_WIN or 
    gGlobalSyncTable.roundState == ROUND_STATE_UNKNOWN_END) then
        if sRoundTimer >= sRoundGGs then
            gGlobalSyncTable.roundState = ROUND_STATE_HIDING
            sRoundTimer = 0
                    -- reset seekers
        for i=0,(MAX_PLAYERS-1) do
            gPlayerSyncTable[i].seeking = false
        end
        hasSeeker = false

        end
        -- pick random seeker
        if not hasSeeker then
            local playerList = activePlayers
            
            if #activePlayers < 5 then
                local randNum = math.random(2)                
                local s = activePlayers[randNum]
                s.seeking = true
            else
                for i=1, numberOfSeekers do                
                    local randNum = math.random(#playerList)                
                    local s = activePlayers[randNum]
                    s.seeking = true
                    table_remove(activePlayers, randNum)
                end
            end
        end
    end

    -- start round
    if (gGlobalSyncTable.roundState == ROUND_STATE_HIDING) then
        if sRoundTimer >= sRoundHideTimeout then

            -- set round state
            gGlobalSyncTable.roundState = ROUND_STATE_ACTIVE
            sRoundTimer = 0
            gGlobalSyncTable.displayTimer = 0
        end
    end
end

local function update()
    pauseExitTimer = pauseExitTimer + 1

    if pauseExitTimer >= 1200 and not canLeave then
        canLeave = true
    end
    -- only allow the server to figure out the seeker
    if network_is_server() then
        server_update()
    end
end

local function screen_transition(trans)
    -- if the local player died next to a seeker, make them a seeker
    local s = gPlayerSyncTable[0]
    if not s.seeking then
        for i=1,(MAX_PLAYERS-1) do
            if gNetworkPlayers[i].connected and gNetworkPlayers[i].currLevelNum == np.currLevelNum and
                gNetworkPlayers[i].currActNum == np.currActNum and gNetworkPlayers[i].currAreaIndex == np.currAreaIndex
                and gPlayerSyncTable[i].seeking then

                local m = gMarioStates[0]
                local a = gMarioStates[i]

                if trans == WARP_TRANSITION_FADE_INTO_BOWSER or (m.floor.type == SURFACE_DEATH_PLANE and m.pos.y <= m.floorHeight + 2048) then
                    if dist_between_objects(m.marioObj, a.marioObj) <= 4000 and m.playerIndex == 0 then
                        s.seeking = true
                    end
                end
            end
        end
    end
end

--- @param m MarioState
local function mario_update(m)
    if (m.flags & MARIO_VANISH_CAP) ~= 0 then
        m.flags = m.flags & ~MARIO_VANISH_CAP --Always Remove Vanish Cap
        stop_cap_music()
    end

    if gGlobalSyncTable.disableBLJ and m.forwardVel <= -55 then
        m.forwardVel = -55
    end

    -- this code runs for all players
    local s = gPlayerSyncTable[m.playerIndex]

    if m.playerIndex == 0 and m.action == ACT_IN_CANNON and m.actionState == 2 then
        cannonTimer = cannonTimer + 1
        if cannonTimer >= 150 then -- 150 is 5 seconds
            m.forwardVel = 100 * coss(m.faceAngle.x)

            m.vel.y = 100 * sins(m.faceAngle.x)

            m.pos.x = m.pos.x + 120 * coss(m.faceAngle.x) * sins(m.faceAngle.y)
            m.pos.y = m.pos.y + 120 * sins(m.faceAngle.x)
            m.pos.z = m.pos.z + 120 * coss(m.faceAngle.x) * coss(m.faceAngle.y)

            play_sound(SOUND_ACTION_FLYING_FAST, m.marioObj.header.gfx.cameraToObject)
            play_sound(SOUND_OBJ_POUNDING_CANNON, m.marioObj.header.gfx.cameraToObject)

            m.marioObj.header.gfx.node.flags = m.marioObj.header.gfx.node.flags | GRAPH_RENDER_ACTIVE
            set_camera_mode(m.area.camera, m.area.camera.defMode, 1)

            set_mario_action(m, ACT_SHOT_FROM_CANNON, 0)
            queue_rumble_data_mario(m, 60, 70)
            m.usedObj.oAction = 2
            cannonTimer = 0
        end
    end

    -- remove caps
    if m.playerIndex == 0 or gGlobalSyncTable.roundState ~= ROUND_STATE_ACTIVE then
        if gGlobalSyncTable.seekerCaps and gPlayerSyncTable[m.playerIndex].seeking then
            m.flags = m.flags & ~MARIO_WING_CAP -- remove wing cap if seeking
            m.flags = m.flags & ~MARIO_METAL_CAP -- remove metal cap if seeking
            stop_cap_music()
            m.capTimer = 0
        elseif gGlobalSyncTable.hiderCaps and not gPlayerSyncTable[m.playerIndex].seeking then
            m.flags = m.flags & ~MARIO_WING_CAP -- remove wing cap if hiding
            m.flags = m.flags & ~MARIO_METAL_CAP -- remove metal cap if hiding
            stop_cap_music()
            m.capTimer = 0
        end
    end

    -- -- warp to the beninging
    -- if m.playerIndex == 0 then
    --     -- gPlayerSyncTable[m.playerIndex].seeking and
    --     if gGlobalSyncTable.displayTimer == 0 and gGlobalSyncTable.roundState == ROUND_STATE_ACTIVE then
    --         warp_to_start_level()
    --     end
    -- end

    -- display all seekers as metal
    if s.seeking then
        m.marioBodyState.modelState = m.marioBodyState.modelState | MODEL_STATE_METAL
    end

    -- pu prevention
    if m.pos.x >= 0 then
        puX = math_floor((8192 + m.pos.x) / 65536)
    else
        puX = math_ceil((-8192 + m.pos.x) / 65536)
    end
    if m.pos.z >= 0 then
        puZ = math_floor((8192 + m.pos.z) / 65536)
    else
        puZ = math_ceil((-8192 + m.pos.z) / 65536)
    end
    if puX ~= 0 or puZ ~= 0 then
        s.seeking = true
        warp_restart_level()
    end
end

---@param m MarioState
---@param action integer
local function before_set_mario_action(m, action)
    if m.playerIndex == 0 then
        if action == ACT_WAITING_FOR_DIALOG or action == ACT_READING_SIGN or action == ACT_READING_NPC_DIALOG or action == ACT_JUMBO_STAR_CUTSCENE then
            return 1
        elseif action == ACT_READING_AUTOMATIC_DIALOG and get_id_from_behavior(m.interactObj.behavior) ~= id_bhvDoor and get_id_from_behavior(m.interactObj.behavior) ~= id_bhvStarDoor then
            return 1
        elseif action == ACT_EXIT_LAND_SAVE_DIALOG then
            set_camera_mode(m.area.camera, m.area.camera.defMode, 1)
            return ACT_IDLE
        end
    end
end

--- @param m MarioState
local function before_phys_step(m)
    -- prevent physics from being altered when bubbled
    local s = gPlayerSyncTable[m.playerIndex]
    local hScale = 1.0

--gGlobalSyncTable.roundState == ROUND_STATE_WAIT and

    if gGlobalSyncTable.roundState == ROUND_STATE_HIDING and s.seeking == true  then
        hScale = hScale * .10        
    end

    if gGlobalSyncTable.roundState == ROUND_STATE_HIDING and s.seeking == false  then
        if m.action ~= ACT_BUBBLED and m.action ~= ACT_WATER_JUMP and m.action ~= ACT_HOLD_WATER_JUMP then
            hScale = hScale * 1.5
        end     
    end

    if gGlobalSyncTable.roundState == ROUND_STATE_ACTIVE and s.seeking == true  then
        if m.action ~= ACT_BUBBLED and m.action ~= ACT_WATER_JUMP and m.action ~= ACT_HOLD_WATER_JUMP then
            hScale = hScale * 1.25
        end
    end

    m.vel.x = m.vel.x * hScale
    m.vel.z = m.vel.z * hScale

end

local function on_pvp_attack(attacker, victim)
    -- this code runs when a player attacks another player
    local sAttacker = gPlayerSyncTable[attacker.playerIndex]
    local sVictim = gPlayerSyncTable[victim.playerIndex]

    -- only consider local player
    if victim.playerIndex ~= 0 then
        return
    end

    -- make victim a seeker
    if gGlobalSyncTable.roundState == ROUND_STATE_ACTIVE and sAttacker.seeking and not sVictim.seeking then    
        sVictim.seeking = true
    end
end

--- @param m MarioState
local function on_player_connected(m)
    -- start out as a seeker
    local s = gPlayerSyncTable[m.playerIndex]
    s.seeking = true
    network_player_set_description(gNetworkPlayers[m.playerIndex], "seeker", 255, 64, 64, 255)
end

local function hud_top_render()
    local seconds = 0
    local text = ""

    if gGlobalSyncTable.roundState == ROUND_STATE_WAIT then
        seconds = 60
        text = "Waiting for Players"
    elseif gGlobalSyncTable.roundState == ROUND_STATE_ACTIVE then
        seconds = math_floor(sRoundEndTimeout / 30 - gGlobalSyncTable.displayTimer)
        if seconds < 0 then seconds = 0 end
        text = "Seekers have " .. seconds .. " seconds left!"
    elseif gGlobalSyncTable.roundState == ROUND_STATE_HIDERS_WIN then
        text = "Congrats Hiders!"
    elseif gGlobalSyncTable.roundState == ROUND_STATE_SEEKERS_WIN then
        text = "Congrats Seekers!"
    elseif gGlobalSyncTable.roundState == ROUND_STATE_HIDING then
        seconds = math_floor(sRoundHideTimeout / 30 - gGlobalSyncTable.displayTimer)
        if seconds < 0 then seconds = 0 end
        text = "Seeker is released in " .. seconds .. " seconds"
    end

    local scale = 0.5

    -- get width of screen and text
    local screenWidth = djui_hud_get_screen_width()
    local width = djui_hud_measure_text(text) * scale

    local x = (screenWidth - width) * 0.5
    local y = 0

    local background = 0.0
    if seconds < 60 and gGlobalSyncTable.roundState == ROUND_STATE_ACTIVE then
        background = (math.sin(sFlashingIndex * 0.1) * 0.5 + 0.5) * 1
        background = background * background
        background = background * background
    end

    -- render top
    djui_hud_set_color(255 * background, 0, 0, 128)
    djui_hud_render_rect(x - 6, y, width + 12, 16)

    djui_hud_set_color(255, 255, 255, 255)
    djui_hud_print_text(text, x, y, scale)
end

local function hud_center_render()
    if gGlobalSyncTable.displayTimer > 3 then return end

    -- set text
    local text = ""
    if gGlobalSyncTable.roundState == ROUND_STATE_SEEKERS_WIN then
        text = "Seekers Win!"
    elseif gGlobalSyncTable.roundState == ROUND_STATE_HIDERS_WIN then
        text = "Hiders Win!"
    elseif gGlobalSyncTable.roundState == ROUND_STATE_HIDING then
        text = "Hide!"
    elseif gGlobalSyncTable.roundState == ROUND_STATE_ACTIVE then
        text = "The seeker is hunting!"
    else
        return
    end

    -- set scale
    local scale = 1

    -- get width of screen and text
    local screenWidth = djui_hud_get_screen_width()
    local screenHeight = djui_hud_get_screen_height()
    local width = djui_hud_measure_text(text) * scale
    local height = 32 * scale

    local x = (screenWidth - width) * 0.5
    local y = (screenHeight - height) * 0.25

    -- render
    djui_hud_set_color(0, 0, 0, 128)
    djui_hud_render_rect(x - 6 * scale, y, width + 12 * scale, height)

    djui_hud_set_color(255, 255, 255, 255)
    djui_hud_print_text(text, x, y, scale)
end

local function on_hud_render()
    -- render to N64 screen space, with the HUD font
    djui_hud_set_resolution(RESOLUTION_N64)
    djui_hud_set_font(FONT_NORMAL)

    hud_top_render()
    hud_center_render()

    sFlashingIndex = sFlashingIndex + 1
end

local function on_touch_tag_command()
    gGlobalSyncTable.touchTag = not gGlobalSyncTable.touchTag
    djui_chat_message_create("Touch tag: " .. on_or_off(gGlobalSyncTable.touchTag))
    return true
end

local function on_hider_cap_command()
    gGlobalSyncTable.hiderCaps = not gGlobalSyncTable.hiderCaps
    djui_chat_message_create("Hider Caps: " .. on_or_off(gGlobalSyncTable.hiderCaps))
    return true
end

local function on_seeker_cap_command()
    gGlobalSyncTable.seekerCaps = not gGlobalSyncTable.seekerCaps
    djui_chat_message_create("Seeker Caps: " .. on_or_off(gGlobalSyncTable.seekerCaps))
    return true
end

local function on_koopa_shell_command()
    gGlobalSyncTable.banKoopaShell = not gGlobalSyncTable.banKoopaShell
    djui_chat_message_create("Koopa Shells: " .. on_or_off(not gGlobalSyncTable.banKoopaShell))
    return true
end

local function on_blj_command()
    gGlobalSyncTable.disableBLJ = not gGlobalSyncTable.disableBLJ
    djui_chat_message_create("BLJS: " .. on_or_off(not gGlobalSyncTable.disableBLJ))
    return true
end

local function level_init()
    local s = gPlayerSyncTable[0]

    pauseExitTimer = 0
    canLeave = false

    if s.seeking then canLeave = true end
end

local function on_pause_exit()
    local s = gPlayerSyncTable[0]

    if not canLeave and not s.seeking then
        djui_popup_create(tostring(math_floor(30 - pauseExitTimer / 30)).." Seconds until you can leave!", 2)
        return false
    end
end

-----------------------
-- network callbacks --
-----------------------

local function on_round_state_changed()
    local rs = gGlobalSyncTable.roundState

    if rs == ROUND_STATE_ACTIVE then
        play_character_sound(gMarioStates[0], CHAR_SOUND_HERE_WE_GO)
    elseif rs == ROUND_STATE_SEEKERS_WIN then
        play_sound(SOUND_MENU_CLICK_CHANGE_VIEW, gMarioStates[0].marioObj.header.gfx.cameraToObject)
        
    elseif rs == ROUND_STATE_HIDERS_WIN then
        play_sound(SOUND_MENU_CLICK_CHANGE_VIEW, gMarioStates[0].marioObj.header.gfx.cameraToObject)

    elseif rs == ROUND_STATE_HIDING then
        
        local s = gPlayerSyncTable[0]

        warp_to_start_level()
    end
end

local function on_seeking_changed(tag, oldVal, newVal)
    local m = gMarioStates[tag]
    local npT = gNetworkPlayers[tag]

    -- play sound and create popup if became a seeker
    if newVal and not oldVal then
        play_sound(SOUND_OBJ_BOWSER_LAUGH, m.marioObj.header.gfx.cameraToObject)
        playerColor = network_get_player_text_color_string(m.playerIndex)

        local messages = {
            playerColor .. npT.name .. "\\#ffa0a0\\ is now a seeker!",
            playerColor .. npT.name .. "\\#ffa0a0\\ joined the dark side.",
            playerColor .. npT.name .. "\\#ffa0a0\\ got that dog in 'em!",
            playerColor .. npT.name .. "\\#ffa0a0\\ is coming for that ass!",
            playerColor .. npT.name .. "\\#ffa0a0\\: 'Aw shit, here we go again.'",
            playerColor .. npT.name .. "\\#ffa0a0\\ dropped their spaghetti.",
            playerColor .. npT.name .. "\\#ffa0a0\\ hears every door you open.",
            playerColor .. npT.name .. "\\#ffa0a0\\ will kill your wife, your son, & your infant daughter.",
            playerColor .. npT.name .. "\\#ffa0a0\\ forgot to turn the oven off.",
            playerColor .. npT.name .. "\\#ffa0a0\\ is rapidly approaching your location!",
            playerColor .. npT.name .. "\\#ffa0a0\\ HIT THE PENTAGON!",
            playerColor .. npT.name .. "\\#ffa0a0\\ is hidern't.",
            playerColor .. npT.name .. "\\#ffa0a0\\ regrets losing their glasses.",
            playerColor .. npT.name .. "\\#ffa0a0\\ is going to grape you!",
            playerColor .. npT.name .. "\\#ffa0a0\\ recognizes the bodies in the water!",
            playerColor .. npT.name .. "\\#ffa0a0\\ is looking for that DAMNED 4th Chaos Emerald!",
            playerColor .. npT.name .. "\\#ffa0a0\\ has been thinking about it and they're definitely back!",
            playerColor .. npT.name .. "\\#ffa0a0\\ got L + ratio'd",
            playerColor .. npT.name .. "\\#ffa0a0\\ definitely didn't tech that!",
            "\\#ffa0a0\\You fucked around and " .. playerColor .. npT.name .. "\\#ffa0a0\\ found out!",
            playerColor .. npT.name .. "\\#ffa0a0\\ knows the age of consent in your tri-state area!",
            playerColor .. npT.name .. "\\#ffa0a0\\ knows why the McDonalds ice cream machine is broken.",
            playerColor .. npT.name .. "\\#ffa0a0\\ jelqed too close to the sun!",
            playerColor .. npT.name .. "\\#ffa0a0\\ unironcally uses the term 'jelqing'!",
            "\\#ffa0a0\\You owe " .. playerColor .. npT.name .. "\\#ffa0a0\\ $5! Time to pay up!",
            playerColor .. npT.name .. "\\#ffa0a0\\ is shidding and fardding!",
            playerColor .. npT.name .. "\\#ffa0a0\\ was pressing buttons!",
            playerColor .. npT.name .. "\\#ffa0a0\\ wants to kiss boys!",
            "\\#ffa0a0\\We hope you don't mind if " .. playerColor .. npT.name .. "\\#ffa0a0\\ goes full Beast Mode!",
            playerColor .. npT.name .. "\\#ffa0a0\\ is going to take you down to Memphis!",
            playerColor .. npT.name .. "\\#ffa0a0\\ looks huge!"
        }

        local pick = math.random(#messages)      
        djui_popup_create(messages[pick], 2)

        sRoundTimer = 32
    end

    if newVal then
        network_player_set_description(npT, "seeker", 255, 64, 64, 255)
    else
        network_player_set_description(npT, "hider", 128, 128, 128, 255)
    end
end

local function check_touch_tag_allowed(i)
    if gMarioStates[i].action ~= ACT_TELEPORT_FADE_IN and gMarioStates[i].action ~= ACT_TELEPORT_FADE_OUT and gMarioStates[i].action ~= ACT_PULLING_DOOR and gMarioStates[i].action ~= ACT_PUSHING_DOOR and gMarioStates[i].action ~= ACT_WARP_DOOR_SPAWN and gMarioStates[i].action ~= ACT_ENTERING_STAR_DOOR and gMarioStates[i].action ~= ACT_STAR_DANCE_EXIT and gMarioStates[i].action ~= ACT_STAR_DANCE_NO_EXIT and gMarioStates[i].action ~= ACT_STAR_DANCE_WATER and gMarioStates[i].action ~= ACT_PANTING and gMarioStates[i].action ~= ACT_UNINITIALIZED and gMarioStates[i].action ~= ACT_WARP_DOOR_SPAWN then
        return true
    end

    return false
end

local function on_interact(m, obj, intee)
    if intee == INTERACT_PLAYER then

        if not gGlobalSyncTable.touchTag then
            return
        end

        if gGlobalSyncTable.roundState == ROUND_STATE_HIDING then
            return
        end

        if m ~= gMarioStates[0] then
            for i=0,(MAX_PLAYERS-1) do
                if gNetworkPlayers[i].connected and gNetworkPlayers[i].currAreaSyncValid then
                    if gPlayerSyncTable[m.playerIndex].seeking and not gPlayerSyncTable[i].seeking and obj == gMarioStates[i].marioObj and check_touch_tag_allowed(i)  then
                        gPlayerSyncTable[i].seeking = true

                        network_player_set_description(gNetworkPlayers[i], "seeker", 255, 64, 64, 255)
                    end
                end
            end
        end
    end
end

local function allow_interact(_, _, intee)
    if intee == INTERACT_KOOPA_SHELL and gGlobalSyncTable.banKoopaShell then
        return false
    end
end

function allow_pvp_attack(m1, m2)
    local s1 = gPlayerSyncTable[m1.playerIndex]
    local s2 = gPlayerSyncTable[m2.playerIndex]
    if s1.seeking == s2.seeking then
        return false
    end
    return true
end

gLevelValues.disableActs = true

-----------
-- hooks --
-----------

hook_event(HOOK_UPDATE, update)
hook_event(HOOK_ON_SCREEN_TRANSITION, screen_transition)
hook_event(HOOK_BEFORE_SET_MARIO_ACTION, before_set_mario_action)
hook_event(HOOK_MARIO_UPDATE, mario_update)
hook_event(HOOK_BEFORE_PHYS_STEP, before_phys_step)
hook_event(HOOK_ALLOW_PVP_ATTACK, allow_pvp_attack)
hook_event(HOOK_ON_PVP_ATTACK, on_pvp_attack)
hook_event(HOOK_ON_PLAYER_CONNECTED, on_player_connected)
hook_event(HOOK_ON_HUD_RENDER, on_hud_render)
hook_event(HOOK_ON_LEVEL_INIT, level_init)
hook_event(HOOK_ON_PAUSE_EXIT, on_pause_exit) -- timer
hook_event(HOOK_ON_INTERACT, on_interact)
hook_event(HOOK_ALLOW_INTERACT, allow_interact)
hook_event(HOOK_USE_ACT_SELECT, function () return false end)

if network_is_server() then
   hook_chat_command("touch-to-tag", "Turn touch tag on or off", on_touch_tag_command)
   hook_chat_command("hiders-caps", "Turn caps for hiders on or off", on_hider_cap_command)
   hook_chat_command("seekers-caps", "Turn caps for seekers on or off", on_seeker_cap_command)
   hook_chat_command("koopa-shell", "Turn the koopa shell on or off", on_koopa_shell_command)
   hook_chat_command("bljs", "Turn bljs on or off", on_blj_command)
end

-- call functions when certain sync table values change
hook_on_sync_table_change(gGlobalSyncTable, "roundState", 0, on_round_state_changed)

for i = 0, (MAX_PLAYERS - 1) do
    gPlayerSyncTable[i].seeking = true
    hook_on_sync_table_change(gPlayerSyncTable[i], "seeking", i, on_seeking_changed)
    network_player_set_description(gNetworkPlayers[i], "seeker", 255, 64, 64, 255)
end

_G.HideAndSeek = {
    is_player_seeker = function (playerIndex)
        return gPlayerSyncTable[playerIndex].seeking
    end,

    set_player_seeker = function (playerIndex, seeking)
        gPlayerSyncTable[playerIndex].seeking = seeking
    end,
}
