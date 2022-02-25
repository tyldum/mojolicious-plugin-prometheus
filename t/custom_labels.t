use Mojo::Base -strict;

use Test::More;
use Mojolicious::Lite;
use Test::Mojo;
use Time::HiRes qw/tv_interval/;

plugin Prometheus => {
	shm_key => time(),

	# Override to get the endpoint (route url) as a label
	http_requests_total => {
		labels => [qw/worker method endpoint code/],
		cb     => sub {
			my $c = shift;
			return ($$, $c->req->method, $c->match->endpoint->to_string, $c->res->code);
		},
	},

	# Override to get information from the URL as a label.
	# You wouldn't actually do this though. This is just an example.
	http_request_duration_seconds => {
		labels => [qw/worker method snailtype/],
		cb     => sub {
			my $c = shift;
			return ($$, $c->req->method, $c->param('type') // 'unknown', tv_interval($c->stash('prometheus.start_time')));
		},
	},
};
get '/snails' => sub { shift->render(text => 'Hello Frenchie!') };
get '/snails/:type' => sub { shift->render(text => 'Bon Appétit!') };

my $t = Test::Mojo->new;
$t->get_ok('/snails')->status_is(200) for 1..2;
$t->get_ok('/snails/garden') for 1..3;
$t->get_ok('/snails/burgundy')->status_is(200) for 1..4;

$t->get_ok('/metrics')
	->status_is(200)
	->content_like(qr/http_request_duration_seconds_count\{worker="\d+",method="GET",snailtype="unknown"\} 2/)
	->content_like(qr/http_request_duration_seconds_count\{worker="\d+",method="GET",snailtype="garden"\} 3/)
	->content_like(qr/http_request_duration_seconds_count\{worker="\d+",method="GET",snailtype="burgundy"\} 4/)
	->content_like(qr/http_requests_total\{worker="\d+",method="GET",endpoint="\/snails",code="200"\} 2/)
	->content_like(qr/http_requests_total\{worker="\d+",method="GET",endpoint="\/snails\/:type",code="200"\} 7/);

done_testing();
