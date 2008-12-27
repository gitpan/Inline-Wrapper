package Inline::Wrapper;
#
#   Inline::* module dynamic loader and useful wrapper routines
#
#   infi/08
#
#   POD documentation after __END__
#
#   TODO: write 'unload()'

use strict;
use warnings;
use Carp qw( croak );
use Data::Dumper;
use vars qw( $TRUE $FALSE $VERSION );
BEGIN { $INC{'Inline::Wrapper.pm'} ||= __FILE__ };  # recursive use check
use Inline::Wrapper::Module;                        # individual code modules

###
### VARS
###

$VERSION = '0.02';
*TRUE    = \1;
*FALSE   = \0;

my $DEFAULTS = {
    base_dir    => '.',                 # default search directory
    auto_reload => $FALSE,              # automatically reload module?
    language    => 'Lua',               # default language
};

my $LANGS = {
    Foo         => '.foo',              # built in to Inline's distro
    C           => '.c',
    Lua         => '.lua',
};

my $PARAMS = {
    base_dir    => sub { $_[0] },
    auto_reload => sub { $_[0] ? $TRUE : $FALSE },
    language    => sub {
                     defined( $_[0] ) and exists( $LANGS->{$_[0]} )
                         ? $_[0]
                         : ( warn sprintf( "Invalid language: %s; using %s",
                                           $_[0], $DEFAULTS->{language} )
                               and $DEFAULTS->{language} )
                   },
};

###
### CONSTRUCTOR
###

sub new
{
    my( $class, @args ) = @_;

    # Check parameters
    @args = %{ $args[0] } if( ref( $args[0] ) eq 'HASH' );
    croak "$class: \%args must be a hash; read the docs" if( @args & 1 );

    # Set up object
    my $self = {
        %$DEFAULTS,
#        modules     => {},
    };
    bless( $self, $class );

    # Initialize object instance
    @args = $self->_process_args( @args );
    $self->initialize( @args );

    return( $self );
}

sub initialize
{
    my( $self ) = @_;

    $self->{modules} = {};

    return;
}

###
### PUBLIC METHODS
###

# Load a code module named $modname from $base_dir with $lang_extension
# XXX: Check for dupes, return the pre-built object if it's a dupe
sub load
{
    my( $self, $modname, @args ) = @_;

    # Check arguments
    croak "load() \$modname is a required param; read the docs"
        unless( $modname );
    @args = %{ $args[0] } if( ref( $args[0] ) eq 'HASH' );
    croak "load(): \%args must be a hash; read the docs"
        if( @args & 1 );
    my %args = @args;

    # Check for duplicate modules, return @function list if found
    if( my $temp_module = $self->_module( $modname ) )
    {
        my $temp_lang     = $args{language} || $self->language();
        my $temp_base_dir = $args{base_dir} || $self->base_dir();
        if( $temp_lang     eq $temp_module->language() &&
            $temp_base_dir eq $temp_module->base_dir() )
        {
            $temp_module->set_auto_reload( $args{auto_reload} )
                if( $args{auto_reload} );
            print "HONK!\n";
            return( $temp_module->_function_list() );   # RETURN
        }
    }

    # Create a new module object
    my $module = Inline::Wrapper::Module->new(
            module_name     => $modname,
            $self->_settings(),
            %args,
    );
    $self->_add_module( $modname, $module );

    # Actually attempt to load the inline module
    my @functions = $module->_load();

    return( @functions );
}

# Run a $modname::$funcname function, passing it @args
sub run
{
    my( $self, $modname, $funcname, @args ) = @_;

    my $module    = $self->_module( $modname );
    my @retvals   = $module->_run( $funcname, @args );

    return( @retvals );
}

# Return the list of already-loaded modules
sub modules
{
    my( $self ) = @_;

    return( $self->_module_names() );
}

# Return the list of functions loaded from $modname
sub functions
{
    my( $self, $modname ) = @_;

    my $module = $self->_module( $modname );
    warn "Module '$modname' not loaded"
        and return()
            unless( ref( $module ) );

    return( $module->_function_list() );
}

###
### PRIVATE METHODS
###

sub _process_args
{
    my( $self, @args ) = @_;
    croak "_process_args() requires an even number of params" if( @args & 1 );
    my %args = @args;

    for( keys %args )
    {
        next unless( exists( $PARAMS->{lc $_} ) );      # not for us, pass on
        $self->{lc $_} = $PARAMS->{lc $_}->( $args{$_} );
        delete( $args{$_} );
    }

    return( %args );
}

sub _module_names
{
    my( $self ) = @_;

    return( keys( %{ $self->{modules} } ) );
}

sub _settings
{
    my( $self ) = @_;

    my %defaults = map { $_ => $self->{$_} } keys( %$DEFAULTS );

    return( %defaults );
}

###
### ACCESSORS
###

sub base_dir
{
    my( $self ) = @_;

    return( $self->{base_dir} );
}

sub set_base_dir
{
    my( $self, $base_dir ) = @_;

    # Validate
    $base_dir = $PARAMS->{base_dir}->( $base_dir );

    return( defined( $base_dir )
              ? $self->{base_dir} = $base_dir
              : $self->{base_dir} );
}

sub language
{
    my( $self ) = @_;

    return( $self->{language} );
}

sub set_language
{
    my( $self, $language ) = @_;

    # Validate
    $language = $PARAMS->{language}->( $language );

    return( defined( $language )
              ? $self->{language} = $language
              : $self->{language} );
}

sub add_language
{
    my( $self, $language, $lang_ext ) = @_;

    warn "add_language(): Language not set; read the docs"
        and return
            unless( $language );
    warn "add_language(): Language extension not set; read the docs"
        and return
            unless( $lang_ext );

    return( ( $LANGS->{$language} = $lang_ext ) ? $language : undef );
}

sub auto_reload
{
    my( $self ) = @_;

    return( $self->{auto_reload} );
}

sub set_auto_reload
{
    my( $self, $auto_reload ) = @_;

    # Validate
    $auto_reload = $PARAMS->{auto_reload}->( $auto_reload );

    return( defined( $auto_reload )
              ? $self->{auto_reload} = $auto_reload
              : $self->{auto_reload} );
}

### PRIVATE ACCESSORS

sub _module
{
    my( $self, $modname ) = @_;

#    croak "Module '$modname' not loaded"
#        unless( exists( $self->{modules}->{$modname} ) );

    return( $self->{modules}->{$modname} );
}

sub _add_module
{
    my( $self, $modname, $module ) = @_;

    return( $self->{modules}->{$modname} = $module );
}

###
### PRIVATE UTILITY ROUTINES
###

sub _lang_ext
{
    my( $self, $language ) = @_;

    $language ||= $self->{language};

    return( $LANGS->{$language} );
}

1;

__END__

=pod

=head1 NAME

Inline::Wrapper - Convenient module wrapper/loader routines for Inline.pm

=head1 SYNOPSIS

sample.pl:

 use Inline::Wrapper;

 my $inline = Inline::Wrapper->new(
    language    => 'C',
    base_dir    => '.',
 );

 my @symbols = $inline->load( 'sample_module' );

 my @retvals = $inline->run( 'sample_module', 'sample_func', 2, 3 );

 print $retvals[0], "\n";

 exit(0);

sample_module.c:

 int sample_func( int arg1, int arg2 ) {
     return arg1 * arg2;
 }

=head1 DESCRIPTION

Inline::Wrapper provides wrapper routines to make embedding another
language into a Perl application more convenient.

Instead of having to include the external code in after __END__ in Perl
source code, you can have separate, individually configurable language module
directories to contain all of your code.

=head1 FEATURES

Inline::Wrapper provides the following:

=over 4

=item * Support for all languages that Inline.pm supports.

=item * A single, unified interface to running loaded module functions.

=item * Loading of files containing pure source code, only in their
respective language.

=item * Individually configurable module directories.

=item * Automatic, run-time module reloading upon file modification time
detection.

=item * No more namespace pollution.

=back

=head1 CONSTRUCTOR

=over 4

=item B<$obj = new(> I<[ var =E<gt> value, ... ]> B<)>

Create a new B<Inline::Wrapper> object, with the appropriate attributes (if
specified).

RETURNS: blessed $object, or undef on failure.

ARGUMENTS:

All arguments are of the hash form  Var => Value.  B<new()> will complain
and croak if they do not follow this form.

B<NOTE:> The arguments to B<new()> become the defaults used by B<load()>.
You can individually configure loaded modules using B<load()>, as well.

=over 4

=item B<language>           [ default: B<Lua> ]

Set to the DEFAULT language for which you wish to load modules, if not
explicitly specified via B<load()>.

B<NOTE>: It defaults to Lua because that is what I wrote this module for.
Just pass in the argument if you don't like that.

B<ALSO NOTE:> Currently only a couple of "known" languages are hard-coded
into this module.  If you wish to use others, don't pass this argument, and
use the B<add_language()> method, documented below, after the object has
been instantiated.

=item B<auto_reload>        [ default: B<FALSE> ]

Set to a TRUE value to default to automatically checking if modules have
been changed since the last B<load()>, and reload them if necessary.

=item B<base_dir>           [ default: B<'.'> ]

Set to the default base directory from which you wish to load all modules.

=back

=back

=head2 Example

 my $wrapper = Inline::Wrapper->new(
        language        => 'C',
        base_dir        => 'src/code/C',
        auto_reload     => 1,
 );

=head1 METHODS

=over 4

=item B<initialize( )>

Initialize arguments.  If you are subclassing, overload this, not B<new()>.

Returns nothing.

=item B<load(> I<$modname [, %arguments ]> B<)>

The workhorse.  Loads the actual module itself, importing its symbols into a
private namespace, and making them available to call via B<run()>.

$modname is REQUIRED.  It corresponds to the base filename, without
extension, loaded from the B<base_dir>.  See the
L<"Details of steps taken by load()"> section, Step 3, a few lines down
for clarification of how pathname resolution is done.  It is also how you
will refer to this particular module from your program.

B<This method accepts all of the same arguments as new().>  Thus, you can
set the DEFAULTS via B<new()>, yet still individually configure module
components different from the defaults, if desired.

Returns a list of @functions made available by loading $modname, or warns
and returns an empty list if unsuccessful.

=back

=head2 Details of steps taken by load()

Since this is the real guts of this module, here are the exact steps taken
when loading the module, doing pathname resolution, etc.

=over 4

=item 1. Checks to see if the specified module has already been loaded, and
if so, returns the list of available functions in that module immediately.

=item 2. Creates a new L<Inline::Wrapper::Module> container object with any
supplied %arguments, or the defaults you specified with
B<Inline::Wrapper->new()>.

=item 3. Constructs a path to the specified $modname, as follows:

=over 2

=item C<$base_dir + $path_separator + $modname + $lang_ext>

=back

=over 4

=item I<$base_dir> is taken either from the default created with B<new()>, or
the explicitly supplied base_dir argument to B<load()>.

=item I<$path_separator> is just the appropriate path separator for your OS.

=item I<$modname> is your supplied module name.  Note that this means that you
can supply your own subdirectories, as well.  'foo' is just as valid as
'foo/bar/baz'.

=item I<$lang_ext> is taken from a data structure that defaults to
common-sense filename extensions on a per-language basis.  Any of these can
be overridden via the B<add_language()> method.

=back

=item 4. Attempts to open the file at the path constructed above, and if
successful, slurps in the entire source file.

=item 5. Attempts to bind() (compile and set symbols) it with the
L<Inline>->bind() method into a private namespace.

=item 6. If step 5 was successful, set the load time, and return the list
of loaded, available functions provided by the module.

=item 7. If step 5 failed, warn and return an empty list.

=back

=over 4

=item B<run(> I<$modname, $function [, @args ]> B<)>

Run the named $function that you loaded from $modname, with the specified
@arguments (if any).

Assuming a successful compilation (you are checking for errors, right?),
this will execute the function provided by the loaded module.  Call syntax
and everything is up to the function provided.  This simply executes the sub
that L<Inline> loaded as-is, but in its own private namespace to keep your
app clean.

Returns @list of actual return values provided by the module itself.
Whatever the module returns in its native language, you get back.

=item B<modules( )>

Returns @list of available, loaded and ready module names, or the empty list
if no modules have been loaded.

=item B<functions(> I<$modname> B<)>

Returns @list of functions provided by $modname, or the empty list.

=back

=head1 ACCESSORS

Various accessors that allow you to inspect or change the default settings
after creating the object.

=over 4

=item B<base_dir( )>

Returns the base_dir attribute from the object.

=item B<set_base_dir(> I<$path> B<)>

Sets the base_dir attribute of the object, and returns whatever it ended
up being set to.

B<NOTE:> Only affects modules loaded after this setting was made.

=item B<auto_reload( )>

Returns a $boolean as to whether or not the current DEFAULT auto_reload()
setting is enabled.

=item B<set_auto_reload(> I<$boolean> B<)>

Sets the auto_reload attribute of the object, and returns whatever it ended
up being set to.

B<NOTE:> Only affects modules loaded after this setting was made.

=item B<language( )>

Returns the language attribute of the object.

=item B<set_language(> I<$lang> B<)>

Sets the language attribute of the object, and returns whatever it ended up
being set to.

B<NOTE:> Only affects modules loaded after this setting was made.

B<ALSO NOTE:> This checks for "valid" languages via a pretty naive method.
Currently only a couple are hard-coded.  However, you can add your own
languages via the B<add_language()> method, described next.

=item B<add_language(> I<$language => $extension> B<)>

Adds a language to the "known languages" table, allowing you to later use
set_language( $lang ).

REQUIRES a $language name (e.g. 'Python') and a filename $extension (e.g.
'.py'), which will be used in pathname resolution, as described under
B<load()>.

Returns TRUE if successful, issues warnings and returns FALSE otherwise.

B<NOTE:>If you I<CHANGE> a language filename extension with a module
already loaded with B<auto_reload> enabled, and don't rename the underlying
file, it'll probably freak during dynamic pathname construction, thinking
the file has been removed.  I'll fix this in a later version.  For now,
Don't Do That(tm).

=back

=head1 SEE ALSO

L<Inline::Wrapper::Module>

The L<Inline> documentation.

The examples/ directory of this module's distribution.

=head1 ACKNOWLEDGEMENTS

Thank you, kennethk and ikegami for your assistance on perlmonks.

L<http://perlmonks.org/index.pl?node_id=732598>

=head1 AUTHOR

Please kindly read through this documentation and the B<examples/>
thoroughly, before emailing me with questions.  Your answer is likely
in here.

Jason McManus (INFIDEL) -- infidel@cpan.org

=head1 LICENSE

Copyright (c) Jason McManus

This module may be used, modified, and distributed under the same terms
as Perl itself.  Please see the license that came with your Perl
distribution for details.

=cut

### Thank you, drive through. ###
