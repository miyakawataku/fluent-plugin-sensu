# -*- encoding: utf-8 -*-
# vim: et sw=2 sts=2

module Fluent

  # Fluentd output plugin to send checks to sensu-client.
  class SensuOutput < Fluent::BufferedOutput
    Fluent::Plugin.register_output('sensu', self)

    #
    # Config parameters
    #

    # The IP address or the hostname of the host running sensu-client.
    config_param :server, :string, :default => 'localhost'

    # The port to which sensu-client is listening.
    config_param :port, :integer, :default => 3030

    # "name" attribute: default = tag if valid, or "fluent-plugin-sensu"
    config_param :check_name, :string, :default => nil
    config_param :check_name_field, :string, :default => nil

    CHECK_NAME_PATTERN = /\A[\w.-]+\z/

    # Load modules.
    private
    def initialize
      super
      require 'json'
    end

    # Read and validate the configuration.
    public
    def configure(conf)
      super
      reject_invalid_check_name
    end

    # Reject check_name option if invalid
    private
    def reject_invalid_check_name
      if @check_name && @check_name !~ CHECK_NAME_PATTERN
        raise ConfigError,
          "check_name must be a string consisting of one or more" +
          " ASCII alphanumerics, underscores, periods, and hyphens"
      end
    end

    # Pack the tuple (tag, time, record).
    public
    def format(tag, time, record)
      [tag, time, record].to_msgpack
    end

    # Send a check
    public
    def write(chunk)
      results = []
      chunk.msgpack_each { |(tag, time, record)|
        payload = {
          'name' => determine_check_name(tag, record),
          'output' => record.to_json,
          'status' => 3,
          'type' => 'standard',
          'handlers' => ['default'],
          'executed' => time,
          'fluentd_tag' => tag,
          'fluentd_time' => time.to_i,
          'fluentd_record' => record,
        }
        send_check(@server, @port, payload)
      }
    end

    # Determines "name" attribute of a check.
    private
    def determine_check_name(tag, record)
      # Field specified by check_name_field option
      if @check_name_field
        check_name = record[@check_name_field]
        if check_name =~ CHECK_NAME_PATTERN
          return record[@check_name_field]
        else
          log.warn('Invalid check name in the field.' +
                   ' Fallback to check_name option, tag,' +
                   ' or constant "fluent-plugin-sensu".',
                   :tag => tag,
                   :check_name_field => @check_name_field,
                   :value => check_name)
          # Fall through
        end
      end

      # check_name option
      if @check_name
        return @check_name
      end

      # Tag
      if tag =~ CHECK_NAME_PATTERN
        return tag
      end

      # Default value
      log.warn('Invalid check name in the tag.' +
               'Fallback to the constant "fluent-plugin-sensu".',
               :tag => tag)
      return 'fluent-plugin-sensu'
    end

    # Send a check to sensu-client.
    public
    def send_check(server, port, payload)
      json = payload.to_json
      sensu_client = TCPSocket.open(@server, @port)
      begin
        sensu_client.puts(json)
      ensure
        sensu_client.close
      end
    end

  end

end
