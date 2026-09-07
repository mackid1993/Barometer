#!/usr/bin/perl
use strict;
use warnings;
use DynaLoader;

die "usage: now-playing-reader.pl BRIDGE\n" unless @ARGV == 1;
my $bridge = DynaLoader::dl_load_file($ARGV[0], 0)
    or die "could not load Now Playing bridge\n";
my $symbol = DynaLoader::dl_find_symbol($bridge, "_barometer_now_playing_get")
    || DynaLoader::dl_find_symbol($bridge, "barometer_now_playing_get")
    or die "Now Playing bridge entry point is missing\n";
DynaLoader::dl_install_xsub("main::barometer_now_playing_get", $symbol);
barometer_now_playing_get();
