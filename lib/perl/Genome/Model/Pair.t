#!/usr/bin/env genome-perl
use above "Genome";
use Test::More;
use Genome::Model::TestHelpers qw(
    define_test_classes
    create_test_sample
    create_test_pp
    create_test_model
);

define_test_classes();
my $sample = create_test_sample('test_sample');
my $pp = create_test_pp('test_pp');

my $first = create_test_model($sample, $pp, 'first_test_model');
my $second = create_test_model($sample, $pp, 'second_test_model');

my $m1 = Genome::Model->get($first);
ok($m1, "got model 1");

my $m2 = Genome::Model->get($second);
ok($m2, "got model 2");

my $pair = Genome::Model::Pair->get(first => $m1, second => $m2);
ok($pair, "got a pair for models");

is($pair->first, $m1, "first model is correct");
is($pair->second, $m2, "second model is correct");

done_testing();
