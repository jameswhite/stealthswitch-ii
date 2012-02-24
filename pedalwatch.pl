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
package PedalWatcher;

use POE::Wheel::Run;
use LWP;
use Time::HiRes;

sub new {
    my $class = shift;
    my $self = {};
    my $cnstr = shift if @_;
    bless($self,$class);
    foreach my $argument ("input","delay_ms"){
        $self->{$argument} = $cnstr->{$argument} if($cnstr->{$argument});
    }
    POE::Session->create(
                          object_states => [
                                             $self => [
                                                        'button_1_down',
                                                        'button_1_up',
                                                        'repeat',
                                                        'rhythmote_action',
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

    # dump the events to stdout
    if(defined($heap->{'seq_start'})){ 
        #my $now = [ Time::HiRes::gettimeofday( ) ];
        #print "start: ".join(" ",@{ $heap->{'seq_start'} })."\n";
        #print join(",",@{ $heap->{'events'} })."\n";
        #print " stop: ".join(" ",@{ $now })."\n";
        my $counter = 0;
        while(my $inspector = shift(@{ $heap->{'events'} })){
           $counter++ if($inspector eq "UP"); 
        }
        if($counter == 1){
            print "next\n";
            $kernel->yield('rhythmote_action', 'next');
        }elsif($counter == 2){
            print "prev\n";
            $kernel->yield('rhythmote_action', 'prev');
        }elsif($counter == 3){
            print "play\n";
            $kernel->yield('rhythmote_action', 'play');
        }else{
            print "$counter\n";
        }
    }

    # clear the events an the timer
    $heap->{'events'} = [];
    $heap->{'seq_start'} = undef;
}

sub button_1_down {
    my ($self, $kernel, $heap, $sender, $what) = @_[OBJECT, KERNEL, HEAP, SENDER, ARG0 .. $#_];

    # Start watching the clock as soon as the first pedal goes down
    unless(defined($heap->{'seq_start'})){ 
        $heap->{'seq_start'} = [ Time::HiRes::gettimeofday( ) ];
    }

    # but always track the event
    push(@{ $heap->{'events'} }, "DOWN");
}

sub button_1_up {
    my ($self, $kernel, $heap, $sender, $what) = @_[OBJECT, KERNEL, HEAP, SENDER, ARG0 .. $#_];

    # events will occur 1 second after the last pedal is released
    $kernel->delay('do_event',1);

    # but always track the event
    push(@{ $heap->{'events'} }, "UP");
}

sub repeat {
    my ($self, $kernel, $heap, $sender, $what) = @_[OBJECT, KERNEL, HEAP, SENDER, ARG0 .. $#_];
    push(@{ $heap->{'events'} }, "REPEAT");
}

sub rhythmote_action{
    my ($self, $kernel, $heap, $sender, $action) = @_[OBJECT, KERNEL, HEAP, SENDER, ARG0 .. $#_];
    my $browser = LWP::UserAgent->new;
    my $url = 'http://eir.eftdomain.net:8000';
    my $response = $browser->post( $url, [ 'action' => $action ]);
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

sub on_child_stdout {
    my ($self, $kernel, $heap, $sender, $stdout_line, $wheel_id) = @_[OBJECT, KERNEL, HEAP, SENDER, ARG0 .. $#_];
    my $child = $_[HEAP]{children_by_wid}{$wheel_id};
    if($stdout_line eq "Type[1] Value[1] Code[30]"){
        $kernel->yield('button_1_down');
    }elsif($stdout_line eq "Type[1] Value[0] Code[30]"){
        $kernel->yield('button_1_up');
    }elsif($stdout_line eq "Type[0] Value[1] Code[0]"){
        $kernel->yield('repeat');
    }else{
        print "pid ", $child->PID, " STDOUT: $stdout_line\n";
    }
    my $device =  $_[HEAP]{device}{$wheel_id};
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

$|=1;
my $pw  = PedalWatcher->new({ 
                              'input'     => '/dev/input/by-id/usb-Ultimarc_Button_Joystick_Trackball_Interface-event-kbd',
                              'delay_ms'  => 500,
                           });
POE::Kernel->run();
exit;
