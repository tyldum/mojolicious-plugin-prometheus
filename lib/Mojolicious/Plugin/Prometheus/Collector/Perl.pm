package Mojolicious::Plugin::Prometheus::Collector::Perl;
use Mojo::Base -base, -signatures;
use Mojo::Collection;
use Net::Prometheus::Types qw( MetricSamples Sample );
use Net::Prometheus::PerlCollector;

has detail       => 0;
has labels_cb    => sub {{}};
has perl_version => sub { ( $^V =~ m/^v(.*)$/ )[0] };

sub collect($self, $opts) {
	my @samples = (
		MetricSamples(
			'perl_info',
			gauge => 'Perl interpreter version',
			[ Sample( 'perl_info', [ version => $self->perl_version, $self->labels_cb->()->%* ], 1 ) ]
		),
	);
	return @samples unless Net::Prometheus::PerlCollector::HAVE_XS;

	my ($arenas, $svs, $svs_by_type, $svs_by_class) = Net::Prometheus::PerlCollector::count_heap($self->detail);

	push @samples, MetricSamples(
		'perl_heap_arenas',
		gauge => 'Number of arenas in the Perl heap',
		[ Sample('perl_heap_arenas', [$self->labels_cb->()->%*], $arenas) ]
	);
	push @samples, MetricSamples(
		'perl_heap_svs',
		gauge => 'Number of SVs in the Perl heap',
		[ Sample('perl_heap_svs', [$self->labels_cb->()->%*], $svs) ]
	);

	if($svs_by_type) {
		my $by_type = Mojo::Collection->new(keys %$svs_by_type)
			->sort
			->map(sub { Sample('perl_heap_svs_by_type', [ type => $_, $self->labels_cb->()->%* ], $svs_by_type->{$_}) })
			->to_array;
		push @samples, MetricSamples('perl_heap_svs_by_type', gauge => 'Number of SVs classified by type', $by_type);
	}

	if($svs_by_class) {
		my $by_class = Mojo::Collection->new(keys %$svs_by_class)
			->sort
			->map(sub { Sample('perl_heap_svs_by_class', [ class => $_, $self->labels_cb->()->%* ], $svs_by_class->{$_}) })
			->to_array;
		push @samples, MetricSamples('perl_heap_svs_by_class', gauge => 'Number of SVs classified by class', $by_class);
	}

	return @samples;
}

1;
