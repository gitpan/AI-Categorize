package AI::Categorize::Evaluate;

use strict;
use Benchmark;

sub new {
  my ($package, %args) = @_;
  
  for ('packages') {
    die "Required parameter '$_' missing" unless $args{$_};
  }

  my $self = bless {
		    data_dir => '.',
		    stopwords => [],
		    %args,
		   }, $package;
  
  foreach (@{$self->{packages}}) {
    eval "use $_";
    die $@ if $@;
    $self->{pkgs}{$_}{obj} = $_->new();
  }

  delete $self->{packages};
  return $self;
}

sub shortname { local $_ = $_[1]; s/.*:://; $_ }

sub read_docs {
  my $self = shift;
  return if $self->{training_docs};

  die "No training set specified\n" unless $self->{training_set};
  $self->{training_docs} = $self->read_dir($self->{training_set});

  if ($self->{test_size}) {
    # Test documents are drawn from the training corpus
    $self->{test_size} = int($self->{test_size} * @{$self->{training_docs}} / 100)
      if $self->{test_size} =~ /%$/;

    for (1..$self->{test_size}) {
      push @{$self->{test_docs}}, 
	splice @{$self->{training_docs}}, rand(@{$self->{training_docs}}), 1;
    }
  } elsif ($self->{test_set}) {
    $self->{test_docs} = $self->read_dir($self->{test_set});
  }
  
  print "No test set given - skipping evaluation phase\n" unless @{$self->{test_docs}};
}

sub read_cats {
  my ($self) = @_; 
  return if $self->{docs};
  
  die "Required parameter 'categories' missing" unless $self->{categories};
  local *FH;
  open FH, $self->{categories} or die "Can't open '$self->{categories}': $!";
  while (<FH>) {
    my ($doc, @cats) = split;
    $self->{docs}{$doc} = [@cats];
  }
  close FH;
}

sub read_dir {
  my ($self, $dir) = @_;
  local *DIR;
  opendir DIR, $dir or die "Can't open directory '$dir': $!";
  return [ map {"$dir/$_"} grep {!/^\./} readdir DIR ];
}

sub types { keys %{shift->{pkgs}} }

sub parse_training_data {
  my ($self) = @_;
  local $| = 1;

  print "---------- parsing training data ---------------\n";

  $self->read_docs;
  $self->read_cats;

  foreach my $type ($self->types) {
    my $i;
    my $start = new Benchmark;
    print "\n$type:\n";
    my $c = $self->{pkgs}{$type}{obj};
    
    $c->stopwords(@{$self->{stopwords}});
    
    foreach my $path ( @{$self->{training_docs}} ) {
      (my $file = $path) =~ s#.*/##;
      
      warn "Warning: no categories found for document '$file'\n" unless $self->{docs}{$file};
      my $cats = $self->{docs}{$file} || [];

      open FILE, $path or die "$path: $!";
      $c->add_document($file, $cats, join '', <FILE>);
      close FILE;

      print "." unless $i++ % 5;
    }
    $c->save_state("$self->{data_dir}/".$self->shortname($type).'-1');
    my $end = new Benchmark;
    print "\nRunning time: ", timestr(timediff($end, $start)), " for $i documents.\n";
  }
}

sub crunch {
  my ($self) = @_;
  local $| = 1;

  print "---------- crunching training data ---------------\n";

  foreach my $type ($self->types) {
    my $start = new Benchmark;
    print "\n$type:\n";
    my $c = $self->{pkgs}{$type}{obj};
    $c->restore_state("$self->{data_dir}/".$self->shortname($type).'-1');
    $c->crunch;
    $c->save_state("$self->{data_dir}/".$self->shortname($type).'-2');
    my $end = new Benchmark;
    print "\nRunning time: ", timestr(timediff($end, $start)), "\n";
  }
}

sub categorize_test_set {
  my ($self) = @_;

  print "\n---------- categorizing test data ---------------\n";

  $self->read_docs;
  $self->read_cats;

  foreach my $type ($self->types) {
    my $i;
    my $start = new Benchmark;
    print "\n$type:\n";
    my $c = $self->{pkgs}{$type}{obj};
    $c->restore_state("$self->{data_dir}/".$self->shortname($type).'-2');

    foreach my $path (@{$self->{test_docs}}) {
      (my $file = $path) =~ s#.*/##;
      print " Categorizing '$file'\n";

      open FILE, $path or die "$path: $!";
      my $r = $c->categorize(join '', <FILE>);
      close FILE;
      
      my @cats = $r->categories;
      my @scores = $r->scores(@cats);

      foreach (0..$#cats) {
	print "   $cats[$_]: $scores[$_]\n";
      }
      print "\nReal Categories:\n";

      warn "Warning: no categories found for document '$file'\n" unless $self->{docs}{$file};
      my $real_cats = $self->{docs}{$file} || [];
      foreach (@$real_cats) {
	print "  + $_\n";
      }

      my $f1 = $c->F1(\@cats, $real_cats);
      print "F1 = $f1\n";

      print "-----------\n\n";
      $i++;
    }
    my $end = new Benchmark;
    print "\nRunning time: ", timestr(timediff($end, $start)), " for $i documents.\n";
  }
}

sub intersection {
  my ($self, $a1, $a2) = @_;
  my %hash;
  @hash{@$a1} = ();
  my @result = grep {exists $hash{$_}} @$a2;
  return @result;  # Will return number of elements in scalar context
}

1;

__END__

=head1 NAME

AI::Categorize::Evaluate - Automate and compare AI::Categorize modules

=head1 SYNOPSIS

  use AI::Categorize::Evaluate;
  my $e = new AI::Categorize::Evaluate
    (
     'packages'     => ['AI::Categorize::NaiveBayes','AI::Categorize::kNN'],
     'training_set' => 'text_dir',
     'test_set'     => 'test_dir',
     'categories'   => 'categories.txt',
     'stopwords'    => [qw(the a of to is that you for and)],
     'data_dir'     => 'data',
    );
  
  $e->parse_training_data;
  $e->crunch;
  $e->categorize_test_set;

=head1 DESCRIPTION

This module helps facilitate automated testing and comparison of
AI::Categorize modules.  It can be used to compare the speed of
execution of various stages of the categorizers, and/or to compare the
results to see which module is more accurate at categorizing various
documents.

=head1 METHODS

=head2 new()

This method creates a new C<AI::Categorize::Evaluate> object.  Several
parameters may be passed to the C<new()> method as key/value pairs:

=over 4

=item * packages

Required.  A list reference containing the names of the packages you
wish to load and evaluate.  The modules will be automatically loaded by
searching @INC.

=item * training_set

Required for C<parse_training_data()>.  This parameter specifies the
directory in which the training documents may be found.

=item * test_set

=item * test_size

Required for C<categorize_test_set()>, optional for
C<parse_training_data()>.  These parameters specify where to find the
test documents that will be used to evaluate the performance of the
categorizers.  C<test_set> simply specifies the directory that contains
the test documents.  Alternatively, C<test_size> can be used to select
a certain number of documents at random from the training set
(specified with the C<training_set> parameter).  That number can be
given either as a simple integer, or as a figure like C<5%> to use a
certain percentage of the training documents.

=item * categories

Required for C<parse_training_data()> and C<categorize_test_set()>
methods.  This parameter specifies the location of an existing text
file which contains the mapping between categories and documents.  It
should contain category information for all the training documents and
all the test documents.  The format of the file is as follows:

  document1     category1   category2   category3  ...
  document2     category3   category7   category4  ...
  .
  .
  .


The amount of whitespace separating document and category names is
arbitrary.  Because of the format of the file, whitespace is not
allowed in the document or category names (if this becomes a problem,
perhaps Text::CSV could be used in the future).

=item * stopwords

Optional (default []).  A list of words to ignore when parsing and
categorizing documents.  This will be passed to the stopwords() method
of the individual categorizers.

=item * data_dir

Optional (default '.').  Specifies the directory in which large data
files will be created during the evaluation process.

=back


=head2 parse_training_data()

Reads all the training documents and feeds them to the categorizers.  

=head2 crunch()

=head2 categorize_test_set()


=head1 AUTHOR

Ken Williams, ken@forum.swarthmore.edu

=head1 COPYRIGHT

Copyright 2000-2001 Ken Williams.  All rights reserved.

This library is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=head1 SEE ALSO

perl(1).   AI::Categorize(3)

=cut
