import Config

config :shodan, api_endpoint: "https://api.shodan.io"
#config :shodan, api_endpoint: "http://127.0.0.1:5000"

#config :logger, :console, metadata: [:module, :function, :line], level: :debug
config :logger, :console, metadata: [:module, :function, :line], level: :info

config :shodan, Shodan.Repo,
  database: System.get_env("REPO_DATABASE", "shodan"),
  username: System.get_env("REPO_USERNAME", "postgres"),
  password: System.get_env("REPO_PASSWORD", "postgres"),
  hostname: System.get_env("REPO_HOSTNAME", "127.0.0.1")

config :shodan, ecto_repos: [Shodan.Repo]

config :postgrex, :json_library, Shodan.Repo.JSON

import_config System.get_env("SECRETS_FILE", "secrets.exs")
