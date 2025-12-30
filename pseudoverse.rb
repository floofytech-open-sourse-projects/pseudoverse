# ============================
# PSEUDOVERSE ENGINE
# Infinite World • Solo / Co‑op • Downed/Revive
# Enemy AI • Eating • Combat • JSON Saves
# Friendly Fire • Clean Input Handling • ESC Fix
# Co‑op Save Labeling
# ============================

require "io/console"
require "json"

WIDTH  = 20
HEIGHT = 10

PLAYER1 = "@1"
PLAYER2 = "@2"
DOG     = "&"
ENEMY   = "E"
FOOD    = "{]"
WALL    = "#"
FLOOR   = "."

SAVE_SLOTS  = 14
SAVE_PREFIX = "save_slot_"

SINGLE_PLAYER = false

# ----------------------------
# Title screen
# ----------------------------

def title_screen
  system("clear") || system("cls")
  puts <<~ART
   ____  ____  _____ _   _ ____  _   _ ____   __   __ ____  _____ ____  _____ 
  |  _ \\|  _ \\| ____| \\ | |  _ \\| | | |  _ \\  \\ \\ / /|  _ \\| ____/ ___|| ____|
  | |_) | |_) |  _| |  \\| | | | | | | | | | |  \\ V / | | | |  _| \\___ \\|  _|  
  |  __/|  _ <| |___| |\\  | |_| | |_| | |_| |   | |  | |_| | |___ ___) | |___ 
  |_|   |_| \\_\\_____|_| \\_|____/ \\___/|____/    |_|  |____/|_____|____/|_____|
                                                                              
                                   P S E U D O V E R S E
  ART

  puts
  puts "Welcome to the PSEUDOVERSE"
  puts "=========================="
  puts
  puts "1) Load Save"
  puts "2) Play Alone"
  puts "3) Play With Friend"
  puts "4) Quit"
  print "> "
end

# ----------------------------
# World generation
# ----------------------------

def make_world
  Array.new(HEIGHT) { Array.new(WIDTH) { FLOOR } }
end

# ----------------------------
# Entities
# ----------------------------

Entity = Struct.new(:x, :y, :glyph, :alive)

def spawn_entities
  [
    Entity.new(3, 3,  DOG,   true),
    Entity.new(10, 4, ENEMY, true),
    Entity.new(7, 7,  FOOD,  true)
  ]
end

# ----------------------------
# Rendering helpers
# ----------------------------

def build_buffer(world)
  Array.new(HEIGHT) { |y| Array.new(WIDTH) { |x| world[y][x] } }
end

def draw_players_into_buffer(buffer, p1, p2)
  buffer[p1[:y]][p1[:x]] = p1[:downed] ? "^" : PLAYER1
  unless SINGLE_PLAYER
    buffer[p2[:y]][p2[:x]] = p2[:downed] ? "^" : PLAYER2
  end
end

# ----------------------------
# Startup animation
# ----------------------------

def startup_animation(world, entities, p1, p2)
  buffer = Array.new(HEIGHT) { Array.new(WIDTH, " ") }

  (0...HEIGHT).each do |y|
    (0...WIDTH).each do |x|
      buffer[y][x] = world[y][x]
      entities.each { |e| buffer[e.y][e.x] = e.glyph if e.alive }
      draw_players_into_buffer(buffer, p1, p2)

      system("clear") || system("cls")
      buffer.each { |row| puts row.join }
      sleep 0.01
    end
  end
end

# ----------------------------
# Death animation
# ----------------------------

def death_animation(world, entities, p1, p2)
  buffer = build_buffer(world)
  entities.each { |e| buffer[e.y][e.x] = e.glyph if e.alive }
  draw_players_into_buffer(buffer, p1, p2)

  (HEIGHT - 1).downto(0) do |y|
    (WIDTH - 1).downto(0) do |x|
      buffer[y][x] = " "
      system("clear") || system("cls")
      buffer.each { |row| puts row.join }
      sleep 0.01
    end
  end

  system("clear") || system("cls")
  puts "HERE WE MOURN THE DEATH OF A HERO"
  sleep 2
end

# ----------------------------
# Rendering
# ----------------------------

def render(world, p1, p2, entities)
  system("clear") || system("cls")

  buffer = build_buffer(world)
  entities.each { |e| buffer[e.y][e.x] = e.glyph if e.alive }
  draw_players_into_buffer(buffer, p1, p2)

  buffer.each { |row| puts row.join }

  puts
  puts "P1 HP: #{p1[:hp]}"
  puts "P2 HP: #{p2[:hp]}" unless SINGLE_PLAYER

  if SINGLE_PLAYER
    puts "P1: WASD move, SPACE attack, E eat"
  else
    puts "P1: WASD move, SPACE attack, E eat, Q revive"
    puts "P2: Arrows move, P attack, I eat, O revive"
    puts "Friendly fire is ON."
  end

  puts "ESC: Save/Load menu | X: quit"
end

# ----------------------------
# Input (ESC fix)
# ----------------------------

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

# ----------------------------
# Utility
# ----------------------------

def manhattan(a, b)
  (a[:x] - b[:x]).abs + (a[:y] - b[:y]).abs
end

def out_of_bounds?(p)
  p[:x] < 0 || p[:x] >= WIDTH || p[:y] < 0 || p[:y] >= HEIGHT
end

# ----------------------------
# Combat / Eating
# ----------------------------

def adjacent_enemy(entities, p)
  entities.find { |e| e.alive && e.glyph == ENEMY && (e.x - p[:x]).abs + (e.y - p[:y]).abs == 1 }
end

def adjacent_player?(a, b)
  return false if b.nil?
  (a[:x] - b[:x]).abs + (a[:y] - b[:y]).abs == 1
end

def player_attack(p, entities, other_player = nil)
  enemy = adjacent_enemy(entities, p)
  enemy.alive = false if enemy

  if other_player && adjacent_player?(p, other_player)
    other_player[:hp] -= 1
  end
end

def adjacent_food(entities, p)
  entities.find { |e| e.alive && e.glyph == FOOD && (e.x - p[:x]).abs + (e.y - p[:y]).abs == 1 }
end

def player_eat(p, entities)
  food = adjacent_food(entities, p)
  return unless food
  p[:hp] += 2
  food.alive = false
end

# ----------------------------
# Movement
# ----------------------------

def move_player(world, p, entities, dx, dy)
  return false if p[:downed]
  p[:x] += dx
  p[:y] += dy
  true
end

# ----------------------------
# Enemy AI
# ----------------------------

def move_enemies(world, entities, p1, p2)
  enemies = entities.select { |e| e.alive && e.glyph == ENEMY }

  enemies.each do |enemy|
    target = SINGLE_PLAYER ? p1 : (manhattan(enemy, p1) <= manhattan(enemy, p2) ? p1 : p2)

    dx = target[:x] < enemy.x ? -1 : target[:x] > enemy.x ? 1 : 0
    dy = target[:y] < enemy.y ? -1 : target[:y] > enemy.y ? 1 : 0

    enemy.x += dx
    enemy.y += dy

    p1[:hp] -= 1 if enemy.x == p1[:x] && enemy.y == p1[:y]
    p2[:hp] -= 1 if !SINGLE_PLAYER && enemy.x == p2[:x] && enemy.y == p2[:y]
  end
end

# ----------------------------
# Save / Load
# ----------------------------

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

# ----------------------------
# Game setup
# ----------------------------

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
      break
    end

  when 2
    Object.send(:remove_const, :SINGLE_PLAYER) rescue nil
    SINGLE_PLAYER = true
    world    = make_world
    entities = spawn_entities
    player1  = { x: 2, y: 2, hp: 10, downed: false }
    player2  = { x: -1, y: -1, hp: 0, downed: true }
    break

  when 3
    Object.send(:remove_const, :SINGLE_PLAYER) rescue nil
    SINGLE_PLAYER = false
    world    = make_world
    entities = spawn_entities
    player1  = { x: 2, y: 2, hp: 10, downed: false }
    player2  = { x: 4, y: 4, hp: 10, downed: false }
    break

  when 4
    puts "Goodbye."
    exit
  end
end

startup_animation(world, entities, player1, player2)

# ----------------------------
# Game loop
# ----------------------------

running = true

while running
  render(world, player1, player2, entities)

  key   = read_key
  moved = false

  case key
  when "w" then moved = move_player(world, player1, entities, 0, -1)
  when "s" then moved = move_player(world, player1, entities, 0, 1)
  when "a" then moved = move_player(world, player1, entities, -1, 0)
  when "d" then moved = move_player(world, player1, entities, 1, 0)

  when "\e[A" then moved = move_player(world, player2, entities, 0, -1) unless SINGLE_PLAYER
  when "\e[B" then moved = move_player(world, player2, entities, 0, 1)  unless SINGLE_PLAYER
  when "\e[D" then moved = move_player(world, player2, entities, -1, 0) unless SINGLE_PLAYER
  when "\e[C" then moved = move_player(world, player2, entities, 1, 0)  unless SINGLE_PLAYER

  when " "
    player_attack(player1, entities, SINGLE_PLAYER ? nil : player2)
  when "p"
    player_attack(player2, entities, player1) unless SINGLE_PLAYER

  when "e" then player_eat(player1, entities)
  when "i" then player_eat(player2, entities) unless SINGLE_PLAYER

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

  when "\e"
    choice = save_load_menu(world, entities, player1, player2)
    if choice == :load
      loaded = load_menu
      if loaded
        world, entities, player1, player2, loaded_single = loaded
        Object.send(:remove_const, :SINGLE_PLAYER) rescue nil
        SINGLE_PLAYER = !!loaded_single
      end
    end

  when "x"
    running = false

  else
    # ignored
  end

  move_enemies(world, entities, player1, player2) if moved

  player1[:downed] = true if player1[:hp] <= 0 && !player1[:downed]
  player2[:downed] = true if !SINGLE_PLAYER && player2[:hp] <= 0 && !player2[:downed]

  if out_of_bounds?(player1) || (!SINGLE_PLAYER && out_of_bounds?(player2))
    world    = make_world
    entities = spawn_entities
    player1[:x] = WIDTH / 2
    player1[:y] = HEIGHT / 2
    unless SINGLE_PLAYER
      player2[:x] = WIDTH / 2 + 1
      player2[:y] = HEIGHT / 2
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
