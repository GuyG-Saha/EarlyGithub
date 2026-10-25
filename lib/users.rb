require "yaml"
require "openssl"
require "securerandom"
require "base64"
require "rack/utils"

# User accounts, kept in a small YAML file: { "alice" => "pbkdf2$...", ... }.
# Passwords are never stored, only a salted PBKDF2 hash of them, so a leaked
# file doesn't hand out passwords. Uses Ruby's built-in OpenSSL, no extra gems.
module Users
  ITERATIONS = 100_000

  module_function

  def file = File.expand_path(ENV.fetch("USERS_FILE", "users.yml"), File.join(__dir__, ".."))

  def all = File.exist?(file) ? (YAML.safe_load_file(file) || {}) : {}

  def add(name, password)
    users = all
    users[name] = hash_password(password)
    File.write(file, users.to_yaml)
  end

  # True when the name exists and the password matches its stored hash.
  def authenticate(name, password)
    stored = all[name] or return false
    _scheme, iterations, salt, expected = stored.split("$")
    actual = pbkdf2(password, Base64.strict_decode64(salt), iterations.to_i)
    Rack::Utils.secure_compare(Base64.strict_encode64(actual), expected)
  end

  def hash_password(password)
    salt = SecureRandom.random_bytes(16)
    digest = pbkdf2(password, salt, ITERATIONS)
    ["pbkdf2", ITERATIONS, Base64.strict_encode64(salt), Base64.strict_encode64(digest)].join("$")
  end

  def pbkdf2(password, salt, iterations)
    OpenSSL::KDF.pbkdf2_hmac(password, salt: salt, iterations: iterations, length: 32, hash: "sha256")
  end
end
