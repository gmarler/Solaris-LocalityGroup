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
Readonly::Scalar my $MDB      => '/bin/mdb';

#
# Instance Attributes
#

# TODO: Rename as 'leaves' to be more intuitive
has 'lgrps'     => ( isa => 'ArrayRef[Solaris::LocalityGroup::Leaf]|Undef',
                     is => 'ro',
                     builder => '_build_lgrp_leaves',
                   );

#
# Drivers whose interrupts are "important" to us, in the sense that if we see on
# of their interrupts bound to a CPU, we make sure we mark that CPU as being
# "used" and not bindable otherwise.
#
# Any other drivers generally don't consume much of a CPU, so their not likely
# to be worth excluding the CPU from our binding.
#
has 'important_interrupts'
                => ( isa => 'RegexpRef',
                     is  => 'ro',
                     default => sub {
                       qr/(nxge|igb|ixgbe)/;
                     },
                   );

# Platform name: T4-4, T5-8, M9000, etc
has 'platform'  => ( isa => 'Str|Undef',
                     is  => 'ro',
                   );

=head2 PUBLIC Methods

=method socket_count

This should also be aliased to leaf_count

=cut

sub socket_count {
  my $self = shift;

}

=method core_count

The count of cores in the entire system

=cut

sub core_count {
  my $self = shift;

  my $core_count = 0;
  foreach my $leaf (@{$self->lgrps}) {
    $core_count += $leaf->core_count;
  }

  return $core_count;
}


=method cpu_count

The count of CPUs / vCPUs in the entire system

=cut

sub cpu_count {
  my $self = shift;

  my $cpu_count = 0;
  foreach my $leaf (@{$self->lgrps}) {
    $cpu_count += $leaf->cpu_count;
  }
  return $cpu_count;
}

=method print

Print out information on this leaf Locality Gruop

=cut

sub print {
  my $self = shift;

  my @leaves = @{$self->lgrps};

  foreach my $leaf (@leaves) {
    $leaf->print;
  }
}


=method print_cpu_avail_terse

Print all CPUS available for binding purposes, for each Leaf Locality Group in
this Root Locality Group

=cut

sub print_cpu_avail_terse {
  my $self = shift;

  my $leaf_aref  = $self->lgrps;

  foreach my $leaf (@{$leaf_aref}) {
    $leaf->print_cpu_avail_terse;
  }
}


=head1 PRIVATE Methods

=cut

sub _build_lgrp_leaves {
  my $self = shift;
  my @leaves;

  my $stdout = qx{$LGRPINFO -cCG};
  # TODO: if command failed, generate an exception

  my $lgrp_specs_aref = $self->_parse_lgrpinfo($stdout);

  $stdout = qx{$KSTAT -p 'cpu_info:::/^\(?:brand|chip_id|core_id|cpu_type|pg_id|device_ID|state|state_begin\)\$/'};

  my $cpu_specs_aref  = $self->_parse_kstat_cpu_info($stdout);

  # Obtain interrupt information
  # TODO: stop getting this with mdb, and use kstats to obtain this instead:
  #       kstat -p 'pci_intrs::config:/(name|pil|cpu|type)/'
  $stdout = $self->_kstat_interrupts();
  my $interrupts_aref = $self->_parse_kstat_interrupts($stdout);

  #
  # TODO: Obtain pset information
  # TODO: Obtain single pbind information
  # TODO: Obtain MCB information

  foreach my $lgrp_ctor_args (@$lgrp_specs_aref) {
    # TODO: Add CPU data specific to the leaf to the constructor args
    my $leaf = Solaris::LocalityGroup::Leaf->new(
                 id        => $lgrp_ctor_args->{lgrp},
                 cpu_range => [ $lgrp_ctor_args->{cpufirst},
                                $lgrp_ctor_args->{cpulast}, ],
                 core_data => $cpu_specs_aref,
               );
    push @leaves, $leaf;
  }
  #my @objs       = map { __PACKAGE__->new(%$_) } @$specs_aref;

  # Add to Class Object Cache attribute, for ease of lookups later
  #foreach my $obj (@objs) {
  #  __PACKAGE__->Cache()->{$obj->id} = $obj;
  #}
  
  # TODO: wantarray() handling
  #return \@objs;

  return \@leaves;
}


sub _parse_lgrpinfo {
  my $self       = shift;
  my $c          = shift;
  my @ctor_args;

  my $re =
    qr{^lgroup \s+ (?<lgroup>\d+) \s+ \(leaf\):\n
       ^ \s+ CPUs: \s+ (?<cpufirst>\d+)-(?<cpulast>\d+)   \n
      }smx;

  while ($c =~ m/$re/gsmx) {
    #say "LGroup: " . $+{lgroup};
    #say "First CPU: " . $+{cpufirst};
    #say "Last  CPU: " . $+{cpulast};
    my $href = { lgrp     => $+{lgroup},
                 cpufirst => $+{cpufirst},
                 cpulast  => $+{cpulast},
               };
    push @ctor_args, $href;
  }

  return \@ctor_args;
}


sub _parse_kstat_cpu_info {
  my $self       = shift;
  my $c          = shift;
  my @ctor_args;

  my (@lines) = split /\n/, $c;

  my (%cpu_ctor_args);
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

    $cpu_ctor_args{$cpu_id}->{$key} = $value;
  }

  @ctor_args = map { my $cpu_id = $_;
                    { id => $cpu_id,
                      map {
                        $_ => $cpu_ctor_args{$cpu_id}->{$_};
                      } keys $cpu_ctor_args{$cpu_id},
                    };
                  } keys %cpu_ctor_args;

  #say Dumper(\@ctor_args);

  return \@ctor_args;
}

sub _kstat_interrupts {
  my $self = shift;

  my $stdout =
    qx{$KSTAT -p 'pci_intrs::config:/^\(?:name|cpu|type|pil\)\$/'};

  return $stdout;
}

sub _parse_kstat_interrupts {
  my $self       = shift;
  my $c          = shift;
  my @ctor_args;

  my $important = $self->important_interrupts;

  my (@lines) = split /\n/, $c;

  my (%interrupt_ctor_args);
  # Parse each individual property line for this interrupt
  foreach my $line (@lines) {
    my ($cpu_id,$key);

    my ($keypart, $value) = split /\s+/, $line;
    say "KEYPART: $keypart";
    say "VALUE:   $value";

    #($cpu_id = $keypart) =~ s{^cpu_info:(\d+):.+$}{$1};

    #say "CPU ID: $cpu_id";

    #($key = $keypart) =~ s{^cpu_info:$cpu_id:[^:]+:(\S+)$}{$1};

    #say "KEY $key";

    #$cpu_ctor_args{$cpu_id}->{$key} = $value;
  }

  # @ctor_args = map { my $cpu_id = $_;
  #                   { id => $cpu_id,
  #                     map {
  #                       $_ => $cpu_ctor_args{$cpu_id}->{$_};
  #                     } keys $cpu_ctor_args{$cpu_id},
  #                   };
  #                 } keys %cpu_ctor_args;

  #say Dumper(\@ctor_args);

  # return \@ctor_args;
}

# TODO: Eliminate these
sub _mdb_interrupts_output {
  my $self = shift;

  my $output = qx{echo "::interrupts" | $MDB -k};

  return $output;
}

sub _parse_mdb_interrupts {
  my $self = shift;


  # Parse the header first, as it will indicate any changes in the output format
  # for us, since the format of this output is not set in stone

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
