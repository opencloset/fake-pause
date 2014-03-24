#!/usr/bin/env perl

use utf8;

use Mojolicious::Lite;

use Path::Tiny;
use Try::Tiny;

#
# plugin
#
plugin 'haml_renderer';

#
# default config
#
app->defaults( %{ plugin Config => { default => {
    js_str  => q{},
    css_str => q{},
    jses    => [],
    csses   => [],
}}});

get '/' => sub {
  my $self = shift;
  $self->render('index');
};

post '/' => sub {
    my $self = shift;

    my $user     = $self->param('HIDDENNAME');
    my $filename = $self->param('pause99_add_uri_upload');
    my $file     = $self->param('pause99_add_uri_httpupload');

    my ( $type, $auth ) = split q{ }, $self->req->headers->authorization;

    return $self->render(text => 'auth failed', status => 401)
        unless
            $type eq 'Basic'
            && app->config->{fakepause}{auth}{$user}
            && app->config->{fakepause}{auth}{$user} eq $auth
            ;

    my $module = join(
        '/',
        'id',
        substr( lc($user), 0, 1 ),
        substr( lc($user), 0, 2 ),
        lc($user),
        $filename,
    );

    my $path = path( app->config->{fakepause}{repo} . "/$module" )->touchpath;
    $file->move_to($path);

    #
    # for reverse proxy
    #
    my $uri = $self->req->headers->header('x-original-uri') || q{};
    $uri =~ s{/$}{};
    $uri .= "/$module";

    app->log->info( "uploaded to " . $self->url_for($uri)->to_abs );
    $self->render(text => $self->url_for($uri)->to_abs, status => 200);
};

app->secrets( app->defaults->{secrets} );
app->start;

__DATA__

@@ index.html.haml
- layout 'default';
- title 'README';

%h1 How-To FakePause

%h2 Dist::Zilla::Plugin::UploadToCPAN
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
      upload_uri     = https://darkpan.silex.kr/pause
      pause_cfg_file = /home/askdna/.pause.silex
    </pre>
  %p
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

      [@SILEX]
      UploadToCPAN.upload_uri     = https://darkpan.silex.kr/pause
      UploadToCPAN.pause_cfg_file = /home/askdna/.pause.silex
    </pre>

%h2 ~/.pause.silex
%div
  %p
    != q{<code>~/.pause.silex</code> 파일 내용은 다음과 같습니다.}
  :plain
    <pre>
      $ cat ~/.pause.silex
      user     FAKEPAUSEID
      password fakepausepw</pre>
    </pre>

@@ layouts/default.html.haml
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
