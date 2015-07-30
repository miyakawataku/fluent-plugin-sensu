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
      'fluentd_tag' => 'ddos',
      'fluentd_time' => time.to_i,
      'fluentd_record' => {},
    }
    assert_equal [['localhost', 3030, expected]], result
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
      'fluentd_tag' => 'ddos',
      'fluentd_time' => time.to_i,
      'fluentd_record' => {},
    }
    assert_equal [['sensu-client.local', 3031, expected]], result
  end

  # }}}1
  # "name" attribute {{{1

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
      'fluentd_tag' => 'ddos',
      'fluentd_time' => time.to_i,
      'fluentd_record' => { 'service' => 'flood' },
    }
    expected2 = {
      'name' => 'ddos_detection',
      'output' => '{"service":"invalid/check/name"}',
      'status' => 3,
      'type' => 'standard',
      'handlers' => ['default'],
      'executed' => time,
      'fluentd_tag' => 'ddos',
      'fluentd_time' => time.to_i,
      'fluentd_record' => { 'service' => 'invalid/check/name' },
    }
    expected3 = {
      'name' => 'ddos_detection',
      'output' => '{}',
      'status' => 3,
      'type' => 'standard',
      'handlers' => ['default'],
      'executed' => time,
      'fluentd_tag' => 'ddos',
      'fluentd_time' => time.to_i,
      'fluentd_record' => {},
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
      'fluentd_tag' => 'ddos',
      'fluentd_time' => time.to_i,
      'fluentd_record' => {},
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
      'fluentd_tag' => 'invalid/check/name',
      'fluentd_time' => time.to_i,
      'fluentd_record' => {},
    }
    assert_equal([['localhost', 3030, expected]], result)
  end

  # }}}1

end
