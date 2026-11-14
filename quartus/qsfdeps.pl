#!/usr/bin/perl
#
# Extract dependency files from a Quartus .qsf file
#

use strict;

my($project,$outfile,@infiles) = @ARGV;

my %dep_deps = ();
my %map_deps = ();
my %asm_deps = ();
my %cof_list = ();

my $output_dir = 'output_files';

sub read_file($) {
    my($infile) = @_;

    $dep_deps{$infile}++;
    $map_deps{$infile}++;

    open(my $in, '<', $infile) or die;
    while (defined(my $l = <$in>)) {
	chomp $l;

	if ($l =~ /^\s*include\s+\"?(.*?)\"?\s*$/) {
	    read_file($1);
	    next;
	} elsif ($l =~ /^\s*\#nodeps:\s*\"?(.*?)\"?\s*$/) {
	    delete $asm_deps{$1};
	    delete $map_deps{$1};
	    delete $cof_list{$1};
	    next;
	}

	next unless ($l =~ /^\s*set_global_assignment\s+\-name\s+(\w+)\s+\"?(.*?)\"?\s*$/);
	my $type = lc($1);
	my $name = $2;

	if ($type =~ /^project_output_directory$/i) {
	    $output_dir = $name;
	    next;
	}

	next if ($type !~ /_file$/i || $type =~ /^generate_/i);

	$name =~ s/^quartus_\w+://;
	$name =~ s/\s-.*$//;

	if ($name =~ /\.cof$/i) {
	    $cof_list{$name}++;
	} elsif ($type =~ /^(signaltap_file|use_signaltap_file|sld_file|cdf_file)$/i) {
	    # Skip
	} elsif ($type eq 'source_tcl_script_file' &&
		 $name =~ /\.qsf$/i) {
	    read_file($name);
	} elsif ($type =~ /^(mif|hex)_file$/i) {
	    $asm_deps{$name}++;
	} else {
	    $map_deps{$name}++;
	}
    }
    close($in);
}

sub print_deps($$%) {
    my($out,$prefix,%deps) = @_;

    print $out "\n", $prefix;

    foreach my $dep (sort keys(%deps)) {
	print $out " \\\n\t", $dep;
    }

    print $out "\n";
}

unlink($outfile);

foreach my $f (@infiles) {
    read_file($f);
}

open(my $out, '>', $outfile) or die;

print_deps($out, "${outfile} :", %dep_deps);

print_deps($out, "${project}_asm_deps := ", %asm_deps);
print $out "\n$output_dir/$project.mif_update.rpt: \$(${project}_asm_deps)\n";
print $out "\nall_asm_deps += \$(${project}_asm_deps)\n";

print_deps($out, "${project}_map_deps := ", %map_deps);
print $out "\n$output_dir/$project.map.rpt: \$(${project}_map_deps)\n";
print $out "\nall_map_deps += \$(${project}_map_deps)\n";

close($out);

exit 0;
