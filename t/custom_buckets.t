use Mojo::Base -strict;

use Test::More;
use Mojolicious::Lite;
use Test::Mojo;

plugin 'Prometheus' => {
	duration_buckets => [qw/1 2 3/],
	request_buckets  => [qw/4 5 6/],
	response_buckets => [qw/7 8 9/],
};

get '/' => sub {
  my $c = shift;
  $c->render(text => 'Hello Mojo!');
};

my $t = Test::Mojo->new;
$t->get_ok('/')->status_is(200)->content_like(qr/Hello Mojo!/);

$t->get_ok('/metrics')->status_is(200)->content_type_like(qr(^text/plain))
	->content_like(qr/http_request_duration_seconds_bucket\{worker="\d+",method="GET",le="1"\} \d/)
	->content_like(qr/http_request_duration_seconds_bucket\{worker="\d+",method="GET",le="2"\} \d/)
	->content_like(qr/http_request_duration_seconds_bucket\{worker="\d+",method="GET",le="3"\} \d/)
	->content_like(qr/http_request_size_bytes_bucket\{worker="\d+",method="GET",le="4"\} \d/)
	->content_like(qr/http_request_size_bytes_bucket\{worker="\d+",method="GET",le="5"\} \d/)
	->content_like(qr/http_request_size_bytes_bucket\{worker="\d+",method="GET",le="6"\} \d/)
	->content_like(qr/http_response_size_bytes_bucket\{worker="\d+",method="GET",code="200",le="7"\} \d/)
	->content_like(qr/http_response_size_bytes_bucket\{worker="\d+",method="GET",code="200",le="8"\} \d/)
	->content_like(qr/http_response_size_bytes_bucket\{worker="\d+",method="GET",code="200",le="9"\} \d/);

done_testing();
