# Step 2: Clone and push over HTTP

## What we built

```sh
git clone http://localhost:9292/alice/hello.git     # anyone
git push  http://localhost:9292/alice/hello.git     # only alice, with her password
```

Users are created with `bin/adduser alice`, which stores a salted password
hash in `users.yml`. The new code is in `app.rb` under "Smart HTTP", and it is
mostly glue: Ruby checks who you are, then hands the request to
`git http-backend`, a program that ships with git and already knows the protocol.

## The conversation behind `git clone`

A clone over HTTP is two requests.

**1. "What do you have?"** The client fetches
`GET /alice/hello.git/info/refs?service=git-upload-pack`. Try it with curl:

```
001e# service=git-upload-pack
0000
010bf06bc494... HEAD\0multi_ack thin-pack side-band ofs-delta ... symref=HEAD:refs/heads/main
003df06bc494... refs/heads/main
0000
```

That's the **ref advertisement**: every branch and the commit it points at, plus a
list of features the server supports after the `\0`.

Each line starts with four hex digits. That's a **pkt-line**: the length of the
line, including those four digits, so `003d` means 61 bytes. `0000` is a "flush"
packet that marks the end of a section. This framing is the whole trick that lets
git send text and binary data down one pipe.

**2. "Here's what I want."** The client
`POST`s to `/alice/hello.git/git-upload-pack`:

```
want f06bc494... side-band-64k thin-pack ofs-delta ...
0000
done
```

A fresh clone has nothing, so it just says *want* and *done*. On a `git fetch` it
also sends *have* lines for commits it already has, and the server works out the
difference. The reply is a **packfile**: every object needed, compressed and
delta-encoded against each other, streamed back in one response.

A push is the mirror image. It starts with `info/refs?service=git-receive-pack`,
then `POST /git-receive-pack` sends "move `main` from commit A to commit B" plus a
packfile of the new objects. `git-receive-pack` on the server stores them and
updates the ref.

To watch this live on your own machine:

```sh
GIT_TRACE_PACKET=1 git clone http://localhost:9292/alice/hello.git
```

(Modern git defaults to protocol version 2, which reorganises these messages into
commands such as `ls-refs` and `fetch` but keeps the same pkt-line framing. Add
`-c protocol.version=0` to see the classic 2008-era version shown above.)

## Where Ruby stops and git starts

`git http-backend` is a **CGI** program. CGI is a 1990s convention for web
servers running external programs. The request details go in environment
variables (`REQUEST_METHOD`, `PATH_INFO`, `QUERY_STRING`), the request body goes
to stdin, and the program prints headers, a blank line and the body to stdout.
`git_http_backend` in `app.rb` does exactly that translation with `Open3`.

So the division of labour is:

| Ruby (our app)                            | git                                        |
|-------------------------------------------|--------------------------------------------|
| Routing `/<owner>/<name>.git/...`         | pkt-line parsing                           |
| Does this repo exist?                     | Ref advertisement and want/have negotiation |
| Who are you? May you push here?           | Building and receiving packfiles           |
| Turning CGI output into an HTTP response  | Updating refs safely                       |

The access rule is deliberately simple: anyone can read, and only the owner can
write. A `401` response with `WWW-Authenticate: Basic` is what makes your git
client prompt for a username and password.

## How it was done back then

GitHub actually launched in 2008 **without** smart HTTP, because it didn't exist
yet. Cloning went over `git://` (the `git daemon`, port 9418, read-only and with
no authentication) and pushing went over SSH. HTTP access used the "dumb"
protocol, which just served the files inside the bare repo one by one.

Smart HTTP landed in git 1.6.6 in late 2009, written largely by Shawn Pearce, and
GitHub adopted it in 2010. HTTPS then gradually became the recommended way to
clone, because it gets through corporate firewalls and needs no SSH key setup.
We skipped the dumb protocol and `git://` since smart HTTP is what survived, and
SSH, the original push path, is step 4.

At GitHub's scale the same request goes through more layers. A front-end proxy
works out which storage server holds `alice/hello`, and authentication and
permission checks are done by a separate service. The core is unchanged, though:
something checks who you are, then git's own pack programs talk pkt-lines with
your client.

## Known shortcuts

- The request and response are held in memory, not streamed. That's fine for
  learning, but a multi-gigabyte push would need streaming.
- Basic auth over plain `http://` sends the password in clear text. Real hosts
  use HTTPS, and you'd put this behind one too.
- Anyone can still create a repo under any owner name from the web form.
  Accounts and sessions on the web side are a later improvement.
