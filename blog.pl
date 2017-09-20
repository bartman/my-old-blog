#!/usr/bin/perl -w
use strict;
use warnings;
use CGI qw( :standard );
use IO::File;
use File::Find::Rule;
use POSIX qw( strftime );

#use Inline (Config => DIRECTORY => '/tmp/bart-blog-inline');
use Inline TT => 'DATA';

my $conf = {
	title    => "Bart's Blog",
	data_dir => '/home/jukie/bart/.blog/entries',
	timezone => 'Canada/Eastern',
	url_base => script_name(),
	host_name => virtual_host(),

	# fix me: don't know how to pass the fact that we are viewing one
	# article into formatted_body()
	hack_single => 0,
	
	meta      => {

		# See http://geourl.org/
		ICBM => '45.36642,-75.74261',
		
		# See http://geotags.com/
		geo  => {
			region    => 'CA.ON',
			placename => 'Ottawa',
		},
	}
};


# Check for CSS first before reading article files
for( path_info() ) {
	m!/blog.css$! && do {
		print header('text/css');
		print stylesheet({});
		exit(0);
	};
}


my %articles = %{Article->load_many({
	data_dir => $conf->{data_dir}
}) };

my @all_articles = reverse sort grep { /^\d{14}$/ } keys %articles;
my %tagged_articles;
foreach my $key ( @all_articles ) {
	foreach my $tag ( $articles{$key}->tags ) {
		$tagged_articles{$tag} = () unless exists $tagged_articles{$tag};
		push @{$tagged_articles{$tag}}, $key;
	}
}
my @current_articles;

for( path_info() ) {

	# Produce feed
	m!^/feed.xml$! && do {
		my $latest = $all_articles[0];
		# TODO: handle Conditional GET by checking ETag and Last-Modified: headers and return 304 if no change
		print header(
			  -type => 'application/rss+xml',
			  -etag => qq{"$latest"},
			  -last_modified => strftime("%a, %d %b %Y %H:%M:%S %Z", (gmtime($articles{$latest}->{mtime}))),
			  -whatever => $articles{$latest}{mtime},
		      ),
		      xml_articles({ 
				conf => $conf, 
				articles => [ @articles{ @all_articles[0 .. 9] } ]
		});
		exit(0);
	};

	# Produce feed
	m!^/full.xml$! && do {
		my $latest = $all_articles[0];
		# TODO: handle Conditional GET by checking ETag and Last-Modified: headers and return 304 if no change
                $conf->{hack_single} = 1;
		print header(
			  -type => 'application/rss+xml',
			  -etag => qq{"$latest"},
			  -last_modified => strftime("%a, %d %b %Y %H:%M:%S %Z", (gmtime($articles{$latest}->{mtime}))),
			  -whatever => $articles{$latest}{mtime},
		      ),
		      xml_articles({ 
				conf => $conf, 
				articles => [ @articles{ @all_articles[0 .. 9] } ]
		});
		exit(0);
	};

	# Handle tags
	m!^/(r?)tag/([^/]+)$! && do {
		my $reversed = $1;
		my $tag = $2;
		if( exists $tagged_articles{$tag} ) {
			@current_articles = @{ $tagged_articles{ $tag } };
			@current_articles = reverse @current_articles if $reversed;
			last;
		}
		print header(
			-type   => 'text/html',
			-status => '404 File Not Found' ),
		      error_404( { conf => $conf, entry_name => $_ } );
		exit(0);
	};

	# Handle date-based searches
	m!^/date/(\d{4})/?(\d{2})?/?(\d{2})?$! && do {
		my ($yy,$mm,$dd) = ($1,$2,$3);
		
		my %what = defined $dd ? ( days   => 1 )
			 : defined $mm ? ( months => 1 )
			 :               ( years  => 1 );
		my $dur   = DateTime::Duration->new( %what );

		$mm ||= 1;
		$dd ||= 1;
		my $start = DateTime->new( year => $yy, month => $mm, day => $dd );
		$start->set_time_zone( $conf->{timezone} );
		
		my $extra = Article->load_many({
			data_dir   => $conf->{data_dir},
			date_start => $start->epoch,
			date_end   => ($start + $dur)->epoch,
		});
		
		@current_articles = grep { /^\d{14}$/ } keys %$extra;
		for my $key ( @current_articles ) { 
			$articles{$key} = $extra->{$key} unless exists $articles{$key};
		}
		last;
	};

	# Handle single article
	m!^/([^/]+)$! && do {
		my $key = $1;
		if( exists $articles{$key} ) {
			@current_articles = ( $key );
			$conf->{hack_single} = 1;
			last;
		}
		print header(
			-type   => 'text/html',
			-status => '404 File Not Found' ),
		      error_404( { conf => $conf, entry_name => $_ } );
		exit(0);
	};

	# Handle list page by default
	@current_articles = @all_articles;

}

if (scalar(@current_articles) > 10) {
        @current_articles = @current_articles[0..9];
}

print header,
	top({ 
		conf    => $conf,
		title   => (scalar(@current_articles) == 1) 
		            ? $articles{ $current_articles[0] }->{subject} . " - $conf->{title}"
			    : $conf->{title},
		current => path_info(),
	}),
	articles({ 
		conf     => $conf, 
		articles => [ @articles{ @current_articles } ],
	}),
	leftbar({ 
		conf     => $conf, 
		articles => [ @articles{ @all_articles } ],
		tags     => [
			map +{ name => $_, weight => log(scalar @{$tagged_articles{$_}})*3 },
                                sort {uc($a) cmp uc($b)} keys %tagged_articles
		],
		current => path_info(),
	}),
	rightbar({ 
		conf     => $conf,
		articles => [ @articles{ @all_articles } ],
		tags     => [
			map +{ name => $_, weight => log(scalar @{$tagged_articles{$_}})*3 },
                                sort {uc($a) cmp uc($b)} keys %tagged_articles
		]
	}),
	bottom({});

exit(0);

package Article;
use File::Basename;
use DateTime;
#use lib "/home/jukie/bart/public_html/";
use Text::Markdown 'markdown';

sub new 
{
	my ($class, $args) = @_;

	$args->{key}   = basename( $args->{filename} );

	my $self = bless $args, $class;

	$self->load();
	
	return $self;
}

sub load
{
	my ($self) = @_;

	my $fh = new IO::File $self->{filename}, 'r';
	if( ! defined $fh ) {
		die "Couldn't open $self->{filename}";
	}

	while( my $line = <$fh> ) {
		chomp;
		last if $line !~ /:/;
		last if $line =~ /^$/;
		my ($key, $value) = $line =~ m/\s*([^\s:]+):\s*(.*?)\s*$/;
		$self->{lc $key} = $value;
	}

	{ 
		local $/;
		$self->{body} = <$fh>;
	}
	close $fh;

	my $date = DateTime->from_epoch( epoch => (stat($self->{filename}))[9]);
	$date->set_time_zone( $conf->{timezone} );
	$self->{mtime} = $date->epoch;

	if( ! exists $self->{'content-type'} ) {
		if( $self->{body} =~ /^</ ) {
			$self->{'content-type'} = 'text/html';
		} else {
			$self->{'content-type'} = 'text/plain';
		}
	}

        if ($self->{'content-type'} eq 'text/x-markdown') {

                my $base = $conf->{url_base};

                # convert [text]{anything} to [text]($url_base/anything) which
                # makes markdown generate <a href=$url_base/anything>text</a>
                $self->{body} =~ s!(\[[^\]]+\])\{([^\}]+)\}!$1($base/$2)!g;
        }
}

sub list
{
	my ($class, $args) = @_;
	my $find = File::Find::Rule->new()
	   ->file
	   ->nonempty
	   ->readable
	   ->maxdepth(1)
	   ->name( qr/^\d{14}$/ )
	   ->mtime( '<=' .  time() );

	return $find->in($args->{data_dir});
}

sub load_many
{
	my ($class, $args) = @_;

	$args->{date_start} ||= DateTime->now->subtract( months => 480)->epoch;
	$args->{date_end}   ||= DateTime->now->epoch;

	my $find = File::Find::Rule->new()
	   ->file
	   ->nonempty
	   ->readable
	   ->maxdepth(1)
	   ->name( qr/^\d{14}$/ )
	   ->mtime( '>=' .  $args->{date_start} )
	   ->mtime( '<=' .  $args->{date_end} );

	my %articles;
	foreach ( $find->in($args->{data_dir}) ) {
		my $a = $class->new({filename => $_}); 
		$articles{$a->{key}}   = $a;
		$articles{$a->{alias}} = $a if exists $a->{alias};
	}

	return \%articles;
}

sub formatted_body 
{
	my ($self) = @_;
	my $formats = { 
		'text/plain'      => sub { return "<pre>$_[0]</pre>" },
		'text/html'       => sub { return $_[0] },
		'text/x-markdown' => sub { return markdown($_[0]) },
	};

	my $out = $formats->{$self->{'content-type'}}->($self->{body})
	    if exists $formats->{$self->{'content-type'}};

	# convert ^<read-more>$ and everything that follows 
	# to a Read More link
	if (not $conf->{hack_single}) {
                my $base = $conf->{url_base};
		my $key  = $self->{alias} ? $self->{alias} : $self->{key};
		my $link = "<a href=$base/$key>[Read More]</a>";
		$out =~ s!((<br>|<p>))\s*<read-more>\s*((<br>|</p>)).*$!\n$1$link$2!s;
	} else {
		$out =~ s!(<br>|<p>)\s*<read-more>\s*(<br>|</p>)!\n!s;
	}

	return $out;
}

sub tags
{
	my ($self) = @_;
	if( exists $self->{tags} ) {
		return split(/\s*,\s*/,$self->{tags});
	}
}

package main;

__DATA__
__TT__
[% BLOCK top %]
<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Transitional//EN"
        "http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd">
<html xmlns="http://www.w3.org/1999/xhtml" xml:lang="en" lang="en">
  <head>
    <title>[% title %]</title>
    <meta name="ICBM" content="[% conf.meta.ICBM %]" /> 
    <meta name="geo.region" content="[% conf.meta.geo.region %]" /> 
    <meta name="geo.placename" content="[% conf.meta.geo.placename %]" /> 
    <META name="keywords" content="embedded, arm, packet, ipv6, consultant, blog, android, consulting, programmer, linux, unix, c, c++, geek, port, porting, debug, thread, multithreaded, macos, linux, unix, software development, consulting, contract programming, assembly, assembler, amd64, x86, opteron, cross-platform, jukie, bart, cross, platform, object-oriented, object, security, ipsec, ssl, ssh, algorithm, sdk, reverse engineering, android, vim, git, zsh, hacker">
    <link rel="alternate" type="application/rss+xml" title="RSS" href="[% conf.url_base %]/feed.xml" /> 
    <link rel="stylesheet" type="text/css" media="all" href="[% conf.url_base %]/blog.css" />
    <link rel="shortcut icon" href="/~bart/blog.ico" type="image/x-icon">
  </head>
  <body>
    <!--
    <h1><a href="[% conf.url_base %]">[% conf.title %]</a></h1>
    -->

    <!--
    [% IF current %]<h4>Now viewing: <a href="[% conf.url_base %][% current %]">[% current %]</a></h4>[% END %]
    -->
[% END %]

[% BLOCK bottom %]
    <br><br><br>
    <div class="content">
    <hr>
    <p align=right>
    Bart Trojanowski<br>
    <a href=http://www.jukie.net/~bart>http://www.jukie.net/~bart</a><br>
    <a href=mailto:bart@jukie.net>bart@jukie.net</a>
    </p>

    <!-- google analytics
        <script type="text/javascript">
        var gaJsHost = (("https:" == document.location.protocol) ? "https://ssl." : "http://www.");
        document.write(unescape("%3Cscript src='" + gaJsHost + "google-analytics.com/ga.js' type='text/javascript'%3E%3C/script%3E"));
        </script>
        <script type="text/javascript">
        try {
                var pageTracker = _gat._getTracker("UA-6605981-1");
                pageTracker._trackPageview();
        } catch(err) {}</script>
    -->
    </div>
  </body>
</html>
[% END %]


[% BLOCK article %]
[% USE date %]
<div class='article'>
  <h2>[% article.subject %]</h2>
  <!--
  <h2><a href='[% conf.url_base %]/[% article.alias ? article.alias : article.key %]'>[% article.subject %]</a></h2>
  -->
  <h4>[ link: <a href='[% conf.url_base %]/[% article.alias ? article.alias : article.key %]'>[% article.alias ? article.alias : article.key %]</a> 
  | tags:
  [% FOREACH tag = article.tags %]
      <a href='[% conf.url_base %]/tag/[% tag %]'>[% tag %]</a>
  [% END %]
  | updated: [% date.format(article.mtime, '%a, %d  %b  %Y  %H:%M:%S  %z') %] ]</h4>
  <div class='article_body'>
	[% article.formatted_body ? article.formatted_body : article.body %]
  </div>
</div>
[% END %]

[% BLOCK articles %]
<div class="content">
[% FOREACH article = articles %]
[% PROCESS article %]
[% END %]
</div>
[% END %]

[% BLOCK leftbar %]
    <div id="leftbar_container">
        <h1><a href="[% conf.url_base %]">[% conf.title %]</a></h1>

    [% IF current %]<p align=right><a href="[% conf.url_base %][% current %]">[% current %]</a></p>[% END %]

    <div id="leftbar">

        <h3>About</h3>
            <!--
            I am an embedded Linux software developer and <a href=http://www.jukie.net/~bart/consulting/>consultant</a>
            operating under <a href=http://www.jukie.net/>Jukie Networks Inc<a/> in Ottawa, Canada.
            -->

            I am a Linux driver, kernel, and embedded software developer,
            currently working for <a href=http://www.diablo-technologies.com/>Diablo Technologies Inc</a>.

            <ul>
            <li><a href="http://www.jukie.net/~bart/sig">contact info</a>
            <li><a href="http://www.jukie.net/~bart/resume">resume</a>
            <li><a href=http://git.jukie.net/>git archive</a>
            <li><a href="http://gallery.jukie.net">pictures</a>
            </ul>

            <!--
            <font color=#008800>I am interested in low-level embedded contract work.</font>
            -->

         <p>
             <a href="http://www.prchecker.info/" target="_blank"><img
             align=left src="http://www.prchecker.info/PR3_img.gif" alt="" border="0" /></a>
         <br><br>
             <a href="[% conf.url_base %]/feed.xml"><img align=left
                   src="/img/rssbanner.png"
                   alt="RSS Feed - Full Content" height="15" width="80" border="0"/></a>
         <br><br>
             <a href="[% conf.url_base %]/full.xml"><img align=left
                   src="/img/rss_fullposts.png"
                   alt="RSS Feed - Full Content" height="15" width="80" border="0"/></a>
         <br><br>
            <!-- IPv6-test.com button BEGIN -->
            <a href='http://ipv6-test.com/validate.php?url=referer'><img
            src='http://ipv6-test.com/button-ipv6-80x15.png' alt='ipv6 ready'
            title='ipv6 ready' border='0' /></a>
            <!-- IPv6-test.com button END -->
         <br><br>
             <a href="http://validator.w3.org/check?uri=referer"><img
             align=left
                   src="/img/valid_xhtml10.png"
                   alt="Valid XHTML 1.0 Transitional" height="15" width="80" border="0"/></a>
         <br><br>
             <a href="http://www.vim.org"><img align=left
                   src="/img/vim_the_editor.png"
                   alt="Created with Vim" height="15" width="80" border="0"/></a>
         <br><br>
             <a href="http://www.perl.org"><img align=left
                   src="/img/perl.png"
                   alt="Created with Perl" height="15" width="80" border="0"/></a>
         <br><br>
             <a
             href="http://www2.clustrmaps.com/counter/maps.php?url=http://www.jukie.net/"><img
             align=left border=0 src="http://www2.clustrmaps.com/stats/maps-no_clusters/www.jukie.net--thumb.jpg"/></a><br>

         <br><br>
         <script src="http://www.gmodules.com/ig/ifr?url=http://www.google.com/coop/api/008986818207157353292/cse/mpgqixlgxqq/gadget&amp;synd=open&amp;w=150&amp;h=150&amp;title=Search+Bart's+stuff&amp;border=%23ffffff%7C0px%2C1px+solid+%23004488%7C0px%2C1px+solid+%23005599%7C0px%2C1px+solid+%230077BB%7C0px%2C1px+solid+%230088CC&amp;output=js"></script>

             <!-- AddThis Button BEGIN -->
             <script type="text/javascript">addthis_pub  = 'bartman';</script> <a href="http://www.addthis.com/bookmark.php" onmouseover="return addthis_open(this, '', '[URL]', '[TITLE]')" onmouseout="addthis_close()"
             onclick="return addthis_sendto()"><img align=left src="http://s7.addthis.com/button1-share.gif" width="125" height="16" border="0" alt="" /></a><script type="text/javascript" src="http://s7.addthis.com/js/152/addthis_widget.js"></script>
             <!-- AddThis Button END -->
         </p>

        <p>
    </div>
    </div>
[% END %]


[% BLOCK rightbar %]
    <div id="rightbar_container">

    <div id="rightbar">
        <h3>Tags</h3>
        <p align=right>
            [% FOREACH tag = tags %]
            <span style='font-size: [% tag.weight + 6 %]pt'><a href="[% conf.url_base %]/tag/[% tag.name %]">[% tag.name %]</a></span>
            [% END %]
        </p>

        <h3>Posts</h3>
        <p align=right>
            [% FOREACH article = articles %]
            <p align=right> [ <a href="[% conf.url_base %]/[% article.alias ? article.alias : article.key %]">[% article.key %]</a> ]<br />[% article.subject %] </p>
            [% END %]
        </p>

    </div>
    </div>
[% END %]


[% BLOCK stylesheet %]
body { 
	color: black;
	background: white;
	font-size: 10pt;
	padding-left: 1%;
	padding-right: 1%;
}

h1, h2, h3 { 
	font-family: lucida, verdana, helvetica, arial, sans-serif;
	font-style: normal;
	font-variant: normal;
	font-weight: bolder;
}

h1 {
	color: #039;
}

h1 a {
	text-decoration: none;
	color: #039;
}

h2 {
	border-top: 1px solid black;
        border-bottom: 1px solid black; 
	background-color: #ffffcc;
	margin-bottom: 0;
}

#leftbar h3 {
	font-size: 12pt;
	margin-left: -10px;
	margin-bottom: 0;
}

#rightbar h3 {
	font-size: 12pt;
	margin-left: -10px;
	margin-bottom: 0;
	text-align: right;
}

h4 {
	margin-top: 0;
	font-size: 10pt;
	font-weight: normal;
	text-align: right;
}

h4.middle {
        text-align: center;
}

.article h4 {
	background-color: #ffffee;
}

.content {
	margin-left: 200px;
	margin-right: 200px;
}

.article_body {
	padding-left: 20px;
	                padding-right: 2px;
	                border-left: 1px solid #eeeeee; 
	                border-right: 1px solid #eeeeee; 
}

code {
        color: #006600;
	background: #EEEEEE;
        display: inline; 
        overflow-x:auto;
}

pre code { 
        color: #006600;
	background: #EEEEEE;
        display: block;
        margin: 0px;
}

#leftbar_container {
	float: left;
	width: 180px;
	margin: 0;
	padding: 0em;
        position:absolute;
        top: 0;
        left: 0;
}

#leftbar {
	width: 160px;
	margin: 0;
	padding: 1em;
}

#rightbar_container {
	float: right;
	width: 180px;
        margin: 0;
	padding: 0em;
        position:absolute;
        top: 0;
        right: 0;
        #background-color: white;
}

#rightbar {
	float: right;
	width: 160px;
        margin: 0;
	padding: 1em;
}

.float-right {/* header element float */
        float: right;
        margin: 0 0 0 0.2em;
}



[% END %]

[% BLOCK xml_articles %]
[% USE date %]
<rss version="0.92" xml:base="[% conf.url_base %]">
  <channel>
    <title>[% conf.title %]</title>
    <link>http://[% conf.host_name %][% conf.url_base %]</link>
    <description></description>
    <language>en</language>

    [% FOREACH item = articles %]
    <item>
      <title>[% item.subject %]</title>
      <link>http://[% conf.host_name %][% conf.url_base %]/[% item.key %]</link>
      [% FOREACH tag = item.tags %]
        <category>[% tag %]</category>
      [% END %]
      <description>
	<![CDATA[ [% item.formatted_body ? item.formatted_body : item.body %]
      ]]></description>
      <pubDate>[% date.format(item.mtime, '%a, %d  %b  %Y  %H:%M:%S  %Z') %]</pubDate>
    </item>
    
    [% END %]
  </channel>
</rss>
[% END %]

[% BLOCK error_404 %]
<!DOCTYPE HTML PUBLIC "-//IETF//DTD HTML 2.0//EN">
<HTML><HEAD>
<TITLE>404 Not Found</TITLE>
</HEAD><BODY>
<H1>Not Found</H1>
The blog entry [% entry_name | html_entity %] was not found.
</BODY></HTML>
[% END %]
