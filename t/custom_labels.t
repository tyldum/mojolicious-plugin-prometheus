use Mojo::Base -strict;

use Test::More;
use Mojolicious::Lite;
use Test::Mojo;

plugin Prometheus => {
	http_requests_total_labels => [qw/worker method endpoint code/],
	http_requests_total_cb => sub {
		my $c = shift;
		return($$, $c->req->method, $c->match->endpoint->to_string, $c->res->code);
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
	->content_like(qr/http_requests_total\{worker="\d+",method="GET",endpoint="\/snails",code="200"\} 2/)
	->content_like(qr/http_requests_total\{worker="\d+",method="GET",endpoint="\/snails\/:type",code="200"\} 7/);

done_testing();
