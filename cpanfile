requires 'Mojolicious';
requires 'Net::Prometheus';
requires 'Time::HiRes';

on 'test' => sub {
    requires 'Test::More', '0.98';
};

