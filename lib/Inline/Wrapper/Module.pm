package Inline::Wrapper::Module;
#
#   Inline::* module dynamic loader and useful wrapper routines
#
#   Individual module handler object
#
#   infi/08
#
#   POD documentation after __END__
#

use strict;
use warnings;
use Carp qw( croak );
use Data::Dumper;
use base qw( Inline::Wrapper );
use Inline;
use vars qw( $TRUE $FALSE $VERSION );

###
### VARS
###

($VERSION) = q$Revision: 6 $ =~ /(\d+)/;
*TRUE    = \1;
*FALSE   = \0;

my $PARAMS = {
    module_name => sub { $_[0] },
};

###
### INITIALIZER
###

sub new
{
    my( $class, @args ) = @_;

    croak "Do not use this class directly; used internally by Inline::Wrapper"
        unless( caller eq 'Inline::Wrapper' );

    return( $class->SUPER::new( @args ) );
}

sub initialize
{
    my( $self, @args ) = @_;

    # Check parameters
    @args = %{ $args[0] } if( ref( $args[0] ) eq 'HASH' );
    croak "initialize(): \%args must be a hash; read the docs"
        if( @args & 1 );
    my %args = @args;

    for( keys %args )
    {
        next unless( exists( $PARAMS->{lc $_} ) );      # ignore unwanted args
        $self->{lc $_} = $PARAMS->{lc $_}->( $args{$_} );
        delete( $args{$_} );
    }

    $self->_set_function_list( [] );
    $self->_set_last_load_time( 0 );

    return;
}

###
### DESTRUCTOMATIC!
###

sub DESTROY
{
    my( $self ) = @_;

    $self->_delete_namespace();

    return;
}

###
### PRIVATE METHODS
###

# Load the self-corresponding sub-language code module.
# At this point in time, we should be a complete object.
sub _load
# "He who fights with monsters should be careful lest he thereby become a
# monster..."
{
    my( $self ) = @_;

    my $module_src = $self->_read_module_source();
    my $namespace  = $self->_namespace();

    # Try to bind via Inline::$language
    $self->_delete_namespace();
    my $code = sprintf(q#package %s::%s;
                         use Inline;
                         Inline->bind( %s => $module_src );
                         package %s;
                         return( grep { !/^(?:BEGIN|ISA)$/ } keys %%%s::%s:: )#,
                        __PACKAGE__,        $namespace,
                        $self->language(),
                        __PACKAGE__,
                        __PACKAGE__,        $namespace );

    # DEAR LORD, STRING EVAL!  RUN AWAY!
    # http://perlmonks.org/index.pl?node_id=732598
    my @symbols = eval $code;
    chomp $@ if( $@ );
    warn "Error compiling " . $self->_module_path() . ": '$@'"
        and return()
            if( $@ );

    # Update our state
    $self->_set_function_list( @symbols );
    $self->_set_last_load_time( time );

    # return loaded symbol list
    return( @symbols );
}

# Actually run the associated function and return its @retvals
sub _run
# ".. And if thou gaze long into an abyss, the abyss will also gaze into thee."
{
    my( $self, $funcname, @args ) = @_;
    croak "run(): $funcname is a required param; read the docs"
        unless( $funcname );

    $self->_load() if( $self->_issue_reload() );

    croak "run(): $funcname not found"
        unless( $self->_func_exists( $funcname ) );

    # Attempt to pull coderef out of package namespace
    my $namespace = $self->_namespace();
    my $sub = \&{__PACKAGE__ . "::${namespace}::${funcname}"};
    warn "No such module or function: '$namespace'::'$funcname'" and return
        unless( ref( $sub ) eq 'CODE' );

    # Attempt to execute coderef
    my @retvals = eval { $sub->( @args ) };  # Ahhh, block eval.
    chomp $@ if( $@ );
    warn "Error executing ${namespace}::${funcname}: $@" and return
        if( $@ );

    return( @retvals );
}

# Fairly self-explanatory.
sub _read_module_source
{
    my( $self ) = @_;

    my $path = $self->_module_path();

    open( my $fd, '<', $path )
        or warn "$path is inaccessible: $!" and return( undef );
    my $module_src = do { local $/; <$fd> };
    close( $fd );

    return( $module_src );
}

sub _delete_namespace
{
    my( $self ) = @_;

    my $namespace = $self->_namespace();
    my $wiped     = delete( $::{__PACKAGE__.'::'}{$namespace.'::'} );

    return( $wiped ? $TRUE : $FALSE );
}

###
### ACCESSORS
###

sub _module_name
{
    my( $self ) = @_;

    return( $self->{module_name} );
}

sub _set_module_name
{
    my( $self, $modname ) = @_;

    # Validate
    $modname = $PARAMS->{module_name}->( $modname );

    return( $modname
              ? $self->{module_name} = $modname
              : $self->{module_name} );
}

sub _function_list
{
    my( $self ) = @_;

    return( keys %{ $self->{functions} } );
}

sub _set_function_list
{
    my( $self, @funcs ) = @_;

    @funcs = @{ $funcs[0] } if( ref( $funcs[0] ) );

    return( $self->{functions} = { map { $_ => $TRUE } @funcs } );
}

sub _func_exists
{
    my( $self, $funcname ) = @_;

    return( exists( $self->{functions}->{$funcname} ) );
}

sub _last_load_time
{
    my( $self ) = @_;

    return( $self->{last_load_time} );
}

sub _set_last_load_time
{
    my( $self, $load_time ) = @_;

    return( $load_time =~ /^\d+$/
              ? $self->{last_load_time} = $load_time
              : $self->{last_load_time} );
}

###
### UTILITY ROUTINES
###

# Return boolean if source file has been updated
sub _issue_reload
{
    my( $self ) = @_;
    return( $FALSE ) unless( $self->auto_reload() );

    my $file_mod_time = $self->_module_mtime();

    return( $self->_last_load_time < $self->_module_mtime ? $TRUE : $FALSE );
}

# Return file modificiation time
sub _module_mtime
{
    my( $self ) = @_;

    my $path = $self->_module_path();

    return( (stat $path)[9] || 0 );
}

# What is our namespace, based on our object state?
# XXX: I don't think this is unique.
sub _namespace
{
    my( $self ) = @_;

    my $modname = $self->_module_name();
    $modname =~ s#[/\\]#_#;

    return( $modname );
}

# What is our path, based on our object state?
sub _module_path
{
    my( $self ) = @_;

    my $modname  = $self->_module_name();
    my $file_ext = $self->_lang_ext();
    my $src_file = ( $modname =~ m/.*\Q$file_ext\E$/ )
                     ? $modname
                     : $modname . $file_ext;
    my $path = _path_join( $self->base_dir(), $src_file );

    return( $path );
}

# Generate a joined path from @_
sub _path_join
{
    ref( $_[0] ) and shift;     # scrap instance ref, if passed

    my $pathchar = ( $^O eq 'MSWin32' ) ? "\\" : '/';
    return( join( $pathchar, @_ ) );
}

1;

__END__

=pod

=head1 NAME

Inline::Wrapper::Module - Internal object wrapper for individual Inline modules.

=head1 SYNOPSIS

 use Inline::Wrapper::Module;

=head1 DESCRIPTION

Inline::Wrapper::Module is used internally by Inline::Wrapper, and should
not be used directly.  It will croak if you attempt to do so.

It is a descendent class of Inline::Wrapper.

=head1 METHODS

=over 4

=item B<new()>

Takes the same arguments as Inline::Wrapper::New, but also requires a
I<module_name> argument.

Don't use this, it will croak if you try to use it directly.

=item B<initialize()>

Initialize the object instance.

=item B<DESTROY()>

Destructor to clean up the object instance, and the private code module
namespace created.

=back

=head1 SEE ALSO

L<Inline::Wrapper>

The L<Inline> documentation.

The examples/ directory of this module's distribution.

=head1 ACKNOWLEDGEMENTS

Thank you, kennethk and ikegami for your assistance on perlmonks.

L<http://perlmonks.org/index.pl?node_id=732598>

=head1 AUTHOR

Please kindly read through this documentation and the B<examples/>
thoroughly, before emailing me with questions.  Your answer is likely
in here.

Jason McManus (infi) -- infidel@cpan.org

=head1 LICENSE

Copyright (c) Jason McManus

This module may be used, modified, and distributed under the same terms
as Perl itself.  Please see the license that came with your Perl
distribution for details.

=cut

### Thank you, drive through. ###

