use v5.18.1;
use feature qw(say);

package TF::Solaris::LocalityGroup::Root;

use File::Temp               qw();
use Readonly                 qw();
use Data::Dumper             qw();
use Carp                     qw(confess);
use Path::Class::File        qw();
use Test::MockModule         qw();

use Test::Class::Moose;
with 'Test::Class::Moose::Role::AutoUse';
use Test::Output;

Readonly::Scalar my $KSTAT    => '/bin/kstat';
Readonly::Scalar my $LGRPINFO => '/bin/lgrpinfo';

# MOCK qx{}, backticks calls, so we can pass in known kstat / lgrpinfo from a
# variety of different system types for testing
our $mock_readpipe = sub { return &CORE::readpipe(@_); };

BEGIN {
  # Attempt to use https://gist.github.com/CUXIDUMDUM/7142813
  #*CORE::GLOBAL::readpipe = sub { $mock_readpipe->(@_); };
  *CORE::GLOBAL::readpipe = \&_mock_readpipe
};

# The global contents of the current lgrpinfo / kstat output file, which will be
# used by _mock_readpipe()
#
our ($lgrpinfo,$kstat,$interrupts,$dladm_show_ether,$prtconf_b);
our ($psrset);
our $pbinds;

# NOTE / WARNING: The "name" below must be unique, as this gets turned into a
#                 hash later
my $mock_files = {
  "M9000" =>   [
                 { # P019
                   name             => "PORT pure SPARC64-VII",
                   lgrpinfo         => "lgrpinfo-OPL-SPARC64-VII.out",
                   kstat            => "kstat-OPL-SPARC64-VII.out",
                   interrupts       => "kstat-pci_intrs-OPL-SPARC64-VII.out",
                   dladm_show_ether => "dladm-show-ether-OPL-SPARC64-VII.out",
                   prtconf_b        => "prtconf_b-M9000.out",
                   psrset           => "psrset-OPS-SPARC64-VII.out",
                 },
                 { # N069
                   name             => "FX SPARC-VI and SPARC64-VII+ mix",
                   lgrpinfo         => "lgrpinfo-M9000.out-N069",
                   kstat            => "kstat-M9000.out-N069",
                   interrupts       => "kstat-pci_intrs-M9000.out-N069",
                   dladm_show_ether => "dladm-show-ether-M9000.out-N069",
                   prtconf_b        => "prtconf_b-M9000.out-N069",
                 },
               ],
  "M5000" =>   [
                 { # J078
                   name             => "UNKNOWN",
                   lgrpinfo         => "lgrpinfo-M5000.out-J078",
                   kstat            => "kstat-M5000.out-J078",
                   interrupts       => "kstat-pci_intrs-M5000.out-J078",
                   dladm_show_ether => "dladm-show-ether-M5000.out-J078",
                   prtconf_b        => "prtconf_b-M5000.out-J078",
                 },
               ],
  "T4-4"  =>   [
                 { 
                   name             => "Perf Test Host 1",
                   lgrpinfo         => "lgrpinfo-T4-4.out",
                   kstat            => "kstat-T4-4.out",
                   interrupts       => "kstat-pci_intrs-T4-4.out",
                   dladm_show_ether => "dladm-show-ether-T4-4.out",
                   prtconf_b        => "prtconf_b-T4-4.out",
                 },
                 {
                   name             => "USER",
                   lgrpinfo         => "lgrpinfo-T4-4.out-P110",
                   kstat            => "kstat-T4-4.out-P110",
                   interrupts       => "kstat-pci_intrs-T4-4.out-P110",
                   dladm_show_ether => "dladm-show-ether-T4-4.out-P110",
                   prtconf_b        => "prtconf_b-T4-4.out-P110",
                 },
               ],
  "T5-2"  =>   [
                 { # NYSOLPERF1
                   name             => "Perf Test Host 2",
                   lgrpinfo         => "lgrpinfo-T5-2.out",
                   kstat            => "kstat-T5-2.out",
                   interrupts       => "kstat-pci_intrs-T5-2.out",
                   dladm_show_ether => "dladm-show-ether-T5-2.out",
                   prtconf_b        => "prtconf_b-T5-2.out",
                 },
                 { 
                   name             => "DSRV",
                   lgrpinfo         => "lgrpinfo-T5-2.out-NJDSRV1",
                   kstat            => "kstat-T5-2.out-NJDSRV1",
                   interrupts       => "kstat-pci_intrs-T5-2.out-NJDSRV1",
                   dladm_show_ether => "dladm-show-ether-T5-2.out-NJDSRV1",
                   prtconf_b        => "prtconf_b-T5-2.out-NJDSRV1",
                 },

               ],
  "T5-4"  =>   [
                 { # SUNDEV51
                   name             => "DEV",
                   lgrpinfo         => "lgrpinfo-T5-4.out",
                   kstat            => "kstat-T5-4.out",
                   interrupts       => "kstat-pci_intrs-T5-4.out",
                   dladm_show_ether => "dladm-show-ether-T5-4.out",
                   prtconf_b        => "prtconf_b-T5-4.out",
                 },
               ],
  "T5-8"  =>   [
                 { # P300
                   name             => "GSRV",
                   lgrpinfo         => "lgrpinfo-T5-8.out",
                   kstat            => "kstat-T5-8.out",
                   interrupts       => "kstat-pci_intrs-T5-8.out",
                   dladm_show_ether => "dladm-show-ether-T5-8.out",
                   prtconf_b        => "prtconf_b-T5-8.out",
                   psrset           => "psrset-T5-8.out",
                 },
               ],
};

# Prep this for population via the test_startup() function
my $mock_output = {
# "M9000"           => { },
# "T4-4"            => { },
#  "T5-2"            => { },
# "T5-4"            => { },
# "T5-8"            => { },
};

# On a Platform basis, the counts of various CPU related components, to be
# tested against
my $platform_counts = {
  # OPL Platforms have variable CPU / Core counts, so it's harder to do this
  # test
  "T4-4"            => { cpu_count  =>  256,
                         core_count =>   32,
                       },
  "T5-2"            => { cpu_count  =>  256,
                         core_count =>   32,
                       },
  "T5-4"            => { cpu_count  =>  512,
                         core_count =>   64,
                       },
  "T5-8"            => { cpu_count  => 1024,
                         core_count =>  128,
                       },
};


sub test_startup {
  my ($test) = shift;
  $test->next::method;

  my $logfile_fh   = File::Temp->new();
  my $logfile_name = $logfile_fh->filename;

  diag "Test logging to $logfile_name";

  # Log::Log4perl Configuration in a string ...
  my $conf = qq(
    #log4perl.rootLogger          = DEBUG, Logfile, Screen
    #log4perl.rootLogger          = DEBUG, Screen
    log4perl.rootLogger          = DEBUG, Logfile

    log4perl.appender.Logfile          = Log::Log4perl::Appender::File
    log4perl.appender.Logfile.filename = $logfile_name
    log4perl.appender.Logfile.layout   = Log::Log4perl::Layout::PatternLayout
    log4perl.appender.Logfile.layout.ConversionPattern = [%r] %F %L %m%n

    log4perl.appender.Screen         = Log::Log4perl::Appender::Screen
    log4perl.appender.Screen.stderr  = 0
    log4perl.appender.Screen.layout = Log::Log4perl::Layout::SimpleLayout
  );

  # ... passed as a reference to init()
  Log::Log4perl::init( \$conf );

  foreach my $platform (keys %$mock_files) {
    foreach my $machine (@{$mock_files->{$platform}}) {
      #say Data::Dumper::Dumper($machine);
      my $lgrpinfo_c         = _load_mock_data($machine->{lgrpinfo});
      my $kstat_c            = _load_mock_data($machine->{kstat});
      my $interrupts_c       = _load_mock_data($machine->{interrupts});
      my $dladm_show_ether_c = _load_mock_data($machine->{dladm_show_ether});
      my $prtconf_b_c        = _load_mock_data($machine->{prtconf_b});
      my $psrset_c          = _load_mock_data($machine->{psrset});

      my $name = $machine->{name};  # The name of the test type

      $mock_output->{$name}->{lgrpinfo}         = $lgrpinfo_c;
      $mock_output->{$name}->{kstat}            = $kstat_c;
      $mock_output->{$name}->{interrupts}       = $interrupts_c;
      $mock_output->{$name}->{dladm_show_ether} = $dladm_show_ether_c;
      $mock_output->{$name}->{psrset}           = $psrset_c;
    }
  }

  # TODO: Get rid of this, once we do it properly below...
  $lgrpinfo         = $mock_output->{"USER"}->{lgrpinfo};
  $kstat            = $mock_output->{"USER"}->{kstat};
  $interrupts       = $mock_output->{"USER"}->{interrupts};
  $dladm_show_ether = $mock_output->{"USER"}->{dladm_show_ether};
  $prtconf_b        = $mock_output->{"USER"}->{prtconf_b};
  $psrset           = $mock_output->{"USER"}->{psrset};

  # $test->{ctor_args}  = $lgrp_specs_aref;
  # $test->{kstat_args} = $cpu_specs_aref;
}

sub test_setup {
  my $test = shift;
  my $test_method = $test->test_report->current_method;

  # if ( 'test_server_logfile' eq $test_method->name ) {
  #   $test->test_skip("TODO");
  # } elsif ( 'test_server_connect_disconnect' eq $test_method->name ) {
  #   $test->test_skip("TODO");
  # } elsif ( 'test_server_connect_bad_protocol' eq $test_method->name ) {
  #   $test->test_skip("TODO");
  # } elsif ( 'test_server_rotate_logs' eq $test_method->name ) {
  #   $test->test_skip("TODO");
  # }
}

# Test kstat / lgrpinfo without mocking them, live for this machine type
sub test_attrs_live {
  my $test = shift;

  my $obj = Solaris::LocalityGroup::Root->new( );

  isa_ok($obj, 'Solaris::LocalityGroup::Root', 'object is of proper class');

  can_ok($obj, qw( leaves ) );

  # Test that returned Locality Group Leaves are valid
  my $leaves = $obj->leaves;
  isa_ok($leaves, 'ARRAY' );

  my @leaves = @{$leaves};
  cmp_deeply(\@leaves, array_each(isa("Solaris::LocalityGroup::Leaf")),
             'LG leaves are of the proper object type');

  stdout_like( sub { $obj->print }, qr/Locality\sGroup:/,
              'printing LG leaves ok');
}

# Use all saved mocked output of lgrpinfo and kstat to determine if constructor
# works as expected
sub test_constructor_mocked {
  my $test = shift;

  my @mocked_objs;

  foreach my $machtype (keys %$mock_output) {
    # say "MACHTYPE: $machtype";
    $lgrpinfo   = $mock_output->{$machtype}->{lgrpinfo};
    $kstat      = $mock_output->{$machtype}->{kstat};
    $interrupts = $mock_output->{$machtype}->{interrupts};
    $prtconf_b  = $mock_output->{$machtype}->{prtconf_b};
    $psrset     = $mock_output->{$machtype}->{psrset};

    my $obj   = Solaris::LocalityGroup::Root->new( );
    push @mocked_objs, $obj;
    # TODO: machine specific tests are needed here
  }

  # Attempt to use: https://gist.github.com/CUXIDUMDUM/7142813
  # {
  #   my $module = Test::MockModule->new('Solaris::LocalityGroup::Root');
  #   $module->mock(
  #     '_build_lgrp_leaves',
  #     sub {
  #       local $mock_readpipe = sub { die "mocked" };
  #       my $orig = $module->original('_build_lgrp_leaves');
  #       return $orig->(@_);
  #     }
  #   );
  #   my $obj   = Solaris::LocalityGroup::Root->new( );
  #   push @mocked_objs, $obj;
  #   $obj->print_cpu_avail_terse;
  # }

  # Are Root objects correct?
  my $ctests = all( isa("Solaris::LocalityGroup::Root"), );
  cmp_deeply(\@mocked_objs, array_each($ctests),
             'Mocked LG leaves are of the proper object type');

  # Are Root objects composed of Leaves?
  my (@mocked_leaf_list);
  foreach my $root (@mocked_objs) {
    my $leaves = $root->leaves;
    push @mocked_leaf_list, $leaves;
  }
  cmp_deeply(\@mocked_leaf_list, array_each(isa("ARRAY")),
             'Mocked LG Roots are have an array of leaves');
  # ... and are the leaves of the right object type?
  cmp_deeply(\@mocked_leaf_list,
             array_each(array_each(isa("Solaris::LocalityGroup::Leaf"))),
             'Each Mocked LG Root has Leaves that are of the correct object type');

  # Squirrel away mocked objects
  $test->{mocked_root_objs} = \@mocked_objs;
}

sub test_core_count {
  my $test = shift;

  my @mocked_objs = @{$test->{mocked_root_objs}};
  my @objs_to_test;

  foreach my $obj (@mocked_objs) {
    my $platform = $obj->platform;
    if (exists($platform_counts->{$platform})) {
      cmp_ok($obj->core_count, '==',
             $platform_counts->{$platform}->{core_count},
             'Correct core count for ' . $platform);
    }
  }

}

sub test_cpu_count {
  my $test = shift;

  my @mocked_objs = @{$test->{mocked_root_objs}};

  foreach my $obj (@mocked_objs) {
    my $platform = $obj->platform;
    if (exists($platform_counts->{$platform})) {
      cmp_ok($obj->cpu_count, '==',
             $platform_counts->{$platform}->{cpu_count},
             'Correct CPU count for ' . $platform);
    }
  }
}


sub test_print_cpu_avail_terse_mocked {
  my $test = shift;

#  # Get the T4-4 item off the mock_output list for testing at the moment
#  # NOTE: This is currently setting a global 'our' variable pair
#  $lgrpinfo         = $mock_output->{'T5-4'}->{lgrpinfo};
#  $kstat            = $mock_output->{'T5-4'}->{kstat};
#  $interrupts       = $mock_output->{'T5-4'}->{interrupts};
#  $dladm_show_ether = $mock_output->{'T5-4'}->{dladm_show_ether};
#
#  my $obj = Solaris::LocalityGroup::Root->new( );

  my @mocked_objs = @{$test->{mocked_root_objs}};

  foreach my $obj (@mocked_objs) {
    #isa_ok($obj, 'Solaris::LocalityGroup::Root');
    stdout_like( sub { $obj->print_cpu_avail_terse }, qr/LGRP/,
                $obj->platform . ': terse CPU list available for binding' );
    say $obj->print_cpu_avail_terse;
  }
}

# Stolen from Solaris::LocalityGroup::Root
sub _parse_lgrpinfo {
  my $self       = shift;
  my $c          = shift;
  my @ctor_args;

  my $re =
    qr{^lgroup \s+ (?<lgroup>\d+) \s+ \(leaf\):\n
       ^ \s+ CPUs: \s+ (?<cpufirst>\d+)-(?<cpulast>\d+)   \n
      }smx;

  while ($c =~ m/$re/gsmx) {
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

    ($cpu_id = $keypart) =~ s{^cpu_info:(\d+):.+$}{$1};

    ($key = $keypart) =~ s{^cpu_info:$cpu_id:[^:]+:(\S+)$}{$1};

    $cpu_ctor_args{$cpu_id}->{$key} = $value;
  }

  @ctor_args = map { my $cpu_id = $_;
                    { id => $cpu_id,
                      map {
                        $_ => $cpu_ctor_args{$cpu_id}->{$_};
                      } keys $cpu_ctor_args{$cpu_id},
                    };
                  } keys %cpu_ctor_args;

  return \@ctor_args;
}


sub _mock_readpipe {
  my $cmd = shift;

  if ($cmd =~ m/^\$LGRPINFO/) {
    return $lgrpinfo;
  } elsif ($cmd =~ m/^\$KSTAT\s+\-p\s+\'cpu_info/) {
    return $kstat;
  } elsif ($cmd =~ m/^\$KSTAT\s+\-p\s+\'pci_intr/) {
    return $interrupts;
  } elsif ($cmd =~ m/^\$DLADM\s+show-ether/) {
    return $dladm_show_ether;
  } elsif ($cmd =~ m/^\$PRTCONF\s+\-b/) {
    return $prtconf_b;
  } elsif ($cmd =~ m/^\$PSRSET/) {
    return $psrset;
  } else {
    confess "NOT IMPLEMENTED";
  }
}

sub _load_mock_data {
  my $datafile = shift;
  my $filepath =
  Path::Class::File->new(__FILE__)->parent->parent->parent->parent->parent
                   ->file("data",$datafile)
                   ->absolute->stringify;

  my $fh       = IO::File->new($filepath,"<") or
  die "Unable to open $filepath for reading";

  my $content = do { local $/; <$fh>; };

  $fh->close;
  return $content;
}


1;
