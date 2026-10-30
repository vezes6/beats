require "includes"
require "tmpdir"
require "fileutils"

class SongDurationTest < Minitest::Test
  SAMPLE_RATE = 44100

  def setup
    @directory = Dir.mktmpdir("beats-duration-")
  end

  def teardown
    FileUtils.remove_entry(@directory)
  end

  def frames(path)
    reader = WaveFile::Reader.new(path)
    reader.total_sample_frames
  ensure
    reader.close if reader
  end

  def test_two_verses_and_two_choruses_end_at_eight_seconds_despite_silent_sample_tail
    [1, 2].each do |channels|
      # A short audible hit followed by almost three seconds of embedded silence.
      hit = channels == 1 ? 1000 : [1000, 1000]
      silence = channels == 1 ? 0 : [0, 0]
      samples = Array.new(2205, hit) + Array.new(SAMPLE_RATE * 3 - 2205, silence)
      kit = Kit.new({"hit" => samples}, channels, 16)
      song = Song.new
      song.tempo = 120
      song.pattern(:verse, [Track.new("hit", "X...............")])
      song.pattern(:chorus, [Track.new("hit", "...............X")])
      song.flow = [:verse, :verse, :chorus, :chorus]

      path = File.join(@directory, "song-#{channels}.wav")
      engine = AudioEngine.new(song, kit)
      engine.write_to_file(path)
      assert_equal SAMPLE_RATE * 8, frames(path)

      extended = File.join(@directory, "extended-#{channels}.wav")
      engine.write_to_file(extended, :preserve_tails => true)
      assert_equal (SAMPLE_RATE * 10.875).to_i, frames(extended)

      # Removing the final tail must not change any audio within the Flow.
      normal_reader = WaveFile::Reader.new(path)
      extended_reader = WaveFile::Reader.new(extended)
      begin
        assert_equal normal_reader.read(SAMPLE_RATE * 8).samples,
                     extended_reader.read(SAMPLE_RATE * 8).samples
      ensure
        normal_reader.close
        extended_reader.close
      end
    end
  end

  def test_sustained_sound_still_crosses_pattern_boundaries
    song = Song.new
    song.tempo = 120
    song.pattern(:verse, [Track.new("hit", "...............X")])
    song.pattern(:chorus, [Track.new("hit", "................")])
    song.flow = [:verse, :chorus]
    kit = Kit.new({"hit" => Array.new(SAMPLE_RATE * 4, 1000)}, 1, 16)
    path = File.join(@directory, "sustain.wav")
    AudioEngine.new(song, kit).write_to_file(path)
    assert_equal SAMPLE_RATE * 4, frames(path)
    reader = WaveFile::Reader.new(path)
    begin
      reader.read(SAMPLE_RATE * 2)
      assert_equal [1000], reader.read(1).samples
    ensure
      reader.close
    end
  end

  def test_runner_with_two_verses_and_one_chorus_ends_at_four_and_a_half_seconds
    # Reproduce TB001's arrangement without depending on an editable user song.
    format = WaveFile::Format.new(1, :pcm_16, SAMPLE_RATE)
    sample_path = File.join(@directory, "ride.wav")
    writer = WaveFile::Writer.new(sample_path, format)
    writer.write(WaveFile::Buffer.new(Array.new(SAMPLE_RATE * 3, 0), format))
    writer.close
    source = File.join(@directory, "song.yaml")
    File.write(source, YAML.dump({
      "Song" => {"Tempo" => 160, "Flow" => [{"Verse" => "x2"}, {"Chorus" => "x1"}],
                 "Kit" => [{"ride" => "ride.wav"}]},
      "Verse" => [{"ride" => "................"}],
      "Chorus" => [{"ride" => "............X..."}]
    }))
    path = File.join(@directory, "TB001_V1.wav")
    BeatsRunner.new(source, path, {}).run
    # Pattern subdivision rounds fractional frames: allow less than 1 ms.
    assert_in_delta 4.5, frames(path).to_f / SAMPLE_RATE, 0.001

    extended = File.join(@directory, "TB001_V1-tails.wav")
    BeatsRunner.new(source, extended, :preserve_tails => true).run
    assert_in_delta 7.125, frames(extended).to_f / SAMPLE_RATE, 0.001
  end

  def test_console_export_obeys_preserve_tails_setting
    require "beats/console"
    sample_path = File.join(@directory, "hit.wav")
    writer = WaveFile::Writer.new(sample_path, WaveFile::Format.new(1, :pcm_16, SAMPLE_RATE))
    writer.write(WaveFile::Buffer.new(Array.new(SAMPLE_RATE * 3, 1000), writer.format))
    writer.close
    settings = {
      "Indicators" => {"Active" => "X", "Rest" => "="},
      "SamplesPath" => @directory, "ProjectsPath" => @directory, "AudioPath" => @directory,
      "Kit" => [{"hit" => "hit.wav"}],
      "Default" => {"Tempo" => 120, "Verse" => [{"hit" => "...............X"}]}
    }
    config_path = File.join(@directory, "beats.yml")
    [false, true].each do |preserve|
      settings["PreserveTails"] = preserve
      File.write(config_path, YAML.dump(settings))
      config = Beats::Console::Configuration.new(config_path)
      project = Beats::Console::Project.new(config)
      assert_equal (SAMPLE_RATE * (preserve ? 4.875 : 2)).to_i, frames(project.generate)
    end
  end
end
