package Mojolicious::Plugin::Prometheus::Guard;
use Mojo::Base -base, -signatures;

use Fcntl ':flock';
use Sereal qw(get_sereal_decoder get_sereal_encoder);

has 'share';

sub _change($self, $cb) {
	$self->share->lock(LOCK_EX);

	my $stats = $self->_fetch;
	$cb->($_) for $stats;
	$self->_store($stats);

	$self->share->unlock;
}

sub _fetch($self) {
	return {} unless my $data = $self->share->fetch;
	return get_sereal_decoder->decode($data);
}

sub _store($self, $value) {
	$self->share->store(get_sereal_encoder->encode($value));
}

1;
