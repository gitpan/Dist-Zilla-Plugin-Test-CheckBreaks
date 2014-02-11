use strict;
use warnings FATAL => 'all';

use Test::More;
use if $ENV{AUTHOR_TESTING}, 'Test::Warnings';
use Test::DZil;
use Path::Tiny;
use File::pushd;

my $tzil = Builder->from_config(
    { dist_root => 't/does-not-exist' },
    {
        add_files => {
            'source/dist.ini' => simple_ini(
                [ GatherDir => ],
                [ 'Test::CheckBreaks' => { conflicts_module => 'Moose::Conflicts' } ],
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

# it's important we require using an eval'd string rather than via a bareword,
# so prereq scanners don't grab this module (::Conflicts modules are not
# usually indexed)
like($content, qr/eval 'require $_; 1'/m, "test checks $_")
    for 'Moose::Conflicts';

subtest 'run the generated test' => sub
{
    my $wd = File::pushd::pushd $build_dir;
    do $file;
    warn $@ if $@;
};

diag join("\n", 'log messages:', @{ $tzil->log_messages }) if not Test::Builder->new->is_passing;

done_testing;