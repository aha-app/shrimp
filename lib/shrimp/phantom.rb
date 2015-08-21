require 'uri'
require 'json'
require 'digest'

module Shrimp
  class NoExecutableError < StandardError
    def initialize(phantom_location=nil)
      msg = "No phantomjs executable found at #{phantom_location}\n"
      msg << ">> Please install phantomjs - http://phantomjs.org/download.html"
      super(msg)
    end
  end

  class ImproperSourceError < StandardError
    def initialize(msg=nil)
      super("Improper Source: #{msg}")
    end
  end

  class RenderingError < StandardError
    def initialize(msg=nil)
      super("Rendering Error: #{msg}")
    end
  end

  class Phantom
    include Dir::Tmpname
    
    attr_accessor :source, :configuration, :outfile, :executable
    attr_reader :options, :cookies, :result, :error
    SCRIPT_FILE = File.expand_path('../rasterize.js', __FILE__)
    
    def self.default_executable
      (defined?(Bundler::GemfileError) ?  
       `bundle exec which phantomjs` : 
       `which phantomjs`).chomp
    end

    # Public: initializes a new Phantom Object
    #
    # url_or_file - The url of the html document to render
    # options     - a hash with options for rendering
    #   * format  - the paper format for the output eg: "5in*7.5in", 
    #               "10cm*20cm", "A4", "Letter"
    #   * zoom    - the viewport zoom factor
    #   * margin  - the margins for the pdf
    # cookies     - hash with cookies to use for rendering
    #
    # Returns self
    def initialize(url_or_file, options = {}, cookies={})
      @source  = Source.new(url_or_file)
      @options = Shrimp.configuration.options.merge(options)
      @cookies = cookies
      @executable = @options[:phantomjs] || self.default_executable
      raise NoExecutableError.new unless File.exists?(@executable)
    end

    # Public: Runs the phantomjs binary
    #
    # Returns the stdout output of phantomjs
    def run
      @error = nil
      cmd_to_run = cmd
      puts cmd_to_run
      @result = `/bin/bash -c "#{cmd_to_run}"`
      puts @result
      unless $?.exitstatus == 0
        @error  = @result
        @result = nil
        raise RenderingError.new(@error) unless options[:fail_silently]
      end
    end

    # Public: Returns the phantom rasterize command
    def cmd
      args = @options.slice(*command_line_options)
      args[:cookies] = dump_cookies
      args[:input] = @source.to_s
      @outfile_path = temp_file_path('shrimp_output', ".#{@options[:output_format]}")
      args[:output] = @outfile_path
      
      arg_list = args.map {|key, value| "-#{key} '#{value}'" }
      
      [@executable, "--ssl-protocol=any --ignore-ssl-errors=true", SCRIPT_FILE, arg_list].flatten.join(" ")
    end

    # Public: renders to PDF. Returns file handle to generated PDF.
    def to_pdf
      @options[:output_format] = "pdf"
      self.run
      File.open(@outfile_path)
    end

    # Public: renders to PNG. Returns file handle to generated PNG.
    def to_png
      @options[:output_format] = "png"
      self.run
      File.open(@outfile_path)
    end

  private
    
    def command_line_options
      [:format, :zoom, :margin, :orientation, :rendering_time, :output_format, 
        :clip_height, :html_output, :header, :header_height, :footer, :footer_height]
    end

    def dump_cookies
      host = @source.url? ? URI::parse(@source.to_s).host : "/"
      json = @cookies.inject([]) { |a, (k, v)| 
          a.push({ :name => k, :value => v, :domain => host }); a 
        }.to_json
      @cookies_file = Tempfile.new(["shrimp", ".cookies"])
      @cookies_file.puts(json)
      @cookies_file.fsync
      @cookies_file.path
    end
    
    def temp_file_path(name, suffix)
      create([name, suffix]) {|tmpname| tmpname }
    end
    
  end
end
