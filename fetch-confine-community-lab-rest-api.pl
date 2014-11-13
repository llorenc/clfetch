#!/usr/bin/perl -w
##
## get Resource Devices' info using community-lab REST-API
## (c) Llorenç Cerdà-Alabern, November 2014.

use JSON ;
use Getopt::Long; Getopt::Long::Configure ("gnu_getopt");
use utf8 ;
binmode(STDOUT, ":utf8");
use Data::Dumper qw(Dumper);

##
## prototypes
##
sub usage() ;
sub escape_ipv6($) ;
sub get_header($$) ;
sub get_content_to_file($$) ;
sub get_json_from_file($) ;
sub download() ;
sub showmembers() ;
sub membercontent() ;

##
## variables
##
my $node_list_file = 'node_list.json' ;
my $api_url = 'https://[fdf5:5351:1dfd::2]/api/' ;
my $data_dir = "data" ;

##
## options
##
my $nodeid = 0 ;
my $optsgen =
  {
   'help|h' => "this help.",
   'nodeid:s' => "only this nodeid, 0 all (default $nodeid).",
   'showmembers' => "show members.",
   'membercontent:s' => "print content of member in list.",
   'download' => "download files, skip downloaded previously.",
   'forcedownload' => "download files, overwrite downloaded previously."
  } ;

##
## body script
##

## process the options
my $command = $0 ; $command =~ s%.*/(\w+)%$1% ;
my(%opts, $res) ;
eval('$res = GetOptions(\\%opts, qw(' . join(' ', keys %{$optsgen}) . '))') ;
$nodeid = $opts{nodeid} if $opts{nodeid} ;
usage() if ((!$res) || $opts{help} || !keys %opts) ;
download() if ($opts{download} || $opts{forcedownload}) ;
showmembers() if $opts{showmembers} ;
membercontent() if $opts{membercontent} ;
exit(0) ;

##
## functions
##
sub download() {
  ## 1. Retrieve the registry API base URI
  my $node_list_uri = get_header($api_url, "http://confine-project.eu/rel/server/node-list") ;
  ## 2. Retrieve the node list.
  get_content_to_file($node_list_uri, $node_list_file) ;
  ## read the node list from file.
  my $node_list_json = get_json_from_file("$data_dir/$node_list_file") ;
  my $count = 0 ;
  my $number = ($nodeid+0) ? split(/,/, $nodeid) : scalar @{$node_list_json} ;
  ## for each node
  foreach my $node (@{$node_list_json}) {
    if(!($nodeid+0) || ($nodeid =~ /\b$node->{id}\b/)) {
      $count++ ;
      ## 1. Retrieve its URI and look for the node API base URI
      print "-- $count/$number: $node->{uri}\n" ;
      my $node_api_base_uri = get_header($node->{uri}, "http://confine-project.eu/rel/server/node-base") ;
      print "node_api_base_uri: $node_api_base_uri\n" ;
      # 2. Retrieve the node API base URI and look for the node URI
      my $node_uri = get_header($node_api_base_uri, "http://confine-project.eu/rel/node/node") ;
      my $node_json_file = "node-$node->{id}.json" ;
      if ($node_uri ne "") {
	print "node_uri: $node_uri\n" ;
	get_content_to_file($node_uri,  $node_json_file) ;
      }
#      exit if ($node->{id} == $nodeid) ;
    }
  }
}

sub showmembers() {
  my $node_json_file ;
  if($opts{nodeid}) {
    $node_json_file = "$data_dir/node-" . $opts{nodeid} . ".json" ;
  } else {
    my @files = glob("$data_dir/node-*.json") ;
    $node_json_file = $files[0] ;
  }
  print "using file '$node_json_file'\n" ;
  if(-e $node_json_file) {
    my $node_json = get_json_from_file($node_json_file) ;
    foreach my $key (keys %{$node_json}) {
      if (ref $node_json->{$key} eq ref {}) {
	foreach my $kkey (keys %{$node_json->{$key}}) {
	  print "$key.$kkey " ;
	}
	print "\n" ;
      } else {
	print "$key\n" ;
      }
    }
  }
}

sub get_id_from_name($) {
  my $name = shift ;
  $name =~ s/^\D*(\d+)\D.*$/$1/g ;
  return $name ;
}

sub JSON::PP::sorter {
    # Sort hash keys alphabetically.
    if(($JSON::PP::a =~ /^\d+$/) && ($JSON::PP::b =~ /^\d+$/)) {
      $JSON::PP::a <=> $JSON::PP::b ;
    } else {
      $JSON::PP::a cmp $JSON::PP::b ;
    }
} ;

sub membercontent() {
  my $json ;
  my @files ;
  if($opts{nodeid}) {
    for my $id (split /,/, $opts{nodeid}) {
      my $fname = "$data_dir/node-${id}.json" ;
      if(-e $fname) {
	push @files, $fname ;
      } else {
	warn "$fname not fount\n" ;
      }
    }
  } else {
    @files = glob("$data_dir/node-*.json") ;
  }
  my $keys ;
  for my $k (split /,/, $opts{membercontent}) {
    if($k =~ /\./) {
      my @kk = split /\./, $k ;
      $keys->{$kk[0]}->{$kk[1]} = 1 ;
    } else {
      $keys->{$k} = 1 ;
    }
  }
  for my $node_json_file (@files) {
    my $node_json = get_json_from_file($node_json_file) ;
    foreach my $k (keys %{$keys}) {
      if(keys %{$keys->{$k}}) {
	foreach my $kk (keys %{$keys->{$k}}) {
	  $json->{$node_json->{id}}->{$k}->{$kk} = $node_json->{$k}->{$kk} if $node_json->{$k}->{$kk} ;
	}
      } else {
	$json->{$node_json->{id}}->{$k} = $node_json->{$k} if $node_json->{$k} ;
      }
    }
  }
  print to_json($json, {pretty => 1, sort_by => "sorter"}) ;
}

sub escape_ipv6($) {
  my $ipv6 = shift ;
  if($ipv6 =~ /[^\\]\]/) {
    $ipv6 =~ s/\[/\\[/ ; $ipv6 =~ s/\]/\\]/ ;
  }
  return($ipv6) ;
}

sub get_header($$) {
  my ($url, $rel) = (shift, shift) ;
  $url = escape_ipv6($url) ;
  my $header = qx(curl --silent --head --insecure -6 '$url') ;
  for my $line (split /\n/, $header) {
    chomp $line ;
    return $line if $line =~ s#^.*(https*:\S+)>; ...="$rel.*$#$1# ;
  }
  if(!($url =~ /\/$/)) { # try adding a slash
    $url =~ s/$/\// ;
    return get_header($url, $rel) ;
  }
  warn "'$rel' not found in '$url'. The header was:\n$header\n" ;
  return "" ;
}

sub get_content_to_file($$) {
  if(! -d "$data_dir") {
    print "creating directory '$data_dir'" ;
    mkdir $data_dir ;
  }
  my($url, $file_name) = (shift, shift) ;
  if(!$opts{forcedownload} && -e "$data_dir/$file_name") {
    print "'$data_dir/$file_name' already downloaded, skypping\n" ;
  } else {
    $url = escape_ipv6($url) ;
    print "downloading '$file_name' from '$url''\n" ;
    qx(curl --insecure -6 '$url' --output '$data_dir/$file_name') ;
  }
}

sub get_json_from_file($) {
  local $/;
  my $file_name = shift ;
  die "file not found '$file_name\n" if ! -e "$file_name" ;
  open FILE, "<$file_name" or die $!;
  binmode FILE;
  my $file_content = <FILE> ;
  die "file empty\n" if $file_content =~ /^\s*$/ ;
  close FILE ;
  return(JSON->new->relaxed->decode($file_content)) ;
}

sub usage() {
  my $msg =
"USAGE: $command <some option>
 Options
" ;
  for my $opt (sort {$a cmp $b} keys %{$optsgen}) {
    my $topt = $opt ;
    for(my $t = length($topt); $t <=10; ++$t){
      $topt .= " " ;
    }
    $msg .= "  $topt " . $optsgen->{$opt} . "\n" ;
  }
  print $msg ;
  print <<EOF;
WORKFLOW EXAMPLE
# 1. Download rest api json files. It may take some time. Need to do
#    it only once. Use '$command --forcedownload' to refresh files.
$command --download
# 2. Retrive member names.
$command --showmembers
# 3. Retrive some members:
$command --membercontent name,uri,addrs.local_ipv6,addrs.local_ipv4
$command --membercontent name,uri,addrs.local_ipv6,addrs.local_ipv4 --nodeid 140,150
EOF
  exit(1) ;
}
