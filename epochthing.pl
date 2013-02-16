#!/usr/bin/env perl

BEGIN {
    chdir '/home/matt/git_tree/epochthing';
}

package EpochThing;

use 5.14.0;
use warnings;

use autodie;

use Data::Dumper;
use Moose;
use Net::Twitter;
use Scalar::Util qw/blessed/;
use List::Util qw/first/;
use Time::HiRes qw//;
use POSIX qw/strftime/;
use namespace::clean -except => 'meta';

has _twatter => (
    isa           => 'Net::Twitter',
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

sub _build__twatter {
    my ($self) = @_;

    my $nt = Net::Twitter->new(
        traits   => [qw/OAuth API::REST/],
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
    my $epochs = do "epochs.hash";
    return $epochs;
}

sub run {
    my ($self) = @_;

    my @localtime = ( localtime, time );
    my $now = pop @localtime;
    my $minute_start = $now - $localtime[0];
    my $minute_end = $minute_start + 59;

    my @to_post = sort grep { $_ <= $minute_end and not $self->get_epoch($_) =~ /^posted/ } $self->all_epochs;

    exit unless @to_post;

    my $index = 0;

    until ( ( my $current_epoch = CORE::time() ) == $minute_end ) {

        # post 3 seconds before to allow for latency
        if ( $to_post[$index] <= $current_epoch + 2 ) {
            my $epoch = $to_post[$index];
            my $epoch_strftime = strftime '%F %T', localtime($epoch);
            my $now_strftime = strftime '%F %T', localtime;
            say "[$now_strftime] about to post $epoch ($epoch_strftime)...";
            $self->post_epoch($epoch, $self->get_epoch($epoch));
            $index++;
            last if $index == @to_post;
        }
        else {
            Time::HiRes::sleep(0.3);
        }
    }

    $self->save_epochs();
    exit 0;
}

sub post_epoch {
    my ($self, $epoch, $message) = @_;

    my $twatter = $self->_twatter;

    local $@;
    eval {
        # $twatter->update($message ? "$epoch - $message" : "\$ date +%s\n$epoch");
        $twatter->update($epoch);
    };
    if ($@) {
        if (!blessed($@) || !$@->isa('Net::Twitter::Error::Lite')) {
            die "Unknown Net::Twitter::Lite error: $@";
        }
    } else {
        # Updated status, all OK
        my $now_strftime = strftime '%F %T', localtime;
        say "[$now_strftime] Tweeted: $epoch";
        $self->set_epoch(
            $epoch => "posted $epoch " . strftime('[%F %T]', localtime($epoch)) . " at " .strftime('%F %T', localtime) . ( $message ? " (original message: $message)" : "" )
        );
    }
}

sub save_epochs {
    my ($self) = @_;
    local $Data::Dumper::Indent    = 1;
    local $Data::Dumper::Terse     = 1;
    local $Data::Dumper::Quotekeys = 0;
    local $Data::Dumper::Sortkeys  = 1;
    IO::File->new("epochs.hash" => 'w')->print(Dumper($self->epochs));
}

1;

package main;

EpochThing->new->run();
