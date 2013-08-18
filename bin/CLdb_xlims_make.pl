#!/usr/bin/env perl

### modules
use strict;
use warnings;
use Pod::Usage;
use Data::Dumper;
use Getopt::Long;
use File::Spec;
use DBI;

### args/flags
pod2usage("$0: No files given.") if ((@ARGV == 0) && (-t STDIN));


my ($verbose, $CLdb_sqlite, @ITEP_sqlite);
my (@subtype, @taxon_id, @taxon_name);
my $extra_query = "";
my $spacer_cutoff = 1;
my $xlim_out = "xlims.txt";
GetOptions(
	   "database=s" => \$CLdb_sqlite,
	   "ITEP=s{,}" => \@ITEP_sqlite,
	   "subtype=s{,}" => \@subtype,
	   "taxon_id=s{,}" => \@taxon_id,
	   "taxon_name=s{,}" => \@taxon_name,
	   "query=s" => \$extra_query,
	   "cutoff=f" =>  \$spacer_cutoff,
	   "verbose" => \$verbose,
	   "help|?" => \&pod2usage # Help
	   );

### I/O error & defaults
# checking CLdb #
die " ERROR: provide a database file name!\n"
	unless $CLdb_sqlite;
die " ERROR: cannot find CLdb database file!\n"
	unless -e $CLdb_sqlite;
	
### MAIN
# connect 2 CLdb #
my %attr = (RaiseError => 0, PrintError=>0, AutoCommit=>0);
my $dbh = DBI->connect("dbi:SQLite:dbname=$CLdb_sqlite", '','', \%attr) 
	or die " Can't connect to $CLdb_sqlite!\n";

# joining query options (for table join) #
my $join_sql = "";
$join_sql .= join_query_opts(\@subtype, "subtype");
$join_sql .= join_query_opts(\@taxon_id, "taxon_id");
$join_sql .= join_query_opts(\@taxon_name, "taxon_name");

# getting loci start-end #
make_xlims($dbh, $join_sql, $extra_query);

# disconnect #
$dbh->disconnect();
exit;


### Subroutines
sub make_xlims{
	my ($dbh, $join_sql, $extra_query) = @_;
	
# same table join #
	my $query = "
SELECT 
loci.locus_start,
loci.locus_end,
loci.taxon_name,
loci.locus_id,
loci.subtype
FROM Loci Loci, Loci b
WHERE Loci.locus_id = b.locus_id
$join_sql
$extra_query
GROUP BY loci.locus_id
";
	$query =~ s/\n|\r/ /g;
	
	# status #
	print STDERR "$query\n" if $verbose;

	# query db #
	my $ret = $dbh->selectall_arrayref($query);
	die " ERROR: no matching entries!\n"
		unless $$ret[0];
	
	print join("\t", qw/start end taxon_name locus_id subtype/), "\n";
	foreach my $row (@$ret){
		print join("\t", @$row), "\n";
		}
	}

sub join_query_opts{
# joining query options for selecting loci #
	my ($vals_r, $cat) = @_;

	return "" unless @$vals_r;	
	
	map{ s/"*(.+)"*/"$1"/ } @$vals_r;
	return join("", " AND loci.$cat IN (", join(", ", @$vals_r), ")");
	}



__END__

=pod

=head1 NAME

CLdb_xlims_make.pl -- making xlims table for plotting

=head1 SYNOPSIS

CLdb_xlims_make.pl [flags] > xlims.txt

=head2 Required flags

=over

=item -d 	CLdb database.

=back

=head2 Optional flags

=over

=item -subtype

Refine query to specific a subtype(s) (>1 argument allowed).

=item -taxon_id

Refine query to specific a taxon_id(s) (>1 argument allowed).

=item -taxon_name

Refine query to specific a taxon_name(s) (>1 argument allowed).

=item -query

Extra sql to refine which sequences are returned.

=item -v 	Verbose output. [FALSE]

=item -h	This help message

=back

=head2 For more information:

perldoc CLdb_xlims_make.pl

=head1 DESCRIPTION

Make a basic xlims table needed for plotting.

=head1 EXAMPLES

=head2 Plotting all loci classified as subtype 'I-A'

CLdb_xlims_make.pl -d CLdb.sqlite -sub I-A 

=head2 No broken loci

CLdb_xlims_make.pl -da CLdb.sqlite -sub I-A -q "AND loci.operon_status != 'broken'"

=head1 AUTHOR

Nick Youngblut <nyoungb2@illinois.edu>

=head1 AVAILABILITY

sharchaea.life.uiuc.edu:/home/git/CLdb/

=head1 COPYRIGHT

Copyright 2010, 2011
This software is licensed under the terms of the GPLv3

=cut

