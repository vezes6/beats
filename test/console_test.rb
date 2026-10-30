require "includes"
require "beats/console"
require "tmpdir"
require "stringio"

class ConsoleTest < Minitest::Test
  def setup
    @directory = Dir.mktmpdir("beats-console-")
    @settings = {
      "Indicators" => {"Active" => "O", "Rest" => "-"},
      "SamplesPath" => File.expand_path("sounds", __dir__),
      "ProjectsPath" => "projects", "AudioPath" => "audio",
      "Kit" => [{"bass" => "bass_mono_16.wav"}, {"snare" => "snare_mono_16.wav"}],
      "Default" => {"Tempo" => 160, "Verse" => [
        {"bass" => "X.......X......."}, {"snare" => "....X.......X..."}
      ]}
    }
    configure
  end

  def teardown
    FileUtils.remove_entry(@directory)
  end

  def configure
    @config_path = File.join(@directory, "beats.yml")
    File.write(@config_path, YAML.dump(@settings))
    @config = Beats::Console::Configuration.new(@config_path)
    @project = Beats::Console::Project.new(@config)
  end

  def editor(project = @project)
    Beats::Console::Editor.new(project, StringIO.new, StringIO.new)
  end

  def test_default_uses_config_paths_and_skips_existing_audio_names
    assert_equal File.join(@directory, "projects", "projeto_1.brf"), @project.path
    FileUtils.mkdir_p(@config.audio_path)
    File.write(@project.audio_path, "existing audio")
    next_project = Beats::Console::Project.new(@config)
    assert_equal "projeto_2.brf", File.basename(next_project.path)
    assert_equal "existing audio", File.read(@project.audio_path)
  end

  def test_round_trip_preserves_kit_samples_and_edits
    @project.toggle(0, 1)
    @project.change_tempo(1)
    @project.save
    # A project carries its own kit and sample location even when defaults change.
    @settings["Kit"] = [{"other" => "missing.wav"}]
    @settings["SamplesPath"] = "elsewhere"
    File.write(@config_path, YAML.dump(@settings))
    config = Beats::Console::Configuration.new(@config_path)
    reopened = Beats::Console::Project.new(config, "projeto_1.brf")
    assert_equal @project.tracks, reopened.tracks
    assert_equal 161, reopened.tempo
    assert_equal @project.kit, reopened.kit
    assert_equal @project.samples_path, reopened.samples_path
    assert reopened.validate_samples!
    refute reopened.dirty
    reopened.toggle(1, 0)
    reopened.save
    assert_equal reopened.tracks, Beats::Console::Project.new(config, reopened.path).tracks
  end

  def test_generate_uses_unsaved_screen_edits_and_overwrites_wav
    @project.generate
    original = File.binread(@project.audio_path)
    @project.toggle(0, 0)
    @project.generate
    refute_equal original, File.binread(@project.audio_path)
    refute File.exist?(@project.path)
    reader = WaveFile::Reader.new(@project.audio_path)
    assert_equal 44100, reader.format.sample_rate
    assert reader.total_sample_frames > 0
    reader.close
  end

  def test_fixed_audio_filename
    @settings["AudioFile"] = "fixed.wav"
    configure
    assert_equal File.join(@directory, "audio", "fixed.wav"), @project.generate
  end

  def test_generation_failure_keeps_existing_audio
    @project.generate
    original = File.binread(@project.audio_path)
    @project.kit["bass"] = "missing.wav"
    assert_raises(Beats::SongParser::ParseError) { @project.generate }
    assert_equal original, File.binread(@project.audio_path)
  end

  def test_partial_write_failure_keeps_previous_project_and_cleans_temporary_file
    @project.save
    original = File.binread(@project.path)
    assert_raises(IOError) do
      @project.send(:atomic_write, @project.path) do |temporary|
        File.write(temporary, "incomplete")
        raise IOError, "disk full"
      end
    end
    assert_equal original, File.binread(@project.path)
    assert_empty Dir.glob(File.join(@config.projects_path, ".beats-*"))
  end

  def test_rendering_and_terminal_restoration_in_full_editor_loop
    console = Object.new
    keys = ["\xe0M".b, "\t", "\u0003"]
    console.define_singleton_method(:getch) { keys.shift }
    output = StringIO.new
    output.define_singleton_method(:winsize) { [24, 80] }
    Beats::Console::Editor.new(@project, console, output).run
    assert_equal "X", @project.tracks[0][1]
    assert File.file?(@project.path)
    assert_includes output.string, "\e[7m"
    assert_includes output.string, "\e[?25h\e[?1049l"
  end

  def test_invalid_project_is_rejected_without_overwriting
    @project.save
    data = @project.document
    data["Verse"][0]["bass"] = "X..."
    File.write(@project.path, YAML.dump(data))
    original = File.read(@project.path)
    assert_raises(ArgumentError) { Beats::Console::Project.new(@config, @project.path) }
    assert_equal original, File.read(@project.path)
    data["Verse"][0]["bass"] = "X..............."
    data["Song"]["Flow"] = [{"Verse" => "x2"}]
    File.write(@project.path, YAML.dump(data))
    assert_raises(ArgumentError) { Beats::Console::Project.new(@config, @project.path) }
  end

  def test_indicators_must_be_distinct_and_not_control_characters
    @settings["Indicators"]["Rest"] = "O"
    assert_raises(ArgumentError) { configure }
    @settings["Indicators"]["Rest"] = "\e"
    assert_raises(ArgumentError) { configure }
  end

  def test_keyboard_edits_only_selected_cell_and_tempo
    view = editor
    view.handle(:right)
    view.handle(:tab)
    assert_equal "X", @project.tracks[0][1]
    assert_equal ".", @project.tracks[1][1]
    2.times { view.handle(:down) }
    view.handle(:up)
    assert_equal 161, @project.tempo
    view.handle(:down)
    assert_equal 160, @project.tempo
    view.handle(:left)
    assert_equal [1, 15], [view.row, view.column]
    assert editor.screen_lines(24, 80).join.include?("O - - -")
  end

  def test_tempo_limits
    @project.tempo = 1
    @project.change_tempo(-1)
    assert_equal 1, @project.tempo
    @project.tempo = 999
    @project.change_tempo(1)
    assert_equal 999, @project.tempo
  end

  def test_tab_on_exit_saves_and_save_failure_keeps_editor_open
    view = editor
    2.times { view.handle(:down) }
    view.handle(:right)
    view.handle(:tab)
    assert File.file?(@project.path)
    refute view.instance_variable_get(:@running)

    view = editor
    @project.define_singleton_method(:save) { raise IOError, "sem permissão" }
    2.times { view.handle(:down) }
    view.handle(:right)
    view.handle(:tab)
    assert view.instance_variable_get(:@running)
    assert_includes view.status, "sem permissão"
  end

  def test_arrow_decoding_for_terminal_and_windows_scan_codes
    fake = Object.new
    keys = ["\e", "[", "A", "\e", "O", "D", "\x00", "P", "\xe0".b, "M", "\t",
            "\xe0H".b, "\xe0P".b, "\xe0K".b, "\xe0M".b, "\e[C"]
    fake.define_singleton_method(:getch) { keys.shift }
    view = Beats::Console::Editor.new(@project, fake, StringIO.new)
    assert_equal [:up, :left, :down, :right, :tab], 5.times.map { view.send(:read_key) }
    assert_equal [:up, :down, :left, :right, :right], 5.times.map { view.send(:read_key) }
  end

  def test_small_terminal_and_long_track_list
    view = editor
    assert_match(/Aumente/, view.screen_lines(10, 40).join)
    assert_operator view.screen_lines(12, 60).length, :<=, 12
  end
end
