requires 'perl', '5.008001';
requires 'Mojolicious';
requires 'Net::Prometheus';

on 'test' => sub {
    requires 'Test::More', '0.98';
};

