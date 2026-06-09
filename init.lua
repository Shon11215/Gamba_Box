dofile_once("data/scripts/lib/utilities.lua")
dofile_once("mods/gamba_box/files/scripts/gamba_chest_tiers.lua")

local GAMBA_BOX_PATH = "mods/gamba_box/files/entities/gamba_box.xml"
local BOX_VISUAL_Y_OFFSET = -16
local DEFAULT_CHEST_TIER = 1
local HOLY_MOUNTAIN_SPAWN_CHECK_FRAMES = 60
local HOLY_MOUNTAIN_REROLL_TAG = "perk_reroll_machine"
local HOLY_MOUNTAIN_SPAWN_VERSION = 7
local HOLY_MOUNTAIN_COUNTER_GLOBAL = "GAMBA_BOX_HOLY_MOUNTAIN_COUNT"
local HOLY_MOUNTAIN_CHEST_X_OFFSET = -152
local HOLY_MOUNTAIN_FLOOR_SAMPLE_X_OFFSET = -105
local HOLY_MOUNTAIN_CHEST_Y_OFFSET = -29
local HOLY_MOUNTAIN_CHEST_RAY_START_Y_OFFSET = -48
local HOLY_MOUNTAIN_CHEST_RAY_END_Y_OFFSET = 96
local EXISTING_HOLY_MOUNTAIN_CHEST_RADIUS = 260

local HOLY_MOUNTAIN_CHEST_SEQUENCE = {
  { tier = 1, cost = 100 },
  { tier = 1, cost = 200 },
  { tier = 2, cost = 400 },
  { tier = 2, cost = 400 },
  { tier = 3, cost = 800 },
  { tier = 3, cost = 800 },
  { tier = 4, cost = 1600 },
}

-- Debug spawn is disabled for Workshop builds. Uncomment this block and the
-- matching block in OnWorldPostUpdate to spawn test chests with L + number.
--[[
local DEBUG_SPAWN_KEY_L = 15
local DEBUG_CHEST_TIER_KEYS = {
  { tier = 0, key = 39, keypad_key = 98 },
  { tier = 1, key = 30, keypad_key = 89 },
  { tier = 2, key = 31, keypad_key = 90 },
  { tier = 3, key = 32, keypad_key = 91 },
  { tier = 4, key = 33, keypad_key = 92 },
}
local DEBUG_CHEST_TIER = 0
]]

local function add_box_storage(entity_id, tag, value_type, value)
  local values = { _tags = tag }
  values[value_type] = value
  EntityAddComponent2(entity_id, "VariableStorageComponent", values)
end

local function get_chest_label(chest_tier, cost)
  return "Tier " .. tostring(chest_tier) .. " Gamba Box\nCost: " .. tostring(cost) .. " gold\nPress E to test your luck"
end

local function update_cost_display(entity_id, cost)
  local cost_display = EntityGetFirstComponentIncludingDisabled(entity_id, "SpriteComponent", "gamba_cost_display")
  if cost_display ~= nil then
    ComponentSetValue2(cost_display, "text", tostring(cost))
  end
end

local function configure_gamba_box(entity_id, chest_tier, cost_override)
  local tier_data = GAMBA_CHEST_TIERS[chest_tier] or GAMBA_CHEST_TIERS[DEFAULT_CHEST_TIER]
  local cost = cost_override or tier_data.base_cost

  add_box_storage(entity_id, "gamba_chest_tier", "value_int", chest_tier)
  add_box_storage(entity_id, "gamba_chest_cost", "value_int", cost)

  local interactable = EntityGetFirstComponentIncludingDisabled(entity_id, "InteractableComponent")
  if interactable ~= nil then
    ComponentSetValue2(interactable, "ui_text", get_chest_label(chest_tier, cost))
  end

  update_cost_display(entity_id, cost)
end

local function spawn_gamba_box(x, y, chest_tier, cost_override)
  local box = EntityLoad(GAMBA_BOX_PATH, x, y + BOX_VISUAL_Y_OFFSET)
  configure_gamba_box(box, chest_tier, cost_override)
end

--[[
local function spawn_gamba_box_at_mouse(x, y, chest_tier)
  local box = EntityLoad(GAMBA_BOX_PATH, x, y)
  configure_gamba_box(box, chest_tier)
end

local function get_held_debug_chest_tier()
  for _, tier_key in ipairs(DEBUG_CHEST_TIER_KEYS) do
    if InputIsKeyDown(tier_key.key) or InputIsKeyDown(tier_key.keypad_key) then
      return tier_key.tier
    end
  end

  return DEBUG_CHEST_TIER
end

local function get_just_pressed_debug_chest_tier()
  for _, tier_key in ipairs(DEBUG_CHEST_TIER_KEYS) do
    if InputIsKeyJustDown(tier_key.key) or InputIsKeyJustDown(tier_key.keypad_key) then
      return tier_key.tier
    end
  end

  return nil
end

local function spawn_debug_gamba_box(chest_tier)
  local x, y = DEBUG_GetMouseWorld()
  spawn_gamba_box_at_mouse(x, y, chest_tier)
  GamePrint("Debug: spawned tier " .. tostring(chest_tier) .. " Gamba Box.")
end
]]

local function get_next_holy_mountain_chest_data()
  local spawned_count = tonumber(GlobalsGetValue(HOLY_MOUNTAIN_COUNTER_GLOBAL, "0")) or 0
  local next_index = spawned_count + 1
  local chest_data = HOLY_MOUNTAIN_CHEST_SEQUENCE[next_index] or HOLY_MOUNTAIN_CHEST_SEQUENCE[#HOLY_MOUNTAIN_CHEST_SEQUENCE]

  GlobalsSetValue(HOLY_MOUNTAIN_COUNTER_GLOBAL, tostring(next_index))

  return chest_data
end

local function mark_next_holy_mountain_chest_used()
  get_next_holy_mountain_chest_data()
end

local function get_holy_mountain_spawn_key(reroll_x, reroll_y)
  local x_key = math.floor((reroll_x + 0.5) / 32)
  local y_key = math.floor((reroll_y + 0.5) / 32)

  return "GAMBA_BOX_HOLY_MOUNTAIN_SPAWNED_V" .. tostring(HOLY_MOUNTAIN_SPAWN_VERSION) .. "_" .. tostring(x_key) .. "_" .. tostring(y_key)
end

local function find_floor_y(x, y)
  local ray_start_y = y + HOLY_MOUNTAIN_CHEST_RAY_START_Y_OFFSET
  local ray_end_y = y + HOLY_MOUNTAIN_CHEST_RAY_END_Y_OFFSET
  local hit, _, hit_y = RaytracePlatforms(x, ray_start_y, x, ray_end_y)

  if hit then return hit_y end

  return y
end

local function holy_mountain_chest_already_exists(reroll_x, reroll_y)
  local nearby_boxes = EntityGetInRadiusWithTag(reroll_x, reroll_y, EXISTING_HOLY_MOUNTAIN_CHEST_RADIUS, "gamba_box")

  return nearby_boxes ~= nil and #nearby_boxes > 0
end

local function try_spawn_holy_mountain_gamba_boxes()
  if GameGetFrameNum() % HOLY_MOUNTAIN_SPAWN_CHECK_FRAMES ~= 0 then return end

  local rerolls = EntityGetWithTag(HOLY_MOUNTAIN_REROLL_TAG)
  if rerolls == nil then return end

  table.sort(rerolls, function(a, b)
    local _, ay = EntityGetTransform(a)
    local _, by = EntityGetTransform(b)

    return ay < by
  end)

  for _, reroll in ipairs(rerolls) do
    local reroll_x, reroll_y = EntityGetTransform(reroll)
    local spawn_key = get_holy_mountain_spawn_key(reroll_x, reroll_y)

    if GlobalsGetValue(spawn_key, "0") ~= "1" then
      if holy_mountain_chest_already_exists(reroll_x, reroll_y) then
        mark_next_holy_mountain_chest_used()
        GlobalsSetValue(spawn_key, "1")
      else
        local chest_x = reroll_x + HOLY_MOUNTAIN_CHEST_X_OFFSET
        local floor_sample_x = reroll_x + HOLY_MOUNTAIN_FLOOR_SAMPLE_X_OFFSET
        local chest_y = find_floor_y(floor_sample_x, reroll_y)
        local chest_data = get_next_holy_mountain_chest_data()

        spawn_gamba_box(chest_x, chest_y + HOLY_MOUNTAIN_CHEST_Y_OFFSET, chest_data.tier, chest_data.cost)
        GlobalsSetValue(spawn_key, "1")
      end
    end
  end
end

function OnWorldPostUpdate()
  try_spawn_holy_mountain_gamba_boxes()

  --[[
  if InputIsKeyJustDown(DEBUG_SPAWN_KEY_L) then
    spawn_debug_gamba_box(get_held_debug_chest_tier())
    return
  end

  if InputIsKeyDown(DEBUG_SPAWN_KEY_L) then
    local chest_tier = get_just_pressed_debug_chest_tier()
    if chest_tier ~= nil then
      spawn_debug_gamba_box(chest_tier)
    end
  end
  ]]
end
