#!/usr/bin/env perl

=pod

=head1 NAME

blast-xml2json.pl -- converting blast output (xml format) to JSON format

=head1 SYNOPSIS

blast-xml2json.pl [flags] < blast_output.xml > blast_output.json

=head2 Required flags

NONE

=head2 Optional flags

=over

=item -v 	Verbose output. [FALSE]

=item -h	This help message

=back

=head2 For more information:

perldoc blast-xml2json.pl

=head1 DESCRIPTION

Simple script for converting blast output in xml format
(-outfmt 5) to JSON format.

=head1 EXAMPLES

=head1 AUTHOR

Nick Youngblut <nyoungb2@illinois.edu>

=head1 AVAILABILITY

sharchaea.life.uiuc.edu:/home/git/CLdb/

=head1 COPYRIGHT

Copyright 2010, 2011
This software is licensed under the terms of the GPLv3

=cut

#--- modules ---#
# core #
use strict;
use warnings;
use Pod::Usage;
use Data::Dumper;
use Getopt::Long;
use XML::XML2JSON;

# CLdb #
use FindBin;
use lib "$FindBin::RealBin/../lib";
use lib "$FindBin::RealBin/../lib/perl5/";

#--- parsing args ---#
pod2usage("$0: No files given.") if ((@ARGV == 0) && (-t STDIN));

my ($verbose);
GetOptions(
	   "verbose" => \$verbose,
	   "help|?" => \&pod2usage # Help
	   );

#--- I/O error & defaults ---#


#--- MAIN ---#
my $XML = '';
$XML .= $_ while <>;

my $XML2JSON = XML::XML2JSON->new();
print $XML2JSON->convert($XML);

