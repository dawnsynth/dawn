# dawn

dawn is a modular synthesizer written in [zig](https://ziglang.org).
interaction is possible through network messages, specifically [open sound control (osc)](https://en.wikipedia.org/wiki/Open_Sound_Control).
it's work in progress in early stages.
expect few features and rough edges: the interface is sketched out, but there are barely any modules.
contributions are welcome!

dusk is a basic command line application that sends messages to dawn and sometimes receives replies. 
it comes included and demonstrates the interface. 
using dawn with other software supporting osc is easy and recommended.


## building from source

with zig 0.11 stable [installed](https://ziglang.org/learn/getting-started/#installing-zig):
```shell
git clone https://github.com/dawnsynth/dawn.git
cd dawn
zig build
```

if all goes well, you should see `dawn` and `dusk` binaries in `./zig-out/bin/` that are used below.
consider adding this directory to your PATH for convenience.


## safety

please take care of your hearing and equipment.
there may be rapid changes it volume.
be advised to keep initital levels low and use speakers instead of headphones, if possible.
use at your own risk.


## getting started

dawn's default patch contains modules for sound i/o and processing osc messages. 
to launch it, run the binary:
```shell
dawn
```

see `dawn --help` for additional options.

dusk can send osc messages to dawn. with dawn running, for example:
```shell
dusk add_module --module_type sineosc --module_name sine
```

to hear a sound, we need to patch our oscillator to the soundio module:
```shell
dusk add_cable --src_module_name sine --src_port_name out --dst_module_name soundio --dst_port_name chan_1
```
this should produce a stereo signal, since channel 1 is normalled to channel 2.

to change its frequency:
```shell
dusk set_param --module_name sine --param_name freq --value 220.0
```

see `dusk --help` for all options and messages.


## other clients

for more flexible interaction its recommended to use dawn with other clients.
thanks to osc this can easily be done. 
some possibilities include [seamstress](https://github.com/ryleelyman/seamstress), [norns](https://monome.org/docs/norns/), [orca](https://github.com/hundredrabbits/Orca), and [open stage control](http://openstagecontrol.ammd.net) among [many others](https://github.com/topics/open-sound-control).


## acknowledgements

dawn's abstractions are inspired by the [initial version of vcv rack](https://github.com/VCVRack/Rack/tree/v0.5), developed by andrew belt.
dawn is written in [zig](https://ziglang.org/), who's creator andrew kelly, also wrote [libsoundio](https://github.com/andrewrk/libsoundio) which is used for the soundio module.
other third party libraries used include [tinyosc](https://github.com/mhroth/tinyosc) by martin roth, [zig-cli](https://github.com/sam701/zig-cli) by alexei samokvalov & contributors, [zig-network](https://github.com/MasterQ32/zig-network) by felix queißner, and [zig-soundio](https://github.com/veloscillator/zig-soundio) by ken kochis.
the interface pattern follows [a blog post by loris cro](https://zig.news/kristoff/easy-interfaces-with-zig-0100-2hc5).


## contributing

contributions are welcome and encouraged.
by submitting a pull request, you agree that your contribution will be under [this repository's license (MIT)](https://github.com/dawnsynth/dawn/blob/main/LICENSE).
