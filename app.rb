require "sinatra/base"
require "fileutils"
require "open3"
require_relative "lib/users"

# A tiny, early-GitHub-shaped app. Repositories are plain bare git repos on
# disk, laid out as repos/<owner>/<name>.git. There is no database: the
# filesystem *is* the source of truth, which is roughly how things started.
class EarlyGitHub < Sinatra::Base
  REPO_ROOT = File.expand_path(ENV.fetch("REPO_ROOT", "repos"), __dir__)

  # Owner and repo names become directory names, so keep them boring.
  # This also blocks path tricks like "../../etc".
  NAME = /\A[A-Za-z0-9][A-Za-z0-9_.-]{0,38}\z/

  # The two programs that speak git's wire protocol, one per direction:
  # upload-pack sends objects to a client (clone, fetch, pull),
  # receive-pack accepts objects from a client (push).
  SERVICES = %w[git-upload-pack git-receive-pack].freeze

  set :views, File.join(__dir__, "views")

  helpers do
    def h(text) = Rack::Utils.escape_html(text.to_s)

    def valid_name?(name) = NAME.match?(name.to_s) && !name.end_with?(".git")

    def repo_path(owner, name) = File.join(REPO_ROOT, owner, "#{name}.git")

    def clone_url(owner, name) = "#{request.base_url}/#{owner}/#{name}.git"

    # Every repo on disk, as [owner, name] pairs.
    def all_repos
      Dir.glob(File.join(REPO_ROOT, "*", "*.git")).sort.map do |path|
        [File.basename(File.dirname(path)), File.basename(path, ".git")]
      end
    end

    # Anyone may clone. Only the repo's owner may push, and must prove it with
    # HTTP Basic auth. A 401 is what makes git ask for a username and password.
    def require_owner!(owner)
      auth = Rack::Auth::Basic::Request.new(request.env)
      user, password = auth.provided? && auth.basic? ? auth.credentials : nil
      return user if user == owner && Users.authenticate(user, password)

      headers "WWW-Authenticate" => 'Basic realm="early-github"'
      halt 401, "Authentication required\n"
    end

    # Hand the request to `git http-backend`, the CGI program that ships with
    # git and implements the "smart HTTP" protocol. CGI is an old, simple
    # contract: request details go in environment variables, the request body
    # goes to stdin, and the program prints HTTP headers, a blank line, then
    # the body on stdout. We translate Rack -> CGI and back, nothing more.
    def git_http_backend(owner, name, rest, user: nil)
      cgi_env = {
        "GIT_PROJECT_ROOT"    => REPO_ROOT,
        "GIT_HTTP_EXPORT_ALL" => "1", # serve every repo; we do our own access checks
        "PATH_INFO"           => "/#{owner}/#{name}.git/#{rest}",
        "REQUEST_METHOD"      => request.request_method,
        "QUERY_STRING"        => request.query_string,
        "CONTENT_TYPE"        => request.content_type.to_s,
        "REMOTE_USER"         => user.to_s, # http-backend refuses pushes without one
        "REMOTE_ADDR"         => request.ip.to_s,
        "HTTP_CONTENT_ENCODING" => request.env["HTTP_CONTENT_ENCODING"].to_s, # git gzips big requests
        "GIT_PROTOCOL"        => request.env["HTTP_GIT_PROTOCOL"].to_s, # protocol version 2 negotiation
      }

      out, err, result = Open3.capture3(cgi_env, "git", "http-backend",
                                        stdin_data: request.body.read, binmode: true)
      halt 500, "git http-backend failed: #{err}" unless result.success?

      # Split the CGI output into headers and body at the first blank line.
      head, body = out.split(/\r?\n\r?\n/, 2)
      cgi_headers = head.lines.to_h { |line| line.chomp.split(": ", 2) }
      status (cgi_headers.delete("Status") || "200").to_i
      headers cgi_headers
      body.to_s
    end

    def find_repo!(owner, name)
      halt 404, "No such repository\n" unless valid_name?(owner) && valid_name?(name) && File.directory?(repo_path(owner, name))
    end
  end

  get "/" do
    @repos = all_repos
    erb :index
  end

  get "/new" do
    erb :new
  end

  post "/repos" do
    owner, name = params[:owner].to_s.strip, params[:name].to_s.strip
    halt 422, erb(:new, locals: { error: "Names may use letters, digits, '-', '_' and '.'" }) unless valid_name?(owner) && valid_name?(name)

    path = repo_path(owner, name)
    halt 409, erb(:new, locals: { error: "#{owner}/#{name} already exists" }) if File.exist?(path)

    # The whole "create repository" feature: make a bare repo and let git do the rest.
    FileUtils.mkdir_p(File.dirname(path))
    _out, err, status = Open3.capture3("git", "init", "--bare", "--quiet", "--initial-branch=main", path)
    halt 500, "git init failed: #{h err}" unless status.success?

    redirect "/#{owner}/#{name}"
  end

  # --- Smart HTTP: what `git clone/fetch/push http://host/owner/name.git` calls ---

  # Step 1 of every clone or push: "which branches do you have, and at which commits?"
  get %r{/([^/]+)/([^/]+)\.git/info/refs} do |owner, name|
    find_repo!(owner, name)
    service = params["service"]
    halt 403, "Only smart HTTP is supported\n" unless SERVICES.include?(service)

    user = require_owner!(owner) if service == "git-receive-pack"
    git_http_backend(owner, name, "info/refs", user: user)
  end

  # Step 2: the client says what it wants (clone) or sends what it has (push).
  post %r{/([^/]+)/([^/]+)\.git/(git-upload-pack|git-receive-pack)} do |owner, name, service|
    find_repo!(owner, name)
    user = require_owner!(owner) if service == "git-receive-pack"
    git_http_backend(owner, name, service, user: user)
  end

  get "/:owner/:name" do |owner, name|
    pass unless valid_name?(owner) && valid_name?(name)
    @owner, @name = owner, name
    @path = repo_path(owner, name)
    halt 404, "No such repository" unless File.directory?(@path)
    erb :repo
  end
end
