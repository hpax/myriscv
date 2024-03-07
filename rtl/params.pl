#!/usr/bin/perl

use strict;
use integer;

print "`define CFGPARAMS";

my @params;

while (<>) {
    chomp;
    # XXX: this could fail on quoted strings!
    s/^\s*(|\w.*?\;)\s*(\/\/.*)?/$1/;
    /(\w+?)\s*[\;\=]/;
    my $pname = $1;
    next unless ($pname ne '');
    print " \\\n\tparameter $_";
    push(@params, $pname);
}

print "\n\n";

print "`define CFG \#\(";
my $pfx = '';
foreach my $p (@params) {
    print $pfx, " \\\n\t.$p ($p)";
    $pfx = ',';
}
print ")\n";
