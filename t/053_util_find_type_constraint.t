#!/usr/bin/perl

use strict;
use warnings;

use Test::More tests => 1;
use Test::Exception;

BEGIN {
	use_ok('Moose::Util::TypeConstraints', (':no_export'));
}

#diag Moose::Util::TypeConstraints::dump_type_constraints();