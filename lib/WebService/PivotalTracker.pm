package WebService::PivotalTracker;

use strict;
use warnings;
use namespace::autoclean;

our $VERSION = '0.05';

use DateTime::Format::RFC3339;
use Params::ValidationCompiler qw( compile );
use Scalar::Util qw( blessed );
use WebService::PivotalTracker::Client;
use WebService::PivotalTracker::Me;
use WebService::PivotalTracker::Project;
use WebService::PivotalTracker::ProjectIteration;
use WebService::PivotalTracker::Story;
use WebService::PivotalTracker::Types
    qw( ArrayRef ClientObject IterationScope LWPObject MD5Hex NonEmptyStr PositiveInt Uri );

use Moo;

has token => (
    is       => 'ro',
    isa      => MD5Hex,
    required => 1,
);

has base_uri => (
    is      => 'ro',
    isa     => Uri,
    coerce  => 1,
    default => 'https://www.pivotaltracker.com/services/v5',
);

has _ua => (
    is        => 'ro',
    isa       => LWPObject,
    init_arg  => 'ua',
    predicate => '_has_ua',
);

has _client => (
    is      => 'ro',
    isa     => ClientObject,
    lazy    => 1,
    builder => '_build_client',
);

sub projects {
    my $self = shift;

    my $uri = $self->_client->build_uri('/projects');

    return [
        map {
            WebService::PivotalTracker::Project->new(
                raw_content => $_,
                pt_api      => $self,
                )
        } @{ $self->_client->get($uri) }
    ];
}

{
    my $check = compile(
        params => {
            project_id => { type => PositiveInt },
            filter     => {
                type     => NonEmptyStr,
                optional => 1
            },
        }
    );

    sub project_stories_where {
        my $self = shift;
        my %args = $check->(@_);

        my $uri = $self->_client->build_uri(
            "/projects/$args{project_id}/stories",
            \%args,
        );

        return [
            map {
                WebService::PivotalTracker::Story->new(
                    raw_content => $_,
                    pt_api      => $self,
                    )
            } @{ $self->_client->get($uri) }
        ];
    }
}

{
    my $check = compile(
        params => {
            story_id => PositiveInt,
        }
    );

    sub story {
        my $self = shift;
        my %args = $check->(@_);

        WebService::PivotalTracker::Story->new(
            raw_content => $self->_client->get(
                $self->_client->build_uri("/stories/$args{story_id}"),
            ),
            pt_api => $self,
        );
    }
}

{
    my $check = compile(
        params => {
            project_id => PositiveInt,
            label      => {
                type     => NonEmptyStr,
                optional => 1
            },
            limit => {
                type    => PositiveInt,
                default => 1,
            },
            offset => {
                type     => PositiveInt,
                optional => 1,
            },
            scope => {
                type     => IterationScope,
                optional => 1
            },
        },
    );

    sub project_iterations {
        my $self = shift;
        my %args = $check->(@_);

        my $uri = $self->_client->build_uri(
            "/projects/$args{project_id}/iterations",
            \%args,
        );

        return [
            map {
                WebService::PivotalTracker::ProjectIteration->new(
                    raw_content => $_,
                    pt_api      => $self,
                    )
            } @{ $self->_client->get($uri) }
        ];
    }
}

# XXX - if we want to add more create_X methods we should find a way to
# streamline & simplify this code so we don't have to repeat this sort of
# boilerplate over and over. Maybe each entity class should provide more
# detail about the properties, including type, coercions (like DateTime ->
# RFC3339 string), required for create/update, etc.
{
    ## no critic (Subroutines::ProtectPrivateSubs)
    my %props  = WebService::PivotalTracker::Story->_properties;
    my %params = map {
        $_ => blessed $props{$_}
            ? { type => $props{$_} }
            : { type => $props{$_}{type} }
    } keys %props;

    my %required = map { $_ => 1 } qw( project_id name );
    $params{$_}{optional} = 1 for grep { !$required{$_} } keys %props;

    %params = (
        %params,
        before_id => {
            type     => PositiveInt,
            optional => 1,
        },
        after_id => {
            type     => PositiveInt,
            optional => 1,
        },
        labels => {
            type => ArrayRef [NonEmptyStr],
            optional => 1
        },
    );

    my $check = compile(
        params => \%params,
    );

    sub create_story {
        my $self = shift;
        my %args = $check->(@_);

        $self->_deflate_datetime_values( \%args );

        my $project_id  = delete $args{project_id};
        my $raw_content = $self->_client->post(
            $self->_client->build_uri("/projects/$project_id/stories"),
            \%args,
        );

        return WebService::PivotalTracker::Story->new(
            raw_content => $raw_content,
            pt_api      => $self,
        );
    }
}

sub me {
    my $self = shift;

    return WebService::PivotalTracker::Me->new(
        raw_content =>
            $self->_client->get( $self->_client->build_uri('/me') ),
        pt_api => $self,
    );
}

sub _build_client {
    my $self = shift;

    return WebService::PivotalTracker::Client->new(
        token    => $self->token,
        base_uri => $self->base_uri,
        ( $self->_has_ua ? ( ua => $self->_ua ) : () ),
    );
}

sub _deflate_datetime_values {
    my $self = shift;
    my $args = shift;

    for my $key ( keys %{$args} ) {
        next unless blessed $args->{$key} && $args->{$key}->isa('DateTime');
        $args->{$key}
            = DateTime::Format::RFC3339->format_datetime( $args->{$key} );
    }

    return;
}

1;

# ABSTRACT: Perl library for the Pivotal Tracker REST API

__END__

=head1 SYNOPSIS

    my $pt =  WebService::PivotalTracker->new(
        token => '...',
    );
    my $story = $pt->story( story_id => 1234 );
    my $me = $pt->me;

    for my $label ( $story->labels ) { ... }

    for my $comment ( $story->comments ) { ... }

=head1 DESCRIPTION

B<This is very alpha (and as of yet mostly undocumented) software>.

This module provides a Perl interface to the L<Pivotal
Tracker|https://www.pivotaltracker.com/> REST API.
