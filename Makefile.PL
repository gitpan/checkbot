# This -*- perl -*- script makes the Makefile
# $Id: Makefile.PL,v 1.2 1996/09/28 08:18:12 graaff Exp $

require 5.002;
use ExtUtils::MakeMaker;

# chk_version from GBARR's IO Makefile.PL
sub chk_version
{
 my($pkg,$wanted,$msg) = @_;
 
 $| = 1;
 print "Checking for $pkg...";
 
 eval { my $p; ($p = $pkg . ".pm") =~ s#::#/#g; require $p; };
 
 my $vstr = ${"${pkg}::VERSION"} ? "found v" . ${"${pkg}::VERSION"}
                                 : "not found";
 my $vnum = ${"${pkg}::VERSION"} || 0;
 
 print $vnum >= $wanted ? "ok\n" : " " . $vstr . "\n";
 
 $vnum >= $wanted;
}

# Check for proper version of LWP
chk_version('LWP' => '5.02') or
  die "*** Checkbot requires LWP 5.02 or later in order to work properly\n";

# FTP should have been checked by LWP, but check anyway
chk_version('Net::FTP' => '2.00') or
  warn "*** Checkbot requires Net::FTP 2.00 or later to correctly check FTP URLs\n";

# Mail::Send is nice, but not really needed
chk_version('Mail::Send' => '1.03') or
  warn "*** Mail::Send not found. You currently can not use the --mailto option\n    of Checkbot\n";

# Write the Makefile
WriteMakefile(
	      NAME   => "checkbot",
	      PL_FILES  => { 'checkbot.pl' => 'checkbot' },
	      EXE_FILES => [ 'checkbot' ],
	      MAN3PODS => {},
	      PM => {},
	      VERSION_FROM => q(checkbot.pl),
	      dist => {COMPRESS => 'gzip',
		       SUFFIX => 'gz' },
);
