#!/usr/bin/env perl -w
use strict;
use Test;

BEGIN { plan tests => 1 }

# Testing the executable is hard, but I suppose we can at least try to
# run the to be installed Checkbot to see if things work out ok.

ok(not system('blib/script/checkbot'));

exit;
