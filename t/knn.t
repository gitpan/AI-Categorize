# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl test.pl'

######################### We start with some black magic to print on failure.

BEGIN { $| = 1; print "1..5\n"; }
END {print "not ok 1\n" unless $loaded;}
use AI::Categorize::kNN;

$loaded = 1;
&report_result(1);

######################### End of black magic.

my $c = new AI::Categorize::kNN();
&report_result($c);

$c->stopwords(qw(are be in of and));
&report_result(1);

$c->add_document('doc1', 'farming', 'Sheep are very valuable in farming.');
$c->add_document('doc2', 'farming', 'Farming requires many kinds of animals.');
$c->add_document('doc3', 'vampire', 'Vampires drink blood and may be staked.');
$c->add_document('doc4', 'vampire', 'Vampires cannot see their images in mirrors.');

$c->crunch;

my $r = $c->categorize('I would like to begin farming sheep.');
print "Categories: ", join(', ', $r->categories), "\n";
&report_result(($r->categories)[0] eq 'farming');

$r = $c->categorize("I see that many vampires may have eaten my beautiful daughter's blood.");
print "Categories: ", join(', ', $r->categories), "\n";
&report_result(($r->categories)[0] eq 'vampire');


###########################################################
sub report_result {
  my $bad = !shift;
  use vars qw($TEST_NUM);
  $TEST_NUM++;
  print "not "x$bad, "ok $TEST_NUM\n";
  
  print $_[0] if ($bad and $ENV{TEST_VERBOSE});
}

__END__

my $dir = 'text';
opendir DIR, $dir or die $!;
while (my $file = readdir DIR) {
  

  next if $file =~ /^\.+$/;
  open FILE, "$dir/$file" or die "$dir/$file: $!";

  $file =~ s/\.txt$//;
  my $cats = $dbh->selectcol_arrayref("SELECT category FROM bayes_old.cat_map WHERE document=?",undef, $file);
  warn "No cats for $file" unless @$cats;

#  $c->add_document($file, $cats, join '', <FILE>);
#  print ".\n" unless $i++ % 100;
}

