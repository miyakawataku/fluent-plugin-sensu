# -*- encoding: utf-8 -*-
# vim: et sw=2 sts=2

module Fluent

  # Fluentd output plugin to send checks to sensu-client.
  class SensuOutput < Fluent::BufferedOutput
    Fluent::Plugin.register_output('sensu', self)
  end
end
