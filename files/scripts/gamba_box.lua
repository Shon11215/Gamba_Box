dofile_once("mods/gamba_box/files/scripts/gamba_chest_tiers.lua")
dofile_once("mods/gamba_box/files/scripts/spell_tiers.lua")

local REWARD_TIERS = {
  common = {
    label = "COMMON",
    spells = { tiers = { 0, 1 }, amount_min = 1, amount_max = 2 },
    wands = {
      { kind = "no_shuffle", tiers = { 1 } },
      { kind = "random", tiers = { 2 } },
    },
  },
  uncommon = {
    label = "UNCOMMON",
    spells = { tiers = { 1, 2 }, amount_min = 2, amount_max = 2 },
    wands = {
      { kind = "no_shuffle", tiers = { 2 } },
      { kind = "random", tiers = { 3 } },
    },
  },
  rare = {
    label = "RARE",
    spells = { tiers = { 2, 3, 4 }, amount_min = 2, amount_max = 4 },
    wands = {
      { kind = "no_shuffle", tiers = { 2, 3 } },
      { kind = "random", tiers = { 4 } },
    },
  },
  epic = {
    label = "EPIC",
    spells = { tiers = { 3, 4, 5, 6 }, amount_min = 3, amount_max = 4 },
    wands = {
      { kind = "no_shuffle", tiers = { 3, 4 } },
      { kind = "random", tiers = { 5 } },
    },
  },
  legendary = {
    label = "LEGENDARY",
    spells = { tiers = { 7 }, amount_min = 3, amount_max = 4 },
    wands = {
      { kind = "no_shuffle", tiers = { 6 } },
      { kind = "random", tiers = { 7 } },
    },
  },
  unique = {
    label = "UNIQUE",
    spells = { tiers = { 10 }, amount_min = 4, amount_max = 6 },
    wands = {
      { kind = "no_shuffle", tiers = { 10 } },
    },
  },
}

local WAND_PATHS = {
  no_shuffle = {
    [1] = "data/entities/items/wand_unshuffle_01.xml",
    [2] = "data/entities/items/wand_unshuffle_02.xml",
    [3] = "data/entities/items/wand_unshuffle_03.xml",
    [4] = "data/entities/items/wand_unshuffle_04.xml",
    [5] = "data/entities/items/wand_unshuffle_05.xml",
    [6] = "data/entities/items/wand_unshuffle_06.xml",
    [10] = "data/entities/items/wand_unshuffle_10.xml",
  },
  random = {
    [1] = "data/entities/items/wand_level_01.xml",
    [2] = "data/entities/items/wand_level_02.xml",
    [3] = "data/entities/items/wand_level_03.xml",
    [4] = "data/entities/items/wand_level_04.xml",
    [5] = "data/entities/items/wand_level_05.xml",
    [6] = "data/entities/items/wand_level_06.xml",
    [7] = "data/entities/items/wand_level_06_better.xml",
    [10] = "data/entities/items/wand_level_10.xml",
  },
}

local BAD_ROLLS = {
  { path = "data/entities/animals/duck.xml", name = "duck" },
  { path = "data/entities/animals/sheep.xml", name = "sheep" },
  { path = "data/entities/animals/deer.xml", name = "deer" },
}

local BAD_ROLL_CHANCE_BY_CHEST_TIER = {
  [1] = 10,
  [2] = 10,
  [3] = 10,
}

local BAD_ROLL_POLYMORPH_EFFECT = "data/entities/particles/polymorph_explosion.xml"
local CHEST_OPEN_SOUND_BANK = "data/audio/Desktop/misc.bank"
local CHEST_OPEN_SOUND_EVENT = "misc/chest_dark_open"

local ROLL_GUI_SCRIPT = "mods/gamba_box/files/scripts/gamba_roll_gui.lua"
local ROLL_DURATION_FRAMES = 310
local ROLL_SLOT_COUNT = 36
local ROLL_FINAL_INDEX_MIN = 22
local ROLL_FINAL_INDEX_MAX = 30
local ROLL_STOP_OFFSET_MIN = -14
local ROLL_STOP_OFFSET_MAX = 14

local function get_box_storage(box_entity, tag)
  return EntityGetFirstComponentIncludingDisabled(box_entity, "VariableStorageComponent", tag)
end

local function get_chest_tier(box_entity)
  local tier_storage = get_box_storage(box_entity, "gamba_chest_tier")
  if tier_storage == nil then return 1 end

  local chest_tier = ComponentGetValue2(tier_storage, "value_int")
  if GAMBA_CHEST_TIERS[chest_tier] == nil then return 1 end

  return chest_tier
end

local function get_chest_cost(box_entity)
  local cost_storage = get_box_storage(box_entity, "gamba_chest_cost")
  if cost_storage ~= nil then
    return ComponentGetValue2(cost_storage, "value_int")
  end

  local tier_data = GAMBA_CHEST_TIERS[get_chest_tier(box_entity)]
  return tier_data.base_cost
end

local function get_chest_label(box_entity)
  local chest_tier = get_chest_tier(box_entity)
  local cost = get_chest_cost(box_entity)

  return "Tier " .. tostring(chest_tier) .. " Gamba Box\nCost: " .. tostring(cost) .. " gold\nPress E to test your luck"
end

local function update_cost_display(box_entity)
  local cost_display = EntityGetFirstComponentIncludingDisabled(box_entity, "SpriteComponent", "gamba_cost_display")
  if cost_display ~= nil then
    ComponentSetValue2(cost_display, "text", tostring(get_chest_cost(box_entity)))
  end
end

local function set_cost_display_enabled(box_entity, enabled)
  local cost_display = EntityGetFirstComponentIncludingDisabled(box_entity, "SpriteComponent", "gamba_cost_display")
  if cost_display ~= nil then
    EntitySetComponentIsEnabled(box_entity, cost_display, enabled)
  end
end

local function update_chest_label(box_entity)
  local interactable = EntityGetFirstComponentIncludingDisabled(box_entity, "InteractableComponent")
  if interactable ~= nil then
    ComponentSetValue2(interactable, "ui_text", get_chest_label(box_entity))
  end

  update_cost_display(box_entity)
end

local function increase_chest_cost(box_entity)
  local cost_storage = get_box_storage(box_entity, "gamba_chest_cost")
  if cost_storage == nil then return end

  local chest_tier = get_chest_tier(box_entity)
  local tier_data = GAMBA_CHEST_TIERS[chest_tier]
  local current_cost = ComponentGetValue2(cost_storage, "value_int")
  local next_cost = math.floor((current_cost * tier_data.cost_multiplier) + 0.5)

  ComponentSetValue2(cost_storage, "value_int", next_cost)
  update_chest_label(box_entity)
end

local function try_pay(box_entity, player_entity)
  local cost = get_chest_cost(box_entity)
  if cost <= 0 then return true end

  local wallet = EntityGetFirstComponentIncludingDisabled(player_entity, "WalletComponent")
  if wallet == nil then
    GamePrint("Gamba Box could not find your wallet.")
    return false
  end

  local money = ComponentGetValue2(wallet, "money")
  if money < cost then
    GamePrint("Not enough gold. Gamba Box costs " .. tostring(cost) .. " gold.")
    return false
  end

  ComponentSetValue2(wallet, "money", money - cost)
  increase_chest_cost(box_entity)
  return true
end

local function should_bad_roll(chest_tier)
  local chance = BAD_ROLL_CHANCE_BY_CHEST_TIER[chest_tier]
  if chance == nil or chance <= 0 then return false end

  return Random(1, 100) <= chance
end

local function roll_chest_type()
  if Random(1, 100) > 50 then return "wand" end

  return "spell"
end

local function spawn_bad_roll(box_entity, x, y)
  local bad_roll = BAD_ROLLS[Random(1, #BAD_ROLLS)]

  EntityLoad(BAD_ROLL_POLYMORPH_EFFECT, x, y)
  GamePlaySound("data/audio/Desktop/game_effect.bank", "game_effect/polymorph/create", x, y)
  EntityLoad(bad_roll.path, x, y - 12)
  GamePrintImportant("BAD ROLL", bad_roll.name)
  EntityKill(box_entity)
end

local function choose_spell_from_tiers(tiers)
  local spell_tiers = GAMBA_SPELL_TIERS
  if spell_tiers == nil then return nil end

  local weighted_spells = {}
  local total_weight = 0

  for _, tier in ipairs(tiers) do
    local tier_spells = spell_tiers.by_tier[tier]
    if tier_spells ~= nil then
      for _, spell in ipairs(tier_spells) do
        local weight = math.floor((spell.probability or 0) * 1000)
        if weight > 0 and spell.id ~= nil and spell.id ~= "" then
          total_weight = total_weight + weight
          table.insert(weighted_spells, {
            id = spell.id,
            weight = weight,
          })
        end
      end
    end
  end

  if total_weight <= 0 or #weighted_spells == 0 then return nil end

  local roll = Random(1, total_weight)
  local current_weight = 0

  for _, spell in ipairs(weighted_spells) do
    current_weight = current_weight + spell.weight
    if roll <= current_weight then
      return spell
    end
  end

  return weighted_spells[#weighted_spells]
end

local function choose_rarity(chest_tier)
  local tier_data = GAMBA_CHEST_TIERS[chest_tier] or GAMBA_CHEST_TIERS[1]
  local total_weight = 0

  for _, rarity in ipairs(GAMBA_RARITY_ORDER) do
    total_weight = total_weight + (tier_data.chances[rarity] or 0)
  end

  if total_weight <= 0 then return "common" end

  local roll = Random(1, total_weight)
  local current_weight = 0

  for _, rarity in ipairs(GAMBA_RARITY_ORDER) do
    current_weight = current_weight + (tier_data.chances[rarity] or 0)
    if roll <= current_weight then
      return rarity
    end
  end

  return "common"
end

local function choose_spell_reward(rarity, tier_data)
  local spell_ids = {}
  local amount = Random(tier_data.spells.amount_min, tier_data.spells.amount_max)

  for i = 1, amount do
    local tier = tier_data.spells.tiers[Random(1, #tier_data.spells.tiers)]
    local spell = choose_spell_from_tiers({ tier })
    if spell ~= nil and spell.id ~= nil and spell.id ~= "" then
      table.insert(spell_ids, spell.id)
    end
  end

  if #spell_ids == 0 then return nil end

  return {
    reward_type = "spell",
    rarity = rarity,
    label = tier_data.label,
    spell_ids = spell_ids,
    title = tier_data.label .. " SPELL",
    description = "You got a spell reward.",
  }
end

local function choose_wand_reward(rarity, tier_data)
  local wand_group = tier_data.wands[Random(1, #tier_data.wands)]
  local wand_tier = wand_group.tiers[Random(1, #wand_group.tiers)]
  local wand_path = WAND_PATHS[wand_group.kind][wand_tier]
  if wand_path == nil then return nil end

  return {
    reward_type = "wand",
    rarity = rarity,
    label = tier_data.label,
    wand_path = wand_path,
    title = tier_data.label .. " WAND",
    description = "You got a wand reward.",
  }
end

local function choose_reward(chest_type, chest_tier)
  local rarity = choose_rarity(chest_tier)
  local tier_data = REWARD_TIERS[rarity]
  if tier_data == nil then return nil end

  if chest_type == "spell" then
    return choose_spell_reward(rarity, tier_data)
  end

  return choose_wand_reward(rarity, tier_data)
end

local function add_roll_storage(entity_id, tag, value_type, value)
  local values = { _tags = tag }
  values[value_type] = value
  EntityAddComponent2(entity_id, "VariableStorageComponent", values)
end

local function is_box_rolling(box_entity)
  return EntityGetFirstComponentIncludingDisabled(box_entity, "VariableStorageComponent", "gamba_rolling") ~= nil
end

local function disable_box_interaction(box_entity)
  add_roll_storage(box_entity, "gamba_rolling", "value_bool", true)
  set_cost_display_enabled(box_entity, false)

  local interactable = EntityGetFirstComponentIncludingDisabled(box_entity, "InteractableComponent")
  if interactable ~= nil then
    EntitySetComponentIsEnabled(box_entity, interactable, false)
  end
end

local function get_roll_label(reward)
  local tier_data = REWARD_TIERS[reward.rarity]
  if tier_data == nil then return "COMMON" end

  return tier_data.label
end

local function build_roll_slots(chest_type, chest_tier, final_reward, final_index)
  local labels = {}
  local rarities = {}

  for i = 1, ROLL_SLOT_COUNT do
    local reward = choose_reward(chest_type, chest_tier) or final_reward
    labels[i] = get_roll_label(reward)
    rarities[i] = reward.rarity
  end

  labels[final_index] = get_roll_label(final_reward)
  rarities[final_index] = final_reward.rarity

  return table.concat(labels, "|"), table.concat(rarities, "|")
end

local function start_roll_animation(box_entity, x, y, chest_type, chest_tier, reward)
  local final_index = Random(ROLL_FINAL_INDEX_MIN, ROLL_FINAL_INDEX_MAX)
  local stop_offset = Random(ROLL_STOP_OFFSET_MIN, ROLL_STOP_OFFSET_MAX)
  local labels, rarities = build_roll_slots(chest_type, chest_tier, reward, final_index)
  local roll_entity = EntityCreateNew("gamba_box_roll")
  EntitySetTransform(roll_entity, x, y)

  add_roll_storage(roll_entity, "start_frame", "value_int", GameGetFrameNum())
  add_roll_storage(roll_entity, "duration_frames", "value_int", ROLL_DURATION_FRAMES)
  add_roll_storage(roll_entity, "final_index", "value_int", final_index)
  add_roll_storage(roll_entity, "roll_stop_offset", "value_float", stop_offset)
  add_roll_storage(roll_entity, "box_entity", "value_int", box_entity)
  add_roll_storage(roll_entity, "roll_world_x", "value_float", x)
  add_roll_storage(roll_entity, "roll_world_y", "value_float", y)
  add_roll_storage(roll_entity, "slot_labels", "value_string", labels)
  add_roll_storage(roll_entity, "slot_rarities", "value_string", rarities)
  add_roll_storage(roll_entity, "reward_type", "value_string", reward.reward_type)
  add_roll_storage(roll_entity, "reward_title", "value_string", reward.title)
  add_roll_storage(roll_entity, "reward_description", "value_string", reward.description)
  add_roll_storage(roll_entity, "spell_ids", "value_string", table.concat(reward.spell_ids or {}, "|"))
  add_roll_storage(roll_entity, "wand_path", "value_string", reward.wand_path or "")

  EntityAddComponent2(roll_entity, "LuaComponent", {
    script_source_file = ROLL_GUI_SCRIPT,
    execute_every_n_frame = 1,
  })
end

local function spawn_reward(x, y, box_entity)
  SetRandomSeed(x + GameGetFrameNum(), y)

  local chest_tier = get_chest_tier(box_entity)

  if should_bad_roll(chest_tier) then
    spawn_bad_roll(box_entity, x, y)
    return
  end

  local chest_type = roll_chest_type()
  local reward = choose_reward(chest_type, chest_tier)
  if reward == nil then
    GamePrint("Gamba Box failed to choose a reward.")
    return
  end

  disable_box_interaction(box_entity)
  start_roll_animation(box_entity, x, y, chest_type, chest_tier, reward)
end

local function open_box(box_entity, player_entity)
  if is_box_rolling(box_entity) then return end

  if try_pay(box_entity, player_entity) then
    local x, y = EntityGetTransform(box_entity)
    GamePlaySound(CHEST_OPEN_SOUND_BANK, CHEST_OPEN_SOUND_EVENT, x, y)
    spawn_reward(x, y, box_entity)
  end
end

function interacting(entity_who_interacted, entity_interacted, _interactable_name)
  open_box(entity_interacted, entity_who_interacted)
end
