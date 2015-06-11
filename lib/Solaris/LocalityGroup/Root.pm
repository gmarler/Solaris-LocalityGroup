use strict;
use warnings;
use v5.18.1;
use feature qw(say);

package Solaris::LocalityGroup::Root;

# VERSION
#
# ABSTRACT: Solaris Locality Group Root abstraction - represents entire system

use Moose;
use Moose::Util::TypeConstraints;
use MooseX::ClassAttribute;
with 'MooseX::Log::Log4perl';
use Data::Dumper;
use Solaris::LocalityGroup::Leaf;

use namespace::autoclean;

use autodie                             qw(:all);
use Readonly                            qw();


Readonly::Scalar my $KSTAT    => '/bin/kstat';
Readonly::Scalar my $LGRPINFO => '/bin/lgrpinfo';

#
# Instance Attributes
#

has 'lgrps'     => ( isa => 'ArrayRef[Solaris::LocalityGroup::Leaf]|Undef',
                     is => 'ro',
                     builder => '_build_lgrp_leaves',
                   );


sub _build_lgrp_leaves {
  my $self = shift;

  my $stdout = qx{$LGRPINFO -cCG};
  # TODO: if command failed, generate an exception

  my $lgrp_specs_aref = __PACKAGE__->_parse_lgrpinfo($stdout);

  $stdout = qx{$KSTAT -p 'cpu_info:::/^\(?:brand|chip_id|core_id|cpu_type|pg_id|device_ID|state|state_begin\)\$/'};

  my $cpu_specs_aref  = __PACKAGE__->_parse_kstat_cpu_info($stdout);

  foreach my $lgrp_con_args (@$lgrp_specs_aref) {
    # TODO: Add CPU data specific to the leaf to the constructor args
    my $leaf = Solaris::LocalityGroup::Leaf->new( $lgrp_con_args );
  }
  #my @objs       = map { __PACKAGE__->new(%$_) } @$specs_aref;

  # Add to Class Object Cache attribute, for ease of lookups later
  #foreach my $obj (@objs) {
  #  __PACKAGE__->Cache()->{$obj->id} = $obj;
  #}
  
  # TODO: wantarray() handling
  #return \@objs;

  return undef;
}

#
# nydevsol10 # lgrpinfo -cCG
# lgroup 1 (leaf):
#         CPUs: 0-63
# lgroup 2 (leaf):
#         CPUs: 64-127
# lgroup 3 (leaf):
#         CPUs: 128-191
# lgroup 4 (leaf):
#         CPUs: 192-255
#
sub _parse_lgrpinfo {
  my $self       = shift;
  my $c          = shift;
  my @con_args;

  my $re =
    qr{^lgroup \s+ (?<lgroup>\d+) \s+ \(leaf\):\n
       ^ \s+ CPUs: \s+ (?<cpus>\d+-\d+)   \n
      }smx;

  while ($c =~ m/$re/gsmx) {
    say "LGroup: " . $+{lgroup};
    say "CPUs " . $+{cpus};
    my $href = { lgrp => $+{lgroup},
                 lgrpinfo_cpus => $+{cpus},
               };
    push @con_args, $href;
  }

  return \@con_args;
}

sub _parse_kstat_cpu_info {
  my $self       = shift;
  my $c          = shift;
  my @con_args;

  my (@lines) = split /\n/, $c;

  my (%cpu_constructor_args);
  # Parse each individual property line for this datalink
  foreach my $line (@lines) {
    my ($cpu_id,$key);

    my ($keypart, $value) = split /\s+/, $line;
    #say "KEYPART: $keypart";
    #say "VALUE:   $value";

    ($cpu_id = $keypart) =~ s{^cpu_info:(\d+):.+$}{$1};

    #say "CPU ID: $cpu_id";

    ($key = $keypart) =~ s{^cpu_info:$cpu_id:[^:]+:(\S+)$}{$1};

    #say "KEY $key";

    $cpu_constructor_args{$cpu_id}->{$key} = $value;
  }

  @con_args = map { my $cpu_id = $_;
                    { id => $cpu_id,
                      map {
                        $_ => $cpu_constructor_args{$cpu_id}->{$_};
                      } keys $cpu_constructor_args{$cpu_id},
                    };
                  } keys %cpu_constructor_args;

  say Dumper(\@con_args);

  return \@con_args;
}




1;

__END__

=head1 SYNOPSIS

  +-------------------------------------------------------------------+
  | Root Locality Group                                               |
  |                                                                   |
  |   +-----------------------------------------------------------+   |
  |   | Leaf Locality Group 1                                     |   |
  |   |                                                           |   |
  |   |   +-----------------------------------------------------+ |   |
  |   |   | Core 1                                              | |   |
  |   |   | +--------+ +--------+ +--------+ +--------+         | |   |
  |   |   | | vCPU 1 | | vCPU 2 | | vCPU 3 | | vCPU 4 | . . .   | |   |
  |   |   | |        | |        | |        | |        |         | |   |
  |   |   | +--------+ +--------+ +--------+ +--------+         | |   |
  |   |   +-----------------------------------------------------+ |   |
  |   |                                                           |   |
  |   |   +-----------------------------------------------------+ |   |
  |   |   | Core 2                                              | |   |
  |   |   | +--------+ +--------+ +--------+ +--------+         | |   |
  |   |   | | vCPU 1 | | vCPU 2 | | vCPU 3 | | vCPU 4 | . . .   | |   |
  |   |   | |        | |        | |        | |        |         | |   |
  |   |   | +--------+ +--------+ +--------+ +--------+         | |   |
  |   |   +-----------------------------------------------------+ |   |
  |   |                                                           |   |
  |   |   +-----------------------------------------------------+ |   |
  |   |   | Core 3                                              | |   |
  |   |   | +--------+ +--------+ +--------+ +--------+         | |   |
  |   |   | | vCPU 1 | | vCPU 2 | | vCPU 3 | | vCPU 4 | . . .   | |   |
  |   |   | |        | |        | |        | |        |         | |   |
  |   |   | +--------+ +--------+ +--------+ +--------+         | |   |
  |   |   +-----------------------------------------------------+ |   |
  |   |                                                           |   |
  |   |                      .  .  .  .                           |   |
  |   |                                                           |   |
  |   |                                                           |   |
  |   +-----------------------------------------------------------+   |
  |                                                                   |
  |   +-----------------------------------------------------------+   |
  |   | Leaf Locality Group 2                                     |   |
  |   |                                                           |   |
  |   |                      .  .  .  .                           |   |
  |   |                                                           |   |
  |   |                                                           |   |
  |   +-----------------------------------------------------------+   |
  |                                                                   |
  |      .  .  .  .  .                                                |
  |                                                                   |
  |                                                                   |
  |                                                                   |
  |                                                                   |
  +-------------------------------------------------------------------+


=cut
