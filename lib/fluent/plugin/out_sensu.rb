# -*- encoding: utf-8 -*-
# vim: et sw=2 sts=2

module Fluent

  # Fluentd output plugin to send checks to sensu-client.
  class SensuOutput < Fluent::BufferedOutput
    Fluent::Plugin.register_output('sensu', self)

    private
    def self.to_status(status_val)
      status_str = status_val.to_s
      return 0 if status_str =~ OK_PATTERN
      return 1 if status_str =~ WARNING_PATTERN
      return 2 if status_str =~ CRITICAL_PATTERN
      return 3 if status_str =~ UNKNOWN_PATTERN
      return nil
    end

    #
    # Config parameters
    #

    # The IP address or the hostname of the host running sensu-client.
    config_param :server, :string, :default => 'localhost'

    # The port to which sensu-client is listening.
    config_param :port, :integer, :default => 3030

    # Options for "name" attribute.
    config_param :check_name, :string, :default => nil
    config_param :check_name_field, :string, :default => nil
    CHECK_NAME_PATTERN = /\A[\w.-]+\z/

    # Options for "output" attribute.
    config_param :check_output_field, :string, :default => nil
    config_param :check_output, :string, :default => nil

    # Options for "status" attribute.
    config_param :check_status_field, :string, :default => nil
    config_param(:check_status, :default => 3) { |status_str|
      check_status = SensuOutput.to_status(status_str)
      if not check_status
        raise Fluent::ConfigError,
          "invalid 'check_status': #{status_str}; 'check_status' must be" +
          " 0/1/2/3, OK/WARNING/CRITICAL/CUSTOM, warn/crit"
      end
      check_status
    }
    OK_PATTERN = /\A(0|OK)\z/i
    WARNING_PATTERN = /\A(1|WARNING|warn)\z/i
    CRITICAL_PATTERN = /\A(2|CRITICAL|crit)\z/i
    UNKNOWN_PATTERN = /\A(3|UNKNOWN|CUSTOM)\z/i

    # Option for "type" attribute.
    config_param(:check_type, :default => 'standard') { |check_type|
      if not ['standard', 'metric'].include?(check_type)
        raise Fluent::ConfigError,
          "invalid 'check_type': #{check_type}; 'check_type' must be" +
          ' either "standard" or "metric".'
      end
      check_type
    }

    # Option for "ttl" attribute.
    config_param :check_ttl, :integer, :default => nil

    # Option for "handlers" attribute.
    config_param(:check_handlers, :default => ['default']) { |handlers_str|
      error_message = "invalid 'check_handlers': #{handlers_str};" +
                      " 'check_handlers' must be an array of strings."
      obj = JSON.load(handlers_str)
      if not obj.is_a?(Array)
        raise Fluent::ConfigError, error_message
      end
      array = obj
      all_string_elements = array.all? { |e| e.is_a?(String) }
      if not all_string_elements
        raise Fluent::ConfigError, error_message
      end
      array
    }

    # Options for flapping thresholds.
    config_param :check_low_flap_threshold, :integer, :default => nil
    config_param :check_high_flap_threshold, :integer, :default => nil

    # Options for "source" attribute.
    config_param :check_source_field, :string, :default => nil
    config_param :check_source, :string, :default => nil

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
      reject_invalid_flapping_thresholds
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

    # Reject invalid check_low_flap_threshold and check_high_flap_threshold
    private
    def reject_invalid_flapping_thresholds
      if @check_low_flap_threshold.nil? ^ @check_high_flap_threshold.nil?
        raise ConfigError,
          "'check_low_flap_threshold' and 'check_high_flap_threshold'" +
          " specified togher, or not specified at all."
      end
      if @check_low_flap_threshold
        in_order = 0 <= @check_low_flap_threshold &&
          @check_low_flap_threshold <= @check_high_flap_threshold &&
          @check_high_flap_threshold <= 100
        if not in_order
          raise ConfigError,
            "the following condition must be true:" +
            " 0 <= check_low_flap_threshold <= check_high_flap_threshold <= 100"
        end
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
          'output' => determine_output(record),
          'status' => determine_status(record),
          'type' => @check_type,
          'handlers' => @check_handlers,
          'executed' => time,
          'fluentd' => {
            'tag' => tag,
            'time' => time.to_i,
            'record' => record,
          },
        }
        add_attribute_if_present(
          payload, 'ttl', @check_ttl)
        add_attribute_if_present(
          payload, 'low_flap_threshold', @check_low_flap_threshold)
        add_attribute_if_present(
          payload, 'high_flap_threshold', @check_high_flap_threshold)
        add_attribute_if_present(
          payload, 'source', determine_source(record))
        send_check(@server, @port, payload)
      }
    end

    private
    def add_attribute_if_present(payload, name, value)
      if value
        payload[name] = value
      end
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

    # Determines "output" attribute of a check.
    private
    def determine_output(record)
      # Read from the field
      if @check_output_field
        check_output = record[@check_output_field]
        if check_output
          return check_output
        end
        # Fall through
      end
      # Returns the option value
      if @check_output
        return @check_output
      end
      # Default to JSON notation of the record
      return record.to_json
    end

    # Determines "status" attribute of a check.
    private
    def determine_status(record)
      # Read from the field
      if @check_status_field
        status_field_val = record[@check_status_field]
        if status_field_val
          check_status = SensuOutput.to_status(status_field_val)
          return check_status if check_status
        end
      end
      # Returns the default
      return @check_status
    end

    private
    def determine_source(record)
      if @check_source_field
        source = record[@check_source_field]
        return source if source
      end
      return @check_source
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
