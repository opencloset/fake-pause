#!/usr/bin/env perl

use Mojolicious::Lite;

use Path::Tiny;
use Try::Tiny;

#
# default config
#
app->defaults( %{ plugin Config => { default => { }}});

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

    {
        my $tempdir = Path::Tiny->tempdir;
        my $path    = $tempdir->child($filename);
        $file->move_to($path);

        my $cmd = app->config->{fakepause}{cmd}->(
            app->config->{fakepause}{repo},
            $user,
            $path,
        );

        try { system @$cmd } catch { app->log->warn("failed to inject") };
    }

    $self->render(text => 'auth success', status => 200);
};

app->secrets( app->defaults->{secrets} );
app->start;

__DATA__

@@ index.html.ep
% layout 'default';
% title 'SILEX Fake Pause';
<h1> SILEX Fake Pause </h1>

<div>
  <p>
    작업중인 프로젝트의 <code>dist.ini</code> 파일의 설정은 다음과 같습니다.
  </p>
  <pre>$ cat dist.ini
name             = Dist-Zilla-PluginBundle-SILEX
license          = Perl_5
copyright_holder = SILEX
copyright_year   = 2014
author           = 김도형 - Keedi Kim <keedi@cpan.org>

[@SILEX]
UploadToCPAN.upload_uri     = http://pause.silex.kr
UploadToCPAN.pause_cfg_file = /home/askdna/.pause.silex</pre>
</div>

<div>
  <p>
    <code>~/.pause.silex</code> 파일의 설정은 다음과 같습니다.
  </p>
  <pre>$ cat ~/.pause.silex
user     FAKEPAUSEID
password fakepausepw</pre>
</div>

@@ layouts/default.html.ep
<!DOCTYPE html>
<html>
  <head><title><%= title %></title></head>
  <body><%= content %></body>
</html>
