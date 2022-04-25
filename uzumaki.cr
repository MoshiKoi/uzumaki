# Uzumaki interpreter
# Reference specification: https://esolangs.org/wiki/Uzumaki
# Language by https://esolangs.org/wiki/User:Zero_player_rodent

require "big"

# Turns the grid into an Array of segment Strings
# Each segment starts at the second character of the side, and goes to the end
class Parser
  @grid : Array(String)
  def initialize(grid : Array(String))
    # Adds R characters (Reverses the stack) to the start of the first line
    # Since the stack contains only one element at the start, this is a NOP
    # This makes the spiral more symmetrical, and thus easier to parse
    @grid = grid.map_with_index { |line, index|
      if index == 0
        "RR" + line
      else
        "  " + line
      end
    }
    @cur_x = 0
    @cur_y = 0
    @cur_length = grid.size + 2
    @segments = Array(String).new grid.size * 4
    @is_parsed = false
  end

  # Parses a single loop of the spiral
  # At the end, @cur_x and @cur_y points the beginning of the next loop
  def parse_loop
    self.get_west_east
    @cur_length -= 2

    # Remember that the first character of a side, belongs to the previous segment,
    # so if it has length 1, that one character belongs to the previous segment
    if @cur_length <= 1
      return
    end

    self.get_north_south

    # Note that if the length is 2, then it looks like this:
    #
    #  OOO
    #    O <- We are here
    #
    # Thus, we break here as well
    if @cur_length <= 2
      return
    end

    self.get_east_west
    @cur_length -= 2

    # Ditto here
    if @cur_length <= 1
      return
    end

    self.get_south_north
    return
  end

  # Lazily evaluate and return the segments of the spiral
  def parse
    unless @is_parsed
      while @cur_length > 2
        parse_loop
      end
    end

    @segments
  end

  # Helper methods to get the segments
  # Note the first character is counted as part of the previous segment
  # All methods will leave @cur_x, @cur_y at the start of the next segment
  def get_west_east
    @segments << (1...@cur_length).map { |i| @grid[@cur_y][@cur_x + i] }.join
    @cur_x += @cur_length - 1
  end

  def get_north_south
    @segments << (1...@cur_length).map { |i| @grid[@cur_y + i][@cur_x] }.join
    @cur_y += @cur_length - 1
  end

  def get_east_west
    @segments << (1...@cur_length).map { |i| @grid[@cur_y][@cur_x - i] }.join
    @cur_x -= @cur_length - 1
  end

  def get_south_north
    @segments << (1...@cur_length).map { |i| @grid[@cur_y - i][@cur_x] }.join
    @cur_y -= @cur_length - 1
  end
end

class Interpreter
  def initialize(segments : Array(String))
    @segments = segments

    @accumulator = BigInt.new
    @queue = Deque(BigInt).new [BigInt.new]

    @cur_segment_index = 0
    @cur_segment_pos = 0

    # Some flags
    @is_printing = false
    @at_end = false
  end

  def run
    # Main loop
    until @at_end
      self.handle_char
      self.next_char
    end
  end

  def handle_char
    cur_char = self.cur_segment[@cur_segment_pos]

    if @is_printing && cur_char != '#'
      STDOUT << cur_char
      return
    end

    begin
      case cur_char
      when '#' then @is_printing = !@is_printing
      when 'Q' then @queue.push BigInt.new
      when 'I' then @queue[0] += 1
      when 'D' then @queue[0] -= 1
      when 'P' then @queue[0] += 10
      when 'M' then @queue[0] -= 10
      when 'O' then STDOUT << @queue.first
      when 'C' then STDOUT << @queue.first.to_i.chr
      when 'A' then @accumulator = @queue.first
      when 'X' then @queue.shift
      when 'Z' then @queue.push @queue.first
      when 'S' then @queue.push BigInt.new STDIN.read_byte || 0
      when 'V' then @queue[0] += @accumulator
      # Main loop will then move again to the next char, skipping it
      when 'J' then if @queue.first == @accumulator { self.next_char } end
      when 'K' then if @queue.first != @accumulator { self.next_char } end
      when 'R' then @queue.reverse!
      # Jump statements
      # Immediately parse the character landed on before the main loop skips it
      when 'H' 
        self.jump_out
        self.handle_char
      when 'B'
        self.jump_in
        self.handle_char
      when 'W'
        self.jump_to_top
        self.handle_char
      when 'E' then STDOUT << @queue
      when 'G' then @queue.push BigInt.new STDIN.read_line.to_i { 0 }
      else
        raise "Error at segment #{self.cur_segment}, position #{@cur_segment_pos} (#{cur_char}):\
               Unknown command"
      end
    rescue IndexError | Enumerable::EmptyError
      raise "Error at segment #{self.cur_segment}, position #{@cur_segment_pos} (#{cur_char}):\
             Queue is empty"
    end
  end

  # Move to the next character
  def next_char
    if @cur_segment_pos == self.cur_segment.size - 1
      if self.at_last_segment
        @at_end = true
      else
        @cur_segment_index += 1
        @cur_segment_pos = 0
      end
    else
      @cur_segment_pos += 1
    end
  end

  def cur_segment
    @segments[@cur_segment_index]
  end

  def at_last_segment
    @cur_segment_index == @segments.size - 1
  end

  def jump_in
    # Consider the following
    #
    # OABCCO .
    # C    O .
    # B O  C O
    # B OAAO O
    # A      O
    # OOOOOOOO
    #
    # Jumping from each of A, B, C will have different behaviour

    inner_wall = @segments[@cur_segment_index + 4]?
    inner_wall_length = if inner_wall.nil? (-1) else (inner_wall.size + 2) end

    # Case A (Also handle the edge case for the two final segments)
    if @cur_segment_pos == 0 || @cur_segment_index >= @segments.size - 2
      @cur_segment_index -= 2
      @cur_segment_pos = self.cur_segment.size - 2 - @cur_segment_pos
    # Case C: Basically the inverse of A
    elsif @cur_segment_pos > inner_wall_length
      @cur_segment_pos = self.cur_segment.size - 2 - @cur_segment_pos
      @cur_segment_index += 2
    # Case B: Blocked by "inner wall"
    else
      @cur_segment_index += 4
      @cur_segment_pos -= 2 # Adjust for the smaller segment size
    end

    # Case B might have put us on the tail of the previous segment, we need to check that
    self.validate_segment_index
  end

  def jump_out
    if @cur_segment_index < 4
      raise "Attempted to jump out of topmost layer"
    end

    @cur_segment_index -= 4;
    @cur_segment_pos += 2;
  end

  # Jump until we reach layer 1, i.e. one of the first four segements
  def jump_to_top
    until @cur_segment_index < 4
      self.jump_out
    end
  end

  def validate_segment_index
    if @cur_segment_pos == -1
      @cur_segment_index -= 1
      @cur_segment_pos == self.cur_segment.size - 1
    end
  end
end

# Main
file_name = ARGV[0]?

if file_name.nil?
  puts "No file specified."
  exit
end

grid = File.read_lines(file_name)

# Check that the width and height of the grid are equal
unless grid.all? { |line| line.size == grid.size }
  puts "Not a perfect spiral"
  exit
end

parser = Parser.new(grid)
interpreter = Interpreter.new parser.parse
interpreter.run