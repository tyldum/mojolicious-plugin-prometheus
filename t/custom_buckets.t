use Mojo::Base -strict;

use Test::More;
use Mojolicious::Lite;
use Test::Mojo;

plugin 'Prometheus' => {
	http_request_size_bytes => {
		buckets => [qw/1 2 3/],
	},
};

get '/' => sub {
  my $c = shift;
  $c->render(text => 'Hello Mojo!');
};

my $t = Test::Mojo->new;
$t->get_ok('/')->status_is(200)->content_like(qr/Hello Mojo!/);

$t->get_ok('/metrics')->status_is(200)->content_type_like(qr(^text/plain))
	->content_like(qr/http_request_size_bytes_count\{worker="\d+",method="GET"\} \d/)
	->content_like(qr/http_request_size_bytes_bucket\{worker="\d+",method="GET",le="1"\} \d/)
	->content_like(qr/http_request_size_bytes_bucket\{worker="\d+",method="GET",le="2"\} \d/)
	->content_like(qr/http_request_size_bytes_bucket\{worker="\d+",method="GET",le="3"\} \d/);

done_testing();
