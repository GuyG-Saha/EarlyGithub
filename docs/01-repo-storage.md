# Step 1: Repositories are just directories

## What we built

`POST /repos` validates an owner and a name, then runs:

```sh
git init --bare repos/<owner>/<name>.git
```

That is the entire "create repository" feature. The home page lists repositories
by globbing `repos/*/*.git`. There is no database yet; the filesystem is the
source of truth.

## Why a *bare* repo?

A normal repo has a working tree (your checked-out files) plus a hidden `.git`
directory. A server never edits files by hand, so it only needs the `.git` part.
`git init --bare` creates exactly that: `HEAD`, `config`, `objects/`, `refs/` and
friends, sitting directly in `<name>.git/`. Pushes write new objects and move refs
in here; clones read them out.

Have a look after creating one:

```sh
ls repos/alice/hello.git
cat repos/alice/hello.git/HEAD     # ref: refs/heads/main
```

## How it was done back then

Early GitHub (2008) was a Rails app, but the repositories themselves were plain
bare repos on a file server, sharded into directories by user. The Rails app
talked to them through **Grit**, a Ruby library written by Tom Preston-Werner
that mostly shelled out to the `git` binary and parsed its output, with some
pure-Ruby object reading for speed. We do the same thing, minus the library:
`Open3.capture3("git", ...)`.

Because the repos were just files, the hard problems came later and were mostly
about scale: one file server filling up, then many file servers, then a routing
layer to find which server holds a given repo, and eventually replicated storage.
None of that changes the core idea you see here.

## Note on names

Owner and repo names become directory names, so `app.rb` only accepts letters,
digits, `-`, `_` and `.`, which also blocks paths like `../../etc`. Real hosts
enforce similar rules for the same reason.
