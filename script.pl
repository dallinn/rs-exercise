#!/usr/bin/env perl

use strict;
use warnings;

use Email::Address;
use Data::Dumper;

__PACKAGE__->main;
exit;

sub main {
    my $self = shift;
    my $file;

    if (@ARGV != 1) {
        print STDERR "ERROR: Must be ran as the following:\n";
        print "\t./script.pl FILE_TO_BE_READ\n";
        print "\tExample: ./script.pl MDaemon-2017-11-16-all-2m.log/data\n";
        exit;
    } else {
        $file = $ARGV[0] || die 'ERROR: please enter a file as argument.';
    }

    my @senders;
    my %auths;

    if (-f $file) {
        open(my $fh, $file) or die "ERROR: $file could not be opened.";

        my $email;

        # Read line by line, as opposed to storing in memory (large file)
        while (my $row = <$fh>) {

            # These first two conditionals are for gathering users injecting authenticated mail
            # I'm not sure if you want both IMAP and SMTP. As of now this includes only SMTP
            if ($row =~ /Accepting SMTP connection from/) {
                my $ip;
                $ip = $1 if ($row =~/(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})/);

                if (%auths && $ip) {
                    foreach my $user (keys %auths) {
                        foreach my $auth_ip (@{$auths{$user}{ips}}) {
                            if ($ip eq $auth_ip) {
                                $auths{$user}{send_count}++;
                            }
                        }
                    }
                }

                next;
            }

            if ($row =~ /First time authenticated SMTP/) {
                my $ip;
                $ip = $1 if ($row =~/(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})/);

                my ($auth_email) = Email::Address->parse($row);

                if ($ip && $auth_email) {
                    my $addr = $auth_email->address;
                    $addr =~ s/\'s//g; # Remove 's

                    if (!$auths{$addr}) {
                        $auths{$addr}{ips} = ();
                        $auths{$addr}{send_count} = 0;
                    }

                    push @{$auths{$addr}{ips}}, $ip;
                }

                next;
            }

            # The second two conditionals are used for gathering the senders.
            # $email is used as a flag
            if ($email) {
                if ($row =~ /SMTP session terminated/) {
                    $email = undef;
                    next;
                }

                if ($row =~ /SMTP session successful/) {
                    push @senders, $email;
                    $email = undef;
                    next;
                }

                next;
            }

            if ($row =~ /MAIL From:/) {
                ($email) = Email::Address->parse($row);
            }
        }

        $self->handle_senders(@senders);
        $self->handle_auths(%auths);
    };
}


sub handle_senders {
    my ($self, @senders) = @_;
    my %count;

    # Add up totals from all mail added to senders
    $count{$_}++ foreach @senders;

    @senders = ();

    # Sort each sender's counted mail
    foreach my $sender (sort {$count{$b} <=> $count{$a}} keys %count) {
        push @senders, $sender;
    }

    my @top20senders = @senders[0 .. 19];

    print "TOP 20 SENDERS:\n";
    printf("\t%-30s => (%s)\n", $_, $count{$_}) foreach @top20senders;
}

sub handle_auths {
    my ($self, %auths) = @_;
    my @top20auths;

    # Sort each authenticated user's total send_count
    foreach my $user (sort {$auths{$b}{send_count} <=> $auths{$a}{send_count}} keys %auths) {
        push @top20auths, $user;
    }

    @top20auths = @top20auths[0 .. 19] if scalar @top20auths > 19;

    print "\nTOP 20 INJECTING AUTH:\n";
    foreach (@top20auths) {
        my $ips = "(". scalar @{$auths{$_}{ips}} .") " . join(', ', @{$auths{$_}{ips}});

        printf("\t%-30s => (%s)\t ips: %s\n", $_, $auths{$_}{send_count}, $ips);
    }
}
