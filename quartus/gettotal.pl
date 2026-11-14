#!/usr/bin/perl
#
# Extract benchmark figures from Quartus reports
#

use strict;

my($fit_rpt, $sta_rpt) = @ARGV;

my $le;
my $mhz;

open(my $fit, '<', $fit_rpt) or die "$0: $fit_rpt: $!\n";

while (defined(my $l = <$fit>)) {
    if ($l =~ /^;\s*Total logic elements\s*;\s*([0-9,]+)\s*\//) {
	$le = $1;
	$le =~ s/\,//g;
	$le += 0;		# It is a number
	last;
    }
}
close($fit);

if (!defined($le)) {
    die "$0: $fit_rpt: No total logic elements count found\n";
}

open(my $sta, '<', $sta_rpt) or die "$0: $sta_rpt: $!\n";

my $watching = 0;
while (defined(my $l = <$sta>)) {
    if ($l =~ /^;\s*Slow 1200mV 85C Model Fmax Summary/) {
	$watching = 1;
    } elsif ($l !~ /^[+;]/) {
	$watching = 0;
    } elsif ($watching && $l =~ /^\;\s*([0-9\.]+) MHz/) {
	$mhz = $1 + 0.0;
	last;
    }
}
close($sta);

if (!defined($mhz)) {
    die "$0: $sta_rpt: No Slow 1200mV 85C Model Fmax Summary found\n";
}

printf "%d LE, %.2f MHz\n", $le, $mhz;
