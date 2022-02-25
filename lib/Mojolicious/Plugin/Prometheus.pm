package Mojolicious::Plugin::Prometheus;
use Mojo::Base 'Mojolicious::Plugin', -signatures;
use Time::HiRes qw/gettimeofday tv_interval/;
use Net::Prometheus;
use IPC::ShareLite;

our $VERSION = '1.3.1';

has prometheus => sub { Net::Prometheus->new(disable_process_collector => 1) };
has route => sub {undef};

# Attributes to hold the different metrics that is registered
has http_request_duration_seconds => sub { undef };
has http_request_size_bytes => sub { undef };
has http_response_size_bytes => sub { undef };
has http_requests_total => sub { undef };

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
	}
};

sub register($self, $app, $config = {}) {
  $self->{key} = $config->{shm_key} || '12345';

  for(keys $self->config->%*) {
    next unless $config->{$_};
    $self->config->{$_} = { $self->config->{$_}->%*, $config->{$_}->%* };
  }

  # Present _only_ for a short while for backward compat
  $self->config->{http_request_size_bytes}{buckets} = $config->{request_buckets} if $config->{request_buckets};
  $self->config->{http_request_duration_seconds}{buckets} = $config->{duration_buckets} if $config->{duration_buckets};
  $self->config->{http_response_size_bytes}{buckets} = $config->{response_buckets} if $config->{response_buckets};

  # Net::Prometheus instance can be overridden in its entirety
  $self->prometheus($config->{prometheus}) if $config->{prometheus};
  $app->helper(prometheus => sub { $self->prometheus });

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


  my $prefix = $config->{route} // $app->routes->under('/');
  $self->route($prefix->get($config->{path} // '/metrics'));
  $self->route->to(
    cb => sub {
      my ($c) = @_;
      # Collect stats and render
      $self->_guard->_change(sub { $_->{$$} = $app->prometheus->render });
      $c->render(
        text => join("\n",
          map { ($self->_guard->_fetch->{$_}) }
          sort keys %{$self->_guard->_fetch}),
        format => 'txt'
      );
    }
  );

}

sub _guard {
  my $self = shift;

  my $share = $self->{share}
    ||= IPC::ShareLite->new(-key => $self->{key}, -create => 1, -destroy => 0)
    || die $!;

  return Mojolicious::Plugin::Mojolicious::_Guard->new(share => $share);
}

sub _start {
  my ($self, $server, $app, $config) = @_;
  return unless $server->isa('Mojo::Server::Daemon');

  Mojo::IOLoop->next_tick(
    sub {
      my $pc = Net::Prometheus::ProcessCollector->new(labels => [worker => $$]);
      $self->prometheus->register($pc) if $pc;
    }
  );

  # Remove stopped workers
  $server->on(
    reap => sub {
      my ($server, $pid) = @_;
      $self->_guard->_change(sub { delete $_->{$pid} });
    }
  ) if $server->isa('Mojo::Server::Prefork');
}

package Mojolicious::Plugin::Mojolicious::_Guard;
use Mojo::Base -base;

use Fcntl ':flock';
use Sereal qw(get_sereal_decoder get_sereal_encoder);

my ($DECODER, $ENCODER) = (get_sereal_decoder, get_sereal_encoder);

sub DESTROY { shift->{share}->unlock }

sub new {
  my $self = shift->SUPER::new(@_);
  $self->{share}->lock(LOCK_EX);
  return $self;
}

sub _change {
  my ($self, $cb) = @_;
  my $stats = $self->_fetch;
  $cb->($_) for $stats;
  $self->_store($stats);
}

sub _fetch {
  return {} unless my $data = shift->{share}->fetch;
  return $DECODER->decode($data);
}

sub _store { shift->{share}->store($ENCODER->encode(shift)) }

1;
__END__

=for stopwords prometheus

=encoding utf8

=head1 NAME

Mojolicious::Plugin::Prometheus - Mojolicious Plugin

=head1 SYNOPSIS

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

=item * request_buckets

Override buckets for request sizes histogram.

Default: C<(1, 50, 100, 1_000, 10_000, 50_000, 100_000, 500_000, 1_000_000)>

=item * response_buckets

Override buckets for response sizes histogram.

Default: C<(5, 50, 100, 1_000, 10_000, 50_000, 100_000, 500_000, 1_000_000)>

=item * duration_buckets

Override buckets for request duration histogram.

Default: C<(0.005, 0.01, 0.025, 0.05, 0.075, 0.1, 0.25, 0.5, 0.75, 1.0, 2.5, 5.0, 7.5, 10)> (actually see L<Net::Prometheus|https://metacpan.org/source/PEVANS/Net-Prometheus-0.05/lib/Net/Prometheus/Histogram.pm#L19>)

=item * shm_key

Key used for shared memory access between workers, see L<$key in IPc::ShareLite|https://metacpan.org/pod/IPC::ShareLite> for details.

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

=head1 AUTHOR

Vidar Tyldum

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
