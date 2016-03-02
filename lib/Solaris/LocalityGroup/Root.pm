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
use IPC::System::Simple qw(capture);

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
# So that we don't mark too many CPUs unusable, expecially for NICs that are not
# even in use, we want to take the data we retrieved into attribute nics_in_use
# and ignore any other interrupts
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
                       qr/^(nxge|igb|ixgbe|i40e)/;
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

  # If there is only one Locality Group in a system, it will be the root
  # Locality Group, not a Leaf; we need to handle this condition
  #
  # lgrpinfo -I prints out the list of Locality Groups.  If it only lists one of
  # them, then we can dispense with the -C option when getting "leaves", as
  # there won't be any children
  #
  # Obtain LG leaf topology
  my $stdout = IPC::System::Simple::capture("$LGRPINFO -cCG");
  # TODO: if command failed, generate an exception
  # say "LGRPINFO:\n$stdout";
  my $lgrp_specs_aref = $self->_parse_lgrpinfo($stdout);

  # Obtain CPU specific info
  $stdout = IPC::System::Simple::capture(
    "$KSTAT -p 'cpu_info:::/^\(?:brand|chip_id|core_id|cpu_type|pg_id|device_ID|state|state_begin\)\$/'");
  my $cpu_specs_aref  = $self->_parse_kstat_cpu_info($stdout);

  # Obtain interrupt information
  # Using kstats to obtain this data now, instead of mdb:
  #       kstat -p '(pci|priq)_intrs::config:/(name|pil|cpu|type)/'
  $stdout = $self->_kstat_interrupts();
  my $interrupts_aref = $self->_parse_kstat_interrupts($stdout);

  #
  # Obtain pset information
  $stdout = $self->_psrset();
  my $psrset_aref;
  if ($stdout) {
    $psrset_aref = $self->_parse_psrset($stdout);
  }
  #say "PSETS:\n" . Dumper( $psrset_aref );

  # Obtain single pbind and MCB bound information
  my $pbind_href;
  $stdout = $self->_pbind_Qc();
  if (defined($stdout) && (length($stdout) == 1) && ($stdout == 2)) {
    # Must be an older version of Solaris
    $stdout = $self->_pbind_Q();
    if (defined($stdout)) {
      $pbind_href = $self->_parse_pbind_Q($stdout);
    }
  } elsif (defined($stdout)) {
    $pbind_href = $self->_parse_pbind_Qc($stdout);
  }

  #say "BINDINGS:\n" . Dumper( $pbind_href );

  #
  # TODO: ONLY PASS PSET/PBIND info on IF THEY ACTUALLY EXIST!
  #

  foreach my $lgrp_ctor_args (@$lgrp_specs_aref) {
    # TODO: Add CPU data specific to the leaf to the constructor args
    my $leaf = Solaris::LocalityGroup::Leaf->new(
                 id             => $lgrp_ctor_args->{lgrp},
                 cpu_range      => [ $lgrp_ctor_args->{cpufirst},
                                     $lgrp_ctor_args->{cpulast}, ],
                 core_data      => $cpu_specs_aref,
                 interrupt_data => $interrupts_aref,
                 pset_data      => $psrset_aref,
                 binding_data   => $pbind_href,
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
                      } keys %{$cpu_ctor_args{$cpu_id}},
                    };
                  } keys %cpu_ctor_args;

  #say Dumper(\@ctor_args);

  return \@ctor_args;
}

sub _kstat_interrupts {
  my $self = shift;

  my $stdout =
    IPC::System::Simple::capture("$KSTAT -p '\(?:pci|priq\)_intrs::config:/^\(?:name|cpu|type|pil\)\$/'");

  return $stdout;
}

sub _parse_kstat_interrupts {
  my $self       = shift;
  my $c          = shift;

  my @nics_in_use = @{$self->nics_in_use};
  # say "NICS in use: " . Dumper(\@nics_in_use);

  my @ctor_args;

  my (@lines) = split /\n/, $c;

  my (%interrupt_ctor_args,
      %coalesce);  # used to coalesce multi-line records

  # Parse each individual property line for this interrupt
  #
  # Each line has a unique "key", which itself is meaningless.  It just
  # signifies when we've moved from one multiline interrupt record to the next.
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
    ($key      = $keypart) =~ s{^((?:pci|priq)_intrs:[^:]+:config):.+$}{$1};
    ($statname = $keypart) =~ s{^(?:pci|priq)_intrs:[^:]+:config:(\S+)$}{$1};
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

  # Look to see if the interrupts of interest look right
  #say Dumper( \%interrupt_ctor_args );

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

  my $stdout = IPC::System::Simple::capture("$PSRSET");
  # TODO: check state of command
  if ( not length($stdout) ) {
    # say "No output from psrset";
    return; # undef
  }

  return $stdout;
}

#
# We only want the list of CPUs that are members of exclusive psets, as we will
# want to mark such CPUs as "oversubscribed" if they are in use in any other
# context, such as interrupt handling for latency sensitive NICs and such.
#
sub _parse_psrset {
  my $self       = shift;
  my $c          = shift;

  my @pset_cpus;
  # NOTE: cpulist will be space separated
  my $re = qr/^user \s processor \s set \s
               (?<psrset_id>\d+) :
               \s processors \s
               (?<cpulist>[^\n]+)\n/smx;

  while ($c =~ m/$re/gsmx) {
    # say "PROCESSOR SET:" .  $+{psrset_id};
    push @pset_cpus, split(/\s+/,$+{cpulist});
    # say "  CPUS: " . join ", ", @cpus;
  }
  @pset_cpus = sort { $a <=> $b } @pset_cpus;
  return \@pset_cpus;
}

=method _pbind_Q

This method will only be called if _pbind_Qc cannot be called (it's not Solaris
11.2 yet).  This will use the old veriant of the pbind command

=cut

sub _pbind_Q {
  my $self = shift;

  my $stdout = IPC::System::Simple::capture("$PBIND -Q");
  # TODO: check state of command
  if ( not length($stdout) ) {
    # say "No output from pbind -Q";
    return; # undef
  }

  return $stdout;
}


=method _parse_pbind_Q

This method parses the output of _pbind_Q, if it's called.

=cut

sub _parse_pbind_Q {
  my $self       = shift;
  my $c          = shift;

  my %bound_cpus;

  # say "_parse_pbind_Q() received this input:\n$c";

  # The point here is to obtain
  # 1. CPUs that have threads bound to them
  # 2. Secondarily, the count of threads bound to each CPU, as it will be useful
  #    in reports that show insane binding counts.
  #
  # Only regular pbinding (single CPU) can occur here, like so:
  #
  # For a single threaded process:
  # process id 7375: 255
  #
  # For multi threaded process:
  # lwp id 12628/7360: 254
  #
  #
  my $re = qr{^(?:process \s+ id \s+ (?<pid>\d+) : \s+ (?<cpu>\d+) |
                  lwp \s+ id \s+ (?<pid>\d+) / (?<thread>\d+) : \s+ (?<cpu>\d+)
               ) \n
             }smx;

  # First, build the list of CPUs that have threads bound to them
  while ($c =~ m/$re/gsmx) {
    # If thread is not defined, it's probably LWP 1 in a single-threaded process
    $bound_cpus{$+{cpu}}++;
  }

  #say "BOUND CPUS: " .
  #  Dumper( [ sort { $a <=> $b } keys %bound_cpus ] );

  return \%bound_cpus;
}


=method _pbind_Qc

Normal method (starting with Solaris 11.2) to determine the single / MCB binding
of CPUs.

=cut

sub _pbind_Qc {
  my $self = shift;

  my $stdout = IPC::System::Simple::capture("$PBIND -Qc");
  # TODO: check state of command
  # If this is prior to Solaris 11.2, the arguments to pbind are quite
  # different, as is the output.  We need to handle that case separately, so
  # another variant of this method can be called instead.
  my $status = $? >> 8;

  # say "pbind -Qc returned with status code: $status";

  if ($status == 2) {
    return 2;   # Return 2 to indicate that we need to call _pbind_Q() instead,
                # as this is an older version of Solaris than 11.2
  }

  if ( not length($stdout) ) {
    # say "No output from pbind -Qc";
    return; # undef
  }

  return $stdout;
}

sub _parse_pbind_Qc {
  my $self       = shift;
  my $c          = shift;

  # say "_parse_pbind_Qc() received this input:\n$c";

  my %bound_cpus;

  # The point here is to obtain
  # 1. CPUs that have threads bound to them
  # 2. Secondarily, the count of threads bound to each CPU, as it will be useful
  #    in reports that show insane binding counts.
  #
  # Regular pbinding (single CPU) lists a single CPU per thread, like so:
  # pbind(1M): LWP 45461/1 strongly bound to processor(s) 220.
  #
  # MCB pbinding (thread to multiple CPUs, non-exclusive), shows many CPUs per
  # thread, like so:
  # pbind(1M): LWP 59745/1 strongly bound to processor(s) 250 251 252 253 254 255.
  #
  my $re = qr{^pbind\(1M\): \s+
               LWP \s+ (?<pid>\d+) / (?<thread>\d+) \s+
               (?:strongly|weakly) \s+ bound \s+ to \s+ processor\(s\) \s+
               (?<cpulist>[^\.]+)\.\n}smx;


  # First, build the list of CPUs that have threads bound to them
  while ($c =~ m/$re/gsmx) {
    my @cpus = split(/\s+/,$+{cpulist});
    foreach my $cpu (@cpus) {
      $bound_cpus{$cpu}++;
    }
  }

  #say "BOUND CPUS: " .
  #  Dumper( [ sort { $a <=> $b } keys %bound_cpus ] );

  return \%bound_cpus;
}

=method _build_nics_in_use

Private method that gives a list of the NIC names that are actively in use.

Used when mapping which interrupts are assigned to which CPUs, so we only pay
attention to NICs that are actually in use.

=cut

sub _build_nics_in_use {
  my $self = shift;
  my @nics;

  my $output = IPC::System::Simple::capture("$DLADM show-ether -p -o link,state");
  # TODO check state of command

  # We only want to NIC interrupts that are "important"
  # my $important_interrupts_re = $self->important_interrupts_re;
  my $important_interrupts_re = qr/^(nxge|igb|ixgbe|i40e)/;

  while ($output =~ m{^([^:]+):([^\n]+)\n}gsmx) {
    my ($link,$state) = ($1, $2);
    # If the link is "up" and it's "important"
    if (($state eq "up") and ($link =~ m/$important_interrupts_re/smx)) {
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

  my $output = IPC::System::Simple::capture("$PRTCONF -b");
  # TODO: check state of command
  if ( not length($output) ) {
    #  say "No output from prtconf -b";
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
