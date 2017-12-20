package Mojolicious::Plugin::Prometheus;
use Mojo::Base 'Mojolicious::Plugin';
use Time::HiRes qw/gettimeofday tv_interval/;
use Net::Prometheus;

our $VERSION = '0.1';

has prometheus => sub { state $prom = Net::Prometheus->new };
has route => sub {undef};
has http_request_duration_seconds => sub {
    undef;
};
has http_requests_total => sub {
    undef;
};

sub register {
    my ( $self, $app, $config ) = @_;

    $self->http_request_duration_seconds(
        $self->prometheus->new_histogram(
            namespace => $config->{namespace} // undef,
            subsystem => $config->{subsystem} // undef,
            name      => "http_request_duration_seconds",
            help      => "Summary request processing time",
            labels    => [qw/method/],
        )
    );

    $self->http_requests_total(
        $self->prometheus->new_counter(
            namespace => $config->{namespace} // undef,
            subsystem => $config->{subsystem} // undef,
            name      => "http_requests_total",
            help =>
                "How many HTTP requests processed, partitioned by status code and HTTP method.",
            labels => [qw/method code/],
        )
    );

    $self->route( $app->routes->get( $config->{path} // '/metrics' ) );
    $self->route->to(
        cb => sub {
            my ($c) = @_;
            $c->render( text => $c->prometheus->render, format => 'txt' );
        }
    );

    $app->hook(
        before_dispatch => sub {
            my ($c) = @_;
            $c->stash( 'prometheus.start_time' => [gettimeofday] );
        }
    );

    $app->hook(
        after_render => sub {
            my ($c) = @_;
            $self->http_request_duration_seconds->observe( $c->req->method,
                tv_interval( $c->stash('prometheus.start_time') ) );
        }
    );

    $app->hook(
        after_dispatch => sub {
            my ($c) = @_;
            $self->http_requests_total->inc( $c->req->method, $c->res->code );
        }
    );

    $app->helper( prometheus => sub { $self->prometheus } );

}

1;
__END__

=encoding utf8

=head1 NAME

Mojolicious::Plugin::Prometheus - Mojolicious Plugin

=head1 SYNOPSIS

  # Mojolicious
  $self->plugin('Prometheus');

  # Mojolicious::Lite
  plugin 'Prometheus';

=head1 DESCRIPTION

L<Mojolicious::Plugin::Prometheus> is a L<Mojolicious> plugin that exports Prometheus metrics from Mojolicious.

Hooks are also installed to measure requests response time and count requests based on method and HTTP return code.

=head1 HELPERS

=head2 prometheus

Create further instrumentation into your application by using this helper which gives access to the L<Net::Prometheus> object.

=head1 METHODS

L<Mojolicious::Plugin::Prometheus> inherits all methods from
L<Mojolicious::Plugin> and implements the following new ones.

=head2 register

  $plugin->register($app, \&config);

Register plugin in L<Mojolicious> application.

C<%config> can have:

=over2

=item * path

The path to mount the exporter.

Default: /metrics

=item * prometheus

Override the L<Net::Prometheus> object. The default is a new singleton instance of L<Net::Prometheus>.

=item * namespace

=item * subsystem

These will be prefixed to the metrics exported.

=back

=head1 METRICS

In addition to exporting the default process metrics that L<Net::Prometheus> already export
this plugin will also export

=over2

=item http_requests_total, counter partitioned over HTTP method and HTTP response code

=item http_request_duration_seconds, histogram partitoned over HTTP method

=back

=head1 AUTHOR

Vidar Tyldum

=head1 COPYRIGHT AND LICENSE
Copyright (C) 2017, Vidar Tyldum
This program is free software, you can redistribute it and/or modify it under
the terms of the Artistic License version 2.0.

=head1 SEE ALSO

=over2

=item L<Net::Prometheus>

=item L<Mojolicious>

=item L<Mojolicious::Guides>

=item L<http://mojolicious.org>

=back

=cut
