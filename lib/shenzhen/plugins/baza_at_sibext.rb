require 'json'
require 'faraday'
require 'faraday_middleware'

module Shenzhen::Plugins
  module Baza_at_sibext
    class Client
      HOSTNAME = 'baza.sibext.com'

      def initialize(app_id, api_key)
        @app_id, @api_key = app_id, api_key
        @connection = Faraday.new(:url => "http://#{HOSTNAME}", :request => { :timeout => 480 }) do |builder|
          builder.request :multipart
          builder.request :json
          builder.response :json, :content_type => /\bjson$/
          builder.basic_auth @app_id, @api_key
          builder.adapter :net_http
        end
      end

      def upload_build(ipa, options)
        options.update({
          :file => Faraday::UploadIO.new(ipa, 'application/octet-stream'),
          :version => options[:version] || '',
          :identifier => options[:identifier] || ''
        })

        @connection.post("/api/upload", options).on_complete do |env|
          yield env[:status], env[:body] if block_given?
        end

      rescue Faraday::Error::TimeoutError
        say_error "Timed out while uploading build. Check https://baza.sibext.ru/ to see if the upload was completed." and abort
      end
    end
  end
end

command :'distribute:baza_at_sibext' do |c|
  c.syntax = "ipa distribute:baza_at_sibext [options]"
  c.summary = "Distribute an .ipa file over baza"
  c.description = ""
  c.option '-f', '--file FILE', ".ipa file for the build"
  c.option '-a', '--app_id TOKEN', "API Token. Available at https://baza.sibext.ru/admin"
  c.option '-u', '--api_key API_KEY', "User Name. Available at https://baza.sibext.ru/admin"
  c.option '-b', '--version VERSION', "version .apk or .ipa"
  c.option '-i', '--identifier IDENTIFIER', "identifier .apk or .ipa"

  c.action do |args, options|
    determine_file! unless @file = options.file
    say_error "Missing or unspecified .ipa or .apk file file" and abort unless @file and File.exist?(@file)

    determine_baza_app_id! unless @app_id = options.app_id || ENV['BAZA_APP_ID']
    say_error "Missing API Token" and abort unless @app_id

    determine_baza_api_key! unless @api_key = options.api_key || ENV['BAZA_API_KEY']
    say_error "Missing User Name" and abort unless @app_id

    @identifier = options.identifier
    @version = options.version

    parameters = {}
    parameters[:version] = @version if @version
    parameters[:identifier] = @identifier if @identifier

    client = Shenzhen::Plugins::Baza_at_sibext::Client.new(@app_id, @api_key)
    response = client.upload_build(@file, parameters)
    if (200...300) === response.status and not response.body["error"]
      say_ok "Build successfully uploaded to Baza"
    else
      say_error "Error uploading to Baza: #{response.body["error"] || "(Unknown Error)"}" and abort
    end
  end

  private

  def determine_baza_app_id!
    @app_id ||= ask "APP ID:"
  end

  def determine_baza_api_key!
    @api_key ||= ask "API KEY:"
  end
end
