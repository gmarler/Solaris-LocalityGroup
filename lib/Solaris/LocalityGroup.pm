use strict;
use warnings;
use v5.18.1;
use feature qw(say);

package Solaris::LocalityGroup;

# VERSION
#
# ABSTRACT: Solaris Locality Group (NUMA node) abstraction

use Moose;
use Moose::Util::TypeConstraints;
use MooseX::ClassAttribute;
with 'MooseX::Log::Log4perl';

use namespace::autoclean;

use autodie                             qw(:all);
use Readonly                            qw();


Readonly::Scalar my $KSTAT    => '/bin/kstat';
Readonly::Scalar my $LGRPINFO => '/bin/lgrpinfo';

#
# Instance Attributes
#
# Locality Group Type
# TODO: This has been replaced by having LocalityGroup::{Root|Leaf} subclasses instead
#       Clean this up
has 'type'      => ( isa => enum([ qw( root leaf ) ]), is => 'ro', required => 1 );

# has 'lgrps'     => ( isa => 

sub new_from_lgrpinfo {
  my $self = shift;

  my $stdout = qx{$LGRPINFO -cCG};

  my $specs_aref = __PACKAGE__->_parse_lgrpinfo($stdout);
  my @objs       = map { __PACKAGE__->new(%$_) } @$specs_aref;

  # Add to Class Object Cache attribute, for ease of lookups later
  #foreach my $obj (@objs) {
  #  __PACKAGE__->Cache()->{$obj->id} = $obj;
  #}
  
  # TODO: wantarray() handling
  return \@objs;
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

  my (@lines) = split /\n/, $c;

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
