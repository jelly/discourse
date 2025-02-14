# frozen_string_literal: true

require_dependency 'compression/engine'

module ThemeStore; end

class ThemeStore::ZipImporter

  attr_reader :url

  def initialize(filename, original_filename)
    @temp_folder = "#{Pathname.new(Dir.tmpdir).realpath}/discourse_theme_#{SecureRandom.hex}"
    @filename = filename
    @original_filename = original_filename
  end

  def import!
    FileUtils.mkdir(@temp_folder)

    Dir.chdir(@temp_folder) do
      Compression::Engine.engine_for(@original_filename).tap do |engine|
        engine.decompress(@temp_folder, @filename)
      end

      # --strip 1 equivalent
      FileUtils.mv(Dir.glob("#{@temp_folder}/*/*"), @temp_folder)
    end
  rescue RuntimeError
    raise RemoteTheme::ImportError, I18n.t("themes.import_error.unpack_failed")
  rescue Compression::Zip::ExtractFailed
    raise RemoteTheme::ImportError, I18n.t("themes.import_error.file_too_big")
  end

  def cleanup!
    FileUtils.rm_rf(@temp_folder)
  end

  def version
    ""
  end

  def real_path(relative)
    fullpath = "#{@temp_folder}/#{relative}"
    return nil unless File.exist?(fullpath)

    # careful to handle symlinks here, don't want to expose random data
    fullpath = Pathname.new(fullpath).realpath.to_s

    if fullpath && fullpath.start_with?(@temp_folder)
      fullpath
    else
      nil
    end
  end

  def all_files
    Dir.chdir(@temp_folder) do
      Dir.glob("**/**").reject { |f| File.directory?(f) }
    end
  end

  def [](value)
    fullpath = real_path(value)
    return nil unless fullpath
    File.read(fullpath)
  end

end
