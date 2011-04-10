package Moose::Util::TypeConstraints::Builtins;

use strict;
use warnings;

use Scalar::Util qw( blessed looks_like_number reftype );

sub type { goto &Moose::Util::TypeConstraints::type }
sub subtype { goto &Moose::Util::TypeConstraints::subtype }
sub as { goto &Moose::Util::TypeConstraints::as }
sub where (&) { goto &Moose::Util::TypeConstraints::where }
sub optimize_as (&) { goto &Moose::Util::TypeConstraints::optimize_as }

sub define_builtins {
    my $registry = shift;

    type 'Any'  => where {1};    # meta-type including all
    subtype 'Item' => as 'Any';  # base-type

    subtype 'Undef'   => as 'Item' => where { !defined($_) };
    subtype 'Defined' => as 'Item' => where { defined($_) };

    subtype 'Bool'
        => as 'Item'
        => where { !defined($_) || $_ eq "" || "$_" eq '1' || "$_" eq '0' };

    subtype 'Value'
        => as 'Defined'
        => where { !ref($_) }
        => optimize_as \&_Value;

    subtype 'Ref'
        => as 'Defined'
        => where { ref($_) }
        => optimize_as \&_Ref;

    subtype 'Str'
        => as 'Value'
        => where { ref(\$_) eq 'SCALAR' }
        => optimize_as \&_Str;

    subtype 'Num'
        => as 'Str'
        => where { Scalar::Util::looks_like_number($_) }
        => optimize_as \&_Num;

    subtype 'Int'
        => as 'Num'
        => where { "$_" =~ /^-?[0-9]+$/ }
        => optimize_as \&_Int;

    subtype 'CodeRef'
        => as 'Ref'
        => where { ref($_) eq 'CODE' }
        => optimize_as \&_CodeRef;

    subtype 'RegexpRef'
        => as 'Ref'
        => where( \&_RegexpRef )
        => optimize_as \&_RegexpRef;

    subtype 'GlobRef'
        => as 'Ref'
        => where { ref($_) eq 'GLOB' }
        => optimize_as \&_GlobRef;

    # NOTE: scalar filehandles are GLOB refs, but a GLOB ref is not always a
    # filehandle
    subtype 'FileHandle'
        => as 'GlobRef'
        => where {
            Scalar::Util::openhandle($_) || ( blessed($_) && $_->isa("IO::Handle") );
        }
        => optimize_as \&_FileHandle;

    subtype 'Object'
        => as 'Ref'
        => where { blessed($_) }
        => optimize_as \&_Object;

    # This type is deprecated.
    subtype 'Role'
        => as 'Object'
        => where { $_->can('does') }
        => optimize_as \&_Role;

    subtype 'ClassName'
        => as 'Str'
        => where { Class::MOP::is_class_loaded($_) }
        => optimize_as \&_ClassName;

    subtype 'RoleName'
        => as 'ClassName'
        => where {
            (Class::MOP::class_of($_) || return)->isa('Moose::Meta::Role');
        }
        => optimize_as \&_RoleName;

    $registry->add_type_constraint(
        Moose::Meta::TypeConstraint::Parameterizable->new(
            name               => 'ScalarRef',
            package_defined_in => __PACKAGE__,
            parent =>
                Moose::Util::TypeConstraints::find_type_constraint('Ref'),
            constraint => sub { ref($_) eq 'SCALAR' || ref($_) eq 'REF' },
            optimized            => \&_ScalarRef,
            constraint_generator => sub {
                my $type_parameter = shift;
                my $check = $type_parameter->_compiled_type_constraint;
                return sub {
                    return $check->( ${$_} );
                };
            }
        )
    );

    $registry->add_type_constraint(
        Moose::Meta::TypeConstraint::Parameterizable->new(
            name               => 'ArrayRef',
            package_defined_in => __PACKAGE__,
            parent =>
                Moose::Util::TypeConstraints::find_type_constraint('Ref'),
            constraint => sub { ref($_) eq 'ARRAY' },
            optimized => \&_ArrayRef,
            constraint_generator => sub {
                my $type_parameter = shift;
                my $check = $type_parameter->_compiled_type_constraint;
                return sub {
                    foreach my $x (@$_) {
                        ( $check->($x) ) || return;
                    }
                    1;
                    }
            }
        )
    );

    $registry->add_type_constraint(
        Moose::Meta::TypeConstraint::Parameterizable->new(
            name               => 'HashRef',
            package_defined_in => __PACKAGE__,
            parent =>
                Moose::Util::TypeConstraints::find_type_constraint('Ref'),
            constraint => sub { ref($_) eq 'HASH' },
            optimized => \&_HashRef,
            constraint_generator => sub {
                my $type_parameter = shift;
                my $check = $type_parameter->_compiled_type_constraint;
                return sub {
                    foreach my $x ( values %$_ ) {
                        ( $check->($x) ) || return;
                    }
                    1;
                    }
            }
        )
    );

    $registry->add_type_constraint(
        Moose::Meta::TypeConstraint::Parameterizable->new(
            name               => 'Maybe',
            package_defined_in => __PACKAGE__,
            parent =>
                Moose::Util::TypeConstraints::find_type_constraint('Item'),
            constraint           => sub {1},
            constraint_generator => sub {
                my $type_parameter = shift;
                my $check = $type_parameter->_compiled_type_constraint;
                return sub {
                    return 1 if not( defined($_) ) || $check->($_);
                    return;
                    }
            }
        )
    );
}

sub _Value { defined($_[0]) && !ref($_[0]) }

sub _Ref { ref($_[0]) }

# We might need to use a temporary here to flatten LVALUEs, for instance as in
# Str(substr($_,0,255)).
sub _Str {
    defined($_[0])
      && (   ref(\             $_[0] ) eq 'SCALAR'
          || ref(\(my $value = $_[0])) eq 'SCALAR')
}

sub _Num { !ref($_[0]) && looks_like_number($_[0]) }

# using a temporary here because regex matching promotes an IV to a PV,
# and that confuses some things (like JSON.pm)
sub _Int {
    my $value = $_[0];
    defined($value) && !ref($value) && $value =~ /\A-?[0-9]+\z/
}

sub _ScalarRef { ref($_[0]) eq 'SCALAR' || ref($_[0]) eq 'REF' }
sub _ArrayRef  { ref($_[0]) eq 'ARRAY'  }
sub _HashRef   { ref($_[0]) eq 'HASH'   }
sub _CodeRef   { ref($_[0]) eq 'CODE'   }
sub _GlobRef   { ref($_[0]) eq 'GLOB'   }

# RegexpRef is implemented in Moose.xs

sub _FileHandle {
    ref( $_[0] ) eq 'GLOB' && Scalar::Util::openhandle( $_[0] )
        or blessed( $_[0] ) && $_[0]->isa("IO::Handle");
}

sub _Object { blessed($_[0]) }

sub _Role {
    Moose::Deprecated::deprecated(
        feature => 'Role type',
        message =>
            'The Role type has been deprecated. Maybe you meant to create a RoleName type? This type be will be removed in Moose 2.0200.'
    );
    blessed( $_[0] ) && $_[0]->can('does');
}

sub _ClassName {
    return Class::MOP::is_class_loaded( $_[0] );
}

sub _RoleName {
    ClassName( $_[0] )
        && ( Class::MOP::class_of( $_[0] ) || return )
        ->isa('Moose::Meta::Role');
}

1;