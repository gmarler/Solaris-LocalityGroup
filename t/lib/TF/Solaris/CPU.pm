package TF::Solaris::CPU;

use File::Temp               qw();
use Readonly                 qw();
use Data::Dumper             qw();

use Test::Class::Moose;
with 'Test::Class::Moose::Role::AutoUse';

use Solaris::LocalityGroup::Root;

Readonly::Scalar my $KSTAT  => '/bin/kstat';

my $mock_cpu_kstats = [
  "kstat-OPL-SPARC64-VII.out",
  "kstat-M9000.out-N069",
  "kstat-M5000.out-J078",
  "kstat-T4-4.out",
  "kstat-T4-4.out-P110",
  "kstat-T5-2.out",
  "kstat-T5-2.out-NJDSRV1",
  "kstat-T5-4.out",
  "kstat-T5-8.out",
];

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

  #$test->{sockpath} = "/tmp/test_glogserver_sockpath.sock-$$";
  #diag "Test socket path will be $test->{sockpath}";

  my (@mocked_kstats);
  foreach my $kstat_file (@{$mock_cpu_kstats}) {
    my $datafile = shift;
    my $filepath =
    Path::Class::File->new(__FILE__)->parent->parent->parent->parent->parent
                     ->file("t","data",$kstat_file)
                     ->absolute->stringify;

    my $fh       = IO::File->new($filepath,"<") or
    die "Unable to open $filepath for reading";
  
    my $content = do { local $/; <$fh>; };
  
    $fh->close;
    push @mocked_kstats, $content;
  }
  $test->{mocked_kstats} = \@mocked_kstats;
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

sub test_parse_live_kstat_cpu_info {
  my ($test) = shift;

  my $stdout = qx{$KSTAT -p 'cpu_info:::/^\(?:brand|chip_id|core_id|cpu_type|device_ID|pg_id|state|state_begin\)\$/'};

  cmp_ok(length($stdout), '>', 0, 'Actually got kstat output for cpu_info');

  #
  # NOTE: Using parser from Solaris::LocalityGroup::Root
  #
  my $aref = Solaris::LocalityGroup::Root->_parse_kstat_cpu_info($stdout);

  my $id_re = re('^\d+$');
  my $state_re = re('on-line|off-line|spare|no-intr');

  my $cpu_cmp = {
    id          => $id_re,
    brand       => ignore(),
    chip_id     => $id_re,
    core_id     => $id_re,
    device_ID   => $id_re,
    cpu_type    => ignore(),
    pg_id       => $id_re,
    state       => $state_re,
    state_begin => $id_re,
  };
 
  cmp_deeply( $aref,
              array_each( isa('HASH') ),
              'Data Parsing produces array of hashrefs'
            );
  cmp_deeply( $aref,
              array_each( $cpu_cmp ),
              'Parsed data has right hash format'
            );
}

sub test_parse_mocked_kstat_cpu_info {
  my ($test) = shift;
  my (@mocked_kstats) = @{$test->{mocked_kstats}};

  my $id_re = re('^\d+$');
  my $state_re = re('on-line|off-line|spare|no-intr');

  my $cpu_cmp = {
    id          => $id_re,
    brand       => ignore(),
    chip_id     => $id_re,
    core_id     => $id_re,
    device_ID   => $id_re,
    cpu_type    => ignore(),
    pg_id       => $id_re,
    state       => $state_re,
    state_begin => $id_re,
  };

  foreach my $kstat_output (@mocked_kstats) {
    #
    # NOTE: Using parser from Solaris::LocalityGroup::Root
    #
    my $aref = Solaris::LocalityGroup::Root->_parse_kstat_cpu_info($kstat_output);
    cmp_deeply( $aref,
                array_each( isa('HASH') ),
                'Data Parsing produces array of hashrefs'
    );
    cmp_deeply( $aref,
                array_each( $cpu_cmp ),
                'Parsed data has right hash format'
    );


  }
}


