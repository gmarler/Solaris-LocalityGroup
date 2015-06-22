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
Readonly::Scalar my $DLADM    => '/sbin/dladm';
Readonly::Scalar my $PRTCONF  => '/sbin/prtconf';
Readonly::Scalar my $PSRSET   => '/sbin/psrset';
Readonly::Scalar my $PBIND    => '/sbin/pbind';

#
# Instance Attributes
#

has 'leaves'    => ( isa => 'ArrayRef[Solaris::LocalityGroup::Leaf]|Undef',
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
# NOTE: This does not currently work, as of Moose 2.1404, as it sometimes
#       returns an undefined value while trying to perform regular expression
#       compilation - use of /o doesn't seem to help either:
#
# Warning message emitted: Use of uninitialized value in regexp compilation
#
has 'important_interrupts_re'
                => ( isa => 'RegexpRef',
                     is  => 'ro',
                     default => sub {
                       qr/^(nxge|igb|ixgbe)/;
                     },
                   );

has 'nics_in_use'
                => ( isa     => 'ArrayRef',
                     is      => 'ro',
                     builder => '_build_nics_in_use',
                     lazy    => 1,
                   );

# Platform name: T4-4, T5-8, M9000, etc
has 'platform'  => ( isa     => 'Str|Undef',
                     is      => 'ro',
                     builder => '_build_platform',
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
  foreach my $leaf (@{$self->leaves}) {
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
  foreach my $leaf (@{$self->leaves}) {
    $cpu_count += $leaf->cpu_count;
  }
  return $cpu_count;
}

=method print

Print out information on this leaf Locality Gruop

=cut

sub print {
  my $self = shift;

  my @leaves = @{$self->leaves};

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

  my $leaf_aref  = $self->leaves;

  foreach my $leaf (@{$leaf_aref}) {
    $leaf->print_cpu_avail_terse;
  }
}


=head1 PRIVATE Methods

=cut

sub _build_lgrp_leaves {
  my $self = shift;
  my @leaves;

  # Obtain LG leaf topology
  my $stdout = qx{$LGRPINFO -cCG};
  # TODO: if command failed, generate an exception
  # say "LGRPINFO:\n$stdout";
  my $lgrp_specs_aref = $self->_parse_lgrpinfo($stdout);

  # Obtain CPU specific info
  $stdout = qx{$KSTAT -p 'cpu_info:::/^\(?:brand|chip_id|core_id|cpu_type|pg_id|device_ID|state|state_begin\)\$/'};
  my $cpu_specs_aref  = $self->_parse_kstat_cpu_info($stdout);

  # Obtain interrupt information
  # Using kstats to obtain this data now, instead of mdb:
  #       kstat -p 'pci_intrs::config:/(name|pil|cpu|type)/'
  $stdout = $self->_kstat_interrupts();
  my $interrupts_aref = $self->_parse_kstat_interrupts($stdout);

  #
  # TODO: Obtain pset information
  $stdout = $self->_psrset();
  my $psrset_aref = $self->_parse_psrset($stdout);

  # TODO: Obtain single pbind information
  # TODO: Obtain MCB information

  foreach my $lgrp_ctor_args (@$lgrp_specs_aref) {
    # TODO: Add CPU data specific to the leaf to the constructor args
    my $leaf = Solaris::LocalityGroup::Leaf->new(
                 id             => $lgrp_ctor_args->{lgrp},
                 cpu_range      => [ $lgrp_ctor_args->{cpufirst},
                                     $lgrp_ctor_args->{cpulast}, ],
                 core_data      => $cpu_specs_aref,
                 interrupt_data => $interrupts_aref,
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

  my @nics_in_use = @{$self->nics_in_use};
  # say "NICS in use: " . Dumper(\@nics_in_use);

  my @ctor_args;

  my $important_interrupts_re = qr/^(nxge|igb|ixgbe)/;

  my (@lines) = split /\n/, $c;

  my (%interrupt_ctor_args,
      %coalesce);  # used to coalesce multi-line records

  # Parse each individual property line for this interrupt
  #
  # Each line has a unique "key", which itself is meaningless.  It just
  # signified when we've moved from one multiline interrupt record to the next.
  #
  # So we keep track of the "lastkey" to know when we've moved to the next
  # multiline interrupt record.
  #
  # keep these outside the loop,
  # so their state is kept for the entire loop run
  #
  my ($lastkey,$currval_aref);
  foreach my $line (@lines) {
    my ($key,$statname);

    my ($keypart, $value) = split /\s+/, $line;
    ($key      = $keypart) =~ s{^(pci_intrs:[^:]+:config):.+$}{$1};
    ($statname = $keypart) =~ s{^pci_intrs:[^:]+:config:(\S+)$}{$1};
    if ($statname eq "cpu") {
      $coalesce{$key}->{cpu}  = $value;
    } elsif ($statname eq "name") {
      $coalesce{$key}->{name} = $value;
    } else {
      # ignore remaining data, for the time being
      next;
    }
  }

  # The keys, or entries, are meaningless to us; this is where we reorganize
  # the collected data into something meaningful
  foreach my $entry (keys %coalesce) {
    my $key   = $coalesce{$entry}->{cpu};
    my $value = $coalesce{$entry}->{name};
    # Ignore / skip "non-important" interrupts
    #say "ENTRY:     $value";
    #say "IMPORTANT: $important_interrupts_re";
    if ($value !~ $important_interrupts_re) {
      #say "Skipping non-important: $value";
      next;
    }
    # TODO: ignore / skip interrupts for NICs that are not in use
    if (  grep(/^$value$/, @nics_in_use) ) {
      #say "including NIC: $value";
    } else {
      #say "Skipping non-utilized NIC: $value";
      next;
    }

    if (not exists($interrupt_ctor_args{$key})) {
      $interrupt_ctor_args{$key} = [];
    }
    push @{$interrupt_ctor_args{$key}}, $value;
  }

  # Sort numerically by CPU
  @ctor_args = map {
                    { cpu            => $_,
                      interrupts_for => $interrupt_ctor_args{$_},
                    };
                  } sort { $a <=> $b } keys %interrupt_ctor_args;

  # say Dumper(\@ctor_args);

  return \@ctor_args;
}

sub _psrset {
  my $self = shift;

  my $stdout = qx{$PSRSET};

  return $stdout;
}

sub _parse_psrset {
  my $self       = shift;
  my $c          = shift;

  say "PSRSET OUTPUT:\n$c";

  # NOTE: cpulist will be space separated
  my $re = qr/^user \s processor \s set \s 
               (?<psrset_id>\d+) :
               \s processors \s
               (?<cpulist>[^\n]+)\n/smx;

  while ($c =~ m/$re/gsmx) {
    say "PROCESSOR SET:" .  $+{psrset_id};
    my @cpus = split(/\s+/,$+{cpulist});
    say "  CPUS: " . join ", ", @cpus;
  }
}

sub _pbind {

}

sub _parse_pbind {
  my $self       = shift;
  my $c          = shift;

}

=method _build_nics_in_use

Private method that gives a list of the NIC names that are actively in use.

Used when mapping which interrupts are assigned to which CPUs, so we only pay
attention to NICs that are actually in use.

=cut

sub _build_nics_in_use {
  my $self = shift;
  my @nics;

  my $output = qx{$DLADM show-ether -p -o link,state};
  # TODO: check state of command
  while ($output =~ m{^([^:]+):([^\n]+)\n}gsmx) {
    my ($link,$state) = ($1, $2);
    if ($state eq "up") {
      push @nics, $link;
    }
  }

  return \@nics;
}

=method _build_platform

Based on the output of prtconf -b, deduce the platform name

=cut

sub _build_platform {
  my $self = shift;

  my $output = qx{$PRTCONF -b};
  # TODO: check state of command
  if ( not length($output) ) {
    say "No output from prtconf -b";
    return; # undef
  }
  my $platform;
  
  if ($output =~ m/banner-name:\s+SPARC\s+Enterprise\s+(M\d000)/smx) {
    $platform = $1;
  } elsif ($output =~ m/banner-name:\s+SPARC\s+(T[457]-[1248])/smx) {
    $platform = $1;
  } else {
    say "UNABLE TO DETERMINE PLATFORM TYPE from: $output";
    return; # undef
  }
  return $platform;
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
