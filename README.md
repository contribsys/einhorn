> <img src="https://stripe.dev/images/badges/archived.png" width="250">
>
> This project is deprecated and is no longer being actively maintained.

# Einhorn: the language-independent shared socket manager

![Einhorn](https://stripe.com/img/blog/posts/meet-einhorn/einhorn.png)

Let's say you have a server process which processes one request at a
time. Your site is becoming increasingly popular, and this one process
is no longer able to handle all of your inbound connections. However,
you notice that your box's load number is low.

So you start thinking about how to handle more requests. You could
rewrite your server to use threads, but threads are a pain to program
against (and maybe you're writing in Python or Ruby where you don't
have true threads anyway). You could rewrite your server to be
event-driven, but that'd require a ton of effort, and it wouldn't help
you go beyond one core. So instead, you decide to just run multiple
copies of your server process.

Enter Einhorn. Einhorn makes it easy to run (and keep alive) multiple
copies of a single long-lived process. If that process is a server
listening on some socket, Einhorn will open the socket in the master
process so that it's shared among the workers.

Einhorn is designed to be compatible with arbitrary languages and
frameworks, requiring minimal modification of your
application. Einhorn is simple to configure and run.

## Installation

Install from Rubygems as:

    $ gem install einhorn

Or build from source by:

    $ gem build einhorn.gemspec

And then install the built gem.

## Usage

Einhorn is the language-independent shared socket manager. Run
`einhorn -h` to see detailed usage. At a high level, usage looks like
the following:

    einhorn [options] program

Einhorn will open one or more shared sockets and run multiple copies
of your process. You can seamlessly reload your code, dynamically
reconfigure Einhorn, and more.

## Overview

To set Einhorn up as a master process running 3 copies of `sleep 5`:

    $ einhorn -n 3 sleep 5

You can communicate your running Einhorn process via `einhornsh`:

    $ einhornsh
    Welcome gdb! You are speaking to Einhorn Master Process 11902
    Enter 'help' if you're not sure what to do.

    Type "quit" or "exit" to quit at any time
    > help
    You are speaking to the Einhorn command socket. You can run the following commands:
    ...

### Server sockets

If your process is a server and listens on one or more sockets,
Einhorn can open these sockets and pass them to the workers. You can
specify the addresses to bind by passing one or more `-b ADDR`
arguments:

    einhorn -b 127.0.0.1:1234 my-command
    einhorn -b 127.0.0.1:1234,r -b 127.0.0.1:1235 my-command

Each address is specified as an ip/port pair, possibly accompanied by options:

    ADDR := (IP:PORT)[<,OPT>...]

In the worker process, the opened file descriptors will be represented
as file descriptor numbers in a series of environment variables named
EINHORN_FD_0, EINHORN_FD_1, etc. (respecting the order that the `-b`
options were provided in), with the total number of file descriptors
in the EINHORN_FD_COUNT environment variable:

    EINHORN_FD_0="6" # 127.0.0.1:1234
    EINHORN_FD_COUNT="1"

    EINHORN_FD_0="6" # 127.0.0.1:1234,r
    EINHORN_FD_1="7" # 127.0.0.1:1235
    EINHORN_FD_COUNT="2"

Valid opts are:

    r, so_reuseaddr: set SO_REUSEADDR on the server socket
    n, o_nonblock: set O_NONBLOCK on the server socket

You can for example run:

    $ einhorn -b 127.0.0.1:2345,r -m manual -n 4 -- example/time_server

Which will run 4 copies of

    EINHORN_FD_0=6 EINHORN_FD_COUNT=1 example/time_server

Where file descriptor 6 is a server socket bound to `127.0.0.1:2345`
and with `SO_REUSEADDR` set. It is then your application's job to
figure out how to `accept()` on this file descriptor.

### Command socket

Einhorn opens a UNIX socket to which you can send commands (run
`help` in `einhornsh` to see what admin commands you can
run). Einhorn relies on file permissions to ensure that no malicious
users can gain access. Run with a `-d DIRECTORY` to change the
directory where the socket will live.

Note that the command socket uses a line-oriented YAML protocol, and
you should ensure you trust clients to send arbitrary YAML messages
into your process.

### Seamless upgrades

You can cause your code to be seamlessly reloaded by upgrading the
worker code on disk and running

    $ einhornsh
    ...
    > upgrade

Once the new workers have been spawned, Einhorn will send each old
worker a SIGUSR2. SIGUSR2 should be interpreted as a request for a
graceful shutdown.

### ACKs

After Einhorn spawns a worker, it will only consider the worker up
once it has received an ACK. Currently two ACK mechanisms are
supported: manual and timer.

#### Manual ACK

A manual ACK (configured by providing a `-m manual`) requires your
application to send a command to the command socket once it's
ready. This is the safest ACK mechanism. If you're writing in Ruby,
just do

    require 'einhorn/worker'
    Einhorn::Worker.ack!

in your worker code. If you're writing in a different language, or
don't want to include Einhorn in your namespace, you can send the
string

    {"command":"worker:ack", "pid":PID}

to the UNIX socket pointed to by the environment variable
`EINHORN_SOCK_PATH`. (Be sure to include a trailing newline.)

To make things even easier, you can pass a `-g` to Einhorn, in which
case you just need to `write()` the above message to the open file
descriptor pointed to by `EINHORN_SOCK_FD`.

(See `lib/einhorn/worker.rb` for details of these and other socket
discovery mechanisms.)

#### Timer ACK [default]

By default, Einhorn will use a timer ACK of 1 second. That means that
if your process hasn't exited after 1 second, it is considered ACK'd
and healthy. You can modify this timeout to be more appropriate for
your application (and even set to 0 if desired). Just pass a `-m
FLOAT`.

### Preloading

If you're running a Ruby process, Einhorn can optionally preload its
code, so it only has to load the code once per upgrade rather than
once per worker process. This also saves on memory overhead, since all
of the code in these processes will be stored only once using your
operating system's copy-on-write features.

To use preloading, just give Einhorn a `-p PATH_TO_CODE`, and make
sure you've defined an `einhorn_main` method.

In order to maximize compatibility, we've worked to minimize Einhorn's
dependencies. It has no dependencies outside of the Ruby standard
library.

### Command name

You can set the name that Einhorn and your workers show in PS. Just
pass `-c <name>`.

### Re exec

You can use the `--reexec-as` option to replace the `einhorn` command with a command or script of your own. This might be useful for those with a Capistrano like deploy process that has changing symlinks. To ensure that you are following the symlinks you could use a bash script like this.

    #!/bin/bash

    cd <symlinked directory>
    exec /usr/local/bin/einhorn "$@"

Then you could set `--reexec-as=` to the name of your bash script and it will run in place of the plain einhorn command.

### Options

    -b, --bind ADDR                  Bind an address and add the corresponding FD via the environment
    -c, --command-name CMD_NAME      Set the command name in ps to this value
    -d, --socket-path PATH           Where to open the Einhorn command socket
    -e, --pidfile PIDFILE            Where to write out the Einhorn pidfile
    -f, --lockfile LOCKFILE          Where to store the Einhorn lockfile
    -g, --command-socket-as-fd       Leave the command socket open as a file descriptor, passed in the EINHORN_SOCK_FD environment variable. This allows your worker processes to ACK without needing to know where on the filesystem the command socket lives.
    -h, --help                       Display this message
    -k, --kill-children-on-exit      If Einhorn exits unexpectedly, gracefully kill all its children
    -l, --backlog N                  Connection backlog (assuming this is a server)
    -m, --ack-mode MODE              What kinds of ACK to expect from workers. Choices: FLOAT (number of seconds until assumed alive), manual (process will speak to command socket when ready). Default is MODE=1.
    -n, --number N                   Number of copies to spin up
    -p, --preload PATH               Load this code into memory, and fork but do not exec upon spawn. Must define an "einhorn_main" method
    -q, --quiet                      Make output quiet (can be reconfigured on the fly)
    -s, --seconds N                  Number of seconds to wait until respawning
    -v, --verbose                    Make output verbose (can be reconfigured on the fly)
        --drop-env-var VAR_NAME      Delete VAR_NAME from the environment that is restored on upgrade
        --reexec-as=CMDLINE          Substitute CMDLINE for \"einhorn\" when upgrading
        --nice MASTER[:WORKER=0][:RENICE_CMD=/usr/bin/renice]
                                     Unix nice level at which to run the einhorn processes. If not running as root, make sure to ulimit -e as appopriate.
        --with-state-fd STATE        [Internal option] With file descriptor containing state
        --upgrade-check              [Internal option] Check if Einhorn can exec itself and exit with status 0 before loading code
    -t, --signal-timeout=T           If children do not react to signals after T seconds, escalate to SIGKILL
        --version                    Show version


## Contributing

### Development Status

Einhorn is still in active operation at Stripe, but we are not maintaining
Einhorn actively. PRs are very welcome, and we will review and merge,
but we are unlikely to triage and fix reported issues without code.

Contributions are definitely welcome. To contribute, just follow the
usual workflow:

1. Fork Einhorn
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Added some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Github pull request

## History

Einhorn came about when Stripe was investigating seamless code
upgrading solutions for our API worker processes. We really liked the
process model of [Unicorn](http://unicorn.bogomips.org/), but didn't
want to use its HTTP functionality. So Einhorn was born, providing the
master process functionality of Unicorn (and similar preforking
servers) to a wider array of applications.

See https://stripe.com/blog/meet-einhorn for more background.

Stripe currently uses Einhorn in production for a number of
services. You can use Conrad Irwin's thin-attach_socket gem along with
EventMachine-LE to support file-descriptor passing. Check out
`example/thin_example` for an example of running Thin under Einhorn.

## Compatibility

Einhorn runs in Ruby 2.0, 2.1, and 2.2

The following libraries ease integration with Einhorn with languages other than
Ruby:

- **[go-einhorn](https://github.com/stripe/go-einhorn)**: Stripe's own library
  for *talking* to an einhorn master (doesn't wrap socket code).
- **[goji](https://github.com/zenazn/goji/)**: Go (golang) server framework. The
  [`bind`](https://godoc.org/github.com/zenazn/goji/bind) and
  [`graceful`](https://godoc.org/github.com/zenazn/goji/graceful)
  packages provide helpers and HTTP/TCP connection wrappers for Einhorn
  integration.
- **[github.com/CHH/einhorn](https://github.com/CHH/einhorn)**: PHP library
- **[thin-attach\_socket](https://github.com/ConradIrwin/thin-attach_socket)**:
  run `thin` behind Einhorn
- **[baseplate](https://reddit.github.io/baseplate/cli/serve.html)**: a
  collection of Python helpers and libraries, with support for running behind
  Einhorn

*NB: this list should not imply any official endorsement or vetting!*

## About

Einhorn is a project of [Stripe](https://stripe.com), led by [Carl Jackson](https://github.com/zenazn). Feel free to get in touch at
info@stripe.com.
