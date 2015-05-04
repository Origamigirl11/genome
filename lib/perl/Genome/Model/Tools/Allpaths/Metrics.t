#!/usr/bin/env genome-perl

use strict;
use warnings;

use above "Genome";

require File::Compare;
use Test::More;

use_ok('Genome::Model::Tools::Allpaths::Metrics') or die;

my $test_dir = Genome::Config::get('test_inputs') . '/Genome-Model-Tools-Allpaths/Metrics/v8';
my $example_metrics_file = $test_dir.'/metrics.txt';

my $temp_dir = Genome::Sys->create_temp_directory();
my $metrics_file = $temp_dir.'/metrics.1.txt';
my $clean_fasta  = $temp_dir.'/clean.final.assembly.1.fasta';
my $metrics = Genome::Model::Tools::Allpaths::Metrics->create(
    assembly_directory => $test_dir,
    major_contig_length => 300,
    output_file => $metrics_file,
    output_clean_assembly_fasta_file => $clean_fasta,
);
ok($metrics, "create") or die;
$metrics->dump_status_messages(1);
ok($metrics->execute, "execute") or die;
is(File::Compare::compare($metrics_file, $example_metrics_file), 0, "files match");

$metrics_file = $temp_dir.'/metrics.2.txt';
$clean_fasta  = $temp_dir.'/clean.final.assembly.2.fasta';
$metrics = Genome::Model::Tools::Allpaths::Metrics->create(
    assembly_directory => $test_dir.'/reads_with_metrics',
    major_contig_length => 300,
    output_file => $metrics_file,
    output_clean_assembly_fasta_file => $clean_fasta,
);
ok($metrics, "create") or die;
$metrics->dump_status_messages(1);
ok($metrics->execute, "execute") or die;
is(File::Compare::compare($metrics_file, $example_metrics_file), 0, "files match");

#print "gvimdiff $metrics_file $example_metrics_file\n"; system "gvimdiff $metrics_file $example_metrics_file"; <STDIN>;
done_testing();
