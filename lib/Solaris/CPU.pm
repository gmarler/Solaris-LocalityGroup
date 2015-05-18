use strict;
use warnings;
use v5.18.1;
use feature qw(say);

package Solaris::CPU;

# VERSION

use Moose;
use Moose::Util::TypeConstraints;
use MooseX::ClassAttribute;
with 'MooseX::Log::Log4perl';

use namespace::autoclean;

use autodie                             qw(:all);
use Readonly                            qw();


Readonly::Scalar my $KSTAT  => '/bin/kstat';

#
# Class Attribute
#
class_has 'Cache' =>
    ( is      => 'rw',
      isa     => 'HashRef',
      default => sub { {} },
    );

#
# Instance Attributes
#
# CPU ID (vCPU)
has 'id'    => ( isa => 'Num', is => 'ro', required => 1 );
# CPU Description
has 'brand' => ( isa => 'Str', is => 'ro', required => 1 );
# CPU State
has 'state' => ( isa => 'Str', is => 'ro', required => 1 );

# Constructor 
#   Dependency Injection:
#   - Class method:
#     - No options indicates kstat ... should be run
#       and possibly generate many instances
#       - NEED TO MOCK OUTPUT OF kstat ... for all CPU types
#

sub new_from_kstat {
  my $self = shift;

  my $stdout = qx{$KSTAT -p 'cpu_info:::/^\(?:brand|chip_id|cpu_type|device_ID|pg_id|state|state_begin\)\$/'};

  my $specs_aref = __PACKAGE__->_parse_kstat_cpu_info($stdout);
  my @objs       = map { __PACKAGE__->new(%$_) } @$specs_aref;

  # Add to Class Object Cache attribute, for ease of lookups later
  foreach my $obj (@objs) {
    __PACKAGE__->Cache()->{$obj->id} = $obj;
  }
  
  # TODO: wantarray() handling
  return \@objs;
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

  return \@con_args;
}


__PACKAGE__->meta()->make_immutable();
 
no Moose;
no MooseX::ClassAttribute;

1;
