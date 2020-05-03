defmodule Shodan.Application do
  require Logger

  use Application

  defp configure_file_logging() do
    [d, _] = DateTime.utc_now()
             |> DateTime.to_iso8601
             |> String.replace(":", "_")
             |> String.split(".")
    path = "logs/all_levels-#{d}.log"
    Logger.info("Logging to #{Path.expand(path)}")

    Logger.add_backend {LoggerFileBackend, :debug}
    Logger.configure_backend {LoggerFileBackend, :debug}, path: path, level: :debug
  end

  def start(_type, _args) do
    configure_file_logging()

    children = [
      {IPUtils, []},
      {Shodan.Repo, []},
      CommandServer,
      Shodan.APIMemo,
      {Shodan.APIService, Shodan.APIMemo},
      Shodan.OpenPortsPipeline,
      Shodan.ValidationPipeline,
      Shodan.SSDPDiscoveryPipeline,
    ]

    opts = [
      strategy: :one_for_one,
      name: Shodan.ApplicationSupervisor,
    ]

    Supervisor.start_link(children, opts)
  end
end
