package Prometheus::MetricRenderer;
use Mojo::Base -base, -signatures;
use List::Util 'pairmap';
use Scalar::Util 'looks_like_number';

sub render($self, $metrics) {
	Mojo::Collection->new($metrics->@*)
		->map(sub {
			my $sampleset = $_;
			my $name      = $sampleset->fullname;
			my $help      = _format_help($sampleset);

			return (
				"# HELP $name $help",
				"# TYPE $name " . $sampleset->type,
				map { _format_sample($_) } $sampleset->samples->@*
			)
	})
	->join("\n");
}

sub _format_help($sampleset) {
	my $help = $sampleset->help;
	$help =~ s/\\/\\\\/g;
	$help =~ s/\n/\\n/g;
	return $help;
}

sub _format_sample($sample) {
	return unless defined $sample->value;
	my $value  = looks_like_number($sample->value) ? $sample->value : 'NaN';
	my $labels = _format_labels($sample->labels);
	sprintf '%s%s %s', $sample->varname, $labels, $value;
}

sub _format_labels($labels) {
	return '' unless scalar @$labels;
	return '{' . join(',', pairmap { $a . '=' . _escape_label_value($b) } @$labels ) . '}';
}

sub _escape_label_value($value) {
	$value =~ s/(["\\])/\\$1/g;
	$value =~ s/\n/\\n/g;
	return qq("$value");
}

1;
