if dofile_once ~= nil then
  dofile_once("data/scripts/lib/utilities.lua")
end

local SLOT_COUNT = 5
local SLOT_WIDTH = 44
local SLOT_HEIGHT = 18
local SLOT_GAP = 3
local DEAD_ZONE_SLOTS = 2
local ROLL_EASE_POWER = 6
local SEPARATOR_IMAGE = "data/ui_gfx/1px_white.png"
local SEPARATOR_ALPHA = 0.42
local WORLD_Y_OFFSET = -52
local REWARD_X_OFFSET = 34
local REWARD_Y_OFFSET = -12
local SPELL_REWARD_SPACING = 12
local GAMBA_WAND_SPAWNED_TAG = "gamba_wand_spawned"
local GAMBA_WAND_THROWN_TAG = "gamba_wand_thrown"
local GAMBA_WAND_STORAGE_TAG = "gamba_wand_reward"
local WAND_CLEAR_RADIUS = 28
local WAND_THROW_START_OFFSET = 8
local WAND_THROW_FORCE_MIN = 32
local WAND_THROW_FORCE_MAX = 75
local WAND_THROW_TORQUE = 0.15
local WAND_SPAWN_JITTER_MIN = -4
local WAND_SPAWN_JITTER_MAX = 4
local WINNING_SLOT_INDEX = 3
local GUI_ID_BASE = 8000
local GUI_ID_STRIDE = 100
local END_HOLD_FRAMES = 85

local function gui_id(entity_id, local_id)
  return GUI_ID_BASE + (entity_id * GUI_ID_STRIDE) + local_id
end

local function frame_gui_id(entity_id, local_id)
  return gui_id(entity_id, (GameGetFrameNum() % 1000) + (local_id * 1000))
end

local function get_storage(entity_id, tag)
  return EntityGetFirstComponentIncludingDisabled(entity_id, "VariableStorageComponent", tag)
end

local function get_string(entity_id, tag, default)
  local comp = get_storage(entity_id, tag)
  if comp == nil then return default end
  return ComponentGetValue2(comp, "value_string")
end

local function get_int(entity_id, tag, default)
  local comp = get_storage(entity_id, tag)
  if comp == nil then return default end
  return ComponentGetValue2(comp, "value_int")
end

local function get_float(entity_id, tag, default)
  local comp = get_storage(entity_id, tag)
  if comp == nil then return default end
  return ComponentGetValue2(comp, "value_float")
end

local function add_int_storage(entity_id, tag, value)
  EntityAddComponent2(entity_id, "VariableStorageComponent", {
    _tags = tag,
    value_int = value,
  })
end

local function is_world_entity(entity_id)
  return EntityGetIsAlive(entity_id) and EntityGetRootEntity(entity_id) == entity_id
end

local function is_gamba_spawned_wand(entity_id)
  if not is_world_entity(entity_id) then return false end
  if EntityHasTag(entity_id, GAMBA_WAND_THROWN_TAG) then return false end
  if EntityHasTag(entity_id, GAMBA_WAND_SPAWNED_TAG) then return true end

  return get_storage(entity_id, GAMBA_WAND_STORAGE_TAG) ~= nil
end

local function set_wand_dropped_state(wand_entity)
  local item = EntityGetFirstComponentIncludingDisabled(wand_entity, "ItemComponent")
  if item ~= nil then
    EntitySetComponentIsEnabled(wand_entity, item, true)
    ComponentSetValue2(item, "play_hover_animation", false)
    ComponentSetValue2(item, "is_pickable", true)
  end

  local simple_physics = EntityGetFirstComponentIncludingDisabled(wand_entity, "SimplePhysicsComponent")
  if simple_physics ~= nil then
    EntitySetComponentIsEnabled(wand_entity, simple_physics, true)
  end

  local velocity = EntityGetFirstComponentIncludingDisabled(wand_entity, "VelocityComponent")
  if velocity ~= nil then
    EntitySetComponentIsEnabled(wand_entity, velocity, true)
    ComponentSetValueVector2(velocity, "mVelocity", 0, 0)
  end
end

local function throw_spawned_gamba_wand(wand_entity)
  if not is_gamba_spawned_wand(wand_entity) then return end

  local x, y = EntityGetTransform(wand_entity)
  local direction = Random(0, 1)
  if direction == 0 then direction = -1 end

  local thrown_x = x + (WAND_THROW_START_OFFSET * direction)
  local force_x = Random(WAND_THROW_FORCE_MIN, WAND_THROW_FORCE_MAX) * direction

  EntityRemoveTag(wand_entity, GAMBA_WAND_SPAWNED_TAG)
  EntityAddTag(wand_entity, GAMBA_WAND_THROWN_TAG)
  set_wand_dropped_state(wand_entity)
  EntitySetTransform(wand_entity, thrown_x, y)
  PhysicsApplyForce(wand_entity, force_x, 0)
  PhysicsApplyTorque(wand_entity, WAND_THROW_TORQUE)
end

local function clear_wand_spawn_spot(x, y)
  local spawned_wands = EntityGetInRadiusWithTag(x, y, WAND_CLEAR_RADIUS, GAMBA_WAND_SPAWNED_TAG)
  if spawned_wands ~= nil then
    for _, wand_entity in ipairs(spawned_wands) do
      throw_spawned_gamba_wand(wand_entity)
    end
  end

  local nearby_items = EntityGetInRadiusWithTag(x, y, WAND_CLEAR_RADIUS, "item")
  if nearby_items == nil then return end

  for _, item_entity in ipairs(nearby_items) do
    throw_spawned_gamba_wand(item_entity)
  end
end

local function tag_spawned_gamba_wand(wand_entity)
  EntityAddTag(wand_entity, GAMBA_WAND_SPAWNED_TAG)
  add_int_storage(wand_entity, GAMBA_WAND_STORAGE_TAG, 1)
end

local function load_wand_at_reward_spot(wand_path, x, y)
  local spawn_x = x + Random(WAND_SPAWN_JITTER_MIN, WAND_SPAWN_JITTER_MAX)
  local spawn_y = y + Random(WAND_SPAWN_JITTER_MIN, WAND_SPAWN_JITTER_MAX)

  return EntityLoad(wand_path, spawn_x, spawn_y)
end

local function split(value)
  local result = {}
  for item in string.gmatch(value or "", "([^|]+)") do
    table.insert(result, item)
  end
  return result
end

local function trim_label(label)
  if label == nil then return "" end
  if #label <= 10 then return label end
  return string.sub(label, 1, 9) .. "."
end

local function get_rarity_color(rarity)
  if rarity == "unique" then
    return 1.0, 0.78, 0.12
  end

  if rarity == "legendary" then
    return 1.0, 0.12, 0.08
  end

  if rarity == "epic" then
    return 0.75, 0.25, 0.9
  end

  if rarity == "rare" then
    return 0.2, 0.45, 1.0
  end

  if rarity == "uncommon" then
    return 0.1, 0.95, 0.35
  end

  return 0.55, 0.55, 0.55
end

local function round(value)
  return math.floor(value + 0.5)
end

local function draw_line(gui, entity_id, local_id, x, y, width, height)
  if width <= 0 or height <= 0 then return end

  GuiOptionsAddForNextWidget(gui, GUI_OPTION.NoPositionTween)
  GuiColorSetForNextWidget(gui, 0.9, 0.82, 0.65, SEPARATOR_ALPHA)
  GuiImage(gui, frame_gui_id(entity_id, local_id), x, y, SEPARATOR_IMAGE, SEPARATOR_ALPHA, width, height)
end

local function draw_slot_edges(gui, entity_id, slot_index, slot_x, slot_y, slot_width)
  local line_id = 300 + (slot_index * 10)

  draw_line(gui, entity_id, line_id, slot_x, slot_y, 1, SLOT_HEIGHT)
  draw_line(gui, entity_id, line_id + 1, slot_x + slot_width - 1, slot_y, 1, SLOT_HEIGHT)
  draw_line(gui, entity_id, line_id + 2, slot_x, slot_y, slot_width, 1)
  draw_line(gui, entity_id, line_id + 3, slot_x, slot_y + SLOT_HEIGHT - 1, slot_width, 1)
end

local function world_to_screen(gui, world_x, world_y)
  local camera_x, camera_y = GameGetCameraPos()
  local _, _, camera_w, camera_h = GameGetCameraBounds()
  local screen_w, screen_h = GuiGetScreenDimensions(gui)

  local screen_x = (screen_w * 0.5) + ((world_x - camera_x) / camera_w) * screen_w
  local screen_y = (screen_h * 0.5) + ((world_y - camera_y) / camera_h) * screen_h

  return screen_x, screen_y
end

local function get_roll_world_position(entity_id)
  local x, y = EntityGetTransform(entity_id)
  return get_float(entity_id, "roll_world_x", x), get_float(entity_id, "roll_world_y", y)
end

local function spawn_final_reward(entity_id, x, y)
  local reward_type = get_string(entity_id, "reward_type", "")
  local reward_title = get_string(entity_id, "reward_title", "GAMBA BOX")
  local reward_description = get_string(entity_id, "reward_description", "")
  local box_entity = get_int(entity_id, "box_entity", 0)

  EntityLoad("data/entities/particles/image_emitters/chest_effect.xml", x, y)

  if reward_type == "spell" then
    local spell_ids = split(get_string(entity_id, "spell_ids", ""))
    for i, spell_id in ipairs(spell_ids) do
      if spell_id ~= "" then
        local offset_x = REWARD_X_OFFSET + ((i - 1) * SPELL_REWARD_SPACING)
        CreateItemActionEntity(spell_id, x + offset_x, y + REWARD_Y_OFFSET)
      end
    end
  elseif reward_type == "wand" then
    local wand_path = get_string(entity_id, "wand_path", "")
    if wand_path ~= "" then
      local wand_x = x + REWARD_X_OFFSET
      local wand_y = y + REWARD_Y_OFFSET

      clear_wand_spawn_spot(wand_x, wand_y)

      local wand_entity = load_wand_at_reward_spot(wand_path, wand_x, wand_y)
      if wand_entity ~= nil and wand_entity ~= 0 then
        tag_spawned_gamba_wand(wand_entity)
      end
    end
  end

  GamePrintImportant(reward_title, reward_description)
end

local function finish_box_roll(box_entity)
  local rolling_storage = EntityGetFirstComponentIncludingDisabled(box_entity, "VariableStorageComponent", "gamba_rolling")
  if rolling_storage ~= nil then
    EntityRemoveComponent(box_entity, rolling_storage)
  end

  local cost_display = EntityGetFirstComponentIncludingDisabled(box_entity, "SpriteComponent", "gamba_cost_display")
  if cost_display ~= nil then
    EntitySetComponentIsEnabled(box_entity, cost_display, true)
  end

  local interactable = EntityGetFirstComponentIncludingDisabled(box_entity, "InteractableComponent")
  if interactable ~= nil then
    EntitySetComponentIsEnabled(box_entity, interactable, true)
  end
end

local function draw_roll(gui, entity_id, elapsed, duration)
  local x, y = get_roll_world_position(entity_id)
  local labels = split(get_string(entity_id, "slot_labels", ""))
  local rarities = split(get_string(entity_id, "slot_rarities", ""))
  if #labels < SLOT_COUNT then return end

  local final_index = get_int(entity_id, "final_index", #labels)
  local final_start = math.max(1, final_index - WINNING_SLOT_INDEX + 1)
  local roll_frames = math.max(1, duration - END_HOLD_FRAMES)
  local progress = math.min(1, elapsed / roll_frames)
  local stop_offset = get_float(entity_id, "roll_stop_offset", 0)
  local slot_pitch = SLOT_WIDTH + SLOT_GAP
  local target_scroll_position = final_start + (stop_offset / slot_pitch)
  local eased = 1 - ((1 - progress) ^ ROLL_EASE_POWER)
  local scroll_position = 1 + ((target_scroll_position - 1) * eased)

  if elapsed >= roll_frames then
    scroll_position = target_scroll_position
  end

  local screen_x, screen_y = world_to_screen(gui, x, y + WORLD_Y_OFFSET)
  local total_width = (SLOT_WIDTH * SLOT_COUNT) + (SLOT_GAP * (SLOT_COUNT - 1))
  local base_x = round(screen_x - (total_width * 0.5))
  local base_y = round(screen_y)
  local first_drawn_slot = math.max(1, math.floor(scroll_position) - DEAD_ZONE_SLOTS)
  local last_drawn_slot = math.min(#labels, math.ceil(scroll_position) + SLOT_COUNT + DEAD_ZONE_SLOTS)
  local visible_min_x = base_x
  local visible_max_x = base_x + total_width

  GuiZSet(gui, -20)

  for slot_index = first_drawn_slot, last_drawn_slot do
    local label = trim_label(labels[slot_index] or "")
    local rarity = rarities[slot_index] or "common"
    local r, g, b = get_rarity_color(rarity)
    local raw_slot_x = base_x + ((slot_index - scroll_position) * slot_pitch)
    local slot_x = math.max(raw_slot_x, visible_min_x)
    local slot_right = math.min(raw_slot_x + SLOT_WIDTH, visible_max_x)
    local slot_width = slot_right - slot_x
    local is_full_slot = raw_slot_x >= visible_min_x and (raw_slot_x + SLOT_WIDTH) <= visible_max_x
    local slot_alpha = 0.82

    if slot_width > 0 then
      GuiOptionsAddForNextWidget(gui, GUI_OPTION.NoPositionTween)
      GuiColorSetForNextWidget(gui, r, g, b, 0.95)
      GuiImageNinePiece(gui, frame_gui_id(entity_id, slot_index), slot_x, base_y, slot_width, SLOT_HEIGHT, slot_alpha)

      draw_slot_edges(gui, entity_id, slot_index, slot_x, base_y, slot_width)

      if is_full_slot then
        GuiOptionsAddForNextWidget(gui, GUI_OPTION.NoPositionTween)
        GuiColorSetForNextWidget(gui, r, g, b, 1)
        GuiText(gui, round(raw_slot_x + 3), base_y + 6, label, 0.62)
      end
    end
  end

  local pointer_x = base_x + ((WINNING_SLOT_INDEX - 1) * (SLOT_WIDTH + SLOT_GAP)) + (SLOT_WIDTH * 0.5) - 2
  GuiOptionsAddForNextWidget(gui, GUI_OPTION.NoPositionTween)
  GuiColorSetForNextWidget(gui, 0.1, 0.65, 1, 1)
  GuiText(gui, pointer_x, base_y + SLOT_HEIGHT + 1, "^", 1)
end

local entity_id = GetUpdatedEntityID()
local start_frame = get_int(entity_id, "start_frame", GameGetFrameNum())
local duration = get_int(entity_id, "duration_frames", 120)
local elapsed = GameGetFrameNum() - start_frame

GAMBA_ROLL_GUIS = GAMBA_ROLL_GUIS or {}
GAMBA_ROLL_GUIS[entity_id] = GAMBA_ROLL_GUIS[entity_id] or GuiCreate()

local gui = GAMBA_ROLL_GUIS[entity_id]
GuiStartFrame(gui)
draw_roll(gui, entity_id, elapsed, duration)

if elapsed >= duration then
  local x, y = EntityGetTransform(entity_id)
  spawn_final_reward(entity_id, x, y)

  local box_entity = get_int(entity_id, "box_entity", 0)
  if box_entity ~= 0 then
    finish_box_roll(box_entity)
  end

  GuiDestroy(gui)
  GAMBA_ROLL_GUIS[entity_id] = nil
  EntityKill(entity_id)
end
