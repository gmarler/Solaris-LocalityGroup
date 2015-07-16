use strict;
use warnings;

package Solaris::LocalityGroup::App;

use Moose;

extends qw(MooseX::App::Cmd);


package Solaris::LocalityGroup::App::Command::terse;

use Moose;
extends qw(MooseX::App::Cmd::Command);

use Solaris::LocalityGroup::Root;

sub execute {
  my ($self, $opt, $args) = @_;

  my $root_lg = Solaris::LocalityGroup::Root->new();
  $root_lg->print_cpu_avail_terse();
}

1;
