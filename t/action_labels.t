use Mojo::Base -strict;

use Test::More;
use Mojolicious::Lite;
use Test::Mojo;

plugin Prometheus => { action => 1 };

get '/snails' => sub { shift->render(text => 'Hello Frenchie!') };
get '/snails/:type' => sub { shift->render(text => 'Bon Appétit!') };

my $t = Test::Mojo->new;
$t->get_ok('/snails')->status_is(200) for 1..2;
$t->get_ok('/snails/garden')->status_is(200) for 1..3;
$t->get_ok('/snails/burgundy')->status_is(200) for 1..4;

# Requests that match no route, the request path is used as action
$t->get_ok('/cats')->status_is(404) for 1..5;

# The built in http metrics carry the "action" label
$t->get_ok('/metrics')
	->status_is(200)
	->content_type_like(qr(^text/plain))
	->content_like(qr/http_requests_total\{action="\/snails",worker="\d+",method="GET",code="200"\} 2/)
	->content_like(qr/http_requests_total\{action="\/snails\/:type",worker="\d+",method="GET",code="200"\} 7/)
	->content_like(qr/http_requests_total\{action="\/cats",worker="\d+",method="GET",code="404"\} 5/)
	->content_like(qr/http_request_duration_seconds_count\{action="\/snails",worker="\d+",method="GET"\} 2/)
	->content_like(qr/http_request_duration_seconds_count\{action="\/snails\/:type",worker="\d+",method="GET"\} 7/)
	->content_like(qr/http_request_size_bytes_count\{action="\/snails",worker="\d+",method="GET"\} 2/)
	->content_like(qr/http_response_size_bytes_count\{action="\/snails",worker="\d+",method="GET",code="200"\} 2/)
	->content_like(qr/http_response_size_bytes_count\{action="\/cats",worker="\d+",method="GET",code="404"\} 5/);

done_testing();
