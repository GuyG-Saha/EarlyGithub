require "sinatra/base"
require "fileutils"
require "open3"

# A tiny, early-GitHub-shaped app. Repositories are plain bare git repos on
# disk, laid out as repos/<owner>/<name>.git. There is no database: the
# filesystem *is* the source of truth, which is roughly how things started.
class EarlyGitHub < Sinatra::Base
  REPO_ROOT = File.expand_path(ENV.fetch("REPO_ROOT", "repos"), __dir__)

  # Owner and repo names become directory names, so keep them boring.
  # This also blocks path tricks like "../../etc".
  NAME = /\A[A-Za-z0-9][A-Za-z0-9_.-]{0,38}\z/

  set :views, File.join(__dir__, "views")

  helpers do
    def h(text) = Rack::Utils.escape_html(text.to_s)

    def valid_name?(name) = NAME.match?(name.to_s) && !name.end_with?(".git")

    def repo_path(owner, name) = File.join(REPO_ROOT, owner, "#{name}.git")

    # Every repo on disk, as [owner, name] pairs.
    def all_repos
      Dir.glob(File.join(REPO_ROOT, "*", "*.git")).sort.map do |path|
        [File.basename(File.dirname(path)), File.basename(path, ".git")]
      end
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

  get "/:owner/:name" do |owner, name|
    pass unless valid_name?(owner) && valid_name?(name)
    @owner, @name = owner, name
    @path = repo_path(owner, name)
    halt 404, "No such repository" unless File.directory?(@path)
    erb :repo
  end
end
