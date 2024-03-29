# This -*- perl -*- script makes the Makefile
# Based on the Makefile.PL in the libwww-perl distribution
# $Id: Makefile.PL 231 2007-02-26 15:51:46Z graaff $

require 5.005;
use strict;
use ExtUtils::MakeMaker;


my $missing_modules = 0;

print "\nChecking for LWP...........";
eval {
    require LWP;
    LWP->VERSION(5.803);
};
if ($@) {
    print " failed\n";
    $missing_modules++;
    print <<EOT;
$@
Checkbot depends on LWP (libwww-perl) for almost all actions.

EOT
    sleep(2);  # Don't hurry too much
} else {
    print " ok\n";
}
print "Checking for URI...........";
eval {
    require URI;
    URI->VERSION(1.10);
};
if ($@) {
    print " failed\n";
    $missing_modules++;
    print <<EOT;
$@
The URI module must be installed.  WWW without URIs would not
be that great :-)

EOT
    sleep(2);  # Don't hurry too much
} else {
    print " ok\n";
}
print "Checking for HTML::Parser..";
eval {
    require HTML::HeadParser;
    HTML::Parser->VERSION(3.33);
};
if ($@) {
    print " failed\n";
    $missing_modules++;
    print <<EOT;
$@
The HTML::Parser is needed to extract correct base URI information from
HTML so that we can resolve relative links correctly.  The HTML::Form
module also need HTML::TokeParser to work.

EOT
    sleep(2);  # Don't hurry too much
} else {
    print " ok\n";
}

print "Checking for MIME::Base64..";
eval {
    require MIME::Base64;
    #MIME::Base64->VERSION('2.00');
};
if ($@) {
    print " failed\n";
    $missing_modules++;
    print <<EOT;
$@
The Base64 encoding is used in authentication headers in HTTP.

EOT
    sleep(2);  # Don't hurry too much
} else {
    print " ok\n";
}

print "Checking for Net::FTP......";
eval {
    require Net::FTP;
    Net::FTP->VERSION('2.58');
};
if ($@) {
    print " failed\n";
    $missing_modules++;
    print <<EOT;
$@
The libwww-perl library normally use the Net::FTP module when
accessing ftp servers.  You would have to install this package or
configure your application to use a proxy server for making ftp
requests work.  Net::FTP is part of the 'libnet' distribution.

EOT
    sleep(2);  # Don't hurry too much
} else {
    print " ok\n";
}

print "Checking for Digest::MD5 ..";
eval {
    require Digest::MD5;
};
if ($@) {
    print " failed\n";
    $missing_modules++;
    print <<EOT;
$@
The Digest::MD5 library is needed if you want to be able use the
experimental "Digest Access Authentication" scheme.  Since very few
servers implement this authentication scheme, you should normally not
worry too much about this.

EOT
} else {
    print " ok\n";
}

print "Checking for Mail::Send ..";
eval {
    require Mail::Send;
};
if ($@) {
    print " failed\n";
    $missing_modules++;
    print <<EOT;
$@ 

Mail::Send is used to allow Checkbot to send email. You currently
can not use the --mailto option of Checkbot. Mail::Send can be found
in the MailTools package.

EOT
} else {
    print " ok\n";
}

print "Checking for Time::Duration ..";
eval {
    require Time::Duration;
};
if ($@) {
    print " failed\n";
    $missing_modules++;
    print <<EOT;
$@ 

Time::Duration is used to display information on elapsed time in the
reports. If Time::Duration is not available Checkbot will still work,
but this information is not printed in the report.

EOT
} else {
    print " ok\n";
}

print "Checking for Net::SSL ..";
eval {
    require Net::SSL;
};
if ($@) {
    print " failed\n";
    $missing_modules++;
    print <<EOT;
$@ 

Net::SSL is used to check https links. If Net::SSL is not available
Checkbot will still work, but it is not possible to check https://
links. Net::SSL is part of the Crypt::SSLeay package. Note that this
package in turn depends on the openssl tools.

EOT
} else {
    print " ok\n";
}
print <<EOT if $missing_modules;
The missing modules can be obtained from CPAN.  Visit
<URL:http://www.perl.com/CPAN/> to find a CPAN site near you.

EOT

print "\n";

# Write the Makefile
WriteMakefile(
	      NAME   => "checkbot",
	      EXE_FILES => [ 'checkbot' ],
	      MAN3PODS => {},
	      PM => {},
	      VERSION_FROM => q(checkbot),
	      dist => {COMPRESS => 'gzip',
		       SUFFIX => 'gz' },
);

