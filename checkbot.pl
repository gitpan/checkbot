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
#
# checkbot - A perl5 script to check validity of links in www document trees
#
# Hans de Graaff <j.j.degraaff@twi.tudelft.nl>, 1994-1996.
# Based on Dimitri Tischenko, Delft University of Technology, 1994
# Based on the testlinks script by Roy Fielding
# With contributions from Bruce Speyer <bruce.speyer@elecomm.com>
#
# Info-URL: http://dutifp.twi.tudelft.nl:8000/checkbot/
#
# $Id: checkbot.pl,v 1.39 1996/09/25 13:25:48 graaff Exp $
# (Log information can be found at the end of the script)

require 5.001;
use strict;

require LWP;
LWP->require_version(5.02);

=head1 NAME

Checkbot - WWW Link Verifier

=head1 SYNOPSIS

checkbot [B<-dhv>] [B<-u> <start URL>] [B<-m> <match string>] [B<-x> <exclude string>] 
         [B<-z> <ignore string>] [B<-f> <file name>] [B<-M> <email address>]
         [B<-N> <note>] [B<-s> <seconds>] [B<-t> <timeout>]

=head1 DESCRIPTION

Checkbot verifies the links in a specific portion of the World Wide
Web. It creates HTML pages with diagnostics.

Checkbot's options are:

=over 4

=item -u <start URL>

Set the start URL. Checkbot starts checking at this URL, and then
recursively checks alls links found on the page.

=item -m <match string>

This option selects which pages Checkbot considers local. If the
I<match string> is contained within the URL, then Checkbot considers
the page local, retrieves it, and will check all the links contained
on it. Otherwise the page is considered external and it is only
checked with a HEAD request.

If no explicit I<match string> is given, the start URL (See option
C<-u>) will be used as a match string instead.

The I<match string> can be a perl regular expression.

=item -x <exclude string>

URLs matching the I<exclude string> are considered to be external,
even if they happen to match the I<match string> (See option C<-m>).

The I<exclude string> can be a perl regular expression.

=item -z <ignore string>

If a URL has an error, and matches the I<ignore string>, its error
will not be listed. This can be useful to stop certain errors from
being listed.

The I<ignore string> can be a perl regular expression.

=item -M <email address>

Send mail to the I<email address> when Checkbot is done
checking. Includes a small summary of the results.

=item -N <note>

The I<note> is included verbatim in the mail message (See option
C<-M>). This can be useful to include the URL of the summary HTML page
for easy reference, for instance.

Only meaningful in combination with the C<-M> option.

=item -h 

Shows brief help message on the standard output.

=item -v 

Show verbose output while running. Includes all links checked, results
from the checks, etc.

=item -d 

Enable debugging mode. Not really supported anymore.

=item -s <seconds>

Number of I<seconds> to sleep in between requests. Default is 2 seconds. 

=item -t <timeout>

Default timeout for the requests, specified in seconds. The default is
2 minutes.

=item -f <file name>

Write the summary pages into file I<file name>. Default is C<checkbot.html>.

=back

=head1 AUTHOR

Hans de Graaff <J.J.deGraaff@twi.tudelft.nl>

=cut

# Prepare the use of DBM files, and show our preferences
use AnyDBM_File;
@AnyDBM_File::ISA = qw(DB_File GDBM_File NDBM_File);

# Version information
($main::VERSION) = sprintf("%d.%02d", q$Revision: 1.39 $ =~ /(\d+)\.(\d+)/);

&check_options();
&init_modules();
&init_globals();
&setup();

# Start actual application
&check_internal();

# Empty checked array to clear up memory
undef %main::checked;
%main::checked = ();

&check_external();

&create_page(1);
&send_mail if defined $main::opt_M;

&clean_up();

exit 0;

### Initialization and setup routines

sub check_options {

  # Get command-line arguments
  use Getopt::Std;
  getopts('dhvu:m:x:f:s:t:M:N:z:');

  # Handle arguments, some are mandatory, some have defaults
  &print_help if ($main::opt_h && $main::opt_h) || !$main::opt_u;
  $main::opt_t = 120 unless defined($main::opt_t) && length($main::opt_t);
  $main::opt_v = 0 unless $main::opt_v;
  $main::opt_s = 2 unless defined($main::opt_s) && length($main::opt_s);
  $main::opt_m = $main::opt_u unless defined $main::opt_m;

  # Work on the regular expressions in -m and -x: escape all 
  # regular expression characters
  $main::opt_x =~ s/([\.\/\\\+\?\~\@])/\\$1/g if defined($main::opt_x);
  $main::opt_z =~ s/([\.\/\\\+\?\~\@])/\\$1/g if defined($main::opt_z);
  $main::opt_m =~ s/([\.\/\\\+\?\~\@])/\\$1/g if defined($main::opt_m);

  # Display messages about the options
  print STDERR "*** Starting in verbose mode\n" if $main::opt_v;

}

sub init_modules {

  # Prepare the user agent to be used:
  use LWP::UserAgent;
  use LWP::MediaTypes;
  use HTML::Parse;
  use HTML::LinkExtor;
  $main::ua = new LWP::UserAgent;
  $main::ua->agent("Checkbot/$main::VERSION LWP/" . LWP::Version);
  $main::ua->timeout($main::opt_t);

  # Don't use strict parsing, it is very likely we will
  # encounter invalid HTML documents on the way.
  URI::URL::strict(0);

  require Mail::Send if defined $main::opt_M;
}

sub init_globals {

  # Remember start time
  $main::start_time = localtime();

  # Directory and files for output
  if ($main::opt_f) {
    $main::file = $main::opt_f;
    $main::file =~ /([^\.]+)\./;
    $main::server_prefix = $1;
  } else { 
    $main::file = "checkbot.html";
    $main::server_prefix = "checkbot";
  }
  $main::tmpdir = "/var/tmp/" . "Checkbot.$$";

  $main::cur_queue  = $main::tmpdir . "/queue";
  $main::new_queue  = $main::tmpdir . "/queue-new";
  $main::extfile = $main::tmpdir . "/external";

  # Set up hashes to be used
  %main::checked = ();
  %main::problem = ();
  %main::servers = ();

  # Start URL
  # Create the start URL
  $main::starturl = new URI::URL $main::opt_u;

  if ($main::starturl->scheme eq 'file') {
    $main::starturl->host('localhost');
  }

  # Variables to keep track of number of links
  $main::LINKS = 0;
  $main::DUPS  = 1;
  $main::PROBL = 2;
  $main::TODO = 3;

  @main::st_int = (0, 0, 0, 1);
  @main::st_ext = (0, 0, 0, 0);

  # We write out our status every now and then.
  $main::cp_int = 1;
  $main::cp_last = time();

}


sub setup {

  mkdir $main::tmpdir, 0755
    || die "$0: unable to create directory $main::tmpdir: $!\n";

  open(EXTERNAL, ">$main::extfile")
    || die "$0: Unable to open EXTERNAL $main::extfile for writing: $!\n";
  open(CURRENT, ">$main::cur_queue")
    || die "$0: Unable to open CURRENT $main::cur_queue for writing: $!\n";
  open(QUEUE, ">$main::new_queue")
    || die "$0: Unable to open QUEUE $main::new_queue for writing: $!\n";


  # Prepare CURRENT queue with starting URL
  print CURRENT $main::starturl->as_string . "|\n";
  close CURRENT;

  open(CURRENT, $main::cur_queue) 
    || die "$0: Unable to open CURRENT $main::cur_queue for reading: $!\n";

}

### Cleaning up after running Checkbot
sub clean_up {
  unless (defined($main::opt_d)) {
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
    while ($line = <CURRENT>) {
      chomp($line);
      &handle_url($line);
      &check_point();
      $main::st_int[$main::TODO]--;
    }

    # Move queues around, and try again, but only if there are still
    # things to do
    if ($main::st_int[$main::TODO]) {
      print STDERR "*** Moving queues around, $main::st_int[$main::TODO] to do\n" 
	if $main::opt_v;
      close CURRENT;
      close QUEUE;

      # TODO: should check whether these succeed
      unlink($main::cur_queue);
      rename($main::new_queue, $main::cur_queue);
    
      open(CURRENT, "$main::cur_queue") 
	|| die "$0: Unable to open $main::cur_queue for reading: $!\n";
      open(QUEUE, ">$main::new_queue") 
	|| die "$0: Unable to open $main::new_queue for writing: $!\n";
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
	
  if ($url->scheme =~ /^(http|file|ftp|gopher|nntp)$/o
      && $url->path !~ /$main::file/
      && $url->path !~ /=/o ) {
    if ($url->path =~ /\/$/o || $url->path eq "") {
      $type = 'text/html';
    } else {
      $type = guess_media_type($url->path);
    }
    if ($type =~ /html/o && $url->scheme =~ /^(http|file|ftp|gopher)$/o) {
      $reqtype = 'GET';
    } else {
      $reqtype = 'HEAD';
    }

    # Output what we are going to do with this link
    printf STDERR "    %4s %s (%s)\n", $reqtype, $url, $type
      if $main::opt_v;
	
    my $ref_header = new HTTP::Headers 'Referer' => $urlparent;
    my $request = new HTTP::Request($reqtype, $url, $ref_header);
    my $response = $main::ua->simple_request($request);

    if ($response->is_success) {
      sleep($main::opt_s) unless $main::opt_d || $url->scheme eq 'file';

      # If this url moves off of this site then return now
      if ($url !~ /$main::opt_m/o 
	  || (defined $main::opt_x && $url =~ /$main::opt_x/o)) {
	print STDERR " Exclude $url\n" if $main::opt_v;
      } else {
	&handle_doc($response) if $reqtype eq 'GET';
      }
    } else {
      if (defined $main::opt_z && $url =~ /$main::opt_z/o) {
	print STDERR "Ignore  $url\n" if $main::opt_v;
      } else {
	print STDERR "         ", $response->code, ' ', $response->message, "\n" 
	  if $main::opt_v;
	$main::problem{$url} = $response;
	$main::st_int[$main::PROBL]++;
      }

      if ($response->is_redirect) {
	print STDERR "         Redirected to " . $response->header('Location') . "\n" if $main::opt_v;
	add_to_queue($response->header('Location'), $urlparent);
      }
    }

    # Done with this URL
  } else {
    # not interested in other URLs right now
    print STDERR "  Ignore $url\n" if $main::opt_v;
  }
}

sub check_external {
  my $newurl;
  my $urlparent;
  my $prevurl = "";
  my $reqtype;

  # We use an external sort and uniq program, because they
  # usually handle large files much better
  rename $main::extfile, $main::extfile . '.unsorted';
  system 'sort', '-u', '-o',  $main::extfile, "$main::extfile.unsorted";
  unlink $main::extfile . '.unsorted';

  # Now I need to know how many links are left.  I'll use 'wc' for
  # now, but it seems all of this could be done in perl.
  open WC, "wc -l $main::extfile | "
    || die "$0: Unable to open a pipe to wc:$!\n";
  <WC> =~ /^\s*(\d+)/;
  $main::st_ext[$main::TODO] = $1;
  $main::st_ext[$main::DUPS] = $main::st_ext[$main::LINKS] - $main::st_ext[$main::TODO];
  close WC;

  print STDERR "*** Checking $main::st_ext[$main::TODO] external links\n"
    if defined $main::opt_v;
  # We know that our list is sorted, but the same URL
  # can exist several types, once for each parent
  # For now we just look at the first url/parent pair, but
  # ideally we should list this for each pair (i.e. for
  # each page on which the link occurs.
  open(EXTERNAL, $main::extfile) 
    || die "$0: Unable to open $main::extfile for reading: $!\n";
  while(<EXTERNAL>) {
    chomp;
    ($newurl, $urlparent) = split(/\|/);

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

      $reqtype = ($url->scheme =~ /^gopher$/o) ? 'GET' : 'HEAD';

      print STDERR "     $reqtype ", $url->abs, "\n" if $main::opt_v;
      my $ref_header = new HTTP::Headers 'Referer' => $urlparent;
      my $request = new HTTP::Request($reqtype, $url, $ref_header);
      my $response = $main::ua->simple_request($request);
      
      if ($response->is_error || $response->is_redirect) {
	if (defined $main::opt_z && $url =~ /$main::opt_z/o) {
	  print STDERR "Ignore  $url error\n";
	} else {
	  printf STDERR "          %d (%s)\n", $response->code, 
	  $response->message
	    if $main::opt_v;
	  $main::problem{$url} = $response;
	  $main::st_ext[$main::PROBL]++;
	}
      }
    }
    $main::st_ext[$main::TODO]--;
    &check_point();
  }
  close EXTERNAL;
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

    print STDERR "*** Start writing results page\n" if $main::opt_v;

    open(OUT, ">$main::file.new") 
	|| die "$0: Unable to open $main::file.bak for writing:\n";
    print OUT "<head>\n";
    if (!$final_page) {
      printf OUT "<META HTTP-EQUIV=\"Refresh\" CONTENT = %d>\n",
      $main::cp_int * 60;
    }

    print OUT "<title>Checkbot report</title></head>\n";
    print OUT "<h1><em>Checkbot</em>: main report</h1>\n";

    # Show the status of this checkbot session
    print OUT "<b>Status:</b> ";
    if ($final_page) {
      print OUT "Done.\n"
    } else {
      print OUT "Running since $main::start_time.\n";
      print OUT "(Last update at ". localtime() 
	. ", next update in <b>$main::cp_int</b> minutes.)\n";
    }

    # Summary (very brief overview of key statistics)
    print OUT "<hr><h2>Report summary</h2>\n";

    print OUT "<table>\n";
    print OUT "<tr> <td> </td> <th>Total<br>links</th> <th>Links<br>To Do</th>";
    print OUT "<th>Unique</br>links</th> <th>Problem<br>links</th> ";
    print OUT "<th>Ratio</th> </tr>\n";

    print OUT "<tr> <th>Internal</th>";
    printf OUT "<td align=right>%d</td> <td align=right>%d</td> <td align=right>%d</td> <td align=right>%d</td> <td align=right>%d%%</td> </tr>\n",
    $main::st_int[$main::LINKS] + $main::st_int[$main::DUPS],
    $main::st_int[$main::TODO],
    $main::st_int[$main::LINKS], $main::st_int[$main::PROBL],
    $main::st_int[$main::PROBL] / $main::st_int[$main::LINKS] * 100;

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
    my $server;
    print OUT "<hr><h2>Overview per server</h2>\n";
    print OUT "<table> <tr> <th>Server</th><th>Server<br>Type</th><th>Unique<br>links</th><th>Problem<br>links</th><th>Ratio</th></tr>\n";
    foreach $server (sort keys %main::servers) {
      &print_server($server, $final_page);
    }
    print OUT "</table>\n\n";
    print OUT "<hr>\n";

    # Checkbot session parameters
    print OUT "<h2>Checkbot session parameters</h2>\n";
    print OUT "<table>\n";
    print OUT "<tr><th>-u</th><td>Start URL</td><td>$main::starturl</td></tr>\n";
    print OUT "<tr><th>-m</th><td>Match regular expression</td><td>$main::opt_m</td></tr>\n";
    print OUT "<tr><th>-x</th><td>Exclude regular expression</td><td>$main::opt_x</td></tr>\n" if defined $main::opt_x;
    print OUT "<tr><th>-z</th><td>Ignore regular expression</td><td>$main::opt_z</td></tr>\n" if defined $main::opt_z;
    
    print OUT "</table>\n";

    # Statistics for types of links

    print OUT signature();

    close(OUT);

    rename($main::file, $main::file . ".bak");
    rename($main::file . ".new", $main::file);

    print STDERR "*** Done writing result page\n" if $main::opt_v;
}


sub get_server_type {
  my($server) = @_;

  my $result;

  if ( ! defined($main::server_type{$server})) {
    if ($server eq 'localhost') {
      $result = 'Direct access';
    } else {
      my $request = new HTTP::Request('HEAD', "http://$server/");
      my $response = $main::ua->simple_request($request);
      $result = $response->header('Server');
    }
    $result = "Unknown server type" if $result eq "";
    print STDERR "=== Server $server is a $result\n" if $main::opt_v;
    $main::server_type{$server} = $result;
  }
  $main::server_type{$server};
}

sub add_checked {
  my($url) = @_;
  my $item;
  my $result = 0;

  if (defined $main::checked{$url}) {
    $result = 1;
    $main::st_int[$main::DUPS]++;
    $main::checked{$url}++;
  } else {
    $main::checked{$url} = 1;
  }

  return $result;
}

# Parse document, and get the links
sub handle_doc {
  my ($response) = @_;
  my ($doc_new, $doc_dup, $doc_ext) = (0, 0, 0);

  # When we received the document we can add a notch to its server
  $main::servers{$response->base->netloc}++;

  # Use the new LinkExtor
  my $p = HTML::LinkExtor->new(undef, $response->base);
  $p->parse($response->content);
  $p->parse(undef);

  # Parse the links we found in this document
  my @links = $p->links();
  foreach (@links) {
    my ($tag, %l) = @{$_};
    foreach (keys %l) {
      my $url = $l{$_};

      # Remove fragments, if any
      $url->frag(undef);

      if ($url->abs =~ /$main::opt_m/o) {
	if (defined $main::checked{$url->abs}) {
	  $doc_dup++;
	} else {
	  add_to_queue($url->abs, $response->base);
	  $doc_new++;
	}
      } else {
	# Add this as an external link if we can check the protocol later
	if ($url->abs =~ /^(http|ftp):/o) {
	  print EXTERNAL $url->abs . "|" . $response->base . "\n";
	  $doc_ext++;
	}
      }
    }
  }
  $main::st_int[$main::DUPS] += $doc_dup;
  $main::st_ext[$main::LINKS] += $doc_ext;
  $main::st_ext[$main::TODO] += $doc_ext;
  if ($main::opt_v) {
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

  print STDERR "    Writing server $server\n" if $main::opt_v;

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
      $main::cp_int * 60;
  }
  print SERVER "<title>Checkbot: output for server $server</title></head>\n";
  print SERVER "<body><h2><em>Checkbot</em>: report for server <tt>$server</tt></h2>\n";
  print SERVER "Go To: <a href=\"$main::file\">Main report page</a>.\n";
  print SERVER "<hr><dl>\n";

  &print_server_problems($server, $final_page);

  print SERVER "</dl>\n";
  print SERVER signature();

  close SERVER;
}

# Return a string containing Checkbot's signature for HTML pages
sub signature {
  return "<hr>\nPage created by <a href=http://dutifp.twi.tudelft.nl:8000/checkbot/>Checkbot $main::VERSION</a> on <em>" . localtime() . "</em>.\n";
}

sub print_server_problems {
  my ($server) = @_;

  my $prevpath = "";
  my $prevcode = 0;
  my $prevmessage = "";

  my $url;

  foreach $url (sort byproblem keys %main::problem) {
    my $response = $main::problem{$url};
    my $parent = new URI::URL $response->request->header('Referer');
    if ($parent =~ $server) {
      if ($response->is_error || $response->is_redirect) {
	my $path = '/' . $parent->path;
	my $string = "";
	if ($response->code != $prevcode 
	    || $response->message !~ m/$prevmessage/i) {
	  $string .= '</dl><h4><b>' . $response->code . '</b> '
	    . $response->message . "</h4>\n<dl>\n";
	  $prevcode = $response->code;
	  $prevmessage = $response->message;
	  $prevpath = "";
	}
	if ($path ne $prevpath) {
	  $string .= "<dt><b><a href=\"$parent\">$path</a></b>";
	  $prevpath = $path;
	}
	$string .= "<dd><a href=\"$url\">$url</a>\n";
	print SERVER $string;
      }
    }
  }
}

sub check_point {
    if ( ($main::cp_last + 60 * $main::cp_int < time()) 
	 || ($main::opt_d && $main::opt_v)) {
	&create_page(0);
	$main::cp_last = time();
	$main::cp_int = int($main::cp_int * 1.5 + 0.5) unless $main::opt_d;
    }
}

sub send_mail {
  my $msg = new Mail::Send;

  $msg->to($main::opt_M);
  $msg->subject("Checkbot results for $main::opt_u available.");

  my $fh = $msg->open;

  print $fh "Checkbot results for $main::opt_u are available.\n\n";
  print $fh "User-supplied note: $main::opt_N\n\n"
    if defined $main::opt_N;

  print $fh "A brief summary of the results follows:\n\n";
  printf $fh "Internal: %6d total, %6d unique, %6d problems, ratio = %3d%%\n",
  $main::st_int[$main::LINKS] + $main::st_int[$main::DUPS],
  $main::st_int[$main::LINKS], $main::st_int[$main::PROBL],
  $main::st_int[$main::PROBL] / $main::st_int[$main::LINKS] * 100;
  printf $fh "External: %6d total, %6d unique, %6d problems, ratio = %3d%%\n",
  $main::st_ext[$main::LINKS] + $main::st_ext[$main::DUPS],
  $main::st_ext[$main::LINKS], $main::st_ext[$main::PROBL],
  $main::st_ext[$main::PROBL] / $main::st_ext[$main::LINKS] * 100;

  print $fh "\n\n-- \nCheckbot $main::VERSION\n";
  print $fh "<URL:http://twi72.twi.tudelft.nl:8000/checkbot/>\n";

  $fh->close;
}

sub print_help {
  print "Checkbot command line options:\n\n";
  print "  -d          Debugging mode: No pauses, stop after 25 links.\n";
  print "  -v          Verbose mode: display many messages about progress.\n";
  print "  -u url      Start URL\n";
  print "  -m match    Check pages only if URL matches `match'\n";
  print "              If no match is given, the start URL is used as a match\n";
  print "  -x exclude  Exclude pages if the URL matches 'exclude'\n";
  print "  -z ignore   Do not list error messages for pages that the URL matches 'ignore'\n";
  print "  -f file     Write results to file, default is checkbot.html\n";
  print "  -M address  Mail brief synopsis to address when done.\n";
  print "  -N note     Include Note (typical URL to report) along with Mail message.\n";
  print "  -s secs     Sleep for secs seconds between requests (default 2)\n";
  print "  -t timeout  Timeout for http requests in seconds (default 120)\n\n";
  print "Options -m, -x, and -z can take a perl regular expression as their argument\n\n";
  print "Use 'perldoc checkbot' for more verbose documentation.\n\n";
  print "Checkbot WWW page     : http://dutifp.twi.tudelft.nl:8000/checkbot/\n";
  print "Mail bugs and problems: checkbot-bugs\@twi72.twi.tudelft.nl\n";
    
  exit 0;
}

sub count_problems {
  my ($server) = @_;
  my $count = 0;
  my $url = '';

  foreach $url (keys %main::problem) {
    my $response = $main::problem{$url};
    my $parent = new URI::URL $response->request->header('Referer');
    $count++ if $parent =~ $server;
  }

  return $count;
}

sub byproblem {
    my $response_a = $main::problem{$::a};
    my $response_b = $main::problem{$::b};
    
    if ($response_a->code == $response_b->code) {
	if ($response_a->message eq $response_b->message) {
	    return $response_a->request->header('Referer') 
		cmp $response_b->request->header('Referer');
	} else {
	    return $response_a->message cmp $response_b->message;
	}
    } else {
	return $response_a->code <=> $response_b->code;
    }
}


# $Log: checkbot.pl,v $
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
