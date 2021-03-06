# Movable Type (r) Open Source (C) 2001-2012 Six Apart, Ltd.
# This program is distributed under the terms of the
# GNU General Public License, version 2.
#
# $Id$

package MT::Website;

use strict;
use base qw( MT::Blog );

__PACKAGE__->install_properties(
    {   class_type    => 'website',
        child_classes => [
            'MT::Page',         'MT::Template',
            'MT::Asset',        'MT::Folder',
            'MT::Notification', 'MT::Log',
            'MT::ObjectTag',    'MT::Association',
            'MT::Comment',      'MT::TBPing',
            'MT::Trackback',    'MT::TemplateMap',
            'MT::Touch',
        ],
    }
);

sub class_label {
    return MT->translate("Website");
}

sub class_label_plural {
    MT->translate("Websites");
}

sub list_props {
    return {
        id         => { base => 'blog.id', },
        name       => { base => 'blog.name', },
        blog_count => {
            label        => 'Blogs',
            filter_label => '__BLOG_COUNT',
            order        => 200,
            base         => '__virtual.object_count',
            display      => 'default',
            count_class  => 'blog',
            count_col    => 'parent_id',
            filter_type  => 'blog_id',
            list_screen  => 'blog',
            count_terms  => sub {
                my $prop = shift;
                my ($opts) = @_;
                return {}
                    if MT->app->user->is_superuser;
                my @perms = MT->model('permission')->load(
                    {   author_id   => MT->instance->user->id,
                        permissions => { not => 'comment' },
                    },
                    { 'fetchonly' => ['blog_id'], },
                );

                return { id => [ map( $_->blog_id, @perms ) ] };
            },
        },
        page_count => {
            base      => 'blog.page_count',
            display   => 'default',
            html_link => sub {
                my $prop = shift;
                my ( $obj, $app ) = @_;
                my $link = $prop->super(@_);
                $link . '&filter=current_context';
            },
        },
        description => { base => 'blog.description' },
        entry_count => { view => [] },
        asset_count => {
            base      => 'blog.asset_count',
            html_link => sub {
                my $prop = shift;
                my ( $obj, $app ) = @_;
                my $link = $prop->super(@_);
                $link . '&filter=current_context';
            },
        },
        comment_count => {
            base      => 'blog.comment_count',
            html_link => sub {
                my $prop = shift;
                my ( $obj, $app ) = @_;
                my $link = $prop->super(@_);
                $link . '&filter=current_context';
            },
        },

        # not in use in 5.1
        # member_count => {
        #     base      => 'blog.member_count',
        #     html_link => sub {
        #         my $prop = shift;
        #         my ( $obj, $app ) = @_;
        #         my $link = $prop->super(@_);
        #         $link . '&filter=current_context';
        #     },
        # },
        theme_id => {
            base                  => 'blog.theme_id',
            single_select_options => sub {
                my $prop = shift;
                require MT::Theme;
                my $themes = MT::Theme->load_all_themes;
                return [
                    map { { label => $_->label, value => $_->id } }
                        sort { $a->label cmp $b->label }
                        grep {
                               $_->{class} eq 'website'
                            || $_->{class} eq 'both'
                        } values %$themes
                ];
            },
        },
        created_on  => { base => 'blog.created_on' },
        modified_on => { base => 'blog.modified_on' },
    };
}

sub create_default_website {
    my $class = shift;
    my ( $site_name, $site_theme ) = @_;
    $site_name ||= MT->translate("First Website");
    $class = ref $class if ref $class;

    my $website = new $class;
    $website->name($site_name);

    # Enable nofollow options
    $website->nofollow_urls(1);
    $website->follow_auth_links(1);

    # Enable default commenter authentication
    $website->commenter_authenticators( MT->config('DefaultCommenterAuth') );

    # set class type
    $website->class('website');

    $website->page_layout('layout-wtt');
    $website->theme_id($site_theme) if $site_theme;

    $website->save or return $class->error( $website->errstr );

    # Apply website theme
    if ($site_theme) {
        $website->apply_theme()
            or return $class->error( $website->errstr );
    }
    return $website;
}

sub blogs {
    my $class = shift;
    my ( $terms, $args ) = @_;

    my $blog_class = MT->model('blog');
    if ( $terms || $args ) {
        $terms ||= {};
        $terms->{class}     = 'blog';
        $terms->{parent_id} = $class->id;
        return [ $blog_class->load( $terms, $args ) ];
    }
    else {
        $class->cache_property(
            'blogs',
            sub {
                [   $blog_class->load(
                        {   parent_id => $class->id,
                            class     => 'blog'
                        }
                    )
                ];
            }
        );
    }
}

sub has_blog {
    my $class = shift;
    return scalar @{ $class->blogs } ? 1 : 0;
}

sub add_blog {
    my $website = shift;
    my ($blog) = @_;
    return unless $blog;

    $blog->parent_id( $website->id );
    $blog->save;

# Apply permission to website administrator if (s)he has manage_member_blogs permission.
    my $author_class   = MT->model('author');
    my @website_admins = $author_class->load(
        { type => MT::Author::AUTHOR(), },
        {   join => MT::Permission->join_on(
                'author_id',
                {   permissions => "\%'manage_member_blogs'\%",
                    blog_id     => $website->id,
                },
                { 'like' => { 'permissions' => 1 } }
            )
        }
    );
    if (@website_admins) {
        require MT::Association;
        require MT::Role;
        my $user = MT->instance->user;
        if ($user) {
            my @roles = MT::Role->load_by_permission("administer_blog");
            my $role;
            foreach my $r (@roles) {
                next if $r->permissions =~ m/\'administer_website\'/;
                $role = $r;
                last;
            }
            foreach my $adm (@website_admins) {
                MT::Association->link( $adm => $role => $blog );
            }
        }
    }
}

1;
__END__

=head1 NAME

MT::Website - Movable Type webpage record

=head1 SYNOPSIS

    use MT::Website;
    my $website = MT::Website->load($website_id);
    $website->name('Some new name');
    $website->save
        or die $website->errstr;

=head1 DESCRIPTION

The C<MT::Website> class is a subclass of L<MT::Blog>.

=head2 MT::Website->class_label

Returns the localized descriptive name for this class.

=head2 MT::Website->class_label_plural

Returns the localized, plural descriptive name for this class.

=head1 METHOD

=head2 blogs

Returns all blogs that belongs to the website.

=head1 AUTHOR & COPYRIGHTS

Please see the I<MT> manpage for author, copyright, and license information.

=cut
