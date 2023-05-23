[![Build Status](https://travis-ci.org/tyldum/mojolicious-plugin-prometheus.svg?branch=master)](https://travis-ci.org/tyldum/mojolicious-plugin-prometheus) [![MetaCPAN Release](https://badge.fury.io/pl/Mojolicious-Plugin-Prometheus.svg)](https://metacpan.org/release/Mojolicious-Plugin-Prometheus) [![Coverage Status](http://codecov.io/github/tyldum/mojolicious-plugin-prometheus/coverage.svg?branch=master)](https://codecov.io/github/tyldum/mojolicious-plugin-prometheus?branch=master)
# NAME

Mojolicious::Plugin::Prometheus - Mojolicious Plugin

# SYNOPSIS

    # Mojolicious
    $self->plugin('Prometheus');

    # Mojolicious::Lite
    plugin 'Prometheus';

    # Mojolicious::Lite, with custom response buckets (seconds)
    plugin 'Prometheus' => { response_buckets => [qw/4 5 6/] };

    # You can add your own route to do access control
    my $under = app->routes->under('/secret' =>sub {
      my $c = shift;
      return 1 if $c->req->url->to_abs->userinfo eq 'Bender:rocks';
      $c->res->headers->www_authenticate('Basic');
      $c->render(text => 'Authentication required!', status => 401);
      return undef;
    });
    plugin Prometheus => {route => $under};

# DESCRIPTION

[Mojolicious::Plugin::Prometheus](https://metacpan.org/pod/Mojolicious%3A%3APlugin%3A%3APrometheus) is a [Mojolicious](https://metacpan.org/pod/Mojolicious) plugin that exports Prometheus metrics from Mojolicious.

Hooks are also installed to measure requests response time and count requests based on method and HTTP return code.

# HELPERS

## prometheus

Create further instrumentation into your application by using this helper which gives access to the [Net::Prometheus](https://metacpan.org/pod/Net%3A%3APrometheus) object.
See [Net::Prometheus](https://metacpan.org/pod/Net%3A%3APrometheus) for usage.

# METHODS

[Mojolicious::Plugin::Prometheus](https://metacpan.org/pod/Mojolicious%3A%3APlugin%3A%3APrometheus) inherits all methods from
[Mojolicious::Plugin](https://metacpan.org/pod/Mojolicious%3A%3APlugin) and implements the following new ones.

## register

    $plugin->register($app, \%config);

Register plugin in [Mojolicious](https://metacpan.org/pod/Mojolicious) application.

`%config` can have:

- route

    [Mojolicious::Routes::Route](https://metacpan.org/pod/Mojolicious%3A%3ARoutes%3A%3ARoute) object to attach the metrics to, defaults to generating a new one for '/'.

    Default: /

- path

    The path to mount the exporter.

    Default: /metrics

- prometheus

    Override the [Net::Prometheus](https://metacpan.org/pod/Net%3A%3APrometheus) object. The default is a new singleton instance of [Net::Prometheus](https://metacpan.org/pod/Net%3A%3APrometheus).

- namespace, subsystem

    These will be prefixed to the metrics exported.

- request\_buckets

    Override buckets for request sizes histogram.

    Default: `(1, 50, 100, 1_000, 10_000, 50_000, 100_000, 500_000, 1_000_000)`

- response\_buckets

    Override buckets for response sizes histogram.

    Default: `(5, 50, 100, 1_000, 10_000, 50_000, 100_000, 500_000, 1_000_000)`

- duration\_buckets

    Override buckets for request duration histogram.

    Default: `(0.005, 0.01, 0.025, 0.05, 0.075, 0.1, 0.25, 0.5, 0.75, 1.0, 2.5, 5.0, 7.5, 10)` (actually see [Net::Prometheus](https://metacpan.org/source/PEVANS/Net-Prometheus-0.05/lib/Net/Prometheus/Histogram.pm#L19))

- shm\_key

    Key used for shared memory access between workers, see [$key in IPc::ShareLite](https://metacpan.org/pod/IPC::ShareLite) for details.

# METRICS

In addition to exposing the default process metrics that [Net::Prometheus](https://metacpan.org/pod/Net%3A%3APrometheus) already expose
this plugin will also expose

- `http_requests_total`, request counter partitioned over HTTP method and HTTP response code
- `http_request_duration_seconds`, request duration histogram partitioned over HTTP method
- `http_request_size_bytes`, request size histogram partitioned over HTTP method
- `http_response_size_bytes`, response size histogram partitioned over HTTP method

# AUTHOR

Vidar Tyldum

(the IPC::ShareLite parts of this code is shamelessly stolen from [Mojolicious::Plugin::Status](https://metacpan.org/pod/Mojolicious%3A%3APlugin%3A%3AStatus) written by Sebastian Riedel and mangled into something that works for me)

# COPYRIGHT AND LICENSE

Copyright (C) 2018, Vidar Tyldum

This program is free software, you can redistribute it and/or modify it under
the terms of the Artistic License version 2.0.

# SEE ALSO

- [Net::Prometheus](https://metacpan.org/pod/Net%3A%3APrometheus)
- [Mojolicious::Plugin::Status](https://metacpan.org/pod/Mojolicious%3A%3APlugin%3A%3AStatus)
- [Mojolicious](https://metacpan.org/pod/Mojolicious)
- [Mojolicious::Guides](https://metacpan.org/pod/Mojolicious%3A%3AGuides)
- [http://mojolicious.org](http://mojolicious.org)
