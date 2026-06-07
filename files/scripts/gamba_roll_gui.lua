local SLOT_COUNT = 5
local SLOT_WIDTH = 44
local SLOT_HEIGHT = 18
local SLOT_GAP = 3
local WORLD_Y_OFFSET = -52
local REWARD_X_OFFSET = 34
local REWARD_Y_OFFSET = -12
local SPELL_REWARD_SPACING = 12
local WINNING_SLOT_INDEX = 3
local GUI_ID_BASE = 8000
local GUI_ID_STRIDE = 100
local END_HOLD_FRAMES = 105

local function gui_id(entity_id, local_id)
  return GUI_ID_BASE + (entity_id * GUI_ID_STRIDE) + local_id
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
      EntityLoad(wand_path, x + REWARD_X_OFFSET, y + REWARD_Y_OFFSET)
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
  local eased = 1 - ((1 - progress) * (1 - progress) * (1 - progress) * (1 - progress))
  local start_index = 1 + math.floor((final_start - 1) * eased)

  if elapsed >= roll_frames then
    start_index = final_start
  end

  local screen_x, screen_y = world_to_screen(gui, x, y + WORLD_Y_OFFSET)
  local total_width = (SLOT_WIDTH * SLOT_COUNT) + (SLOT_GAP * (SLOT_COUNT - 1))
  local base_x = round(screen_x - (total_width * 0.5))
  local base_y = round(screen_y)

  GuiZSet(gui, -20)

  for i = 1, SLOT_COUNT do
    local slot_index = start_index + i - 1
    local label = trim_label(labels[slot_index] or "")
    local rarity = rarities[slot_index] or "common"
    local r, g, b = get_rarity_color(rarity)
    local slot_x = base_x + ((i - 1) * (SLOT_WIDTH + SLOT_GAP))
    local is_winning_slot = (i == WINNING_SLOT_INDEX) and (elapsed >= roll_frames)
    local slot_alpha = 0.82

    if is_winning_slot then
      local blink = math.abs(math.sin(elapsed * 0.45))
      slot_alpha = 0.78 + (blink * 0.22)

      GuiColorSetForNextWidget(gui, r, g, b, 0.32 + (blink * 0.45))
      GuiImageNinePiece(gui, gui_id(entity_id, 50), slot_x - 2, base_y - 2, SLOT_WIDTH + 4, SLOT_HEIGHT + 4, 0.9)
    end

    GuiColorSetForNextWidget(gui, r, g, b, 0.95)
    GuiImageNinePiece(gui, gui_id(entity_id, i), slot_x, base_y, SLOT_WIDTH, SLOT_HEIGHT, slot_alpha)

    GuiColorSetForNextWidget(gui, r, g, b, 1)
    GuiText(gui, slot_x + 3, base_y + 6, label, 0.62)
  end

  local pointer_x = base_x + ((WINNING_SLOT_INDEX - 1) * (SLOT_WIDTH + SLOT_GAP)) + (SLOT_WIDTH * 0.5) - 2
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
