use Config;
use File::Basename qw(basename dirname);
chdir(dirname($0));
($file = basename($0)) =~ s/\.pl$//;
$file =~ s/\.pl$//
        if ($Config{'osname'} eq 'VMS' or
            $Config{'osname'} eq 'OS2');  # "case-forgiving"
open OUT,">$file" or die "Can't create $file: $!";
chmod(0755, $file);
print "Extracting $file (with variable substitutions)\n";
 
print OUT <<"!GROK!THIS!";
$Config{'startperl'} -w
    eval 'exec perl -S \$0 "\$@"'
        if 0;
 
!GROK!THIS!
 
print OUT <<'!NO!SUBS!';
#!/usr/bin/perl -w
#
# checkbot - A perl5 script to check validity of links in www document trees
#
# Hans de Graaff <hans@degraaff.org>, 1994-2000.
# Based on Dimitri Tischenko, Delft University of Technology, 1994
# Based on the testlinks script by Roy Fielding
# With contributions from Bruce Speyer <bruce.speyer@elecomm.com>
#
# Info-URL: http://degraaff.org/checkbot/
# Comments to: checkbot@degraaff.org
#
# $Id: checkbot.pl,v 1.61 2000/06/29 19:56:48 graaff Exp $
# (Log information can be found at the end of the script)

require 5.004;
use strict;

require LWP;

=head1 NAME

Checkbot - WWW Link Verifier

=head1 SYNOPSIS

checkbot [B<--debug>] [B<--help>] [B<--verbose>] [B<--url> start URL] 
         [B<--match> match string] [B<--exclude> exclude string]
         [B<--proxy> proxy URL] [B<--internal-only>]
         [B<--ignore> ignore string] [B<-file> file name] 
         [B<--mailto> email address]
         [B<--note> note] [B<--sleep> seconds] [B<--timeout> timeout]
         [B<--interval> seconds] [B<--dontwarn> HTTP responde codes]
         [start URLs]

=head1 DESCRIPTION

Checkbot verifies the links in a specific portion of the World Wide
Web. It creates HTML pages with diagnostics. 

Options for Checkbot are:

=over 4

=item --url <start URL>

Set the start URL. Checkbot starts checking at this URL, and then
recursively checks all links found on this page. The start URL takes
precedence over additional URLs specified on the command line.

If no scheme is protocol for the URL, the file protocol is assumed.

=item --match <match string>

This option selects which pages Checkbot considers local. If the
I<match string> is contained within the URL, then Checkbot considers
the page local, retrieves it, and will check all the links contained
on it. Otherwise the page is considered external and it is only
checked with a HEAD request.

If no explicit I<match string> is given, the first start URL (See
option C<--url>) will be used as a match string instead.

The I<match string> can be a perl regular expression.

=item --exclude <exclude string>

URLs matching the I<exclude string> are considered to be external,
even if they happen to match the I<match string> (See option C<--match>).

The I<exclude string> can be a perl regular expression.

=item --ignore <ignore string>

If a URL has an error, and matches the I<ignore string>, its error
will not be listed. This can be useful to stop certain errors from
being listed.

The I<ignore string> can be a perl regular expression.

=item --proxy <proxy URL>

This attribute specifies the URL for a proxy server.  Only external URLs 
are queried through this proxy server, because Checkbot assumes all 
internal URLs can be accessed directly.  Currently only the HTTP and FTP 
protocols will be send to the proxy server.

=item --internal-only 

Skip the checking of external links at the end of the Checkbot
run. Only matching links are checked. Not that some redirections may
still cause external links to be checked.

=item --mailto <email address>

Send mail to the I<email address> when Checkbot is done
checking. Includes a small summary of the results.

=item --note <note>

The I<note> is included verbatim in the mail message (See option
C<--mailto>). This can be useful to include the URL of the summary HTML page
for easy reference, for instance.

Only meaningful in combination with the C<--mailto> option.

=item --help

Shows brief help message on the standard output.

=item --verbose

Show verbose output while running. Includes all links checked, results
from the checks, etc.

=item --debug

Enable debugging mode. Not really supported anymore.

=item --sleep <seconds>

Number of I<seconds> to sleep in between requests. Default is 2 seconds. 

=item --timeout <timeout>

Default timeout for the requests, specified in seconds. The default is
2 minutes.

=item --interval <seconds>

The maximum interval between updates in seconds. Default is 3 hours
(10800 seconds). Checkbot will start the intervale at one minute, and
gradually extend it towards the maximum interval.

=item --file <file name>

Write the summary pages into file I<file name>. Default is C<checkbot.html>.

=item --dontwarn <HTTP response codes regular expression>

Don't include warnings on the result pages for those HTTP response
codes which match the regular expression. For instance, --dontwarn
"(301|404)" would not include 301 and 404 response codes.

=back

=head1 PREREQUISITES

This script uses the C<LWP> modules.

=head1 COREQUISITES

This script can send mail when C<Mail::Send> is present.

=head1 AUTHOR

Hans de Graaff <hans@degraaff.org>

=pod OSNAMES 

any

=cut

# Prepare the use of DBM files, and show our preferences
use AnyDBM_File;
@AnyDBM_File::ISA = qw(DB_File GDBM_File NDBM_File);

# Declare some global variables, avoids ugly use of main:: all around
my @starturls = ();
# A hash of warnings generated by Checkbot apart from HTTP responses
my %warning = ();

# This hash is indexed by two fields, and contains an array of responses:
# $problems{HTTP Response code}{URL} = @( HTTP::Response );
my %problems = ();

# Version information
my $VERSION;
( $VERSION ) = sprintf("%d.%02d", q$Revision: 1.61 $ =~ /(\d+)\.(\d+)/);

# If on a Mac we should ask for the arguments through some MacPerl stuff
if ($^O eq 'MacOS') {
  $main::mac_answer = eval "MacPerl::Ask('Enter Command-Line Options')";
  push(@ARGV, split(' ', $main::mac_answer));
}

&check_options();
&init_modules();
&init_globals();
&setup();

# Start actual application
&check_internal();

# Empty checked array to clear up memory
undef %main::checked;
%main::checked = ();

if (defined $main::opt_internal_only) {
  print STDERR "*** Not checking external links because of --internal-only option.\n"
    if defined $main::opt_verbose;
} else {
  check_external();
}

&create_page(1);
&send_mail if defined $main::opt_mailto;

&clean_up();

exit 0;

### Initialization and setup routines

sub check_options {

  # Get command-line arguments
  use Getopt::Long;
  my $result = GetOptions(qw(debug help verbose url=s match=s exclude|x=s file=s ignore|z=s mailto|M=s note|N=s proxy=s internal-only sleep=i timeout=i interval=i dontwarn=s));

  # Handle arguments, some are mandatory, some have defaults
  &print_help if (($main::opt_help && $main::opt_help) 
                  || (!$main::opt_url && $#ARGV == -1));
  $main::opt_timeout = 120 unless defined($main::opt_timeout) && length($main::opt_timeout);
  $main::opt_verbose = 0 unless $main::opt_verbose;
  $main::opt_sleep = 2 unless defined($main::opt_sleep) && length($main::opt_sleep);
  $main::opt_interval = 10800 unless defined $main::opt_interval and length $main::opt_interval;
  $main::opt_dontwarn = "xxx" unless defined $main::opt_dontwarn and length $main::opt_dontwarn;
  # The default for opt_match will be set later, because we might want
  # to muck with opt_url first.

  # Display messages about the options
  print STDERR "*** Starting Checkbot $VERSION in verbose mode\n" 
    if $main::opt_verbose;
  print STDERR "    Will skip checking of external links\n"
    if $main::opt_internal_only;
}

sub init_modules {

  use URI;
  # Prepare the user agent to be used:
  use LWP::UserAgent;
  use LWP::MediaTypes;
  #use LWP::Debug qw(- +debug);
  use HTML::LinkExtor;
  $main::ua = new LWP::UserAgent;
  $main::ua->agent("Checkbot/$VERSION LWP/" . LWP::Version);
  $main::ua->timeout($main::opt_timeout);

  # Don't use strict parsing, it is very likely we will
  # encounter invalid HTML documents on the way.
  URI::URL::strict(0);

  require Mail::Send if defined $main::opt_mailto;

  use HTTP::Status;
}

sub init_globals {
  my $url;

  # Remember start time
  $main::start_time = localtime();

  # Directory and files for output
  if ($main::opt_file) {
    $main::file = $main::opt_file;
    $main::file =~ /(.*)\./;
    $main::server_prefix = $1;
  } else { 
    $main::file = "checkbot.html";
    $main::server_prefix = "checkbot";
  }
  $main::tmpdir = ($ENV{'TMPDIR'} or "/tmp") . "/Checkbot.$$";

  $main::cur_queue  = $main::tmpdir . "/queue";
  $main::new_queue  = $main::tmpdir . "/queue-new";
  $main::extfile = $main::tmpdir . "/external";

  # Set up hashes to be used
  %main::checked = ();
  %main::servers = ();
  %main::servers_get_only = ();

  # Initialize the start URLs. --url takes precedence. Otherwise
  # just process URLs in order as they appear on the command line.
  unshift(@ARGV, $main::opt_url) if $main::opt_url;
  foreach (@ARGV) {
    $url = new URI::URL $_;
    # If no scheme is defined we will assume file is used, so that
    # it becomes easy to check a single file.
    $url->scheme('file') unless defined $url->scheme;
    $url->host('localhost') if $url->scheme eq 'file';
    if (!defined $main::opt_match) {
      $main::opt_match = quotemeta $url;
    }
    if (!defined $url->host) {
      warn "No host specified in URL $url, ignoring it.\n";
      next;
    }
    push(@starturls, $url);
  }
  die "There are no valid starting URLs to begin checking with!\n"
    if scalar(@starturls) == -1;

  # Variables to keep track of number of links
  $main::LINKS = 0;
  $main::DUPS  = 1;
  $main::PROBL = 2;
  $main::TODO = 3;

  @main::st_int = (0, 0, 0, scalar(@starturls));
  @main::st_ext = (0, 0, 0, 0);

  # We write out our status every now and then.
  $main::cp_int = 1;
  $main::cp_last = time();

}


sub setup {

  mkdir $main::tmpdir, 0755
    || die "$0: unable to create directory $main::tmpdir: $!\n";

  # Explicitly set the record separator. I had the problem that this
  # was not defined under my perl 5.00502. This should fix that, and
  # not cause problems for older versions of perl.
  $/ = "\n";

  open(EXTERNAL, ">$main::extfile")
    || die "$0: Unable to open EXTERNAL $main::extfile for writing: $!\n";
  open(CURRENT, ">$main::cur_queue")
    || die "$0: Unable to open CURRENT $main::cur_queue for writing: $!\n";
  open(QUEUE, ">$main::new_queue")
    || die "$0: Unable to open QUEUE $main::new_queue for writing: $!\n";


  # Prepare CURRENT queue with starting URLs
  foreach (@starturls) {
    print CURRENT $_->as_string . "|\n";
  }
  close CURRENT;

  open(CURRENT, $main::cur_queue) 
    || die "$0: Unable to open CURRENT $main::cur_queue for reading: $!\n";

}

### Cleaning up after running Checkbot
sub clean_up {
  unless (defined($main::opt_debug)) {
    unlink $main::cur_queue, $main::new_queue, $main::extfile;
    rmdir $main::tmpdir;
  }
}


### Main application code

sub check_internal {
  my $line;

  # As long as there are links to do, check them
  while ( $main::st_int[$main::TODO] > 0 ) {
    # Read a line from the queue, and process it
    while (defined ($line = <CURRENT>) ) {
      chomp($line);
      &handle_url($line);
      &check_point();
      $main::st_int[$main::TODO]--;
    }

    # Move queues around, and try again, but only if there are still
    # things to do
    if ($main::st_int[$main::TODO]) {
      print STDERR "*** Moving queues around, $main::st_int[$main::TODO] to do\n" 
	if $main::opt_verbose;
      close CURRENT;
      close QUEUE;

      # TODO: should check whether these succeed
      unlink($main::cur_queue);
      rename($main::new_queue, $main::cur_queue);
    
      open(CURRENT, "$main::cur_queue") 
	|| die "$0: Unable to open $main::cur_queue for reading: $!\n";
      open(QUEUE, ">$main::new_queue") 
	|| die "$0: Unable to open $main::new_queue for writing: $!\n";

      # This should not happen, but it might anyway,and we don't want
      # to loop forever.
      $main::st_int[$main::TODO] = 0 if -z $main::cur_queue;
    }
  }
  close CURRENT;
  close QUEUE;
  close EXTERNAL;
}

sub handle_url {
  my ($line) = @_;
  my ($urlstr, $urlparent) = split(/\|/, $line);
  my $reqtype;
  my $response;
  my $type;

  # Add this URL to the ones we've seen already, return 
  # if it is a duplicate
  return if &add_checked($urlstr);

  my $url = new URI::URL $urlstr;
  $main::st_int[$main::LINKS]++;
	
  if (defined($url->scheme) 
      && $url->scheme =~ /^(http|file|ftp|gopher|nntp)$/o
      && $url->path !~ /$main::file/
      && $url->path !~ /[=\?]/o ) {
    if ($url->path =~ /\/$/o || $url->path eq "") {
      $type = 'text/html';
    } else {
      $type = guess_media_type($url->path);
    }

    # If we are unsure about the type it could well be a special extension
    # for e.g. on-the-fly HTML, or a script or some such. Should ask the
    # server.
    if ($type eq 'application/octet-stream') {
      $response = performRequest('HEAD', $url, $urlparent, $type);
      $type = $response->content_type;
    }

    if ($type =~ /html/o 
        && $url->scheme =~ /^(http|file|ftp|gopher)$/o
        && (!defined $main::opt_exclude || $url !~ /$main::opt_exclude/o)) {
      $reqtype = 'GET';
    } else {
      $reqtype = 'HEAD';
    }

    $response = performRequest($reqtype, $url, $urlparent, $type)
      unless defined($response) and $reqtype eq 'HEAD';

    if ($response->is_success) {
      sleep($main::opt_sleep) unless $main::opt_debug || $url->scheme eq 'file';

      # If this url moves off of this site then return now
      if ($url !~ /$main::opt_match/o 
	  || (defined $main::opt_exclude && $url =~ /$main::opt_exclude/o)) {
	print STDERR " Exclude $url\n" if $main::opt_verbose;
      } else {
	&handle_doc($response) if $reqtype eq 'GET';
      }
    } else {
      if (defined $main::opt_ignore && $url =~ /$main::opt_ignore/o) {
	print STDERR "Ignore  $url\n" if $main::opt_verbose;
      } else {
	print STDERR "         ", $response->code, ' ', $response->message, "\n" 
	  if $main::opt_verbose;
        push @{$problems{$response->code}{$url}}, $response unless $response->code =~ /$main::opt_dontwarn/o;
	$main::st_int[$main::PROBL]++;
      }

      if ($response->is_redirect) {
	if ($response->code == 300) {  # multiple choices, but no redirection available
	  print STDERR "        Multiple choices.\n" if $main::opt_verbose;
	} else {
	  my $baseURI = URI->new($url);
	  my $redir_url = URI->new_abs($response->header('Location'), $baseURI);
	  print STDERR "         Redirected to " . $redir_url . "\n" if $main::opt_verbose;
	  
	  add_to_queue($redir_url, $urlparent);
	}
      }
    }

    # Done with this URL
  } else {
    # not interested in other URLs right now
    print STDERR "  Ignore $url\n" if $main::opt_verbose;
  }
}

sub performRequest {
  my ($reqtype, $url, $urlparent, $type) = @_;

  # Output what we are going to do with this link
  printf STDERR "    %4s %s (%s)\n", $reqtype, $url, $type
    if $main::opt_verbose;
	
  my $ref_header = new HTTP::Headers 'Referer' => $urlparent;
  my $request = new HTTP::Request($reqtype, $url, $ref_header);
  my $response = $main::ua->simple_request($request);

  return $response;
}

sub check_external {
  my $newurl;
  my $urlparent;
  my $prevurl = "";
  my $reqtype;

  # Add a proxy to the user agent, if defined
  $main::ua->proxy(['http', 'ftp'], $main::opt_proxy) 
    if defined($main::opt_proxy);

  # I'll just read in all external URLs in an array, sort them, and
  # then remove duplicates and tally them. This improves over the old
  # situation because we don't rely on sort and wc being there, and
  # the tally will actually be correct. Drawback: we might get into
  # memory problems more easily. Oh well, buy more, I suppose.

  print STDERR "*** Reading and sorting external URLs\n" 
    if $main::opt_verbose;;
  open EXTERNAL, $main::extfile
    or die "$0: Unable to open $main::extfile for reading: $!\n";
  # Gobble!
  my @externals = sort <EXTERNAL>;

  close EXTERNAL;

  $main::st_ext[$main::TODO] = $#externals;
  $main::st_ext[$main::DUPS] = $main::st_ext[$main::LINKS] - $main::st_ext[$main::TODO];

  print STDERR "*** Checking $main::st_ext[$main::TODO] external links\n"
    if $main::opt_verbose;
  # We know that our list is sorted, but the same URL
  # can exist several types, once for each parent
  # For now we just look at the first url/parent pair, but
  # ideally we should list this for each pair (i.e. for
  # each page on which the link occurs.
  foreach (@externals) {
    ($newurl, $urlparent) = split(/\|/);
    $main::st_ext[$main::TODO]--;

    next if $prevurl eq $newurl;
    $prevurl = $newurl;
    
    my $url = new URI::URL $newurl, $urlparent;

    if ($url->scheme =~ /^(http|ftp|gopher|nntp)$/o) { 

      # Normally, we would only need to do a HEAD, but given the way
      # LWP handles gopher requests, we need to do a GET on those to
      # get at least a 500 and 501 error. We would need to parse the
      # document returned by LWP to find out if we had problems
      # finding the file. -- Patch by Bruce Speyer
      # <bspeyer@texas-one.org>

      # We also need to do GET instead of HEAD if we know the remote server
      # won't accept it.  The standard way for an HTTP server to indicate
      # this is by returning a 405 ("Method Not Allowed") or 501 ("Not
      # Implemented").  Other circumstances may also require sending GETs
      # instead of HEADs to a server.  Details are documented below.
      # -- Larry Gilbert <larry@n2h2.com>

      my ($reqtype, $ref_header, $request, $response);

      foreach $reqtype ('HEAD', 'GET') {
        # Under normal circumstances, we will go through this loop only once
        # and thus make a single HEAD request.

        # If we already know a HEAD won't work, skip it and do GET
        next if $reqtype eq 'HEAD' && ($url->scheme =~ /^gopher$/o ||
         $main::servers_get_only{$url->netloc} );

        print STDERR "     $reqtype ", $url->abs, "\n" if $main::opt_verbose;
        $ref_header = new HTTP::Headers 'Referer' => $urlparent;
        $request = new HTTP::Request($reqtype, $url, $ref_header);
        $response = $main::ua->simple_request($request);

        if ($reqtype eq 'HEAD') {

          # 405 and 501 are standard indications that HEAD shouldn't be used
          if ($response->code =~ /^(405|501)$/o) {
            print STDERR "Server doesn't like HEAD requests; retrying\n"
             if $main::opt_verbose;
            $main::servers_get_only{$url->netloc}++;
            next;
          }

          # Microsoft IIS has been seen dropping the connection prematurely
          # when it should be returning 405 instead
          elsif ($response->status_line =~ /^500 unexpected EOF/o) {
            print STDERR "Server hung up on HEAD request; retrying\n"
             if $main::opt_verbose;
            $main::servers_get_only{$url->netloc}++;
            next;
          }

          # Netscape Enterprise has been seen returning 500 and even 404
          # (yes, 404!!) in response to HEAD requests
          elsif ($response->server =~ /^Netscape-Enterprise/o &&
           $response->code =~ /^(404|500)$/o) {
            print STDERR "Unreliable response to HEAD request; retrying\n"
             if $main::opt_verbose;
            $main::servers_get_only{$url->netloc}++;
            next;
          }

          # If a HEAD request resulted in nothing noteworthy, no need for
          # any further attempts
          else { last; }
        }
      }

      if ($response->is_error || $response->is_redirect) {
	if (defined $main::opt_ignore && $url =~ /$main::opt_ignore/o) {
	  print STDERR "Ignore  $url error\n";
	} else {
	  printf STDERR "          %d (%s)\n", $response->code, 
	  $response->message
	    if $main::opt_verbose;
          push @{$problems{$response->code}{$url}}, $response unless $response->code =~ /$main::opt_dontwarn/o;
	  $main::st_ext[$main::PROBL]++;
	}
      }
    }
    &check_point();
  }
}


# This routine creates a (temporary) WWW page based on the current
# findings This allows somebody to monitor the process, but is also
# convenient when this program crashes or waits because of diskspace
# or memory problems

sub create_page {
    my($final_page) = @_;

    my $path = "";
    my $prevpath = "";
    my $prevcode = 0;
    my $prevmessage = "";

    print STDERR "*** Start writing results page\n" if $main::opt_verbose;

    open(OUT, ">$main::file.new") 
	|| die "$0: Unable to open $main::file.bak for writing:\n";
    print OUT "<head>\n";
    if (!$final_page) {
      printf OUT "<META HTTP-EQUIV=\"Refresh\" CONTENT = %d>\n",
      int($main::cp_int * 60 / 2 - 5);
    }

    print OUT "<title>Checkbot report</title></head>\n";
    print OUT "<h1><em>Checkbot</em>: main report</h1>\n";

    # Show the status of this checkbot session
    print OUT "<table><tr><th>Status:</th><td>";
    if ($final_page) {
      print OUT "Done.\n"
    } else {
      print OUT "Running since $main::start_time.<br>\n";
      print OUT "Last update at ". localtime() . ".<br>\n";
      print OUT "Next update in <b>", int($main::cp_int), "</b> minutes.\n";
    }
    print OUT "</td></tr></table>\n\n";

    # Summary (very brief overview of key statistics)
    print OUT "<hr><h2>Report summary</h2>\n";

    print OUT "<table>\n";
    print OUT "<tr> <td> </td> <th>Total<br>links</th> <th>Links<br>To Do</th>";
    print OUT "<th>Unique</br>links</th> <th>Problem<br>links</th> ";
    print OUT "<th>Ratio</th> </tr>\n";

    if ($main::st_int[$main::LINKS]) {
    print OUT "<tr> <th>Internal</th>";
    printf OUT "<td align=right>%d</td> <td align=right>%d</td> <td align=right>%d</td> <td align=right>%d</td> <td align=right>%d%%</td> </tr>\n",
    $main::st_int[$main::LINKS] + $main::st_int[$main::DUPS],
    $main::st_int[$main::TODO],
    $main::st_int[$main::LINKS], $main::st_int[$main::PROBL],
    $main::st_int[$main::PROBL] / $main::st_int[$main::LINKS] * 100;
    }

  if ($main::st_ext[$main::LINKS]) {
    print OUT "<tr> <th>External</th>";
    printf OUT "<td align=right>%d</td> <td align=right>%d</td> <td align=right>%d</td> <td align=right>%d</td> <td align=right>%d%%</td> </tr>\n",
    $main::st_ext[$main::LINKS] + $main::st_ext[$main::DUPS],
    $main::st_ext[$main::TODO],
    $main::st_ext[$main::LINKS], $main::st_ext[$main::PROBL],
    $main::st_ext[$main::PROBL] / $main::st_ext[$main::LINKS] * 100;
  }

    print OUT "</table>\n\n";
    
    # Server information
    printAllServers($final_page);

    # Checkbot session parameters
    print OUT "<hr><h2>Checkbot session parameters</h2>\n";
    print OUT "<table>\n";
    print OUT "<tr><th align=left>--url</th><td>Start URL(s)</td><td>",
              join(',', @starturls), "</td></tr>\n";
    print OUT "<tr><th align=left>--match</th><td>Match regular expression</td><td>$main::opt_match</td></tr>\n";
    print OUT "<tr><th align=left>--exclude</th><td>Exclude regular expression</td><td>$main::opt_exclude</td></tr>\n" if defined $main::opt_exclude;
    print OUT "<tr><th align=left>--ignore</th><td>Ignore regular expression</td><td>$main::opt_ignore</td></tr>\n" if defined $main::opt_ignore;
    
    print OUT "</table>\n";

    # Statistics for types of links

    print OUT signature();

    close(OUT);

    rename($main::file, $main::file . ".bak");
    rename($main::file . ".new", $main::file);

    print STDERR "*** Done writing result page\n" if $main::opt_verbose;
}

# Create a list of all the servers, and create the corresponding table
# and subpages. We use the servers overview for this. This can result
# in strange effects when the same server (e.g. IP address) has
# several names, because several entries will appear. However, when
# using the IP address there are also a number of tricky situations,
# e.g. with virtual hosting. Given that likely the servers have
# different names for a reasons, I think it is better to have
# duplicate entries in some cases, instead of working off of the IP
# addresses.

sub printAllServers {
  my ($finalPage) = @_;

  my $server;
  print OUT "<hr><h2>Overview per server</h2>\n";
  print OUT "<table> <tr> <th>Server</th><th>Server<br>Type</th><th>Unique<br>links</th><th>Problem<br>links</th><th>Ratio</th></tr>\n";

  foreach $server (sort keys %main::servers) {
    print_server($server, $finalPage);
  }
  print OUT "</table>\n\n";
}

sub get_server_type {
  my($server) = @_;

  my $result;

  if ( ! defined($main::server_type{$server})) {
    if ($server eq 'localhost') {
      $result = 'Direct access through filesystem';
    } else {
      my $request = new HTTP::Request('HEAD', "http://$server/");
      my $response = $main::ua->simple_request($request);
      $result = $response->header('Server');
    }
    $result = "Unknown server type" if $result eq "";
    print STDERR "=== Server $server is a $result\n" if $main::opt_verbose;
    $main::server_type{$server} = $result;
  }
  $main::server_type{$server};
}

sub add_checked {
  my($urlstr) = @_;
  my $item;
  my $result = 0;

  # Substitute hostname with IP-address. This keeps us from checking 
  # the same pages for each name of the server, wasting time & resources.
  my $url = URI->new($urlstr);

  # TODO: This should be fixed in a more sane way. Really the URI
  # class should deal with stuff like this. Checkbot can't be expected
  # to know which URI schemes do have a host component and which types
  # don't.
  $url->host(ip_address($url->host)) if $url->scheme =~ /^(http|ftp|gopher|https|ldap|news|nntp|pop|rlogin|snews|telnet)$/;
  $urlstr = $url->as_string;

  if (defined $main::checked{$urlstr}) {
    $result = 1;
    $main::st_int[$main::DUPS]++;
    $main::checked{$urlstr}++;
  } else {
    $main::checked{$urlstr} = 1;
  }

  return $result;
}

# Parse document, and get the links
sub handle_doc {
  my ($response) = @_;
  my ($doc_new, $doc_dup, $doc_ext) = (0, 0, 0);

  # TODO: we are making an assumption here that the $reponse->base is
  # valid, which might not always be true! This needs to be fixed, but
  # first let's try to find out why this stuff is sometimes not
  # valid...

  # When we received the document we can add a notch to its server
  $main::servers{$response->base->netloc}++;

  my $p = HTML::LinkExtor->new(undef, $response->base);
  $p->parse($response->content);
  $p->eof;

  # Parse the links we found in this document
  my @links = $p->links();
  foreach (@links) {
    my ($tag, %l) = @{$_};
    foreach (keys %l) {
      # Get the canonical URL, so we don't need to worry about base, case, etc.
      my $url = $l{$_}->canonical;

      # Remove fragments, if any
      $url->fragment(undef);

      # Check whether URL has fully-qualified hostname
      if ($url->scheme =~ /^(http|ftp)/) {
        if (! defined $url->host) {
          print STDERR "--> No host name found in URL: $url\n" if $main::opt_verbose;
          $warning{'No host name found in URL'}{$url} .= $url . "\n";
          next;
        } elsif ($url->host !~ /\./) {
          print STDERR "--> Unqualified host name: $url\n" if $main::opt_verbose;
          $warning{'Unqualified host name in URL'}{$url} .= $url . "\n";
        }
      }

      if ($url =~ /$main::opt_match/o) {
	if (defined $main::checked{$url}) {
	  $doc_dup++;
	} else {
	  add_to_queue($url, $response->base);
	  $doc_new++;
	}
      } else {
	# Add this as an external link if we can check the protocol later
	if ($url =~ /^(http|ftp):/o) {
	  print EXTERNAL $url . "|" . $response->base . "\n";
	  $doc_ext++;
	}
      }
    }
  }
  $main::st_int[$main::DUPS] += $doc_dup;
  $main::st_ext[$main::LINKS] += $doc_ext;
  $main::st_ext[$main::TODO] += $doc_ext;
  if ($main::opt_verbose) {
    my @string = ();
    push(@string, "$doc_new new") if $doc_new > 0;
    push(@string, "$doc_dup dup") if $doc_dup > 0;
    push(@string, "$doc_ext ext") if $doc_ext > 0;
    printf STDERR "         (%s)\n", join(',', @string) if $#string > 0;
  }
}

sub add_to_queue {
  my ($url, $parent) = @_;

  print QUEUE $url . '|' . $parent . "\n";
  $main::st_int[$main::TODO]++;
}

sub print_server {
  my($server, $final_page) = @_;

  my $host = $server;
  $host =~ s/(.*):\d+/$1/;

  print STDERR "    Writing server $server (really ", ip_address($host), ")\n" if $main::opt_verbose;

  my $server_problem = &count_problems($server);
  my $filename = "$main::server_prefix-$server.html";
  $filename =~ s/:/-/o;

  print OUT "<tr> <td>";
  print OUT "<a href=\"$filename\">" if $server_problem > 0;
  print OUT "$server";
  print OUT "</a>" if $server_problem > 0;
  print OUT "</td>";
  print OUT "<td>" . &get_server_type($server) . "</td>";
  printf OUT "<td align=right>%d</td> <td align=right>%d</td>",
  $main::servers{$server} + $server_problem,
  $server_problem;
  my $ratio = $server_problem / ($main::servers{$server} + $server_problem) * 100;
  print OUT "<td align=right>";
  print OUT "<b>" unless $ratio < 0.5;
  printf OUT "%4d%%", $ratio;
  print OUT "</b>" unless $ratio < 0.5;
  print OUT "</td>";
  print OUT "</tr>\n";

  # Create this server file
  open(SERVER, ">$filename")
    || die "Unable to open server file $filename for writing: $!";
  print SERVER "<head>\n";
  if (!$final_page) {
    printf SERVER "<META HTTP-EQUIV=\"Refresh\" CONTENT = %d>\n",
      int($main::cp_int * 60 / 2 - 5);
  }
  print SERVER "<title>Checkbot: output for server $server</title></head>\n";
  print SERVER "<body><h2><em>Checkbot</em>: report for server <tt>$server</tt></h2>\n";
  print SERVER "Go To: <a href=\"$main::file\">Main report page</a>.\n";
  print SERVER "<hr>\n";

  printServerProblems($server, $final_page);

  print SERVER "<hr>\n";
  printServerWarnings($server, $final_page);

  print SERVER "\n";
  print SERVER signature();

  close SERVER;
}

# Return a string containing Checkbot's signature for HTML pages
sub signature {
  return "<hr>\nPage created by <a href=\"http://degraaff.org/checkbot/\">Checkbot $VERSION</a> on <em>" . localtime() . "</em>.\n</body></html>";
}

# Loop through all possible problems, select relevant ones for this server
# and display them in a meaningful way.
sub printServerProblems {
  my ($server) = @_;

  foreach my $code (sort keys %problems) {
    my $codeOutput = '';
    my %thisServerList = ();

    foreach my $url (sort keys %{ $problems{$code}}) {

      foreach my $response (@{ $problems{$code}{$url} }) {
	my $parent = $response->request->header('Referer');
	next if $parent !~ $server;

	chomp $parent;
	$thisServerList{$parent}{$url} = $response;
      }
    }
      
    foreach my $parent (sort keys %thisServerList) {
      my $urlOutput = '';
      foreach my $url (sort keys %{ $thisServerList{$parent} }) {
	my $response = $thisServerList{$parent}{$url};
	$urlOutput .= "<li><a href=\"$url\">$url</a><br>\n";
	$urlOutput .= $response->message . "\n" if $response->message ne status_message($code);
      }
      if ($urlOutput ne '') {
	$codeOutput .= "<dt><a href=\"$parent\">$parent</a>\n<dd>\n";
	$codeOutput .= "<ul>\n$urlOutput\n</ul>\n\n";
      }
    }

    if ($codeOutput ne '') {
      print SERVER "<h4>$code ", status_message($code), "</h4>\n";
      print SERVER "<dl>\n$codeOutput\n</dl>\n";
    }
  }

}

sub printServerWarnings {
  my ($server,$finalPage) = @_;

  my $warningType;
  my $oldWarningType = '';
  my $url;
  my $parent;

  foreach $warningType (sort keys %warning) {
    print SERVER "<h4>$warningType</h4>\n<dl>\n" unless $oldWarningType eq $warningType;
    $oldWarningType = $warningType;
    my %thisServerList = ();

    foreach $url (sort keys %{$warning{$warningType}}) {
      # Get only those parent URLs that match this server
      my @parents = grep(/$server/, split(/\n/, $warning{$warningType}{$url}));
      if ($#parents >= 0) {
	foreach my $parent (@parents) {
	  $thisServerList{$parent}{$url} = 1;
	}
      }
    }

    foreach my $parent (sort keys %thisServerList) {
      print SERVER "<dt><a href=\"$parent\">$parent</a>\n<dd>\n";
      foreach my $url (sort keys %{ $thisServerList{$parent} }) {
	print SERVER "<a href=\"$url\">$url</a><br>";
      }
    }
    print SERVER "</dl>\n";
  }
}

sub check_point {
    if ( ($main::cp_last + 60 * $main::cp_int < time()) 
	 || ($main::opt_debug && $main::opt_verbose)) {
	&create_page(0);
	$main::cp_last = time();
	$main::cp_int = $main::cp_int * 1.25 unless $main::opt_debug;
        $main::cp_int = $main::cp_int > $main::opt_interval ? $main::opt_interval : $main::cp_int;
    }
}

sub send_mail {
  my $msg = new Mail::Send;

  $msg->to($main::opt_mailto);
  $msg->subject("Checkbot results for $main::opt_url available.");

  my $fh = $msg->open;

  print $fh "Checkbot results for $main::opt_url are available.\n\n";
  print $fh "User-supplied note: $main::opt_note\n\n"
    if defined $main::opt_note;

  print $fh "A brief summary of the results follows:\n\n";
  printf $fh "Internal: %6d total, %6d unique, %6d problems, ratio = %3d%%\n",
  $main::st_int[$main::LINKS] + $main::st_int[$main::DUPS],
  $main::st_int[$main::LINKS], $main::st_int[$main::PROBL],
  $main::st_int[$main::PROBL] / $main::st_int[$main::LINKS] * 100;
  if ($main::st_ext[$main::LINKS] > 0) {
    printf $fh "External: %6d total, %6d unique, %6d problems, ratio = %3d%%\n",
    $main::st_ext[$main::LINKS] + $main::st_ext[$main::DUPS],
    $main::st_ext[$main::LINKS], $main::st_ext[$main::PROBL],
    $main::st_ext[$main::PROBL] / $main::st_ext[$main::LINKS] * 100;
  }

  print $fh "\n\n-- \nCheckbot $VERSION\n";
  print $fh "<URL:http://degraaff.org/checkbot/>\n";

  $fh->close;
}

sub print_help {
  print "Checkbot $VERSION command line options:\n\n";
  print "  --debug            Debugging mode: No pauses, stop after 25 links.\n";
  print "  --verbose          Verbose mode: display many messages about progress.\n";
  print "  --url url          Start URL\n";
  print "  --match match      Check pages only if URL matches `match'\n";
  print "                     If no match is given, the start URL is used as a match\n";
  print "  --exclude exclude  Exclude pages if the URL matches 'exclude'\n";
  print "  --ignore ignore    Do not list error messages for pages that the\n";
  print "                     URL matches 'ignore'\n";
  print "  --file file        Write results to file, default is checkbot.html\n";
  print "  --mailto address   Mail brief synopsis to address when done.\n";
  print "  --note note        Include Note (e.g. URL to report) along with Mail message.\n";
  print "  --proxy URL        URL of proxy server for external http and ftp requests.\n";
  print "  --internal-only    Only check internal links, skip checking external links.\n";
  print "  --sleep seconds    Sleep for secs seconds between requests (default 2)\n";
  print "  --timeout seconds  Timeout for http requests in seconds (default 120)\n";
  print "  --interval seconds Maximum time interval between updates (default 10800)\n";
  print "  --dontwarn codes   Do not write warnings for these HTTP response codes\n";
  print "\n";
  print "Options --match, --exclude, and --ignore can take a perl regular expression\nas their argument\n\n";
  print "Use 'perldoc checkbot' for more verbose documentation.\n\n";
  print "Checkbot WWW page     : http://degraaff.org/checkbot/\n";
  print "Mail bugs and problems: checkbot\@degraaff.org\n";
    
  exit 0;
}

sub ip_address {
  my($host) = @_;

  return $main::ip_cache{$host} if defined $main::ip_cache{$host};

  my($name,$aliases,$adrtype,$length,@addrs) = gethostbyname($host);
  if (defined $addrs[0]) {
    my($n1,$n2,$n3,$n4) = unpack ('C4',$addrs[0]);
    $main::ip_cache{$host} = "$n1.$n2.$n3.$n4";
  } else {
    # Whee! No IP-address found for this host. Just keep whatever we
    # got for the host. If this really is some kind of error it will
    # be found later on.
    $main::ip_cache{$host} = $host;
   }
}

sub count_problems {
  my ($server) = @_;
  my $count = 0;

  foreach my $code (sort keys %problems) {
    foreach my $url (sort keys %{ $problems{$code}}) {
      foreach my $response (@{ $problems{$code}{$url} }) {
	my $parent = new URI::URL $response->request->header('Referer');
	$count++ if $parent =~ $server;
      }
    }
  }

  return $count;
}


# $Log: checkbot.pl,v $
# Revision 1.61  2000/06/29 19:56:48  graaff
# Updated Makefile.PL
# Use GET instead of HEAD for confused servers.
# Update email and web address.
#
# Revision 1.60  2000/04/30 13:34:32  graaff
# Add option --dontwarn to avoid listing certain HTTP responses. Deal
# with 300 Multiple Choices HTTP Response. Fix warning with
# --internal-only option and add message when used. Use MacPerl stuff to
# get command line options on a Mac. Check whether URLs on command line
# have a proper host.
#
# Revision 1.59  2000/01/30 20:23:32  graaff
# --internal-only option, hide some warnings when not running verbose,
# and fixed a warning.
#
# Revision 1.58  2000/01/02 15:39:59  graaff
# Deal with hostnameless URIs, use TMPDIR where available, and work
# nicely with the new HTML::LinkExtor.
#
# Revision 1.57  1999/10/24 16:11:00  graaff
# Added URI check.
#
# Revision 1.56  1999/07/31 14:52:17  graaff
# Fixed redirection URL's, deal with new URI way of handling
# hostname-less URI's.
#
# Revision 1.55  1999/05/09 15:30:34  graaff
# List broken links under the pages that contain them, instead of the
# other way around, reverting back to the way things are in 1.53 and
# earlier.
# Handle redirected, but unqualified links.
# Only print each warning header once.
# Documentation fixes.
#
# Revision 1.54  1999/01/18 22:22:29  graaff
# Fixed counting of problem links to correct checkbot.html results page.
#
# Revision 1.53  1999/01/17 20:59:14  graaff
# Fixed internal problem storage.
# Changed report to collate HTTP response codes.
# Added warning section to pages with additional warnings.
# Hammered out bug with record separator in perl 5.005.
#
# Revision 1.52  1998/10/10 08:41:50  graaff
# new version, some documentation work, and the HTML::Parse problem fixed.
#
# Revision 1.51  1997/09/06 14:01:58  graaff
# per 5.004 changes and address changes
#
# Revision 1.50  1997/04/28 07:10:26  graaff
# Fixed small problem with VERSION
#
# Revision 1.49  1997/04/27 19:24:22  graaff
# A bunch of smaller stuff
#
# Revision 1.48  1997/04/05 15:28:35  graaff
# Small fixes
#
# Revision 1.47  1997/01/28 13:48:00  graaff
# Protect against corrupted todo link count
#
# Revision 1.46  1996/12/30 15:27:11  graaff
# Several bugs fixed and features added, see changelog
#
# Revision 1.45  1996/12/24 13:59:15  graaff
# Deal with IP address not found.
#
# Revision 1.44  1996/12/11 16:16:07  graaff
# Proxy support, small bugs fixed.
#
# Revision 1.43  1996/12/05 12:35:41  graaff
# Checked URLs indexed with IP address, small changes to layout etc.
#
# Revision 1.42  1996/11/04 13:21:07  graaff
# Fixed several small problems. See ChangeLog.
#
# Revision 1.41  1996/10/04 15:15:35  graaff
# use long option names now
#
# Revision 1.40  1996/09/28 08:18:14  graaff
# updated, see ChangeLog
#
# Revision 1.39  1996/09/25 13:25:48  graaff
# update rev
#
# Revision 1.4  1996/09/25 12:53:04  graaff
# Moved checkbot back to checkbot.pl so that we can substitute some
# variables upon installation.
#
# Revision 1.37  1996/09/12 13:12:05  graaff
# Updates, and checkbot now requires LWP 5.02, which fixes some bugs.
#
# Revision 1.36  1996/09/05 14:13:58  graaff
# Mainly documentation fixes. Also fixed comparison.
#
# Revision 1.35  1996/09/01 19:39:24  graaff
# Small stuff. See Changelog.
#
# Revision 1.34  1996/08/07 08:10:18  graaff
# Stupid bug in parsing the LinkExtor output fixed.
#
# Revision 1.33  1996/08/05 06:47:43  graaff
# Fixed silly bug in calculation of percentage for each server.
#
# Revision 1.32  1996/08/02 21:51:18  graaff
# Use the new LinkExtor to retrieve links from a document. Uses less
# memory, and should be quicker.
#
# Revision 1.31  1996/08/02 21:38:39  graaff
# Added a number of patches by Bruce Speyer.
# Added POD documentation.
# Added summary to mail message.
#
# Revision 1.30  1996/08/02 11:11:09  graaff
# See ChangeLog
#
# Revision 1.29  1996/07/27 20:28:35  graaff
# See Changelog
#
# Revision 1.28  1996/07/23 12:32:09  graaff
# See ChangeLog
#
# Revision 1.27  1996/07/22 20:34:44  graaff
# Fixed silly bug in columns printf
#
# Revision 1.26  1996/06/22 12:52:57  graaff
# redirection, optimization, correct base url
#
# Revision 1.25  1996/06/20 14:13:52  graaff
# Major rewrite of initialization. Fixed todo links indicators.
#
# Revision 1.24  1996/06/19 15:49:38  graaff
# added -M option, fixed division by 0 bug
#
# Revision 1.23  1996/06/01 17:33:40  graaff
# lwp-win32 changes, and counting cleanup
#
# Revision 1.22  1996/05/29 18:36:37  graaff
# Fixed error in regexp, small bugs
#
# Revision 1.21  1996/05/26 08:06:13  graaff
# Possibly add ending slash to URL's
#
# Revision 1.20  1996/05/13 17:01:17  graaff
# hide messages behind verbose flag
#
# Revision 1.19  1996/05/13 13:05:53  graaff
# See ChangeLog
#
# Revision 1.18  1996/05/05 07:25:38  graaff
# see changelog
#
# Revision 1.17  1996/04/29 16:23:11  graaff
# Updated, see Changelog for details.
#
# Revision 1.16  1996/04/29 06:43:57  graaff
# Updated
#
# Revision 1.15  1996/04/28 19:42:11  graaff
# See Changelog
#
# Revision 1.14  1996/03/29 10:09:36  graaff
# See ChangeLog
#
# Revision 1.13  1996/03/24 19:16:23  graaff
# See Changelog
#
# Revision 1.12  1996/03/22 13:10:03  graaff
# *** empty log message ***
#
# Revision 1.11  1996/03/17 09:33:26  graaff
# See ChangeLog
#
# Revision 1.10  1996/02/27 09:05:22  graaff
# See ChangeLog
#
# Revision 1.9  1996/02/26 14:47:31  graaff
# Fixed bug with referer field, added -x option to help, make server
# page auto-refresh.
#
# Revision 1.8  1996/02/24 12:14:48  graaff
# Added -x option
#
# Revision 1.7  1995/12/08 12:44:33  graaff
# Major rewrite of internals
# Changed the way the checked links are kept
#
# Revision 1.6  1995/11/29 07:52:10  graaff
# Small fixes to verbose layout.
#
# Revision 1.5  1995/11/27 08:50:46  graaff
# stupid bug in calling sort
#
# Revision 1.4  1995/11/24 15:48:34  graaff
# Fixed numerous small problems, mostly in the output.
# Fixed checking of external links (each link now gets checked only once)
# Sorting of errors is now done by error code, by error text, by page.
#
# Revision 1.3  1995/11/22 09:51:58  graaff
# Last part of major revision towards Perl 5 and libwww5. Checkbot now
# seems to work again, and at least generates the proper reports.
# However, more work, in particular cleanups, is needed.
#
# Revision 1.2  1995/08/25 11:28:57  graaff
# First rewrite towards perl 5, most stuff done in a crude way.
#
# Revision 1.1  1995/08/25 09:16:29  graaff
# First version is identical to the perl4 version. I will change it
# gradually.
#
!NO!SUBS!
