# ============================
# Pseudoverse Engine
# 2P Co-op + Downed/Revive
# AI Enemies + Combat + Eating
# Animations + JSON Saves (14 slots)
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

# ----------------------------
# World
# ----------------------------

def make_world
  Array.new(HEIGHT) do |y|
    Array.new(WIDTH) do |x|
      if y == 0 || y == HEIGHT - 1 || x == 0 || x == WIDTH - 1
        WALL
      else
        FLOOR
      end
    end
  end
end

# ----------------------------
# Entities
# ----------------------------

Entity = Struct.new(:x, :y, :glyph, :alive)

def spawn_entities
  [
    Entity.new(3, 3, DOG,   true),
    Entity.new(10, 4, ENEMY, true),
    Entity.new(7, 7, FOOD,  true)
  ]
end

# ----------------------------
# Rendering helpers
# ----------------------------

def build_buffer(world)
  Array.new(HEIGHT) do |y|
    Array.new(WIDTH) do |x|
      world[y][x]
    end
  end
end

def draw_players_into_buffer(buffer, p1, p2)
  buffer[p1[:y]][p1[:x]] = p1[:downed] ? "^" : PLAYER1
  buffer[p2[:y]][p2[:x]] = p2[:downed] ? "^" : PLAYER2
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
  puts "P1 HP: #{p1[:hp]}   P2 HP: #{p2[:hp]}"
  puts "P1: WASD move, SPACE attack, E eat, Q revive"
  puts "P2: Arrows move, P attack, I eat, O revive"
  puts "ESC: Save/Load menu | X: quit"
end

# ----------------------------
# Input
# ----------------------------

def read_key
  STDIN.echo = false
  STDIN.raw!
  c1 = STDIN.getc.chr

  if c1 == "\e"
    c2 = STDIN.getc.chr rescue nil
    c3 = STDIN.getc.chr rescue nil
    key = c1 + (c2 || "") + (c3 || "")
  else
    key = c1
  end
ensure
  STDIN.echo = true
  STDIN.cooked!
  return key
end

# ----------------------------
# Collision helpers
# ----------------------------

def walkable?(world, x, y)
  world[y][x] != WALL
end

def entity_at(entities, x, y)
  entities.find { |e| e.alive && e.x == x && e.y == y }
end

def entity_blocking?(entities, x, y)
  e = entity_at(entities, x, y)
  return false if e.nil?
  return false if e.glyph == FOOD
  true
end

# ----------------------------
# Combat
# ----------------------------

def adjacent_enemy(entities, p)
  entities.find do |e|
    e.alive &&
    e.glyph == ENEMY &&
    ((e.x - p[:x]).abs + (e.y - p[:y]).abs == 1)
  end
end

def player_attack(p, entities)
  enemy = adjacent_enemy(entities, p)
  return unless enemy
  enemy.alive = false
end

# ----------------------------
# Eating
# ----------------------------

def adjacent_food(entities, p)
  entities.find do |e|
    e.alive &&
    e.glyph == FOOD &&
    ((e.x - p[:x]).abs + (e.y - p[:y]).abs == 1)
  end
end

def player_eat(p, entities)
  food = adjacent_food(entities, p)
  return unless food
  p[:hp] += 2
  food.alive = false
end

# ----------------------------
# Distance
# ----------------------------

def manhattan(a, b)
  (a[:x] - b[:x]).abs + (a[:y] - b[:y]).abs
end

# ----------------------------
# Movement
# ----------------------------

def move_player(world, p, entities, dx, dy)
  return false if p[:downed]

  nx = p[:x] + dx
  ny = p[:y] + dy

  return false unless walkable?(world, nx, ny)

  target = entity_at(entities, nx, ny)

  case target&.glyph
  when ENEMY
    p[:hp] -= 1
    return false
  when FOOD
    p[:hp] += 2
    target.alive = false
  when DOG
    return false
  end

  return false if entity_blocking?(entities, nx, ny)

  p[:x] = nx
  p[:y] = ny
  true
end

# ----------------------------
# Enemy AI
# ----------------------------

def move_enemies(world, entities, p1, p2)
  enemies = entities.select { |e| e.alive && e.glyph == ENEMY }

  enemies.each do |enemy|
    enemy_hash = { x: enemy.x, y: enemy.y }

    target = manhattan(enemy_hash, p1) <= manhattan(enemy_hash, p2) ? p1 : p2

    dx = target[:x] < enemy.x ? -1 : target[:x] > enemy.x ? 1 : 0
    dy = target[:y] < enemy.y ? -1 : target[:y] > enemy.y ? 1 : 0

    nx = enemy.x + dx
    ny = enemy.y + dy

    next unless walkable?(world, nx, ny)

    if nx == p1[:x] && ny == p1[:y]
      p1[:hp] -= 1
      next
    elsif nx == p2[:x] && ny == p2[:y]
      p2[:hp] -= 1
      next
    end

    blocker = entity_at(entities, nx, ny)
    next if blocker

    enemy.x = nx
    enemy.y = ny
  end
end

# ----------------------------
# Save / Load
# ----------------------------

def save_game(slot, world, entities, p1, p2)
  data = {
    "world"    => world,
    "entities" => entities.map { |e|
      { "x" => e.x, "y" => e.y, "glyph" => e.glyph, "alive" => e.alive }
    },
    "player1"  => p1,
    "player2"  => p2
  }

  File.write("#{SAVE_PREFIX}#{slot}.json", JSON.pretty_generate(data))
end

def load_game(slot)
  file = "#{SAVE_PREFIX}#{slot}.json"
  return nil unless File.exist?(file)

  data = JSON.parse(File.read(file))

  world = data["world"]

  entities = data["entities"].map do |h|
    Entity.new(h["x"], h["y"], h["glyph"], h["alive"])
  end

  p1 = data["player1"].transform_keys(&:to_sym)
  p2 = data["player2"].transform_keys(&:to_sym)

  [world, entities, p1, p2]
end

def save_menu(world, entities, p1, p2)
  system("clear") || system("cls")
  puts "=== SAVE GAME ==="
  (1..SAVE_SLOTS).each { |i| puts "#{i}) Save Slot #{i}" }
  puts "#{SAVE_SLOTS + 1}) Cancel"
  print "> "
  choice = STDIN.gets.to_i
  return if choice < 1 || choice > SAVE_SLOTS
  save_game(choice, world, entities, p1, p2)
end

def load_menu
  system("clear") || system("cls")
  puts "=== LOAD GAME ==="
  (1..SAVE_SLOTS).each do |i|
    exists = File.exist?("#{SAVE_PREFIX}#{i}.json")
    puts "#{i}) Slot #{i} #{exists ? "(USED)" : "(EMPTY)"}"
  end
  puts "#{SAVE_SLOTS + 1}) Cancel"
  print "> "
  choice = STDIN.gets.to_i
  return nil if choice < 1 || choice > SAVE_SLOTS
  load_game(choice)
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

world    = make_world
entities = spawn_entities
player1  = { x: 2, y: 2, hp: 10, downed: false }
player2  = { x: 4, y: 4, hp: 10, downed: false }

startup_animation(world, entities, player1, player2)

# ----------------------------
# Game loop
# ----------------------------

running = true

while running
  render(world, player1, player2, entities)

  key = read_key
  moved = false

  case key
  # Player 1 movement
  when "w" then moved = move_player(world, player1, entities, 0, -1) unless player1[:downed]
  when "s" then moved = move_player(world, player1, entities, 0, 1)  unless player1[:downed]
  when "a" then moved = move_player(world, player1, entities, -1, 0) unless player1[:downed]
  when "d" then moved = move_player(world, player1, entities, 1, 0)  unless player1[:downed]

  # Player 2 movement
  when "\e[A" then moved = move_player(world, player2, entities, 0, -1) unless player2[:downed]
  when "\e[B" then moved = move_player(world, player2, entities, 0, 1)  unless player2[:downed]
  when "\e[D" then moved = move_player(world, player2, entities, -1, 0) unless player2[:downed]
  when "\e[C" then moved = move_player(world, player2, entities, 1, 0)  unless player2[:downed]

  # Attacks
  when " " then player_attack(player1, entities) unless player1[:downed]
  when "p" then player_attack(player2, entities) unless player2[:downed]

  # Eating
  when "e" then player_eat(player1, entities) unless player1[:downed]
  when "i" then player_eat(player2, entities) unless player2[:downed]

  # Revive
  when "q"
    if !player1[:downed] && player2[:downed]
      player2[:downed] = false
      player2[:hp] = 5
    else
      running = false
    end

  when "o"
    if !player2[:downed] && player1[:downed]
      player1[:downed] = false
      player1[:hp] = 5
    end

  # Save/Load
  when "\e"
    choice = save_load_menu(world, entities, player1, player2)
    if choice == :load
      loaded = load_menu
      if loaded
        world, entities, player1, player2 = loaded
      end
    end

  # Quit
  when "x"
    running = false
  end

  move_enemies(world, entities, player1, player2) if moved

  # Downed logic
  player1[:downed] = true if player1[:hp] <= 0 && !player1[:downed]
  player2[:downed] = true if player2[:hp] <= 0 && !player2[:downed]

  # Full death
  if player1[:downed] && player2[:downed]
    death_animation(world, entities, player1, player2)
    running = false
  end
end

puts "You have left the Pseudoverse."
