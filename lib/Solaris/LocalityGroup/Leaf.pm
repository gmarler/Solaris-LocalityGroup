use strict;
use warnings;
use v5.18.1;
use feature qw(say);

package Solaris::LocalityGroup::Leaf;

# VERSION
#
# ABSTRACT: Solaris Locality Group Root abstraction - represents entire system

use Moose;
use Moose::Util::TypeConstraints;
use MooseX::ClassAttribute;
with 'MooseX::Log::Log4perl';
use Data::Dumper;
use Solaris::CPU::Core;
use Solaris::CPU::vCPU;

use namespace::autoclean;

use autodie                             qw(:all);
use Readonly                            qw();


Readonly::Scalar my $KSTAT    => '/bin/kstat';
Readonly::Scalar my $LGRPINFO => '/bin/lgrpinfo';

#
# Instance Attributes
#

has 'id'        => ( isa      => 'Int',
                     is       => 'ro',
                     required => 1,
                   );

has 'cores'     => ( isa => 'HashRef[Solaris::CPU::Core]|Undef',
                     is => 'ro',
                     # init_arg => cpu_info_data,
                   );

has 'cpus'      => ( isa => 'HashRef[Solaris::CPU::vCPU]|Undef',
                     is  => 'ro',
                   );

override BUILDARGS => sub {
  my $self = shift;

  my %args = @_;

  say Dumper(\%args);

  # We're passing in lgrp => { lgrp => <ID>, lgrpinfo_cpus => ... }, so we need to
  # deal with it as such (two levels of indirection)
  if (exists($args{'lgrp'})) {
    my $id = $args{'lgrp'}->{'lgrp'};
    delete $args{'lgrp'};
    return { id => $id, %args };
  }

  return super;
};

sub BUILD {
  my $self = shift;

  my $id = $self->id;
  say "Building Locality Group Leaf: $id";
}

=head2 PUBLIC Methods

=method print

Print out information on this leaf Locality Gruop

=cut

sub print
{
  my $self = shift;

}

=head1 PRIVATE Methods

=cut

# sub _build_id {
#   my $self     = shift;
#   my $con_args = shift;
# 
#   my $id = $con_args->{lgrp};
# 
#   say "Building Locality Group Leaf: $id";
# 
#   return $id;
# }

1;
