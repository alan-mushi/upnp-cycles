defmodule Shodan.ShimProducer do
  require Logger
  use GenStage

  @moduledoc ~S"""
  Empty producer to inject events (with some logging) from
  Shodan.DiscoveryPipeline.transform_and_push_messages/2 we have more control
  on what's going on this way.
  """

  def init(_state) do
    {:producer, []}
  end

  def handle_demand(demand, []) when demand > 0 do
    Logger.debug("State is empty!")
    {:noreply, [], []}
  end

  def handle_demand(demand, state) when demand > 0 do
    Logger.debug("Got demand of #{demand} events")

    {events, new_state} = Enum.split(state, demand)

    {:noreply, events, new_state}
  end
end
