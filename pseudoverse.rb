require "io/console"
require "json"

WIDTH  = 30
HEIGHT = 12

PLAYER1 = "@1"
PLAYER2 = "@2"
DOG     = "&"
ENEMY   = "E"
FOOD    = "{]"
BEER    = "B"
WALL    = "#"
FLOOR   = "."

FACTION_DOGS = "&"
FACTION_PYCO = "P"
FACTION_ARMY = "A"
FACTION_SPY  = "S"

SAVE_SLOTS  = 14
SAVE_PREFIX = "save_slot_"

SINGLE_PLAYER = false

INVENTORY_SIZE = 5

FACTIONS = {
  FACTION_DOGS => { name: "The Dogs", anger_threshold: 20 },
  FACTION_PYCO => { name: "The Pycoes", anger_threshold: 20 },
  FACTION_ARMY => { name: "The Army",  anger_threshold: 20 },
  FACTION_SPY  => { name: "The Spies", anger_threshold: 20 }
}

FACTION_LIST = [FACTION_DOGS, FACTION_PYCO, FACTION_ARMY, FACTION_SPY]

$faction_disposition = Hash.new(50)
$player_faction = nil

def faction_hostile?(glyph)
  return false if $player_faction == glyph
  info = FACTIONS[glyph]
  return false unless info
  $faction_disposition[glyph] < info[:anger_threshold]
end

def change_faction_disposition(glyph, delta)
  return unless FACTIONS[glyph]
  $faction_disposition[glyph] = [
    0,
    [$faction_disposition[glyph] + delta, 100].min
  ].max
end

FACTION_TASKS = {
  FACTION_DOGS => {
    description: "Give us one piece of food.",
    requirement: :give_food,
    completed: false
  },
  FACTION_PYCO => {
    description: "Hit any enemy once.",
    requirement: :hit_enemy,
    completed: false
  },
  FACTION_ARMY => {
    description: "Stand still for 3 turns.",
    requirement: :stand_still,
    completed: false,
    counter: 0
  },
  FACTION_SPY => {
    description: "Observe an enemy for 2 turns without attacking.",
    requirement: :observe_enemy,
    completed: false,
    counter: 0
  }
}

DOG_DIALOG = [
  {
    text: "The scent on you is unfamiliar.",
    choices: [
      { label: "I mean no harm.",       delta: +10, result: "Then walk with care. The pack watches." },
      { label: "Just passing through.", delta: 0,   result: "Then pass quietly. The wild listens." },
      { label: "Back off, mutt.",       delta: -25, result: "Your bark is weak. Your fear is loud." }
    ]
  },
  {
    text: "These lands belong to the pack.",
    choices: [
      { label: "I respect your territory.",      delta: +5,  result: "Respect is rare. You may continue." },
      { label: "I didn't know.",                 delta: 0,   result: "Now you do. Step lightly." },
      { label: "Territory means nothing to me.", delta: -20, result: "Then you mean nothing to us." }
    ]
  }
]

PYCO_DIALOG = [
  {
    text: "Heheheb& you look funny.",
    choices: [
      { label: "You're funny too.", delta: +10, result: "I know! Isn't it great?" },
      { label: "Uhb& thanks?",     delta: 0,   result: "No problem. Or is it?" },
      { label: "Shut up.",          delta: -20, result: "Rude. Very rude." }
    ]
  },
  {
    text: "Want to see something weird?",
    choices: [
      { label: "Sure.",           delta: +5,  result: "Too late. You already did!" },
      { label: "Maybe later.",    delta: 0,   result: "Time is meaningless anyway." },
      { label: "Leave me alone.", delta: -25, result: "Then we're alone now. Together." }
    ]
  }
]

ARMY_DIALOG = [
  {
    text: "Identify yourself, civilian.",
    choices: [
      { label: "Friendly traveler.",     delta: +5,  result: "Acknowledged. Maintain course." },
      { label: "Just exploring.",        delta: 0,   result: "Stay within designated zones." },
      { label: "I don't answer to you.", delta: -20, result: "Then you are a threat." }
    ]
  },
  {
    text: "State your intentions.",
    choices: [
      { label: "Cooperation.", delta: +10, result: "Good. Cooperation maintains order." },
      { label: "Neutral.",     delta: 0,   result: "Neutrality is acceptable." },
      { label: "Hostile.",     delta: -30, result: "Hostility confirmed. Engaging." }
    ]
  }
]

SPY_DIALOG = [
  {
    text: "You move loudly. That makes you easy to track.",
    choices: [
      { label: "I'll be quieter.",    delta: +10, result: "Good. Silence keeps you alive." },
      { label: "I didn't realize.",   delta: 0,   result: "Awareness is the first step." },
      { label: "Mind your business.", delta: -20, result: "I always do. You should too." }
    ]
  },
  {
    text: "Information is more valuable than strength.",
    choices: [
      { label: "I agree.",                      delta: +5,  result: "Then you already understand our work." },
      { label: "Sometimes.",                   delta: 0,   result: "Balance is important." },
      { label: "Strength is all that matters.", delta: -25, result: "Only fools believe that." }
    ]
  }
]

def distort_text(text, intensity = 0.15)
  text.chars.map { |c| rand < intensity && c =~ /[A-Za-z]/ ? ('a'..'z').to_a.sample : c }.join
end

def npc_dialog(faction_glyph, player)
  if !SINGLE_PLAYER
    system("clear") || system("cls")
    puts "Faction conversations are only available in SOLO mode."
    puts "(Press ENTER to continue)"
    STDIN.gets
    return
  end

  dialog_pool =
    case faction_glyph
    when FACTION_DOGS then DOG_DIALOG
    when FACTION_PYCO then PYCO_DIALOG
    when FACTION_ARMY then ARMY_DIALOG
    when FACTION_SPY  then SPY_DIALOG
    else return
    end

  task = FACTION_TASKS[faction_glyph]

  loop do
    system("clear") || system("cls")

    faction_name = FACTIONS[faction_glyph][:name]
    disp = $faction_disposition[faction_glyph]
    state = faction_hostile?(faction_glyph) ? "HOSTILE" : "NEUTRAL"
    status = ($player_faction == faction_glyph ? "MEMBER" : "OUTSIDER")

    puts "[#{faction_name}]"
    puts
    puts "Disposition: #{disp} (#{state})"
    puts "Your status: #{status}"
    if task && !task[:completed] && $player_faction.nil?
      puts "Task: #{task[:description]}"
    end
    puts

    convo = dialog_pool.sample

    text = convo[:text]
    text = distort_text(text, 0.15) if (player[:drunk] || 0) > 0
    puts text
    puts

    convo[:choices].each_with_index do |c, i|
      label = c[:label]
      label = distort_text(label, 0.10) if (player[:drunk] || 0) > 0
      puts "#{i+1}) #{label}"
    end

    # Dogs-only membership: only Dogs can ever offer the join option
    join_option_available =
      SINGLE_PLAYER &&
      task &&
      task[:completed] &&
      $player_faction.nil? &&
      faction_glyph == FACTION_DOGS

    if join_option_available
      join_label = "I want to join #{faction_name}"
      join_label = distort_text(join_label, 0.10) if (player[:drunk] || 0) > 0
      puts "4) #{join_label}"
    end

    print "> "
    choice = STDIN.gets.to_i

    if choice == 4
      if !SINGLE_PLAYER
        system("clear") || system("cls")
        puts "You can only join factions in SOLO mode."
        puts "(Press ENTER to continue)"
        STDIN.gets
        next
      end

      if join_option_available
        $player_faction = faction_glyph
        $faction_disposition[faction_glyph] = 100
        (FACTION_LIST - [faction_glyph]).each do |other|
          change_faction_disposition(other, -10)
        end

        system("clear") || system("cls")
        msg = "You have joined #{faction_name}!"
        msg = distort_text(msg, 0.15) if (player[:drunk] || 0) > 0
        puts msg
        puts "(Press ENTER to continue)"
        STDIN.gets
        break
      end
    end

    next unless choice.between?(1, convo[:choices].size)

    selected = convo[:choices][choice-1]
    change_faction_disposition(faction_glyph, selected[:delta])

    result_text = selected[:result]
    result_text = distort_text(result_text, 0.15) if (player[:drunk] || 0) > 0

    system("clear") || system("cls")
    puts result_text
    puts
    puts "(Press ENTER to continue)"
    STDIN.gets
    break
  end
end

def title_screen
  system("clear") || system("cls")
  puts "PSEUDOVERSE"
  puts
  puts "1) Load Save"
  puts "2) Play Alone"
  puts "3) Play With Friend"
  puts "4) Quit"
  print "> "
end

def make_world
  Array.new(HEIGHT) { Array.new(WIDTH, FLOOR) }
end

def add_walls_with_shapes(world, p1, p2, dog_entity)
  walls = []
  avoid = []
  avoid << [p1[:x], p1[:y]] if p1
  avoid << [p2[:x], p2[:y]] if p2
  avoid << [dog_entity.x, dog_entity.y] if dog_entity
  avoid << [WIDTH / 2, HEIGHT / 2]
  shapes = [:scatter, :room, :corridor, :ruin]
  shape = shapes.sample

  case shape
  when :scatter
    while walls.size < 5
      x = rand(WIDTH)
      y = rand(HEIGHT)
      coord = [x, y]
      next if avoid.include?(coord)
      next if walls.include?(coord)
      walls << coord
    end
  when :room
    return add_walls_with_shapes(world, p1, p2, dog_entity) if WIDTH < 3 || HEIGHT < 3
    cx = rand(0..(WIDTH - 3))
    cy = rand(0..(HEIGHT - 3))
    coords = [
      [cx,     cy],     [cx+1, cy],     [cx+2, cy],
      [cx,  cy+1],                    [cx+2, cy+1],
      [cx,  cy+2],   [cx+1, cy+2],   [cx+2, cy+2]
    ]
    coords.shuffle.each do |x, y|
      coord = [x, y]
      next if avoid.include?(coord)
      next if walls.include?(coord)
      walls << coord
      break if walls.size >= 5
    end
  when :corridor
    if rand < 0.5
      y = rand(HEIGHT)
      xs = (0...WIDTH).to_a.shuffle
      xs.each do |x|
        coord = [x, y]
        next if avoid.include?(coord)
        next if walls.include?(coord)
        walls << coord
        break if walls.size >= 5
      end
    else
      x = rand(WIDTH)
      ys = (0...HEIGHT).to_a.shuffle
      ys.each do |y|
        coord = [x, y]
        next if avoid.include?(coord)
        next if walls.include?(coord)
        walls << coord
        break if walls.size >= 5
      end
    end
  when :ruin
    x = rand(0..(WIDTH - 2))
    y = rand(0..(HEIGHT - 2))
    coords = [
      [x,   y],
      [x+1, y],
      [x+1, y+1],
      [x+1, y-1 < 0 ? y : y-1].tap { |c| c[1] = y if c[1] < 0 },
      [x-1 < 0 ? x : x-1, y].tap { |c| c[0] = x if c[0] < 0 }
    ]
    coords.each do |wx, wy|
      next unless wx.between?(0, WIDTH-1) && wy.between?(0, HEIGHT-1)
      coord = [wx, wy]
      next if avoid.include?(coord)
      next if walls.include?(coord)
      walls << coord
      break if walls.size >= 5
    end
  end

  while walls.size < 5
    x = rand(WIDTH)
    y = rand(HEIGHT)
    coord = [x, y]
    next if avoid.include?(coord)
    next if walls.include?(coord)
    walls << coord
  end

  walls.each { |x, y| world[y][x] = WALL }
end

def safe_spawn(world, avoid_coords = [])
  loop do
    x = rand(WIDTH)
    y = rand(HEIGHT)
    coord = [x, y]
    next unless world[y][x] == FLOOR
    next if avoid_coords.include?(coord)
    return [x, y]
  end
end

def safe_entity_spawn(world, avoid_coords)
  loop do
    x = rand(WIDTH)
    y = rand(HEIGHT)
    coord = [x, y]
    next unless world[y][x] == FLOOR
    next if avoid_coords.include?(coord)
    return [x, y]
  end
end

Entity = Struct.new(:x, :y, :glyph, :alive)

def spawn_entities(world, p1, p2)
  entities = []
  avoid = []
  avoid << [p1[:x], p1[:y]] if p1
  avoid << [p2[:x], p2[:y]] if p2 && !p2[:downed]

  if SINGLE_PLAYER
    x, y = safe_entity_spawn(world, avoid)
    entities << Entity.new(x, y, DOG, true)
    avoid << [x, y]
  end

  rand(3..6).times do
    x, y = safe_entity_spawn(world, avoid)
    entities << Entity.new(x, y, ENEMY, true)
    avoid << [x, y]
  end

  rand(2..4).times do
    x, y = safe_entity_spawn(world, avoid)
    entities << Entity.new(x, y, FOOD, true)
    avoid << [x, y]
  end

  rand(1..2).times do
    x, y = safe_entity_spawn(world, avoid)
    entities << Entity.new(x, y, BEER, true)
    avoid << [x, y]
  end

  entities
end

def spawn_faction_npcs(world, p1, p2, entities)
  avoid = []
  avoid << [p1[:x], p1[:y]] if p1
  avoid << [p2[:x], p2[:y]] if p2 && !p2[:downed]
  entities.each { |e| avoid << [e.x, e.y] }
  FACTION_LIST.each do |glyph|
    3.times do
      x, y = safe_entity_spawn(world, avoid)
      entities << Entity.new(x, y, glyph, true)
      avoid << [x, y]
    end
  end
end

def dog_entity(entities)
  entities.find { |e| e.alive && e.glyph == DOG }
end

def build_buffer(world)
  Array.new(HEIGHT) { |y| Array.new(WIDTH) { |x| world[y][x] } }
end

def draw_players_into_buffer(buffer, p1, p2)
  buffer[p1[:y]][p1[:x]] = p1[:downed] ? "^" : PLAYER1
  unless SINGLE_PLAYER
    buffer[p2[:y]][p2[:x]] = p2[:downed] ? "^" : PLAYER2
  end
end

def startup_animation(world, entities, p1, p2)
  buffer = Array.new(HEIGHT) { Array.new(WIDTH, " ") }
  (0...HEIGHT).each do |y|
    (0...WIDTH).each do |x|
      buffer[y][x] = world[y][x]
      entities.each { |e| buffer[e.y][e.x] = e.glyph if e.alive }
      draw_players_into_buffer(buffer, p1, p2)
      system("clear") || system("cls")
      buffer.each { |row| puts row.join(" ") }
      sleep 0.0005
    end
  end
end

def death_animation(world, entities, p1, p2)
  buffer = build_buffer(world)
  entities.each { |e| buffer[e.y][e.x] = e.glyph if e.alive }
  draw_players_into_buffer(buffer, p1, p2)
  (HEIGHT - 1).downto(0) do |y|
    (WIDTH - 1).downto(0) do |x|
      buffer[y][x] = " "
      system("clear") || system("cls")
      buffer.each { |row| puts row.join(" ") }
      sleep 0.0005
    end
  end
  system("clear") || system("cls")
  puts "HERE WE MOURN THE DEATH OF A HERO"
  sleep 2
end

def render(world, p1, p2, entities)
  system("clear") || system("cls")
  buffer = build_buffer(world)
  entities.each { |e| buffer[e.y][e.x] = e.glyph if e.alive }
  draw_players_into_buffer(buffer, p1, p2)
  buffer.each { |row| puts row.join(" ") }
  puts
  puts "P1 HP: #{p1[:hp]}"
  puts "P2 HP: #{p2[:hp]}" unless SINGLE_PLAYER
  drunk1 = p1[:drunk] || 0
  drunk2 = SINGLE_PLAYER ? 0 : (p2[:drunk] || 0)

  if SINGLE_PLAYER
    puts "P1: WASD move#{drunk1 > 0 ? ' (INVERTED while drunk)' : ''}, SPACE attack,"
    puts "    E eat, G pick up, T give, R drop, I inventory, F talk"
  else
    puts "P1: WASD move#{drunk1 > 0 ? ' (INVERTED while drunk)' : ''}, SPACE attack,"
    puts "    E eat, G pick up, T give (SOLO only), R drop, I inventory"
    puts "P2: Arrows move#{drunk2 > 0 ? ' (INVERTED while drunk)' : ''}, P attack,"
    puts "    e eat, G pick up, R drop, L talk (SOLO only)"
    puts "Friendly fire is ON."
  end

  if drunk1 > 0 || drunk2 > 0
    puts
    puts "Status: DRUNK (enemies ignore you; factions love you) b turns left:"
    puts "P1 drunk turns: #{drunk1}"
    puts "P2 drunk turns: #{drunk2}" unless SINGLE_PLAYER
  end

  puts
  puts "Factions:"
  FACTION_LIST.each do |glyph|
    info  = FACTIONS[glyph]
    disp  = $faction_disposition[glyph]
    state = faction_hostile?(glyph) ? "HOSTILE" : "NEUTRAL"
    member = ($player_faction == glyph ? " (YOU)" : "")
    puts "#{glyph} #{info[:name]}: #{disp} (#{state})#{member}"
  end

  puts
  puts "ESC: Save/Load menu | X: quit"
end

def read_key
  STDIN.echo = false
  STDIN.raw!
  c1 = STDIN.getc
  if c1 == "\e"
    if IO.select([STDIN], nil, nil, 0.01)
      c2 = STDIN.getc
      if IO.select([STDIN], nil, nil, 0.001)
        c3 = STDIN.getc
        return c1 + c2 + c3
      else
        return c1 + c2
      end
    else
      return "\e"
    end
  end
  c1
ensure
  STDIN.echo = true
  STDIN.cooked!
end

def manhattan(a, b)
  (a[:x] - b[:x]).abs + (a[:y] - b[:y]).abs
end

def out_of_bounds?(p)
  p[:x] < 0 || p[:x] >= WIDTH || p[:y] < 0 || p[:y] >= HEIGHT
end

def adjacent_faction_npc(entities, p)
  entities.find do |e|
    e.alive &&
      FACTIONS[e.glyph] &&
      ((e.x - p[:x]).abs + (e.y - p[:y]).abs == 1)
  end
end

def adjacent_food_entity(entities, p)
  entities.find do |e|
    e.alive &&
      e.glyph == FOOD &&
      ((e.x - p[:x]).abs + (e.y - p[:y]).abs == 1)
  end
end

def adjacent_attackable(entities, p)
  entities.find do |e|
    next false unless e.alive
    next false if FACTIONS[e.glyph] && $player_faction == e.glyph
    (e.glyph == ENEMY || FACTIONS[e.glyph]) &&
      ((e.x - p[:x]).abs + (e.y - p[:y]).abs == 1)
  end
end

def adjacent_food_for_eating(entities, p)
  entities.find { |e| e.alive && e.glyph == FOOD && (e.x - p[:x]).abs + (e.y - p[:y]).abs == 1 }
end

def adjacent_player?(a, b)
  return false if b.nil?
  (a[:x] - b[:x]).abs + (a[:y] - b[:y]).abs == 1
end

def player_attack(p, entities, other_player = nil)
  target = adjacent_attackable(entities, p)
  if target
    if target.glyph == ENEMY
      task = FACTION_TASKS[FACTION_PYCO]
      if task[:requirement] == :hit_enemy && !task[:completed]
        task[:completed] = true
      end
    end

    if FACTIONS[target.glyph]
      change_faction_disposition(target.glyph, -25)
    end

    target.alive = false
  end

  if other_player && adjacent_player?(p, other_player)
    other_player[:hp] -= 1
  end
end

def player_eat(player, entities)
  food = adjacent_food_for_eating(entities, player)
  if food
    player[:hp] += 2
    food.alive = false
    return
  end

  player[:inventory] ||= Array.new(INVENTORY_SIZE)

  if remove_first_item(player, :food)
    player[:hp] += 2
    return
  end

  if remove_first_item(player, :beer)
    player[:drunk] = 10
    FACTION_LIST.each { |f| $faction_disposition[f] = 100 }
    return
  end
end

def inventory_full?(player)
  inv = player[:inventory] || []
  inv.compact.size >= INVENTORY_SIZE
end

def add_item(player, item)
  player[:inventory] ||= Array.new(INVENTORY_SIZE)
  idx = player[:inventory].index(nil)
  return false unless idx
  player[:inventory][idx] = item
  true
end

def remove_first_item(player, item)
  player[:inventory] ||= Array.new(INVENTORY_SIZE)
  idx = player[:inventory].index(item)
  return false unless idx
  player[:inventory][idx] = nil
  true
end

def first_item(player)
  player[:inventory] ||= Array.new(INVENTORY_SIZE)
  player[:inventory].compact.first
end

def drop_first_item(player, world, entities)
  player[:inventory] ||= Array.new(INVENTORY_SIZE)
  item = first_item(player)
  return unless item
  x = player[:x]
  y = player[:y]
  return unless world[y][x] == FLOOR
  occupied = entities.any? { |e| e.alive && e.x == x && e.y == y }
  return if occupied

  case item
  when :food
    entities << Entity.new(x, y, FOOD, true)
  when :beer
    entities << Entity.new(x, y, BEER, true)
  end

  remove_first_item(player, item)
end

def show_inventory(player)
  player[:inventory] ||= Array.new(INVENTORY_SIZE)
  system("clear") || system("cls")
  puts "Inventory:"
  player[:inventory].each_with_index do |item, i|
    label =
      case item
      when :food then "Food"
      when :beer then "Beer"
      when nil   then "(empty)"
      else item.to_s
      end
    puts "#{i+1}) #{label}"
  end
  puts
  puts "(Press ENTER to continue)"
  STDIN.gets
end

def pick_up_items(player, entities)
  return if inventory_full?(player)

  item = entities.find do |e|
    e.alive &&
      (e.glyph == FOOD || e.glyph == BEER) &&
      ((e.x - player[:x]).abs + (e.y - player[:y]).abs == 1)
  end

  return unless item

  case item.glyph
  when FOOD
    add_item(player, :food)
  when BEER
    add_item(player, :beer)
  end

  item.alive = false
end

def give_food_to_faction(player, entities)
  return unless first_item(player) == :food
  npc = adjacent_faction_npc(entities, player)
  return unless npc
  remove_first_item(player, :food)

  if npc.glyph == FACTION_DOGS
    task = FACTION_TASKS[FACTION_DOGS]
    if task[:requirement] == :give_food && !task[:completed] && SINGLE_PLAYER
      task[:completed] = true
    end
    change_faction_disposition(FACTION_DOGS, +10)
  else
    change_faction_disposition(npc.glyph, +5)
  end

  system("clear") || system("cls")
  puts "You gave food to #{FACTIONS[npc.glyph][:name]}."
  puts "(Press ENTER to continue)"
  STDIN.gets
end

def move_player(world, p, entities, dx, dy)
  return false if p[:downed]
  p[:x] += dx
  p[:y] += dy
  true
end

def dog_turn(world, entities, player)
  dog = dog_entity(entities)
  return unless dog && dog.alive

  enemy = entities.find do |e|
    e.alive &&
      e.glyph == ENEMY &&
      (e.x - dog.x).abs + (e.y - dog.y).abs == 1
  end

  if enemy
    enemy.alive = false
    return
  end

  dx = if player[:x] < dog.x
         -1
       elsif player[:x] > dog.x
         1
       else
         0
       end

  dy = if player[:y] < dog.y
         -1
       elsif player[:y] > dog.y
         1
       else
         0
       end

  new_x = dog.x + dx
  new_y = dog.y + dy
  return unless new_x.between?(0, WIDTH-1) && new_y.between?(0, HEIGHT-1)
  return if world[new_y][new_x] == WALL
  return if (new_x == player[:x] && new_y == player[:y])

  occupied = entities.any? do |e|
    e.alive && e != dog && e.x == new_x && e.y == new_y
  end
  return if occupied

  dog.x = new_x
  dog.y = new_y
end

def move_enemies(world, entities, p1, p2)
  drunk_any = (p1[:drunk] || 0) > 0 || (!SINGLE_PLAYER && (p2[:drunk] || 0) > 0)

  enemies = entities.select do |e|
    next false unless e.alive
    if drunk_any
      false
    else
      if FACTIONS[e.glyph]
        faction_hostile?(e.glyph)
      else
        e.glyph == ENEMY
      end
    end
  end

  enemies.each do |enemy|
    enemy_hash = { x: enemy.x, y: enemy.y }
    target = if SINGLE_PLAYER
               p1
             else
               manhattan(enemy_hash, p1) <= manhattan(enemy_hash, p2) ? p1 : p2
             end

    dx = target[:x] < enemy.x ? -1 : target[:x] > enemy.x ? 1 : 0
    dy = target[:y] < enemy.y ? -1 : target[:y] > enemy.y ? 1 : 0

    enemy.x += dx
    enemy.y += dy

    p1[:hp] -= 1 if enemy.x == p1[:x] && enemy.y == p1[:y]
    p2[:hp] -= 1 if !SINGLE_PLAYER && enemy.x == p2[:x] && enemy.y == p2[:y]
  end
end

def save_game(slot, world, entities, p1, p2)
  data = {
    "world"         => world,
    "entities"      => entities.map { |e| { "x" => e.x, "y" => e.y, "glyph" => e.glyph, "alive" => e.alive } },
    "player1"       => p1,
    "player2"       => p2,
    "single_player" => SINGLE_PLAYER
  }

  File.write("#{SAVE_PREFIX}#{slot}.json", JSON.pretty_generate(data))
end

def load_game(slot)
  file = "#{SAVE_PREFIX}#{slot}.json"
  return nil unless File.exist?(file)
  data = JSON.parse(File.read(file))
  world    = data["world"]
  entities = data["entities"].map { |h| Entity.new(h["x"], h["y"], h["glyph"], h["alive"]) }
  p1       = data["player1"].transform_keys(&:to_sym)
  p2       = data["player2"].transform_keys(&:to_sym)
  single   = data["single_player"]
  [world, entities, p1, p2, single]
end

def save_menu(world, entities, p1, p2)
  system("clear") || system("cls")
  puts "=== SAVE GAME ==="
  (1..SAVE_SLOTS).each { |i| puts "#{i}) Save Slot #{i}" }
  puts "#{SAVE_SLOTS + 1}) Cancel"
  print "> "
  slot = STDIN.gets.to_i
  return if slot < 1 || slot > SAVE_SLOTS
  save_game(slot, world, entities, p1, p2)
end

def load_menu
  system("clear") || system("cls")
  puts "=== LOAD GAME ==="

  (1..SAVE_SLOTS).each do |i|
    file = "#{SAVE_PREFIX}#{i}.json"

    if File.exist?(file)
      data = JSON.parse(File.read(file))
      label = data["single_player"] ? "USED" : "USED CO-OP"
      puts "#{i}) Slot #{i} (#{label})"
    else
      puts "#{i}) Slot #{i} (EMPTY)"
    end
  end

  puts "#{SAVE_SLOTS + 1}) Cancel"
  print "> "
  slot = STDIN.gets.to_i
  return nil if slot < 1 || slot > SAVE_SLOTS
  load_game(slot)
end

def save_load_menu(world, entities, p1, p2)
  system("clear") || system("cls")
  puts "=== SAVE / LOAD MENU ==="
  puts "1) Save Game"
  puts "2) Load Game"
  puts "3) Cancel"
  print "> "
  choice = STDIN.gets.to_i

  case choice
  when 1 then save_menu(world, entities, p1, p2); :save
  when 2 then :load
  else :cancel
  end
end

world    = nil
entities = nil
player1  = nil
player2  = nil

loop do
  title_screen
  choice = STDIN.gets.to_i

  case choice
  when 1
    loaded = load_menu
    if loaded
      world, entities, player1, player2, loaded_single = loaded
      Object.send(:remove_const, :SINGLE_PLAYER) rescue nil
      SINGLE_PLAYER = !!loaded_single
      player1[:inventory] ||= Array.new(INVENTORY_SIZE)
      player2[:inventory] ||= Array.new(INVENTORY_SIZE)
      player1[:drunk] ||= 0
      player2[:drunk] ||= 0
      break
    end
  when 2
    Object.send(:remove_const, :SINGLE_PLAYER) rescue nil
    SINGLE_PLAYER = true
    world = make_world
    x, y = safe_spawn(world)
    player1 = {
      x: x, y: y, hp: 10, downed: false,
      inventory: Array.new(INVENTORY_SIZE),
      drunk: 0
    }
    player2 = {
      x: -1, y: -1, hp: 0, downed: true,
      inventory: Array.new(INVENTORY_SIZE),
      drunk: 0
    }
    entities = spawn_entities(world, player1, nil)
    dog = dog_entity(entities)
    add_walls_with_shapes(world, player1, nil, dog)
    spawn_faction_npcs(world, player1, nil, entities)
    break
  when 3
    Object.send(:remove_const, :SINGLE_PLAYER) rescue nil
    SINGLE_PLAYER = false
    world = make_world
    x1, y1 = safe_spawn(world)
    player1 = {
      x: x1, y: y1, hp: 10, downed: false,
      inventory: Array.new(INVENTORY_SIZE),
      drunk: 0
    }
    x2, y2 = safe_spawn(world, [[x1, y1]])
    player2 = {
      x: x2, y: y2, hp: 10, downed: false,
      inventory: Array.new(INVENTORY_SIZE),
      drunk: 0
    }
    entities = spawn_entities(world, player1, player2)
    dog = nil
    add_walls_with_shapes(world, player1, player2, dog)
    spawn_faction_npcs(world, player1, player2, entities)
    break
  when 4
    puts "Goodbye."
    exit
  end
end

startup_animation(world, entities, player1, player2)

running = true

while running
  render(world, player1, player2, entities)

  key   = read_key
  moved = false

  drunk1 = player1[:drunk] || 0
  drunk2 = SINGLE_PLAYER ? 0 : (player2[:drunk] || 0)

  case key
  when "w"
    if drunk1 > 0
      moved = move_player(world, player1, entities, 0, 1)
    else
      moved = move_player(world, player1, entities, 0, -1)
    end
  when "s"
    if drunk1 > 0
      moved = move_player(world, player1, entities, 0, -1)
    else
      moved = move_player(world, player1, entities, 0, 1)
    end
  when "a"
    if drunk1 > 0
      moved = move_player(world, player1, entities, 1, 0)
    else
      moved = move_player(world, player1, entities, -1, 0)
    end
  when "d"
    if drunk1 > 0
      moved = move_player(world, player1, entities, -1, 0)
    else
      moved = move_player(world, player1, entities, 1, 0)
    end
  when "\e[A"
    unless SINGLE_PLAYER
      if drunk2 > 0
        moved = move_player(world, player2, entities, 0, 1)
      else
        moved = move_player(world, player2, entities, 0, -1)
      end
    end
  when "\e[B"
    unless SINGLE_PLAYER
      if drunk2 > 0
        moved = move_player(world, player2, entities, 0, -1)
      else
        moved = move_player(world, player2, entities, 0, 1)
      end
    end
  when "\e[D"
    unless SINGLE_PLAYER
      if drunk2 > 0
        moved = move_player(world, player2, entities, 1, 0)
      else
        moved = move_player(world, player2, entities, -1, 0)
      end
    end
  when "\e[C"
    unless SINGLE_PLAYER
      if drunk2 > 0
        moved = move_player(world, player2, entities, -1, 0)
      else
        moved = move_player(world, player2, entities, 1, 0)
      end
    end
  when " "
    player_attack(player1, entities, SINGLE_PLAYER ? nil : player2)
  when "p"
    player_attack(player2, entities, player1) unless SINGLE_PLAYER
  when "e"
    player_eat(player1, entities)
  when "i"
    player_eat(player2, entities) unless SINGLE_PLAYER
  when "g"
    pick_up_items(player1, entities)
    pick_up_items(player2, entities) unless SINGLE_PLAYER
  when "t"
    if !SINGLE_PLAYER
      system("clear") || system("cls")
      puts "You can only give food to factions in SOLO mode."
      puts "(Press ENTER to continue)"
      STDIN.gets
    else
      give_food_to_faction(player1, entities)
    end
  when "r"
    drop_first_item(player1, world, entities)
    drop_first_item(player2, world, entities) unless SINGLE_PLAYER
  when "I"
    show_inventory(player1)
  when "q"
    if !SINGLE_PLAYER && !player1[:downed] && player2[:downed]
      player2[:downed] = false
      player2[:hp] = 5
    end
  when "o"
    if !SINGLE_PLAYER && !player2[:downed] && player1[:downed]
      player1[:downed] = false
      player1[:hp] = 5
    end
  when "f"
    if !SINGLE_PLAYER
      system("clear") || system("cls")
      puts "You can only talk to factions in SOLO mode."
      puts "(Press ENTER to continue)"
      STDIN.gets
    else
      npc = adjacent_faction_npc(entities, player1)
      npc_dialog(npc.glyph, player1) if npc
    end
  when "l"
    if !SINGLE_PLAYER
      system("clear") || system("cls")
      puts "You can only talk to factions in SOLO mode."
      puts "(Press ENTER to continue)"
      STDIN.gets
    else
      npc = adjacent_faction_npc(entities, player2)
      npc_dialog(npc.glyph, player2) if npc
    end
  when "\e"
    choice = save_load_menu(world, entities, player1, player2)
    if choice == :load
      loaded = load_menu
      if loaded
        world, entities, player1, player2, loaded_single = loaded
        Object.send(:remove_const, :SINGLE_PLAYER) rescue nil
        SINGLE_PLAYER = !!loaded_single
        player1[:inventory] ||= Array.new(INVENTORY_SIZE)
        player2[:inventory] ||= Array.new(INVENTORY_SIZE)
        player1[:drunk] ||= 0
        player2[:drunk] ||= 0
      end
    end
  when "x"
    running = false
  else
  end

  army_task = FACTION_TASKS[FACTION_ARMY]
  if army_task[:requirement] == :stand_still && !army_task[:completed]
    if moved
      army_task[:counter] = 0
    else
      army_task[:counter] ||= 0
      army_task[:counter] += 1
      army_task[:completed] = true if army_task[:counter] >= 3
    end
  end

  spy_task = FACTION_TASKS[FACTION_SPY]
  if spy_task[:requirement] == :observe_enemy && !spy_task[:completed]
    enemy_visible = entities.any? { |e| e.alive && e.glyph == ENEMY }
    if enemy_visible && key != " " && key != "p"
      spy_task[:counter] ||= 0
      spy_task[:counter] += 1
      spy_task[:completed] = true if spy_task[:counter] >= 2
    else
      spy_task[:counter] = 0
    end
  end

  move_enemies(world, entities, player1, player2) if moved
  dog_turn(world, entities, player1) if SINGLE_PLAYER

  player1[:drunk] -= 1 if (player1[:drunk] || 0) > 0
  player2[:drunk] -= 1 if !SINGLE_PLAYER && (player2[:drunk] || 0) > 0

  player1[:downed] = true if player1[:hp] <= 0 && !player1[:downed]
  player2[:downed] = true if !SINGLE_PLAYER && player2[:hp] <= 0 && !player2[:downed]

  if out_of_bounds?(player1) || (!SINGLE_PLAYER && out_of_bounds?(player2))
    world = make_world

    if SINGLE_PLAYER
      x, y = safe_spawn(world)
      player1[:x] = x
      player1[:y] = y
      entities = spawn_entities(world, player1, nil)
      dog = dog_entity(entities)
      add_walls_with_shapes(world, player1, nil, dog)
      spawn_faction_npcs(world, player1, nil, entities)
    else
      x1, y1 = safe_spawn(world)
      player1[:x] = x1
      player1[:y] = y1

      x2, y2 = safe_spawn(world, [[x1, y1]])
      player2[:x] = x2
      player2[:y] = y2

      entities = spawn_entities(world, player1, player2)
      dog = nil
      add_walls_with_shapes(world, player1, player2, dog)
      spawn_faction_npcs(world, player1, player2, entities)
    end

    startup_animation(world, entities, player1, player2)
    next
  end

  if SINGLE_PLAYER
    if player1[:downed]
      death_animation(world, entities, player1, player2)
      running = false
    end
  else
    if player1[:downed] && player2[:downed]
      death_animation(world, entities, player1, player2)
      running = false
    end
  end
end

puts "You have left the PSEUDOVERSE."
