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
use POE;
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
package PedalWatcher;

use POE;
use Time::HiRes;

sub new {
    my $class = shift;
    my $self = {};
    my $cnstr = shift if @_;
    bless($self,$class);
    foreach my $argument ("input","pedals","debug"){
        $self->{$argument} = $cnstr->{$argument} if($cnstr->{$argument});
    }
    POE::Session->create(
                          object_states => [
                                             $self => [
                                                        'pedal_down',
                                                        'pedal_up',
                                                        'repeat',
                                                        '_start',
                                                        'do_event',
                                                        'spawn',
                                                        'on_child_stdout',
                                                        'on_child_stderr',
                                                        'on_child_close',
                                                        'on_child_signal',
                                                      ],
                                           ],
                          #options       => { trace => 1 },
    );
    return $self;
}

sub _start {
    my ($self, $kernel, $heap, $sender, @args) = @_[OBJECT, KERNEL, HEAP, SENDER, ARG0 .. $#_];
    if(defined($self->{'input'})){
        $kernel->yield('spawn', ["./pedal_watcher",$self->{'input'}],'say');
    }
    return;
}

sub do_event {
    my ($self, $kernel, $heap, $sender, $what) = @_[OBJECT, KERNEL, HEAP, SENDER, ARG0 .. $#_];

    # run the passed in code ref based on how many "UP"s we see
    if(defined($heap->{'seq_start'})){ 
        foreach my $key (keys(%{ $heap->{'events'} })){
            my $counter = 0;
            next if($#{ $heap->{'events'}->{$key} } < 0);
            while(my $inspector = shift(@{ $heap->{'events'}->{$key} })){
               $counter++ if($inspector eq 'UP'); 
            }
            if(defined($self->{'pedals'}->{$key}->[$counter - 1])){
                &{ $self->{'pedals'}->{$key}->[$counter - 1 ] };
            }else{
                print STDERR "no subroutine for [$counter] clicks on pedal [$key] provided.\n";
            }
        }
        # clear the events an the timer
        $heap->{'events'}->{$key} = [];
    }
    $heap->{'seq_start'} = undef;
}

sub pedal_down {
    my ($self, $kernel, $heap, $sender, $pedal) = @_[OBJECT, KERNEL, HEAP, SENDER, ARG0 .. $#_];

    # Start watching the clock as soon as the first pedal goes down
    unless(defined($heap->{'seq_start'})){ 
        $heap->{'seq_start'} = [ Time::HiRes::gettimeofday( ) ];
    }

    # but always track the event
    push(@{ $heap->{'events'}->{$pedal} }, "DOWN");
}

sub pedal_up {
    my ($self, $kernel, $heap, $sender, $pedal) = @_[OBJECT, KERNEL, HEAP, SENDER, ARG0 .. $#_];

    # events will occur 1 second after the last pedal is released
    $kernel->delay('do_event',1);

    # but always track the event
    push(@{ $heap->{'events'}->{$pedal} }, "UP");
}

sub repeat {
    my ($self, $kernel, $heap, $sender, $what) = @_[OBJECT, KERNEL, HEAP, SENDER, ARG0 .. $#_];
    # not doing anything with this, but I've got ideas about long presses
}

sub spawn{
    my ($self, $kernel, $heap, $sender, $program, $reply_event) = @_[OBJECT, KERNEL, HEAP, SENDER, ARG0 .. $#_];
    my $child = POE::Wheel::Run->new(
                                      Program      => $program,
                                      StdoutEvent  => "on_child_stdout",
                                      StderrEvent  => "on_child_stderr",
                                      CloseEvent   => "on_child_close",
                                    );

    $_[KERNEL]->sig_child($child->PID, "on_child_signal");

    # Wheel events include the wheel's ID.
    $_[HEAP]{children_by_wid}{$child->ID} = $child;

    # Signal events include the process ID.
    $_[HEAP]{children_by_pid}{$child->PID} = $child;

    # Save who will get the reply
    $_[HEAP]{device}{$child->ID} = $program->[1];

    print("Child pid ", $child->PID, " started as wheel ", $child->ID, ".\n");
}


# a Type[1] Value[1] Code[30]
# b Type[1] Value[1] Code[48]
# c Type[1] Value[1] Code[46]
# d Type[1] Value[1] Code[32]
# e Type[1] Value[1] Code[18]

sub on_child_stdout {
    my ($self, $kernel, $heap, $sender, $stdout_line, $wheel_id) = @_[OBJECT, KERNEL, HEAP, SENDER, ARG0 .. $#_];
    my $child = $_[HEAP]{children_by_wid}{$wheel_id};
    my ($pedal,$direction) = ('','');
    print STDERR "$stdout_line\n" if($self->{'debug'});

    if($stdout_line eq "Type[0] Value[0] Code[0]"){
        # set all currently DOWN keys to UP
        foreach my $key (keys(%{ $heap->{'events'} })){
            if($heap->{'events'}->{$key}->[ $#{ $heap->{'events'}->{$key} } ] eq 'DOWN'){
                $kernel->yield('pedal_up',$key);
            }
        }
        # we may need to kill and restart the C program here... # FIXME
        return;
    }
    if($stdout_line eq "Type[0] Value[1] Code[0]"){
        $kernel->yield('repeat');
        return;
    }

    if($stdout_line     =~m/Code\[30\]/){
        $pedal = 'a';
    }elsif($stdout_line =~m/Code\[48\]/){
        $pedal = 'b';
    }elsif($stdout_line =~m/Code\[46\]/){
        $pedal = 'c';
    }elsif($stdout_line =~m/Code\[32\]/){
        $pedal = 'd';
    }elsif($stdout_line =~m/Code\[18\]/){
        $pedal = 'e';
    }else{
        # someone with more pedals than me send me a pull request...
        $pedal = '?';
    }

    if($stdout_line =~m/Value\[0\]/){
        $direction='up';
        $kernel->yield('pedal_up',$pedal);
    }elsif($stdout_line =~m/Value\[1\]/){
        $direction='down';
        $kernel->yield('pedal_down',$pedal);
    }else{
        $direction='unknown';
    }
    print STDERR "$pedal:$direction\n" if($self->{'debug'});
}

# Wheel event, including the wheel's ID.
sub on_child_stderr {
    my ($self, $kernel, $heap, $sender, $stderr_line, $wheel_id) = @_[OBJECT, KERNEL, HEAP, SENDER, ARG0 .. $#_];
    my $child = $_[HEAP]{children_by_wid}{$wheel_id};
    print "pid ", $child->PID, " STDERR: $stderr_line\n";
}

# Wheel event, including the wheel's ID.
sub on_child_close {
    my ($self, $kernel, $heap, $sender, $wheel_id) = @_[OBJECT, KERNEL, HEAP, SENDER, ARG0 .. $#_];
    my $child = delete $_[HEAP]{children_by_wid}{$wheel_id};
    delete $_[HEAP]{device}{$wheel_id};

    # May have been reaped by on_child_signal().
    unless (defined $child) {
      print "wid $wheel_id closed all pipes.\n";
      return;
    }

    print "pid ", $child->PID, " closed all pipes.\n";
    delete $_[HEAP]{children_by_pid}{$child->PID};
}

sub on_child_signal {
    my ($self, $kernel, $heap, $sender, $wheel_id) = @_[OBJECT, KERNEL, HEAP, SENDER, ARG0 .. $#_];
    print "pid $_[ARG1] exited with status $_[ARG2].\n";
    my $child = delete $_[HEAP]{children_by_pid}{$_[ARG1]};

    # May have been reaped by on_child_close().
    return unless defined $child;

    delete $_[HEAP]{children_by_wid}{$child->ID};
    delete $_[HEAP]{device}{$wheel_id};
}

1;
