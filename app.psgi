#!/usr/bin/env perl

use utf8;

use Mojolicious::Lite;

use CPAN::Common::Index::LocalPackage;
use DateTime;
use MIME::Base64;
use Path::Tiny;
use Try::Tiny;

use OpenCloset::Schema;

#
# plugin
#
plugin 'haml_renderer';
plugin 'RenderFile';

#
# default config
#
app->defaults( %{ plugin Config => { default => {
    js_str  => q{},
    css_str => q{},
    jses    => [],
    csses   => [],
}}});

my $DB = OpenCloset::Schema->connect({
    dsn      => app->config->{fakepause}{database}{dsn},
    user     => app->config->{fakepause}{database}{user},
    password => app->config->{fakepause}{database}{pass},
    %{ app->config->{fakepause}{database}{opts} },
});

plugin Minion => { SQLite => 'sqlite:db/minion.db' };

plugin 'authentication' => {
    autoload_user => 1,
    load_user     => sub {
        my ( $app, $uid ) = @_;

        my $user_obj = $DB->resultset('User')->find({ id => $uid });

        return $user_obj
    },
    session_key   => 'access_token',
    validate_user => sub {
        my ( $self, $user, $pass, $extradata ) = @_;

        my $user_obj = $DB->resultset('User')->find({ email => $user });
        unless ($user_obj) {
            app->log->warn("cannot find such user: $user");
            return;
        }

        #
        # GitHub #199
        #
        # check expires when login
        #
        my $now = DateTime->now( time_zone => app->config->{timezone} )->epoch;
        unless ( $user_obj->expires && $user_obj->expires > $now ) {
            app->log->warn( "$user\'s password is expired" );
            return;
        }

        unless ( $user_obj->check_password($pass) ) {
            app->log->warn("$user\'s password is wrong");
            return;
        }

        unless ( $user_obj->user_info->staff ) {
            app->log->warn("$user is not a staff");
            return;
        }

        return $user_obj->id;
    },
};

app->minion->add_task(
    orepan_indexing => sub {
        my ($job, $module) = @_;

        $job->app->log->info("Orepan Indexing for [$module]...");
        $job->app->log->info('$ orepan2-indexer ' . $job->app->config->{fakepause}{repo});
        system "orepan2-indexer", $job->app->config->{fakepause}{repo};
        $job->app->log->info("Done");
    }
);

get '/' => sub {
    my $self = shift;

    my $path = path( app->config->{fakepause}{repo} . "/modules/02packages.details.txt.gz" );
    my @modules;
    if ( $path->exists ) {
        my $index   = CPAN::Common::Index::LocalPackage->new({ source => $path });
        @modules = $index->search_packages({ package => qr/.*/ });
    }

    $self->stash( modules => \@modules );
    $self->render( 'index' );
};

get '/#id/#tarball' => sub {
    my $self = shift;

    my $id      = $self->param('id');
    my $tarball = $self->param('tarball');

    my $path = path(
        app->config->{fakepause}{repo} . sprintf(
            "/authors/id/%s/%s/%s/%s",
            substr( $id, 0, 1 ),
            substr( $id, 0, 2 ),
            $id,
            $tarball,
        )
    );
    unless ( $path->exists ) {
        app->log->warn("failed to find $path");
        $self->render_not_found;
        return;
    }

    my $ret = $self->render_file(
        filepath => $path,
        filename => $path->basename,
    );
    unless ($ret) {
        app->log->warn("failed to preparing $path");
        $self->render_not_found;
        return;
    }
};

post '/' => sub {
    my $self = shift;

    my $user     = $self->param('HIDDENNAME');
    my $filename = $self->param('pause99_add_uri_upload');
    my $file     = $self->param('pause99_add_uri_httpupload');

    my ( $type, $auth ) = split q{ }, $self->req->headers->authorization;

    return $self->render(text => 'type is required', status => 401) unless $type;
    return $self->render(text => 'auth is required', status => 401) unless $auth;
    return $self->render(text => 'type is invalid',  status => 401) unless $type eq 'Basic';

    my ( $u, $p ) = split q{:}, decode_base64($auth);
    return $self->render(text => 'user is invalid',  status => 401) unless $user eq $u;
    return $self->render(text => 'auth failed',      status => 401) unless $self->authenticate( lc($u), $p );

    my $module = join(
        '/',
        'authors',
        'id',
        substr( uc($user), 0, 1 ),
        substr( uc($user), 0, 2 ),
        uc($user),
        $filename,
    );

    my $path = path( app->config->{fakepause}{repo} . "/$module" )->touchpath;
    $file->move_to($path);

    my $uri = $self->url_for("/$module")->to_abs;
    app->log->info("uploaded to $uri");

    $self->minion->enqueue(orepan_indexing => [$module]);

    $self->render(text => $uri, status => 200);
};

app->sessions->cookie_name( app->config->{cookie}{name} );
app->sessions->cookie_path( app->config->{cookie}{path} );
app->secrets( app->defaults->{secrets} );
app->start;

__DATA__

@@ index.html.haml
- layout 'default';
- title 'OpenCloset Perl Modules';

%h1 OpenCloset Perl Modules

%h2 Module List

%table.table.table-striped.table-bordered.table-hover
  %thead
    %tr
      %th.center #
      %th 이름
      %th 버전
  %tbody
    - use Path::Tiny;
    - my $count = 0;
    - my %main_modules;
    - for my $module (@$modules) {
    -   ( my $uri = $module->{uri} ) =~ s{^cpan:///distfile}{};
    -   my @namespaces = split '-', path($uri)->basename;
    -   pop @namespaces;
    -   my $main_module = join '::', @namespaces;
    -   push @{ $main_modules{$main_module} }, $module;
    -   next if @{ $main_modules{$main_module} } > 1;
      %tr
        %td.center= ++$count;
        %td
          %a{ :href => "#{ url_for($uri) }" }= $main_module;
        %td
          %a{ :href => "#{ url_for($uri) }" }= $module->{version};
    - }

%h2 How-To FakePause

%h3 Dist::Zilla::Plugin::UploadToCPAN
%div
  %p
    != q{<code>Dist::Zilla</code>를 사용할 경우 <code>dist.ini</code> 파일에}
    != q{<code>UploadToCPAN</code> 플러그인 설정을 추가합니다.}
  :plain
    <pre>
      $ cat dist.ini
      name             = Your-Awesome-Module
      license          = Perl_5
      copyright_holder = SILEX
      copyright_year   = 2014
      author           = 김도형 - Keedi Kim <keedi@cpan.org>

      [UploadToCPAN]
      upload_uri     = https://cpan.theopencloset.net
      pause_cfg_dir  = .
      pause_cfg_file = .pause


    </pre>
  %p
    != q{<code>Dist::Zilla::PluginBundle::DAGOLDEN</code> 플러그인 번들이나}
    != q{<code>Dist::Zilla::PluginBundle::SILEX</code> 플러그인 번들을 사용할 경우}
    != q{<code>dist.ini</code> 파일에 <code>UploadToCPAN</code> 설정을 추가합니다.}
  :plain
    <pre>
      $ cat dist.ini
      name             = Your-Awesome-Module
      license          = Perl_5
      copyright_holder = SILEX
      copyright_year   = 2014
      author           = 김도형 - Keedi Kim <keedi@cpan.org>

      [@DAGOLDEN]
      UploadToCPAN.upload_uri     = https://cpan.theopencloset.net
      UploadToCPAN.pause_cfg_dir  = .
      UploadToCPAN.pause_cfg_file = .pause
    </pre>

%h3 .pause
%div
  %p
    != q{<code>.pause</code> 파일 내용은 다음과 같습니다.}
  :plain
    <pre>
      $ cat .pause.silex
      user     FAKEPAUSEID
      password fakepausepw</pre>
    </pre>
  %p
    != q{<code>pause_cfg_dir</code> 값을 설정하지 않으면 홈디렉터리를 기본으로 설정하므로 주의합니다.}

@@ layouts/default.html.haml
!!! 5
%html
  %head
    %title= "$project_name - " . title
    %link{ :rel => 'icon', :type => 'image/png', :href => '/icon.png' }
    = include 'layouts/default/meta'
    = include 'layouts/default/css'
    = include 'layouts/default/js'

  %body
    = include 'layouts/default/nav'
    #content
      .container
        .row
          .col-lg-9
            = content

    = include 'layouts/default/footer'
    = include 'layouts/default/body-js'
    = include 'layouts/default/google-analytics'

@@ layouts/default/meta.html.haml
/ META
    %meta{:charset => "utf-8"}
    %meta{:name => "author",                                content => "Keedi Kim"}
    %meta{:name => "description",                           content => "#{$project_desc}"}
    %meta{:name => "apple-mobile-web-app-capable",          content => "yes"}
    %meta{:name => "apple-mobile-web-app-status-bar-style", content => "black-translucent"}

@@ layouts/default/css.html.haml
/ CSS
    %link{:rel => "stylesheet", :type => "text/css", :href => "//fonts.googleapis.com/css?family=Open+Sans:400italic,600italic,400,600"}
    %link{:rel => "stylesheet", :type => "text/css", :href => "//fonts.googleapis.com/earlyaccess/nanumgothic.css"}
    %link{:rel => "stylesheet", :type => "text/css", :href => "//fonts.googleapis.com/earlyaccess/nanumgothiccoding.css"}
    %link{:rel => "stylesheet", :type => "text/css", :href => "//netdna.bootstrapcdn.com/font-awesome/4.0.3/css/font-awesome.min.css"}
    %link{:rel => "stylesheet", :type => "text/css", :href => "//netdna.bootstrapcdn.com/bootswatch/3.1.1/flatly/bootstrap.min.css"}
    - for my $css (@$csses) {
      %link{:rel => "stylesheet", :type => "text/css", :href => "#{$css}"}
    - }
    - if ($css_str) {
      :css
        #{ $css_str }
    - }

@@ layouts/default/js.html.haml
/ Javascript
    / Le HTML5 shim, for IE6-8 support of HTML5 elements
    /[if lt IE 9]
      %script{ :type => "text/javascript" :src => "//html5shim.googlecode.com/svn/trunk/html5.js" }

@@ layouts/default/footer.html.haml
/ Footer
    #footer
      .container
        %ul.list-unstyled
          %li.pull-right
            %a{ :href => "#top" } Back to top
      .container
        %hr/
        .span6!= qq{&copy; $copyright. All Rights Reserved.}
        .span4.offset1
          %span.pull-right
            Built by
            %a{ :href => "http://bootswatch.com" } Bootswatch
            ,
            %a{ :href => "http://mojolicio.us" } Mojolicious
            &
            %a{ :href => "http://www.perl.org" } Perl

@@ layouts/default/body-js.html.haml
/ Javascript in body
    %script{ :type => "text/javascript" :src => "//ajax.googleapis.com/ajax/libs/jquery/2.1.0/jquery.min.js" }
    %script{ :type => "text/javascript" :src => "//netdna.bootstrapcdn.com/bootstrap/3.1.1/js/bootstrap.min.js" }
    - for my $js (@$jses) {
      %script{ :type => "text/javascript" :src => "#{$js}" }
    - }
    - if ($js_str) {
      :javascript
        $(function() {
          #{ $js_str }
        });
    - }

@@ layouts/default/google-analytics.html.haml
/ google analytics
    - if ($google_analytics) {
      :javascript
        var gaJsHost = (("https:" == document.location.protocol) ? "https://ssl." : "http://www.");
        document.write(unescape("%3Cscript src='" + gaJsHost + "google-analytics.com/ga.js' type='text/javascript'%3E%3C/script%3E"));
      :javascript
        try {
          var pageTracker = _gat._getTracker("#{ $google_analytics }");
          pageTracker._trackPageview();
        } catch(err) {}
    - }

@@ layouts/error.html.haml
!!! 5
%html
  %head
    %title= "$project_name - " . title
    = include 'layouts/default/meta'
    = include 'layouts/default/css'
    = include 'layouts/default/js'

  %body
    = include 'layouts/default/nav'

    #content
      .container
        .row
          .span2
            = include 'layouts/default/header'
          .span10
            .widget
              = content

    = include 'layouts/default/footer'
    = include 'layouts/default/body-js'
    = include 'layouts/default/google-analytics'

@@ not_found.html.haml
- layout 'error', csses => [ 'error.css' ], jses => [];
- title '404 Not Found';
%h2 404 Not Found

.error-details Sorry, an error has occured, Requested page not found!

@@ layouts/default/nav.html.haml
/ navigation
    .navbar.navbar-default.navbar-fixed-top
      .container
        .navbar-header
          %a.navbar-brand{ :href => "/" }= $project_name
          %button.navbar-toggle{ type => "button", 'data-toggle' => "collapse", 'data-target' => "#navbar-main" }
            %span.icon-bar
            %span.icon-bar
            %span.icon-bar
        #navbar-main.navbar-collapse.collapse
          - if ( @{ $nav_links->{left} } ) {
            %ul.nav.navbar-nav
              - for my $link ( @{ $nav_links->{left} } ) {
                %li
                  %a{ :href => "#{ $link->{url} }" }= $link->{desc}
              - }
          - }
          - if ( @{ $nav_links->{right} } ) {
            %ul.nav.navbar-nav.navbar-right
              - for my $link ( @{ $nav_links->{right} } ) {
                %li
                  %a{ :href => "#{ $link->{url} }", :target => "_blank" }= $link->{desc}
              - }
          - }
