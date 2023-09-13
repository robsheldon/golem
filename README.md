<table border="0">
  <tr>
   <td border="0" width="650">
    <p><img src="https://github.com/robsheldon/golem/raw/assets/golem_github.png"></p>
    <p align="right"><sup>Graphics by Gabriel Kolbe. Visit Gabriel's <a href="https://www.deviantart.com/gabkt">DeviantArt</a>.</sup></p>
   </td>
   <td>
    <p><i>The existence of a golem is sometimes a mixed blessing. Golems are not intelligent, and if commanded to perform a task, they will perform the instructions literally.</i></p>
    <p align="right"><sup><a href="https://en.wikipedia.org/wiki/Golem">Wikipedia</a></sup></p>
   </td>
  </tr>
</table>

# Golem: Literate Dev-Ops With Bash and Markdown

**Golem** is:

* an advanced footgun that allows you to make spectacular mistakes on multiple servers with a single command;

* a convenient helper for managing and executing shell scripts locally and on remote servers;

* an agent-less tool for literate devops, designed to work well with [mdsh](https://github.com/bashup/mdsh), so you can write executable documentation for your infrastructure.

Golem is not intended to replace bigger, popular infrastructure management systems like Ansible, but it could be a useful tool for people who like documentation and shell scripts and only have a handful of servers to look after.


# An example
```bash
$ cat <<'EOF' | tee ~/golem_example.sh >/dev/null
#!/bin/bash

current_time=$(date)
current_ip=$(curl -s ifconfig.me)
current_load=$(uptime)
current_name=$(hostname -f)
mailto=$(needopt mailto -p "Email to:")
cat <<ENDMAIL | mail -s "Status from $current_name" "$mailto"
Time Now: $current_time
Address:  $current_ip
Load:     $current_load

Have a great day!
ENDMAIL
EOF
$ golem import script ~/golem_example.sh as "status update"

Successfully imported "status update" as "status_update.sh"

$ golem status update @yourserver @yourotherserver --mailto "you@example.com"
```

This creates a simple demonstration script, imports it into golem's command library, and then runs the script on the remote servers "yourserver" and "yourotherserver", both of which should be defined in your ~/.ssh/config file. The `--mailto` option passes a "mailto" value to the script on each remote server, allowing the server to send the results to the address you provided (if you have `mail` installed on that server).

If you have [mdsh](https://github.com/bashup/mdsh) installed, you can do this with markdown documents too.


# Table of Contents

* [Integrations](#integrations)
  * [Shellcheck](#shellcheck)
  * [MDSH](#mdsh)
  * [Phabricator](#phabricator)
* [Using Golem](#using-golem)
  * [Importing a script](#importing-a-script)
    * [Working with MDSH](#working-with-mdsh)
    * [Troubleshooting a failed import](#troubleshooting-a-failed-import)
  * [Executing a script](#executing-a-script)
    * [Servers in your ssh config](#servers-in-your-ssh-config)
    * [Passing parameters on the commandline](#passing-parameters-on-the-commandline)
  * [Writing a script](#writing-a-script)
    * [Golem's helper functions](#golems-helper-functions)
* [Why I built Golem](#why-i-built-golem)
* [Status](#status)
  * [Gotchas](#gotchas)
* [Contributing](#contributing)


# Integrations

## Shellcheck

Golem looks for [shellcheck](https://github.com/koalaman/shellcheck) in your `$PATH` when importing shell scripts. shellcheck is *strongly* recommended, and shellcheck is *required* when importing Markdown documents (see "MDSH" below), because of the potential for catastrophic mistakes.

If you haven't used shellcheck much before, your first few runs with it may be frustrating. Your shell scripts may have picked up some bad habits and sometimes shellcheck seems a bit nitpicky (like insisting that `$(...)` be used instead of `\`\``, or `command -v ...` instead of `which ...`). But, it will also catch more serious mistakes you didn't realize you were making. It doesn't take very long to learn how to write shellcheck-approved scripts.

See below, [Importing a script](#importing-a-script), for more details on how shellcheck works during the script import process.

## MDSH

Golem was built to extend [mdsh](https://github.com/bashup/mdsh) into a complete system for executable documents. If you have markdown documents with embedded shell code, and mdsh is in your `$PATH`, you can import those documents directly into Golem. Just add `.mdsh` to the filename. During the import process, Golem will look for mdsh and use it to compile the markdown document into an executable shell script. See below, [Importing a script](#importing-a-script), or [mdsh](https://github.com/bashup/mdsh), for more information.

## Phabricator

If you're storing documentation in Phabricator, you might find one of my other little projects, [grease](https://github.com/robsheldon/grease), helpful. It can mass-extract documents from Phriction.


# Using Golem

Golem keeps your scripts in a library, in `/path/to/golem/scripts/`. Scripts should be imported into this folder using a special `golem import script` function. When files are imported, they are not changed. During the import process, a matching shell script is generated and stored in the `/path/to/golem/.cache/`.

When Golem is invoked, it resolves the "command" to the closest matching file name in the `.cache` directory. If it finds a match there, it checks to make sure that the original file is still present in `scripts/` and hasn't changed. If it can't find a match in `.cache`, it will look in `scripts/`, and if it finds a match there, it will try to automatically import the file.

This is designed so that you can keep an original copy of your shell scripts or markdown documents, and Golem can have a ready-to-use shell script, without having to re-generate the shell script every time it's invoked.

## Importing a script

To import a new shell script into your Golem:
```bash
$ golem import script '/path/to/your/script.sh' as "command to use"
```

For example,
```bash
$ golem import script ~/hello_world.sh as "hello world"

Successfully imported "hello world" as "hello_world.sh"

$ golem hello world

Hello, world.
```

If [shellcheck](https://github.com/koalaman/shellcheck) is installed on your system (and can be found in your `$PATH`), then the import process will shellcheck your script, generate a new shell script in Golem's `.cache` directory with some helper functions added to it, and then shellcheck the result again. shellcheck can't verify that your script is *correct*, but it can at least catch some common errors before you try running it on remote servers. The second pass with shellcheck helps to ensure that there are no conflicts with the helper functions that are added to command scripts (see [Golem's Helper Functions, below](#golems-helper-functions)).

The import is handled by `scripts/import_script.sh` in Golem's directory. This script is handled differently from normal Golem command scripts, so it is not a good example of how to write a Golem command script, but it may help you understand the import process if you enjoy reading shell code.

### Working with mdsh

If [mdsh](https://github.com/bashup/mdsh) is installed on your system (and can be found in your `$PATH`), then any markdown document ending in ".mdsh" will be compiled by mdsh during import. Golem injects a function into the mdsh compilation process so that `\`\`\`` fenced-blocks labeled "bash" are treated the same way as blocks labeled "shell" (the mdsh default).

### Troubleshooting a failed import

An import may fail during one of the shellcheck passes. Although it's possible to just drop a new file into the `scripts/` directory, and Golem will auto-import it if you invoke it, it's better to do the import explicitly so that import errors can be handled gracefully.

If the import does fail, you'll see something like this:
```bash
$ golem import script ~/hello_world.sh as "hello world"

ERROR: The command script in /path/to/golem/scripts/hello_world.sh
isn't passing shellcheck. Please run "shellcheck
/path/to/golem/scripts/hello_world.sh", fix it, and then try again.
```


## Executing a script

Once a script or markdown document is successfully imported, you can run it on remote servers. Golem provides some helpful features to make this process easier. Here are some examples:

**Simple, runs on the local system**
```bash
$ golem hello world
```

**Simple, runs on the remote servers "server1" and "server2"**
```bash
$ golem @server1 @server2 hello world
```

**Passing parameters to a script on a remote server**
```bash
$ golem @server1 hello world --greeting "hello, world"
```

### Servers in your ssh config

In the examples above, remote servers are identified by `@` followed by a host identifier. These host identifiers should match `Host` identifiers in your `~/.ssh/config` file. You can specify a fully qualified hostname and it will work, but Golem currently doesn't understand ssh URIs, so you can't use a different username or port.

It's also a good idea to use public/private key authentication. If the remote host asks for a password, it sometimes makes a mess of the inbound command script, because the remote server begins reading from the pipe when it's expecting your password. You really shouldn't be using password authentication on your remotes anyway.

Golem attempts to resolve a host identifier to a valid IP address before connecting and will complain if it can't figure it out. It will parse your ssh config file and do a simple network trick to do this.

Servers are accessed sequentially, not in parallel. A command script must finish execution on one server before it can be run on the next. This is a really severe limiting factor if you have a large fleet of servers to manage, but if that's your situation, you're probably using more advanced devops tooling anyway. Golems are peasant magic. :-)

### Passing parameters on the commandline

One of the examples above includes `--greeting "hello, world"`. Command scripts can use a Golem helper function called `needopt` to look for named longopts in the script invocation. That value is then loaded into a variable of the command script's choosing. This makes it convenient to handle complicated systems administration tasks by passing parameters like usernames and hostnames to command scripts as they're run on remote servers.


## Writing a script

If you can write an ordinary shell script and get it to pass shellcheck, then you should be able to import it directly into Golem and run it. I have tried very hard to avoid requiring any special behavior from command scripts. If you have an extensive shell script or markdown library already, most of it should be import-able with minimal modifications. If you've never used [shellcheck](https://github.com/koalaman/shellcheck) before, then you'll want to set aside some time to patiently adjust your scripts until it's happy with them.

If your script expects parameters to be passed on the commandline, they will still be available when Golem executes it. You'll just have to strip out the first couple of words that are used to invoke your script.

### Golem's Helper Functions

When it generates a command script from some source file -- whether a shell script or a markdown document -- Golem injects a block of code into the top of the script that provides some additional safety features and helper functions.

* Header comment: a comment block is added that tells the reader that they're looking at a generated file, and where they can find the original file.
* `script*` variables: `scriptname`, `scriptpath`, `scriptdir`, and `scriptshell` are initialized.
* `set -u`, `pipefail`: these options are set for additional safety. `set -e` is not set here because there are some commands that need to be able to fail without killing the whole script (grep, for example).
* `trap ... TERM`: the `TERM` signal is caught and used to invoke a simple `exit 1` command. This is used by another helper function, `fail()`, to try and terminate the current script in the event of an error.
* `path_*` functions: `path_filename`, `path_directory`, `path_basename`, and `path_extension` provide canonical, battle-tested approaches to working with paths.
* `random_string`: get an imperfect, but usable-in-a-pinch randomly-generated sequence that's appropriate for temporary passwords, keys, and some other secrets. This function strips out some characters that can cause confusion in some environments (like `lI1`).
* `warn`: write a message to STDERR.
* `fail`: write a message to STDERR and try to halt the script. Halting scripts from nested subshells is very hard in bash. Golem makes a good effort here but the fact is that it's not as bulletproof as I'd like it to be. Try to avoid calling `fail` from subshells.
* `ask`: this is a really, really nice function that allows your script to prompt the user for yes/no responses or more complicated requests. It includes support for default values, automatic timeouts, and required values, and is very easy to use.
* `loadopt`: allows command scripts to retrieve the value of a named longopt provided by the user. `loadopt` returns a non-zero exit status code if the user didn't provide the named longopt. For example, `if username="$(loadopt "username")"; then echo "$username"; elso echo "No username"; fi` will display the value following "--username" on the commandline if it exists, or "No username" if it doesn't.
* `needopt`: similar to `loadopt`, but treats the named longopt as a required value and displays a prompt if the value wasn't provided. `needopt` also allows command scripts to require a value to match a regular expression.
* some argument processing: a block near the bottom extracts any named longopt values from the argument list and stores them for use by the `needopt()` function.

You can find all of this code between the `# begin-golem-injected-code` and `# end-golem-injected-code` lines in the main Golem shell script. When building a command script, Golem reads its own file and copy-pastes this section into the top of the command script.

There is one more block of code that may be injected into some command scripts. Golem attempts to determine if a particular script will use `sudo` or not. If it does, golem adds an extra block of code below all of the other injected code. This block checks to see if the current user has `sudo` access and *also* "warms up" sudo with a simple command. This helps prevent script execution from getting mangled by `sudo` waiting on a password prompt.


# Why I Built Golem

## To Scratch an Itch

I've been managing servers long before tools like Ansible were developed, and I accumulated large amounts of step-by-step documentation with lots of historical notes. They were all gradually translated to markdown, and I thought it would be fun if I had a way to just "run" these notes on remote servers.

## Literate Programming

Knuth [described literate programming back in 1992](https://www-cs-faculty.stanford.edu/~knuth/lp.html). The various how-to guides you could find on sites like [Linode](https://www.linode.com/docs/guides/) and [DigitalOcean](https://www.digitalocean.com/community/tutorials), along with systems like Jupyter Notebooks, are the closest things we have today to mainstream literate programming. The ability to easily embed code in markdown documents gets us even closer to fully executable documents. Linode, DigitalOcean, and any other site that offers how-to guides for systems administration could make their guides downloadable in a markdown format, and Golem or something like it could run them directly.

## As An Exercise

I discovered [mdsh](https://github.com/bashup/mdsh), which gracefully handled all the hard work of constructing a shell script from a markdown document. I just needed a way to manage the documents and scripts, and then execute them remotely, along with a few other nice-to-haves. I iteratively built Golem to do just that. It gave me an excuse to become very familiar with shellcheck and to clean up all of my documentation until I could run any of it on a remote system with a single command.

## To refine my shell code

I *like* shell scripts. I've been writing them since 2005 at leaat -- back when `/etc/init.d` ruled everything. And, I *like* documentation -- good documentation, anyway. `shellcheck` encouraged me to spend more time thinking about *idiomatic* shell programming: ensuring the details were all correct and consistent across the years of documentation and bits of shell code I had accumulated.

# Status

All of the features I had planned for Golem have been completed. I have been using it in production for a little while. Golem is currently written specifically for bash; I hope to gradually make it more compatible with other shells.

## Gotchas

The `fail` function doesn't work as reliably as I'd like. It's very hard to reliably kill a parent process from inside a subshell. I've tried several different approaches and the one currently in golem is the best I've found. I'm all out of new ideas to try.


# Contributing

Please feel free to open an issue if you have a question or your Golem murders a server. I'm also happy to accept pull requests that can make Golem an even better, less deadly tool for literate systems administration.