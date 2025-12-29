# pseudoverse.rb
require "io/console"
require "json"

GRID = 10
MAX_HEALTH = 7
SAVE_SLOTS = 14
SAVE_PREFIX = "pseudoverse_save_"

class Entity
  attr_accessor :x, :y, :symbol

  def initialize(x, y, symbol)
    @x = x
    @y = y
    @symbol = symbol
  end

  def to_h
    { "x" => @x, "y" => @y, "symbol" => @symbol }
  end

  def self.from_h(h)
    Entity.new(h["x"], h["y"], h["symbol"])
  end
end

class World
  attr_accessor :player1, :player2, :npcs, :dogs, :food, :enemies,
                :grid, :health1, :health2, :alive1, :alive2, :coop_mode

  def initialize(coop_mode)
    @coop_mode = coop_mode
    @health1 = MAX_HEALTH
    @health2 = MAX_HEALTH
    @alive1 = true
    @alive2 = coop_mode ? true : false
    regen_world
  end

  # ============================================================
  # SAVE / LOAD SYSTEM (14 SLOTS)
  # ============================================================
  def save_to_slot(slot)
    data = {
      "coop_mode" => @coop_mode,
      "health1" => @health1,
      "health2" => @health2,
      "alive1" => @alive1,
      "alive2" => @alive2,
      "player1" => @player1&.to_h,
      "player2" => @player2&.to_h,
      "npcs" => @npcs.map(&:to_h),
      "dogs" => @dogs.map(&:to_h),
      "food" => @food.map(&:to_h),
      "enemies" => @enemies.map(&:to_h)
    }
    File.write("#{SAVE_PREFIX}#{slot}.json", JSON.pretty_generate(data))
  end

  def load_from_slot(slot)
    file = "#{SAVE_PREFIX}#{slot}.json"
    return unless File.exist?(file)

    data = JSON.parse(File.read(file))

    @coop_mode = data["coop_mode"]
    @health1 = data["health1"]
    @health2 = data["health2"]
    @alive1 = data["alive1"]
    @alive2 = data["alive2"]
    @player1 = data["player1"] ? Entity.from_h(data["player1"]) : nil
    @player2 = if @coop_mode && data["player2"]
                 Entity.from_h(data["player2"])
               else
                 nil
               end
    @npcs = data["npcs"].map { |h| Entity.from_h(h) }
    @dogs = data["dogs"].map { |h| Entity.from_h(h) }
    @food = data["food"].map { |h| Entity.from_h(h) }
    @enemies = data["enemies"].map { |h| Entity.from_h(h) }
  end

  def save_game_menu
    system("clear") || system("cls")
    puts "=== SAVE GAME ==="
    (1..SAVE_SLOTS).each { |i| puts "#{i}) Save Slot #{i}" }
    puts "15) Cancel"
    print "> "

    choice = STDIN.getch.to_i
    return if choice < 1 || choice > SAVE_SLOTS

    save_to_slot(choice)
    puts "\nSaved to slot #{choice}!"
    sleep 1
  end

  def load_game_menu
    system("clear") || system("cls")
    puts "=== LOAD GAME ==="
    (1..SAVE_SLOTS).each do |i|
      exists = File.exist?("#{SAVE_PREFIX}#{i}.json")
      status = exists ? "(USED)" : "(EMPTY)"
      puts "#{i}) Slot #{i} #{status}"
    end
    puts "15) Cancel"
    print "> "

    choice = STDIN.getch.to_i
    return if choice < 1 || choice > SAVE_SLOTS

    load_from_slot(choice)
    puts "\nLoaded slot #{choice}!"
    sleep 1
  end

  def esc_menu
    system("clear") || system("cls")
    puts "=== PSEUDOVERSE MENU ==="
    puts "1) Save Game"
    puts "2) Load Game"
    puts "3) Cancel"
    print "> "

    choice = STDIN.getch
    case choice
    when "1" then save_game_menu
    when "2" then load_game_menu
    end
  end

  # ============================================================
  # WORLD GENERATION
  # ============================================================
  def regen_world
    @grid = Array.new(GRID) { Array.new(GRID, ".") }

    (0...GRID).each do |i|
      @grid[0][i] = "#"
      @grid[GRID-1][i] = "#"
      @grid[i][0] = "#"
      @grid[i][GRID-1] = "#"
    end

    door_side = rand(4)
    case door_side
    when 0 then @grid[0][rand(1..8)] = "[*]"
    when 1 then @grid[GRID-1][rand(1..8)] = "[*]"
    when 2 then @grid[rand(1..8)][0] = "[*]"
    when 3 then @grid[rand(1..8)][GRID-1] = "[*]"
    end

    @player1 = Entity.new(5, 5, "@1")
    if @coop_mode
      @player2 = Entity.new(4, 5, "@2")
      @alive2 = true
      @health2 = MAX_HEALTH
    else
      @player2 = nil
      @alive2 = false
    end

    @alive1 = true
    @health1 = MAX_HEALTH

    @npcs = [
      Entity.new(rand(1..8), rand(1..8), "$"),
      Entity.new(rand(1..8), rand(1..8), "$")
    ]

    @dogs = [
      Entity.new(rand(1..8), rand(1..8), "&"),
      Entity.new(rand(1..8), rand(1..8), "&")
    ]

    @food = [
      Entity.new(rand(1..8), rand(1..8), "{]"),
      Entity.new(rand(1..8), rand(1..8), "{]")
    ]

    @enemies = [
      Entity.new(rand(1..8), rand(1..8), "\\"),
      Entity.new(rand(1..8), rand(1..8), "\\")
    ]
  end

  # ============================================================
  # HEALTH BARS
  # ============================================================
  def health_bar(hp)
    bar = ""
    (0...MAX_HEALTH).each do |i|
      if i < MAX_HEALTH - hp
        bar << "/"
      else
        bar << "="
      end
    end
    bar
  end

  def render_health
    if @alive1
      puts "\nP1: #{health_bar(@health1)}"
    else
      puts "\nP1: DEAD"
    end

    if @coop_mode
      if @alive2
        puts "P2: #{health_bar(@health2)}"
      else
        puts "P2: DEAD"
      end
    end
  end

  # ============================================================
  # EAT FOOD
  # ============================================================
  def eat_food(player_number)
    case player_number
    when 1
      return unless @alive1
      eater = @player1
      return unless eater
      eaten = @food.find { |f| f.x == eater.x && f.y == eater.y }
      return unless eaten
      @health1 += 1 if @health1 < MAX_HEALTH
      @food.delete(eaten)
    when 2
      return unless @coop_mode && @alive2
      eater = @player2
      return unless eater
      eaten = @food.find { |f| f.x == eater.x && f.y == eater.y }
      return unless eaten
      @health2 += 1 if @health2 < MAX_HEALTH
      @food.delete(eaten)
    end
  end

  # ============================================================
  # LINE-BY-LINE DRAW
  # ============================================================
  def draw_line_by_line
    system("clear") || system("cls")

    temp = Marshal.load(Marshal.dump(@grid))
    temp[@player1.y][@player1.x] = "@1" if @alive1 && @player1
    if @coop_mode && @alive2 && @player2
      temp[@player2.y][@player2.x] = "@2"
    end
    @npcs.each { |n| temp[n.y][n.x] = "$" }
    @dogs.each { |d| temp[d.y][d.x] = "&" }
    @food.each { |f| temp[f.y][f.x] = "{]" }
    @enemies.each { |e| temp[e.y][e.x] = "\\" }

    temp.each do |row|
      puts row.map { |c| c.to_s.ljust(3) }.join
      sleep 0.05
    end

    render_health
  end

  # ============================================================
  # STARTUP SCREEN
  # ============================================================
  def render_startup
    system("clear") || system("cls")
    puts "WELLCOME TO THE PSEUDOVERSE"
    sleep 1.5
    draw_line_by_line
  end

  # ============================================================
  # NORMAL RENDER
  # ============================================================
  def render
    temp = Marshal.load(Marshal.dump(@grid))
    temp[@player1.y][@player1.x] = "@1" if @alive1 && @player1
    if @coop_mode && @alive2 && @player2
      temp[@player2.y][@player2.x] = "@2"
    end
    @npcs.each { |n| temp[n.y][n.x] = "$" }
    @dogs.each { |d| temp[d.y][d.x] = "&" }
    @food.each { |f| temp[f.y][f.x] = "{]" }
    @enemies.each { |e| temp[e.y][e.x] = "\\" }

    system("clear") || system("cls")
    temp.each { |row| puts row.map { |c| c.to_s.ljust(3) }.join }
    render_health
  end

  # ============================================================
  # COMBAT
  # ============================================================
  def attack(player_number)
    case player_number
    when 1
      return unless @alive1 && @player1
      px = @player1.x
      py = @player1.y
    when 2
      return unless @coop_mode && @alive2 && @player2
      px = @player2.x
      py = @player2.y
    else
      return
    end

    @enemies.delete_if do |e|
      (e.x == px && (e.y - py).abs == 1) ||
      (e.y == py && (e.x - px).abs == 1)
    end
  end

  # ============================================================
  # DAMAGE
  # ============================================================
  def damage_player(num)
    case num
    when 1
      return unless @alive1
      @health1 -= 1 if @health1 > 0
      if @health1 <= 0
        @alive1 = false
        player_death_sequence(1)
      end
    when 2
      return unless @coop_mode && @alive2
      @health2 -= 1 if @health2 > 0
      if @health2 <= 0
        @alive2 = false
        player_death_sequence(2)
      end
    end
  end

  # ============================================================
  # MOVEMENT + WORLD REGEN
  # ============================================================
  def move_player(num, dx, dy)
    case num
    when 1
      return unless @alive1 && @player1
      actor = @player1
    when 2
      return unless @coop_mode && @alive2 && @player2
      actor = @player2
    else
      return
    end

    new_x = actor.x + dx
    new_y = actor.y + dy

    if new_x < 0 || new_x >= GRID || new_y < 0 || new_y >= GRID
      regen_world
      draw_line_by_line
      return
    end

    return if @grid[new_y][new_x] == "#"

    if @grid[new_y][new_x] == "[*]"
      regen_world
      draw_line_by_line
      return
    end

    actor.x = new_x
    actor.y = new_y
  end

  # ============================================================
  # REVIVE
  # ============================================================
  def revive(player_number)
    case player_number
    when 1
      return unless @coop_mode && @alive1 && !@alive2 && @player1 && @player2
      # P1 tries to revive P2: must be adjacent to P2's last position
      if adjacent?(@player1.x, @player1.y, @player2.x, @player2.y)
        @alive2 = true
        @health2 = [MAX_HEALTH / 2, 1].max
      end
    when 2
      return unless @coop_mode && @alive2 && !@alive1 && @player1 && @player2
      # P2 tries to revive P1
      if adjacent?(@player2.x, @player2.y, @player1.x, @player1.y)
        @alive1 = true
        @health1 = [MAX_HEALTH / 2, 1].max
      end
    end
  end

  def adjacent?(x1, y1, x2, y2)
    (x1 == x2 && (y1 - y2).abs == 1) ||
    (y1 == y2 && (x1 - x2).abs == 1)
  end

  # ============================================================
  # AI
  # ============================================================
  def update_npcs
    @npcs.each do |n|
      dx = [-1, 0, 1].sample
      dy = [-1, 0, 1].sample
      nx = n.x + dx
      ny = n.y + dy
      next if nx < 1 || nx > 8 || ny < 1 || ny > 8
      next if @grid[ny][nx] == "#"
      n.x = nx
      n.y = ny
    end
  end

  def update_dogs
    @dogs.each do |d|
      target = if @coop_mode && @alive2 && @player2
                 # maybe follow P1 more, but for now follow P1
                 @player1
               else
                 @player1
               end
      dx = target.x <=> d.x
      dy = target.y <=> d.y
      nx = d.x + dx
      ny = d.y + dy
      next if nx < 1 || nx > 8 || ny < 1 || ny > 8
      next if @grid[ny][nx] == "#"
      d.x = nx
      d.y = ny
    end
  end

  def update_enemies
    @enemies.each do |e|
      # choose nearest alive player as target
      targets = []
      targets << [@player1, 1] if @alive1 && @player1
      targets << [@player2, 2] if @coop_mode && @alive2 && @player2
      next if targets.empty?

      target, tnum = targets.min_by { |(pl, _)| (pl.x - e.x).abs + (pl.y - e.y).abs }

      dx = target.x <=> e.x
      dy = target.y <=> e.y
      nx = e.x + dx
      ny = e.y + dy

      if nx == target.x && ny == target.y
        damage_player(tnum)
      end

      next if nx < 1 || nx > 8 || ny < 1 || ny > 8
      next if @grid[ny][nx] == "#"
      e.x = nx
      e.y = ny
    end
  end

  # ============================================================
  # PLAYER-SPECIFIC DEATH SEQUENCE
  # ============================================================
  def player_death_sequence(num)
    system("clear") || system("cls")
    who = num == 1 ? "PLAYER 1" : "PLAYER 2"
    puts "#{who} HAS FALLEN..."
    sleep 1

    lines = Array.new(5) { "#{who} FADES FROM THIS WORLD..." }

    until lines.all? { |l| l.strip.empty? }
      system("clear") || system("cls")
      lines.map! do |line|
        chars = line.chars
        rand(3..6).times do
          idx = rand(chars.length)
          chars[idx] = " " unless chars[idx] == " "
        end
        chars.join
      end
      lines.each { |l| puts l }
      sleep 0.05
    end

    system("clear") || system("cls")
    puts "HERE WE MOURN THE DEATH OF A HEREO"
    sleep 1.5
  end

  # ============================================================
  # TICK
  # ============================================================
  def tick
    update_npcs
    update_dogs
    update_enemies
  end
end

# ============================================================
# INPUT HANDLING (INCL. ARROWS)
# ============================================================
def read_key
  ch1 = STDIN.getch
  if ch1 == "\e"
    ch2 = STDIN.getch rescue nil
    ch3 = STDIN.getch rescue nil
    seq = ch1 + (ch2 || "") + (ch3 || "")
    return seq
  else
    ch1
  end
end

# ============================================================
# MODE SELECT
# ============================================================
system("clear") || system("cls")
puts "PSEUDOVERSE MODE SELECT"
puts "1) Single Player"
puts "2) Co-Op (2 players)"
print "> "
mode_choice = STDIN.getch
coop_mode = (mode_choice == "2")

world = World.new(coop_mode)
world.render_startup

loop do
  print "P1: WASD/E/Q SPACE   "
  print "P2: ARROWS/I/P O" if coop_mode
  print "   ESC: Menu\n"

  input = read_key

  case input
  when "\e" # ESC
    world.esc_menu

  # ---------- PLAYER 1 CONTROLS ----------
  when "w" then world.move_player(1, 0, -1)
  when "s" then world.move_player(1, 0, 1)
  when "a" then world.move_player(1, -1, 0)
  when "d" then world.move_player(1, 1, 0)
  when " " then world.attack(1)
  when "e", "E" then world.eat_food(1)
  when "q", "Q" then world.revive(1)

  # ---------- PLAYER 2 CONTROLS (ARROWS / I / O / P) ----------
  when "\e[A" # up arrow
    world.move_player(2, 0, -1) if coop_mode
  when "\e[B" # down arrow
    world.move_player(2, 0, 1) if coop_mode
  when "\e[D" # left arrow
    world.move_player(2, -1, 0) if coop_mode
  when "\e[C" # right arrow
    world.move_player(2, 1, 0) if coop_mode
  when "o", "O"
    world.attack(2) if coop_mode
  when "i", "I"
    world.eat_food(2) if coop_mode
  when "p", "P"
    world.revive(2) if coop_mode
  end

  world.tick
  world.render
end
