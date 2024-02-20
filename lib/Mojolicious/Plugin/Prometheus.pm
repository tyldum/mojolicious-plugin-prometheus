package Mojolicious::Plugin::Prometheus;
use Mojo::Base 'Mojolicious::Plugin', -signatures;
use Mojolicious::Plugin::Prometheus::Collector::Perl;
use IPC::ShareLite;
use Net::Prometheus;
use Time::HiRes qw/gettimeofday tv_interval/;
use Mojo::Collection;
use Mojolicious::Plugin::Prometheus::Guard;
use Prometheus::MetricRenderer;

our $VERSION = '1.4.1';

has prometheus => \&_prometheus;
has guard   => \&_guard;
has share   => \&_share;
has route   => sub { undef };
has shm_key => sub { $$ };

has global_collectors => sub { Mojo::Collection->new };

# Attributes to hold the different metrics that are registered
has http_request_duration_seconds => sub { undef };
has http_request_size_bytes       => sub { undef };
has http_response_size_bytes      => sub { undef };
has http_requests_total           => sub { undef };

# Configuration for the default metric types
has config => sub {
  {
    http_request_duration_seconds => {
      buckets => [.005, .01, .025, .05, .075, .1, .25, .5, .75, 1.0, 2.5, 5.0, 7.5, 10],
      labels  => [qw/worker method/],
      cb      => sub($c) { $$, $c->req->method, tv_interval($c->stash('prometheus.start_time')) },
    },
    http_request_size_bytes => {
      buckets => [1, 50, 100, 1_000, 10_000, 50_000, 100_000, 500_000, 1_000_000],
      labels  => [qw/worker method/],
      cb      => sub($c) { $$, $c->req->method, $c->req->content->body_size },
    },
    http_response_size_bytes => {
      buckets => [5, 50, 100, 1_000, 10_000, 50_000, 100_000, 500_000, 1_000_000],
      labels  => [qw/worker method code/],
      cb      => sub($c) { $$, $c->req->method, $c->res->code, $c->res->content->body_size },
    },
    http_requests_total => {
      labels  => [qw/worker method code/],
      cb      => sub($c) { $$, $c->req->method, $c->res->code },
    },
    perl_collector => {
      enabled   => 1,
      labels_cb => sub { { worker => $$ } },
    },
    process_collector => {
      enabled   => 1,
      labels_cb => sub { { worker => $$ } },
    },
  }
};

sub register($self, $app, $config = {}) {
  $self->shm_key($config->{shm_key}) if $config->{shm_key};

  for(keys $self->config->%*) {
    next unless $config->{$_};
    $self->config->{$_} = { $self->config->{$_}->%*, $config->{$_}->%* };
  }

  # Present _only_ for a short while for backward compat
  $self->config->{http_request_duration_seconds}{buckets} = $config->{duration_buckets} if $config->{duration_buckets};
  $self->config->{http_request_size_bytes}{buckets}       = $config->{request_buckets}  if $config->{request_buckets};
  $self->config->{http_response_size_bytes}{buckets}      = $config->{response_buckets} if $config->{response_buckets};

  # Net::Prometheus instance can be overridden in its entirety
  $self->prometheus($config->{prometheus}) if $config->{prometheus};

  # Only the two built-in servers are supported for now
  $app->hook(before_server_start => sub { $self->_start(@_, $config) });

  $self->http_request_duration_seconds(
    $self->prometheus->new_histogram(
      namespace => $config->{namespace}        // undef,
      subsystem => $config->{subsystem}        // undef,
      name      => "http_request_duration_seconds",
      help      => "Histogram with request processing time",
      labels    => $self->config->{http_request_duration_seconds}{labels},
      buckets   => $self->config->{http_request_duration_seconds}{buckets},
    )
  );

  $self->http_request_size_bytes(
    $self->prometheus->new_histogram(
      namespace => $config->{namespace} // undef,
      subsystem => $config->{subsystem} // undef,
      name      => "http_request_size_bytes",
      help      => "Histogram containing request sizes",
      labels    => $self->config->{http_request_size_bytes}{labels},
      buckets   => $self->config->{http_request_size_bytes}{buckets},
    )
  );

  $self->http_response_size_bytes(
    $self->prometheus->new_histogram(
      namespace => $config->{namespace} // undef,
      subsystem => $config->{subsystem} // undef,
      name      => "http_response_size_bytes",
      help      => "Histogram containing response sizes",
      labels    => $self->config->{http_response_size_bytes}{labels},
      buckets   => $self->config->{http_response_size_bytes}{buckets},
    )
  );

  $self->http_requests_total(
    $self->prometheus->new_counter(
      namespace => $config->{namespace} // undef,
      subsystem => $config->{subsystem} // undef,
      name      => "http_requests_total",
      help      => "How many HTTP requests processed, partitioned by status code and HTTP method.",
      labels    => $self->config->{http_requests_total}{labels},
    )
  );

  $app->hook(
    before_dispatch => sub {
      my ($c) = @_;
      $c->stash('prometheus.start_time' => [gettimeofday]);
      $self->http_request_size_bytes->observe($self->config->{http_request_size_bytes}{cb}->($c));
    }
  );

  $app->hook(
    after_render => sub {
      my ($c) = @_;
      $self->http_request_duration_seconds->observe($self->config->{http_request_duration_seconds}{cb}->($c));
    }
  );

  $app->hook(
    after_dispatch => sub {
      my ($c) = @_;
      $self->http_requests_total->inc($self->config->{http_requests_total}{cb}->($c));
      $self->http_response_size_bytes->observe($self->config->{http_response_size_bytes}{cb}->($c));
    }
  );

  # Create common helper methods
  $app->helper('prometheus.instance' => sub { $self->prometheus });
  $app->helper('prometheus.register' => \&_register);

	# Plugin-internal helper methods
  $app->helper('prometheus.collect' => \&_collect);
  $app->helper('prometheus.guard'   => sub { $self->guard });
  $app->helper('prometheus.global_collectors' => sub { $self->global_collectors });

  # Create the endpoint that should serve metrics
  my $prefix = $config->{route} // $app->routes->under('/');
  $self->route($prefix->get($config->{path} // '/metrics'));
  $self->route->to(cb => \&_metrics);
}

sub _metrics($c) {
  $c->render(text => $c->prometheus->collect, format => 'txt');
}

sub _register($c, $collector, $scope = 'worker') {
  return $c->prometheus->instance->register($collector) if $scope eq 'worker';
  return push $c->prometheus->global_collectors->@*, $collector;
}

sub _collect($c) {
  # Update stats for current worker
  $c->prometheus->guard->_change(sub { $_->{$$} = $c->prometheus->instance->render });

  # Fetch stats for all worker-specific collectors
  my $worker_stats = Mojo::Collection->new(keys %{$c->prometheus->guard->_fetch})
    ->sort
    ->map(sub { ($c->prometheus->guard->_fetch->{$_}) })
    ->join("\n");

  # Fetch stats for global / on-demand collectors
  my $renderer = Prometheus::MetricRenderer->new;
  my $global_stats = $c->prometheus->global_collectors
    ->map(sub { [ $_->collect({}) ] })
    ->map(sub { $renderer->render($_) })
    ->join("\n");

  return $worker_stats."\n".$global_stats."\n";
}

sub _share($self) {
  IPC::ShareLite->new(-key => $self->shm_key, -create => 1, -destroy => 0) || die $!;
}

sub _guard($self) {
  Mojolicious::Plugin::Prometheus::Guard->new(share => $self->share);
}

sub _start {
  my ($self, $server, $app, $config) = @_;
  return unless $server->isa('Mojo::Server::Daemon');

  Mojo::IOLoop->next_tick(
    sub {
      my $labels    = $self->config->{process_collector}{labels_cb}->();
      my $collector = Net::Prometheus::ProcessCollector->new(labels => [%$labels]);
      $app->prometheus->register($collector);
    }
  ) if $self->config->{process_collector}{enabled};

  # Remove stopped workers
  $server->on(
    reap => sub {
      my ($server, $pid) = @_;
      $self->guard->_change(sub { delete $_->{$pid} });
    }
  ) if $server->isa('Mojo::Server::Prefork');
}

sub _prometheus($self) {
  my $prometheus = Net::Prometheus->new(disable_process_collector => 1, disable_perl_collector => 1);

  # Adding the Perl-collector, if enabled
  if($self->config->{perl_collector}{enabled}) {
    my $perl_collector = Mojolicious::Plugin::Prometheus::Collector::Perl->new($self->config->{perl_collector});
    $prometheus->register($perl_collector);
  }
  return $prometheus;
};

1;

__END__

=for stopwords prometheus

=encoding utf8

=head1 NAME

Mojolicious::Plugin::Prometheus - Mojolicious Plugin

=head1 SYNOPSIS

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

=head1 DESCRIPTION

L<Mojolicious::Plugin::Prometheus> is a L<Mojolicious> plugin that exports Prometheus metrics from Mojolicious.

Hooks are also installed to measure requests response time and count requests based on method and HTTP return code.

=head1 HELPERS

=head2 prometheus

Create further instrumentation into your application by using this helper which gives access to the L<Net::Prometheus> object.
See L<Net::Prometheus> for usage.

=head1 METHODS

L<Mojolicious::Plugin::Prometheus> inherits all methods from
L<Mojolicious::Plugin> and implements the following new ones.

=head2 register

  $plugin->register($app, \%config);

Register plugin in L<Mojolicious> application.

C<%config> can have:

=over 2

=item * route

L<Mojolicious::Routes::Route> object to attach the metrics to, defaults to generating a new one for '/'.

Default: /

=item * path

The path to mount the exporter.

Default: /metrics

=item * prometheus

Override the L<Net::Prometheus> object. The default is a new singleton instance of L<Net::Prometheus>.

=item * namespace, subsystem

These will be prefixed to the metrics exported.

=item * shm_key

Key used for shared memory access between workers, see L<$key in IPC::ShareLite|https://metacpan.org/pod/IPC::ShareLite> for details. Default is the process id read from C<$$>.

=item * http_request_duration_seconds

Structure that overrides the configuration for the C<http_request_duration_seconds> metric. See below.

=item * http_request_size_bytes

Structure that overrides the configuration for the C<http_request_size_bytes> metric. See below.

=item * http_response_size_bytes

Structure that overrides the configuration for the C<http_response_size_bytes> metric. See below.

=item * http_requests_total

Structure that overrides the configuration for the C<http_requests_total> metric. See below.

=item perl_collector

Structure that tells the plugin to enable or disable a Perl collector. Previously the Perl collector from L<Net::Prometheus> was used, but that is no longer in use due to it not being possible to add dynamic label values. Now L<Mojolicious::Plugin::Prometheus::Collector::Perl> is used. The configuration here need as follows:

=over 4

=item enabled

Boolean-ish value indicating if this collector should be used.

=item labels_cb

A subref that the collector can call to dynamically resolve which labels and corresponding label values should be added to each metric. Default is:

  {
    enabled   => 1,
    labels_cb => sub { { worker => $$ } },
  }

=back

=item process_collector

Structure that tells the plugin to enable or disable a process collector. The process collector from L<Net::Prometheus> is used for this. The configuration here need as follows:

=over 4

=item enabled

Boolean-ish value indicating if this collector should be used.

=item labels_cb

A subref that the collector can call to dynamically resolve which labels and corresponding label values should be added to each metric. Default is:

  {
    enabled   => 1,
    labels_cb => sub { { worker => $$ } },
  }

=back

=back

=head1 METRICS

In addition to exposing the default process metrics that L<Net::Prometheus> already expose
this plugin will also expose

=over 2

=item * C<http_requests_total>, request counter partitioned over HTTP method and HTTP response code

=item * C<http_request_duration_seconds>, request duration histogram partitioned over HTTP method

=item * C<http_request_size_bytes>, request size histogram partitioned over HTTP method

=item * C<http_response_size_bytes>, response size histogram partitioned over HTTP method

=back

Custom configuration of the built in metrics is possible. An example structure can be seen in the synopsis. The four built in metrics from this plugin all have more or less the same structure. Metrics provided by the Perl- and Process-collectors from L<Net::Prometheus|https://metacpan.org/pod/Net::Prometheus> can be used and changed by providing a custom C<prometheus> object instead of using the defaults as detailed previously.

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

=head1 AUTHOR

=over 2

=item * Vidar Tyldum / L<TYLDUM|https://metacpan.org/author/TYLDUM> - Author

=item * Christopher Rasch-Olsen Raa / L<CRORAA|https://metacpan.org/author/CRORAA> - Co-maintainer

=back

(the IPC::ShareLite parts of this code is shamelessly stolen from L<Mojolicious::Plugin::Status> written by Sebastian Riedel and mangled into something that works for me)

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2018, Vidar Tyldum

This program is free software, you can redistribute it and/or modify it under
the terms of the Artistic License version 2.0.

=head1 SEE ALSO

=over 2

=item L<Net::Prometheus>

=item L<Mojolicious::Plugin::Status>

=item L<Mojolicious>

=item L<Mojolicious::Guides>

=item L<http://mojolicious.org>

=back

=cut
