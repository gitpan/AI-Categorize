use ExtUtils::MakeMaker;

WriteMakefile(
    'NAME'		=> 'AI::Categorize',
    'VERSION_FROM'	=> 'Categorize.pm',
    'PREREQ_PM'		=> {Storable => 0},
);
