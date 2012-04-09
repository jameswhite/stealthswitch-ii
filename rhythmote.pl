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
    my $result = $poster->post($url,["action" => $action]);
    print $result->content."\n";
}

# create one PedalWatcher instance for each input device you have a master pedal on
my $pw  = PedalWatcher->new({ 
                              'debug'   => 0,
                              'input'   => $device_id,
                              'pedals'  => {   
                                             'a' => [ 
                                                      sub {
                                                            print "next\n";
                                                            rhythmote_action("next");
                                                          },
                                                      sub {
                                                            print "prev\n";
                                                            rhythmote_action("prev");
                                                          },
                                                      sub {
                                                            print "play\n";
                                                            rhythmote_action("play");
                                                          },
                                                    ],
                                             'd' => [ 
                                                      sub {
                                                            print "resynergy\n";
                                                            system("$ENV{'HOME'}/bin/resynergy");
                                                          },
                                                      sub {
                                                            print "d: two clicks\n";
                                                          },
                                                      sub {
                                                            print "d: three clicks\n";
                                                          },
                                                    ],
                                           # ... as many pedals as you have ...
                                           },
                           });
POE::Kernel->run();
exit;
