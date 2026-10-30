require "includes"
require "beats/console"
require "tmpdir"
require "fileutils"

class SampleAlignmentTest < Minitest::Test
  def setup
    @directory = Dir.mktmpdir("beats-alignment-")
  end

  def teardown
    FileUtils.remove_entry(@directory)
  end

  def write_sample(name, samples, channels = 1)
    path = File.join(@directory, name)
    format = WaveFile::Format.new(channels, :pcm_16, 44100)
    writer = WaveFile::Writer.new(path, format)
    writer.write(WaveFile::Buffer.new(samples, format))
    writer.close
    path
  end

  def test_alignment_removes_quiet_preroll_and_preserves_original_file
    path = write_sample("hit.wav", [0, 0, 2, -2, 1000, 500, 0])
    original = File.binread(path)
    plain = KitBuilder.new(@directory)
    plain.add_item("hit", "hit.wav")
    assert_equal [0, 0, 2, -2, 1000, 500, 0], plain.build_kit.get_sample_data("hit")

    aligned = KitBuilder.new(@directory, :trim_leading_silence => true)
    aligned.add_item("hit", "hit.wav")
    assert_equal [1000, 500, 0], aligned.build_kit.get_sample_data("hit")
    assert_equal original, File.binread(path)
  end

  def test_stereo_channels_are_aligned_together_using_either_channels_attack
    write_sample("stereo.wav", [[0, 0], [0, 2], [0, 1000], [400, 500]], 2)
    builder = KitBuilder.new(@directory, :trim_leading_silence => true)
    builder.add_item("hit", "stereo.wav")
    assert_equal [[0, 1000], [400, 500]], builder.build_kit.get_sample_data("hit")
  end

  def test_silent_samples_and_samples_without_preroll_are_preserved
    write_sample("silent.wav", [0, 0, 0])
    write_sample("hit.wav", [1000, 500, 0])
    builder = KitBuilder.new(@directory, :trim_leading_silence => true)
    builder.add_item("silent", "silent.wav")
    builder.add_item("hit", "hit.wav")
    kit = builder.build_kit
    assert_equal [0, 0, 0], kit.get_sample_data("silent")
    assert_equal [1000, 500, 0], kit.get_sample_data("hit")
  end

  def test_console_places_delayed_snare_attacks_on_requested_steps
    write_sample("snare.wav", Array.new(8350, 0) + Array.new(441, 1000))
    settings = {
      "Indicators" => {"Active" => "X", "Rest" => "="},
      "SamplesPath" => @directory, "ProjectsPath" => @directory, "AudioPath" => @directory,
      "Kit" => [{"snare" => "snare.wav"}],
      "Default" => {"Tempo" => 120, "Verse" => [{"snare" => "....X.......X..."}]}
    }
    config_path = File.join(@directory, "beats.yml")
    File.write(config_path, YAML.dump(settings))
    config = Beats::Console::Configuration.new(config_path)
    project = Beats::Console::Project.new(config)
    reader = WaveFile::Reader.new(project.generate)
    samples = reader.read(reader.total_sample_frames).samples
    reader.close
    assert_equal 88200, samples.length
    assert_equal 22050, samples.index { |sample| sample != 0 }
    assert_equal 1000, samples[66150]
    assert_equal 882, samples.count { |sample| sample != 0 }

    settings["TrimLeadingSilence"] = false
    File.write(config_path, YAML.dump(settings))
    original = Beats::Console::Project.new(Beats::Console::Configuration.new(config_path))
    reader = WaveFile::Reader.new(original.generate)
    samples = reader.read(reader.total_sample_frames).samples
    reader.close
    assert_equal 22050 + 8350, samples.index { |sample| sample != 0 }
  end

  def test_project_patterns_are_saved_without_quotes_and_round_trip_unchanged
    settings = {
      "Indicators" => {"Active" => "X", "Rest" => "="},
      "SamplesPath" => @directory, "ProjectsPath" => @directory, "AudioPath" => @directory,
      "Kit" => [{"bass" => "hit.wav"}, {"snare" => "hit.wav"}, {"hat" => "hit.wav"}],
      "Default" => {"Tempo" => 120, "Verse" => [
        {"bass" => "X.......X......."}, {"snare" => "....X.......X..."}, {"hat" => "................"}
      ]}
    }
    config_path = File.join(@directory, "beats.yml")
    File.write(config_path, YAML.dump(settings))
    config = Beats::Console::Configuration.new(config_path)
    project = Beats::Console::Project.new(config)
    project.save
    text = File.read(project.path)
    assert_includes text, "- snare: ....X.......X..."
    assert_includes text, "- hat: ................"
    assert_equal project.document, YAML.safe_load(text)
    assert_equal project.tracks, Beats::Console::Project.new(config, project.path).tracks
  end
end
