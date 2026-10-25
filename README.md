# early-github

A small, readable re-creation of what a git hosting site looked like under the
hood in its earliest days, before it had to scale. It is a learning project,
not a product: every piece is kept as close to "just call git" as possible so
the moving parts stay visible.

## The plan

1. **Repo storage** (done). A web app that creates bare repos on disk and lists them.
2. **Clone and push over HTTP** (done). Put git's own `http-backend` behind basic auth.
3. **Repo pages.** Browse files and commits using git plumbing (`ls-tree`, `cat-file`, `log`).
4. **Clone and push over SSH.** `authorized_keys` with a forced command that checks access.

Each step has a short write-up in [`docs/`](docs) on how this was done back then.

## Running it

Needs Ruby 3.x and git.

```sh
bundle install
bundle exec rackup -p 9292
```

Then open http://localhost:9292 and create a repository. It appears on disk under
`repos/<owner>/<name>.git`. Set `REPO_ROOT` to store repositories somewhere else.

To push, create a user whose name matches the repo's owner:

```sh
bin/adduser alice
git clone http://localhost:9292/alice/hello.git   # anyone can clone
git push                                          # asks for alice's password
```

## Layout

```
app.rb        the web app (Sinatra), including the smart HTTP glue
lib/users.rb  user accounts with salted password hashes (users.yml)
bin/adduser   create a user who can push
config.ru     Rack entry point
views/        ERB templates
docs/         one note per step on how it worked historically
repos/        hosted repositories, created at runtime (git-ignored)
```
