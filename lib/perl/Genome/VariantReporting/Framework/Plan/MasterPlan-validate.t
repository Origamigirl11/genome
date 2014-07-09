#!/usr/bin/env genome-perl

use strict;
use warnings FATAL => 'all';

use Test::More;
use above 'Genome';
use Genome::Utility::Test qw(compare_ok);
use Test::Exception;
use Test::Output;
use Genome::VariantReporting::Framework::Plan::TestHelpers; # defines classes

BEGIN {
    $ENV{UR_DBI_NO_COMMIT} = 1;
    $ENV{UR_USE_DUMMY_AUTOGENERATED_IDS} = 1;
};

my $pkg = 'Genome::VariantReporting::Framework::Plan::MasterPlan';
use_ok($pkg) || die;
test_bad_plan('missing_expert', qr(expert_missing) );
test_bad_plan('missing_filter', qr(filter_missing) );
test_bad_plan('missing_interpreter', qr(interpreter_missing) );
test_bad_plan('missing_reporter', qr(reporter_missing) );

test_bad_plan('misspelled_parameter', qr(bad_parameter_name) );
test_bad_plan('invalid_reporter', qr(Interpreters required), qr(Interpreters provided) );
test_bad_plan('invalid_experts', qr(Annotations required));

test_bad_yaml('invalid_yaml');

done_testing();


sub test_bad_plan {
    my $name = shift;
    my @error_regex = @_;

    my $filename = $name . '.yaml';

    my $plan_file = plan_file($filename);
    my $plan = $pkg->create_from_file($plan_file);
    ok($plan, sprintf("Made a plan from file ($plan_file)."));

    dies_ok sub {$plan->validate();}, "Validation fails for invalid plan ($name).";
    ok(my @errors = $plan->__errors__, 'Got some errors as expected');
    for my $error_regex (@error_regex) {
        stderr_like(sub {$plan->print_errors(@errors);}, $error_regex, "Errors look as expected for invalid plan ($name)");
    }
}

sub test_bad_yaml {
    my $name = shift;
    my $filename = $name . '.yaml';

    my $plan_file = plan_file($filename);
    throws_ok sub {$pkg->create_from_file($plan_file);}, qr(invalid information),
        "create_from_file fails for invalid yaml ($name).";
}

sub plan_file {
    my $filename = shift;
    return File::Spec->join(__FILE__ . ".d", $filename);
}


