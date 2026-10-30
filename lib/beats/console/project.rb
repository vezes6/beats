require "yaml"
require "fileutils"
require "pathname"
require "tempfile"

module Beats
  module Console
    class Configuration
      attr_reader :active, :rest, :samples_path, :projects_path, :audio_path,
                  :audio_file, :kit, :defaults, :preserve_tails, :trim_leading_silence

      def initialize(path)
        path = File.expand_path(path)
        data = YAML.safe_load(File.read(path), aliases: false)
        raise ArgumentError, "Configuração deve ser um mapa YAML." unless data.is_a?(Hash)
        indicators = data.fetch("Indicators")
        @active, @rest = indicators.fetch("Active"), indicators.fetch("Rest")
        unless [@active, @rest].all? { |value| value.is_a?(String) && value.match?(/\A[!-~]\z/) } && @active != @rest
          raise ArgumentError, "Indicadores devem ser caracteres ASCII visíveis e diferentes."
        end
        root = File.dirname(path)
        @samples_path = resolve_path(data.fetch("SamplesPath"), root)
        @projects_path = resolve_path(data.fetch("ProjectsPath"), root)
        @audio_path = resolve_path(data.fetch("AudioPath"), root)
        @audio_file = data["AudioFile"]
        @preserve_tails = data.fetch("PreserveTails", false)
        unless @preserve_tails == true || @preserve_tails == false
          raise ArgumentError, "PreserveTails deve ser true ou false."
        end
        @trim_leading_silence = data.fetch("TrimLeadingSilence", true)
        unless @trim_leading_silence == true || @trim_leading_silence == false
          raise ArgumentError, "TrimLeadingSilence deve ser true ou false."
        end
        if @audio_file
          @audio_file = resolve_path(@audio_file, @audio_path)
          raise ArgumentError, "AudioFile deve ter extensão .wav." unless File.extname(@audio_file).downcase == ".wav"
        end
        @kit = data.fetch("Kit")
        @defaults = data.fetch("Default")
      end

      private

      def resolve_path(value, root)
        raise ArgumentError, "Caminho inválido na configuração." unless value.is_a?(String) && !value.empty?
        File.expand_path(value, root)
      end
    end

    class Project
      STEPS = 16
      attr_reader :path, :names, :tracks, :kit, :samples_path, :config, :tempo
      attr_accessor :dirty

      def initialize(config, requested_path = nil)
        @config = config
        if requested_path
          @path = File.expand_path(requested_path)
          @path = File.expand_path(requested_path, config.projects_path) unless File.file?(@path)
          raise ArgumentError, "Projeto deve ter extensão .brf." unless File.extname(@path).downcase == ".brf"
          data = YAML.safe_load(File.read(@path), aliases: false)
          raise ArgumentError, "Projeto deve ser um mapa YAML." unless data.is_a?(Hash)
          unless data.keys.sort == ["Song", "Verse"]
            raise ArgumentError, "Esta versão aceita somente Song e um padrão Verse."
          end
          header = data.fetch("Song")
          unless header.fetch("Flow") == [{"Verse" => "x1"}]
            raise ArgumentError, "Esta versão requer Flow: [{Verse: x1}]."
          end
          @kit = normalize_kit(header.fetch("Kit"))
          @samples_path = File.expand_path(header.fetch("SamplesPath", config.samples_path), File.dirname(@path))
          self.tempo = header.fetch("Tempo")
          read_tracks(data.fetch("Verse"))
          @dirty = false
        else
          @path = next_project_path
          @kit = normalize_kit(config.kit)
          @samples_path = config.samples_path
          self.tempo = config.defaults.fetch("Tempo")
          read_tracks(config.defaults.fetch("Verse"))
          @dirty = true
        end
      end

      def tempo=(value)
        unless value.is_a?(Integer) && value.between?(1, 999)
          raise ArgumentError, "Tempo deve ser um inteiro entre 1 e 999 BPM."
        end
        @tempo = value
      end

      def change_tempo(delta)
        value = [[tempo + delta, 1].max, 999].min
        @dirty = true if value != tempo
        self.tempo = value
      end

      def toggle(row, column)
        @tracks[row][column] = @tracks[row][column] == "X" ? "." : "X"
        @dirty = true
      end

      def audio_path
        config.audio_file || File.join(config.audio_path, File.basename(path, File.extname(path)) + ".wav")
      end

      def save
        # These validated 16-step strings are safe YAML plain scalars. Writing
        # Verse explicitly keeps dot-leading rhythms readable without quotes.
        text = YAML.dump({"Song" => document.fetch("Song")}) + "Verse:\n"
        names.each_with_index do |name, index|
          text += "- #{name}: #{tracks[index].join}\n"
        end
        atomic_write(path) { |temporary| File.write(temporary, text) }
        @dirty = false
        path
      end

      def generate
        song, sounds = parsed_song
        atomic_write(audio_path) do |temporary|
          AudioEngine.new(song, sounds).write_to_file(temporary, :preserve_tails => config.preserve_tails)
        end
        audio_path
      end

      def validate_samples!
        parsed_song
        true
      end

      def document
        relative_samples = begin
          Pathname.new(samples_path).relative_path_from(Pathname.new(File.dirname(path))).to_s
        rescue ArgumentError
          samples_path
        end
        {
          "Song" => {"Tempo" => tempo, "Flow" => [{"Verse" => "x1"}],
                     "SamplesPath" => relative_samples, "Kit" => kit.map { |name, file| {name => file} }},
          "Verse" => names.each_with_index.map { |name, index| {name => tracks[index].join} }
        }
      end

      private

      def next_project_path
        index = 1
        loop do
          name = "projeto_#{index}"
          candidate = File.join(config.projects_path, name + ".brf")
          return candidate unless File.exist?(candidate) || File.exist?(File.join(config.audio_path, name + ".wav"))
          index += 1
        end
      end

      def normalize_kit(value)
        entries = value.is_a?(Hash) ? value.map { |name, file| {name => file} } : value
        unless entries.is_a?(Array) && !entries.empty? && entries.all? { |entry| entry.is_a?(Hash) && entry.size == 1 }
          raise ArgumentError, "Kit deve conter instrumentos e seus arquivos WAV."
        end
        result = {}
        entries.each do |entry|
          name, file = entry.first
          unless name.is_a?(String) && name.match?(/\A[a-zA-Z][a-zA-Z0-9_-]*\z/) && file.is_a?(String) && !file.empty?
            raise ArgumentError, "Kit inválido: use nomes simples e caminhos de samples WAV."
          end
          raise ArgumentError, "Instrumento repetido: #{name}." if result.key?(name)
          result[name] = file
        end
        result
      end

      def read_tracks(value)
        unless value.is_a?(Array) && !value.empty? && value.all? { |entry| entry.is_a?(Hash) && entry.size == 1 }
          raise ArgumentError, "Verse deve conter uma lista de pistas."
        end
        @names, @tracks = [], []
        value.each do |entry|
          name, rhythm = entry.first
          raise ArgumentError, "Pista desconhecida ou repetida: #{name}." unless kit.key?(name) && !names.include?(name)
          unless rhythm.is_a?(String) && rhythm.match?(/\A[X. |]+\z/) && rhythm.delete(" |").length == STEPS
            raise ArgumentError, "A pista #{name} deve conter 16 passos usando X e ."
          end
          @names << name
          @tracks << rhythm.delete(" |").chars
        end
      end

      def parsed_song
        # The original parser understands X/.; screen indicators never enter the audio engine.
        SongParser.parse(samples_path, YAML.dump(document),
                         :trim_leading_silence => config.trim_leading_silence)
      end

      def atomic_write(destination)
        FileUtils.mkdir_p(File.dirname(destination))
        temporary = Tempfile.new([".beats-", File.extname(destination)], File.dirname(destination))
        temporary.close
        begin
          yield temporary.path
          File.rename(temporary.path, destination)
        ensure
          temporary.close!
        end
      end
    end
  end
end
