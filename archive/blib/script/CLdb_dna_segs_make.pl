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
	
# checking ITEP input #
if(@ITEP_sqlite){
	die " ERROR: '-ITEP' must be 2 arguments (database_file, runID)!\n"
		unless scalar @ITEP_sqlite >= 2;
	die " ERROR: cannot find ITEP database file!\n"
		unless -e $ITEP_sqlite[0];
	}

### MAIN
# connect 2 CLdb #
my %attr = (RaiseError => 0, PrintError=>0, AutoCommit=>0);
my $dbh = DBI->connect("dbi:SQLite:dbname=$CLdb_sqlite", '','', \%attr) 
	or die " Can't connect to $CLdb_sqlite!\n";

# connect to ITEP #
my $dbh_ITEP;
if(@ITEP_sqlite){
	my %attr = (RaiseError => 0, PrintError=>0, AutoCommit=>0);
	$dbh_ITEP = DBI->connect("dbi:SQLite:dbname=$ITEP_sqlite[0]", '','', \%attr) 
		or die " Can't connect to $ITEP_sqlite[0]!\n";	
	}

# joining query options (for table join) #
my $join_sql = "";
$join_sql .= join_query_opts(\@subtype, "subtype");
$join_sql .= join_query_opts(\@taxon_id, "taxon_id");
$join_sql .= join_query_opts(\@taxon_name, "taxon_name");

# getting subtype #
my $subtypes_r = get_subtypes($dbh, $join_sql, $extra_query);

# getting spacer, DR, leader, & gene info from CLdb #
my %dna_segs; 
my $spacer_clusters_r = get_spacer_info($dbh, \%dna_segs, 
							$join_sql, $extra_query, $spacer_cutoff);
get_DR_info($dbh, \%dna_segs, $join_sql, $extra_query);
get_gene_info($dbh, \%dna_segs, $join_sql, $extra_query);
get_leader_info($dbh, \%dna_segs, $join_sql, $extra_query);

# getting gene cluster info if ITEP provided #
my $gene_cluster_r = get_gene_cluster_info($dbh_ITEP, $ITEP_sqlite[0], 
						$ITEP_sqlite[1], \%dna_segs)
						if @ITEP_sqlite;

# mutli-loci / multi-subtype problem
## determining if multiple loci/subtypes per taxon_name ##
my ($multi_loci, $multi_subtype)  = check_multi(\%dna_segs, $subtypes_r);

## adding loci & subtypes to DNA_segs names ##
my $dna_segs_r = edit_dna_segs_taxon_name(\%dna_segs, $subtypes_r, $multi_loci, $multi_subtype);

# writing table #
write_dna_segs(\%dna_segs, $subtypes_r);

# disconnect #
$dbh->disconnect();
$dbh_ITEP->disconnect() if $dbh_ITEP;
exit;


### Subroutines
sub write_dna_segs{
# writing dna_segs precursor table #
## required columns ##
# name
# start
# end
# strand
# col
# lty
# lwd
# pch
# cex
# gene_type

## extra columns: ##
### taxon_name
### locus_ID
### feat_ID 

	my ($dna_segs, $subtypes_r) = @_;
	
	# header #
	print join("\t", qw/name start end strand col lty lwd pch cex gene_type taxon_name locus_id feat feat_id subtype dna_segs_id/), "\n";
	
	# body #
	foreach my $taxon_name (keys %$dna_segs){
		foreach my $locus_id (keys %{$dna_segs->{$taxon_name}}){
			# spacers #
			foreach my $id (keys %{$dna_segs->{$taxon_name}{$locus_id}{"spacer"}}){
				my $row = $dna_segs->{$taxon_name}{$locus_id}{"spacer"}{$id};
				
				# start-end, color #
				my $start = $$row[0];
				my $end = $$row[1];
				my $col = $$row[2];
				my $dna_segs_id = $$row[$#$row];
				
				print join("\t",  
					$id,
					$start,
					$end,
					1,				# strand
					$col,
					1, 0.5, 8, 1,	# plot formatting
					"blocks", 		# end of required columns
					$taxon_name,
					$locus_id,
					"spacer", 		# feature
					$id,
					$subtypes_r->{$taxon_name}{$locus_id},
					$dna_segs_id
					), "\n";				
				}
			# DRs #
			foreach my $id (keys %{$dna_segs->{$taxon_name}{$locus_id}{"DR"}}){
				my $row = $dna_segs->{$taxon_name}{$locus_id}{"DR"}{$id};
				
				# start-end, color #
				my $start = $$row[0];
				my $end = $$row[1];
				my $dna_segs_id = $$row[$#$row];				

				print join("\t",  
					$id,
					$start,
					$end,
					1, 				# strand 
					1,				# col
					1, 0.1, 8, 1,	# plot formatting
					"blocks", 		# end of required columns
					$taxon_name,
					$locus_id,
					"directrepeat", 	# feature
					$id,
					$subtypes_r->{$taxon_name}{$locus_id},
					$dna_segs_id
					), "\n";				
				}
			# leaders #
			foreach my $id (keys %{$dna_segs->{$taxon_name}{$locus_id}{"leader"}}){
				my $row = $dna_segs->{$taxon_name}{$locus_id}{"leader"}{$id};
				
				# start-end, color #
				my $start = $$row[0];
				my $end = $$row[1];
				my $dna_segs_id = $$row[$#$row];				

				print join("\t",  
					$id,			
					$start,
					$end,
					1, 				# strand 
					1,				# col
					1, 0.1, 8, 1,	# plot formatting
					"blocks", 		# end of required columns
					$taxon_name,
					$locus_id,
					"leader", 		# feature
					$id,
					$subtypes_r->{$taxon_name}{$locus_id},
					$dna_segs_id
					), "\n";				
				}			
			# genes #
			foreach my $id (keys %{$dna_segs->{$taxon_name}{$locus_id}{"gene"}}){
				my $row = $dna_segs->{$taxon_name}{$locus_id}{"gene"}{$id};
				
				# start-end, color #			
				my $start = $$row[0];
				my $end = $$row[1];
				my $alias = $$row[2];
				my $dna_segs_id = $$row[$#$row];
				
				# color #
				my $col = 1;
				$col = $$row[3]
					if $$row[3];
				
				print join("\t",  
					$alias,
					$start,
					$end,
					get_strand($start, $end), 		# strand 
					$col,
					1, 1, 8, 1,				# plot formatting
					"arrows", 				# end of required columns
					$taxon_name,
					$locus_id,
					"gene", 				# feature
					$id,
					$subtypes_r->{$taxon_name}{$locus_id},
					$dna_segs_id			
					), "\n";				
				}				
			}
		}
	}

sub edit_dna_segs_taxon_name{
    my ($dna_segs_r, $header_r, $multi_loci, $multi_subtype) = @_;
   
	foreach my $taxon_name (keys %$dna_segs_r){
    	foreach my $locus_id (keys %{$dna_segs_r->{$taxon_name}}){
        	# editing taxon_name in row #
        	my $dna_segs_id = $taxon_name;
        	$dna_segs_id = join("__", $taxon_name, "cli$locus_id")
            	            if $multi_loci;
            $dna_segs_id = join("__", $dna_segs_id, $dna_segs_r->{$taxon_name}{$locus_id}{"subtype"})
                           if $multi_subtype;
        	
        	foreach my $cat (keys %{$dna_segs_r->{$taxon_name}{$locus_id}}){  
                foreach my $id (keys %{$dna_segs_r->{$taxon_name}{$locus_id}{$cat}}){  
				
					push(@{$dna_segs_r->{$taxon_name}{$locus_id}{$cat}{$id}}, $dna_segs_id);
					}                               
				}
        	}
        }
       
       	#print Dumper $dna_segs_r; exit;
	}

sub check_multi{
# checking for multiple entries per taxon #
	my ($dna_segs_r, $subtypes_r) = @_;
	
	my $multi_loci = 0;				# mutliple loci per taxon_name
	my $multi_subtype = 0;			# multiple subtypes total 
	my %subtype_sum; 
	foreach my $taxon_name (keys %$dna_segs_r){
		$multi_loci = 1 if scalar keys %{$dna_segs_r->{$taxon_name}} > 1;
			
		foreach my $locus_id (keys %{$dna_segs_r->{$taxon_name}} ){
			# sanity check #
			die " ERROR: cannot find subtype for $taxon_name -> $locus_id!\n"
				unless exists $subtypes_r->{$taxon_name}{$locus_id};
			
			$subtype_sum{$subtypes_r->{$taxon_name}{$locus_id}}++;
			}
		}
	$multi_subtype = 1 if scalar keys %subtype_sum > 1;

	# status #
	print STDERR "...Found multiple loci for 1 or more taxa. Adding loci_ids to names in dna_segs table!\n"
		if $multi_loci;
	print STDERR "...Found multiple subtypes. Adding subtype to names in dna_segs table!\n"
		if $multi_subtype;
		
	return $multi_loci, $multi_subtype;
	}

sub get_strand{
# start > end? #
	my ($start, $end) = @_;
	if($start <= $end){ return 1; }		# + strand
	else{ return -1; }					# - strand
	}

sub get_gene_cluster_info{
# getting gene cluster info from ITEP #
	my ($dbh_ITEP, $ITEP_file, $runID, $dna_segs_r) = @_;
	
	my $query = "
SELECT clusterid
FROM clusters
WHERE runid = ?
AND geneid = ?
";
	$query =~ s/\n|\r/ /g;
	
	my $sth = $dbh_ITEP->prepare($query);
	
	my %gene_clusters;
	foreach my $taxon_id (keys %$dna_segs_r){
		foreach my $locus_id (keys %{$dna_segs_r->{$taxon_id}}){
			foreach my $gene_id (keys %{$dna_segs_r->{$taxon_id}{$locus_id}{"gene"}}){
				$sth->bind_param(1, $runID);
				$sth->bind_param(2, $gene_id);
				$sth->execute;
				my $ret =$sth->fetchrow_arrayref();	
				die " ERROR: no matching entries for ITEP query!\n"
					unless $$ret[0];
				
				push @{$dna_segs_r->{$taxon_id}{$locus_id}{"gene"}{$gene_id}}, $$ret[0];
				
				$gene_clusters{$$ret[0]} = 1;
				}
			}
		}
	
		#print Dumper %gene_clusters; exit;
	return \%gene_clusters;
	}

sub get_gene_info{
# getting direct repeat info from CLdb #
	my ($dbh, $dna_segs_r, $join_sql, $extra_query) = @_;

	my $query = "
SELECT
loci.taxon_name,
loci.locus_id, 
genes.gene_id, 
genes.gene_start, 
genes.gene_end,
genes.gene_alias
FROM Loci, Genes
WHERE Loci.locus_id = Genes.locus_id
AND Genes.In_operon = 'yes'
$join_sql
$extra_query
";
	$query =~ s/\n|\r/ /g;
	
	# status #
	print STDERR "$query\n" if $verbose;

	# query db #
	my $ret = $dbh->selectall_arrayref($query);
	die " ERROR: no matching entries for CAS gene query!\n"
		unless $$ret[0];
	
	#my %gene_ids;
	foreach my $row (@$ret){
		$dna_segs_r->{$$row[0]}{$$row[1]}{"gene"}{$$row[2]} = [@$row[3..$#$row]];
		
		}
	
		#print Dumper %$dna_segs_r; exit;
	#return \%gene_ids;
	}	

sub get_leader_info{
# getting leader info from CLdb (optional) #
## just using locus-ID for leader_ID
	my ($dbh, $dna_segs_r, $join_sql, $extra_query) = @_;

	my $query = "
SELECT 
loci.taxon_name,
loci.locus_id, 
leaders.locus_id,
leaders.leader_start, 
leaders.leader_end
FROM Loci, leaders
WHERE Loci.locus_id = leaders.locus_id
$join_sql
$extra_query
";
	$query =~ s/\n|\r/ /g;
	
	# status #
	print STDERR "$query\n" if $verbose;

	# query db #
	my $ret = $dbh->selectall_arrayref($query);
		
	if($$ret[0]){
		foreach my $row (@$ret){
			$dna_segs_r->{$$row[0]}{$$row[1]}{"leader"}{$$row[2]} = [@$row[3..$#$row]];
			}	
		}
	else{
		print STDERR " WARNING: no matching entries in leaders table! Leaders not added to dna_segs table!\n";
		}

	#print Dumper %$dna_segs_r; exit;
	}

sub get_DR_info{
# getting direct repeat info from CLdb #
	my ($dbh, $dna_segs_r, $join_sql, $extra_query) = @_;

	my $query = "
SELECT 
loci.taxon_name,
loci.locus_id, 
DRs.DR_id, 
DRs.DR_start, 
DRs.DR_end
FROM Loci, DRs
WHERE Loci.locus_id = DRs.locus_id
$join_sql
$extra_query
";
	$query =~ s/\n|\r/ /g;
	
	# status #
	print STDERR "$query\n" if $verbose;

	# query db #
	my $ret = $dbh->selectall_arrayref($query);
	die " ERROR: no matching entries for DR query!\n"
		unless $$ret[0];
	
	foreach my $row (@$ret){
		$dna_segs_r->{$$row[0]}{$$row[1]}{"DR"}{$$row[2]} = [@$row[3..$#$row]];
		}
	
	#print Dumper %$dna_segs_r; exit;
	}	

sub get_spacer_info{
# getting spacer info from CLdb #
	my ($dbh, $dna_segs_r, $join_sql, $extra_query, $spacer_cutoff) = @_;
	
	# checking for spacer_hclust #
	my $q = "SELECT count(*) FROM spacer_hclust";
	my $chk = $dbh->selectall_arrayref($q);
	die " ERROR! no entries in spacer_hclust table!  Run CLdb_hclusterArrays.pl prior to this script!\n"
		unless @$chk;
	
	# query of spacers #
	my $query = "
SELECT 
loci.taxon_name,
loci.locus_id, 
spacers.spacer_id, 
spacers.spacer_start, 
spacers.spacer_end, 
spacer_hclust.cluster_id
FROM Loci, Spacers, Spacer_hclust
WHERE Loci.locus_id = Spacers.locus_id
AND Spacers.locus_id = Spacer_hclust.locus_id
AND Spacers.spacer_id = Spacer_hclust.spacer_id
AND Spacer_hclust.cutoff = $spacer_cutoff
$join_sql
$extra_query
";
	$query =~ s/\n|\r/ /g;
	
	# status #
	print STDERR "$query\n" if $verbose;

	# query db #
	my $ret = $dbh->selectall_arrayref($query);
	die " ERROR: no matching entries for spacer query!\n"
		unless $$ret[0];
	
	my %spacer_clusters; 
	foreach my $row (@$ret){
		# sanity check #
		die " ERROR: multiple entries for $$row[0], $$row[1], $$row[2]!\n"
			if exists $dna_segs_r->{$$row[0]}{$$row[1]}{"spacer"}{$$row[2]};
		
		# loading dna_segs_r #
		$dna_segs_r->{$$row[0]}{$$row[1]}{"spacer"}{$$row[2]} = [@$row[3..$#$row]];
		$spacer_clusters{$$row[5]}++;			# unique clusters 
		}
	
		#print Dumper %$dna_segs_r; exit;
		#print Dumper \%spacer_clusters; exit;
		#exit;
	return \%spacer_clusters;
	}

sub get_subtypes{
	my ($dbh, $join_sql, $extra_query ) = @_;
	
	my $query = "
SELECT 
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
	die " ERROR: no matching entries for subtype query!\n"
		unless $$ret[0];
	
	my %subtypes; 
	foreach my $row (@$ret){
		$subtypes{$$row[0]}{$$row[1]} = $$row[2]; 		# taxon_name => locus_id => subtype
		}
	
		#print Dumper %subtypes; exit;
	return \%subtypes;
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

CLdb_dna_segs_make.pl -- making dna_segs table for plotting

=head1 SYNOPSIS

CLdb_dna_segs_make.pl [flags] > dna_segs.txt

=head2 Required flags

=over

=item -database  <char>

CLdb database.

=back

=head2 Optional flags

=over

=item -ITEP  <char>

Get gene cluster info from ITEP. 2 arguments required: (ITEP_sqlite_file, cluster_runID).

=item -cutoff  <float>

Spacer clustering cutoff for spacer coloring (0.8 - 1). [1]

=item -subtype  <char>

Refine query to specific a subtype(s) (>1 argument allowed).

=item -taxon_id  <char>

Refine query to specific a taxon_id(s) (>1 argument allowed).

=item -taxon_name  <char>

Refine query to specific a taxon_name(s) (>1 argument allowed).

=item -query  <char>

Extra sql to refine which sequences are returned.

=item -verbose  <bool> 

Verbose output. [FALSE]

=item -help  <bool>

This help message

=back

=head2 For more information:

perldoc CLdb_dna_segs_make.pl

=head1 DESCRIPTION

Make a basic dna_segs object needed for plotting.

=head2 Coloring genes by gene cluster

Provide and ITEP sqlite file name and cluster run ID
to add cluster info to the table (used for coloring)

=head1 EXAMPLES

=head2 Plotting all loci classified as subtype 'I-A'

CLdb_dna_segs_make.pl -d CLdb.sqlite -sub I-A 

=head2 Gene cluster info from ITEP

CLdb_dna_segs_make.pl -d CLdb.sqlite -sub I-A  -I DATABASE.sqlite all_I_2.0_c_0.4_m_maxbit

=head2 No broken loci

CLdb_dna_segs_make.pl -da CLdb.sqlite -sub I-A -q "AND loci.operon_status != 'broken'"

=head1 AUTHOR

Nick Youngblut <nyoungb2@illinois.edu>

=head1 AVAILABILITY

sharchaea.life.uiuc.edu:/home/git/CLdb/

=head1 COPYRIGHT

Copyright 2010, 2011
This software is licensed under the terms of the GPLv3

=cut

