require "beats"
require "io/console"
require "optparse"
require "beats/console/project"
require "beats/console/editor"

module Beats
  module Console
    def self.start(arguments, input: $stdin, output: $stdout, error: $stderr)
      config_path = File.expand_path("../../beats.yml", __dir__)
      parser = OptionParser.new do |options|
        options.banner = "Uso: bundle exec .\\beats [projeto.brf] [--config arquivo.yml]"
        options.on("--config ARQUIVO", "Arquivo de configuração") { |path| config_path = path }
        options.on("-h", "--help", "Mostrar ajuda") { output.puts(options); return 0 }
      end
      paths = parser.parse(arguments)
      raise ArgumentError, parser.to_s if paths.length > 1
      input = IO.console || input if input.equal?($stdin)
      unless input.tty? && output.tty?
        raise ArgumentError, "Abra num terminal interativo. Use --help para ver os comandos."
      end

      config = Configuration.new(config_path)
      project = Project.new(config, paths.first)
      project.validate_samples!
      Editor.new(project, input, output).run
      0
    rescue StandardError => exception
      error.puts "Beats: #{exception.message}"
      1
    end
  end
end
