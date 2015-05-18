package TF::Solaris::CPU;

use File::Temp               qw();
use Readonly                 qw();
use Data::Dumper             qw();

use Test::Class::Moose;
with 'Test::Class::Moose::Role::AutoUse';

Readonly::Scalar my $KSTAT  => '/bin/kstat';


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

sub test_parse_kstat_cpu_info {
  my ($test) = shift;

  my $stdout = qx{$KSTAT -p 'cpu_info:::/^\(?:brand|chip_id|cpu_type|device_ID|pg_id|state|state_begin\)\$/'};

  #diag $stdout;

  cmp_ok(length($stdout), '>', 0, 'Actually got kstat output for cpu_info');

  my $aref = Solaris::CPU->_parse_kstat_cpu_info($stdout);

  my $d = Data::Dumper->new( $aref );

  #diag $d->Dump;
  my $id_re = re('^\d+$');
  my $cpu_cmp = {
    id => $id_re,
  };
 
  cmp_deeply( $aref,
              array_each( isa('HASH') )
            );
  #foreach my $e (@$aref) {
  #  cmp_deeply( $e, any( hash_each( $cpu_cmp ) ) );
  #}
}

sub test_new_from_kstat {
  my ($test) = shift;

  my $aref = Solaris::CPU->new_from_kstat();

  cmp_deeply( $aref, array_each( isa('Solaris::CPU') ) );

  my $d = Data::Dumper->new( $aref );

  diag $d->Dump;
}


