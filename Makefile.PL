use ExtUtils::MakeMaker;

my $module = 'AI::Categorize';
my ($name, $dir);
($name = $module) =~ s/.*::(\w+)/$1.pm/;
($dir = $module) =~ s/::/-/g;

WriteMakefile(
    'NAME'		=> 'AI::Categorize',
    'VERSION_FROM'	=> 'Categorize.pm',
    'PREREQ_PM'		=> {Storable => 0},
    'dist' => { COMPRESS=>"gzip", 
		SUFFIX=>"gz", 
		PREOP=>('rm -f README; '.
			"pod2text -80 < $name > README; ".
			"cp -f README $dir-\$(VERSION); "
		       ),
	      },
);
