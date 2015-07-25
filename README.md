# fluent-plugin-sensu

[Fluentd](http://fluentd.org) output plugin to send check results to
[sensu-client](https://sensuapp.org/docs/latest/clients),
which is an agent process of Sensu monitoring framework.

This plugin is under development and not working yet.

## Configuration

### Example configuration

```apache
<match ddos>
  type sensu

  # Connection settings
  server localhost
  port 3030

  # Payload settings

  ## The check is named "ddos_detection"
  name ddos_detection

  ## The severity is read from the field "level"
  status_field level
</match>
```

### Plugin type

Tye type of this plugin is `sensu`.
Specify `type sensu` in the match section.

### Connection setting

* `server` (default is "localhost")
  * The IP address or the hostname of the host running sensu-client daemon.
* `port` (default is 3030)
  * The TCP port number of the [Sensu client socket
    ](https://sensuapp.org/docs/latest/clients#client-socket-input)
    on which sensu-client daemon is listening.

### Check payload

The payload of a check result is JSON data with attributes as follows.

* `name`
  * The check name to identify the check.
* `output`
  * An arbitrary string to describe the check result.
  * This attribute is often used to contain metric values.
* `status`
  * The severity of the check result.
  * 0 (OK), 1 (WARNING), 2 (CRITICAL) or 3 (UNKNOWN or CUSTOM).

The payload of a check result can also contain
standard check definition attributes.
This plugin supports the properties below.

* `type`
  * Either "standard" or "metric".
  * If the attribute is set to "standard", the sensu-server creates an event
    only when the status is not OK or when the status is changed to OK.
  * If the attribute is set to "metric", the sensu-server creates an event
    even if the status is OK.
    It is useful when Sensu sends check results to metrics collectors
    such as [Graphite](http://graphite.wikidot.com/).
* `ttl`
  * The time to live (TTL) in seconds,
    until the check result is considered stale.
    If TTL expires, sensu-server creates an event.
  * This attribute is useful when you want to be notified
    when logs are not output for a certain period.
  * Same as `freshness_threshold` in Nagios.
* `handler` and `handlers`
  * The name(s) of the handler(s) which process events created for the check.
* `low_flap_threshold` and `high_flap_threshold`
  * Threshold percentages to determine the status is considered "flapping,"
    or the state is changed too frequently.
  * Same as the options in Nagios.
    See the description of [Flap Detection
    ](https://assets.nagios.com/downloads/nagioscore/docs/nagioscore/3/en/flapping.html)
    in Nagios.
* `source`
  * The source of the check, such as servers or network switches.
  * If this attribute is not specified,
    the host of sensu-client is considered as the source.

#### `name` of the check

The check name (`name` in Sensu check data)
is determined as below.

1. The field specified by `name_field` option, if present (highest priority)
2. or `name` option, if present
3. or the tag name (lowest priority)

#### `output` to describe the check result

The check output (`output` in Sensu check data)
is determined as below.

1. The field specified by `output_field` option, if present (highest priority)
2. or `output` option, if present
3. or JSON notation of the record (lowest priority)

#### `status` of the check severity

The severity of the check result (`status` in Sensu check data)
is determined as below.

1. The field specified by `status_field` option,
   if present and permitted (highest priority)
  * The values permitted to the field for each state:
    * 0: an integer ``0``
      and strings ``"0"``, ``"OK"`` (case insensitive)
    * 1: an integer ``1``
      and strings ``"1"``, ``"WARNING"``, ``"warn"``
    * 2: an integer ``2``
      and strings ``"2"``, ``"CRITICAL"``, ``"crit"``
    * 3: an integer ``3``
      and strings ``"3"``, ``"UNKNOWN"``, ``"CUSTOM"``
2. or `status` option, if present
  * The permitted values for each state:
    * 0: ``0`` and ``OK``
    * 1: ``1``, ``WARNING"``, ``warn``
    * 2: ``2``, ``CRITICAL``, ``crit``
    * 3: ``3``, ``UNKNOWN``, ``CUSTOM``
  * If the value is not permitted, it causes a configuration error.
3. or `3`, which means `UNKNOWN` (lowest priority)

The value of the field or the option is case insensitive.

"warn" and "crit" come from
[fluent-plugin-notifier](https://github.com/tagomoris/fluent-plugin-notifier).

#### `type` of the check

The check type (`type` in Sensu check data)
is determined as below.

1. `check_type` option (highest priority)
  * The permitted values are ``standard`` and ``metric``.
  * If the value is not permitted, it causes a configuration error.
2. or "standard" (lowest priority)

#### `ttl` seconds till expiration

The TTL seconds till expiration (`ttl` in Sensu check data)
is determined as below.

1. `ttl` option (highest priority)
  * In seconds.
2. or N/A (lowest priority)
  * It means no expiration detection is performed.

#### `handler` or `handlers` to process check results

The handlers which process check results
(`handler` or `handlers` in Sensu check data)
are determined as below.

1. `handlers` option (highest priority)
  * Specified as an array of strings.
2. or `["default"]` (lowest priority)

This plugin yields only `handlers` attribute.

#### `low_flap_threshold` and `high_flap_threshold` for flap detection

The threshold percentages for flap detection
(`low_flap_threshold` and `high_flap_threshold` in Sensu check data)
are determined as below.

1. `low_flap_threshold` and `high_flap_threshold` options (highest priority)
  * In percentage.
2. or N/A (lowest priority)
  * It means no flap detection is performed.

The two options either must be specified together,
not specified at all.
If only one of the options is specified,
it causes a configuration error.

#### `source` of the check

The source of the checks (`source` in Sensu check data)
is determined as below.

1. The field specified by `source_field` option (highest priority)
2. or `source` option
3. or N/A (lowest priority)
  * It means the host of sensu-client is considered as the check source.

### Buffering

The default value of `flush_interval` option is set to 1 second.
It means that check results are delayed at most 1 second
before being sent.

Except for `flush_interval`,
the plugin uses default options
for buffered output plugins (defined in Fluent::BufferedOutput class).

You can override buffering options in the configuration.
For example:

```apache
<match ddos>
  type sensu
  ...snip...
  buffer_type file
  buffer_path /var/lib/fluentd/buffer/ddos
  flush_interval 0.1
  try_flush_interval 0.1
</match>
```

## Use case: "too many server errors" alert

#### Situation

Assume you have a web server which runs:

* Apache HTTP server
* Fluentd
* sensu-client
  * which listens to the TCP port 3030 for [Sensu client socket
    ](https://sensuapp.org/docs/latest/clients#client-socket-input).

You want to be notified when Apache responds too many server errors,
for example 5 errors per minute as WARNING,
and 50 errors per minute as CRITICAL.

#### Configuration

The setting for Fluentd utilizes
[fluent-plugin-datacounter](https://github.com/tagomoris/fluent-plugin-datacounter),
[fluent-plugin-record-reformer](https://github.com/sonots/fluent-plugin-record-reformer),
and of course [fluent-plugin-sensu](https://github.com/miyakawataku/fluent-plugin-sensu).
Install those plugins and add configuration as below.

```apache
# Parse Apache access log
<source>
  type tail
  tag access
  format apache2

  # The paths vary by setup
  path /var/log/httpd/access_log
  pos_file /var/lib/fluentd/pos/httpd-access_log.pos
</source>

# Count 5xx errors per minute
<match access>
  type datacounter
  tag count.access
  unit minute
  aggregate all
  count_key code
  pattern1 error ^5\d\d$
</match>

# Calculate the severity level
<match count.access>
  type record_reformer
  tag server_errors
  enable_ruby true
  <record>
    level ${error_count < 5 ? 'OK' : error_count < 50 ? 'WARNING' : 'CRITICAL'}
  </record>
</match>

# Send checks to sensu-client
<match server_errors>
  type sensu
  server localhost
  port 3030

  name server_errors
  check_type standard
  status_field level
  ttl 100
</match>
```

The TTL is set to 100 seconds here,
because the check must be sent for each 60 seconds,
plus 40 seconds as a margin.

## Alternatives

You can use [record\_transformer
](http://docs.fluentd.org/articles/filter_record_transformer) filter
instead of `fluent-plugin-record-reformer`
on Fluentd 0.12.0 and above.

If you are concerned with scalability,
[fluent-plugin-norikra](https://github.com/norikra/fluent-plugin-norikra)
may be a better option than datacounter and record\_reformer.

Another alternative configuration for the use case is
sending the error count to Graphite using [fluent-plugin-graphite
](https://github.com/studio3104/fluent-plugin-graphite),
and making Sensu monitor the value on Graphite with [check-data.rb
](https://github.com/sensu/sensu-community-plugins/blob/master/plugins/graphite/check-data.rb).

## Installation

Install `fluent-plugin-sensu` gem (not yet available).

# Contributing

Submit an [issue](https://github.com/miyakawataku/fluent-plugin-sensu/issues)
or a [pull request](https://github.com/miyakawataku/fluent-plugin-sensu/pulls).

Feedback to [@miyakawa\_taku](https://twitter.com/miyakawa_taku) on Twitter
is also welcome.
