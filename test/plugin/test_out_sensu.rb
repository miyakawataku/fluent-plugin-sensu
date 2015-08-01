# -*- encoding: utf-8 -*-
# vim: et sw=2 sts=2 fdm=marker

require 'helper'

# Test class for Fluent::SensuOutput
class SensuOutputTest < Test::Unit::TestCase

  # Setup {{{1

  # Sets up the test env and the stub
  def setup
    Fluent::Test.setup
  end

  # Returns a driver of the plugin
  def create_driver(conf, tag = 'test')
    driver = Fluent::Test::BufferedOutputTestDriver.new(Fluent::SensuOutput, tag)
    driver.configure(conf)
    def (driver.instance).send_check(server, port, payload)
      @sent_data ||= []
      @sent_data.push([server, port, payload])
    end
    def (driver.instance).sent_data
      return @sent_data
    end
    return driver
  end

  # }}}1
  # Default value {{{1

  # Send default values for empty data and empty setting
  def test_write_empty_data_with_empty_setting
    driver = create_driver('', 'ddos')
    time = Time.parse('2015-01-03 12:34:56 UTC').to_i
    driver.emit({}, time)
    driver.run
    result = driver.instance.sent_data
    expected = {
      'name' => 'ddos',
      'output' => '{}',
      'status' => 3,
      'type' => 'standard',
      'handlers' => ['default'],
      'executed' => time,
      'fluentd' => {
        'tag' => 'ddos',
        'time' => time.to_i,
        'record' => {},
      },
    }
    assert_equal [['localhost', 3030, expected]], result
  end

  # }}}1
  # Connection {{{1

  # Connection settings are read
  def test_connection_settings
    driver = create_driver(%[
      server sensu-client.local
      port 3031
    ])
    assert_equal 'sensu-client.local', driver.instance.instance_eval{ @server }
    assert_equal 3031, driver.instance.instance_eval{ @port }
  end

  # Default values are set to connection settings
  def test_default_connection_settings
    driver = create_driver('')
    assert_equal 'localhost', driver.instance.instance_eval{ @server }
    assert_equal 3030, driver.instance.instance_eval{ @port }
  end

  # Send default values to aother node and another port
  def test_send_to_another_connection
    driver = create_driver(%[
      server sensu-client.local
      port 3031
    ], 'ddos')
    time = Time.parse('2015-01-03 12:34:56 UTC').to_i
    driver.emit({}, time)
    driver.run
    result = driver.instance.sent_data
    expected = {
      'name' => 'ddos',
      'output' => '{}',
      'status' => 3,
      'type' => 'standard',
      'handlers' => ['default'],
      'executed' => time,
      'fluentd' => {
        'tag' => 'ddos',
        'time' => time.to_i,
        'record' => {},
      },
    }
    assert_equal [['sensu-client.local', 3031, expected]], result
  end

  # }}}1
  # "name" attribute {{{1

  # Rejects invalid check name config
  def test_rejects_invalid_check_name_in_option
    assert_raise(Fluent::ConfigError) {
      create_driver(%[check_name invalid/check/name], 'ddos')
    }
  end

  # Determine "name" attribute with options
  def test_determine_name_attribute_with_options
    driver = create_driver(%[
      check_name_field service
      check_name ddos_detection
    ], 'ddos')
    time = Time.parse('2015-01-03 12:34:56 UTC').to_i
    driver.emit({ 'service' => 'flood' }, time)
    driver.emit({ 'service' => 'invalid/check/name' }, time)
    driver.emit({}, time)
    driver.run
    result = driver.instance.sent_data
    expected1 = {
      'name' => 'flood',
      'output' => '{"service":"flood"}',
      'status' => 3,
      'type' => 'standard',
      'handlers' => ['default'],
      'executed' => time,
      'fluentd' => {
        'tag' => 'ddos',
        'time' => time.to_i,
        'record' => { 'service' => 'flood' },
      },
    }
    expected2 = {
      'name' => 'ddos_detection',
      'output' => '{"service":"invalid/check/name"}',
      'status' => 3,
      'type' => 'standard',
      'handlers' => ['default'],
      'executed' => time,
      'fluentd' => {
        'tag' => 'ddos',
        'time' => time.to_i,
        'record' => { 'service' => 'invalid/check/name' },
      },
    }
    expected3 = {
      'name' => 'ddos_detection',
      'output' => '{}',
      'status' => 3,
      'type' => 'standard',
      'handlers' => ['default'],
      'executed' => time,
      'fluentd' => {
        'tag' => 'ddos',
        'time' => time.to_i,
        'record' => {},
      },
    }
    assert_equal [
      ['localhost', 3030, expected1],
      ['localhost', 3030, expected2],
      ['localhost', 3030, expected3],
    ], result
  end

  # Dertermine "name" attribute with tag
  def test_determine_name_attribute_with_tag
    driver = create_driver('', 'ddos')
    time = Time.parse('2015-01-03 12:34:56 UTC').to_i
    driver.emit({}, time)
    driver.run
    result = driver.instance.sent_data
    expected = {
      'name' => 'ddos',
      'output' => '{}',
      'status' => 3,
      'type' => 'standard',
      'handlers' => ['default'],
      'executed' => time,
      'fluentd' => {
        'tag' => 'ddos',
        'time' => time.to_i,
        'record' => {},
      },
    }
    assert_equal([['localhost', 3030, expected]], result)
  end

  # Dertermine "name" attribute as default constant
  def test_determine_name_attribute_as_default_constant
    driver = create_driver('', 'invalid/check/name')
    time = Time.parse('2015-01-03 12:34:56 UTC').to_i
    driver.emit({}, time)
    driver.run
    result = driver.instance.sent_data
    expected = {
      'name' => 'fluent-plugin-sensu',
      'output' => '{}',
      'status' => 3,
      'type' => 'standard',
      'handlers' => ['default'],
      'executed' => time,
      'fluentd' => {
        'tag' => 'invalid/check/name',
        'time' => time.to_i,
        'record' => {},
      },
    }
    assert_equal([['localhost', 3030, expected]], result)
  end

  # }}}1
  # "output" attribute {{{1

  # Check output is determined by check_output_field
  # or check_output if specified
  def test_determine_output_attribute_with_options
    driver = create_driver(%[
      check_output_field desc
      check_output Something is going on
    ], 'ddos')
    time = Time.parse('2015-01-03 12:34:56 UTC').to_i
    driver.emit({ 'desc' => 'Something is afield' }, time)
    driver.emit({}, time)
    driver.run
    result = driver.instance.sent_data
    expected_for_output_field = {
      'name' => 'ddos',
      'output' => 'Something is afield',
      'status' => 3,
      'type' => 'standard',
      'handlers' => ['default'],
      'executed' => time,
      'fluentd' => {
        'tag' => 'ddos',
        'time' => time.to_i,
        'record' => { 'desc' => 'Something is afield' },
      },
    }
    expected_for_output_option = {
      'name' => 'ddos',
      'output' => 'Something is going on',
      'status' => 3,
      'type' => 'standard',
      'handlers' => ['default'],
      'executed' => time,
      'fluentd' => {
        'tag' => 'ddos',
        'time' => time.to_i,
        'record' => {},
      },
    }
    assert_equal([
      ['localhost', 3030, expected_for_output_field],
      ['localhost', 3030, expected_for_output_option],
    ], result)
  end

  # }}}1
  # "status" attribute {{{1

  # Rejects an invalid value for check_status option.
  def test_rejects_invalid_status
    assert_raise(Fluent::ConfigError) {
      create_driver(%[check_status 4], 'ddos')
    }
  end

  # "status" attribute is determined by check_status
  # and check_status_field option if specified.
  def test_determine_status_attribute_with_options
    driver = create_driver(%[
      check_status_field severity
      check_status 0
    ], 'ddos')
    time = Time.parse('2015-01-03 12:34:56 UTC').to_i
    driver.emit({ 'severity' => 1 }, time)
    driver.emit({ 'severity' => 'Critical' }, time)
    driver.emit({}, time)
    driver.run
    result = driver.instance.sent_data
    expected_for_numerical_severity = {
      'name' => 'ddos',
      'output' => '{"severity":1}',
      'status' => 1,
      'type' => 'standard',
      'handlers' => ['default'],
      'executed' => time,
      'fluentd' => {
        'tag' => 'ddos',
        'time' => time.to_i,
        'record' => { 'severity' => 1 },
      },
    }
    expected_for_string_severity = {
      'name' => 'ddos',
      'output' => '{"severity":"Critical"}',
      'status' => 2,
      'type' => 'standard',
      'handlers' => ['default'],
      'executed' => time,
      'fluentd' => {
        'tag' => 'ddos',
        'time' => time.to_i,
        'record' => { 'severity' => 'Critical' },
      },
    }
    expected_for_option = {
      'name' => 'ddos',
      'output' => '{}',
      'status' => 0,
      'type' => 'standard',
      'handlers' => ['default'],
      'executed' => time,
      'fluentd' => {
        'tag' => 'ddos',
        'time' => time.to_i,
        'record' => {},
      },
    }
    assert_equal([
      ['localhost', 3030, expected_for_numerical_severity],
      ['localhost', 3030, expected_for_string_severity],
      ['localhost', 3030, expected_for_option],
    ], result)
  end

  # }}}1
  # "type" attribute {{{1

  # Rejects a check types if it is neither "standard" nor "metric".
  def test_rejects_invalid_check_type
    assert_raise(Fluent::ConfigError) {
      create_driver(%[check_type nosuchtype], 'ddos')
    }
  end

  # Specifies "standard" check type.
  def test_specify_standard_check_type
    driver = create_driver(%[
      check_type standard
    ], 'ddos')
    time = Time.parse('2015-01-03 12:34:56 UTC').to_i
    driver.emit({}, time)
    driver.run
    result = driver.instance.sent_data
    expected = {
      'name' => 'ddos',
      'output' => '{}',
      'status' => 3,
      'type' => 'standard',
      'handlers' => ['default'],
      'executed' => time,
      'fluentd' => {
        'tag' => 'ddos',
        'time' => time.to_i,
        'record' => {},
      },
    }
    assert_equal([
      ['localhost', 3030, expected],
    ], result)
  end

  # Specifies "metric" check type.
  def test_specify_metric_check_type
    driver = create_driver(%[
      check_type metric
    ], 'ddos')
    time = Time.parse('2015-01-03 12:34:56 UTC').to_i
    driver.emit({}, time)
    driver.run
    result = driver.instance.sent_data
    expected = {
      'name' => 'ddos',
      'output' => '{}',
      'status' => 3,
      'type' => 'metric',
      'handlers' => ['default'],
      'executed' => time,
      'fluentd' => {
        'tag' => 'ddos',
        'time' => time.to_i,
        'record' => {},
      },
    }
    assert_equal([
      ['localhost', 3030, expected],
    ], result)
  end

  # }}}1
  # "ttl" attribute {{{1

  # Specifies TTL at config.
  def test_specify_ttl
    driver = create_driver(%[
      check_ttl 30
    ], 'ddos')
    time = Time.parse('2015-01-03 12:34:56 UTC').to_i
    driver.emit({}, time)
    driver.run
    result = driver.instance.sent_data
    expected = {
      'name' => 'ddos',
      'output' => '{}',
      'status' => 3,
      'type' => 'standard',
      'handlers' => ['default'],
      'executed' => time,
      'fluentd' => {
        'tag' => 'ddos',
        'time' => time.to_i,
        'record' => {},
      },
      'ttl' => 30,
    }
    assert_equal([
      ['localhost', 3030, expected],
    ], result)
  end

  # }}}1
  # "handlers" attribute {{{1

  # Rejects the option if it is malformed.
  def test_rejects_malformed_handlers
    assert_raise(JSON::ParserError) {
      create_driver(%[check_handlers NotJsonString], 'ddos')
    }
  end

  # Rejects the option if it is not an array.
  def test_rejects_nonarray_handlers
    assert_raise(Fluent::ConfigError) {
      create_driver(%[check_handlers 30], 'ddos')
    }
  end

  # Rejects the option if the array contains non-integer values.
  def test_rejects_nonstring_element_in_handlers
    assert_raise(Fluent::ConfigError) {
      create_driver(%[check_handlers ["default", 32]], 'ddos')
    }
  end

  # Specifies handlers at config.
  def test_specifies_handlers
    driver = create_driver(%[
      check_handlers ["default", "graphite"]
    ], 'ddos')
    time = Time.parse('2015-01-03 12:34:56 UTC').to_i
    driver.emit({}, time)
    driver.run
    result = driver.instance.sent_data
    expected = {
      'name' => 'ddos',
      'output' => '{}',
      'status' => 3,
      'type' => 'standard',
      'handlers' => ['default', 'graphite'],
      'executed' => time,
      'fluentd' => {
        'tag' => 'ddos',
        'time' => time.to_i,
        'record' => {},
      },
    }
    assert_equal([
      ['localhost', 3030, expected],
    ], result)
  end

  # }}}1
  # "low_flap_threshold" and "high_flap_threshold" attributes {{{1

  # The thresholds must be specified together if one is specified.
  def test_flapping_thrsholds_must_be_specified_together
    assert_raise(Fluent::ConfigError) {
      create_driver(%[
        check_low_flap_threshold 40
      ], 'ddos')
    }
    assert_raise(Fluent::ConfigError) {
      create_driver(%[
        check_high_flap_threshold 60
      ], 'ddos')
    }
  end

  # The thresholds must be in order.
  def test_flapping_thresholds_order
    assert_nothing_raised {
      create_driver(%[
        check_low_flap_threshold 0
        check_high_flap_threshold 100
      ], 'ddos')
    }
    assert_raise(Fluent::ConfigError) {
      create_driver(%[
        check_low_flap_threshold -1
        check_high_flap_threshold 100
      ], 'ddos')
    }
    assert_raise(Fluent::ConfigError) {
      create_driver(%[
        check_low_flap_threshold 0
        check_high_flap_threshold 101
      ], 'ddos')
    }
    assert_nothing_raised {
      create_driver(%[
        check_low_flap_threshold 50
        check_high_flap_threshold 50
      ], 'ddos')
    }
    assert_raise(Fluent::ConfigError) {
      create_driver(%[
        check_low_flap_threshold 50
        check_high_flap_threshold 49
      ], 'ddos')
    }
  end

  # Specifies flapping thresholds.
  def test_specify_flapping_thresholds
    driver = create_driver(%[
      check_low_flap_threshold 40
      check_high_flap_threshold 60
    ], 'ddos')
    time = Time.parse('2015-01-03 12:34:56 UTC').to_i
    driver.emit({}, time)
    driver.run
    result = driver.instance.sent_data
    expected = {
      'name' => 'ddos',
      'output' => '{}',
      'status' => 3,
      'type' => 'standard',
      'handlers' => ['default'],
      'executed' => time,
      'fluentd' => {
        'tag' => 'ddos',
        'time' => time.to_i,
        'record' => {},
      },
      'low_flap_threshold' => 40,
      'high_flap_threshold' => 60,
    }
    assert_equal([
      ['localhost', 3030, expected],
    ], result)
  end

  # }}}1
  # "source" attribute {{{1

  # "source" attribute is determined by check_source_field
  # and check_source option if specified.
  def test_determine_source_by_options
    driver = create_driver(%[
      check_source_field machine
      check_source router.example.com
    ], 'ddos')
    time = Time.parse('2015-01-03 12:34:56 UTC').to_i
    driver.emit({ 'machine' => 'ups.example.com' }, time)
    driver.emit({}, time)
    driver.run
    result = driver.instance.sent_data
    expected_for_field = {
      'name' => 'ddos',
      'output' => '{"machine":"ups.example.com"}',
      'status' => 3,
      'type' => 'standard',
      'handlers' => ['default'],
      'executed' => time,
      'fluentd' => {
        'tag' => 'ddos',
        'time' => time.to_i,
        'record' => { 'machine' => 'ups.example.com' },
      },
      'source' => 'ups.example.com',
    }
    expected_for_option = {
      'name' => 'ddos',
      'output' => '{}',
      'status' => 3,
      'type' => 'standard',
      'handlers' => ['default'],
      'executed' => time,
      'fluentd' => {
        'tag' => 'ddos',
        'time' => time.to_i,
        'record' => {},
      },
      'source' => 'router.example.com',
    }
    assert_equal([
      ['localhost', 3030, expected_for_field],
      ['localhost', 3030, expected_for_option],
    ], result)
  end

  # }}}1
  # "executed" attribute {{{1

  # Determine "executed" time attribute by the options.
  def test_determine_executed_by_options
    driver = create_driver(%[
      check_executed_field timestamp
    ], 'ddos')
    data_time = Time.parse('2015-01-03 12:34:56 UTC').to_i
    field_time = Time.parse('2015-01-03 23:45:12 UTC').to_i
    driver.emit({ 'timestamp' => field_time.to_i }, data_time)
    driver.emit({ 'timestamp' => 'not-integer' }, data_time)
    driver.emit({}, data_time)
    driver.run
    result = driver.instance.sent_data
    expected_for_field = {
      'name' => 'ddos',
      'output' => "{\"timestamp\":#{field_time.to_i}}",
      'status' => 3,
      'type' => 'standard',
      'handlers' => ['default'],
      'executed' => field_time.to_i,
      'fluentd' => {
        'tag' => 'ddos',
        'time' => data_time.to_i,
        'record' => { 'timestamp' => field_time.to_i },
      },
    }
    expected_for_error_data = {
      'name' => 'ddos',
      'output' => '{"timestamp":"not-integer"}',
      'status' => 3,
      'type' => 'standard',
      'handlers' => ['default'],
      'executed' => data_time.to_i,
      'fluentd' => {
        'tag' => 'ddos',
        'time' => data_time.to_i,
        'record' => { 'timestamp' => 'not-integer' },
      },
    }
    expected_for_data_time = {
      'name' => 'ddos',
      'output' => "{}",
      'status' => 3,
      'type' => 'standard',
      'handlers' => ['default'],
      'executed' => data_time.to_i,
      'fluentd' => {
        'tag' => 'ddos',
        'time' => data_time.to_i,
        'record' => {},
      },
    }
    assert_equal([
      ['localhost', 3030, expected_for_field],
      ['localhost', 3030, expected_for_error_data],
      ['localhost', 3030, expected_for_data_time],
    ], result)
  end

  # }}}1

end
