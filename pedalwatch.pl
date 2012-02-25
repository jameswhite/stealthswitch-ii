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

sub rhythmote_action{
    my $action = shift;
    my $poster = LWP::UserAgent->new;
    $poster->post($url,["action" => $action]);
}

# create one PedalWatcher instance for each input device you have a master pedal on
my $pw  = PedalWatcher->new({ 
                              'debug'   => 0,
                              'input'   => $device_id,
                              'pedals'  => {   
                                             'b' => [ 
                                                      sub {
                                                            print "b: one click\n";
                                                            rhythmote_action("next");
                                                          },
                                                      sub {
                                                            print "b: two clicks\n";
                                                          },
                                                      sub {
                                                            print "b: three clicks\n";
                                                          },
                                                      # ... as many clicks as you want ...
                                                    ],
                                             'c' => [ 
                                                      sub {
                                                            print "c: one click\n";
                                                            rhythmote_action("prev");
                                                          },
                                                      sub {
                                                            print "c: two clicks\n";
                                                          },
                                                      sub {
                                                            print "c: three clicks\n";
                                                          },
                                                      # ... as many clicks as you want ...
                                                    ],
                                             'd' => [ 
                                                      sub {
                                                            print "d: one click\n";
                                                            rhythmote_action("play");
                                                          },
                                                      sub {
                                                            print "d: two clicks\n";
                                                          },
                                                      sub {
                                                            print "d: three clicks\n";
                                                          },
                                                      # ... as many clicks as you want ...
                                                    ],
                                           # ... as many pedals as you have ...
                                           },
                           });
POE::Kernel->run();
exit;
