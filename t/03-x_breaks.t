use strict;
use warnings FATAL => 'all';

use Test::More;
use if $ENV{AUTHOR_TESTING}, 'Test::Warnings';
use Test::DZil;
use Path::Tiny;
use File::pushd;
use Test::Deep;

use lib 't/lib';

my $tzil = Builder->from_config(
    { dist_root => 't/does-not-exist' },
    {
        add_files => {
            'source/dist.ini' => simple_ini(
                [ GatherDir => ],
                [ 'Test::CheckBreaks' => ],
                [ '=Breaks' => {
                    'Dist::Zilla' => '>= ' . Dist::Zilla->VERSION,  # fails; stored as 'version'
                    'ExtUtils::MakeMaker' => '<= 20.0',             # fails
                    'version' => '== ' . version->VERSION,          # fails
                    'Test::More' => '!= ' . Test::More->VERSION,    # passes
                  }
                ],
            ),
            path(qw(source lib Foo.pm)) => "package Foo;\n1;\n",
        },
    },
);

$tzil->chrome->logger->set_debug(1);
$tzil->build;

my $build_dir = $tzil->tempdir->subdir('build');
my $file = path($build_dir, 't', 'zzz-check-breaks.t');
ok(-e $file, 'test created');

my $content = $file->slurp;
unlike($content, qr/[^\S\n]\n/m, 'no trailing whitespace in generated test');

unlike($content, qr/$_/m, "test does not do anything with $_")
    for 'Foo::Conflicts';

my @expected_break_specs = (
    '"Dist::Zilla".*"' . Dist::Zilla->VERSION . '"',
    '"ExtUtils::MakeMaker".*"<= 20.0"',
    '"version".*"== ' . version->VERSION . '"',
    '"Test::More".*"!= ' . Test::More->VERSION . '"',
);

like($content, qr/$_/m, 'test checks the right version range') foreach @expected_break_specs;

subtest 'run the generated test' => sub
{
    my $wd = File::pushd::pushd $build_dir;
    do $file;
    warn $@ if $@;
};

# we define a global $result in the test, which we can now use to extract the values of the test
my $breaks_result = eval '$main::result';

my $is_defined = code(sub { defined $_[0] });
cmp_deeply(
    $breaks_result,
    {
        'ExtUtils::MakeMaker' => $is_defined,
        'Dist::Zilla' => $is_defined,
        'version' => $is_defined,
        'Test::More' => undef,
    },
    'breakages checked, with the correct results achieved',
);


diag join("\n", 'log messages:', @{ $tzil->log_messages }) if not Test::Builder->new->is_passing;

done_testing;
