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
use LWP;

my $device_id = '/dev/input/by-id/usb-Ultimarc_Button_Joystick_Trackball_Interface-event-kbd';
my $url = "http://eir:8000";

my $pw  = PedalWatcher->new({ 
                              'input'   => $device_id,
                              'pedals'  => {   
                                             'a' => [ 
                                                      sub {
                                                            print "one clicks\n";
                                                            my $poster = LWP::UserAgent->new;
                                                            $poster->post($url,["action" => "next"]);
                                                          },
                                                      sub {
                                                            print "two clicks\n";
                                                            my $poster = LWP::UserAgent->new;
                                                            $poster->post($url,["action" => "prev"]);
                                                          },
                                                      sub {
                                                            print "three clicks\n";
                                                            my $poster = LWP::UserAgent->new;
                                                            $poster->post($url,["action" => "play"]);
                                                          },
                                                      # ... as many clicks as you want
                                                    ],
                                           },
                           });
POE::Kernel->run();
exit;
