#!/usr/bin/env perl

BEGIN {
    chdir '/home/matt/git_tree/epochthing';
}

package EpochThing;

use 5.14.0;
use Moose;
use warnings;

use autodie;

use Data::Dumper;
use Net::Twitter::Lite::WithAPIv1_1;
use Scalar::Util qw/blessed/;
use List::Util qw/first/;
use Time::HiRes qw//;
use POSIX qw/strftime/;
use namespace::clean -except => 'meta';
use Math::Prime::FastSieve;
use JSON::XS qw//;

has _twatter => (
    isa           => 'Net::Twitter::Lite::WithAPIv1_1',
    is            => 'ro',
    documentation => "Net::Twatter::Lite instance",
    lazy_build    => 1,
);

has epochs => (
    is => 'ro',
    isa => 'HashRef',
    traits => ['Hash'],
    lazy_build => 1,
    handles => {
        get_epoch => 'get',
        all_epochs => 'keys',
        delete_epoch => 'delete',
        set_epoch => 'set',
    },
);

has config => (
    is => 'ro',
    isa => 'HashRef',
    lazy_build => 1,
);

has json => (
    is => 'ro',
    isa => 'JSON::XS',
    default => sub { JSON::XS->new->pretty->canonical(1) },
);

sub _build__twatter {
    my ($self) = @_;

    my $nt = Net::Twitter::Lite::WithAPIv1_1->new(
        traits   => [qw/OAuth/],
        consumer_key        => $self->config->{consumer_key},
        consumer_secret     => $self->config->{consumer_secret},
        access_token        => $self->config->{access_token},
        access_token_secret => $self->config->{access_token_secret},
    );

    return $nt;
}

sub _build_config {
    my ($self) = @_;
    my @lines = IO::File->new("epochthing.conf" => 'r')->getlines;
    my %config;
    foreach my $line ( @lines ) {
        chomp $line;
        my ($key, $value) = ( $line =~ m/\A (\w+) \s+ (.*) \z/xms );
        $config{$key} = $value;
    }

    return \%config;
}

sub _build_epochs {
    my ($self) = @_;
    local $/;
    my $epoch_cache_fh = IO::File->new('epochs.json' => 'r');
    return $self->json->decode(<$epoch_cache_fh>);
}

sub new_sieve {
    my ($self, $end_epoch) = @_;
    my $now_strftime = _strftime(time);
    say "[$now_strftime] creating new prime sieve until: $end_epoch";
    my $sieve = Math::Prime::FastSieve::Sieve->new($end_epoch);
}

sub save_epochs {
    my ($self) = @_;
    IO::File->new('epochs.json' => 'w')->print($self->json->encode($self->epochs));
}

sub run {
    my ($self) = @_;

    my @localtime = ( localtime, time );
    my $now = pop @localtime;
    my $minute_start = $now - $localtime[0];
    my $minute_end = $minute_start + 59;

    my @to_post = sort grep { $_ <= $minute_end and not $self->get_epoch($_) =~ /^posted/ } $self->all_epochs;

    my $index = 0;

    unless ( not @to_post ) {

        until ( ( my $current_epoch = CORE::time() ) == $minute_end ) {

            # post 3 seconds before to allow for latency
            if ( $to_post[$index] <= $current_epoch + 3 ) {
                my $epoch = $to_post[$index];
                my $epoch_strftime = _strftime($epoch);
                my $now_strftime = _strftime(time);
                my $message = $self->get_epoch($epoch);
                say "[$now_strftime] about to post $epoch ($epoch_strftime) ($message)...";
                $self->post_epoch($epoch, $message);
                $index++;
                last if $index == @to_post;
            }
            else {
                Time::HiRes::sleep(0.3);
            }
        }

    }

    # determine any interesting epochs from teh futar!!1
    my $the_future = $self->get_interesting_epochs($minute_end + 60, $minute_end + 179);
    keys %$the_future and $self->set_epoch(%$the_future);

    $self->save_epochs() if ( keys %$the_future or @to_post );
    exit 0;
}

sub _strftime ($) {
    POSIX::strftime('%F %T', localtime($_[0]));
}

sub post_epoch {
    my ($self, $epoch, $epoch_message) = @_;

    my $twatter = $self->_twatter;

    local $@;
    eval {
        # $twatter->update($epoch_message ? "$epoch - $epoch_message " : $epoch);
        $twatter->update($epoch);
    };
    if ($@) {
        if (!blessed($@) || !$@->isa('Net::Twitter::Lite::Error')) {
            die "Unknown Net::Twitter::Lite error: $@";
        }
    } else {
        # Updated status, all OK
        my $now_strftime = _strftime(time);
        say "[$now_strftime] Tweeted: $epoch";
        $self->set_epoch(
            $epoch => "posted epoch $epoch " . _strftime($epoch) . " at " . _strftime(time) . ( $epoch_message ? " (original message: $epoch_message)" : "" )
        );
    }
}

sub get_interesting_epochs {
    my ($self, $start_epoch, $end_epoch) = @_;

    # my $sieve = $self->new_sieve($end_epoch + 1);

    my $start_time = _strftime($start_epoch);
    my $end_time   = _strftime($end_epoch);
    # warn "get_interesting_epochs() start_time: $start_time\n";
    # warn "get_interesting_epochs() end_time:   $end_time\n";

    my @return;

    my @ten_second_buckets = ( [] );

    foreach my $epoch ( $start_epoch .. $end_epoch ) {
        my $bucket = $ten_second_buckets[-1];
        @$bucket == 10 and push @ten_second_buckets, ( $bucket = [] );
        push @$bucket, $epoch;
    }

    # warn Dumper(\@ten_second_buckets);

    my %interesting_epochs;

    my $primes = 0;

    BUCKET:
    foreach my $bucket (@ten_second_buckets) {

        my %found_epochs;

        EPOCH:
        foreach my $epoch (@$bucket) {

            ( $found_epochs{$epoch} = '1234567', next EPOCH )
            if $epoch =~ m/1234567/;

            # lots of the same digit
            ( $found_epochs{$epoch} = 'repetition', next EPOCH )
            if $epoch =~ m/([0-9])\1\1\1\1\1\1\1+/;

            ( $found_epochs{$epoch} = 'triplets', next EPOCH )
            if $epoch =~ m/([0-9]{3})\1\1/;

            ( $found_epochs{$epoch} = 'doublets', next EPOCH )
            if $epoch =~ m/([0-9]{2})\1\1\1\1/;

            # $sieve->isprime($epoch) and ++$primes == 1
            # and ( $found_epochs{$epoch} = 'prime' and next EPOCH );

            ( $found_epochs{$epoch} = 'symmetrical', next EPOCH )
            if substr($epoch, 0, 5) == reverse(substr($epoch, 5, 5));
        }

        # sometimes there's a 10-second batch of triplets, the most interesting
        # is the one the ends in 1, as it also starts with 1. so delete the rest.

        if ( grep { $_ eq 'triplets' } values %found_epochs == @$bucket ) {
            my @to_delete = grep { substr($_, 9, 1) != 1 } keys %found_epochs;
            delete @found_epochs{@to_delete};
        }

        @interesting_epochs{keys %found_epochs} = values %found_epochs;
    }

    keys(%interesting_epochs) and warn "interesting_epochs: ".Dumper(\%interesting_epochs);

    return \%interesting_epochs;
}

1;

package main;

EpochThing->new->run();
