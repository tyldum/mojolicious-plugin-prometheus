[![Build Status](https://travis-ci.org/tyldum/mojolicious-plugin-prometheus.svg?branch=master)](https://travis-ci.org/tyldum/mojolicious-plugin-prometheus) [![MetaCPAN Release](https://badge.fury.io/pl/Mojolicious-Plugin-Prometheus.svg)](https://metacpan.org/release/Mojolicious-Plugin-Prometheus)
# NAME

Mojolicious::Plugin::Prometheus - Mojolicious Plugin

# SYNOPSIS

    # Mojolicious
    $self->plugin('Prometheus');

    # Mojolicious::Lite
    plugin 'Prometheus';

# DESCRIPTION

[Mojolicious::Plugin::Prometheus](https://metacpan.org/pod/Mojolicious::Plugin::Prometheus) is a [Mojolicious](https://metacpan.org/pod/Mojolicious) plugin that exports Prometheus metrics from Mojolicious.

Hooks are also installed to measure requests response time and count requests based on method and HTTP return code.

# HELPERS

## prometheus

Create further instrumentation into your application by using this helper which gives access to the [Net::Prometheus](https://metacpan.org/pod/Net::Prometheus) object.

# METHODS

[Mojolicious::Plugin::Prometheus](https://metacpan.org/pod/Mojolicious::Plugin::Prometheus) inherits all methods from
[Mojolicious::Plugin](https://metacpan.org/pod/Mojolicious::Plugin) and implements the following new ones.

## register

    $plugin->register($app, \&config);

Register plugin in [Mojolicious](https://metacpan.org/pod/Mojolicious) application.

`%config` can have:

- path

    The path to mount the exporter.

    Default: /metrics

- prometheus

    Override the [Net::Prometheus](https://metacpan.org/pod/Net::Prometheus) object. The default is a new singleton instance of [Net::Prometheus](https://metacpan.org/pod/Net::Prometheus).

- namespace, subsystem

    These will be prefixed to the metrics exported.

# METRICS

In addition to exporting the default process metrics that [Net::Prometheus](https://metacpan.org/pod/Net::Prometheus) already export
this plugin will also export

- `http_requests_total`, counter partitioned over HTTP method and HTTP response code
- `http_request_duration_seconds`, histogram partitoned over HTTP method

# AUTHOR

Vidar Tyldum

# COPYRIGHT AND LICENSE
Copyright (C) 2017, Vidar Tyldum

This program is free software, you can redistribute it and/or modify it under
the terms of the Artistic License version 2.0.

# SEE ALSO

- [Net::Prometheus](https://metacpan.org/pod/Net::Prometheus)
- [Mojolicious](https://metacpan.org/pod/Mojolicious)
- [Mojolicious::Guides](https://metacpan.org/pod/Mojolicious::Guides)
- [http://mojolicious.org](http://mojolicious.org)
