#!/usr/bin/env perl
################################################################################
BEGIN {
        # figure out where we are and include our relative lib directory
        use Cwd;
        my $script=$0;
        my $pwd = getcwd();
        my $libdir = $pwd;
        if($0=~s/(.*)\/([^\/]*)//){
            $script = $2;
            my $oldpwd = $pwd;
            chdir($1);
            $pwd = getcwd();
            if($libdir=~m/\/bin$/){
                $libdir=$pwd; $libdir=~s/\/bin$/\/lib/;
            }else{
                $libdir="$pwd/lib";
            }
        }
        unshift(@INC,"$libdir") if ( -d "$libdir");
      }
################################################################################
use POE::Wheel::Run;
use PedalWatcher;

$|=1;
my $pw  = PedalWatcher->new({ 
                              'input'     => '/dev/input/by-id/usb-Ultimarc_Button_Joystick_Trackball_Interface-event-kbd',
                              'delay_ms'  => 500,
                           });
POE::Kernel->run();
exit;
