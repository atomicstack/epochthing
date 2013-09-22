#!/usr/bin/env perl

use 5.16.0;
use strict;
use warnings;

use Data::Dumper;
use IO::File;
use JSON::XS qw/encode_json decode_json/;

my %epochs = do {
    local $/;
    my $fh = IO::File->new("epochs.json" => 'r');
    my $epochs = decode_json(<$fh>);
    %$epochs;
};

my $progress_output_fh = IO::File->new("progress" => 'w');
$progress_output_fh->autoflush(1);

my $epoch = time;

until ( $epoch > ( $^T + ( 86400 * 100 ) ) ) {

    my $start_of_hour = $epoch - ( $epoch % 3600 );
    my $end_of_hour   = $start_of_hour + 3599;

    # lots of the same digit
    dump_epoch($epoch, 'repetition') if $epoch =~ m/([0-9])\1\1\1\1\1\1+/;

    # repeating doublets.
    dump_epoch($epoch, 'doublets') if $epoch =~ m/([0-9]{2})\1\1\1\1/;

    # repeating triplets. sometime occur in a cluster, how do we detect this
    # and only post the only most interesting (the one that ends in 1)?
    dump_epoch($epoch, 'triplets') if $epoch =~ m/([0-9]{3})\1\1/; # and shift_epoch_by_x($epoch, 4) == $epoch;

    # vertical symmetry, kinda boring.
    # dump_epoch($epoch, 'vertical symmetry') if substr($epoch, 0, 5) == reverse(substr($epoch, 5, 5));

    $epoch++;
    $progress_output_fh->print("\n");
}

sub dump_epoch {
    my ($epoch, $property) = @_;
    say "$epoch has $property (".localtime($epoch).")";
}

sub shift_epoch_by_x {
    my ($epoch, $x) = @_;
    die "bad shift param [$x]; must be between 1-9" if ( $x < 1 or $x > 9 );
    my @chunks = split //, $epoch;

    foreach my $i ( 1 .. $x ) {
        my $end = pop @chunks;
        unshift @chunks, $end;
    }


    my $shifted_epoch = join '' => @chunks;
    warn "$epoch => $shifted_epoch\n";
    return $shifted_epoch;
}

sub bucketise_hour {
    my ($epoch) = @_;
}
