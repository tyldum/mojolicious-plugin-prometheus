[![Actions Status](https://github.com/tyldum/mojolicious-plugin-prometheus/actions/workflows/.github/workflows/linux.yml/badge.svg)](https://github.com/tyldum/mojolicious-plugin-prometheus/actions) [![MetaCPAN Release](https://badge.fury.io/pl/Mojolicious-Plugin-Prometheus.svg)](https://metacpan.org/release/Mojolicious-Plugin-Prometheus)
# NAME

Mojolicious::Plugin::Prometheus - Mojolicious Plugin

# SYNOPSIS

    # Mojolicious, no extra options
    $self->plugin('Prometheus');

    # Mojolicious::Lite, no extra options
    plugin 'Prometheus';

    # Mojolicious::Lite, with custom response buckets and metrics pr endpoint
    plugin 'Prometheus' => {
      http_requests_total => {
        buckets => [qw/4 5 6/],
        labels  => [qw/worker method endpoint code/],
        cb      => sub {
          my $c = shift;
          my $endpoint = $c->match->endpoint ? $c->match->endpoint->to_string : undef;
          return ($$, $c->req->method, $endpoint || $c->req->url, $c->res->code);
        },
      },
    };

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

- shm\_key

    Key used for shared memory access between workers, see [$key in IPC::ShareLite](https://metacpan.org/pod/IPC::ShareLite) for details. Default is the process id read from `$$`.

- http\_request\_duration\_seconds

    Structure that overrides the configuration for the `http_request_duration_seconds` metric. See below.

- http\_request\_size\_bytes

    Structure that overrides the configuration for the `http_request_size_bytes` metric. See below.

- http\_response\_size\_bytes

    Structure that overrides the configuration for the `http_response_size_bytes` metric. See below.

- http\_requests\_total

    Structure that overrides the configuration for the `http_requests_total` metric. See below.

- perl\_collector

    Structure that tells the plugin to enable or disable a Perl collector. Previously the Perl collector from [Net::Prometheus](https://metacpan.org/pod/Net%3A%3APrometheus) was used, but that is no longer in use due to it not being possible to add dynamic label values. Now [Mojolicious::Plugin::Prometheus::Collector::Perl](https://metacpan.org/pod/Mojolicious%3A%3APlugin%3A%3APrometheus%3A%3ACollector%3A%3APerl) is used. The configuration here need as follows:

    - enabled

        Boolean-ish value indicating if this collector should be used.

    - labels\_cb

        A subref that the collector can call to dynamically resolve which labels and corresponding label values should be added to each metric. Default is:

            {
              enabled   => 1,
              labels_cb => sub { { worker => $$ } },
            }

- process\_collector

    Structure that tells the plugin to enable or disable a process collector. The process collector from [Net::Prometheus](https://metacpan.org/pod/Net%3A%3APrometheus) is used for this. The configuration here need as follows:

    - enabled

        Boolean-ish value indicating if this collector should be used.

    - labels\_cb

        A subref that the collector can call to dynamically resolve which labels and corresponding label values should be added to each metric. Default is:

            {
              enabled   => 1,
              labels_cb => sub { { worker => $$ } },
            }

# METRICS

In addition to exposing the default process metrics that [Net::Prometheus](https://metacpan.org/pod/Net%3A%3APrometheus) already expose
this plugin will also expose

- `http_requests_total`, request counter partitioned over HTTP method and HTTP response code
- `http_request_duration_seconds`, request duration histogram partitioned over HTTP method
- `http_request_size_bytes`, request size histogram partitioned over HTTP method
- `http_response_size_bytes`, response size histogram partitioned over HTTP method

Custom configuration of the built in metrics is possible. An example structure can be seen in the synopsis. The four built in metrics from this plugin all have more or less the same structure. Metrics provided by the Perl- and Process-collectors from [Net::Prometheus](https://metacpan.org/pod/Net::Prometheus) can be used and changed by providing a custom `prometheus` object instead of using the defaults as detailed previously.

Default configuration for the built in metrics are as follows:

    http_request_duration_seconds => {
      buckets => [.005, .01, .025, .05, .075, .1, .25, .5, .75, 1.0, 2.5, 5.0, 7.5, 10],
      labels  => [qw/worker method/],
      cb      =>  sub($c) { $$, $c->req->method, tv_interval($c->stash('prometheus.start_time')) },
    }
    
    http_request_size_bytes => {
      buckets => [1, 50, 100, 1_000, 10_000, 50_000, 100_000, 500_000, 1_000_000],
      labels  => [qw/worker method/],
      cb      => sub($c) { $$, $c->req->method, $c->req->content->body_size },
    }
    
    http_response_size_bytes => {
      buckets => [5, 50, 100, 1_000, 10_000, 50_000, 100_000, 500_000, 1_000_000],
      labels  => [qw/worker method code/],
      cb      => sub($c) { $$, $c->req->method, $c->res->code, $c->res->content->body_size },
    }
    
    http_requests_total => {
      labels  => [qw/worker method code/],
      cb      => sub($c) { $$, $c->req->method, $c->res->code },
    }

# AUTHOR

- Vidar Tyldum / [TYLDUM](https://metacpan.org/author/TYLDUM) - Author
- Christopher Rasch-Olsen Raa / [CRORAA](https://metacpan.org/author/CRORAA) - Co-maintainer

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

# POD ERRORS

Hey! **The above document had some coding errors, which are explained below:**

- Around line 339:

    Expected '=item \*'

- Around line 360:

    Expected '=item \*'
