use strict;
use Storable ();

package AI::Categorize;

use vars qw($VERSION);
$VERSION = '0.04';

sub new {
  my $package = shift;
  return bless {
                'category_map' => 'AI::Categorize::Map'->new(),
		'results_class' => 'AI::Categorize::Result',
		@_
	       }, $package;
}

sub stopwords {
  my $self = shift;
  if (@_) {
    $self->{stopwords} = { map {$_,1} @_ };
  }
}

sub add_stopword {
  my $self = shift;
  $self->{stopwords}{shift()} = 1;
}

sub stopword_hash {
  my $self = shift;
  return %{$self->{stopwords}};
}

sub extract_words {
  my $self = shift;
  
  my %words;
  pos($_[0]) = 0;
  while ($_[0] =~ /([\w-]+)/g) {
    my $word = lc $1;
    next unless $word =~ /[a-z]/;
    $word =~ s/^[^a-z]+//;  # Trim leading non-alpha characters (helps with ordinals)
    next if exists $self->{stopwords}{$word};
    $words{$word}++;
  }
  return \%words;
}

sub save_state {
  my ($self,$path) = @_;
  Storable::store($self, $path);
}

sub restore_state {
  my ($self,$path) = @_;
  %$self = %{Storable::retrieve($path)};
}

sub F1 { # F1 = 2I/(A+C), I=Intersection, A=Assigned, C=Correct
  my ($self, $assigned, $correct) = @_;
  my %correct = map {$_,1} @$correct;
  my $intersection = 0;
  foreach (@$assigned) {$intersection++ if exists $correct{$_}}
  return 2*$intersection / (@$assigned + @$correct);
}

# Default noop
sub crunch {}

# Abstract methods
sub categorize {
  die sprintf "Class '%s' has not implemented the '%s' method.\n", ref $_[0], (caller(0))[3];
}

sub add_document {
  die sprintf "Class '%s' has not implemented the '%s' method.\n", ref $_[0], (caller(0))[3];
}


###########################################################################
package AI::Categorize::Result;

sub new {
  my $package = shift;
  my $self = bless {@_}, $package;
  return $self;
}

sub in_category {
  my ($self, $cat) = @_;
  return unless exists $self->{scores}{$cat};
  return $self->{scores}{$cat} > $self->{threshold};
}

sub categories {
  my $self = shift;
  return @{$self->{cats}} if $self->{cats};
  $self->{cats} = [sort {$self->{scores}{$b} <=> $self->{scores}{$a}}
		   grep {$self->{scores}{$_} > $self->{threshold}}
		   keys %{$self->{scores}}];
  return @{$self->{cats}};
}

sub scores {
  my $self = shift;
  return @{$self->{scores}}{@_};
}

###########################################################################
package AI::Categorize::Map;

# Manages a mapping between categories & documents.  Can look up
# either by category or by document, so we use a double hash.

sub new {
  my ($package) = @_;
  return bless {'by_cat' => {},
		'by_doc' => {},
	       }, $package;
}

sub clear {
  %{shift()} = (by_cat => {}, by_doc => {});
}

sub add_document {
  my ($self, $doc, $cats) = @_;
  foreach my $cat (@$cats) {
    push @{$self->{by_cat}{$cat}}, $doc;
  }
  @{$self->{by_doc}{$doc}} = @$cats;
}

sub documents_of {
  my ($self, $cat) = @_;
  return @{$self->{by_cat}{$cat} ||= []};
}

sub categories_of {
  my ($self, $doc) = @_;
  return @{$self->{by_doc}{$doc} ||= []};
}

sub categories { return keys %{shift()->{by_cat}} }
sub documents  { return keys %{shift()->{by_doc}} }

1;

__END__

=head1 NAME

AI::Categorize - Automatically categorize documents based on content

=head1 SYNOPSIS

  ### This is one of the categorizers available (see below for more)
  use AI::Categorize::NaiveBayes;
  my $c = new AI::Categorize::NaiveBayes();
  
  ### Supply some training documents so it can learn how to categorize
  $c->stopwords('the','a','and','but','I');  # Ignore these words
  $c->add_document($name, \@categories, $content);
  ... repeat for many documents, then:
  $c->crunch();
  
  $c->save_state('filename'); # Save machine for later use
  
  ### Categorize a new unknown document
  my $c = new AI::Categorize::NaiveBayes();
  $c->restore_state('filename');
  my $results = $c->categorize($content);
  if ($results->in_category('sports')) { ... }
  my @cats = $results->categories;
  my @scores = $results->scores(@cats);

=head1 DESCRIPTION

This module implements several algorithms for automatically guessing
category information of documents based on the category information of
existing documents.  For example, one might categorize incoming email
messages in order to place them into existing mailboxes, or one might
categorize newspaper articles by general topic (business, sports,
etc.).  All of the categorizers learn their categorization rules from
a body of existing pre-categorized documents.

Disclaimer: the results of any of these algorithms are far from
infallible (close to fallible?).  Categorization of documents is often
a difficult task even for humans well-trained in the particular domain
of knowledge, and there are many things a human would consider that
none of these algorithms consider.  These are only statistical tests -
at best they are neat tricks or helpful assistants, and at worst they
are totally unreliable.  If you plan to use this module for anything
important, human supervision is essential.

But this voodoo can be quite fun. =)

=head1 ALGORITHMS

Currently two different algorithms are implemented in this bundle:

  AI::Categorize::NaiveBayes
  AI::Categorize::kNN

These are all subclasses of C<AI::Categorize>.  Please see the
documentation of these individual modules for more details on their
guts and quirks.  The common interface for all the algorithms is
described here.

All these classes are designed to be subclassible so you can modify
their behavior to suit your needs.

=head1 AI::Categorize Methods

=over 4

=item * new()

Creates a new categorizer object (hereafter referred to as C<$c>).
The arguments to C<new()> will depend on which subclass of
C<AI::Categorize> you happen to be using.  See the subclasses'
individual documentation for more info.

=item * $c->stopwords()

=item * $c->stopwords(@words)

Gets (and optionally sets) the list of stopwords.  Stopwords are words
that should be ignored by the categorizer, and typically they are the
most common non-informative words in the documents.  The most common
reason to use stopwords is to reduce processing time.

The stoplist should be set before processing any documents.

=item * $c->stopwords_hash()

Returns the stopwords as the keys of a hash reference.  The
corresponding values are all 1.  Can be useful for quick checking of
whether a word is a stopword.

=item * $c->add_stopword($word)

Adds a single entry to the stopword list.

=item * $c->add_document($name, $categories, $content)

Adds a new training document to the database.  C<$name> should be a
unique string identifying this document.  C<$categories> may be either
the name of a single category to which this document belongs, or a
reference to an array containing the names of several categories.
C<$content> is the text content of the document.

To ease syntax, in the future C<$content> may be allowed
to be given as a path to the document, which will be opened and parsed.

=item * $c->crunch()

After all documents have been added, call C<crunch()> so that the
categorizer can compute some statistics on the training data and get
ready to categorize new documents.

=item * $c->categorize($content)

Processes the text in C<$content> and returns an object blessed into
the C<AI::Categorize::Result> class (hereafter abbreviated as C<$r>).

To ease memory requirements, in the future C<$content> may be allowed
to be passed as a filehandle.

=item * $c->save_state($filename)

At any time you may save the state of the categorizer to a file, so
that you can reload it later using the C<restore_state()> method.

=item * $c->restore_state($filename)

Reads in the categorizer data from $filename, which should have
previously been saved using the C<save_state()> method.

=item * $c->F1(\@assigned_categories, \@correct_categories)

This method computes the F1 measure, which is helpful for evaluating
how well the categorizer did when it assigned categories.  The F1
measure is defined to be 2 times the number of correctly assigned
categories divided by the sum of the number of assigned categories and
correct categories.  

In other words, if A is the set of categories that were assigned by
the system, C is the set of categories that B<should> have been
assigned by the system, and I is the intersection of A and C, then

           2*I
    F1 = -------
          A + C

(Other sources may define F1 as C<2*recall*precision/(recall+precision)>, 
which is equivalent to the above formula but forces division by zero
if either A or C is empty.)

A perfect job categorizing (all correct categories were assigned and
no extras were assigned) will have an F1 score of 1.  A terrible job
categorizing (no overlap between correct & assigned categories) will
have an F1 score of 0.  Medium jobs will be somewhere in between.

=item * $r->extract_words($text)

Returns a reference to a hash whose keys are the words contained in
C<$text> and whose values are the number of times each word appears.
Stopwords are omitted and words are put into canonical form
(lower-cased, leading & trailing non-word characters stripped).

Don't call this method directly, as it is used internally by the
various categorization modules.  However, you may be interested in
subclassing one of the modules and overriding C<extract_words()> to
behave differently.  For instance, you may want to "lemmatize" your
words to remove affixes so that "abominable", "abominableness",
"abominably", "abominate", "abomination", and "abominator" all share a
single entry in the categorizer.

=back

=head1 AI::Categorize::Result Methods

An C<AI::Categorize::Result> object is returned by the
C<$c-E<gt>categorize> method, described above.

=over 4

=item * $r->in_category($category)

Returns true or false depending on whether the document was placed in
the given category.

=item * $r->categories()

Returns an ordered list of the categories the document was placed in,
with best matches first.

=item * $r->scores(@categories)

Returns a list of result scores for the given categories.  Since the
interface is still changing, not very much can officially be said
about the scores, except that a good score is higher than a bad score.
This may change to something like a probability scale, with all
numbers between 0 and 1, and a threshold for membership somewhere in
between.

Please consider the scoring feature somewhat unstable for now.

=back

=head1 CAVEATS

Don't depend on the specific scores given by C<$r-E<gt>scores>.  They
may change in future releases.

The entire categorizer is currently created in memory, which can get
pretty demanding if you have a lot of data.  If this turns out to be a
problem, future versions may try to cache large chunks on disk.  This
would come with a speed penalty.

Finally, I am not an expert in document categorization.  I have
thought about it some, and I have written these modules largely as a
way to concretize my thinking and learn more about the processes.  If
you know of ways to improve accuracy, please let me know.

=head1 TO DO

Idea from obvy: try tying into infobot (purl) to identify IRC moods: 
@moods = qw(indifferent flame_mode pissed inebriated happy sad)

=head1 AUTHOR

Ken Williams, ken@forum.swarthmore.edu

=head1 COPYRIGHT

Copyright 2000-2001 Ken Williams.  All rights reserved.

This library is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=head1 SEE ALSO

perl(1), DBI(3).

"A re-examination of text categorization methods" by Yiming Yang
L<"http://www.cs.cmu.edu/~yiming/publications.html">

Other links from Na'im Tyson:

www.ruf.rice.edu/~barlow/corpus.html (corp. lx.)
ciir.cs.umass.edu (info. ret)
www.georgetown.edu/wilson/IR/IR.html (class in IR @ Georgetown University)
www.research.att.com/~lewis (professional homepage
  of David Lews, one of the leaders in document
  categorization.  you may want to visit his site
  sooner than the others since he has left AT&T research.)


=cut
