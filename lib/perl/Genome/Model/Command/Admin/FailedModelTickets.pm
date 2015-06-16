package Genome::Model::Command::Admin::FailedModelTickets;

use strict;
use warnings;

use Genome;

use Data::Dumper 'Dumper';
use Error qw(:try);
use File::Find 'find';
use File::Grep 'fgrep';
require IO::Prompt;
require RT::Client::REST;
require RT::Client::REST::Ticket;
require WWW::Mechanize;

BEGIN {
        $ENV{UR_DBI_NO_COMMIT} = 1;
}

class Genome::Model::Command::Admin::FailedModelTickets {
    is => 'Genome::Command::WithColor',
    doc => 'find failed cron models, check that they are in a ticket',
    has_input => [
        include_failed => {
            is => 'Boolean',
            default_value => 1,
            doc => 'Include builds with status Failed',
        },
        include_unstartable => {
            is => 'Boolean',
            default_value => 1,
            doc => 'Include builds with status Unstartable',
        },
        include_pending => {
            is => 'Boolean',
            default_value => 0,
            doc => 'Include builds whose model status is requested, scheduled, or running.',
        },
    ],
};

sub help_detail {
    return <<HELP;
This command collects cron models by failed or unstartable build events and scours tickets for them. If they are not found, the models are summaraized first by the error entry log and then by grepping the error log files. The summary is the printed to STDOUT.
HELP
}

sub execute {
    my $self = shift;

    my %builds = $self->get_builds();

    $self->remove_builds_in_tickets(\%builds);

    my $build_errors = $self->get_build_errors(%builds);

    # Report
    $self->status_message("\n\n");
    $self->status_message(join("\n\n", map { $build_errors->{$_} } sort keys %$build_errors));

    return 1;
}

sub get_builds {
    my $self = shift;

    # Find cron models by failed build events
    my @builds;
    if ($self->include_failed) {
        $self->status_message('Looking for failed builds...');
        @builds = Genome::Model::Build->get(
            status => 'Failed',
            run_by => 'apipe-builder',
        );
    }

    # Find cron models by unstartable build events
    if ($self->include_unstartable) {
        $self->status_message('Looking for unstartable builds...');
        my @unstartable_builds = Genome::Model::Build->get(
            status => 'Unstartable',
            run_by => 'apipe-builder',
        );
        @builds = (@builds, @unstartable_builds);
    }

    unless (scalar(@builds)) {
        $self->error_message('No failed or unstartable builds found!');
        die $self->error_message();
    }

    my @models = Genome::Model->get('id in' => [map {$_->model_id} @builds]);
    $self->status_message(sprintf("Found %d builds in %d models",
            scalar(@builds), scalar(@models)));

    # cache the model_status calculations (they're calculated and slowly)...
    my %model_status;
    for my $model (@models) {
        $model_status{$model->id} = $model->status;
    }

    $self->status_message("Filtering down to latest build for each model...");
    my %builds;
    for my $build (@builds) {
        my $model = $build->model;

        #If the latest build of the model succeeds, ignore those old
        #failing ones that will be cleaned by admin "cleanup-succeeded".
        my $model_status = $model_status{$model->id};
        if ($model_status) {
            next if $model_status eq 'Succeeded';

            unless ($self->include_pending) {
                next if $model_status eq 'Requested';
                next if $model_status eq 'Scheduled';
                next if $model_status eq 'Running';
            }
        }

        # only keep the most recently scheduled build
        next if $builds{ $model->id } and $builds{ $model->id }->date_scheduled gt $build->date_scheduled;
        $builds{ $model->id } = $build;
    }
    $self->status_message('Found '.keys(%builds).' models');
    return %builds;
}


sub get_build_errors {
    my ($self, %builds) = @_;

    $self->status_message('Categorizing builds...');

    my %build_errors;

    for my $build ( values %builds ) {
        my $cmd = Genome::Model::Build::Command::DetermineError->execute(
            build => $build,
            display_results => 0,
        );

        my $key = "Unknown Error";
        my $header = join("\t", qw(Model Build Build-Class Date));
        my $line = join("\t", $build->model_id, $build->id, $build->class, $cmd->error_date);
        if ($cmd->error_type eq 'Unstartable') {
            $key = $cmd->get_unstartable_key;
        } elsif ($cmd->error_type eq 'Failed') {
            $key = $cmd->get_failed_key;

            # unstartable and unknown errors don't generally have a host.
            $header = join("\t", qw(Model Build Build-Class Host Date));
            $line = join("\t", $build->model_id, $build->id, $build->class, $cmd->error_host, $cmd->error_date);
        }

        unless ($build_errors{$key}) {
            $build_errors{$key} = sprintf("%s: %s\n%s:\n%s\n\n%s\n",
                $self->_color("Key:", "bold"), $key,
                $self->_color("Example error:", "bold"), $cmd->error_text,
                $header,
            );
        }
        $build_errors{$key} .= $line . "\n";
    }

    return \%build_errors;
}


sub remove_builds_in_tickets {
    my ($self, $builds) = @_;

    # Connect
    my $rt = _login_sso();

    # The call to $rt->search() below messed up the login credentials stored in the
    # $rt session, making the loop at the bottom that retrieves tickets fail.
    # Save a copy of the login credentials here so we can re-set them when it's
    # time to get the ticket details
    my $login_cookies = $rt->_cookie();

    # Retrieve tickets -
    $self->status_message('Looking for tickets...');
    my @ticket_ids;
    try {
        @ticket_ids = $rt->search(
            type => 'ticket',
            query => "Queue = 'apipe-support' AND ( Status = 'new' OR Status = 'open' )",

        );
    }
    catch Exception::Class::Base with {
        my $msg = shift;
        if ( $msg eq 'Internal Server Error' ) {
            die 'Incorrect username or password';
        }
        else {
            die $msg->message;
        }
    };
    $self->status_message($self->_color('Tickets (new or open): ', 'bold').scalar(@ticket_ids));

    # Go through tickets
    my %tickets;

    # re-set the login cookies that we saved away eariler
    $rt->_ua->cookie_jar($login_cookies);
    $self->status_message('Matching models and builds to tickets...');
    for my $ticket_id ( @ticket_ids ) {
        my $ticket = eval {
            RT::Client::REST::Ticket->new(
                rt => $rt,
                id => $ticket_id,
            )->retrieve;
        };
        unless ($ticket) {
            $self->error_message("Problem retrieving data for ticket $ticket_id: $@");
            next;
        }

        my $transactions = $ticket->transactions;
        my $transaction_iterator = $transactions->get_iterator;
        while ( my $transaction = &$transaction_iterator ) {
            my $content = $transaction->content;
            next unless $content;
            for my $model_id ( keys %$builds ) {
                my $build_id = $builds->{$model_id}->id;
                next if $content !~ /$model_id/ and $content !~ /$build_id/;
                push @{$tickets{$ticket_id.' '.$ticket->subject}}, $model_id;
            }
        }
    }

    for my $model_id_list (values %tickets) {
        for my $model_id (@$model_id_list) {
            delete $builds->{$model_id};
        }
    }

    my $models_in_tickets = map { @{$tickets{$_}} } keys %tickets;
    my $models_not_in_tickets = keys %$builds;
    $self->status_message($self->_color('Tickets mentioning models/builds: ', 'bold').scalar(values(%tickets)));
    $self->status_message($self->_color('Models: ', 'bold').($models_in_tickets + $models_not_in_tickets));
    $self->status_message($self->_color('Models in tickets: ', 'bold').$models_in_tickets);
    $self->status_message($self->_color('Models not in tickets: ', 'bold').$models_not_in_tickets);

    return %tickets;
}

sub _server {
    return 'https://rt.gsc.wustl.edu/';
}

sub _login_sso {
    my $self = shift;

    my $mech = WWW::Mechanize->new(
        after =>  1,
        timeout => 10,
        agent =>  'WWW-Mechanize',
    );
    $mech->get( _server() );

    my $uri = $mech->uri;
    my $host = $uri->host;
    if ($host ne 'sso.gsc.wustl.edu') {
        return;
    }

    $mech->submit_form (
        form_number =>  1,
        fields =>  {
            j_username => 'limsrt',
            j_password => 'Koh3gaed',
        },
    );
    $mech->submit();

    return RT::Client::REST->new(server => _server(), _cookie =>  $mech->{cookie_jar});
}

1;
