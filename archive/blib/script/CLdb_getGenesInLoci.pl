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

my ($verbose, $database_file, $quiet);
my ($all_genes, $existing, $conflicting);
my (@subtype, @taxon_id, @taxon_name);
my $query = "";
GetOptions(
	   "database=s" => \$database_file,
	   "subtype=s{,}" => \@subtype,
	   "taxon_id=s{,}" => \@taxon_id,
	   "taxon_name=s{,}" => \@taxon_name,
	   "sql=s" => \$query,
	   "all" => \$all_genes, 				# get all genes (including existing?; overwriting conflicts w/ existing entry). [FALSE]
	   "existing" => \$existing, 			# check for existing, if yes, do not write (unless '-a'). [TRUE]
	   "conflicting" => \$conflicting, 		# write out both entries for conflicts? [FALSE]
	   "verbose" => \$verbose,				# TRUE
	   "quiet" => \$quiet, 					# turn off warnings
	   "help|?" => \&pod2usage # Help
	   );

### I/O error & defaults
die " ERROR: provide a database file name!\n"
	unless $database_file;
die " ERROR: cannot find database file!\n"
	unless -e $database_file;
my $db_path = get_database_path($database_file);
my $genbank_path = "$db_path/genbank";
$genbank_path = File::Spec->rel2abs($genbank_path);


### MAIN
# connect 2 db #
my %attr = (RaiseError => 0, PrintError=>0, AutoCommit=>0);
my $dbh = DBI->connect("dbi:SQLite:dbname=$database_file", '','', \%attr) 
	or die " Can't connect to $database_file!\n";

# joining query options (for table join) #
my $join_sql = "";
$join_sql .= join_query_opts(\@subtype, "subtype");
$join_sql .= join_query_opts(\@taxon_id, "taxon_id");
$join_sql .= join_query_opts(\@taxon_name, "taxon_name");

# getting loci start - end from loci table (& genbank file names)
my $loci_se_r = get_loci_start_end($dbh, $query, $join_sql);

# getting CDS info for CDS features in loci regions #
my $loci_tbl_r = call_genbank_get_region($loci_se_r, $genbank_path);

# determine if CDS are already in gene table #
## if exists & '-a', existing entry written ## 
check_exists_in_gene_table($dbh, $loci_tbl_r, $all_genes, $conflicting) unless $existing; 

# determine if CDS are in operons #
check_in_operon($loci_se_r, $loci_tbl_r);

# write locus-gene table #
write_loci_tbl($loci_tbl_r);

# disconnect #
$dbh->disconnect();
exit;


### Subroutines
sub check_exists_in_gene_table{
# determine if CDS are already in gene table #
## if exists & '-a', existing entry written ## 
	my ($dbh, $loci_tbl_r, $all_genes, $conflicting) = @_;
	
	# query gene table #
	my $query = "SELECT Locus_ID,Gene_Start,Gene_End,Gene_ID,Gene_Alias,Gene_Length__AA,In_Operon from Genes";
	my $genes_r = $dbh->selectall_arrayref($query);	

	# loading hash w/ entries: locus=>gene_id #
	my %exists;
	map{ $exists{$$_[0]}{$$_[3]} = [@$_[1..$#$_]] } @$genes_r;
	
	# checking for existing #
	foreach my $locus (sort keys %$loci_tbl_r){
		foreach my $feat (keys %{$loci_tbl_r->{$locus}}){
			my $gene_id = ${$loci_tbl_r->{$locus}{$feat}}[2];

			if(exists $exists{ $locus }{ $gene_id } ){		# existing entry for gene
				# just conflicting entries 
				if($conflicting){				
					$loci_tbl_r->{$locus}{"N$feat"} = $exists{$locus}{$gene_id};
					}
				# removing existing gene
				else{		
					delete $loci_tbl_r->{$locus}{$feat};				
					# replacing existing 
					if($all_genes){					
						$loci_tbl_r->{$locus}{$feat} = $exists{$locus}{$gene_id};
						}
					}
				}
			else{
				delete $loci_tbl_r->{$locus}{$feat} if $conflicting;		# just 
				}
			}
		}
		#print Dumper %$loci_tbl_r; exit;
	}

sub write_loci_tbl{
# writing out loci table for manual editting of aliases #
	my ($loci_tbl_r) = @_;

	print join("\t", qw/Locus_ID Gene_Id Gene_start Gene_end Gene_length__AA In_Operon Gene_Alias Sequence/), "\n";
	foreach my $loci (keys %$loci_tbl_r){
		foreach my $feature (keys %{$loci_tbl_r->{$loci}}){
			unless (${$loci_tbl_r->{$loci}{$feature}}[2] =~ /fig\|.+peg/){		# db_xref must be fig|.+peg
				print STDERR " WARNING: Locus$loci -> $feature does not have a FIG-PEG ID in a db_xref tag!\n"
					unless $quiet;
				next;
				}
			
			# length already found? #
			my ($len_AA, $seq);
			if(${$loci_tbl_r->{$loci}{$feature}}[4] =~ /^\d+$/){			# existing entry; no sequence
				$len_AA = ${$loci_tbl_r->{$loci}{$feature}}[4];
				if($conflicting){ $seq = "existing_entry"; }
				else{ $seq = ""; }
				}
			else{ 
				$len_AA = length ${$loci_tbl_r->{$loci}{$feature}}[4]; 
				$seq = ${$loci_tbl_r->{$loci}{$feature}}[4];
				}
			
			# writing line #
			print join("\t", "cli.$loci", 
				${$loci_tbl_r->{$loci}{$feature}}[2], 			# Gene_id (db_xref)
				@{$loci_tbl_r->{$loci}{$feature}}[(0..1)], 		# start, end 
				$len_AA, 										# length (AA)
				${$loci_tbl_r->{$loci}{$feature}}[5], 			# In Operon	
				${$loci_tbl_r->{$loci}{$feature}}[3],
				$seq											# sequence
				), "\n";
			}
		}
	}

sub check_in_operon{
# checing whether CDS features are in the designated operon locations #
	my ($loci_se_r, $loci_tbl_r) = @_;
	
	#print Dumper $loci_tbl_r; exit;
	
	foreach my $locus (keys %$loci_tbl_r){
		foreach my $feature (keys %{$loci_tbl_r->{$locus}}){
			die " LOGIC ERROR: $!\n" unless 
				exists $loci_se_r->{$locus};
			
			# defining start - end #
			## f = feature; o = operion; c = crispr array ##
			my $f_start = int ${$loci_tbl_r->{$locus}{$feature}}[0];
			my $f_end = int ${$loci_tbl_r->{$locus}{$feature}}[1];
			
			my $o_start = ${$loci_se_r->{$locus}}[3];
			my $o_end = ${$loci_se_r->{$locus}}[4];			
			
			my $c_start = ${$loci_se_r->{$locus}}[5];
			my $c_end = ${$loci_se_r->{$locus}}[6];
			
				#print Dumper $f_start, $f_end, $o_start, $o_end, $c_start, $c_end; 

			# making all on the + strand #
			($f_start, $f_end) = set_to_pos_strand($f_start, $f_end);
			($o_start, $o_end) = set_to_pos_strand($o_start, $o_end);
			($c_start, $c_end) = set_to_pos_strand($c_start, $c_end) if $c_start && $c_end;		
			
			# determining location #
			## gene must fall in operon, without falling into crispr array ##
			if($f_start >= $o_start && $f_end <= $o_end){	# gene in operon
				if($c_start && $c_end){					# check for overlap w/ CRISPR array if present
					if( ($f_start < $c_start && $f_end < $c_end) ||
						($f_start > $c_start && $f_end > $c_end) ){			# not in crispr array
						push(@{$loci_tbl_r->{$locus}{$feature}}, "yes");
						}
					else{ push(@{$loci_tbl_r->{$locus}{$feature}}, "no"); }	# in crispr array, so not defined as in operon				
					}
				else{ push(@{$loci_tbl_r->{$locus}{$feature}}, "yes"); }	# in operon, no CRISPR array
				}
			else{ push(@{$loci_tbl_r->{$locus}{$feature}}, "no"); }		# no in operon
			}
		}
		#print Dumper %$loci_tbl_r; exit;
	}

sub set_to_pos_strand{
# setting all start-end so start is <= end #
	my ($start, $end) = @_;
	if ($start > $end){ return $end, $start; }
	else{ return $start, $end; }
	}

sub get_database_path{
	my $database_file = shift;
	$database_file = File::Spec->rel2abs($database_file);
	my @parts = File::Spec->splitpath($database_file);
	return $parts[1];
	}

sub call_genbank_get_region{
# calling genbank_get_region to get CDS info from genbank files #
	my ($loci_se_r, $genbank_path) = @_;
	
	my %loci_tbl;
	foreach my $locus (keys %$loci_se_r){
		my $genbank_file = join("/", $genbank_path, ${$loci_se_r->{$locus}}[2]);
		die " ERROR: $genbank_file not found!\n"
			unless -e $genbank_file;
		
		my $cmd; 
		my $start = ${$loci_se_r->{$locus}}[0];
		my $end = ${$loci_se_r->{$locus}}[1];
		if($start <= $end){
			$cmd = "genbank_get_region.pl -r $start $end < $genbank_file |";
			}
		else{
			$cmd = "genbank_get_region.pl -r $start $end < $genbank_file |";			
			}
			
		print STDERR "$cmd\n" unless $verbose;
		open PIPE, $cmd or die $!;
		
		my %header;
		my @col_sel = qw/start end db_xref product translation/;
		while(<PIPE>){
			chomp;
		
			if($. == 1){
				tr/A-Z/a-z/;					# header to lower case
				my @line = split /\t/;			
				for my $i (0..$#line){
					$header{$line[$i]} = $i;
					}
				}
			else{
				my @line = split /\t/;			

				# parsing & scrubing fig/peg # (eg. 'ITEP:') #
				my $fig_peg;
				my @fig_peg = split /::/, $line[$header{"db_xref"}];
				map{ $line[$header{"db_xref"}] = $_ if /fig\|.+peg\.\d+/ } @fig_peg;		# should only be 1 fig-peg
				$line[$header{"db_xref"}] =~ s/^[^:]+://;
			
				# checking for existence of columns of interest #
				my $next_bool;
				foreach my $col (@col_sel){
					unless($line[$header{$col}]){
						print STDERR " WARNING: \"$col\" tag not found in feature: $_! Skipping feature\n";						
						$next_bool = 1; last;
						}
					}
				next if $next_bool;
			
				# loading hash; selecting just tags of interest #
				$loci_tbl{$locus}{$line[$header{feature_num}]} = [@line[@header{@col_sel}]]; 	# locusID=>feature_num = feature
				}
			}
		close PIPE;
		}
		#print Dumper %loci_tbl; exit;
	return \%loci_tbl;		#  locusID=>feature_num = \@feature
	}

sub get_loci_start_end{
# getting locus start and locus end from loci table in db #
	my ($dbh, $query, $join_sql) = @_;
	
	my %loci_se;
	my $cmd = "SELECT Locus_id, Locus_start, Locus_end, Genbank_File, Operon_start, Operon_end, Array_Start, Array_End from loci where (Operon_start is not null or Operon_end is not null) $join_sql $query";

	my $loci_se_r = $dbh->selectall_arrayref($cmd);	
	die " ERROR: no locus start-end values found!\n" unless $loci_se_r;	

	foreach my $row (@$loci_se_r){
		$loci_se{$$row[0]} = [@$row[1..$#$row]];
		}
		#print Dumper %loci_se; exit;
	return \%loci_se;
	}

sub join_query_opts{
# joining query options for selecting loci #
	my ($vals_r, $cat) = @_;

	return "" unless @$vals_r;	
	
	map{ s/"*(.+)"*/"$1"/ } @$vals_r;
	return join("", " AND $cat IN (", join(", ", @$vals_r), ")");
	}


__END__

=pod

=head1 NAME

CLdb_getGenesInLoci.pl -- getting all genes in CRISPR Loci; output is a table of gene information

=head1 SYNOPSIS

CLdb_getGenesInLoci.pl [flags] 

=head2 Required flags

=over

=item -database  <char>

CLdb database.

=back

=head2 Optional flags

=over

=item -exist  <bool>

Do not write any genes already existing in the Genes table (unless '-a' used). [TRUE]

=item -all  <bool>

All genes defined by the Loci table are written. 
Any existing entries written in place of new entry.
Not compatible with '-c' [FALSE]

=item -conflict  <bool>

Just write out genes that are conflicting
(new and old versions). Not compatible with '-a' [FALSE]

=item -sql  <char>

sql to refine loci table query (see EXAMPLES). 

=item -quiet  <bool>

Turn off all warnings. [FALSE]

=item -verbose  <bool>

Verbose output. [TRUE]

=item -help  <bool>

This help message.

=back

=head2 For more information:

perldoc CLdb_getGenesInLoci.pl

=head1 DESCRIPTION

Get all CDS features from >= genbanks that fall
into CRISPR loci. 

The output can be piped directly into
CLdb_loadGenes.pl or the aliases (or other values)
can be edited first.

Genbank files must be in $CLdb_HOME/genbank/

=head2 Existing genes in Genes table ('-e', '-a', '-c')

By default, only new genes (ie. not found already in
Genes table) are written. This is to
preserve the existing alias values, which may 
have been manually editted. 

All gene entries (new & existing) can be written
using '-a'. To view conflicting gene entries,
use '-c'. For '-c', existing entries will have 'existing_entry'
in the 'Sequence' column.

=head2 In_Operon

Genes are designated as falling in the CAS operon
('In_Operon' field in DB) if they fall inside
the designated operon range (designated in Loci table)
but not inside the CRISPR array range (also 
designated in Loci table).

=head2 WARNING:

CDS features in genbanks must have db_xref tags with 
the fig|peg ID (example: "fig|6666666.40253.peg.2362");
otherwise, the CDS will not be written to the output table.
Extra information can come before 'fig' (eg. 'ITEP:' or 'SEED:'),
but it must end with a colon.

=head2 Requires:

genbank_get_region.pl

=head1 EXAMPLES

=head2 Basic usage:

CLdb_getGenesInLoci.pl -d CRISPR.sqlite > gene_info.txt

=head2 Direct loading to CRISPR database

CLdb_getGenesInLoci.pl -d CRISPR.sqlite | CLdb_loadGenes.pl -d CRISPR.sqlite

=head2 Refining query to just the 'I-B' subtype

CLdb_getGenesInLoci.pl -d CRISPR.sqlite -s "WHERE subtype='I-B'"

=head2 Refining query to just taxon '6666666.40253'

CLdb_getGenesInLoci.pl -d CRISPR.sqlite -s "WHERE taxon_id='6666666.40253'"

=head2 Write out all entries (new & old; on conflict: old entry is written)

CLdb_getGenesInLoci.pl -d CRISPR.sqlite -a

=head2 Write out all conflicting entries 

CLdb_getGenesInLoci.pl -d CRISPR.sqlite -c

=head1 AUTHOR

Nick Youngblut <nyoungb2@illinois.edu>

=head1 AVAILABILITY

sharchaea.life.uiuc.edu:/home/git/CLdb/

=head1 COPYRIGHT

Copyright 2010, 2011
This software is licensed under the terms of the GPLv3

=cut

