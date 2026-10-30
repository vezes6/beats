module Beats
  module Console
    class Editor
      attr_reader :row, :column, :status

      def initialize(project, input, output)
        @project, @input, @output = project, input, output
        @row, @column, @footer = 0, 0, 0
        @status = "Tab alterna o passo selecionado."
        @running = true
      end

      def run
        @output.write "\e[?1049h\e[?25l"
        begin
          while @running
            render
            begin
              handle(read_key)
            rescue Interrupt
              handle(:eof)
            end
          end
        ensure
          @output.write "\e[0m\e[?25h\e[?1049l"
          @output.flush
        end
        @output.puts "Projeto salvo: #{@project.path}"
      end

      def handle(key)
        footer = @row == @project.names.length
        case key
        when :left, :right
          move_horizontal(key == :right ? 1 : -1)
        when :up, :down
          if footer && @footer == 0
            @project.change_tempo(key == :up ? 1 : -1)
          elsif key == :up
            @row = [@row - 1, 0].max
          else
            @row = [@row + 1, @project.names.length].min
          end
        when :tab
          if footer
            case @footer
            when 1 then finish
            when 2
              @status = "Gerando áudio..."
              render
              @status = "Áudio gerado: #{@project.generate}"
            end
          else
            @project.toggle(@row, @column)
          end
        when :eof
          finish
        end
      rescue StandardError => exception
        @status = "Erro: #{exception.message}"
      end

      def render
        height, width = @output.winsize
        height = 24 if height < 1
        width = 80 if width < 1
        lines = screen_lines(height, width)
        @output.write "\e[H\e[2J" + lines.join("\r\n")
        @output.flush
      end

      def screen_lines(height, width)
        return ["Aumente o terminal (mínimo 60 x 12)."] if width < 60 || height < 12
        label_width = [@project.names.map(&:length).max, 20].min
        visible_count = [@project.names.length, height - 9].min
        first = [[@row - visible_count + 1, 0].max, @project.names.length - visible_count].min
        lines = ["Beats | #{File.basename(@project.path)}#{@project.dirty ? ' *' : ''}", "-" * (width - 1), "Verse:"]
        @project.names.each_with_index.to_a.slice(first, visible_count).each do |name, index|
          cells = @project.tracks[index].each_with_index.map do |step, position|
            character = step == "X" ? @project.config.active : @project.config.rest
            selected = @row == index && @column == position
            selected ? "\e[7m#{character}\e[0m" : character
          end
          lines << "  - #{name[0, label_width].ljust(label_width)}: #{cells.join(' ')}"
        end
        lines << "  Pistas #{first + 1}-#{first + visible_count}/#{@project.names.length}"
        fields = ["Tempo [#{@project.tempo}]", "[Sair]", "[Gerar]"]
        fields[@footer] = "\e[7m#{fields[@footer]}\e[0m" if @row == @project.names.length
        lines << " " + fields.join("  ")
        lines << "-" * (width - 1)
        lines << "Setas: mover | Tab: alternar/acionar | Tempo: cima/baixo"
        lines << "Tempo: esquerda volta à grade | Ctrl+C: salvar e sair"
        lines << @status.gsub(/[[:cntrl:]]/, " ")[0, width - 1]
        lines
      end

      private

      def finish
        @project.save
        @running = false
      end

      def move_horizontal(delta)
        if @row == @project.names.length
          @footer += delta
          if @footer < 0
            @row, @column, @footer = @project.names.length - 1, Project::STEPS - 1, 0
          elsif @footer > 2
            @row, @column, @footer = 0, 0, 0
          end
        else
          @column += delta
          if @column >= Project::STEPS
            @column = 0
            @row += 1
            @footer = 0
          elsif @column < 0
            if @row == 0
              @row, @column, @footer = @project.names.length, 0, 2
            else
              @row -= 1
              @column = Project::STEPS - 1
            end
          end
        end
      end

      def read_key
        character = @input.getch
        return :eof if character.nil? || character.empty?
        return :tab if character == "\t"
        raise Interrupt if character == "\u0003"
        # io-console and terminal hosts may deliver Windows scan codes or VT sequences.
        if [0, 224].include?(character.bytes.first) && character.bytesize >= 2
          return {72 => :up, 80 => :down, 75 => :left, 77 => :right}[character.bytes[1]]
        end
        if ["\x00", "\xe0".b].include?(character.b)
          return {"H" => :up, "P" => :down, "K" => :left, "M" => :right}[@input.getch]
        end
        if character.bytesize > 1 && character.start_with?("\e")
          return {"A" => :up, "B" => :down, "C" => :right, "D" => :left}[character[-1]]
        end
        if character == "\e"
          prefix = @input.getch
          return unless ["[", "O"].include?(prefix)
          sequence = @input.getch
          sequence = @input.getch until sequence.nil? || sequence.match?(/[A-Za-z~]/)
          return {"A" => :up, "B" => :down, "C" => :right, "D" => :left}[sequence]
        end
        nil
      end
    end
  end
end
