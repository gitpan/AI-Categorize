package AI::Categorize::Evaluate;

use strict;
use Benchmark;
use Storable ();


=begin data model

$self = 
  {
   tests => 
   [
    {
     pkg => 'AI::Categorize::kNN',
     name => '...', # visual id
     args => [...],
     c => $c,
     test_docs => {...},
     training_docs => [...],
     stopwords => [...],
     categories => {...},
    },
    { ... },
    ...
   ],
   # 'defaults' specifies global parameters, so they can be shared among several tests
   defaults =>
   {
    test_docs => {...},
    training_docs => [...],
    stopwords => [...],
    categories => {...},
   }
   data_dir => '...',
  };

=end

=cut

sub new {
  my ($package, %args) = @_;
  
  my $self = bless 
    {
     tests => [],
     data_dir => ($args{data_dir} || '.'),
    }, $package;
  
  $self->{defaults} = $self->new_instance(undef, %args);
  $self->{iterations} = $args{iterations} || 1;

  if ($args{packages}) {
    my %more_args = $args{test_size} ? (test_size => $args{test_size}) : ();
    foreach my $pkg (@{$args{packages}}) {
      $self->add($pkg, %more_args) for 1..$self->{iterations};  # Use default args
    }
  }
  for ('save', 'verbose') {
    $self->{$_} = $args{$_} if $args{$_};
  }

  return $self;
}

sub add {
  my ($self, $pkg, %args) = @_;
  eval "use $pkg";
  die $@ if $@;

  my $new_test;
  push @{$self->{tests}}, $new_test = $self->new_instance($self->{defaults}, %args);
  $new_test->{pkg} = $pkg;
  $new_test->{name} = sprintf("%02d-", scalar @{$self->{tests}}) . $self->shortname($pkg);
  $new_test->{args} ||= [];
  $new_test->{c} = $pkg->new(@{$new_test->{args}});

  return $new_test;
}

sub new_instance {
  my ($self, $default, %args) = @_;
  my $struct = {};

  if ($args{training_set}) {
    $struct->{training_docs} = $self->read_dir($args{training_set});
  } elsif ($default) {
    $struct->{training_docs} = $default->{training_docs};
  }

  if ($args{test_set}) {
    $struct->{test_docs} = {map {$_,1} @{$self->read_dir($args{test_set})}};
  } elsif ($args{test_size}) {
    die "No training set specified\n" unless $struct->{training_docs};
    $struct->{test_docs} = $self->random_subset($struct->{training_docs}, $args{test_size});
  } elsif ($default) {
    $struct->{test_docs} = $default->{test_docs};
  }

  for ('categories') {
    if ($args{$_})   { $struct->{$_} = $self->read_cats($args{$_}) }
    elsif ($default) { $struct->{$_} = $default->{$_}              }
  }

  for ('stopwords', 'args') {
    if ($args{$_})   { $struct->{$_} = $args{$_}      }
    elsif ($default) { $struct->{$_} = $default->{$_} }
    else             { $struct->{$_} = []             }
  }

  return $struct;
}

sub shortname { local $_ = $_[1]; s/.*:://; $_ }

sub random_subset {
  my ($self, $set, $size) = @_;

  $size = int($size * @$set / 100) if $size =~ /%$/;

  die ("$size documents needed for testing, but only " . @$set . " docs in training set - aborting")
    if $size >= @$set;

  warn "Warning: no documents in test set\n" unless $size;

  my $result = {};
  for (1..$size) {
    my $random = $set->[ rand @$set ];
    redo if exists $result->{$random};
    $result->{$random} = 1;
  }
  
  return $result;
}

sub read_cats {
  my ($self, $path) = @_; 
  
  local *FH;
  open FH, $path or die "Can't open '$path': $!";
  my $result = {};
  local $_;
  while (<FH>) {
    my ($doc, @cats) = split;
    $result->{$doc} = [@cats];
  }
  close FH;
  return $result;
}

sub read_dir {
  my ($self, $dir) = @_;
  local *DIR;
  opendir DIR, $dir or die "Can't open directory '$dir': $!";
  return [ map {"$dir/$_"} grep {!/^\./} readdir DIR ];
}

sub parse_training_data {
  my ($self) = @_;
  local $| = 1;

  print "---------- parsing training data ---------------\n";

  foreach my $test (@{$self->{tests}}) {
    my $i;
    my $start = new Benchmark;
    print "\n$test->{name}:\n";
    my $c = $test->{c};
    
    $c->stopwords(@{$test->{stopwords}});
    
    foreach my $path ( @{$test->{training_docs}} ) {
      next if $test->{test_docs}{$path}; # Skip docs used in testing
      (my $name = $path) =~ s#.*/##;
      
      warn "Warning: no categories found for document '$name'\n" unless $test->{categories}{$name};
      my $cats = $test->{categories}{$name} || [];
	
      open FILE, $path or die "$path: $!";
      $c->add_document($name, $cats, join '', <FILE>);
      close FILE;
      
      print "." unless $i++ % 5;
    }

    my $end = new Benchmark;
    print "\nRunning time: ", timestr(timediff($end, $start)), " for $i documents.\n";
  }
  $self->save();
}

sub show_test_docs {
  my ($self) = @_;
  local $| = 1;

  print "---------- test docs: ---------------\n";

  foreach my $test (@{$self->{tests}}) {
    print "\n$test->{name}:\n";
    print " $_ \n" foreach keys %{$test->{test_docs}};
  }
}


sub save {
  my ($self) = @_;
  return unless $self->{save};
  
  (my $subname = (caller(1))[3]) =~ s/.*:://;
  my $file = "$self->{save}-$subname";
  warn "Saving $file\n";
  Storable::store($self->{tests}, $file);
}

sub load {
  my ($self, $prev) = @_;
  return unless $self->{save};
  
  my $file = "$self->{save}-$prev";
  warn "Loading $file\n";
  $self->{tests} = Storable::retrieve($file);
}

sub crunch {
  my ($self) = @_;
  local $| = 1;

  print "---------- crunching training data ---------------\n";

  $self->load('parse_training_data');
  foreach my $test (@{$self->{tests}}) {
    my $start = new Benchmark;
    print "\n$test->{name}:\n";
    my $c = $test->{c};
    $c->{verbose} = $self->{verbose};
    $c->crunch;
    my $end = new Benchmark;
    print "\nRunning time: ", timestr(timediff($end, $start)), "\n";
  }
  $self->save();
}

sub categorize_test_set {
  my ($self) = @_;

  print "\n---------- categorizing test data ---------------\n";

  $self->load('crunch');
  
  foreach my $test (@{$self->{tests}}) {
    my $i;
    my $start = new Benchmark;
    print "\n$test->{name}:\n";
    my $c = $test->{c};
    
    my $num_tests = keys %{$test->{test_docs}};
    my %ratings = map {$_ => 0} qw(F1 error recall precision);

    while (my ($path) = each %{$test->{test_docs}}) {
      (my $file = $path) =~ s#.*/##;
      print " Categorizing '$file': ";
      
      open FILE, $path or die "$path: $!";
      my $r = $c->categorize(join '', <FILE>);
      close FILE;
      
      my @cats = $r->categories;
      my @scores = $r->scores(@cats);
      my $real_cats = $test->{categories}{$file} || [];

      if ($self->{verbose}) {
	print "\nAssigned Categories:\n";
	foreach (0..$#cats) {
	  print "   $cats[$_]: $scores[$_]\n";
	}
	print "Real Categories:\n";
	
	warn "Warning: no categories found for document '$file'\n" unless $test->{categories}{$file};
	foreach (@$real_cats) {
	  print "   $_\n";
	}
      }

      foreach my $method (keys %ratings) {
	my $value = $c->$method(\@cats, $real_cats);
	print "$method = ", substr($value, 0, 5), ", ";
	$ratings{$method} += $value;
      }
      print "\n";
      
      print "-----------\n\n" if $self->{verbose};
      $i++;
    }

    foreach my $method (keys %ratings) {
      $ratings{$method} /= $num_tests;
    }
    $test->{results} = {%ratings};

    my $end = new Benchmark;
    $test->{results}{time} = 0 + timestr(timediff($end, $start));
    print "\nRunning time: ", timestr(timediff($end, $start)), " for $i documents.\n";
  }

  print "******************* Summary *************************************\n";
  print "*        Name         miR   miP   miF1  error      time         *\n";
  foreach my $test (@{$self->{tests}}) {
    printf("* %15s:   %.3f %.3f %.3f  %.3f    %4d sec       *\n",
	   $test->{name}, @{$test->{results}}{qw(recall precision F1 error)}, $test->{results}{time});
  }
  print ("*****************************************************************\n",
	 "*  miR = micro-avg. recall         miP = micro-avg. precision   *\n",
	 "*  miF = micro-avg. F1           error = micro-avg. error rate  *\n",
	 "*****************************************************************\n");
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
  
  $e->add('AI::Categorize::SomethingElse',
          'categories' => 'othercategories.txt');
  
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

Optional.  A list reference containing the names of the packages you
wish to load and schedule tests for.  The modules will be
automatically loaded by searching @INC.  If you don't provide a list
of packages, it's assumed that you'll add tests later by using the
C<add()> method.

=item * args

An optional list of arguments that will be passed to the C<new()>
method of each categorizer.

=item * training_set

Required for running C<parse_training_data()>.  This parameter specifies the
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

If you use C<test_size> to randomly select test documents from the
training documents, you need to give this parameter from the very
beginning (specifying in C<new()> or C<add()>, before calling
C<parse_training_data()>), because otherwise your random test
documents will be part of the training corpus - not a good thing.

=item * categories

Required for the C<parse_training_data()> and C<categorize_test_set()>
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
perhaps Text::CSV could be used in the future - or you could subclass
this module and read the category file yourself ;-).

=item * stopwords

Optional (default []).  A list of words to ignore when parsing and
categorizing documents.  This will be passed to the stopwords() method
of the individual categorizers.

=item * save

Specifies the name of a file in which state will be saved after each
stage of creating the categorizers.  This allows you to run one script
that calls C<parse_training_data()> and C<crunch()>, then go away for
a while, then run another script that calls C<categorize_test_set()>,
picking up where it left off after the C<crunch()>.

Specify a complete path/filename - some suffixes will be added to the
filename to indicate which stage has been completed.

I've implemented this a couple different ways so far, and I haven't
really settled on a good interface yet, so the details may change.

=back

=head2 add($package, arg1=>val1, arg2=>val2, ...)

Adds an additional test to the list of tests to be run.  The required
first parameter is the module to use (it will be automatically
loaded).  Any additional parameters will override the defaults you
specified in the C<new()> method.  

For example, you may want to run several tests of the C<kNN>
classifier using different parameters for C<k>:

  my $e = new AI::Categorize::Evaluate(
     'training_set' => 'text_dir',
     'test_set'     => 'test_dir',
     'categories'   => 'categories.txt',
     'stopwords'    => [qw(the a of to is that you for and)],
     'data_dir'     => 'data',
    );
  $e->add('AI::Categorize::kNN', 'args' => [k => 10]);
  $e->add('AI::Categorize::kNN', 'args' => [k => 20]);
  $e->add('AI::Categorize::kNN', 'args' => [k => 30]);

Since there was no C<packages> parameter to the C<new()> method, it
didn't create any tests at that time, but it did set several default
parameters for the tests that were created later using the C<add()>
method.  The C<args> parameter to C<add()> overrode any C<args>
parameter to C<new()> (but in this case there wasn't one).

=head2 parse_training_data()

Reads all the training documents and feeds them to the categorizers so
the categorization models can be built.

=head2 crunch()

Calls the C<crunch()> method for each categorizer.

=head2 categorize_test_set()

Feeds the test documents to each categorizer and reports the categorization results.

=head1 CAVEATS

The interface here isn't very stable at all.  I'm still experimenting
to see which things are useful in general and which are dumb.  Things
may go away, and because this is a testing module rather than
something that provides core functionality (at least so far), I won't
feel compelled to worry much about backward compatibility.

=head1 TO DO

Implement an 'iterations' mechanism through which one can test a
categorizer several times with different test documents.  For example,
you should be able to tell the Evaluate package to "run these two
categorizers, using this corpus, with 10 random documents (or 10% of
the documents) held out for test data, and repeat the procedure 10
times."

=head1 AUTHOR

Ken Williams, ken@forum.swarthmore.edu

=head1 COPYRIGHT

Copyright 2000-2001 Ken Williams.  All rights reserved.

This library is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=head1 SEE ALSO

perl(1).   AI::Categorize(3)

=cut
