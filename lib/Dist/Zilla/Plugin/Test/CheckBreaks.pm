use strict;
use warnings;
package Dist::Zilla::Plugin::Test::CheckBreaks;
# git description: v0.010-2-g9825135
$Dist::Zilla::Plugin::Test::CheckBreaks::VERSION = '0.011';
# ABSTRACT: Generate a test that shows what modules you are breaking
# KEYWORDS: distribution prerequisites upstream dependencies modules conflicts breaks breakages metadata
# vim: set ts=8 sw=4 tw=78 et :

use Moose;
with (
    'Dist::Zilla::Role::FileGatherer',
    'Dist::Zilla::Role::FileMunger',
    'Dist::Zilla::Role::TextTemplate',
    'Dist::Zilla::Role::PrereqSource',
);
use Module::Metadata 1.000005;
use Path::Tiny;
use Module::Runtime 'module_notional_filename';
use List::Util 1.33 qw(any first);
use Sub::Exporter::ForMethods 'method_installer';
use Data::Section 0.004 { installer => method_installer }, '-setup';
use Data::Dumper ();
use namespace::autoclean;

sub filename { path('t', 'zzz-check-breaks.t') }

around dump_config => sub
{
    my ($orig, $self) = @_;
    my $config = $self->$orig;

    $config->{+__PACKAGE__} = {
        conflicts_module => $self->conflicts_module,
    };

    return $config;
};

sub gather_files
{
    my $self = shift;

    require Dist::Zilla::File::InMemory;

    $self->add_file( Dist::Zilla::File::InMemory->new(
        name => $self->filename->stringify,
        content => ${$self->section_data('test-check-breaks')},
    ));
}

has conflicts_module => (
    is => 'ro', isa => 'Str|Undef',
    lazy => 1,
    default => sub {
        my $self = shift;

        $self->log_debug('no conflicts_module provided; looking for one in the dist...');
        # TODO: use Dist::Zilla::Role::ModuleMetadata
        my $main_file = $self->zilla->main_module;
        my $fh;
        ($main_file->can('encoding')
            ? open $fh, sprintf('<encoding(%s)', $main_file->encoding), \$main_file->encoded_content
            : open $fh, '<', \$main_file->content)
                or $self->log_fatal('cannot open handle to ' . $main_file->name . ' content: ' . $!);

        my $mmd = Module::Metadata->new_from_handle($fh, $main_file->name);
        my $module = ($mmd->packages_inside)[0] . '::Conflicts';

        # check that the file exists in the dist (it should never be shipped
        # separately!)
        my $conflicts_filename = module_notional_filename($module);
        if (any { $_->name eq path('lib', $conflicts_filename) } @{ $self->zilla->files })
        {
            $self->log_debug($module . ' found');
            return $module;
        }

        $self->log_debug('No ' . $module . ' found');
        return undef;
    },
);

sub munge_files
{
    my $self = shift;

    my $breaks_data = $self->zilla->distmeta->{x_breaks};
    $self->log_debug('no x_breaks metadata and no conflicts module found to check against: adding no-op test')
        if not keys %$breaks_data and not $self->conflicts_module;

    my $filename = $self->filename;
    my $file = first { $_->name eq $filename } @{ $self->zilla->files };

    $file->content(
        $self->fill_in_string(
            $file->content,
            {
                dist => \($self->zilla),
                plugin => \$self,
                module => \($self->conflicts_module),
                breaks => \$breaks_data,
            }
        )
    );

    return;
}

sub register_prereqs
{
    my $self = shift;

    my $distmeta = $self->zilla->distmeta;

    $self->zilla->register_prereqs(
        {
            phase => 'test',
            type  => 'requires',
        },
        'Test::More' => '0.88',
        exists $distmeta->{x_breaks} && keys %{ $distmeta->{x_breaks} }
            ? (
                'CPAN::Meta::Requirements' => '0',
                'CPAN::Meta::Check' => '0.007',
            ) : (),
    );
}

__PACKAGE__->meta->make_immutable;

#pod =pod
#pod
#pod =head1 SYNOPSIS
#pod
#pod In your F<dist.ini>:
#pod
#pod     [Breaks]
#pod     Foo = <= 1.1    ; Foo at 1.1 or lower will break when I am installed
#pod
#pod     [Test::CheckBreaks]
#pod     conflicts_module = Moose::Conflicts
#pod
#pod =head1 DESCRIPTION
#pod
#pod This is a L<Dist::Zilla> plugin that runs at the
#pod L<gather files|Dist::Zilla::Role::FileGatherer> stage, providing a test file
#pod that runs last in your test suite and checks for conflicting modules, as
#pod indicated by C<x_breaks> in your distribution metadata.
#pod (See the F<t/zzz-check-breaks.t> test in this distribution for an example.)
#pod
#pod C<x_breaks> entries are expected to be
#pod L<version ranges|CPAN::Meta::Spec/Version Ranges>, with one
#pod addition, for backwards compatibility with
#pod L<[Conflicts]|Dist::Zilla::Plugin::Conflicts>: if a bare version number is
#pod specified, it is interpreted as C<< '<= $version' >> (to preserve the intent
#pod that versions at or below the version specified are those considered to be
#pod broken).  It is possible that this interpretation will be removed in the
#pod future; almost certainly before C<breaks> becomes a formal part of the meta
#pod specification.
#pod
#pod =head1 CONFIGURATION
#pod
#pod =head2 C<conflicts_module>
#pod
#pod The name of the conflicts module to load and upon which to invoke the C<check_conflicts>
#pod method. Defaults to the name of the main module with 'C<::Conflicts>'
#pod appended, such as what is generated by the
#pod L<[Conflicts]|Dist::Zilla::Plugin::Conflicts> plugin.
#pod
#pod If your distribution uses L<Moose> but does not itself generate a conflicts
#pod plugin, then C<Moose::Conflicts> is an excellent choice, as there are numerous
#pod interoperability conflicts catalogued in that module.
#pod
#pod There is no error if the module does not exist. This test does not require
#pod L<[Conflicts]|Dist::Zilla::Plugin::Conflicts> to be used in your distribution;
#pod this is only a feature added for backwards compatibility.
#pod
#pod =for Pod::Coverage filename gather_files munge_files register_prereqs
#pod
#pod =head1 BACKGROUND
#pod
#pod =for stopwords irc
#pod
#pod I came upon this idea for a test after handling a
#pod L<bug report|https://rt.cpan.org/Ticket/Display.html?id=92780>
#pod I've seen many times before when dealing with L<Moose> code: "hey, when I
#pod updated Moose, my other thing that uses Moose stopped working!"  For quite
#pod some time Moose has generated breakage information in the form of the
#pod F<moose-outdated> executable and a check in F<Makefile.PL> (which uses the
#pod generated module C<Moose::Conflicts>), but the output is usually buried in the
#pod user's install log or way up in the console buffer, and so doesn't get acted
#pod on nearly as often as it should.  I realized it would be a simple matter to
#pod re-run the executable at the very end of tests by crafting a filename that
#pod always sorts (and runs) last, and further that we could generate this test.
#pod This coincided nicely with conversations on irc C<#toolchain> about the
#pod C<x_breaks> metadata field and plans for its future. Therefore, this
#pod distribution, and its sister plugin L<[Breaks]|Dist::Zilla::Plugin::Breaks>
#pod were born!
#pod
#pod =head1 SEE ALSO
#pod
#pod =for :list
#pod * L<Dist::Zilla::Plugin::Breaks>
#pod * L<Dist::CheckConflicts>
#pod * L<The Annotated Lancaster Consensus|http://www.dagolden.com/index.php/2098/the-annotated-lancaster-consensus/> at "Improving on 'conflicts'"
#pod * L<Module::Install::CheckConflicts>
#pod
#pod =cut

=pod

=encoding UTF-8

=head1 NAME

Dist::Zilla::Plugin::Test::CheckBreaks - Generate a test that shows what modules you are breaking

=head1 VERSION

version 0.011

=head1 SYNOPSIS

In your F<dist.ini>:

    [Breaks]
    Foo = <= 1.1    ; Foo at 1.1 or lower will break when I am installed

    [Test::CheckBreaks]
    conflicts_module = Moose::Conflicts

=head1 DESCRIPTION

This is a L<Dist::Zilla> plugin that runs at the
L<gather files|Dist::Zilla::Role::FileGatherer> stage, providing a test file
that runs last in your test suite and checks for conflicting modules, as
indicated by C<x_breaks> in your distribution metadata.
(See the F<t/zzz-check-breaks.t> test in this distribution for an example.)

C<x_breaks> entries are expected to be
L<version ranges|CPAN::Meta::Spec/Version Ranges>, with one
addition, for backwards compatibility with
L<[Conflicts]|Dist::Zilla::Plugin::Conflicts>: if a bare version number is
specified, it is interpreted as C<< '<= $version' >> (to preserve the intent
that versions at or below the version specified are those considered to be
broken).  It is possible that this interpretation will be removed in the
future; almost certainly before C<breaks> becomes a formal part of the meta
specification.

=head1 CONFIGURATION

=head2 C<conflicts_module>

The name of the conflicts module to load and upon which to invoke the C<check_conflicts>
method. Defaults to the name of the main module with 'C<::Conflicts>'
appended, such as what is generated by the
L<[Conflicts]|Dist::Zilla::Plugin::Conflicts> plugin.

If your distribution uses L<Moose> but does not itself generate a conflicts
plugin, then C<Moose::Conflicts> is an excellent choice, as there are numerous
interoperability conflicts catalogued in that module.

There is no error if the module does not exist. This test does not require
L<[Conflicts]|Dist::Zilla::Plugin::Conflicts> to be used in your distribution;
this is only a feature added for backwards compatibility.

=for Pod::Coverage filename gather_files munge_files register_prereqs

=head1 BACKGROUND

=for stopwords irc

I came upon this idea for a test after handling a
L<bug report|https://rt.cpan.org/Ticket/Display.html?id=92780>
I've seen many times before when dealing with L<Moose> code: "hey, when I
updated Moose, my other thing that uses Moose stopped working!"  For quite
some time Moose has generated breakage information in the form of the
F<moose-outdated> executable and a check in F<Makefile.PL> (which uses the
generated module C<Moose::Conflicts>), but the output is usually buried in the
user's install log or way up in the console buffer, and so doesn't get acted
on nearly as often as it should.  I realized it would be a simple matter to
re-run the executable at the very end of tests by crafting a filename that
always sorts (and runs) last, and further that we could generate this test.
This coincided nicely with conversations on irc C<#toolchain> about the
C<x_breaks> metadata field and plans for its future. Therefore, this
distribution, and its sister plugin L<[Breaks]|Dist::Zilla::Plugin::Breaks>
were born!

=head1 SEE ALSO

=over 4

=item *

L<Dist::Zilla::Plugin::Breaks>

=item *

L<Dist::CheckConflicts>

=item *

L<The Annotated Lancaster Consensus|http://www.dagolden.com/index.php/2098/the-annotated-lancaster-consensus/> at "Improving on 'conflicts'"

=item *

L<Module::Install::CheckConflicts>

=back

=head1 AUTHOR

Karen Etheridge <ether@cpan.org>

=head1 COPYRIGHT AND LICENSE

This software is copyright (c) 2014 by Karen Etheridge.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=head1 CONTRIBUTOR

=for stopwords Olivier Mengué

Olivier Mengué <dolmen@cpan.org>

=cut

__DATA__
___[ test-check-breaks ]___
use strict;
use warnings;

# this test was generated with {{ ref($plugin) . ' ' . ($plugin->VERSION || '<self>') }}

use Test::More 0.88;

SKIP: {
{{
    if ($module) {
        require Module::Runtime;
        my $filename = Module::Runtime::module_notional_filename($module);
        <<"CHECK_CONFLICTS";
    eval 'require $module; ${module}->check_conflicts';
    skip('no $module module found', 1) if not \$INC{'$filename'};

    diag \$@ if \$@;
    pass 'conflicts checked via $module';
CHECK_CONFLICTS
    }
    else
    {
        "    skip 'no conflicts module found to check against', 1;\n";
    }
}}}

{{
    if (keys %$breaks)
    {
        my $dumper = Data::Dumper->new([ $breaks ], [ 'breaks' ]);
        $dumper->Sortkeys(1);
        $dumper->Indent(1);
        $dumper->Useqq(1);
        my $dist_name = $dist->name;
        'my ' . $dumper->Dump . <<'CHECK_BREAKS_1' .

use CPAN::Meta::Requirements;
my $reqs = CPAN::Meta::Requirements->new;
$reqs->add_string_requirement($_, $breaks->{$_}) foreach keys %$breaks;

use CPAN::Meta::Check 0.007 'check_requirements';
our $result = check_requirements($reqs, 'conflicts');

if (my @breaks = grep { defined $result->{$_} } keys %$result)
{
CHECK_BREAKS_1
    "    diag 'Breakages found with $dist_name:';\n" .
    <<'CHECK_BREAKS_2';
    diag "$result->{$_}" for sort @breaks;
    diag "\n", 'You should now update these modules!';
}
CHECK_BREAKS_2
    }
    else { q{pass 'no x_breaks data to check';} . "\n" }
}}
done_testing;
