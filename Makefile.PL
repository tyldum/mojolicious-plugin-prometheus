use strict;
use warnings;

use ExtUtils::MakeMaker;

WriteMakefile(
  NAME         => 'Mojolicious::Plugin::Prometheus',
  VERSION_FROM => 'lib/Mojolicious/Plugin/Prometheus.pm',
  AUTHOR       => 'A Good Programmer <nospam@cpan.org>',
  PREREQ_PM    => {'Mojolicious' => '7.59'},
  test         => {TESTS => 't/*.t'}
);
